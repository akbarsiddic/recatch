import SwiftUI

/// Ask lives inside the dashboard. One window for everything except the floating overlay.
struct AskPane: View {
    @StateObject private var model = PanelSession.shared
    @StateObject private var capture = AudioCaptureManager.shared
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PaneHeader(title: "Ask",
                           subtitle: "Answers come from what has been said in this meeting, in its own language.")

                PaneCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            modeButton(.now, "Right now", "bolt.fill")
                            modeButton(.missed, "What did I miss", "clock.arrow.circlepath")
                            modeButton(.ask, "Question", "questionmark.bubble")
                            Spacer()
                            if model.mode == .missed {
                                Picker("", selection: $model.windowSec) {
                                    Text("Last 5 min").tag(300)
                                    Text("Last 15 min").tag(900)
                                    Text("Whole meeting").tag(0)
                                }
                                .labelsHidden().frame(width: 150)
                            }
                        }

                        if model.mode == .ask {
                            HStack(spacing: 8) {
                                TextField("Ask about this meeting…", text: $model.question)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($fieldFocused)
                                    .onSubmit { model.run() }
                                Button("Ask") { model.run() }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Brand.accent)
                                    .disabled(model.question.trimmingCharacters(in: .whitespaces).isEmpty || model.isLoading)
                            }
                        } else {
                            HStack(spacing: 8) {
                                Button(model.isLoading ? "Thinking…" : "Get answer") { model.run() }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Brand.accent)
                                    .disabled(model.isLoading)
                                if !model.asOf.isEmpty {
                                    Text("as of \(model.asOf)").font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }

                answerCard

                if capture.state != .listening {
                    Label("Not listening — start a meeting first.", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundColor(Brand.warn)
                }
            }
            .padding(20)
        }
        .onAppear { if model.mode == .ask { fieldFocused = true } }
    }

    private func modeButton(_ mode: PanelMode, _ title: String, _ icon: String) -> some View {
        Button {
            model.mode = mode
            if mode != .ask { model.run() } else { fieldFocused = true }
        } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.bordered)
        .tint(model.mode == mode ? Brand.accent : nil)
    }

    private var answerCard: some View {
        PaneCard {
            VStack(alignment: .leading, spacing: 8) {
                if model.isLoading {
                    HStack(spacing: 8) {
                        BrandDots()
                        Text("Reading the transcript…").font(.callout).foregroundColor(.secondary)
                    }
                }
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundColor(Brand.bad)
                } else if !model.emptyReason.isEmpty {
                    Text(model.emptyReason).font(.callout).foregroundColor(.secondary)
                } else if model.result.isEmpty {
                    Text("Pick one above. Answers are written in the meeting's language — ReCatch does not translate.")
                        .font(.callout).foregroundColor(.secondary)
                } else {
                    Text(model.result)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
