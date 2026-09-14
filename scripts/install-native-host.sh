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

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <chrome-extension-id>" >&2
    exit 1
fi

EXTENSION_ID="$1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE_HOST_DIR="$REPO_ROOT/native-host"

if ! command -v jq >/dev/null 2>&1; then
    echo "error: this script requires 'jq' (brew install jq)" >&2
    exit 1
fi

echo "==> Building snapzy-native-host (release)"
swift build --package-path "$NATIVE_HOST_DIR" -c release --product snapzy-native-host

BUILT_BINARY="$NATIVE_HOST_DIR/.build/release/snapzy-native-host"
if [ ! -x "$BUILT_BINARY" ]; then
    echo "error: build did not produce $BUILT_BINARY" >&2
    exit 1
fi

echo "==> Reading canonical configuration from the built binary"
CONFIG_JSON="$("$BUILT_BINARY" --print-config)"

INSTALLED_APP_SUPPORT_DIR="$(echo "$CONFIG_JSON" | jq -r '.nativeMessagingInstallDirectory')"
BINARY_NAME="$(echo "$CONFIG_JSON" | jq -r '.nativeMessagingHostBinaryName')"
INSTALLED_BINARY_PATH="$INSTALLED_APP_SUPPORT_DIR/$BINARY_NAME"
CHROME_HOSTS_DIR="$(echo "$CONFIG_JSON" | jq -r '.chromeNativeMessagingHostsDirectory')"
MANIFEST_NAME="$(echo "$CONFIG_JSON" | jq -r '.nativeMessagingManifestName')"
MANIFEST_PATH="$CHROME_HOSTS_DIR/$MANIFEST_NAME"
HOST_NAME="$(echo "$CONFIG_JSON" | jq -r '.nativeMessagingHostName')"

echo "==> Installing binary to $INSTALLED_BINARY_PATH"
mkdir -p "$INSTALLED_APP_SUPPORT_DIR"
cp "$BUILT_BINARY" "$INSTALLED_BINARY_PATH"
chmod 755 "$INSTALLED_BINARY_PATH"

echo "==> Writing Chrome Native Messaging host manifest to $MANIFEST_PATH"
mkdir -p "$CHROME_HOSTS_DIR"
cat > "$MANIFEST_PATH" <<EOF
{
  "name": "$HOST_NAME",
  "description": "Capture browser bridge",
  "path": "$INSTALLED_BINARY_PATH",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://$EXTENSION_ID/"
  ]
}
EOF

echo "==> Done. Reload the extension in chrome://extensions -- it can now connectNative(\"$HOST_NAME\")."
