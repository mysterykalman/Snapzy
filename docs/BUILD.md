# Manual Build Guide

Build Snapzy from source on your local machine.

> If you only need first-time local setup and a basic debug run, start with [DEVELOPMENT.md](DEVELOPMENT.md).

## Prerequisites

- macOS 13.0+
- Xcode 15.0+
- Command Line Tools: `xcode-select --install`

## Quick Build (Xcode)

```bash
open Snapzy.xcodeproj
```

Press ⌘R to build and run.

## Regenerate App Icon Assets

After editing `Snapzy/SnapzyIcon.icon` in Icon Composer, regenerate the padded macOS asset catalog before building a release:

```bash
brew install imagemagick # one-time dependency if magick is missing
scripts/generate-app-icon-assets.sh
```

The script renders the `.icon` package with Icon Composer's bundled `ictool`, then centers the rendered artwork in an 832 × 832 px box on a 1024 × 1024 px transparent canvas. This preserves the Icon Composer artwork while keeping Finder/Dock margins consistent with other macOS apps.

If you only have a manually exported Icon Composer PNG, use:

```bash
scripts/generate-app-icon-assets.sh --source-png /path/to/IconComposerExport.png
```

For other projects, copy `scripts/generate-icon-composer-appiconset.sh` and run it directly:

```bash
./generate-icon-composer-appiconset.sh /path/to/MyIcon.icon
```

By default it writes `AppIcon.appiconset` next to the input `.icon` package. To target an existing asset catalog:

```bash
./generate-icon-composer-appiconset.sh /path/to/MyIcon.icon \
  --appiconset /path/to/Assets.xcassets/AppIcon.appiconset
```

## Command Line Build

### Development Build

```bash
xcodebuild -project Snapzy.xcodeproj -scheme Snapzy -configuration Debug build
```

Output: `~/Library/Developer/Xcode/DerivedData/Snapzy-*/Build/Products/Debug/Snapzy.app`

### Release Build (Unsigned)

```bash
xcodebuild -project Snapzy.xcodeproj \
  -scheme Snapzy \
  -configuration Release \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  build
```

### Release Archive (Signed)

Requires Apple Developer account.

```bash
# 1. Create archive
xcodebuild -project Snapzy.xcodeproj \
  -scheme Snapzy \
  -configuration Release \
  archive -archivePath Snapzy.xcarchive

# 2. Export app bundle
xcodebuild -exportArchive \
  -archivePath Snapzy.xcarchive \
  -exportPath ./exported_app \
  -exportOptionsPlist ExportOptions.plist
```

### Create DMG

After exporting, create distributable DMG:

```bash
# Using create-dmg (brew install create-dmg)
create-dmg \
  --volname "Snapzy" \
  --background "assets/dmg-background.png" \
  --window-size 660 400 \
  --icon-size 120 \
  --icon "Snapzy.app" 180 170 \
  --app-drop-link 480 170 \
  --no-internet-enable \
  "Snapzy.dmg" \
  "./exported_app/Snapzy.app"
```

## Build Locations

| Build Type | Location |
|------------|----------|
| Debug | `DerivedData/Snapzy-*/Build/Products/Debug/` |
| Release | `DerivedData/Snapzy-*/Build/Products/Release/` |
| Archive | `./Snapzy.xcarchive` |
| Export | `./exported_app/Snapzy.app` |

## Troubleshooting

### "archive not found" Error

You used `build` instead of `archive`. The `build` command outputs to DerivedData, not `.xcarchive`.

```bash
# Wrong
xcodebuild ... build
xcodebuild -exportArchive -archivePath Snapzy.xcarchive ...  # Fails!

# Correct
xcodebuild ... archive -archivePath Snapzy.xcarchive
xcodebuild -exportArchive -archivePath Snapzy.xcarchive ...  # Works!
```

### Code Signing Issues

For local testing without signing:

```bash
xcodebuild ... CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO build
```

### Clean Build

```bash
xcodebuild -project Snapzy.xcodeproj -scheme Snapzy clean
rm -rf ~/Library/Developer/Xcode/DerivedData/Snapzy-*
```

## Personal artifact and browser bridge (release-readiness checkpoint)

Dev Artifact Build packages `Capture-dev.zip` inside the workflow artifact.
Extract both archive layers, then move `Capture.app` to Applications. The inner
archive preserves the app bundle structure, symlinks and executable modes.
The build includes a universal native host and the unpacked Chrome extension.
No Xcode, Swift compiler, Homebrew or jq is required to install the bundled host.

1. In Chrome, open `chrome://extensions`, enable Developer mode, and load unpacked
   `/Applications/Capture.app/Contents/Resources/BrowserBridge/chromium`.
2. Copy the extension's 32-letter ID.
3. Run (replace `EXTENSION_ID` with that ID):

   ```sh
   bash /Applications/Capture.app/Contents/Resources/BrowserBridge/install-native-host.sh EXTENSION_ID /Applications/Capture.app
   ```

4. Enable Browser Bridge in the app's Preferences, then reload the extension.
5. Assign the accessibility/ecommerce audit commands at `chrome://extensions/shortcuts`.
   Open an ordinary HTTPS page, run an audit, and open Inspection Results in the app.

The installer copies the helper into the existing user Application Support
location and registers only the supplied extension ID. Re-run after updating
the app or changing the extension ID. Existing Snapzy bundle IDs, preferences,
socket paths and history locations are intentionally preserved for compatibility.

The artifact workflow checks the executable, universal host, compiled localization
tables, permission resources, extension script inventory, Mach-O dependencies and
code signature, including after an archive round trip. This does not establish
translation completeness or interactive correctness. Real Chrome and Mac capture,
permissions, editor, export and history smoke tests are still required.
