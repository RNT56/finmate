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
