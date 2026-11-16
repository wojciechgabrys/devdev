import Foundation
import Testing

@testable import DevDevCore

/// The Helper as a whole, on a temporary data folder.
@Suite struct HelperHostTests {
    @Test func theHelperKeepsItsSocketAndConfigurationInsideItsDataFolderAndReloadsThemOnTheNextStart()
        async throws
    {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = HelperPaths(dataFolder: root.appendingPathComponent("data", isDirectory: true))
        let projectFolder = root.appendingPathComponent("shop", isDirectory: true)
        try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)

        let first = try HelperHost.start(paths: paths, shell: .plain)
        let client = try await HelperClient.connect(socketPath: paths.socketPath, clientName: "test")
        guard
            case .project(let project) = try await client.send(
                .addProject(folder: projectFolder.path, name: nil), origin: .user)
        else {
            Issue.record("expected a Project")
            return
        }
        _ = try await client.send(
            .addCommand(projectID: project.id, settings: CommandSettings(name: "Vite", commandLine: "npm run dev")),
            origin: .user)
        client.close()
        first.server.stop()

        #expect(FileManager.default.fileExists(atPath: paths.configurationFile.path))
        let permissions = try FileManager.default.attributesOfItem(atPath: paths.dataFolder.path)[.posixPermissions]
        #expect(permissions as? Int == 0o700)

        let second = try HelperHost.start(paths: paths, shell: .plain)
        defer { second.server.stop() }
        let snapshot = await second.engine.snapshot()
        #expect(snapshot.projects.map(\.name) == ["shop"])
        #expect(snapshot.projects.first?.commands.map(\.settings.name) == ["Vite"])
        #expect(snapshot.projects.first?.commands.map(\.status) == [.stopped])
    }

    @Test func theHelperRefusesToStartOnAConfigurationFileItCannotReadAndLeavesTheFileAlone() throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = HelperPaths(dataFolder: root)
        let damaged = Data("{ not json".utf8)
        try damaged.write(to: paths.configurationFile)

        #expect(throws: (any Error).self) {
            _ = try HelperHost.start(paths: paths, shell: .plain)
        }
        #expect(try Data(contentsOf: paths.configurationFile) == damaged)
    }
}
