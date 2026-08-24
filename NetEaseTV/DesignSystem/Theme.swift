import SwiftUI

enum TVTheme {
    static let accent = Color(red: 1.0, green: 0.22, blue: 0.30)
    static let magenta = Color(red: 0.87, green: 0.18, blue: 0.55)
    static let amber = Color(red: 1.0, green: 0.52, blue: 0.20)
    static let background = Color(red: 0.018, green: 0.022, blue: 0.045)
    static let surface = Color.white.opacity(0.075)
    static let elevatedSurface = Color.white.opacity(0.12)
    static let secondaryText = Color.white.opacity(0.62)
    static let horizontalPadding: CGFloat = 76
    static let cardPadding: CGFloat = 14
    static let sectionSpacing: CGFloat = 52
}

struct TVBackground: View {
    var tint: Color = TVTheme.magenta

    var body: some View {
        ZStack {
            TVTheme.background
            RadialGradient(
                colors: [tint.opacity(0.20), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 1_000
            )
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.38)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

struct GlassPanelModifier: ViewModifier {
    var cornerRadius: CGFloat = 26

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
    }
}

struct TVCardButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var cornerRadius: CGFloat = 24
    var contentPadding: CGFloat = TVTheme.cardPadding
    var focusedScale: CGFloat = 1.035

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(contentPadding)
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isFocused ? Color.white : TVTheme.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(isFocused ? 0.92 : 0.10), lineWidth: isFocused ? 3 : 1)
            }
            .scaleEffect(isFocused && !reduceMotion ? focusedScale : (configuration.isPressed ? 0.985 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.46 : 0.16), radius: isFocused ? 28 : 10, y: isFocused ? 14 : 5)
            .opacity(isEnabled ? 1 : 0.38)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isFocused)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

struct TVHeroButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .overlay {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(Color.white.opacity(isFocused ? 0.95 : 0.12), lineWidth: isFocused ? 4 : 1)
            }
            .scaleEffect(isFocused && !reduceMotion ? 1.025 : (configuration.isPressed ? 0.99 : 1))
            .brightness(isFocused ? 0.06 : 0)
            .shadow(color: .black.opacity(isFocused ? 0.48 : 0.20), radius: isFocused ? 34 : 14, y: isFocused ? 16 : 7)
            .opacity(isEnabled ? 1 : 0.38)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isFocused)
    }
}

struct TVPillButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var tint: Color = TVTheme.accent
    var prominent = false
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 24)
            .padding(.vertical, 13)
            .foregroundStyle(foregroundColor)
            .background(Capsule().fill(backgroundColor))
            .overlay {
                Capsule()
                    .stroke(borderColor, lineWidth: isFocused ? 3 : 1)
            }
            .scaleEffect(isFocused && !reduceMotion ? 1.06 : (configuration.isPressed ? 0.97 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.38 : 0.10), radius: isFocused ? 18 : 6, y: isFocused ? 8 : 3)
            .opacity(isEnabled ? 1 : 0.38)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isFocused)
    }

    private var foregroundColor: Color {
        if isFocused { return prominent ? .black : .black }
        if destructive { return TVTheme.accent }
        return .white
    }

    private var backgroundColor: Color {
        if isFocused { return .white }
        if prominent { return tint }
        if destructive { return TVTheme.accent.opacity(0.14) }
        return TVTheme.elevatedSurface
    }

    private var borderColor: Color {
        if isFocused { return .white.opacity(0.95) }
        if destructive { return TVTheme.accent.opacity(0.55) }
        return .white.opacity(0.14)
    }
}

struct TVIconButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var size: CGFloat = 58
    var prominent = false
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2.weight(.semibold))
            .frame(width: size, height: size)
            .foregroundStyle(active ? TVTheme.accent : (isFocused || prominent ? Color.black : Color.white))
            .background(Circle().fill(isFocused || prominent ? Color.white : TVTheme.elevatedSurface))
            .overlay {
                Circle().stroke(Color.white.opacity(isFocused ? 0.95 : 0.12), lineWidth: isFocused ? 3 : 1)
            }
            .scaleEffect(isFocused && !reduceMotion ? 1.12 : (configuration.isPressed ? 0.94 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.42 : 0.12), radius: isFocused ? 18 : 6, y: isFocused ? 9 : 3)
            .opacity(isEnabled ? 1 : 0.34)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isFocused)
    }
}

struct TVPlaybackButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var size: CGFloat = 58
    var prominent = false
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: prominent ? 31 : 24, weight: .semibold))
            .frame(width: size, height: size)
            .foregroundStyle(isFocused ? Color.black : (active ? TVTheme.accent : Color.white.opacity(0.92)))
            .background {
                Circle()
                    .fill(isFocused ? Color.white : (prominent ? Color.white.opacity(0.13) : Color.clear))
            }
            .overlay {
                if prominent && !isFocused {
                    Circle().stroke(Color.white.opacity(0.16), lineWidth: 1)
                }
            }
            .scaleEffect(isFocused && !reduceMotion ? 1.11 : (configuration.isPressed ? 0.94 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.38 : 0), radius: 16, y: 8)
            .opacity(isEnabled ? 1 : 0.28)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isFocused)
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 26) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius))
    }
}

struct LoadStateView: View {
    let title: String
    var message: String?
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: retry == nil ? "waveform" : "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                .font(.system(size: 54, weight: .medium))
                .foregroundStyle(TVTheme.accent)
            Text(title)
                .font(.title2.bold())
            if let message {
                Text(message)
                    .font(.body)
                    .foregroundStyle(TVTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 700)
            }
            if let retry {
                Button("重试", action: retry)
                    .buttonStyle(TVPillButtonStyle(prominent: true))
            } else {
                ProgressView()
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView: View {
    let title: String
    var message: String?
    var symbol = "music.note"

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 50, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
            Text(title)
                .font(.title2.bold())
            if let message {
                Text(message)
                    .font(.headline)
                    .foregroundStyle(TVTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
