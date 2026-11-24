import AppKit
import UniformTypeIdentifiers

let usage = """
    usage:
      default-app probe [name ...]       show the content type and the default app of each name
      default-app set <app> [name ...]   make <app> the default app for the content type of each name

    <app>   an application path (/Applications/Visual Studio Code.app)
            or a bundle identifier (com.microsoft.VSCode)
    name    an extension (md, .md), or a file name or path (README.md, ./Makefile)

    Without names, they are read from a pipe or a file on standard input, one per line.
    Blank lines and lines that start with # are skipped.
    """

/// `md`, `.md` and `c++` are extensions. An argument with a slash, or with a dot after
/// its first character, is a file name or path.
func isExtension(_ argument: String) -> Bool {
    !argument.contains("/") && !argument.dropFirst().contains(".")
}

/// The name of the sample file that stands for `argument`: `sample.md` for the extension
/// `md`, and the last path component for a file name or path.
/// A path is read as text and never resolved. `URL(fileURLWithPath: "..").lastPathComponent`
/// is the name of the parent directory, and a file with that name has the content type
/// public.data, which `set` must not change.
func sampleName(for argument: String) -> String? {
    guard isExtension(argument) else {
        return (argument as NSString).lastPathComponent
    }
    let ext = argument.hasPrefix(".") ? String(argument.dropFirst()) : argument
    return ext.isEmpty ? nil : "sample." + ext
}

/// The names in a list: one per line, without blank lines and # comments.
func names(in list: String) -> [String] {
    list.split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
}

/// Whether some app or macOS declares a content type for `ext` that conforms to `supertype`.
func isDeclared(_ ext: String, conformingTo supertype: UTType) -> Bool {
    UTType.types(tag: ext, tagClass: .filenameExtension, conformingTo: supertype).contains { $0.isDeclared }
}

/// Creates an empty item that stands for `argument`, directly inside `directory`.
/// macOS takes the content type of a file from its name, so an empty file answers for the
/// files with that name. An extension that is declared only for package types
/// (.xcodeproj, .rtfd) gets a directory, because macOS only gives a directory that type.
func makeSample(for argument: String, in directory: URL) -> URL? {
    guard let name = sampleName(for: argument) else {
        return nil
    }
    let url = directory.appendingPathComponent(name)
    guard url.standardizedFileURL.deletingLastPathComponent().path == directory.standardizedFileURL.path else {
        return nil
    }
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: url.path) {
        return url
    }
    let ext = url.pathExtension
    if !ext.isEmpty && isDeclared(ext, conformingTo: .directory) && !isDeclared(ext, conformingTo: .data) {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
            return url
        } catch {
            return nil
        }
    }
    return fileManager.createFile(atPath: url.path, contents: nil) ? url : nil
}

func contentType(of url: URL) -> UTType? {
    try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
}

/// The item that `probe` checks for `argument`: the path itself when it exists, otherwise
/// its sample. An existing item can differ from its sample: an executable file with no
/// extension is public.unix-executable, and a file can have an app chosen for it alone.
func probeItem(for argument: String, in samples: URL) -> URL? {
    if !isExtension(argument) && FileManager.default.fileExists(atPath: argument) {
        return URL(fileURLWithPath: argument)
    }
    return makeSample(for: argument, in: samples)
}

enum SetRefusal: Error, CustomStringConvertible {
    case unusableName
    case noContentType
    case unrecognizedName

    var description: String {
        switch self {
        case .unusableName:
            return "not a usable file name"
        case .noContentType:
            return "no content type"
        case .unrecognizedName:
            return "macOS has no content type for this name. It gets public.data, as every unrecognized name without an extension does, so `set` does not change it."
        }
    }
}

/// The sample and the content type that `set` changes for `argument`.
/// `set` uses the name only, also when the argument is a path that exists: a path to a
/// folder must not make `set` change the app for folders.
/// public.data is refused, because one name such as `Dockerfile` would change the app for
/// every unrecognized name without an extension.
func setTarget(for argument: String, in samples: URL) throws -> (sample: URL, type: UTType) {
    guard let sample = makeSample(for: argument, in: samples) else {
        throw SetRefusal.unusableName
    }
    guard let type = contentType(of: sample) else {
        throw SetRefusal.noContentType
    }
    guard type != .data else {
        throw SetRefusal.unrecognizedName
    }
    return (sample, type)
}

/// The application that the `<app>` argument names.
struct RequestedApp {
    let url: URL
    /// The argument was the path of one copy of the app, not a bundle identifier.
    let isPath: Bool
}

