import CryptoKit
import Foundation
import Testing

@testable import DevDevCore

/// The updater as the App wires it: the menu item, what Sparkle offers for which version, and
/// that nothing of it reaches the Helper. The App's sources are read as text; the version rule
/// is asked of Sparkle itself, from the framework the project pins.
///
/// No test here opens a window, reads the real feed, the Keychain or `/Applications`.
/// Clicking the real menu item stays on the manual checklist.
@Suite struct UpdaterInTheAppTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func read(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
    }

    /// The source without its comment lines, so a comment that names a thing does not count as using it.
    private func code(_ path: String) throws -> String {
        try read(path).components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func swiftFiles(in folder: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: Self.root.appendingPathComponent(folder).path)
            .filter { $0.hasSuffix(".swift") }.sorted().map { "\(folder)/\($0)" }
    }

    // MARK: - AC-5

    @Test func aReleaseBuildPutsCheckForUpdatesDirectlyBelowAboutDevDevAndItStartsASparkleCheck() throws {
        // A Release build has an updater, so the item is there.
        #expect(BuildFlavor.release.hasUpdater)
        let updater = try code("App/AppUpdater.swift")
        #expect(updater.contains("static let forThisBuild: AppUpdater? = BuildFlavor.current().hasUpdater ? AppUpdater() : nil"))

        // About DevDev is the whole of the app-info group, and the update item is what follows that group.
        let about = try code("App/AboutWindow.swift")
        #expect(about.contains("CommandGroup(replacing: .appInfo) {\n            AboutMenuItem()\n        }"))
        #expect(about.contains("Button(\"About DevDev\")"))
        #expect(updater.contains("CommandGroup(after: .appInfo) {"))
        #expect(updater.contains("Button(\"Check for Updates…\") { updater.checkForUpdates() }"))
        #expect(updater.contains(".disabled(!updater.canCheckForUpdates)"))

        // Nothing else in the App is placed around About DevDev, so nothing can sit between the two.
        var placedAtAppInfo: [String] = []
        for file in try swiftFiles(in: "App") {
            for line in try code(file).components(separatedBy: "\n") where line.contains(".appInfo") {
                placedAtAppInfo.append("\(file): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(
            placedAtAppInfo == [
                "App/AboutWindow.swift: CommandGroup(replacing: .appInfo) {",
                "App/AppUpdater.swift: CommandGroup(after: .appInfo) {",
            ])

        // The App installs both, with the updater it started at launch.
        let app = try code("App/DevDevApp.swift")
        #expect(app.contains("private let updater = AppUpdater.forThisBuild"))
        #expect(app.contains("AboutCommands()\n            UpdateCommands(updater: updater)"))

        // Choosing the item asks Sparkle's standard controller, already started, to check now.
        #expect(updater.contains("private let controller: SPUStandardUpdaterController"))
        #expect(updater.contains("startingUpdater: true"))
        #expect(updater.contains("func checkForUpdates() {\n        controller.checkForUpdates(nil)\n    }"))
    }

    // MARK: - AC-8

    /// The Sparkle package Xcode resolved for this checkout, found the way `scripts/make-appcast.sh` finds it.
    private func sparkleArtifacts() throws -> URL {
        let inDerivedData = "SourcePackages/artifacts/sparkle/Sparkle"
        func holdsSparkle(_ folder: URL) -> Bool {
            FileManager.default.fileExists(
                atPath: folder.appendingPathComponent("Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework").path)
        }
        if let named = ProcessInfo.processInfo.environment["DERIVED_DATA"], !named.isEmpty {
            let folder = URL(fileURLWithPath: named).appendingPathComponent(inDerivedData)
            if holdsSparkle(folder) { return folder }
        }
        let project = Self.root.resolvingSymlinksInPath().appendingPathComponent("devdev.xcodeproj").path
        let all = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
        for name in (try? FileManager.default.contentsOfDirectory(atPath: all.path))?.sorted() ?? [] {
            let derived = all.appendingPathComponent(name)
            guard holdsSparkle(derived.appendingPathComponent(inDerivedData)),
                let info = NSDictionary(contentsOf: derived.appendingPathComponent("info.plist")),
                let workspace = info["WorkspacePath"] as? String,
                URL(fileURLWithPath: workspace).resolvingSymlinksInPath().path == project
            else { continue }
            return derived.appendingPathComponent(inDerivedData)
        }
        Issue.record(
            "Sparkle is not resolved. Run: xcodebuild -project devdev.xcodeproj -scheme devdev -resolvePackageDependencies")
        throw CocoaError(.fileNoSuchFile)
    }

    private func run(_ tool: String, _ arguments: [String], environment: [String: String] = [:]) throws
        -> (status: Int32, output: String)
    {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        // A plain environment: the test runner's own build settings must not steer the compiler.
        process.environment = [
            "PATH": "/usr/bin:/bin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
        ].merging(environment) { $1 }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }

    /// `sparkle:version` of an appcast that `scripts/make-appcast.sh` built for this version, with a throwaway key.
    private func appcastVersion(for version: String, sparkle: URL, in folder: URL) throws -> String {
        let key = folder.appendingPathComponent("throwaway.key")
        try Data(Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString().utf8).write(to: key)
        let disk = folder.appendingPathComponent("small.dmg")
        try Data("not a real disk image".utf8).write(to: disk)
        let notes = folder.appendingPathComponent("notes.md")
        try Data("* A fix\n".utf8).write(to: notes)
        let output = folder.appendingPathComponent("appcast-\(version).xml")

        let made = try run(
            "/bin/sh",
            [Self.root.appendingPathComponent("scripts/make-appcast.sh").path, disk.path, version, notes.path, key.path, output.path],
            environment: ["SIGN_UPDATE": sparkle.appendingPathComponent("bin/sign_update").path])
        try #require(made.status == 0, "make-appcast.sh failed: \(made.output)")

        let appcast = try String(contentsOf: output, encoding: .utf8)
        let open = try #require(appcast.range(of: "<sparkle:version>"))
        let close = try #require(appcast.range(of: "</sparkle:version>"))
        return String(appcast[open.upperBound..<close.lowerBound])
    }

    @Test func sparkleOffersNoUpdateToABuildWhoseVersionEqualsOrIsHigherThanTheAppcasts() throws {
        let sparkle = try sparkleArtifacts()
        let framework = sparkle.appendingPathComponent("Sparkle.xcframework/macos-arm64_x86_64").path
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        // Sparkle offers an appcast item only when its own comparator puts the installed build's
        // CFBundleVersion below the item's sparkle:version. This tool asks that comparator.
        let source = folder.appendingPathComponent("main.swift")
        try """
            import Foundation
            import Sparkle

            let installed = CommandLine.arguments[1]
            let inAppcast = CommandLine.arguments[2]
            let order = SUStandardVersionComparator.default.compareVersion(installed, toVersion: inAppcast)
            print(order == .orderedAscending ? "offered" : "not offered")
            """.write(to: source, atomically: true, encoding: .utf8)
        let tool = folder.appendingPathComponent("offer").path
        let compiled = try run(
            "/usr/bin/xcrun",
            [
                "swiftc", source.path, "-o", tool, "-F", framework, "-framework", "Sparkle",
                "-module-cache-path", folder.appendingPathComponent("modules").path,
                "-Xlinker", "-rpath", "-Xlinker", framework,
            ])
        try #require(compiled.status == 0, "the tool did not compile against Sparkle: \(compiled.output)")

        func offer(installed: String, inAppcast: String) throws -> String {
            let asked = try run(tool, [installed, inAppcast])
            try #require(asked.status == 0, "\(asked.output)")
            return asked.output.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // The installed build's CFBundleVersion is DevDevCore.version: VersionTests holds the project to that.
        let installed = DevDevCore.version
        var numbers = installed.split(separator: ".").map { Int($0) ?? 0 }
        numbers[numbers.count - 1] += 1
        let next = numbers.map(String.init).joined(separator: ".")

        let same = try appcastVersion(for: installed, sparkle: sparkle, in: folder)
        #expect(same == installed)
        #expect(try offer(installed: installed, inAppcast: same) == "not offered")

        // A build ahead of the newest release, such as one made by scripts/install.sh after a bump.
        #expect(try offer(installed: next, inAppcast: same) == "not offered")
        #expect(try offer(installed: "1.0", inAppcast: same) == "not offered")
        // Sparkle compares numbers, not text: 0.10.0 is higher than 0.9.0.
        #expect(try offer(installed: "0.10.0", inAppcast: "0.9.0") == "not offered")

        // The other way round, or the three checks above would prove nothing.
        let newer = try appcastVersion(for: next, sparkle: sparkle, in: folder)
        #expect(newer == next)
        #expect(try offer(installed: installed, inAppcast: newer) == "offered")
    }

    // MARK: - AC-16

    @Test func theUpdaterNeverStopsRestartsOrSignalsTheHelper() throws {
        // The updater's own code knows nothing of the Helper, and gives Sparkle no delegate
        // that could act when an update installs or the App relaunches.
        let updater = try code("App/AppUpdater.swift")
        for word in ["Helper", "NSRunningApplication", "NSWorkspace", "Process(", "kill", "terminate", "launchctl", "signal"] {
            #expect(!updater.localizedCaseInsensitiveContains(word), "App/AppUpdater.swift mentions \(word)")
        }
        #expect(updater.contains("updaterDelegate: nil, userDriverDelegate: nil"))

        // AppUpdater.swift is the App's only door to Sparkle.
        for file in try swiftFiles(in: "App") where file != "App/AppUpdater.swift" {
            let text = try code(file)
            #expect(!text.contains("import Sparkle"), "\(file) imports Sparkle")
            #expect(!text.contains("SPU"), "\(file) uses a Sparkle type")
        }

        // The Updates section of Settings only flips Sparkle's own preference.
        let settings = try code("App/SettingsView.swift")
        let section = try #require(settings.range(of: "Section(UpdatesSection.title)"))
        let rest = settings[section.upperBound...]
        let body = rest[..<(try #require(rest.range(of: ".formStyle(")).lowerBound)]
        #expect(body.contains("setAutomaticallyChecksForUpdates"))
        #expect(!body.contains("model."), "the Updates section sends something to the Helper")

        // What publishes an update never reaches a Helper either.
        let publishing = [
            "scripts/make-appcast.sh", "scripts/setup-update-key.sh", "scripts/verify-update-signature.swift",
            ".github/workflows/release.yml",
        ]
        for file in publishing {
            let text = try read(file)
            for word in ["kill", "launchctl", "helper"] {
                #expect(!text.localizedCaseInsensitiveContains(word), "\(file) mentions \(word)")
            }
        }
    }

    @Test func theHelperHasNoUpdaterAndItsMenubarPanelHasNoUpdateEntry() throws {
        for file in try swiftFiles(in: "Helper") {
            let text = try read(file)
            for word in ["Sparkle", "SPU", "SUFeedURL", "appcast", "Check for Updates"] {
                #expect(!text.localizedCaseInsensitiveContains(word), "\(file) mentions \(word)")
            }
        }
        // The panel's view and the three models behind it never say "update" at all.
        let panel = [
            "Helper/MenubarPanelView.swift",
            "Packages/DevDevCore/Sources/DevDevCore/MenubarPanel.swift",
            "Packages/DevDevCore/Sources/DevDevCore/MenubarModel.swift",
            "Packages/DevDevCore/Sources/DevDevCore/MenubarPopover.swift",
        ]
        for file in panel {
            #expect(!(try read(file)).localizedCaseInsensitiveContains("update"), "\(file) mentions an update")
        }
    }
}
