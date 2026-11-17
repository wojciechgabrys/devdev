/// What the Updates section of Settings shows. It needs no Helper: the version comes from the
/// App's bundle, and the one switch belongs to Sparkle, which stores it itself.
public struct UpdatesSection: Equatable, Sendable {
    public static let title = "Updates"

    /// A switch of the section. There is none for installing automatically: the user always clicks Install.
    public enum Switch: String, Sendable, CaseIterable, Identifiable {
        case automaticChecks

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .automaticChecks: "Check for updates automatically"
            }
        }
    }

    /// The current version, shown in every build.
    public let versionLabel: String

    /// Only a build with an updater has switches. See `BuildFlavor.hasUpdater`.
    public let switches: [Switch]

    public init(flavor: BuildFlavor, short: String, build: String) {
        versionLabel = DevDevCore.versionLabel(short: short, build: build)
        switches = flavor.hasUpdater ? Switch.allCases : []
    }
}
