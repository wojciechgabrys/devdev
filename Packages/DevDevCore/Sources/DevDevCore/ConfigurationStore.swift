import Foundation

/// Reads and writes the one configuration file. Only the Helper uses it.
public struct ConfigurationStore: Sendable {
    public let file: URL

    public init(file: URL) {
        self.file = file
    }

    /// The saved configuration, or an empty one when nothing was saved yet.
    public func load() throws -> Configuration {
        guard FileManager.default.fileExists(atPath: file.path) else { return Configuration() }
        return try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: file))
    }

    public func save(_ configuration: Configuration) throws {
        let folder = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: file, options: .atomic)
    }
}
