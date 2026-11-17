import Foundation
import Testing

/// `scripts/setup-update-key.sh`, run against a fake `gh` and a fake `generate_keys`.
/// The fake `generate_keys` keeps its "Keychain" in a file inside the test's own folder.
/// The real Keychain, the real `gh` and the real repo are never touched. The real run is
/// the user's, and stays not verified.
@Suite struct SetupUpdateKeyScriptTests {
    /// Made-up values with the shape of a real key: base64 of 32 bytes, 44 characters.
    private static let publicKey = String(repeating: "P", count: 43) + "="
    private static let privateKey = String(repeating: "S", count: 43) + "="

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private static let fakeGenerateKeys = """
        #!/bin/bash
        echo "generate_keys $*" >> "$FAKE_STATE/calls.log"
        keychain="$FAKE_STATE/keychain"
        case "${1:-}" in
            -p)
                [ -f "$keychain" ] || { echo "No existing signing key found" >&2; exit 1; }
                echo "$FAKE_PUBLIC_KEY"
                ;;
            -x)
                [ -f "$keychain" ] || exit 1
                [ -e "$2" ] && { echo "$2 already exists" >&2; exit 1; }
                echo "$2" >> "$FAKE_STATE/export-paths"
                cat "$keychain" > "$2"
                ;;
            "")
                if [ ! -f "$keychain" ]; then
                    echo "$FAKE_PRIVATE_KEY" > "$keychain"
                    echo created >> "$FAKE_STATE/keys-created"
                fi
                echo "<key>SUPublicEDKey</key><string>$FAKE_PUBLIC_KEY</string>"
                ;;
            *)
                exit 64
                ;;
        esac
        """

    private static let fakeGh = """
        #!/bin/bash
        echo "gh $*" >> "$FAKE_STATE/calls.log"
        case "${1:-} ${2:-}" in
            "auth status")
                [ -f "$FAKE_STATE/gh-signed-out" ] && { echo "You are not logged into any GitHub hosts." >&2; exit 1; }
                exit 0
                ;;
            "secret list")
                [ -f "$FAKE_STATE/gh-no-access" ] && { echo "HTTP 403: Resource not accessible" >&2; exit 1; }
                exit 0
                ;;
            "secret set")
                if [ -f "$FAKE_STATE/gh-set-fails" ]; then
                    cat > /dev/null
                    echo "HTTP 500" >&2
                    exit 1
                fi
                cat > "$FAKE_STATE/secret-body"
                ;;
            *)
                exit 64
                ;;
        esac
        """

    /// One test's folder: the fake tools, their state, and the folder the script puts temporary files in.
    private struct Sandbox {
        let folder: URL
        var state: URL { folder.appendingPathComponent("state") }
        var bin: URL { folder.appendingPathComponent("bin") }
        var temporary: URL { folder.appendingPathComponent("tmp") }

        init() throws {
            folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("devdev-key-script-\(UUID().uuidString)")
            for url in [state, bin, temporary, folder.appendingPathComponent("home")] {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
            for (name, text) in [("generate_keys", fakeGenerateKeys), ("gh", fakeGh)] {
                let tool = bin.appendingPathComponent(name)
                try text.write(to: tool, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
            }
        }

        func remove() { try? FileManager.default.removeItem(at: folder) }

        func mark(_ name: String) throws {
            try "".write(to: state.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        func stateFile(_ name: String) -> String? {
            try? String(contentsOf: state.appendingPathComponent(name), encoding: .utf8)
        }

        var calls: [String] {
            (stateFile("calls.log") ?? "").split(separator: "\n").map(String.init)
        }

        /// Every file under the sandbox whose text holds the private key, except the fake Keychain
        /// and the secret the fake `gh` received.
        func strayCopiesOfThePrivateKey() -> [String] {
            let allowed = ["state/keychain", "state/secret-body"]
            guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return [] }
            var found: [String] = []
            for case let url as URL in walker {
                guard let text = try? String(contentsOf: url, encoding: .utf8), text.contains(privateKey) else { continue }
                let path = url.resolvingSymlinksInPath().path
                if !allowed.contains(where: { path.hasSuffix($0) }) { found.append(path) }
            }
            return found
        }

        func runScript() throws -> (status: Int32, output: String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [root.appendingPathComponent("scripts/setup-update-key.sh").path]
            process.environment = [
                "PATH": "\(bin.path):/usr/bin:/bin",
                "HOME": folder.appendingPathComponent("home").path,
                "TMPDIR": temporary.path,
                "SPARKLE_BIN": bin.path,
                "FAKE_STATE": state.path,
                "FAKE_PUBLIC_KEY": publicKey,
                "FAKE_PRIVATE_KEY": privateKey,
            ]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }
    }

    @Test func theKeyScriptMakesTheKeySetsTheSecretAndPrintsThePublicKey() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }

        let result = try sandbox.runScript()

        #expect(result.status == 0, "\(result.output)")
        #expect(sandbox.stateFile("keychain") == Self.privateKey + "\n")
        #expect(sandbox.calls.contains("gh secret set SPARKLE_ED_PRIVATE_KEY --repo wojciechgabrys/devdev"))
        #expect(sandbox.stateFile("secret-body")?.trimmingCharacters(in: .whitespacesAndNewlines) == Self.privateKey)
        #expect(result.output.contains(Self.publicKey))
    }

