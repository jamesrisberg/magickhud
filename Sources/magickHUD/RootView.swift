import magickHUDKit
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @ObservedObject var model: AppModel
    var expand: () -> Void = {}
    var dismiss: () -> Void = {}
    var compact: () -> Void = {}
    var openFiles: () -> Void = {}

    var body: some View {
        Group {
            if model.isCompact {
                CompactTile(model: model, expand: expand)
            } else {
                VStack(spacing: 0) {
                    HeaderView(model: model, dismiss: dismiss, compact: compact, openFiles: openFiles)
                    Divider().opacity(0.4)
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            DropZoneView(model: model, openFiles: openFiles)
                            Divider().opacity(0.4)
                            PresetListView(model: model)
                        }
                        .frame(width: 250)
                        Divider().opacity(0.4)
                        DetailView(model: model)
                    }
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .onDrop(of: [.fileURL], isTargeted: $model.isDropTargeted) { providers in
            DropHandler.handle(providers, model: model)
        }
        .overlay {
            if model.isDropTargeted {
                RoundedRectangle(cornerRadius: model.isCompact ? 12 : 16, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// File URLs from a drag, in order, handed to the model on the main queue.
enum DropHandler {
    @MainActor
    static func handle(_ providers: [NSItemProvider], model: AppModel) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        var paths = [String?](repeating: nil, count: fileProviders.count)
        let group = DispatchGroup()
        for (i, provider) in fileProviders.enumerated() {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                DispatchQueue.main.async {
                    paths[i] = url?.path
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            let added = model.drop(paths.compactMap { $0 })
            if added.isEmpty { model.show("No images in that drop", error: true) }
        }
        return true
    }
}

// MARK: - Compact

/// The 44 pt tile: a wand, a badge (running jobs, else dropped images), and a drop target.
struct CompactTile: View {
    @ObservedObject var model: AppModel
    var expand: () -> Void

    var body: some View {
        Button(action: expand) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(model.runningCount > 0 ? Color.accentColor : .primary)
                    .frame(width: 44, height: 44)
                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .padding(.horizontal, 4).frame(minWidth: 15, minHeight: 15)
                        .background(Capsule().fill(model.runningCount > 0 ? Color.orange : Color.accentColor))
                        .foregroundStyle(.white)
                        .offset(x: -3, y: 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.files.isEmpty ? "magickHUD: drop images here" : "\(model.files.count) images ready")
    }

    private var badge: String? {
        if model.runningCount > 0 { return String(model.runningCount) }
        return model.files.isEmpty ? nil : String(model.files.count)
    }
}

// MARK: - Header

struct HeaderView: View {
    @ObservedObject var model: AppModel
    var dismiss: () -> Void
    var compact: () -> Void
    var openFiles: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars").foregroundStyle(Color.accentColor)
            Text("magickHUD").font(.system(size: 13, weight: .semibold))
            if let message = model.message {
                Text(message).font(.system(size: 10, weight: .medium)).lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(model.messageIsError ? Color.orange.opacity(0.85) : Color.white.opacity(0.14)))
            } else if let version = model.magickVersion {
                Text(version).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Label("ImageMagick not found: brew install imagemagick", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10)).foregroundStyle(.orange).lineLimit(1)
                    .textSelection(.enabled)
            }
            Spacer()
            HeaderButton(symbol: "plus", help: "Add images (⌘O)", action: openFiles)
            HeaderButton(symbol: "arrow.down.right.and.arrow.up.left", help: "Compact tile", action: compact)
            HeaderButton(symbol: "xmark", help: "Hide (Esc)", action: dismiss)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
    }
}

struct HeaderButton: View {
    var symbol: String
    var help: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }
}

// MARK: - Drop zone

struct DropZoneView: View {
    @ObservedObject var model: AppModel
    var openFiles: () -> Void
    private let columns = [GridItem(.adaptive(minimum: 68, maximum: 80), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.files.isEmpty {
                Button(action: openFiles) {
                    VStack(spacing: 8) {
                        Image(systemName: "wand.and.stars").font(.system(size: 26, weight: .light))
                        Text("Drop images here").font(.system(size: 12, weight: .medium))
                        Text("one or many · ⌘O to choose").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                        .foregroundStyle(.secondary.opacity(0.6)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(model.files) { file in
                            FileTile(file: file) { model.remove(file.path) }
                        }
                    }
                }
                HStack {
                    Text(summary).font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { model.clearFiles() }.buttonStyle(.plain).font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(height: 210)
    }

    private var summary: String {
        let bytes = model.files.compactMap(\.info?.bytes).reduce(0, +)
        let n = model.files.count
        return "\(n) image\(n == 1 ? "" : "s") · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
    }
}

struct FileTile: View {
    let file: DroppedFile
    var remove: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                Thumb(image: file.thumbnail).frame(width: 64, height: 52)
                if hovering {
                    Button(action: remove) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 13))
                            .symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 4, y: -4)
                }
            }
            Text(file.name).font(.system(size: 9)).lineLimit(1).truncationMode(.middle)
            Text(file.info?.dimensions ?? "…").font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
        }
        .onHover { hovering = $0 }
        .help("\(file.path)\n\(file.info?.summary ?? "")")
    }
}

