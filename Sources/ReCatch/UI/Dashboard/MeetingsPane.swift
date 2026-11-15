import SwiftUI

/// History of everything ReCatch heard. Kept deliberately plain: list → transcript → rename/delete.
struct MeetingsPane: View {
    @State private var meetings: [MeetingStore.MeetingSummary] = []
    @State private var selected: UUID?
    @State private var segments: [TranscriptSegment] = []
    @State private var renaming: UUID?
    @State private var renameText = ""
    @State private var error: String?

    private let store: MeetingStore? = try? MeetingStore(path: AudioCaptureManager.defaultDBPath())

    var body: some View {
        HSplitView {
            list
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
            detail
                .frame(minWidth: 420, maxWidth: .infinity)
        }
        .onAppear(perform: load)
        .onReceive(NotificationCenter.default.publisher(for: .recatchMeetingsChanged)) { _ in load() }
    }

    // MARK: List

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                PaneHeader(title: "Meetings", subtitle: "\(meetings.count) stored")
                Spacer()
                Button {
                    load()
                } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Refresh")
            }
            .padding(16)
            Divider()

            if meetings.isEmpty {
                emptyState
            } else {
                List(selection: $selected) {
                    ForEach(groupedByDay, id: \.day) { group in
                        Section(header: Text(group.day).font(.caption).foregroundColor(.secondary)) {
                            ForEach(group.items) { m in
                                row(m).tag(m.id)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .onChange(of: selected) { _, id in loadSegments(id) }
            }
        }
    }

    private func row(_ m: MeetingStore.MeetingSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if renaming == m.id {
                    TextField("Name", text: $renameText, onCommit: { commitRename(m.id) })
                        .textFieldStyle(.roundedBorder)
                        .onExitCommand { renaming = nil }
                } else {
                    Text(m.title.isEmpty ? "Meeting" : m.title)
                        .font(.callout).bold()
                        .lineLimit(1)
                }
                Spacer()
                Text(timeRange(m)).font(.caption2).foregroundColor(.secondary)
            }
            HStack(spacing: 6) {
                Text("\(m.segments) lines").font(.caption2).foregroundColor(.secondary)
                if let d = m.duration, d > 0, d < 86_400 {
                    Text("·").font(.caption2).foregroundColor(.secondary)
                    Text(durationText(d)).font(.caption2).foregroundColor(.secondary)
                }
            }
            if !m.preview.isEmpty {
                Text(m.preview).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("Rename…") { startRename(m) }
            Button("Delete", role: .destructive) { delete(m.id) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray").font(.largeTitle).foregroundColor(.secondary)
            Text("No meetings yet").font(.callout)
            Text("Start listening and everything you hear lands here.")
                .font(.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let id = selected, let m = meetings.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(m.title.isEmpty ? "Meeting" : m.title).font(.title3).bold()
                        Text("\(m.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(m.segments) lines")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Rename") { startRename(m) }
                        .buttonStyle(.bordered)
                    Button(role: .destructive) { delete(m.id) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(16)
                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(segments) { seg in
                            HStack(alignment: .top, spacing: 10) {
                                Text(timestamp(seg.tStartMs))
                                    .font(.caption2).monospacedDigit()
                                    .foregroundColor(.secondary)
                                    .frame(width: 46, alignment: .trailing)
                                Text(seg.text)
                                    .font(.callout)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "text.bubble").font(.largeTitle).foregroundColor(.secondary)
                Text("Pick a meeting to read its transcript").foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Data

    private func load() {
        guard let store else { error = "Cannot open the transcript store."; return }
        meetings = (try? store.listMeetings()) ?? []
        if let id = selected, !meetings.contains(where: { $0.id == id }) { selected = nil; segments = [] }
        if selected == nil, let first = meetings.first { selected = first.id; loadSegments(first.id) }
    }

    private func loadSegments(_ id: UUID?) {
        guard let id, let store else { segments = []; return }
        segments = (try? store.fetchSegments(meetingId: id)) ?? []
    }

    private func startRename(_ m: MeetingStore.MeetingSummary) {
        renaming = m.id
        renameText = m.title
    }

    private func commitRename(_ id: UUID) {
        guard let store else { return }
        try? store.renameMeeting(id: id, title: renameText.trimmingCharacters(in: .whitespaces))
        renaming = nil
        load()
    }

    private func delete(_ id: UUID) {
        guard let store else { return }
        try? store.deleteMeeting(id: id)
        if selected == id { selected = nil; segments = [] }
        load()
    }

    // MARK: Formatting

    private var groupedByDay: [(day: String, items: [MeetingStore.MeetingSummary])] {
        let cal = Calendar.current
        var order: [String] = []
        var buckets: [String: [MeetingStore.MeetingSummary]] = [:]
        for m in meetings {
            let day = cal.isDateInToday(m.startedAt) ? "Today"
                : cal.isDateInYesterday(m.startedAt) ? "Yesterday"
                : m.startedAt.formatted(date: .abbreviated, time: .omitted)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(m)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    private func timeRange(_ m: MeetingStore.MeetingSummary) -> String {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        let start = f.string(from: m.startedAt)
        guard let end = m.endedAt else { return start }
        return "\(start)–\(f.string(from: end))"
    }

    private func durationText(_ d: TimeInterval) -> String {
        let mins = Int(d / 60)
        return mins < 1 ? "<1 min" : "\(mins) min"
    }

    private func timestamp(_ ms: Int64) -> String {
        let s = Int(ms / 1000)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

extension Notification.Name {
    /// Posted when a meeting ends so the list refreshes without polling.
    static let recatchMeetingsChanged = Notification.Name("recatch.meetingsChanged")
}
