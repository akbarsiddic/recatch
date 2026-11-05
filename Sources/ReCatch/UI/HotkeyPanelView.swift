import SwiftUI

/// Hotkey panel: Right now / What did I miss / Ask. Nonactivating panel, Esc dismisses.
struct HotkeyPanelView: View {
    @ObservedObject var model: PanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                modeButton("Right now", .now, key: "1")
                modeButton("What did I miss", .missed, key: "2")
                modeButton("Ask", .ask, key: "3")
            }
            if model.mode == .missed {
                HStack {
                    ForEach([(120, "2m"), (300, "5m"), (600, "10m")], id: \.0) { secs, label in
                        Button(label) { model.windowSec = secs; model.run() }
                            .buttonStyle(.link)
                            .fontWeight(model.windowSec == secs ? .semibold : .regular)
                    }
                    Button("Since you looked") { model.windowSec = 3600; model.run() }
                        .buttonStyle(.link)
                }.font(.caption)
            }
            if model.mode == .ask {
                TextField("Ask about the meeting so far…", text: $model.question, onCommit: { model.run() })
                    .textFieldStyle(.roundedBorder)
            }
            ScrollView {
                if model.isLoading, model.result.isEmpty {
                    ProgressView("Listening back…").frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(model.result.isEmpty ? "No speech heard." : model.result)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .frame(height: 220)
            if let err = model.errorMessage {
                HStack {
                    Text(err).font(.caption).foregroundColor(.red)
                    Spacer()
                    Button("Retry") { model.retry() }
                }
            }
            HStack {
                Text(model.asOf.isEmpty ? "—" : "as of \(model.asOf)")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                if model.isLoading {
                    Button("Stop") { model.cancel() }
                } else {
                    Button(model.verbose ? "Shorter" : "More") { model.verbose.toggle(); model.run() }
                }
            }
        }
        .padding(16).frame(width: 480)
        .onExitCommand { Task { @MainActor in HotkeyPanelController.dismiss() } }
    }

    private func modeButton(_ title: String, _ m: PanelViewModel.Mode, key: String) -> some View {
        Button(title) { model.mode = m; model.run() }
            .buttonStyle(.link)
            .fontWeight(model.mode == m ? .semibold : .regular)
            .keyboardShortcut(KeyEquivalent(Character(key)), modifiers: .command)
    }
}
