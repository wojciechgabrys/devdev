import CryptoKit
import Foundation
import Testing

/// `scripts/make-appcast.sh`, run on a small file with a throwaway key made here.
/// Nothing reads the real key, the real feed, the Keychain or `/Applications`.
@Suite struct AppcastScriptTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// One run of the script in a temporary folder.
    private struct Run {
        let status: Int32
        let printed: String
        let appcast: Data?
        let disk: Data
        let key: Curve25519.Signing.PrivateKey

        var secret: String { key.rawRepresentation.base64EncodedString() }

        func feed() throws -> Feed {
            let parser = XMLParser(data: try #require(appcast))
            let feed = Feed()
            parser.delegate = feed
            #expect(parser.parse(), "the appcast is not well-formed XML: \(String(describing: parser.parserError))")
            return feed
        }
    }

    /// The appcast as an XML parser reads it.
    private final class Feed: NSObject, XMLParserDelegate {
        private(set) var items = 0
        private(set) var text: [String: String] = [:]
        private(set) var attributes: [String: [String: String]] = [:]
        private var path: [String] = []

        func parser(
            _ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
            attributes found: [String: String]
        ) {
            path.append(name)
            if name == "item" { items += 1 }
            attributes[name] = found
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            path.removeLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard path.contains("item"), let name = path.last else { return }
            text[name, default: ""] += string
        }

        func parser(_ parser: XMLParser, foundCDATA block: Data) {
            guard path.contains("item"), let name = path.last else { return }
            text[name, default: ""] += String(decoding: block, as: UTF8.self)
        }
    }

    private func run(
        version: String = "0.2.2", notes: String = "## What's Changed\n* A fix\n", keyOnStandardInput: Bool = false
    ) throws -> Run {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let key = Curve25519.Signing.PrivateKey()
        let keyFile = folder.appendingPathComponent("throwaway.key")
        try Data(key.rawRepresentation.base64EncodedString().utf8).write(to: keyFile)

        let disk = Data((0..<4099).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let diskFile = folder.appendingPathComponent("small.dmg")
        try disk.write(to: diskFile)

        let notesFile = folder.appendingPathComponent("notes.md")
        try Data(notes.utf8).write(to: notesFile)

        let output = folder.appendingPathComponent("appcast.xml")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            Self.root.appendingPathComponent("scripts/make-appcast.sh").path,
            diskFile.path, version, notesFile.path, keyOnStandardInput ? "-" : keyFile.path, output.path,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = keyOnStandardInput ? try FileHandle(forReadingFrom: keyFile) : FileHandle.nullDevice
        try process.run()
        let printed = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()

        return Run(
            status: process.terminationStatus, printed: printed, appcast: try? Data(contentsOf: output),
            disk: disk, key: key)
    }

    @Test func theAppcastHoldsOneItemWithTheReleaseVersionAndTheReleaseURL() throws {
        let run = try run(version: "0.2.2")
        try #require(run.status == 0, "make-appcast.sh failed: \(run.printed)")
        let feed = try run.feed()

        #expect(feed.items == 1)
        #expect(feed.text["sparkle:version"] == "0.2.2")
        #expect(feed.text["sparkle:shortVersionString"] == "0.2.2")
        #expect(
            feed.attributes["enclosure"]?["url"]
                == "https://github.com/wojciechgabrys/devdev/releases/download/v0.2.2/devdev-0.2.2.dmg")
    }

    @Test func theEnclosureCarriesTheByteLengthAndAnEdDSASignatureOfTheFile() throws {
        let run = try run()
        try #require(run.status == 0, "make-appcast.sh failed: \(run.printed)")
        let enclosure = try #require(try run.feed().attributes["enclosure"])

        #expect(enclosure["length"] == "4099")
        let signature = try #require(Data(base64Encoded: enclosure["sparkle:edSignature"] ?? ""))
        #expect(run.key.publicKey.isValidSignature(signature, for: run.disk))
        // A different file must not pass, or the check above proves nothing.
        #expect(!run.key.publicKey.isValidSignature(signature, for: run.disk + [0]))
    }

    @Test func theItemNeedsMacOS26() throws {
        let run = try run()
        try #require(run.status == 0, "make-appcast.sh failed: \(run.printed)")
        #expect(try run.feed().text["sparkle:minimumSystemVersion"] == "26.0")
    }

    @Test func theNotesAreEmbeddedAsMarkdownTheWaySparkleRendersThem() throws {
        let notes = """
            ## What's Changed
            * Add the updater by @someone in https://github.com/wojciechgabrys/devdev/pull/7

            **Full Changelog**: https://github.com/wojciechgabrys/devdev/compare/v0.2.1...v0.2.2

            """
        let run = try run(notes: notes)
        try #require(run.status == 0, "make-appcast.sh failed: \(run.printed)")
        let feed = try run.feed()

        #expect(feed.attributes["description"]?["sparkle:format"] == "markdown")
        #expect(feed.text["description"] == notes)
    }

    @Test func hostileNoteTextLeavesTheXMLWellFormedAndArrivesUnchanged() throws {
        let notes = """
            * Compare a < b && c > d, say "hi" and 'bye'
            * End the block early ]]> </description></item><item><title>fake</title>
            * Twice ]]>]]> and an entity &lt; &amp; &#x41; <!-- comment --> <![CDATA[ nested ]]>
            * <script>alert("x")</script> <enclosure url="https://example.com/evil.dmg"/>

            """
        let run = try run(notes: notes)
        try #require(run.status == 0, "make-appcast.sh failed: \(run.printed)")
        let feed = try run.feed()

        #expect(feed.items == 1)
        #expect(feed.text["description"] == notes)
        #expect(feed.text["sparkle:version"] == "0.2.2")
        #expect(
            feed.attributes["enclosure"]?["url"]
                == "https://github.com/wojciechgabrys/devdev/releases/download/v0.2.2/devdev-0.2.2.dmg")
    }

    @Test func controlCharactersInTheNotesAreDroppedSoTheXMLStaysWellFormed() throws {
        let run = try run(notes: "* A\u{1}B\u{8}C\u{1B}[0m\n")
        try #require(run.status == 0, "make-appcast.sh failed: \(run.printed)")
        #expect(try run.feed().text["description"] == "* ABC[0m\n")
    }

    @Test func thePrivateKeyIsNeitherPrintedNorWrittenToTheAppcast() throws {
        for keyOnStandardInput in [false, true] {
            let run = try run(keyOnStandardInput: keyOnStandardInput)
            try #require(run.status == 0, "make-appcast.sh failed: \(run.printed)")
            let appcast = String(decoding: try #require(run.appcast), as: UTF8.self)

            #expect(!run.printed.contains(run.secret))
            #expect(!appcast.contains(run.secret))
        }
    }

    @Test func theKeyCanBeReadFromStandardInput() throws {
        let run = try run(keyOnStandardInput: true)
        try #require(run.status == 0, "make-appcast.sh failed: \(run.printed)")
        let enclosure = try #require(try run.feed().attributes["enclosure"])

        let signature = try #require(Data(base64Encoded: enclosure["sparkle:edSignature"] ?? ""))
        #expect(run.key.publicKey.isValidSignature(signature, for: run.disk))
    }

    @Test func aVersionThatCouldBreakTheXMLOrTheURLIsRefused() throws {
        for version in ["0.2.2\"/><x", "v0.2.2", "0.2.2 beta", "../0.2.2", ""] {
            let run = try run(version: version)
            #expect(run.status != 0, "accepted the version \(version)")
            #expect(run.appcast == nil)
        }
    }
}
