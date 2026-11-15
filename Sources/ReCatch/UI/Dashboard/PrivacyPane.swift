import SwiftUI

/// Privacy: what is stored, for how long, and exactly what has left this machine.
struct PrivacyPane: View {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var capture = AudioCaptureManager.shared
    @State private var log: [MeetingStore.LLMLogEntry] = []
    @State private var storage = "—"
    @State private var confirmDelete = false
    @State private var flash: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PaneHeader(title: "Privacy", subtitle: "Audio never leaves this Mac.")
                promiseCard
                retentionCard
                networkCard
                dangerCard
            }
            .padding(20)
        }
        .onAppear(perform: reload)
    }

    private var promiseCard: some View {
        PaneCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Audio is transcribed on this Mac and discarded.", systemImage: "waveform.badge.mic")
                    .font(.callout).bold()
                Text("Only the transcript window you asked about is sent to your provider — never audio, never the whole meeting. Every request is listed below.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private var retentionCard: some View {
        PaneCard(title: "Storage") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Keep transcripts for").font(.callout)
                    Picker("", selection: $settings.retentionDays) {
                        ForEach([1, 3, 7, 14, 30], id: \.self) { Text("\($0) days").tag($0) }
                    }
                    .labelsHidden().frame(width: 110)
                    Spacer()
                    Text(storage).font(.callout).bold().monospacedDigit()
                }
                Text("Older transcripts are deleted automatically, hourly.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private var networkCard: some View {
        PaneCard(title: "What left this machine") {
            if log.isEmpty {
                Text("Nothing sent yet. Ask a question with ⌥⌘R and it will show up here — timestamp and size only, never content.")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 4) {
                    ForEach(log, id: \.t) { e in
                        HStack {
                            Text(Self.date.string(from: Date(timeIntervalSince1970: TimeInterval(e.t) / 1000)))
                            Spacer()
                            Text("\(e.provider) · \(e.model)").foregroundColor(.secondary).lineLimit(1)
                            Text("↑\(e.tokensIn) ↓\(e.tokensOut)").foregroundColor(.secondary).monospacedDigit()
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    private var dangerCard: some View {
        PaneCard(title: "Delete") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remove every transcript and request log.").font(.callout)
                    Text("This cannot be undone.").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button("Delete everything now", role: .destructive) { confirmDelete = true }
                    .buttonStyle(.bordered)
            }
            if let flash {
                Text(flash).font(.caption).foregroundColor(Brand.ok)
            }
        }
        .confirmationDialog("Delete all transcripts?", isPresented: $confirmDelete) {
            Button("Delete everything", role: .destructive) { deleteAll() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func deleteAll() {
        if capture.state == .listening { Task { await capture.stopMeeting() } }
        try? FileManager.default.removeItem(at: dbURL())
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: dbURL().path + suffix))
        }
        TranscriptFeed.shared.reset()
        NotificationCenter.default.post(name: .recatchMeetingsChanged, object: nil)
        flash = "Deleted."
        reload()
    }

    private func reload() {
        guard let store = try? MeetingStore(path: AudioCaptureManager.defaultDBPath()) else { return }
        log = (try? store.fetchLLMLog(limit: 40)) ?? []
        storage = ByteCountFormatter.string(fromByteCount: store.storageBytes(), countStyle: .file)
    }

    private func dbURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReCatch.sqlite")
    }

    private static let date: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
        return f
    }()
}
