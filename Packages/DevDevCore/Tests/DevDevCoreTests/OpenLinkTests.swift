import Foundation
import Testing

@testable import DevDevCore

/// The link that opens the App on one Command's output. The menubar panel uses it now, notifications later.
@Suite struct OpenLinkTests {
    private let id = UUID(uuidString: "6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F")!

    @Test func theOpenOnCommandLinkIsBuiltAndParsedBack() throws {
        let url = OpenLink.command(id).url(flavor: .release)
        #expect(url.absoluteString == "devdev://command/6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F")
        #expect(OpenLink(url: url, flavor: .release) == .command(id))
    }

    @Test func aDebugBuildUsesItsOwnSchemeAndIgnoresTheReleaseOne() {
        let url = OpenLink.command(id).url(flavor: .debug)
        #expect(url.scheme == "devdev-debug")
        #expect(OpenLink(url: url, flavor: .debug) == .command(id))
        #expect(OpenLink(url: url, flavor: .release) == nil)
        #expect(OpenLink(url: OpenLink.command(id).url(flavor: .release), flavor: .debug) == nil)
    }

    @Test func aLinkThatIsNotOursIsIgnored() throws {
        for text in [
            "devdev://command/not-a-uuid", "devdev://project/6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F", "devdev://command",
            "https://example.com/command/6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F",
        ] {
            #expect(OpenLink(url: try #require(URL(string: text)), flavor: .release) == nil, "\(text)")
        }
    }

    @Test func theUUIDIsReadWhateverItsLetterCase() throws {
        let url = try #require(URL(string: "devdev://command/6f1c2d3e-4a5b-4c6d-8e9f-0a1b2c3d4e5f"))
        #expect(OpenLink(url: url, flavor: .release) == .command(id))
    }
}

/// How the Helper finds the App it belongs to, and that the App registers the link's scheme.
@Suite struct AppLocationTests {
    @Test func theHelperOpensTheAppThatContainsIt() {
        let helper = URL(fileURLWithPath: "/Applications/devdev.app/Contents/Helpers/devdevHelper.app", isDirectory: true)
        #expect(HelperLocation.app(containingHelper: helper).path == "/Applications/devdev.app")
    }

    @Test func theXcodeProjectRegistersTheLinkSchemeOfEachFlavor() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let project = try String(
            contentsOf: root.appendingPathComponent("devdev.xcodeproj/project.pbxproj"), encoding: .utf8)
        let plist = try String(contentsOf: root.appendingPathComponent("Config/App-Info.plist"), encoding: .utf8)
        #expect(plist.contains("<string>$(DEVDEV_URL_SCHEME)</string>"))
        // Xcode quotes a value with a dash, so accept both forms.
        for flavor in BuildFlavor.allCases {
            let plain = "DEVDEV_URL_SCHEME = \(flavor.urlScheme);"
            let quoted = "DEVDEV_URL_SCHEME = \"\(flavor.urlScheme)\";"
            #expect(project.contains(plain) || project.contains(quoted), "\(flavor)")
        }
        #expect(project.components(separatedBy: "INFOPLIST_FILE = \"Config/App-Info.plist\";").count == 3)
    }
}
