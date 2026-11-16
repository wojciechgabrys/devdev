import Foundation

/// The Settings the Helper stores and acts on (`docs/spec.md` section 7, Settings).
public struct HelperSettings: Codable, Sendable, Equatable {
    /// When off, the Helper keeps running with no menubar icon.
    public var showMenubarIcon: Bool
    /// Starts the Helper at login. Never starts a Process.
    public var launchAtLogin: Bool
    /// One switch per notification kind.
    public var notifications: NotificationSettings

    public init(
        showMenubarIcon: Bool = true, launchAtLogin: Bool = false,
        notifications: NotificationSettings = NotificationSettings()
    ) {
        self.showMenubarIcon = showMenubarIcon
        self.launchAtLogin = launchAtLogin
        self.notifications = notifications
    }

    // A setting missing from the file keeps its default, so a later setting never breaks an older file.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = HelperSettings()
        showMenubarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenubarIcon) ?? defaults.showMenubarIcon
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        notifications =
            try container.decodeIfPresent(NotificationSettings.self, forKey: .notifications) ?? defaults.notifications
    }
}

/// Makes the Helper start at login, or stops it from doing so. Neither call starts or stops a Helper now.
public protocol LoginItem: Sendable {
    func apply(enabled: Bool) throws
}
