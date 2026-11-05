import SwiftUI

/// P0 debug window: two live labeled sections Me / Others with mm:ss. Verifies M0 exit.
/// `status` carries chunk/VAD/model diagnostics so a silent pipeline is diagnosable, not just "Waiting".
struct DebugTranscriptView: View {
    var lines: [(id: UUID, who: String, text: String)] = []
    var status: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BrandHeader(status: lines.isEmpty ? "Waiting" : "\(lines.count) lines")
            if !status.isEmpty {
                Text(status).font(.caption).foregroundColor(.secondary)
            }
            if lines.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "mic.badge.plus").foregroundStyle(Brand.accent)
                    Text("Start listening and talk — lines appear here live, Me on the left, Others on the right.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    column("Me", lines.filter { $0.who == "Me" }, system: "person.fill", tone: Brand.accent)
                    Divider()
                    column("Others", lines.filter { $0.who == "Others" }, system: "person.2.fill", tone: .purple)
                }
            }
        }.padding(12).frame(width: 600, height: 380)
    }

    private func column(_ title: String, _ rows: [(id: UUID, who: String, text: String)], system: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: system).foregroundStyle(tone)
                Text(title).font(.headline)
                Text("\(rows.count)").font(.caption).foregroundColor(.secondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(rows, id: \.id) { Text($0.text).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(8).frame(minWidth: 260)
    }
}

/// M4 overlay pill: off by default, draggable, collapsible, opacity slider.
struct OverlayPillView: View {
    @Binding var nowLine: String
    @State var expanded = false
    @State var opacity = 0.9
    var body: some View {
        Group {
            if expanded { Text(nowLine).padding(8).background(.thinMaterial).opacity(opacity) }
            else { Circle().frame(width: 12, height: 12) }
        }
        .onTapGesture { expanded.toggle() }
    }
}
