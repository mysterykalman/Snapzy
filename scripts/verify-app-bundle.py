#!/usr/bin/env python3
"""Inspect a packaged personal-testing app without launching it or changing defaults."""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys


def require(condition, message):
    if not condition:
        raise SystemExit('Bundle verification failed: ' + message)


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def verify(app):
    contents = app / 'Contents'
    info = plistlib.loads((contents / 'Info.plist').read_bytes())
    executable = contents / 'MacOS' / info['CFBundleExecutable']
    require(os.access(executable, os.X_OK), f'executable missing or not executable: {executable}')
    require(info['CFBundleIdentifier'] == 'com.trongduong.snapzy', 'unexpected release bundle ID')
    resources = contents / 'Resources'
    require((resources / 'Assets.car').is_file(), 'compiled asset catalog missing')
    require((resources / 'whats_new.json').is_file(), 'What\'s New configuration missing')
    host = contents / 'Helpers' / 'snapzy-native-host'
    require(os.access(host, os.X_OK), 'native host missing or not executable')
    config = json.loads(output(str(host), '--print-config'))
    require(config['appBundleIdentifier'] == info['CFBundleIdentifier'], 'native host/app ID mismatch')
    for binary in (executable, host):
        arches = output('lipo', '-archs', str(binary)).split()
        require({'arm64', 'x86_64'} <= set(arches), f'universal architectures missing: {binary}')
    extension = resources / 'BrowserBridge' / 'chromium'
    manifest = json.loads((extension / 'manifest.json').read_text())
    require((resources / 'BrowserBridge' / 'install-native-host.sh').is_file(), 'installer missing')
    scripts = [manifest['background']['service_worker']]
    for entry in manifest['content_scripts']:
        scripts.extend(entry['js'])
    for script in scripts:
        require((extension / script).is_file(), f'extension script missing: {script}')
    require(config['nativeMessagingHostName'] in (extension / scripts[0]).read_text(), 'extension/host name mismatch')
    # Check resources against the actual source catalogs, preserving all existing languages.
    # Translation completeness is a separate source-level check, not inferred from lproj presence.
    root = Path(__file__).resolve().parents[1]
    for catalog in (root / 'Snapzy/Resources/Localization').rglob('*.xcstrings'):
        data = json.loads(catalog.read_text())
        locales = {locale for entry in data['strings'].values() for locale in entry.get('localizations', {})}
        for locale in locales:
            folder = resources / f'{locale}.lproj'
            require(any((folder / (catalog.stem + suffix)).is_file() for suffix in ('.strings', '.stringsdict')),
                    f'compiled table missing: {locale}/{catalog.stem}')
    for source in (root / 'Snapzy/Resources').glob('*.lproj/InfoPlist.strings'):
        require((resources / source.parent.name / source.name).is_file(), f'permission strings missing: {source.parent.name}')
    # Inspect Mach-O load commands, not arbitrary strings/debug information.
    machos = []
    for file in contents.rglob('*'):
        if file.is_file() and not file.is_symlink() and 'Mach-O' in output('file', '-b', str(file)):
            machos.append(file)
    for binary in machos:
        deps = output('otool', '-L', str(binary)).splitlines()[1:]
        for line in deps:
            dependency = line.strip().split(' (', 1)[0]
            if not dependency or dependency.endswith(':'):
                continue
            require(not dependency.startswith(('/Users/', '/Volumes/', '/private/', '/tmp/', '/opt/', '/usr/local/')),
                    f'developer-machine dependency: {binary}: {dependency}')
            if dependency.startswith('/'):
                require(dependency.startswith(('/System/Library/', '/usr/lib/')), f'non-system absolute dependency: {dependency}')
            elif dependency.startswith('@loader_path/'):
                require((binary.parent / dependency.removeprefix('@loader_path/')).exists(), f'missing loader dependency: {dependency}')
            elif dependency.startswith('@rpath/'):
                relative = dependency.removeprefix('@rpath/')
                # App frameworks plus nested framework helpers (e.g. Sparkle's updater).
                require(any((folder / relative).exists() for folder in [contents / 'Frameworks', *contents.rglob('Frameworks')]),
                        f'missing bundled framework: {binary}: {dependency}')
    print(f'Bundle inspection passed: {app} ({len(machos)} Mach-O files)')


if __name__ == '__main__':
    require(len(sys.argv) == 2, 'usage: verify-app-bundle.py Capture.app')
    verify(Path(sys.argv[1]).resolve())
