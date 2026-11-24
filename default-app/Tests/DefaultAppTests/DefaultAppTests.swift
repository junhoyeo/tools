import UniformTypeIdentifiers
import XCTest

@testable import DefaultApp

final class DefaultAppTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("default-app-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testExtensionBecomesASampleFileName() {
        XCTAssertEqual(sampleName(for: "md"), "sample.md")
        XCTAssertEqual(sampleName(for: ".md"), "sample.md")
        XCTAssertEqual(sampleName(for: "c++"), "sample.c++")
    }

    func testFileNameOrPathKeepsItsLastComponent() {
        XCTAssertEqual(sampleName(for: "README.md"), "README.md")
        XCTAssertEqual(sampleName(for: "src/main.rs"), "main.rs")
        XCTAssertEqual(sampleName(for: "./Makefile"), "Makefile")
        XCTAssertEqual(sampleName(for: "./.gitignore"), ".gitignore")
    }

    func testEmptyExtensionHasNoSampleName() {
        XCTAssertNil(sampleName(for: ""))
        XCTAssertNil(sampleName(for: "."))
    }

    func testListSkipsBlankLinesAndComments() {
        XCTAssertEqual(names(in: "# Markdown\nmd\n\n  ./Makefile  \n# end\n"), ["md", "./Makefile"])
    }

    func testPathThatDoesNotEndInAFileNameHasNoSample() {
        for argument in ["", ".", "..", "/", "../", "a/b/.."] {
            XCTAssertNil(makeSample(for: argument, in: directory), "\"\(argument)\"")
        }
    }

    func testSampleFileHasTheTypeOfItsExtension() throws {
        let sample = try XCTUnwrap(makeSample(for: "txt", in: directory))
        XCTAssertEqual(contentType(of: sample), .plainText)
    }

    func testExtensionOfPackageTypesOnlyGetsADirectory() throws {
        let sample = try XCTUnwrap(makeSample(for: "rtfd", in: directory))
        XCTAssertEqual(contentType(of: sample), .rtfd)
    }

    func testSetRefusesANameThatMacOSDoesNotRecognize() {
        // The last argument is a path to a folder that exists. `set` must use its name only:
        // if it followed the path, the content type would be public.folder and not refused.
        for argument in ["./Dockerfile", "./.env", directory.path] {
            XCTAssertThrowsError(try setTarget(for: argument, in: directory), argument) { error in
                XCTAssertEqual(error as? SetRefusal, .unrecognizedName)
            }
        }
    }

    func testSetTargetsTheContentTypeOfTheName() throws {
        XCTAssertEqual(try setTarget(for: "json", in: directory).type, .json)
        XCTAssertEqual(try setTarget(for: "notes/data.json", in: directory).type, .json)
    }

    func testProbeChecksAnExistingPathItself() throws {
        let item = try XCTUnwrap(probeItem(for: directory.path, in: directory))
        XCTAssertEqual(contentType(of: item), .folder)
    }

    func testApplicationIsAPathOrABundleIdentifier() {
        XCTAssertEqual(application("/System/Applications/TextEdit.app")?.lastPathComponent, "TextEdit.app")
        XCTAssertEqual(application("com.apple.TextEdit")?.lastPathComponent, "TextEdit.app")
        XCTAssertNil(application("com.example.no-such-application.app"))
    }
}
