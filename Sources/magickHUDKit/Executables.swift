import Foundation

/// Finds executables the way a login shell would. An app launched from Finder inherits a bare
/// PATH, so the Homebrew prefixes are searched explicitly.
public enum Executables {
    public static let searchPaths: [String] = {
        let env = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        var seen = Set<String>()
        return (env + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"])
            .filter { seen.insert($0).inserted }
    }()

    /// Absolute path for `name`, or nil when it is not installed.
    public static func path(_ name: String) -> String? {
        let name = (name as NSString).expandingTildeInPath
        if name.hasPrefix("/") { return FileManager.default.isExecutableFile(atPath: name) ? name : nil }
        for dir in searchPaths {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// `magick`, honouring an explicit path from settings.
    public static func magick(override: String = "") -> String? {
        override.trimmingCharacters(in: .whitespaces).isEmpty ? path("magick") : path(override)
    }

    /// The environment for child processes: PATH includes the Homebrew prefixes (magick's
    /// delegates, e.g. gs for PDF, are found that way).
    public static var childEnvironment: [String: String] {
        ProcessInfo.processInfo.environment.merging(["PATH": searchPaths.joined(separator: ":")]) { _, new in new }
    }
}
