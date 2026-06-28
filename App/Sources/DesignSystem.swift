import SwiftUI

// MARK: - DesignSystem (Liquid Glass) — docs/06 / docs/14
// In production these live in a `DesignSystem` SPM package (docs/03); for this
// first executable slice they ship in the app target. One cohesive glass language.

enum FinmateTokens {
    static let cornerRadius: CGFloat = 22
    static let cardPadding: CGFloat = 16
    static let spacing: CGFloat = 12
}

/// App background gradient (deferential, lets glass read on top).
struct FinmateGradient: View {
    var body: some View {
        LinearGradient(
            colors: [Color(.systemBackground), Color.accentColor.opacity(0.10)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

/// Liquid Glass on iOS 26+, automatic Materials fallback on iOS 18–25 (docs/04 ADR-0004).
struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = FinmateTokens.cornerRadius
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content.background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
    }
}

/// A glass card container.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = FinmateTokens.cornerRadius
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(FinmateTokens.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(GlassBackground(cornerRadius: cornerRadius))
    }
}

// MARK: - Loading / error states (M7 polish — docs/06 §a11y)

/// An inline error card with a Retry action. Used by feature views when a store's
/// load throws — the happy path never renders this.
struct ErrorStateCard: View {
    var title: String = "Couldn't load"
    let message: String
    var retry: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(action: retry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
        .accessibilityHint("Double tap to retry")
    }
}

/// A redacted placeholder row used as a skeleton while a store loads (instead of a
/// blank flash or a "—"). Honors `.redacted(reason: .placeholder)` from the caller.
struct SkeletonRow: View {
    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                Circle().fill(.secondary).frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Placeholder name").font(.headline)
                    Text("Placeholder secondary line").font(.caption)
                }
                Spacer()
                Text("€00.00").font(.headline.monospacedDigit())
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

/// A vertical stack of skeleton rows for list-style loading states.
struct SkeletonList: View {
    var count: Int = 3
    var body: some View {
        VStack(spacing: FinmateTokens.spacing) {
            ForEach(0..<count, id: \.self) { _ in SkeletonRow() }
        }
        .accessibilityLabel("Loading")
    }
}

struct PlaceholderView: View {
    let title: String
    let symbol: String
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                title,
                systemImage: symbol,
                description: Text("Arrives in a later milestone (see docs/08).")
            )
            .navigationTitle(title)
            .background(FinmateGradient())
        }
    }
}
