// Packages/BrowserBridgeKit/Sources/BrowserBridgeKit/BridgeConfiguration.swift
import Foundation

/// The single canonical source of truth for every path/name/version the
/// browser bridge's two independent processes — the Capture (Snapzy) app
/// and the Chrome-launched native-messaging host — must agree on without
/// either one importing the other's app-specific code.
///
/// Ported from Capso-Capture's `BrowserBridgeKit` (BSL 1.1, personal-use
/// permitted; see docs/REFERENCE_PROVENANCE.md), which had already
/// refactored this out of duplicated hand-kept copies in the original
/// Capture repo. Because the native host lives in a fully separate SwiftPM
/// package (`native-host/`) that cannot depend on the main app target, it
/// depends on this package directly via a relative path instead — so there
/// is exactly one definition of each value, imported by both sides.
public enum BridgeConfiguration {
    /// Bumped whenever the wire-format shape of `BridgeMessage`/
    /// `BridgeResponse` changes in a way older/newer peers couldn't parse
    /// safely. A message whose `version` doesn't match is rejected by the
    /// receiver rather than guessed at.
    public static let protocolVersion = 1

    /// Folder name under `~/Library/Application Support/` — matches the
    /// app's existing convention (see `DatabaseManager.databaseDirectory`)
    /// of a bare `Snapzy` folder rather than a reverse-DNS bundle ID.
    public static let applicationSupportFolderName = "Snapzy"

    /// The Chrome Native Messaging host name this extension connects to via
    /// `chrome.runtime.connectNative(...)`. Must exactly match the `name`
    /// field of the installed native-messaging-host manifest JSON.
    public static let nativeMessagingHostName = "com.trongduong.snapzy.browserbridge"

    /// The release bundle identifier of the Capture (Snapzy) app itself —
    /// used by the install script to sanity-check it is installing against
    /// a real, matching build.
    public static let appBundleIdentifier = "com.trongduong.snapzy"

    /// `~/Library/Application Support/Snapzy/IPC/socket` — where the app's
    /// `BridgeSocketServer` listens and where the native host's
    /// `BridgeSocketClient` connects. Both sides call this exact same
    /// computed property.
    public static var socketURL: URL {
        applicationSupportDirectory
            .appendingPathComponent("IPC", isDirectory: true)
            .appendingPathComponent("socket")
    }

    /// Where the native-messaging host binary is installed
    /// (`.../Snapzy/NativeMessaging/snapzy-native-host`). Read by the
    /// install script and printed by the native host binary's own
    /// `--print-config` diagnostic so the two never drift apart.
    public static var nativeMessagingInstallDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("NativeMessaging", isDirectory: true)
    }

    public static var nativeMessagingHostBinaryName: String { "snapzy-native-host" }

    /// The Chrome Native Messaging host manifest Chrome itself reads to
    /// know which binary to launch and which extension origins may call
    /// `connectNative` with this host name.
    public static var chromeNativeMessagingManifestName: String {
        "\(nativeMessagingHostName).json"
    }

    public static var chromeNativeMessagingHostsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts", isDirectory: true)
    }

    private static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(applicationSupportFolderName, isDirectory: true)
    }
}