/// The application for the `<app>` argument: the path of an application, or a bundle identifier.
func application(_ argument: String) -> RequestedApp? {
    let url = URL(fileURLWithPath: argument)
    if Bundle(url: url)?.bundleIdentifier != nil {
        return RequestedApp(url: url, isPath: true)
    }
    return NSWorkspace.shared.urlForApplication(withBundleIdentifier: argument).map {
        RequestedApp(url: $0, isPath: false)
    }
}

func isSameFile(_ a: URL, _ b: URL) -> Bool {
    func identity(_ url: URL) -> NSObjectProtocol? {
        try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
    }
    guard let a = identity(a), let b = identity(b) else { return false }
    return a.isEqual(b)
}

func hasSameBundleIdentifier(_ a: URL, _ b: URL) -> Bool {
    guard let a = Bundle(url: a)?.bundleIdentifier, let b = Bundle(url: b)?.bundleIdentifier else { return false }
    return a.caseInsensitiveCompare(b) == .orderedSame
}

/// Why `opener`, the app that macOS now uses, is not the requested app, or nil when it is.
/// macOS stores the bundle identifier of the default app. When the user named one copy by
/// its path, macOS can still open the file with another copy of the same app.
func mismatch(of opener: URL?, with app: RequestedApp) -> String? {
    guard let opener, hasSameBundleIdentifier(opener, app.url) else {
        return "macOS did not make \(app.url.path) the default app"
    }
    if app.isPath && !isSameFile(opener, app.url) {
        return "macOS opens another copy of this app, \(opener.path). It stores the bundle identifier, not the path."
    }
    return nil
}

func report(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

@main
@MainActor
struct Main {
    static func main() async {
        // Each result is written when it is known, also to a pipe, so that the output shows
        // how far `set` came when macOS waits for the user to confirm a change.
        setlinebuf(stdout)

        var arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first, command == "probe" || command == "set" else {
            report(usage)
            exit(2)
        }
        arguments.removeFirst()

        var app: RequestedApp?
        if command == "set" {
            guard let argument = arguments.first else {
                report(usage)
                exit(2)
            }
            guard let requested = application(argument) else {
                report("error: no application found for \(argument)")
                exit(2)
            }
            app = requested
            arguments.removeFirst()
        }

        if arguments.isEmpty && isatty(STDIN_FILENO) != 0 {
            report(usage)
            exit(2)
        }
        if arguments.isEmpty {
            guard let list = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) else {
                report("error: standard input is not UTF-8 text")
                exit(2)
            }
            arguments = names(in: list)
        }

        let workspace = NSWorkspace.shared
        let fileManager = FileManager.default
        let samples = fileManager.temporaryDirectory.appendingPathComponent("default-app-\(UUID().uuidString)")
        do {
            try fileManager.createDirectory(at: samples, withIntermediateDirectories: true)
        } catch {
            report("error: \(error.localizedDescription)")
            exit(1)
        }

        var failed = false
        for argument in arguments {
            if isExtension(argument) && fileManager.fileExists(atPath: argument) {
                report("note: \(argument): read as an extension. For the item with that name, write ./\(argument)")
            }

            guard let app else {
                guard let item = probeItem(for: argument, in: samples) else {
                    report("error: \(argument): \(SetRefusal.unusableName)")
                    failed = true
                    continue
                }
                let type = contentType(of: item)?.identifier ?? "-"
                let opener = workspace.urlForApplication(toOpen: item)?.path ?? "-"
                print("\(argument)\t\(type)\t\(opener)")
                continue
            }

            do {
                let (sample, type) = try setTarget(for: argument, in: samples)
                let before = workspace.urlForApplication(toOpen: sample)
                // macOS can ask the user to confirm the change, and answers only after that.
                let notice = Task {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    report("\(argument): waiting for macOS. It can show a dialog that asks you to confirm this change.")
                }
                defer { notice.cancel() }
                try await workspace.setDefaultApplication(at: app.url, toOpen: type)
                let after = workspace.urlForApplication(toOpen: sample)
                print("\(argument)\t\(type.identifier)\t\(before?.path ?? "-") -> \(after?.path ?? "-")")
                if let mismatch = mismatch(of: after, with: app) {
                    report("error: \(argument): \(mismatch)")
                    failed = true
                }
            } catch let refusal as SetRefusal {
                report("error: \(argument): \(refusal)")
                failed = true
            } catch {
                report("error: \(argument): \(error.localizedDescription)")
                failed = true
            }
        }

        try? fileManager.removeItem(at: samples)
        exit(failed ? 1 : 0)
    }
}
