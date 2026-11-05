import SwiftUI

/// Hotkey panel: Right now / What did I miss / Ask. Nonactivating panel, Esc dismisses.
struct HotkeyPanelView: View {
    enum Mode { case now, missed, ask }
    @State var mode: Mode = .now
    @State var result: String = ""
    @State var asOf: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Right now") { mode = .now }
                Button("What did I miss") { mode = .missed }
                Button("Ask") { mode = .ask }
            }
            if mode == .missed {
                HStack {
                    Button("2m") {}; Button("5m") {}; Button("10m") {}; Button("Since looked") {}
                }.font(.caption)
            }
            ScrollView { Text(result.isEmpty ? "No speech heard." : result).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(height: 220)
            HStack {
                Text("as of \(asOf)").font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("Shorter") {}; Button("More") {}
            }
        }
        .padding(16).frame(width: 480)
    }
}