struct Thumb: View {
    let image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.06))
            if let image {
                Image(nsImage: image).resizable().interpolation(.medium).aspectRatio(contentMode: .fit).padding(2)
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Presets

struct PresetListView: View {
    @ObservedObject var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 11))
                TextField("Search presets", text: $model.search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searchFocused)
                    .onSubmit { if let first = model.visiblePresets.first { model.presetID = first.id } }
                if !model.search.isEmpty {
                    Button { model.search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
            .padding(.horizontal, 10).padding(.top, 8)

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(model.visiblePresets) { preset in
                        PresetRow(preset: preset, selected: preset.id == model.presetID) { model.presetID = preset.id }
                    }
                    if model.visiblePresets.isEmpty {
                        Text("No presets match").font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 20)
                    }
                }
                .padding(.horizontal, 6).padding(.bottom, 8)
            }
        }
        .onChange(of: model.searchFocusRequest) { searchFocused = true }
    }
}

struct PresetRow: View {
    let preset: Preset
    let selected: Bool
    var select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                Image(systemName: preset.symbol).frame(width: 18).foregroundStyle(selected ? Color.white : Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.title).font(.system(size: 12, weight: .medium))
                    Text(preset.summary).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.55) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Detail: form, preview, run, before/after, jobs

struct DetailView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let preset = model.preset
                HStack(spacing: 8) {
                    Image(systemName: preset.symbol).font(.system(size: 16)).foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(preset.title).font(.system(size: 14, weight: .semibold))
                        Text(preset.summary).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                FormView(model: model, preset: preset)
                CommandPreview(model: model)
                if !model.jobs.isEmpty { JobsView(model: model) }
                if model.after != nil { BeforeAfterView(model: model) }
            }
            .padding(14)
        }
    }
}

struct FormView: View {
    @ObservedObject var model: AppModel
    let preset: Preset

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 7) {
            ForEach(preset.fields) { field in
                GridRow {
                    Text(field.label).font(.system(size: 11)).foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    control(field)
                }
            }
            GridRow {
                Text("Output").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField(model.outputDescription, text: $model.outputTemplate)
                    .textFieldStyle(.roundedBorder).font(.system(size: 11))
                    .help("Optional path template: {dir} {name} {ext} {preset}, e.g. {dir}/small/{name}.{ext}. Existing files are never overwritten.")
            }
        }
        .id(preset.id)
    }

    @ViewBuilder
    private func control(_ field: PresetField) -> some View {
        switch field.kind {
        case .select:
            Picker("", selection: model.binding(field)) {
                ForEach(field.options, id: \.value) { Text($0.label).tag($0.value) }
            }
            .labelsHidden().pickerStyle(.menu).frame(maxWidth: 240, alignment: .leading)
        case .toggle:
            Toggle("", isOn: Binding(get: { PresetField.bool(model.value(field)) },
                                     set: { model.binding(field).wrappedValue = $0 ? "1" : "0" }))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
        case .text, .number:
            TextField(field.placeholder ?? "", text: model.binding(field))
                .textFieldStyle(.roundedBorder).font(.system(size: 11))
                .frame(maxWidth: field.kind == .number ? 120 : .infinity)
        }
    }
}

