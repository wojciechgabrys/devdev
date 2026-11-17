import AppKit
import DevDevCore
import SwiftUI

/// The About DevDev menu item. It opens the About window rather than the standard panel,
/// because the standard panel has no room for the dependencies' licenses.
struct AboutCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            AboutMenuItem()
        }
    }
}

private struct AboutMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About DevDev") { openWindow(id: AboutWindow.id) }
    }
}

/// DevDev's version, copyright and license, and every package built into devdev.app
/// with its license and NOTICE text, as `Acknowledgements` lists them.
struct AboutWindow: View {
    static let id = "about"

    @State private var selection: Acknowledgement.ID? = Acknowledgements.devDev.id

    private var selected: Acknowledgement {
        Acknowledgements.all.first { $0.id == selection } ?? Acknowledgements.devDev
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                list
                    .frame(width: 230)
                Divider()
                detail
            }
        }
        .frame(width: 780, height: 560)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("DevDev").font(.title.bold())
                Text(Self.version).foregroundStyle(.secondary)
                Text("\(Acknowledgements.copyright). Released under the MIT License.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var list: some View {
        List(selection: $selection) {
            Section("DevDev") {
                row(Acknowledgements.devDev)
            }
            Section("Built with") {
                ForEach(Acknowledgements.packages) { row($0) }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ entry: Acknowledgement) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.name)
            Text(entry.license).font(.caption).foregroundStyle(.secondary)
        }
        .tag(entry.id)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(selected.name).font(.headline)
                Text(selected.license).foregroundStyle(.secondary)
                Spacer()
                // "owner/repo", which says more than the host every entry shares.
                Link(String(selected.url.path().dropFirst()), destination: selected.url)
                    .help(selected.url.absoluteString)
            }
            ScrollView {
                Text(Acknowledgements.text(of: selected))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(.background.secondary, in: .rect(cornerRadius: 6))
            .id(selected.id)
        }
        .padding(16)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let flavor = BuildFlavor.current() == .release ? "" : " (Debug)"
        return DevDevCore.versionLabel(short: short, build: build) + flavor
    }
}
