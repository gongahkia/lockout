import LockOutCore
import SwiftUI

enum LockOutPalette {
    static let sky = Color(red: 0.23, green: 0.48, blue: 0.91)
    static let mint = Color(red: 0.21, green: 0.66, blue: 0.56)
    static let amber = Color(red: 0.91, green: 0.63, blue: 0.23)
    static let coral = Color(red: 0.86, green: 0.36, blue: 0.39)
    static let slate = Color(red: 0.21, green: 0.25, blue: 0.34)
    static let mist = Color(red: 0.96, green: 0.98, blue: 1.0)
    static let separator = Color(nsColor: .separatorColor)
}

enum LockOutLayout {
    static let cornerRadius: CGFloat = 8
    static let iconCornerRadius: CGFloat = 6
}

struct LockOutSceneBackground: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()
    }
}

struct LockOutCard<Content: View>: View {
    let title: String?
    let subtitle: String?
    let icon: String?
    let accent: Color
    let content: Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        icon: String? = nil,
        accent: Color = LockOutPalette.sky,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 10) {
                        if let icon {
                            Image(systemName: icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(accent)
                                .frame(width: 28, height: 28)
                                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: LockOutLayout.iconCornerRadius))
                        }

                        if let title {
                            Text(title)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)
                        }

                        Spacer(minLength: 0)
                    }

                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            content
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: LockOutLayout.cornerRadius)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: LockOutLayout.cornerRadius)
                        .strokeBorder(LockOutPalette.separator.opacity(0.35), lineWidth: 1)
                )
        )
    }
}

struct LockOutScreenHeader: View {
    let title: String
    let subtitle: String
    let symbol: String
    let accent: Color

    init(title: String, subtitle: String, symbol: String, accent: Color = LockOutPalette.sky) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.accent = accent
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(accent, in: RoundedRectangle(cornerRadius: LockOutLayout.iconCornerRadius))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

struct LockOutMetricTile: View {
    let value: String
    let label: String
    let detail: String?
    let accent: Color

    init(value: String, label: String, detail: String? = nil, accent: Color = LockOutPalette.sky) {
        self.value = value
        self.label = label
        self.detail = detail
        self.accent = accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Capsule()
                .fill(accent)
                .frame(width: 42, height: 6)

            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()

            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: LockOutLayout.cornerRadius)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: LockOutLayout.cornerRadius)
                        .strokeBorder(accent.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

enum LockOutBadgeTone {
    case neutral
    case info
    case success
    case warning
    case critical

    var foreground: Color {
        switch self {
        case .neutral:
            return LockOutPalette.slate
        case .info:
            return LockOutPalette.sky
        case .success:
            return LockOutPalette.mint
        case .warning:
            return LockOutPalette.amber
        case .critical:
            return LockOutPalette.coral
        }
    }

    var background: Color {
        foreground.opacity(0.14)
    }
}

struct LockOutStatusBadge: View {
    let title: String
    let tone: LockOutBadgeTone

    init(_ title: String, tone: LockOutBadgeTone = .neutral) {
        self.title = title
        self.tone = tone
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(tone.background, in: Capsule())
    }
}

struct LockOutEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    let accent: Color

    init(
        symbol: String,
        title: String,
        message: String,
        accent: Color = LockOutPalette.sky
    ) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.accent = accent
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 62, height: 62)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: LockOutLayout.cornerRadius))

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}

struct LockOutKeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.primary)
        }
        .font(.subheadline)
    }
}

struct LockOutInsightRow: View {
    let card: InsightCard
    let accent: Color

    init(card: InsightCard, accent: Color = LockOutPalette.sky) {
        self.card = card
        self.accent = accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.title)
                .font(.subheadline.weight(.semibold))

            Text(card.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(card.recommendation)
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: LockOutLayout.cornerRadius)
                .fill(accent.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: LockOutLayout.cornerRadius)
                        .strokeBorder(accent.opacity(0.12), lineWidth: 1)
                )
        )
    }
}
