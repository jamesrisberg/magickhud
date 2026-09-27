import Foundation

/// Isolation switches for tests and parallel instances:
///
/// - `MAGICKHUD_HOME`: base directory (settings in `<home>/preferences.json`); default
///   `~/Library/Application Support/magickHUD`. An isolated instance also keeps its panel frames
///   apart from the real one's.
/// - `MAGICKHUD_SOCKET`: socket name under MacHUD's sockets directory; default `magickhud`.
/// - `MAGICKHUD_NO_HOTKEYS`: set to skip registering the global hotkey.
enum AppEnvironment {
    static let environment = ProcessInfo.processInfo.environment

    static var isolatedHome: String? {
        environment["MAGICKHUD_HOME"].flatMap { $0.isEmpty ? nil : $0 }
    }

    static var baseDirectory: URL {
        if let home = isolatedHome {
            return URL(fileURLWithPath: (home as NSString).expandingTildeInPath, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("magickHUD", isDirectory: true)
    }

    static var settingsURL: URL { baseDirectory.appendingPathComponent("preferences.json") }

    /// Where panel frames are remembered: the app's defaults, or a separate suite when
    /// `MAGICKHUD_HOME` isolates this instance (so a test run never moves the real panel).
    static let defaults: UserDefaults = isolatedHome == nil
        ? .standard
        : UserDefaults(suiteName: "xyz.machud.magickhud.isolated") ?? .standard

    static func socketName(default name: String) -> String {
        environment["MAGICKHUD_SOCKET"].flatMap { $0.isEmpty ? nil : $0 } ?? name
    }

    static var hotKeysEnabled: Bool { environment["MAGICKHUD_NO_HOTKEYS"] == nil }
}
