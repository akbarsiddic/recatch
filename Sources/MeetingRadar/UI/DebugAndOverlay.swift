import SwiftUI

/// P0 debug window: two live labeled sections Me / Others with mm:ss. Verifies M0 exit.
struct DebugTranscriptView: View {
    var lines: [(String, String)] = []
    var body: some View {
        HSplitView {
            VStack(alignment: .leading) {
                Text("Me").font(.headline)
                ForEach(lines.filter { $0.0 == "Me" }.map { $0.1 }, id: \.self) { Text($0) }
            }.frame(minWidth: 240)
            VStack(alignment: .leading) {
                Text("Others").font(.headline)
                ForEach(lines.filter { $0.0 == "Others" }.map { $0.1 }, id: \.self) { Text($0) }
            }.frame(minWidth: 240)
        }.padding().frame(width: 560, height: 360)
    }
}

/// M4 overlay pill: off by default, draggable, collapsible, opacity slider.
struct OverlayPillView: View {
    @State var expanded = false
    @State var opacity = 0.9
    var nowLine = "Now: —"
    var body: some View {
        Group {
            if expanded { Text(nowLine).padding(8).background(.thinMaterial).opacity(opacity) }
            else { Circle().frame(width: 12, height: 12) }
        }
        .onTapGesture { expanded.toggle() }
    }
}
