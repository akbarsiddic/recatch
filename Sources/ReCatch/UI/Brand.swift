import SwiftUI

/// ReCatch brand: one accent, one radius, one header style, everywhere.
enum Brand {
    static let name = "ReCatch"
    static let tagline = "Never ask “what did I miss?” again."

    /// Brand coral #FF5A36 — reads on light and dark.
    static let accent = Color(red: 1.0, green: 0.353, blue: 0.212)
    static let accentSoft = Color(red: 1.0, green: 0.353, blue: 0.212).opacity(0.12)
    static let warn = Color.orange
    static let bad = Color.red
    static let ok = Color.green
    /// Brand yellow #FFD23F — the dot in the ReCatch mark.
    static let yellow = Color(red: 1.0, green: 0.824, blue: 0.247)
    static let radius: CGFloat = 12

    // MARK: - Surfaces
    // Warm off-white, StreamLingo-ish: a page that isn't pure white and cards that aren't gray.
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let raised = Color(nsColor: .textBackgroundColor)
    static let line = Color.primary.opacity(0.08)
    static let ink = Color.primary
    static let muted = Color.secondary

    /// Card radius used by panels and settings rows.
    static let cardRadius: CGFloat = 16
    /// Large radius for the floating overlay.
    static let overlayRadius: CGFloat = 20

}

/// The ReCatch mark — a coral three-quarter arc with a yellow dot in the opening.
struct BrandMark: View {
    var size: CGFloat = 24
    var tint: Color = Brand.accent
    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.12, to: 0.88)
                .stroke(tint, style: StrokeStyle(lineWidth: size * 0.26, lineCap: .round))
                .padding(size * 0.14)
            Circle()
                .fill(Brand.yellow)
                .frame(width: size * 0.22, height: size * 0.22)
                .offset(x: size * 0.24)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Branded panel/window header: mark + name + live status pill.
struct BrandHeader: View {
    var status: String
    var tone: Color = Brand.accent
    var body: some View {
        HStack(spacing: 8) {
            BrandMark(size: 22, tint: tone)
            VStack(alignment: .leading, spacing: 0) {
                Text(Brand.name).font(.headline)
                Text(Brand.tagline).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text(status)
                .font(.caption).bold()
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(tone.opacity(0.14))
                .foregroundStyle(tone)
                .clipShape(Capsule())
        }
    }
}

/// Accent text button — use instead of `.buttonStyle(.link)` (consistent brand,
/// renders everywhere).
struct BrandLink: View {
    var title: String
    var action: () -> Void
    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .fontWeight(.semibold)
            .foregroundStyle(Brand.accent)
    }
}

/// Three-dot "working" indicator. Static dots preview everywhere (unlike ProgressView's spinner).
struct BrandDots: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Brand.accent.opacity([1, 0.55, 0.3][i]))
                    .frame(width: 7, height: 7)
            }
        }.accessibilityLabel("Working")
    }
}

/// Card container used across panel, settings and debug.
struct BrandCard<Content: View>: View {
    var content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(10)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Brand.radius))
    }
}

/// Level meter: 12 blocks, fills with brand accent. Pure (previewable).
struct LevelMeter: View {
    var level: Double // 0...1
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<12, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Double(i) / 12.0 < level ? Brand.accent : Color.secondary.opacity(0.25))
                    .frame(width: 5, height: 14)
            }
        }.accessibilityLabel("Mic level")
    }
}
