import Foundation

/// `{input} {output} {dir} {name} {ext} {preset}` in output templates, suffixes and custom args.
///
/// - `{input}`: the input path; `{dir}`: its folder; `{name}`: its file name without extension;
///   `{ext}`: the output extension (no dot); `{output}`: the output path; `{preset}`: the preset's
///   suffix word (`resized`).
public struct Tokens: Equatable, Sendable {
    public var input: String
    public var output: String
    public var ext: String
    public var preset: String

    public init(input: String, output: String = "", ext: String = "", preset: String = "") {
        self.input = input
        self.output = output
        self.ext = ext
        self.preset = preset
    }

    public var dir: String { (input as NSString).deletingLastPathComponent }
    public var name: String { ((input as NSString).lastPathComponent as NSString).deletingPathExtension }

    public func expand(_ template: String) -> String {
        var s = template
        for (token, value) in [("{input}", input), ("{output}", output), ("{dir}", dir),
                               ("{name}", name), ("{ext}", ext), ("{preset}", preset)] {
            s = s.replacingOccurrences(of: token, with: value)
        }
        return s
    }
}

/// Where a result is written. Never an existing file, never the input, never a path already
/// claimed by another output of the same run.
public struct OutputNaming: Equatable, Sendable {
    public var policy: OutputPolicy
    public var subfolder: String
    public var folder: String
    /// Appended to the name; tokens allowed (default `_{preset}`).
    public var suffix: String

    public init(policy: OutputPolicy = .same, subfolder: String = "magickHUD",
                folder: String = "~/Pictures/magickHUD", suffix: String = "_{preset}") {
        self.policy = policy
        self.subfolder = subfolder
        self.folder = folder
        self.suffix = suffix
    }

    /// The folder results for `input` go to.
    public func directory(for input: String) -> String {
        let dir = (input as NSString).deletingLastPathComponent
        switch policy {
        case .same: return dir
        case .subfolder: return (dir as NSString).appendingPathComponent(subfolder)
        case .folder: return (folder as NSString).expandingTildeInPath
        }
    }

    /// The path before collision handling. `template` (an `output=` override, tokens allowed)
    /// wins over the policy; a template without an extension gets `ext`.
    public func proposed(input: String, ext: String, preset: String, baseName: String? = nil,
                         template: String? = nil) -> String {
        let tokens = Tokens(input: input, ext: ext, preset: preset)
        if let template, !template.trimmingCharacters(in: .whitespaces).isEmpty {
            var path = (tokens.expand(template) as NSString).expandingTildeInPath
            if !path.hasPrefix("/") { path = (tokens.dir as NSString).appendingPathComponent(path) }
            if (path as NSString).pathExtension.isEmpty, !ext.isEmpty { path += ".\(ext)" }
            return path
        }
        let name = baseName ?? (tokens.name + tokens.expand(suffix))
        let file = ext.isEmpty ? name : "\(name).\(ext)"
        return (directory(for: input) as NSString).appendingPathComponent(file)
    }

    /// `path`, or `name-2.ext`, `name-3.ext`, ... : the first that does not exist, is not in
    /// `taken` and is not `avoiding` (the input).
    public static func unique(_ path: String, taken: Set<String> = [], avoiding: Set<String> = [],
                              exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String {
        func free(_ p: String) -> Bool {
            let key = (p as NSString).standardizingPath
            return !exists(p) && !taken.contains(key) && !avoiding.contains(key)
        }
        if free(path) { return path }
        let ext = (path as NSString).pathExtension
        let stem = (path as NSString).deletingPathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem)-\(n)" : "\(stem)-\(n).\(ext)"
            if free(candidate) { return candidate }
            n += 1
        }
    }
}
