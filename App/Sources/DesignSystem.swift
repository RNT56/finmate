import SwiftUI

// MARK: - DesignSystem (Obsidian Liquid Glass) — docs/06 / docs/14
//
// Authentic iOS 26 Liquid Glass (`glassEffect`, `GlassEffectContainer`, `.glass`/
// `.glassProminent` button styles, scroll-edge effects) with a graceful Materials
// fallback on iOS 18–25 (docs/04 ADR-0004). One cohesive glass language: glass and
// content carry the depth over a near-flat neutral background — there is no ambient
// multi-color gradient. Tokens live in `DesignSystemTokens.swift`.

// MARK: - App background (near-flat neutral)

/// The Obsidian app background — a near-flat neutral surface that lets glass read on
/// top. No multi-color gradient: a whisper of bronze separates top from bottom only
/// enough to give the glass something to refract.
struct FinmateBackground: View {
    var body: some View {
        ZStack {
            FinmateColor.background
            // A barely-there vertical lift (a few % bronze) so flat glass still reads.
            LinearGradient(
                colors: [
                    FinmateColor.bronze.opacity(0.05),
                    Color.clear,
                    FinmateColor.ink.opacity(0.03),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

/// Deprecated alias kept so existing call sites compile; routes to `FinmateBackground`.
/// New code should use `FinmateBackground`.
struct FinmateGradient: View {
    var body: some View { FinmateBackground() }
}

// MARK: - Glass surfaces

/// Liquid Glass on iOS 26+, automatic Materials fallback on iOS 18–25 (docs/04 ADR-0004).
/// `tinted` opts a prominent surface into a subtle bronze tint.
struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = FinmateRadius.lg
    /// When true the glass carries a subtle bronze tint (for prominent surfaces).
    var tinted: Bool = false

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(glass(tinted: tinted), in: shape)
        } else {
            content
                .background(FinmateColor.glassFill, in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(FinmateColor.glassBorder, lineWidth: 0.75))
        }
    }

    @available(iOS 26.0, *)
    private func glass(tinted: Bool) -> Glass {
        tinted ? .regular.tint(FinmateColor.bronze.opacity(0.16)) : .regular
    }
}

extension View {
    /// Apply the Obsidian glass surface.
    func glassSurface(cornerRadius: CGFloat = FinmateRadius.lg, tinted: Bool = false) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius, tinted: tinted))
    }
}

/// A glass card container.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = FinmateRadius.lg
    var tinted: Bool = false
    var padding: CGFloat = FinmateSpacing.lg
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(GlassBackground(cornerRadius: cornerRadius, tinted: tinted))
    }
}

// MARK: - Scroll-edge effect helper

extension View {
    /// Apply the iOS 26 scroll-edge effect to a primary scroll/list surface (no-op on
    /// older OSes). Soft style keeps content legible as it passes under the glass nav.
    @ViewBuilder func finmateScrollEdge() -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
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
            VStack(alignment: .leading, spacing: FinmateSpacing.md) {
                Label(title, systemImage: "exclamationmark.triangle.fill")
                    .font(FinmateType.headline)
                    .foregroundStyle(FinmateColor.warning)
                Text(message)
                    .font(FinmateType.subheadline)
                    .foregroundStyle(FinmateColor.labelSecondary)
                GlassButton("Retry", systemImage: "arrow.clockwise",
                            kind: .secondary, size: .small, action: retry)
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
            HStack(spacing: FinmateSpacing.lg) {
                Circle().fill(FinmateColor.neutral.opacity(0.5)).frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: FinmateSpacing.xs + 2) {
                    Text("Placeholder name").font(FinmateType.headline)
                    Text("Placeholder secondary line").font(FinmateType.caption)
                }
                Spacer()
                Text("€00.00").font(FinmateType.money(.headline))
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
        VStack(spacing: FinmateSpacing.md) {
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
            .background(FinmateBackground())
        }
    }
}
