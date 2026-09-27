import Foundation

/// Where results go (`output.policy`).
public enum OutputPolicy: String, Codable, CaseIterable, Sendable {
    /// Beside the input.
    case same
    /// In a folder beside the input (`output.subfolder`, default `magickHUD`).
    case subfolder
    /// In one fixed folder (`output.folder`).
    case folder
}

/// User settings (schema: Resources/settings.json), stored as JSON at `<base>/preferences.json`.
public struct MagickSettings: Codable, Equatable, Sendable {
    public var outputPolicy: OutputPolicy = .same
    public var outputSubfolder: String = "magickHUD"
    public var outputFolder: String = "~/Pictures/magickHUD"
    /// Appended to the input's name; `{preset}` is the preset's suffix (`photo_resized.png`).
    public var suffix: String = "_{preset}"
    /// The quality presets start with (1-100).
    public var defaultQuality: Int = 85
    /// Explicit path to `magick`; empty means search PATH and the Homebrew prefixes.
    public var magickPath: String = ""

    public init() {}

    enum CodingKeys: String, CodingKey {
        case outputPolicy = "output.policy"
        case outputSubfolder = "output.subfolder"
        case outputFolder = "output.folder"
        case suffix = "output.suffix"
        case defaultQuality = "quality.default"
        case magickPath = "magick.path"
    }

    /// Saved values are merged over the defaults key by key: a missing key, or one whose value no
    /// longer decodes, keeps its default and the other saved values are kept.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MagickSettings()
        outputPolicy = (try? c.decodeIfPresent(OutputPolicy.self, forKey: .outputPolicy)) ?? d.outputPolicy
        outputSubfolder = (try? c.decodeIfPresent(String.self, forKey: .outputSubfolder)) ?? d.outputSubfolder
        outputFolder = (try? c.decodeIfPresent(String.self, forKey: .outputFolder)) ?? d.outputFolder
        suffix = (try? c.decodeIfPresent(String.self, forKey: .suffix)) ?? d.suffix
        defaultQuality = (try? c.decodeIfPresent(Int.self, forKey: .defaultQuality)) ?? d.defaultQuality
        magickPath = (try? c.decodeIfPresent(String.self, forKey: .magickPath)) ?? d.magickPath
    }

    public static let keys = CodingKeys.allValues

    public var json: [String: Any] {
        ["output.policy": outputPolicy.rawValue, "output.subfolder": outputSubfolder,
         "output.folder": outputFolder, "output.suffix": suffix,
         "quality.default": defaultQuality, "magick.path": magickPath]
    }

    /// Field defaults the settings supply to presets.
    public var presetDefaults: [String: String] { ["quality": String(defaultQuality)] }

    public var naming: OutputNaming {
        OutputNaming(policy: outputPolicy, subfolder: outputSubfolder, folder: outputFolder, suffix: suffix)
    }

    public enum SettingsError: Error, CustomStringConvertible, Equatable {
        case invalid(String)
        public var description: String { if case .invalid(let s) = self { return s }; return "" }
    }

    /// Applies string values (from `settings set`), validating all before changing any.
    public func applying(_ values: [String: String]) throws -> MagickSettings {
        var copy = self
        for (key, value) in values {
            switch key {
            case "output.policy":
                guard let policy = OutputPolicy(rawValue: value) else {
                    throw SettingsError.invalid("output.policy must be same, subfolder or folder")
                }
                copy.outputPolicy = policy
            case "output.subfolder":
                let name = value.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else {
                    throw SettingsError.invalid("output.subfolder must be a folder name without /")
                }
                copy.outputSubfolder = name
            case "output.folder":
                guard !value.trimmingCharacters(in: .whitespaces).isEmpty else {
                    throw SettingsError.invalid("output.folder must be a path")
                }
                copy.outputFolder = value
            case "output.suffix":
                guard !value.contains("/") else { throw SettingsError.invalid("output.suffix must not contain /") }
                copy.suffix = value
            case "quality.default":
                guard let q = Int(value), (1...100).contains(q) else {
                    throw SettingsError.invalid("quality.default must be a whole number from 1 to 100")
                }
                copy.defaultQuality = q
            case "magick.path":
                copy.magickPath = value
            default:
                throw SettingsError.invalid("unknown setting \(key)")
            }
        }
        return copy
    }

    public static func load(from url: URL) -> MagickSettings {
        guard let data = try? Data(contentsOf: url) else { return MagickSettings() }
        return (try? JSONDecoder().decode(MagickSettings.self, from: data)) ?? MagickSettings()
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

extension MagickSettings.CodingKeys: CaseIterable {
    static var allValues: [String] { allCases.map(\.stringValue) }
}
