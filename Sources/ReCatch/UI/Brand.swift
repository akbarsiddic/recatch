import SwiftUI

/// ReCatch brand: one accent, one radius, one header style, everywhere.
enum Brand {
    static let name = "ReCatch"
    static let tagline = "Never ask “what did I miss?” again."

    /// Deep lagoon teal — reads on light and dark.
    static let accent = Color(red: 0.04, green: 0.52, blue: 0.51)
    static let accentSoft = Color(red: 0.04, green: 0.52, blue: 0.51).opacity(0.12)
    static let warn = Color.orange
    static let bad = Color.red
    static let ok = Color.green
    static let radius: CGFloat = 12
}

/// Branded panel/window header: mark + name + live status pill.
struct BrandHeader: View {
    var status: String
    var tone: Color = Brand.accent
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundStyle(tone)
                .accessibilityHidden(true)
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
