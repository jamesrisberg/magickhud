import Foundation

/// The built-in presets: resize, convert, compress, web, thumbnail, crop, trim, rotate/flip,
/// strip, grayscale, adjust colors, blur, sharpen, border, watermark, montage (contact sheet) and
/// a custom argument list for batches. The argv each one makes lives in `CommandBuilder`.
public enum PresetCatalog {
    static let gravities = ["center", "north", "south", "east", "west",
                            "northeast", "northwest", "southeast", "southwest"].map { PresetOption($0) }

    static let quality = PresetField("quality", "Quality (1-100)", kind: .number, default: "85", placeholder: "85")

    public static let all: [Preset] = [
        Preset(id: "resize", title: "Resize", symbol: "arrow.up.left.and.arrow.down.right",
               summary: "Scale by percent or to a width and/or height",
               keywords: ["scale", "shrink", "smaller", "size", "dimensions"],
               fields: [
                   PresetField("size", "Size", kind: .select, options: [
                       PresetOption("50%"), PresetOption("25%"), PresetOption("1920x", "1920 px wide"),
                       PresetOption("1280x", "1280 px wide"), PresetOption("800x", "800 px wide"),
                       PresetOption("150x150", "Thumbnail 150 px"),
                   ], default: "50%"),
                   PresetField("width", "Width (px)", kind: .number, placeholder: "auto"),
                   PresetField("height", "Height (px)", kind: .number, placeholder: "auto"),
                   PresetField("fit", "Fit", kind: .select, options: [
                       PresetOption("fit", "Fit inside, keep aspect"), PresetOption("fill", "Fill, keep aspect"),
                       PresetOption("exact", "Exact (stretch)"), PresetOption("shrink", "Only shrink larger"),
                   ], default: "fit"),
               ], suffix: "resized"),
        Preset(id: "convert", title: "Convert format", symbol: "arrow.triangle.2.circlepath",
               summary: "Save as JPEG, PNG, WebP, HEIC, AVIF, GIF, TIFF or PDF",
               keywords: ["format", "jpeg", "jpg", "png", "webp", "heic", "avif", "gif", "tiff", "pdf", "export"],
               fields: [
                   PresetField("format", "Format", kind: .select, options: [
                       PresetOption("jpg", "JPEG - small, photos"), PresetOption("png", "PNG - lossless"),
                       PresetOption("webp", "WebP - modern, small"), PresetOption("heic", "HEIC"),
                       PresetOption("avif", "AVIF"), PresetOption("gif", "GIF"),
                       PresetOption("tiff", "TIFF - high quality"), PresetOption("pdf", "PDF"),
                   ], default: "jpg"),
                   quality,
               ], suffix: "converted"),
        Preset(id: "compress", title: "Compress", symbol: "arrow.down.right.and.arrow.up.left",
               summary: "Re-encode at a lower quality, keeping the format",
               keywords: ["quality", "smaller", "reduce", "optimize", "file size"],
               fields: [quality, .toggle("strip", "Strip metadata", on: true)],
               suffix: "compressed"),
        Preset(id: "web", title: "Web-ready", symbol: "globe",
               summary: "Shrink to fit 1920 px, strip metadata, JPEG or WebP",
               keywords: ["optimize", "blog", "upload", "batch", "smaller"],
               fields: [
                   PresetField("max", "Longest side (px)", kind: .number, default: "1920"),
                   PresetField("format", "Format", kind: .select, options: [
                       PresetOption("jpg", "JPEG"), PresetOption("webp", "WebP"), PresetOption("keep", "Keep format"),
                   ], default: "jpg"),
                   quality,
               ], suffix: "web"),
        Preset(id: "thumbnail", title: "Thumbnail", symbol: "square.grid.2x2",
               summary: "Square thumbnail, center-cropped",
               keywords: ["square", "avatar", "icon", "preview"],
               fields: [PresetField("size", "Size (px)", kind: .number, default: "256")],
               suffix: "thumb"),
        Preset(id: "crop", title: "Crop", symbol: "crop",
               summary: "Crop to an aspect ratio or a WxH+X+Y region",
               keywords: ["aspect", "square", "16:9", "4:3", "cut"],
               fields: [
                   PresetField("aspect", "Crop to", kind: .select, options: [
                       PresetOption("1:1", "Square (1:1)"), PresetOption("16:9", "16:9 widescreen"),
                       PresetOption("4:3", "4:3 standard"), PresetOption("3:2", "3:2 photo"),
                       PresetOption("9:16", "9:16 portrait"), PresetOption("custom", "Custom region"),
                   ], default: "1:1"),
                   PresetField("geometry", "Region", placeholder: "WxH+X+Y (e.g. 800x600+100+50)"),
                   PresetField("gravity", "Anchor", kind: .select, options: gravities, default: "center"),
               ], suffix: "cropped"),
        Preset(id: "trim", title: "Trim edges", symbol: "rectangle.dashed",
               summary: "Remove borders that match the corner color",
               keywords: ["autocrop", "whitespace", "border", "crop"],
               fields: [PresetField("fuzz", "Tolerance (%)", kind: .number, default: "5")],
               suffix: "trimmed"),
        Preset(id: "rotate", title: "Rotate / Flip", symbol: "rotate.right",
               summary: "Rotate by 90/180, flip, mirror or auto-orient",
               keywords: ["turn", "mirror", "flop", "orientation", "exif"],
               fields: [
                   PresetField("rotation", "Rotation", kind: .select, options: [
                       PresetOption("90", "90° clockwise"), PresetOption("-90", "90° counter-clockwise"),
                       PresetOption("180", "180°"), PresetOption("flip", "Flip vertical"),
                       PresetOption("flop", "Flip horizontal"), PresetOption("auto", "Auto-orient (EXIF)"),
                   ], default: "90"),
               ], suffix: "rotated"),
        Preset(id: "strip", title: "Strip metadata", symbol: "eye.slash",
               summary: "Remove EXIF, GPS and color profiles (smaller file)",
               keywords: ["exif", "gps", "privacy", "location", "profile"],
               suffix: "stripped"),
        Preset(id: "grayscale", title: "Grayscale", symbol: "circle.lefthalf.filled",
               summary: "Convert to black and white",
               keywords: ["black and white", "monochrome", "gray", "grey", "desaturate"],
               suffix: "gray"),
        Preset(id: "adjust", title: "Adjust colors", symbol: "slider.horizontal.3",
               summary: "Brightness, contrast and saturation",
               keywords: ["brightness", "contrast", "saturation", "color", "levels"],
               fields: [
                   PresetField("brightness", "Brightness (-100 to 100)", kind: .number, placeholder: "e.g. 10"),
                   PresetField("contrast", "Contrast (-100 to 100)", kind: .number, placeholder: "e.g. 10"),
                   PresetField("saturation", "Saturation (%)", kind: .number, placeholder: "120 more, 80 less"),
               ], suffix: "adjusted"),
        Preset(id: "blur", title: "Blur", symbol: "drop",
               summary: "Gaussian blur",
               keywords: ["soften", "effect", "gaussian"],
               fields: [PresetField("sigma", "Strength (sigma, or RxS)", default: "2", placeholder: "2 or 0x2")],
               suffix: "blurred"),
        Preset(id: "sharpen", title: "Sharpen", symbol: "sparkle",
               summary: "Sharpen edges",
               keywords: ["crisp", "effect", "detail"],
               fields: [PresetField("sigma", "Strength (sigma, or RxS)", default: "1", placeholder: "1 or 0x1")],
               suffix: "sharpened"),
        Preset(id: "border", title: "Border", symbol: "square.dashed",
               summary: "Add a solid border",
               keywords: ["frame", "padding", "matte"],
               fields: [
                   PresetField("width", "Width (px)", kind: .number, default: "10"),
                   PresetField("color", "Color", default: "white", placeholder: "white, #222, rgba(...)"),
               ], suffix: "border"),
        Preset(id: "watermark", title: "Watermark text", symbol: "textformat",
               summary: "Stamp a line of text in a corner",
               keywords: ["text", "copyright", "caption", "annotate", "label"],
               fields: [
                   PresetField("text", "Text", placeholder: "© 2026 Your Name", required: true),
                   PresetField("gravity", "Position", kind: .select, options: gravities, default: "southeast"),
                   PresetField("pointsize", "Size (pt)", kind: .number, default: "24"),
                   PresetField("color", "Color", default: "rgba(255,255,255,0.6)"),
                   PresetField("margin", "Margin (px)", kind: .number, default: "16"),
               ], suffix: "watermarked"),
        Preset(id: "montage", title: "Contact sheet", symbol: "rectangle.grid.3x2",
               summary: "Tile every image into one sheet (montage)",
               keywords: ["montage", "grid", "collage", "tile", "sheet", "combine"],
               fields: [
                   PresetField("columns", "Columns", kind: .number, default: "4"),
                   PresetField("tile", "Tile size (px)", kind: .number, default: "256"),
                   PresetField("spacing", "Spacing (px)", kind: .number, default: "4"),
                   PresetField("background", "Background", default: "#222222"),
                   .toggle("labels", "File names under tiles", on: false),
                   PresetField("format", "Format", kind: .select, options: [
                       PresetOption("png", "PNG"), PresetOption("jpg", "JPEG"),
                   ], default: "png"),
               ], combinesInputs: true, suffix: "contact-sheet"),
        Preset(id: "custom", title: "Custom (batch)", symbol: "terminal",
               summary: "Your own magick arguments, run over every file",
               keywords: ["batch", "arguments", "advanced", "command", "manual"],
               fields: [
                   PresetField("args", "Arguments", placeholder: "-resize 50% -strip", required: true),
                   PresetField("ext", "Output extension", placeholder: "same as input"),
               ], suffix: "custom"),
    ]

    public static func preset(_ id: String) -> Preset? { all.first { $0.id == id } }

    public static func search(_ query: String) -> [Preset] { all.filter { $0.matches(query) } }
}
