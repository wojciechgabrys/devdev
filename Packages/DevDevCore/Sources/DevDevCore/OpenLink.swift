import Foundation

/// A link the App handles: opens the main window on one Command's output.
///
/// The menubar panel uses it when a Command's name is clicked; notifications use it when clicked.
/// Each build flavor has its own URL scheme, so a Debug build never opens the installed App.
public enum OpenLink: Sendable, Equatable {
    case command(UUID)

    private static let commandHost = "command"

    public func url(flavor: BuildFlavor) -> URL {
        switch self {
        case .command(let id):
            var components = URLComponents()
            components.scheme = flavor.urlScheme
            components.host = Self.commandHost
            components.path = "/" + id.uuidString
            // A scheme, a host and a UUID path always make a valid URL.
            return components.url!
        }
    }

    /// Nil for a URL that is not a link of this flavor.
    public init?(url: URL, flavor: BuildFlavor) {
        guard url.scheme?.lowercased() == flavor.urlScheme, url.host()?.lowercased() == Self.commandHost else {
            return nil
        }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1, let id = UUID(uuidString: parts[0]) else { return nil }
        self = .command(id)
    }
}

extension BuildFlavor {
    /// The URL scheme the App of this flavor registers. Must match `DEVDEV_URL_SCHEME` in the Xcode project.
    public var urlScheme: String {
        switch self {
        case .release: "devdev"
        case .debug: "devdev-debug"
        }
    }
}
