import Foundation

/// One choice in a `select` field: what the user sees, what the command gets.
public struct PresetOption: Codable, Equatable, Sendable {
    public var value: String
    public var label: String

    public init(_ value: String, _ label: String? = nil) {
        self.value = value
        self.label = label ?? value
    }
}

/// A control in a preset's form. Values always travel as strings (form, socket, CLI).
public struct PresetField: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case text, number, select, toggle }

    public var id: String
    public var label: String
    public var kind: Kind
    public var options: [PresetOption]
    /// The initial value. `quality` fields take the `quality.default` setting instead.
    public var defaultValue: String
    public var placeholder: String?
    public var required: Bool

    public init(_ id: String, _ label: String, kind: Kind = .text, options: [PresetOption] = [],
                default defaultValue: String = "", placeholder: String? = nil, required: Bool = false) {
        self.id = id
        self.label = label
        self.kind = kind
        self.options = options
        self.defaultValue = defaultValue
        self.placeholder = placeholder
        self.required = required
    }

    public static func toggle(_ id: String, _ label: String, on: Bool) -> PresetField {
        PresetField(id, label, kind: .toggle, default: on ? "1" : "0")
    }

    public static func bool(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["1", "true", "yes", "on"].contains(value.lowercased())
    }
}

/// A named ImageMagick operation: the form it shows and (in `CommandBuilder`) the argv it makes.
public struct Preset: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    /// SF Symbol name.
    public var symbol: String
    public var summary: String
    /// Extra words the search matches.
    public var keywords: [String]
    public var fields: [PresetField]
    /// `montage`: every input goes into one output. Other presets make one output per input.
    public var combinesInputs: Bool
    /// What `{preset}` expands to in the output suffix (`photo_resized.png`).
    public var suffix: String

    public init(id: String, title: String, symbol: String, summary: String, keywords: [String] = [],
                fields: [PresetField] = [], combinesInputs: Bool = false, suffix: String? = nil) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.summary = summary
        self.keywords = keywords
        self.fields = fields
        self.combinesInputs = combinesInputs
        self.suffix = suffix ?? id
    }

    public func field(_ id: String) -> PresetField? { fields.first { $0.id == id } }

    /// Every field's value: `values` over `defaults` (settings, e.g. quality) over the field's own.
    /// Keys that are not fields of this preset are dropped. Values are trimmed.
    public func resolve(_ values: [String: String], defaults: [String: String] = [:]) -> [String: String] {
        var out: [String: String] = [:]
        for field in fields {
            let raw = values[field.id] ?? defaults[field.id] ?? field.defaultValue
            out[field.id] = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return out
    }

    /// Case-insensitive match on title, id, summary and keywords; every word must match.
    public func matches(_ query: String) -> Bool {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let haystack = ([id, title, summary] + keywords).joined(separator: " ").lowercased()
        return words.allSatisfy { haystack.contains($0) }
    }
}
