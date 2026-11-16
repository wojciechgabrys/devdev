import DevDevCore
import SwiftUI

/// Go to Command (Cmd-K): type part of a Command's or Project's name, pick with the arrows, press Return.
/// Matching and order come from `CommandSearch`.
struct GoToCommand: View {
    let model: WindowModel
    @Binding var isOpen: Bool
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        let results = CommandSearch.results(for: query, in: model.state.snapshot)
        ZStack(alignment: .top) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { close() }
            VStack(spacing: 0) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Graphite.secondary)
                    TextField("Go to Command", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .foregroundStyle(Graphite.strong)
                        .focused($isFieldFocused)
                        .onSubmit { pick(results) }
                        .onKeyPress(.downArrow) {
                            highlighted = min(highlighted + 1, max(results.count - 1, 0))
                            return .handled
                        }
                        .onKeyPress(.upArrow) {
                            highlighted = max(highlighted - 1, 0)
                            return .handled
                        }
                        .onKeyPress(.escape) {
                            close()
                            return .handled
                        }
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                Rectangle().fill(Graphite.line).frame(height: 1)
                if results.isEmpty {
                    Text("No Command matches “\(query)”")
                        .font(.system(size: 12))
                        .foregroundStyle(Graphite.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                                    row(result, isHighlighted: index == highlighted)
                                        .id(index)
                                        .onTapGesture { show(result) }
                                }
                            }
                            .padding(6)
                        }
                        .frame(maxHeight: 320)
                        .onChange(of: highlighted) { _, index in proxy.scrollTo(index) }
                    }
                }
            }
            .frame(width: 540)
            .fixedSize(horizontal: false, vertical: true)
            .background(RoundedRectangle(cornerRadius: 12).fill(Graphite.chrome))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Graphite.line))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.35), radius: 30, y: 14)
            .padding(.top, 70)
        }
        .onAppear { isFieldFocused = true }
        .onChange(of: query) { highlighted = 0 }
    }

    private func row(_ result: CommandSearch.Result, isHighlighted: Bool) -> some View {
        HStack(spacing: 9) {
            StatusGlyph(result.status)
            Text(result.commandName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isHighlighted ? .white : Graphite.strong)
            Text(result.projectName)
                .font(.system(size: 12))
                .foregroundStyle(isHighlighted ? .white.opacity(0.75) : Graphite.secondary)
            Spacer(minLength: 12)
            Text(result.commandLine)
                .font(Graphite.monoSmall)
                .foregroundStyle(isHighlighted ? .white.opacity(0.7) : Graphite.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 6).fill(isHighlighted ? Graphite.accent : .clear))
        .contentShape(Rectangle())
    }

    private func pick(_ results: [CommandSearch.Result]) {
        guard results.indices.contains(highlighted) else { return }
        show(results[highlighted])
    }

    private func show(_ result: CommandSearch.Result) {
        close()
        Task { await model.show(command: result.commandID) }
    }

    private func close() {
        isOpen = false
        query = ""
    }
}
