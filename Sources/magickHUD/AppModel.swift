import AppKit
import magickHUDKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// A file in the drop zone.
struct DroppedFile: Identifiable, Equatable {
    var path: String
    var info: ImageInfo?
    var thumbnail: NSImage?
    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }

    static func == (a: DroppedFile, b: DroppedFile) -> Bool {
        a.path == b.path && a.info == b.info && (a.thumbnail == nil) == (b.thumbnail == nil)
    }
}

/// The result of a single-file run, for the before/after view.
struct AfterImage: Equatable {
    var jobID: String
    var before: DroppedFile
    var after: DroppedFile
}

/// Everything the panel shows: dropped files, the preset form, jobs, settings.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var files: [DroppedFile] = []
    @Published var presetID: String = "resize"
    @Published var search = ""
    /// Form values per preset, so switching presets keeps what was typed.
    @Published var values: [String: [String: String]] = [:]
    /// `output=` template for the next run (tokens allowed); empty means the settings' policy.
    @Published var outputTemplate = ""
    @Published private(set) var jobs: [Job] = []
    @Published private(set) var after: AfterImage?
    @Published private(set) var settings: MagickSettings
    @Published var isCompact = false
    @Published var isDropTargeted = false
    @Published var message: String?
    @Published var messageIsError = false
    /// Bumped to move keyboard focus to the preset search field.
    @Published var searchFocusRequest = 0

    let settingsURL: URL
    let runner = Runner()
    private(set) var magick: String?
    private(set) var magickVersion: String?
    private var nextJob = 1
    private var messageClear: DispatchWorkItem?

    /// Visibility of files / jobs changed (for `state` events).
    var onChange: (() -> Void)?

    init(settingsURL: URL) {
        self.settingsURL = settingsURL
        settings = MagickSettings.load(from: settingsURL)
        locateMagick()
    }

    func locateMagick() {
        magick = Executables.magick(override: settings.magickPath)
        magickVersion = magick.flatMap { Identify.version(binary: $0) }
    }

    var preset: Preset { PresetCatalog.preset(presetID) ?? PresetCatalog.all[0] }
    var visiblePresets: [Preset] { PresetCatalog.search(search) }
    var runningCount: Int { jobs.filter(\.isActive).count }

    // MARK: - Files

    static func isImage(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension
        guard let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf)
    }

    /// Adds image files (a folder adds the images directly inside it). Returns the paths added.
    /// Missing files and non-images are skipped; a file already in the zone is not added twice.
    @discardableResult
    func drop(_ paths: [String], completion: (([DroppedFile]) -> Void)? = nil) -> [String] {
        var added: [String] = []
        let fm = FileManager.default
        for raw in paths {
            let path = (raw as NSString).standardizingPath
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir) else { continue }
            let candidates: [String]
            if isDir.boolValue {
                candidates = ((try? fm.contentsOfDirectory(atPath: path)) ?? []).sorted()
                    .filter { !$0.hasPrefix(".") }.map { (path as NSString).appendingPathComponent($0) }
            } else {
                candidates = [path]
            }
            for file in candidates where Self.isImage(file) && !files.contains(where: { $0.path == file }) && !added.contains(file) {
                added.append(file)
            }
        }
        guard !added.isEmpty else { completion?([]); return [] }
        files += added.map { DroppedFile(path: $0) }
        after = nil
        onChange?()
        load(added, completion: completion)
        return added
    }

    /// Identifies and thumbnails `paths` off the main thread.
    private func load(_ paths: [String], completion: (([DroppedFile]) -> Void)?) {
        let binary = magick
        let group = DispatchGroup()
        for path in paths {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let info = Identify.info(path, binary: binary)
                DispatchQueue.main.async {
                    if let i = self.files.firstIndex(where: { $0.path == path }) { self.files[i].info = info }
                    group.leave()
                }
            }
            group.enter()
            Self.thumbnail(path, size: 128) { image in
                if let i = self.files.firstIndex(where: { $0.path == path }) { self.files[i].thumbnail = image }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            completion?(self.files.filter { paths.contains($0.path) })
        }
    }

    /// QuickLook's thumbnail (ImageIO as the fallback), delivered on the main queue.
    static func thumbnail(_ path: String, size: CGFloat, done: @escaping @MainActor (NSImage?) -> Void) {
        let request = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: path), size: CGSize(width: size, height: size),
                                                   scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            let cg = rep?.cgImage
            DispatchQueue.main.async {
                if let cg {
                    done(NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2)))
                } else {
                    done(NSImage(contentsOfFile: path))
                }
            }
        }
    }

    func remove(_ path: String) {
        files.removeAll { $0.path == path }
        if files.count != 1 { after = nil }
        onChange?()
    }

    func clearFiles() {
        files = []
        after = nil
        onChange?()
    }

    // MARK: - Form

    func value(_ field: PresetField) -> String {
        values[presetID]?[field.id] ?? settings.presetDefaults[field.id] ?? field.defaultValue
    }

    func binding(_ field: PresetField) -> Binding<String> {
        let id = presetID
        return Binding(get: { [weak self] in self?.value(field) ?? "" },
                       set: { [weak self] in self?.values[id, default: [:]][field.id] = $0 })
    }

    /// What Run would execute for the dropped files, or why it cannot.
    var plan: Result<[MagickCommand], BuildError> {
        do {
            return .success(try CommandBuilder.plan(preset, values: values[presetID] ?? [:], inputs: files.map(\.path),
                                                    naming: settings.naming, defaults: settings.presetDefaults,
                                                    binary: magick ?? "magick",
                                                    outputTemplate: outputTemplate.isEmpty ? nil : outputTemplate))
        } catch let error as BuildError {
            return .failure(error)
        } catch {
            return .failure(.invalid("\(error)"))
        }
    }

    // MARK: - Jobs

    /// Plans and starts a job. `values` default to the form's; `inputs` to the dropped files.
    @discardableResult
    func run(presetID id: String? = nil, inputs: [String]? = nil, values override: [String: String]? = nil,
             outputTemplate template: String? = nil, onFinish: ((Job) -> Void)? = nil) throws -> Job {
        guard let preset = PresetCatalog.preset(id ?? presetID) else {
            throw BuildError.invalid("unknown preset \(id ?? "") (\(PresetCatalog.all.map(\.id).joined(separator: ", ")))")
        }
        let inputs = inputs.map { $0.map { (($0 as NSString).expandingTildeInPath as NSString).standardizingPath } } ?? files.map(\.path)
        let fm = FileManager.default
        if let missing = inputs.first(where: { !fm.fileExists(atPath: ($0 as NSString).expandingTildeInPath) }) {
            throw BuildError.invalid("no such file: \(missing)")
        }
        let template = template ?? (outputTemplate.isEmpty ? nil : outputTemplate)
        let commands = try CommandBuilder.plan(preset, values: override ?? values[preset.id] ?? [:], inputs: inputs,
                                               naming: settings.naming, defaults: settings.presetDefaults,
                                               binary: magick ?? "magick", outputTemplate: template)
        let job = Job(id: "j\(nextJob)", preset: preset, commands: commands)
        nextJob += 1
        jobs.insert(job, at: 0)
        if jobs.count > 30 { jobs.removeLast(jobs.count - 30) }
        onChange?()
        runner.start(job) { [weak self] updated in
            MainActor.assumeIsolated { self?.jobUpdated(updated, onFinish: onFinish) }
        }
        return job
    }

    private func jobUpdated(_ job: Job, onFinish: ((Job) -> Void)?) {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        let wasActive = jobs[index].isActive
        jobs[index] = job
        onChange?()
        guard wasActive, job.items.allSatisfy(\.isFinished) else { return }
        switch job.state {
        case .done: show("\(job.title): \(job.doneCount) written")
        case .failed: show("\(job.title): \(job.failedCount) of \(job.items.count) failed", error: true)
        case .cancelled: show("\(job.title) cancelled")
        default: break
        }
        // Before/after for a single image: QuickLook thumbnails and identify for both sides.
        // Any other finished job retires the previous pair.
        after = nil
        if job.items.count == 1, let item = job.items.first, item.status == .done, item.command.inputs.count == 1 {
            let input = item.input, output = item.output
            let known = files.first { $0.path == input }
            after = AfterImage(jobID: job.id, before: known ?? DroppedFile(path: input), after: DroppedFile(path: output))
            let binary = magick
            let paths = known?.info == nil ? [input, output] : [output]
            for path in paths {
                DispatchQueue.global(qos: .userInitiated).async {
                    let info = Identify.info(path, binary: binary)
                    DispatchQueue.main.async { self.updateAfter(path) { $0.info = info } }
                }
                Self.thumbnail(path, size: 256) { image in self.updateAfter(path) { $0.thumbnail = image } }
            }
        }
        onFinish?(job)
    }

    private func updateAfter(_ path: String, _ change: (inout DroppedFile) -> Void) {
        guard var current = after else { return }
        if current.after.path == path { change(&current.after) }
        if current.before.path == path { change(&current.before) }
        after = current
    }

    func cancel(_ id: String) { runner.cancel(id) }

    func reveal(_ job: Job) {
        let urls = job.outputs.map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func clearFinishedJobs() {
        jobs.removeAll { !$0.isActive }
        after = nil
        onChange?()
    }

    // MARK: - Settings

    func updateSettings(_ values: [String: String]) throws {
        let updated = try settings.applying(values)
        try updated.save(to: settingsURL)
        let pathChanged = updated.magickPath != settings.magickPath
        settings = updated
        if pathChanged { locateMagick() }
    }

    // MARK: - Messages

    func show(_ text: String, error: Bool = false) {
        message = text
        messageIsError = error
        messageClear?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.message = nil }
        messageClear = task
        DispatchQueue.main.asyncAfter(deadline: .now() + (error ? 6 : 3), execute: task)
    }

    func focusSearch() { searchFocusRequest += 1 }

    func copyCommand() {
        guard case .success(let commands) = plan else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commands.map(\.display).joined(separator: "\n"), forType: .string)
        show(commands.count == 1 ? "Command copied" : "\(commands.count) commands copied")
    }

    /// "Same folder", "magickHUD/ beside each image", "~/Pictures/magickHUD".
    var outputDescription: String {
        if preset.combinesInputs {
            let place = settings.outputPolicy == .folder ? settings.outputFolder : "beside the first image"
            return "\(preset.suffix).ext \(place)"
        }
        switch settings.outputPolicy {
        case .same: return "beside each image, name\(settings.suffix.replacingOccurrences(of: "{preset}", with: preset.suffix))"
        case .subfolder: return "\(settings.outputSubfolder)/ beside each image"
        case .folder: return settings.outputFolder
        }
    }
}
