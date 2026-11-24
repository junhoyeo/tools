import AppKit
import UniformTypeIdentifiers

let usage = """
    usage:
      default-app probe [name ...]       show the content type and the default app of each name
      default-app set <app> [name ...]   make <app> the default app for the content type of each name

    <app>   an application path (/Applications/Visual Studio Code.app)
            or a bundle identifier (com.microsoft.VSCode)
    name    an extension (md, .md), or a file name or path (README.md, ./Makefile)

    Without names, they are read from standard input, one per line.
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
/// is the name of the parent directory, and a file with that name has the content type of
/// every unrecognized file.
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
/// macOS types an item by its name, so an empty item answers for every file with that name.
/// An extension that is declared only for package types (.xcodeproj, .rtfd) gets a directory,
/// because macOS only gives a directory that type.
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

/// The application for the `<app>` argument: a path, or a bundle identifier.
func application(_ argument: String) -> URL? {
    guard argument.contains("/") || argument.hasSuffix(".app") else {
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: argument)
    }
    let url = URL(fileURLWithPath: argument)
    return Bundle(url: url)?.bundleIdentifier == nil ? nil : url
}

func sameApplication(_ a: URL?, _ b: URL) -> Bool {
    guard let a, let identifier = Bundle(url: a)?.bundleIdentifier else { return false }
    return identifier.caseInsensitiveCompare(Bundle(url: b)?.bundleIdentifier ?? "") == .orderedSame
}

func report(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

@main
@MainActor
struct Main {
    static func main() async {
        var arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first, command == "probe" || command == "set" else {
            report(usage)
            exit(2)
        }
        arguments.removeFirst()

        var app: URL?
        if command == "set" {
            guard let argument = arguments.first else {
                report(usage)
                exit(2)
            }
            guard let url = application(argument) else {
                report("error: no application found for \(argument)")
                exit(2)
            }
            app = url
            arguments.removeFirst()
        }

        if arguments.isEmpty && isatty(STDIN_FILENO) != 0 {
            report(usage)
            exit(2)
        }
        let inputs = arguments.isEmpty
            ? names(in: String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self))
            : arguments

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
        for argument in inputs {
            // `probe` checks an existing path itself, so that a choice made for that one file shows.
            let item: URL
            if app == nil && !isExtension(argument) && fileManager.fileExists(atPath: argument) {
                item = URL(fileURLWithPath: argument)
            } else if let sample = makeSample(for: argument, in: samples) {
                item = sample
            } else {
                report("error: \(argument): not a usable file name")
                failed = true
                continue
            }

            let type = contentType(of: item)
            let before = workspace.urlForApplication(toOpen: item)
            guard let app else {
                print([argument, type?.identifier ?? "-", before?.path ?? "-"].joined(separator: "\t"))
                continue
            }

            guard let type else {
                report("error: \(argument): no content type")
                failed = true
                continue
            }
            if type == .data {
                report("error: \(argument): macOS does not recognize this name. Its content type, public.data, belongs to every unrecognized file, so `set` does not change it.")
                failed = true
                continue
            }
            do {
                try await workspace.setDefaultApplication(at: app, toOpen: type)
            } catch {
                report("error: \(argument): \(error.localizedDescription)")
                failed = true
                continue
            }
            let after = workspace.urlForApplication(toOpen: item)
            print("\(argument)\t\(type.identifier)\t\(before?.path ?? "-") -> \(after?.path ?? "-")")
            if !sameApplication(after, app) {
                report("error: \(argument): macOS did not make \(app.path) the default app")
                failed = true
            }
        }

        try? fileManager.removeItem(at: samples)
        exit(failed ? 1 : 0)
    }
}
