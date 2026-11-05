import SwiftUI

/// Empty-state explainer (why there's no answer yet). Extracted so it renders
/// identically in the panel and in headless previews.
struct PanelEmptyReason: View {
    var text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "ear.badge.checkmark")
                .foregroundStyle(Brand.accent)
            Text(text.isEmpty ? "No speech heard." : text)
                .foregroundColor(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Hotkey panel: Right now / What did I miss / Ask. Nonactivating panel, Esc dismisses.
struct HotkeyPanelView: View {
    @ObservedObject var model: PanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BrandHeader(status: statusText, tone: statusTone)
            HStack(spacing: 4) {
                modeButton("Right now", .now, key: "1")
                modeButton("What did I miss", .missed, key: "2")
                modeButton("Ask", .ask, key: "3")
            }
            .buttonStyle(.plain)
            if model.mode == .missed {
                HStack(spacing: 10) {
                    ForEach([(120, "2m"), (300, "5m"), (600, "10m")], id: \.0) { secs, label in
                        windowChip(label, selected: model.windowSec == secs) {
                            model.windowSec = secs; model.run()
                        }
                    }
                    windowChip("Since you looked", selected: model.windowSec == 3600) {
                        model.windowSec = 3600; model.run()
                    }
                }.font(.caption)
            }
            if model.mode == .ask {
                TextField("Ask about the meeting so far…", text: $model.question, onCommit: { model.run() })
                    .textFieldStyle(.roundedBorder)
            }
            BrandCard {
                ScrollView {
                    if model.isLoading, model.result.isEmpty {
                        HStack(spacing: 8) {
                            BrandDots()
                            Text("Listening back…").foregroundColor(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    } else if model.result.isEmpty {
                        PanelEmptyReason(text: model.emptyReason)
                    } else {
                        Text(model.result)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .frame(height: 220)
            }
            if let err = model.errorMessage {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warn)
                    Text(err).font(.caption)
                    Spacer()
                    BrandLink(title: "Retry") { model.retry() }
                }
            }
            HStack {
                Text(model.asOf.isEmpty ? "—" : "as of \(model.asOf)")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                if model.isLoading {
                    BrandLink(title: "Stop") { model.cancel() }
                } else {
                    BrandLink(title: model.verbose ? "Shorter" : "More") { model.verbose.toggle(); model.run() }
                }
            }
        }
        .padding(16).frame(width: 500)
        .onExitCommand { Task { @MainActor in HotkeyPanelController.dismiss() } }
    }

    private var statusText: String {
        if model.isLoading { return "Thinking…" }
        if !model.result.isEmpty { return "Answered" }
        return model.mode == .ask ? "Ask" : model.mode == .missed ? "Catch up" : "Live"
    }

    private var statusTone: Color {
        model.errorMessage == nil ? Brand.accent : Brand.warn
    }

    private func modeButton(_ title: String, _ m: PanelViewModel.Mode, key: String) -> some View {
        Button(title) { model.mode = m; model.run() }
            .fontWeight(model.mode == m ? .semibold : .regular)
            .foregroundStyle(model.mode == m ? Brand.accent : Color.primary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(model.mode == m ? Brand.accentSoft : Color.clear)
            .clipShape(Capsule())
            .keyboardShortcut(KeyEquivalent(Character(key)), modifiers: .command)
    }

    private func windowChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .fontWeight(selected ? .semibold : .regular)
            .foregroundStyle(selected ? .white : Brand.accent)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(selected ? Brand.accent : Brand.accentSoft)
            .clipShape(Capsule())
    }
}
