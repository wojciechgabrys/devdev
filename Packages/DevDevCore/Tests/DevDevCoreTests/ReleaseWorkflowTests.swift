import CryptoKit
import Foundation
import Testing

/// The release workflow's update steps, and the script that checks a DMG's signature against the
/// public key in a built app. Every key is a throwaway made here. Nothing reads the real key,
/// the Keychain, GitHub or `/Applications`.
@Suite struct ReleaseWorkflowTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private static let secretName = "SPARKLE_ED_PRIVATE_KEY"

    // MARK: - The workflow file

    /// One step of the workflow: its name and all of its lines, the name's line included.
    private struct Step {
        let name: String
        let lines: [String]

        var text: String { lines.joined(separator: "\n") }

        /// The shell script under `run: |`, without its indent.
        var script: String {
            guard let run = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "run: |" }) else {
                return ""
            }
            return lines[(run + 1)...]
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
        }

        /// The script with each line that ends in a backslash joined to the next one.
        var commands: [String] {
            script.replacingOccurrences(of: " \\\n", with: " ")
                .components(separatedBy: "\n")
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        }
    }

    private func workflowLines() throws -> [String] {
        try String(contentsOf: Self.root.appendingPathComponent(".github/workflows/release.yml"), encoding: .utf8)
            .components(separatedBy: "\n")
    }

    /// The named steps of the one job, in the order they run.
    private func steps() throws -> [Step] {
        var steps: [Step] = []
        var current: (name: String, lines: [String])?
        for line in try workflowLines() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") {
                if let current { steps.append(Step(name: current.name, lines: current.lines)) }
                current = trimmed.hasPrefix("- name: ") ? (String(trimmed.dropFirst("- name: ".count)), [line]) : nil
            } else if trimmed.hasPrefix("#") && current != nil && !line.hasPrefix("          ") {
                // A comment above the next step is not part of this one.
                continue
            } else {
                current?.lines.append(line)
            }
        }
        if let current { steps.append(Step(name: current.name, lines: current.lines)) }
        return steps
    }

    private func step(_ name: String) throws -> Step {
        try #require(try steps().first { $0.name == name }, "the workflow has no step named \(name)")
    }

    private func position(_ name: String) throws -> Int {
        try #require(try steps().firstIndex { $0.name == name }, "the workflow has no step named \(name)")
    }

    private func runScript(_ script: String, environment: [String: String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-e", "-c", script]
        process.environment = ["PATH": "/usr/bin:/bin"].merging(environment) { $1 }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    // MARK: - The secret check

    private let secretCheck = "Check the update signing key is set"

    @Test(arguments: [nil, "", " \n"])
    func theSecretCheckFailsAndNamesTheSecretWhenItIsMissingOrEmpty(secret: String?) throws {
        var environment: [String: String] = [:]
        if let secret { environment[Self.secretName] = secret }
        let result = try runScript(try step(secretCheck).script, environment: environment)

        #expect(result.status != 0)
        let error = result.output.split(separator: "\n").first { $0.hasPrefix("::error::") }
        #expect(error?.contains(Self.secretName) == true, "\(result.output)")
    }

    @Test func theSecretCheckPassesWithAKeyAndDoesNotPrintIt() throws {
        let secret = Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString()
        let result = try runScript(try step(secretCheck).script, environment: [Self.secretName: secret])

        #expect(result.status == 0, "\(result.output)")
        #expect(!result.output.contains(secret))
    }

    @Test func theSecretCheckRunsBeforeTheBuild() throws {
        #expect(try position(secretCheck) < position("Resolve packages"))
        #expect(try position(secretCheck) < position("Build Release"))
        #expect(try step(secretCheck).text.contains("\(Self.secretName): ${{ secrets.\(Self.secretName) }}"))
    }

    // MARK: - The private key in the workflow

    @Test func thePrivateKeyReachesStepsOnlyThroughEnv() throws {
        let lines = try workflowLines()
        let handover = "\(Self.secretName): ${{ secrets.\(Self.secretName) }}"
        // An expression inside a script is pasted into the script's text, which the log can show.
        let expressions = lines.filter { $0.contains("secrets.") }
        #expect(!expressions.isEmpty)
        #expect(expressions.allSatisfy { $0.trimmingCharacters(in: .whitespaces) == handover }, "\(expressions)")
    }

    @Test func noStepPrintsThePrivateKeyOrWritesItToAFile() throws {
        for step in try steps() {
            for command in step.commands where command.contains("$\(Self.secretName)") || command.contains("${\(Self.secretName)") {
                let allowed =
                    command.hasPrefix("if [ -z \"$(printf '%s' \"$\(Self.secretName)\" | tr -d '[:space:]')\" ]")
                    || command.hasPrefix("printf '%s\\n' \"$\(Self.secretName)\" | scripts/make-appcast.sh ")
                #expect(allowed, "\(step.name) uses the key in: \(command)")
                #expect(!command.contains(">"), "\(step.name) redirects output on a line that holds the key")
            }
            #expect(!step.script.contains("set -x"), "\(step.name) traces its commands")
        }
    }

    // MARK: - Notes, appcast and the release

    private let notesStep = "Get the release notes"
    private let appcastStep = "Sign the DMG and make the appcast"
    private let verifyStep = "Check the signature against the key in the app"
    private let publishStep = "Publish the release"

    @Test func theNotesAreGeneratedOnceAndGoToBothTheAppcastAndTheRelease() throws {
        let all = try steps()
        let generating = all.filter { $0.script.contains("generate-notes") }
        #expect(generating.map(\.name) == [notesStep])
        #expect(try step(notesStep).script.contains("releases/generate-notes"))
        #expect(try step(notesStep).script.contains("> release-notes.md"))

        let appcast = try #require(try step(appcastStep).commands.first { $0.contains("scripts/make-appcast.sh") })
        #expect(appcast.contains(" release-notes.md "))
        let create = try #require(try step(publishStep).commands.first { $0.contains("gh release create") })
        #expect(create.contains("--notes-file release-notes.md"))
        #expect(!create.contains("--generate-notes"))
    }

    @Test func theAppcastIsMadeFromTheDMGTheVersionAndTheKeyOnStandardInput() throws {
        let commands = try step(appcastStep).commands
        #expect(
            commands == [
                "printf '%s\\n' \"$\(Self.secretName)\" | scripts/make-appcast.sh \"devdev-$VERSION.dmg\" \"$VERSION\" release-notes.md - appcast.xml"
            ])
    }

    @Test func theSignatureIsCheckedAgainstTheBuiltAppBeforeAnyReleaseExists() throws {
        let verify = try step(verifyStep)
        #expect(
            verify.script.contains(
                "swift scripts/verify-update-signature.swift \"devdev-$VERSION.dmg\" appcast.xml \"$DERIVED_DATA/Build/Products/Release/devdev.app\""
            ))
        #expect(!verify.text.contains("continue-on-error"))
        #expect(!verify.text.contains("|| true"))

        #expect(try position("Make the DMG") < position(notesStep))
        #expect(try position(notesStep) < position(appcastStep))
        #expect(try position(appcastStep) < position(verifyStep))
        #expect(try position(verifyStep) < position(publishStep))

        // Only the last step touches releases, so a failed check leaves none behind.
        let releasing = try steps().filter { $0.script.contains("gh release") }
        #expect(releasing.map(\.name) == [publishStep])
        #expect(try position(publishStep) == steps().count - 1)
    }

    @Test func theReleaseIsCreatedOnceWithTheDMGAndTheAppcastAndNothingElse() throws {
        let commands = try step(publishStep).commands
        #expect(commands.count == 1)
        let create = try #require(commands.first)
        let words = create.split(separator: " ").map(String.init)

        #expect(Array(words.prefix(3)) == ["gh", "release", "create"])
        // The words between the tag and the first flag are the assets.
        let assets = words.dropFirst(4).prefix { !$0.hasPrefix("--") }
        #expect(Array(assets) == ["\"devdev-$VERSION.dmg\"", "appcast.xml"])
        #expect(try workflowLines().allSatisfy { !$0.contains("gh release upload") })
    }

    @Test func nothingIsCommittedOrPushed() throws {
        for step in try steps() {
            #expect(!step.script.contains("git push"), "\(step.name) pushes")
            #expect(!step.script.contains("git commit"), "\(step.name) commits")
            #expect(!step.script.contains("gh-pages"), "\(step.name) uses gh-pages")
            #expect(!step.script.contains(".zip"), "\(step.name) makes a zip")
        }
    }

    // MARK: - scripts/verify-update-signature.swift

    /// One run of the verify script on a small file, a one-item appcast and a folder shaped like an app.
    private func verify(
        signWith signer: Curve25519.Signing.PrivateKey = .init(),
        appKey: (Curve25519.Signing.PrivateKey) -> String? = { $0.publicKey.rawRepresentation.base64EncodedString() },
        changeDiskAfterSigning: Bool = false,
        signature: ((String) -> String?) = { $0 }
    ) throws -> (status: Int32, output: String, secret: String) {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        var disk = Data((0..<4099).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let signed = try signer.signature(for: disk).base64EncodedString()
        if changeDiskAfterSigning { disk.append(0) }
        let diskFile = folder.appendingPathComponent("small.dmg")
        try disk.write(to: diskFile)

        let attribute = signature(signed).map { " sparkle:edSignature=\"\($0)\"" } ?? ""
        let appcast = """
            <?xml version="1.0" encoding="utf-8"?>
            <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
              <channel>
                <item>
                  <description sparkle:format="markdown"><![CDATA[sparkle:edSignature="AAAA"]]></description>
                  <enclosure url="https://example.com/small.dmg" length="\(disk.count)"\(attribute)/>
                </item>
              </channel>
            </rss>
            """
        let appcastFile = folder.appendingPathComponent("appcast.xml")
        try Data(appcast.utf8).write(to: appcastFile)

        let app = folder.appendingPathComponent("devdev.app")
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleIdentifier": "com.example.throwaway"]
        if let key = appKey(signer) { info["SUPublicEDKey"] = key }
        try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = [
            Self.root.appendingPathComponent("scripts/verify-update-signature.swift").path,
            diskFile.path, appcastFile.path, app.path,
        ]
        // The variables `swift test` sets for its own build must not reach a second compiler.
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory()]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus, String(decoding: data, as: UTF8.self),
            signer.rawRepresentation.base64EncodedString()
        )
    }

    @Test func aSignatureMadeWithTheKeyOfTheAppPasses() throws {
        let result = try verify()
        #expect(result.status == 0, "\(result.output)")
        #expect(!result.output.contains(result.secret))
    }

    @Test func aSignatureMadeWithAnotherKeyFails() throws {
        let result = try verify(appKey: { _ in Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString() })
        #expect(result.status != 0)
        #expect(result.output.contains("SUPublicEDKey"), "\(result.output)")
    }

    @Test func aDiskImageChangedAfterSigningFails() throws {
        #expect(try verify(changeDiskAfterSigning: true).status != 0)
    }

    @Test func anAppWithoutAPublicKeyFails() throws {
        let result = try verify(appKey: { _ in nil })
        #expect(result.status != 0)
        #expect(result.output.contains("SUPublicEDKey"), "\(result.output)")
    }

    @Test(arguments: ["", "not base64", "AAAA"])
    func anAppWithAMalformedPublicKeyFails(key: String) throws {
        #expect(try verify(appKey: { _ in key }).status != 0)
    }

    @Test func anAppcastWithoutASignatureFails() throws {
        // The notes of the test appcast hold the text of a signature attribute. It must not count.
        #expect(try verify(signature: { _ in nil }).status != 0)
        #expect(try verify(signature: { _ in "" }).status != 0)
    }
}
