#!/bin/bash
# Installs snapzy-native-host as a Chrome Native Messaging host.
#
# Usage: scripts/install-native-host.sh <chrome-extension-id>
#
# The extension ID must be supplied explicitly -- load extensions/chromium/
# unpacked in chrome://extensions first, copy the ID Chrome shows there, and
# pass it here.
#
# Every path/name this script needs (socket path, install directory,
# native-messaging host name/manifest filename, Chrome's NativeMessagingHosts
# directory) is read from the built binary's own `--print-config`, not
# hardcoded here -- BrowserBridgeKit's `BridgeConfiguration` is the one
# canonical source, and this script only ever asks the binary for it.
#
# Ported from Capso-Capture's scripts/install-native-host.sh
# (see docs/REFERENCE_PROVENANCE.md).

set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "Usage: $0 <chrome-extension-id> [Capture.app]" >&2
    exit 1
fi

EXTENSION_ID="$1"
if [[ ! "$EXTENSION_ID" =~ ^[a-p]{32}$ ]]; then
    echo "error: extension ID must be the 32-letter ID shown by Chrome" >&2
    exit 1
fi

if [ "$#" -eq 2 ]; then
    BUILT_BINARY="$2/Contents/Helpers/snapzy-native-host"
else
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    NATIVE_HOST_DIR="$REPO_ROOT/native-host"
    echo "==> Building snapzy-native-host (release)"
    swift build --package-path "$NATIVE_HOST_DIR" -c release --product snapzy-native-host
    BUILT_BINARY="$NATIVE_HOST_DIR/.build/release/snapzy-native-host"
fi
if [ ! -x "$BUILT_BINARY" ]; then
    echo "error: native host is missing or not executable: $BUILT_BINARY" >&2
    exit 1
fi

echo "==> Reading canonical configuration from the built binary"
CONFIG_JSON="$("$BUILT_BINARY" --print-config)"

INSTALLED_APP_SUPPORT_DIR="$(printf "%s" "$CONFIG_JSON" | /usr/bin/plutil -extract nativeMessagingInstallDirectory raw -o - -)"
BINARY_NAME="$(printf "%s" "$CONFIG_JSON" | /usr/bin/plutil -extract nativeMessagingHostBinaryName raw -o - -)"
INSTALLED_BINARY_PATH="$INSTALLED_APP_SUPPORT_DIR/$BINARY_NAME"
CHROME_HOSTS_DIR="$(printf "%s" "$CONFIG_JSON" | /usr/bin/plutil -extract chromeNativeMessagingHostsDirectory raw -o - -)"
MANIFEST_NAME="$(printf "%s" "$CONFIG_JSON" | /usr/bin/plutil -extract nativeMessagingManifestName raw -o - -)"
MANIFEST_PATH="$CHROME_HOSTS_DIR/$MANIFEST_NAME"
HOST_NAME="$(printf "%s" "$CONFIG_JSON" | /usr/bin/plutil -extract nativeMessagingHostName raw -o - -)"

echo "==> Installing binary to $INSTALLED_BINARY_PATH"
mkdir -p "$INSTALLED_APP_SUPPORT_DIR"
cp "$BUILT_BINARY" "$INSTALLED_BINARY_PATH"
chmod 755 "$INSTALLED_BINARY_PATH"

echo "==> Writing Chrome Native Messaging host manifest to $MANIFEST_PATH"
mkdir -p "$CHROME_HOSTS_DIR"
# Let plutil escape paths correctly, including quotes in the user's home path.
MANIFEST_TEMP="$(mktemp "$CHROME_HOSTS_DIR/.capture-host.XXXXXX")"
trap 'rm -f "$MANIFEST_TEMP"' EXIT
/usr/bin/plutil -create xml1 "$MANIFEST_TEMP"
/usr/bin/plutil -insert name -string "$HOST_NAME" "$MANIFEST_TEMP"
/usr/bin/plutil -insert description -string "Capture browser bridge" "$MANIFEST_TEMP"
/usr/bin/plutil -insert path -string "$INSTALLED_BINARY_PATH" "$MANIFEST_TEMP"
/usr/bin/plutil -insert type -string stdio "$MANIFEST_TEMP"
/usr/bin/plutil -insert allowed_origins -json "[\"chrome-extension://$EXTENSION_ID/\"]" "$MANIFEST_TEMP"
/usr/bin/plutil -convert json "$MANIFEST_TEMP"
mv "$MANIFEST_TEMP" "$MANIFEST_PATH"

echo "==> Done. Reload the extension in chrome://extensions -- it can now connectNative(\"$HOST_NAME\")."
