import Foundation

/// The running Helper: the engine and its socket, on the data folder of one build flavor.
public final class HelperHost: Sendable {
    public let paths: HelperPaths
    public let engine: HelperEngine
    public let server: HelperServer

    /// Loads the saved configuration and starts listening. Fails with `alreadyRunning` when another
    /// Helper of the same flavor runs, and fails rather than overwrite a configuration file it cannot read.
    public static func start(
        paths: HelperPaths,
        shell: Shell = .userLogin(),
        timings: Timings = .standard,
        helperVersion: String = DevDevCore.version
    ) throws -> HelperHost {
        try FileManager.default.createDirectory(
            at: paths.dataFolder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let store = ConfigurationStore(file: paths.configurationFile)
        let engine = HelperEngine(configuration: try store.load(), store: store, shell: shell, timings: timings,
            helperVersion: helperVersion)
        let server = HelperServer(engine: engine, socketPath: paths.socketPath)
        try server.start()
        return HelperHost(paths: paths, engine: engine, server: server)
    }

    private init(paths: HelperPaths, engine: HelperEngine, server: HelperServer) {
        self.paths = paths
        self.engine = engine
        self.server = server
    }
}
