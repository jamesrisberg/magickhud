import Foundation

public enum BuildError: Error, Equatable, CustomStringConvertible {
    case noInput
    case invalid(String)

    public var description: String {
        switch self {
        case .noInput: return "drop an image first"
        case .invalid(let why): return why
        }
    }
}

/// One planned invocation: the argv handed to `Process` (never a shell) and what it reads and writes.
public struct MagickCommand: Equatable, Sendable, Codable {
    public var argv: [String]
    public var inputs: [String]
    public var output: String

    public init(argv: [String], inputs: [String], output: String) {
        self.argv = argv
        self.inputs = inputs
        self.output = output
    }

    /// Copy/paste-able shell rendering, for display only.
    public var display: String { argv.map(Self.quoted).joined(separator: " ") }

    public static func quoted(_ arg: String) -> String {
        let safe = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-./:=+%,@")
        if !arg.isEmpty && arg.unicodeScalars.allSatisfy({ safe.contains($0) }) { return arg }
        return "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Turns a preset plus field values into argv arrays. Pure: the only outside fact it consults
/// is `exists` (for never-overwrite naming), which tests replace.
public enum CommandBuilder {
    /// Plans a run: one command per input, or one for all inputs when the preset combines them
    /// (montage). Output names never collide with existing files, the inputs, or each other.
    /// `outputTemplate` (tokens allowed) overrides the naming policy.
    public static func plan(_ preset: Preset, values: [String: String], inputs: [String],
                            naming: OutputNaming = OutputNaming(), defaults: [String: String] = [:],
                            binary: String = "magick", outputTemplate: String? = nil,
                            exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) throws -> [MagickCommand] {
        let inputs = inputs.map(expand).filter { !$0.isEmpty }
        guard let first = inputs.first else { throw BuildError.noInput }
        let v = preset.resolve(values, defaults: defaults)
        try validate(preset, v)
        let avoiding = Set(inputs.map { ($0 as NSString).standardizingPath })
        var taken = Set<String>()

        func claim(_ proposed: String) -> String {
            let path = OutputNaming.unique(proposed, taken: taken, avoiding: avoiding, exists: exists)
            taken.insert((path as NSString).standardizingPath)
            return path
        }

        if preset.combinesInputs {
            let ext = outputExtension(preset, v, input: first)
            let output = claim(naming.proposed(input: first, ext: ext, preset: preset.suffix,
                                               baseName: preset.suffix, template: outputTemplate))
            return [MagickCommand(argv: try argv(preset, v, inputs: inputs, output: output, binary: binary),
                                  inputs: inputs, output: output)]
        }
        return try inputs.map { input in
            let ext = outputExtension(preset, v, input: input)
            let output = claim(naming.proposed(input: input, ext: ext, preset: preset.suffix, template: outputTemplate))
            return MagickCommand(argv: try argv(preset, v, inputs: [input], output: output, binary: binary),
                                 inputs: [input], output: output)
        }
    }

    private static func expand(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : (trimmed as NSString).expandingTildeInPath
    }

    static func validate(_ preset: Preset, _ v: [String: String]) throws {
        for field in preset.fields {
            let value = v[field.id] ?? ""
            if field.required, value.isEmpty { throw BuildError.invalid("\(field.label) is required") }
            if field.kind == .number, !value.isEmpty, Double(value) == nil {
                throw BuildError.invalid("\(field.label) must be a number")
            }
            if field.kind == .select, !value.isEmpty, !field.options.contains(where: { $0.value == value }) {
                throw BuildError.invalid("\(field.label) must be one of \(field.options.map(\.value).joined(separator: ", "))")
            }
        }
        if let q = v["quality"], let n = Int(q), !(1...100).contains(n) {
            throw BuildError.invalid("Quality must be from 1 to 100")
        }
        if preset.id == "adjust", ["brightness", "contrast", "saturation"].allSatisfy({ (v[$0] ?? "").isEmpty }) {
            throw BuildError.invalid("set brightness, contrast or saturation")
        }
        if preset.id == "crop", v["aspect"] == "custom", (v["geometry"] ?? "").isEmpty {
            throw BuildError.invalid("Region is required for a custom crop")
        }
    }

    /// The extension of the result (no dot).
    public static func outputExtension(_ preset: Preset, _ v: [String: String], input: String) -> String {
        let inputExt = (input as NSString).pathExtension
        let keep = inputExt.isEmpty ? "png" : inputExt
        switch preset.id {
        case "convert", "montage": return v["format"] ?? keep
        case "web": return v["format"] == "keep" ? keep : (v["format"] ?? "jpg")
        case "custom":
            let ext = (v["ext"] ?? "").trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            return ext.isEmpty ? keep : ext
        default: return keep
        }
    }

    static let lossy: Set<String> = ["jpg", "jpeg", "webp", "heic", "avif", "jxl"]

    /// The argv for one command. `inputs` has one element except for presets that combine inputs.
    public static func argv(_ preset: Preset, _ v: [String: String], inputs: [String], output: String,
                            binary: String = "magick") throws -> [String] {
        let input = inputs.first ?? ""
        func val(_ key: String) -> String { v[key] ?? "" }
        var ops: [String] = []

        switch preset.id {
        case "resize":
            ops = ["-resize", resizeGeometry(v)]
        case "convert":
            if lossy.contains(val("format")) { ops = ["-quality", val("quality")] }
        case "compress":
            if PresetField.bool(v["strip"]) { ops.append("-strip") }
            ops += ["-quality", val("quality")]
        case "web":
            let max = val("max").isEmpty ? "1920" : val("max")
            ops = ["-auto-orient", "-resize", "\(max)x\(max)>", "-strip"]
            let ext = outputExtension(preset, v, input: input).lowercased()
            if lossy.contains(ext) { ops += ["-quality", val("quality")] }
        case "thumbnail":
            let s = val("size").isEmpty ? "256" : val("size")
            ops = ["-auto-orient", "-thumbnail", "\(s)x\(s)^", "-gravity", "center", "-extent", "\(s)x\(s)"]
        case "crop":
            if val("aspect") == "custom" {
                ops = ["-crop", val("geometry"), "+repage"]
            } else {
                ops = ["-gravity", val("gravity").isEmpty ? "center" : val("gravity"), "-crop", val("aspect"), "+repage"]
            }
        case "trim":
            ops = ["-fuzz", "\(val("fuzz").isEmpty ? "0" : val("fuzz"))%", "-trim", "+repage"]
        case "rotate":
            switch val("rotation") {
            case "auto": ops = ["-auto-orient"]
            case "flip": ops = ["-flip"]
            case "flop": ops = ["-flop"]
            case let angle: ops = ["-rotate", angle]
            }
        case "strip":
            ops = ["-strip"]
        case "grayscale":
            ops = ["-colorspace", "Gray"]
        case "adjust":
            let brightness = val("brightness").isEmpty ? "0" : val("brightness")
            let contrast = val("contrast").isEmpty ? "0" : val("contrast")
            if brightness != "0" || contrast != "0" { ops += ["-brightness-contrast", "\(brightness)x\(contrast)"] }
            if !val("saturation").isEmpty { ops += ["-modulate", "100,\(val("saturation")),100"] }
        case "blur":
            ops = ["-blur", sigma(val("sigma"), fallback: "2")]
        case "sharpen":
            ops = ["-sharpen", sigma(val("sigma"), fallback: "1")]
        case "border":
            ops = ["-bordercolor", val("color").isEmpty ? "white" : val("color"),
                   "-border", val("width").isEmpty ? "10" : val("width")]
        case "watermark":
            let margin = val("margin").isEmpty ? "16" : val("margin")
            ops = ["-gravity", val("gravity"), "-fill", val("color"), "-pointsize", val("pointsize"),
                   "-annotate", "+\(margin)+\(margin)", val("text")]
        case "montage":
            let columns = val("columns").isEmpty ? "4" : val("columns")
            let tile = val("tile").isEmpty ? "256" : val("tile")
            let spacing = val("spacing").isEmpty ? "4" : val("spacing")
            var argv = [binary, "montage"]
            if PresetField.bool(v["labels"]) { argv += ["-label", "%f", "-fill", "white"] }
            argv += inputs
            argv += ["-tile", "\(columns)x", "-geometry", "\(tile)x\(tile)+\(spacing)+\(spacing)",
                     "-background", val("background").isEmpty ? "#222222" : val("background"), output]
            return argv
        case "custom":
            let tokens = Tokens(input: input, output: output,
                                ext: (output as NSString).pathExtension, preset: preset.suffix)
            let words = try split(val("args")).map(tokens.expand)
            let original = try split(val("args"))
            var argv = [binary]
            if !original.contains(where: { $0.contains("{input}") }) { argv.append(input) }
            argv += words
            if !original.contains(where: { $0.contains("{output}") }) { argv.append(output) }
            return argv
        default:
            throw BuildError.invalid("unknown preset \(preset.id)")
        }
        return [binary, input] + ops + [output]
    }

    /// `-resize` geometry: width/height (either may be empty) with the fit mode, else `size`.
    public static func resizeGeometry(_ v: [String: String]) -> String {
        let w = v["width"] ?? "", h = v["height"] ?? ""
        guard !w.isEmpty || !h.isEmpty else { return (v["size"] ?? "").isEmpty ? "50%" : v["size"]! }
        let flag: String
        switch v["fit"] ?? "fit" {
        case "fill": flag = "^"
        case "exact": flag = (w.isEmpty || h.isEmpty) ? "" : "!"
        case "shrink": flag = ">"
        default: flag = ""
        }
        return "\(w)x\(h)\(flag)"
    }

    /// `2` -> `0x2`; `0x2` stays.
    static func sigma(_ raw: String, fallback: String) -> String {
        let s = raw.isEmpty ? fallback : raw
        return s.contains("x") ? s : "0x\(s)"
    }

    /// Splits custom arguments into words: whitespace separates, single or double quotes group,
    /// backslash escapes. No shell is involved; this only decides word boundaries.
    public static func split(_ line: String) throws -> [String] {
        var words: [String] = []
        var current = ""
        var inWord = false
        var quote: Character?
        var escaping = false
        for ch in line {
            if escaping { current.append(ch); escaping = false; inWord = true; continue }
            if ch == "\\" && quote != "'" { escaping = true; continue }
            if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
                continue
            }
            if ch == "'" || ch == "\"" { quote = ch; inWord = true; continue }
            if ch.isWhitespace {
                if inWord { words.append(current); current = ""; inWord = false }
                continue
            }
            current.append(ch)
            inWord = true
        }
        if quote != nil { throw BuildError.invalid("unbalanced quote in arguments") }
        if escaping { current.append("\\") }
        if inWord { words.append(current) }
        return words
    }
}