    @Test func theKeyScriptLeavesNoCopyOfThePrivateKeyOnDiskAndNeverPrintsIt() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }

        let result = try sandbox.runScript()

        #expect(result.status == 0, "\(result.output)")
        #expect(!result.output.contains(Self.privateKey))
        let exported = try #require(sandbox.stateFile("export-paths")).split(separator: "\n").map(String.init)
        #expect(exported.count == 1)
        for path in exported {
            #expect(!FileManager.default.fileExists(atPath: path))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: sandbox.temporary.path).isEmpty)
        #expect(sandbox.strayCopiesOfThePrivateKey().isEmpty)
    }

    @Test func aSecondRunOfTheKeyScriptReusesTheKeychainKeyAndMakesNoNewOne() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }

        let first = try sandbox.runScript()
        let callsAfterFirst = sandbox.calls.count
        let second = try sandbox.runScript()

        #expect(first.status == 0, "\(first.output)")
        #expect(second.status == 0, "\(second.output)")
        #expect(sandbox.stateFile("keys-created") == "created\n")
        #expect(sandbox.stateFile("keychain") == Self.privateKey + "\n")
        #expect(second.output.contains(Self.publicKey))
        #expect(second.output.contains("Reusing"))
        // The second run only looks the key up and exports it. It never calls the form that can make a key.
        let secondRunCalls = sandbox.calls.dropFirst(callsAfterFirst).filter { $0.hasPrefix("generate_keys") }
        #expect(secondRunCalls.count == 2)
        #expect(secondRunCalls.first == "generate_keys -p")
        #expect(secondRunCalls.last?.hasPrefix("generate_keys -x ") == true)
        #expect(sandbox.stateFile("secret-body")?.trimmingCharacters(in: .whitespacesAndNewlines) == Self.privateKey)
    }

    @Test func theKeyScriptStopsBeforeTouchingTheKeychainWhenGhIsNotSignedIn() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.mark("gh-signed-out")

        let result = try sandbox.runScript()

        #expect(result.status != 0)
        #expect(result.output.contains("gh is not signed in"))
        #expect(result.output.contains("gh auth login"))
        #expect(!sandbox.calls.contains { $0.hasPrefix("generate_keys") })
        #expect(sandbox.stateFile("keychain") == nil)
    }

    @Test func theKeyScriptStopsBeforeTouchingTheKeychainWhenGhCannotSetSecretsOnTheRepo() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.mark("gh-no-access")

        let result = try sandbox.runScript()

        #expect(result.status != 0)
        #expect(result.output.contains("wojciechgabrys/devdev"))
        #expect(sandbox.calls.contains("gh secret list --repo wojciechgabrys/devdev"))
        #expect(!sandbox.calls.contains { $0.hasPrefix("generate_keys") })
        #expect(sandbox.stateFile("keychain") == nil)
    }

    @Test func theKeyScriptRemovesItsTemporaryKeyFileWhenSettingTheSecretFails() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.mark("gh-set-fails")

        let result = try sandbox.runScript()

        #expect(result.status != 0)
        #expect(result.output.contains("SPARKLE_ED_PRIVATE_KEY"))
        #expect(!result.output.contains(Self.privateKey))
        #expect(!result.output.contains("Public key:"))
        let exported = try #require(sandbox.stateFile("export-paths")).split(separator: "\n").map(String.init)
        for path in exported {
            #expect(!FileManager.default.fileExists(atPath: path))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: sandbox.temporary.path).isEmpty)
        #expect(sandbox.strayCopiesOfThePrivateKey().isEmpty)
    }

    @Test func theKeyScriptPassesBashSyntaxCheck() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-n", Self.root.appendingPathComponent("scripts/setup-update-key.sh").path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
