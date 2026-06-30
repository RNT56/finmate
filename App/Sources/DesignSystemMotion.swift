import SwiftUI

// MARK: - DesignSystem motion / micro-interactions — docs/06 §motion
//
// The motion layer for the Obsidian design language: reduce-motion-gated spring
// helpers, a consistent button press-feedback style, an iOS-26 GlassEffectContainer
// wrapper (no-op fallback ≤25), and a glassEffectID morph helper. Every animation
// here resolves to `nil` when `accessibilityReduceMotion` is on, so motion is opt-in
// per the system setting. Animations stay SUBTLE + FAST (FinmateMotion tokens).
//
// Nothing here changes layout, data, or logic — it is presentation-only polish.

// MARK: - GlassEffectContainer wrapper (iOS 26) with a no-op fallback ≤25

/// Wraps related glass surfaces so iOS 26 can blend/merge them correctly (and so
/// `glassEffectID` morphs are matched within one namespace). On iOS 18–25 this is a
/// transparent pass-through `VStack`-free container — it simply renders the content,
/// keeping layout identical.
struct FinmateGlassGroup<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder var content: () -> Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

// MARK: - glassEffectID morph helper

extension View {
    /// Tag a glass surface with a `glassEffectID` for matched-geometry morph
    /// transitions inside a `FinmateGlassGroup` / `GlassEffectContainer`. No-op on
    /// iOS 18–25 and a clean pass-through when `reduceMotion` is on (so morphs never
    /// fight the reduce-motion setting). `id` must be `Hashable`.
    @ViewBuilder
    func finmateGlassMorph(
        id: some Hashable & Sendable,
        in namespace: Namespace.ID,
        reduceMotion: Bool
    ) -> some View {
        if #available(iOS 26.0, *), !reduceMotion {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }
}

// MARK: - Button press feedback

/// Press-feedback transform layered over an already-styled button. Because the system
/// glass/bordered button styles consume the tap, we observe press state with a
/// zero-distance `DragGesture` added *simultaneously* (it never consumes the tap or
/// changes hit-testing) purely to drive a subtle scale/opacity transform. Reduce-motion
/// disables the transform entirely (the gesture stays inert).
struct PressScale: ViewModifier {
    var reduceMotion: Bool
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(isPressed && !reduceMotion ? 0.9 : 1)
            .animation(reduceMotion ? nil : FinmateMotion.fastEase, value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !isPressed { isPressed = true } }
                    .onEnded { _ in isPressed = false }
            )
    }
}

// MARK: - Glass appearance transition

extension AnyTransition {
    /// A subtle insert/remove transition for list rows + dashboard cards.
    static var finmateRow: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.96).combined(with: .opacity),
            removal: .opacity
        )
    }
}