struct CommandPreview: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let plan = model.plan
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Group {
                    switch plan {
                    case .success(let commands):
                        let shown = commands.prefix(2).map(Self.shortDisplay).joined(separator: "\n")
                            + (commands.count > 2 ? "\n… and \(commands.count - 2) more like these" : "")
                        Text(shown).foregroundStyle(.primary)
                    case .failure(let error):
                        Text(error == .noInput ? "magick {input} … {output}\n(drop an image to see the command)" : "⚠︎ \(error.description)")
                            .foregroundStyle(error == .noInput ? Color.secondary : Color.orange)
                    }
                }
                .font(.system(size: 10.5, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8).padding(.trailing, 22)
                if case .success = plan {
                    Button { model.copyCommand() } label: { Image(systemName: "doc.on.doc").font(.system(size: 10)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).padding(6).help("Copy (⌘⇧C)")
                }
            }
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.28)))

            HStack {
                Button { _ = try? model.run() } label: {
                    Label(runTitle(plan), systemImage: "play.fill").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canRun(plan))
                .keyboardShortcut(.return, modifiers: .command)
                Text("⌘↩").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    /// The display form with `magick` instead of its resolved path.
    static func shortDisplay(_ command: MagickCommand) -> String {
        var short = command
        if let first = short.argv.first { short.argv[0] = (first as NSString).lastPathComponent }
        return short.display
    }

    private func canRun(_ plan: Result<[MagickCommand], BuildError>) -> Bool {
        if case .success = plan { return model.magick != nil }
        return false
    }

    private func runTitle(_ plan: Result<[MagickCommand], BuildError>) -> String {
        if model.preset.combinesInputs { return "Make sheet of \(model.files.count)" }
        let n = model.files.count
        return n <= 1 ? "Run" : "Run on \(n) images"
    }
}

struct BeforeAfterView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let pair = model.after {
            VStack(alignment: .leading, spacing: 6) {
                Text("Before / after").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                HStack(alignment: .center, spacing: 10) {
                    card(title: "Before", file: pair.before)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    card(title: "After", file: pair.after)
                }
            }
        }
    }

    private func card(title: String, file: DroppedFile) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Thumb(image: file.thumbnail).frame(width: 150, height: 110)
            Text(title).font(.system(size: 10, weight: .semibold))
            Text(file.info?.summary ?? "…").font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
            Text(file.name).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
        .frame(width: 150)
    }
}

struct JobsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Jobs").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if model.jobs.contains(where: { !$0.isActive }) {
                    Button("Clear finished") { model.clearFinishedJobs() }.buttonStyle(.plain)
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            ForEach(model.jobs) { job in JobRow(model: model, job: job) }
        }
    }
}

struct JobRow: View {
    @ObservedObject var model: AppModel
    let job: Job
    @State private var showErrors = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(color).font(.system(size: 12))
                Text(job.statusLine).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                if job.isActive {
                    Button("Cancel") { model.cancel(job.id) }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.orange)
                } else if !job.outputs.isEmpty {
                    Button("Reveal") { model.reveal(job) }.buttonStyle(.plain).font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
            }
            if job.isActive || job.items.count > 1 { JobBar(job: job) }
            let failures = job.items.filter { $0.status == .failed }
            if !failures.isEmpty {
                DisclosureGroup(isExpanded: $showErrors) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(failures) { item in
                            VStack(alignment: .leading, spacing: 1) {
                                Text((item.input as NSString).lastPathComponent).font(.system(size: 10, weight: .semibold))
                                Text((item.log.isEmpty ? [item.error ?? "failed"] : item.log).joined(separator: "\n"))
                                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.orange)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Errors (\(failures.count))").font(.system(size: 10)).foregroundStyle(.orange)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private var detail: String {
        if job.items.count == 1, let item = job.items.first {
            return "→ " + (item.output as NSString).lastPathComponent
        }
        return "\(job.doneCount)/\(job.items.count)"
    }

    private var icon: String {
        switch job.state {
        case .pending: return "clock"
        case .running: return "gearshape.fill"
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle"
        }
    }

    private var color: Color {
        switch job.state {
        case .done: return .green
        case .failed: return .orange
        case .cancelled: return .secondary
        default: return .accentColor
        }
    }
}

/// Per-file progress: done (green), failed (orange), cancelled (gray), the rest empty.
struct JobBar: View {
    let job: Job

    var body: some View {
        GeometryReader { geo in
            let total = CGFloat(max(job.items.count, 1))
            let segments: [(Color, Int)] = [
                (.green, job.doneCount), (.orange, job.failedCount),
                (.gray, job.items.filter { $0.status == .cancelled }.count),
                (.accentColor, job.items.filter { $0.status == .running }.count),
            ]
            HStack(spacing: 0) {
                ForEach(segments.indices, id: \.self) { i in
                    Rectangle().fill(segments[i].0.opacity(i == 3 ? 0.5 : 1))
                        .frame(width: geo.size.width * CGFloat(segments[i].1) / total)
                }
                Spacer(minLength: 0)
            }
            .background(Color.white.opacity(0.1))
            .clipShape(Capsule())
        }
        .frame(height: 4)
    }
}
