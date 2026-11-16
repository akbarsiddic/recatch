import SwiftUI

/// Ask lives inside the dashboard. One window for everything except the floating overlay.
/// Shaped like an AI chat: the thread is the page, the composer is pinned to the bottom.
struct AskPane: View {
    @StateObject private var model = PanelSession.shared
    @StateObject private var capture = AudioCaptureManager.shared
    @State private var turns: [ChatTurn] = []
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        PaneHeader(title: "Ask",
                                   subtitle: "Answers come from what has been said in this meeting, in its own language.")
                        if turns.isEmpty {
                            emptyState
                        } else {
                            ChatThreadView(turns: turns)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: model.result) { _, _ in scrollToBottom(proxy) }
                .onChange(of: turns.count) { _, _ in scrollToBottom(proxy) }
            }
            Divider()
            composer
        }
        // The engine streams into `result`; the thread mirrors it into the active turn.
        .onChange(of: model.result) { _, _ in sync() }
        .onChange(of: model.isLoading) { _, _ in sync() }
        .onChange(of: model.errorMessage) { _, _ in sync() }
        .onChange(of: model.emptyReason) { _, _ in sync() }
        .onAppear { focused = true }
    }

    // MARK: - Thread

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ask about this meeting")
                .font(.system(size: 15, weight: .semibold))
            Text("ReCatch answers from the transcript of the meeting that is running now. It does not translate — answers come back in the meeting's own language.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Start with **Right now** or **What did I miss** below, or type your own question.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func suggestion(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Brand.raised, in: Capsule())
                .overlay(Capsule().strokeBorder(Brand.line, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                suggestion("Right now", "bolt.fill") { ask(.now, "What's happening right now?") }
                suggestion("What did I miss", "clock.arrow.circlepath") { ask(.missed, "What did I miss?") }
                if model.mode == .missed {
                    Picker("", selection: $model.windowSec) {
                        Text("Last 5 min").tag(300)
                        Text("Last 15 min").tag(900)
                        Text("Whole meeting").tag(0)
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
                Spacer()
                if capture.state != .listening {
                    Label("Not listening", systemImage: "exclamationmark.circle")
                        .font(.caption2)
                        .foregroundStyle(Brand.warn)
                }
            }

            HStack(spacing: 8) {
                TextField("Ask about this meeting…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(canSend ? Brand.accent : Color.secondary.opacity(0.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help("Ask (⏎)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Brand.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Brand.line, lineWidth: 1)
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Brand.surface)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.isLoading
    }

    // MARK: - Actions

    private func send() {
        guard canSend else { return }
        let q = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        ask(.ask, q)
    }

    private func ask(_ mode: PanelMode, _ question: String) {
        model.cancel()
        turns.append(ChatTurn(question: question))
        model.mode = mode
        if mode == .ask { model.question = question }
        model.run()
    }

    private func sync() {
        guard let index = turns.indices.last else { return }
        if let error = model.errorMessage, !error.isEmpty {
            turns[index].error = error
            turns[index].answer = ""
            return
        }
        if model.result.isEmpty, !model.emptyReason.isEmpty {
            turns[index].error = model.emptyReason
            return
        }
        turns[index].answer = model.result
        turns[index].error = nil
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
    }
}
