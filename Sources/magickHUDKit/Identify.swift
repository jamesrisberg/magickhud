import Foundation
import ImageIO

/// What the drop zone shows under a thumbnail.
public struct ImageInfo: Equatable, Sendable, Codable {
    public var format: String
    public var width: Int
    public var height: Int
    /// Frames or pages (GIF, PDF, TIFF).
    public var frames: Int
    public var bytes: Int64

    public init(format: String, width: Int, height: Int, frames: Int = 1, bytes: Int64 = 0) {
        self.format = format
        self.width = width
        self.height = height
        self.frames = frames
        self.bytes = bytes
    }

    public var dimensions: String { "\(width)×\(height)" }
    public var size: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    /// "PNG 64×64 · 1 KB"
    public var summary: String {
        "\(format) \(dimensions)\(frames > 1 ? " ×\(frames)" : "") · \(size)"
    }

    public var json: [String: Any] {
        ["format": format, "width": width, "height": height, "frames": frames, "bytes": bytes]
    }
}

/// Dimensions and format via `magick identify -ping -format`, with ImageIO as the fallback when
/// magick is missing or cannot read the file.
public enum Identify {
    /// One line per frame: `FORMAT|WIDTH|HEIGHT`.
    public static let format = "%m|%w|%h\\n"

    public static func argv(_ path: String, binary: String = "magick") -> [String] {
        [binary, "identify", "-ping", "-format", format, path]
    }

    /// Parses identify's output: the first frame's format and size, the number of frames.
    public static func parse(_ output: String, bytes: Int64 = 0) -> ImageInfo? {
        let lines = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = lines.first else { return nil }
        let parts = first.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3, let w = Int(parts[1]), let h = Int(parts[2]), !parts[0].isEmpty else { return nil }
        let frames = lines.filter { $0.split(separator: "|").count >= 3 }.count
        return ImageInfo(format: parts[0], width: w, height: h, frames: max(frames, 1), bytes: bytes)
    }

    public static func fileSize(_ path: String) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Blocking; call off the main thread. `binary` nil skips magick and uses ImageIO.
    public static func info(_ path: String, binary: String? = Executables.magick()) -> ImageInfo? {
        let bytes = fileSize(path)
        if let binary, let output = run(argv(path, binary: binary)), let info = parse(output, bytes: bytes) {
            return info
        }
        return imageIO(path, bytes: bytes)
    }

    static func imageIO(_ path: String, bytes: Int64) -> ImageInfo? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let type = (CGImageSourceGetType(source) as String?) ?? ""
        let format = type.split(separator: ".").last.map { $0.uppercased() } ?? "IMAGE"
        return ImageInfo(format: format == "JPEG" ? "JPEG" : format, width: w, height: h,
                         frames: max(CGImageSourceGetCount(source), 1), bytes: bytes)
    }

    /// Runs argv and returns stdout, or nil on failure.
    static func run(_ argv: [String]) -> String? {
        guard let first = argv.first, let exe = Executables.path(first) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = Array(argv.dropFirst())
        process.environment = Executables.childEnvironment
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// `magick -version`'s first line, e.g. "ImageMagick 7.1.2-12 Q16-HDRI aarch64".
    public static func version(binary: String) -> String? {
        guard let out = run([binary, "-version"]), let line = out.components(separatedBy: .newlines).first else { return nil }
        return line.replacingOccurrences(of: "Version: ", with: "")
            .components(separatedBy: " https://").first
    }
}
