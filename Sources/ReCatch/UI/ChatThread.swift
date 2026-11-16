import SwiftUI

/// One exchange in an Ask thread. `answer` fills in as tokens stream; `error` replaces it
/// when the run failed, so a failed question stays visible in the thread instead of vanishing.
struct ChatTurn: Identifiable, Equatable {
    let id: UUID
    let question: String
    var answer: String
    var error: String?

    init(id: UUID = UUID(), question: String, answer: String = "", error: String? = nil) {
        self.id = id
        self.question = question
        self.answer = answer
        self.error = error
    }
}

/// AI-chat shaped thread: your question in a bubble on the right, the answer as plain text on
/// the left under a small ReCatch mark. Shared by the dashboard and the overlay so both read as
/// the same product — the overlay just runs it at a smaller size.
struct ChatThreadView: View {
    var turns: [ChatTurn]
    var compact = false

    private var answerSize: CGFloat { compact ? 11.5 : 13 }
    private var bubbleSize: CGFloat { compact ? 11.5 : 12.5 }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 14 : 22) {
            ForEach(turns) { turn in
                VStack(alignment: .leading, spacing: compact ? 7 : 10) {
                    questionBubble(turn.question)
                    answerBlock(turn)
                }
            }
        }
    }

    private func questionBubble(_ text: String) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: compact ? 26 : 90)
            Text(text)
                .font(.system(size: bubbleSize, weight: .medium))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.horizontal, compact ? 9 : 12)
                .padding(.vertical, compact ? 6 : 8)
                .background(Brand.accent.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: compact ? 10 : 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: compact ? 10 : 13, style: .continuous)
                        .strokeBorder(Brand.accent.opacity(0.22), lineWidth: 1)
                )
        }
    }

    private func answerBlock(_ turn: ChatTurn) -> some View {
        HStack(alignment: .top, spacing: compact ? 7 : 9) {
            mark
            VStack(alignment: .leading, spacing: compact ? 3 : 5) {
                Text(Brand.name)
                    .font(.system(size: compact ? 9 : 10, weight: .bold))
                    .foregroundStyle(.secondary)
                if let e = turn.error, !e.isEmpty {
                    Text(e)
                        .font(.system(size: answerSize))
                        .foregroundStyle(Brand.warn)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                } else if turn.answer.isEmpty {
                    BrandDots()
                } else {
                    Text(Self.styled(turn.answer))
                        .font(.system(size: answerSize))
                        .lineSpacing(compact ? 1.5 : 3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var mark: some View {
        BrandMark(size: compact ? 16 : 20)
            .padding(.top, 1)
    }

    /// Answers come back as light markdown with `【m:ss】` citations. Render the bold/italics,
    /// and turn the full-width brackets into something that reads in Latin text.
    static func styled(_ raw: String) -> AttributedString {
        let normalized = raw
            .replacingOccurrences(of: "【", with: " (")
            .replacingOccurrences(of: "】", with: ")")
        if let attributed = try? AttributedString(
            markdown: normalized,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(normalized)
    }
}

/// Small uppercase section heading. Sections had no boundaries before, which is why
/// NOW / summary / chat ran together into one grey block.
struct SectionLabel: View {
    var title: String
    var compact = false

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: compact ? 9 : 10, weight: .bold))
            .tracking(0.9)
            .foregroundStyle(.secondary)
    }
}
