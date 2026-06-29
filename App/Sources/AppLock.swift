import SwiftUI
import Observation
import LocalAuthentication
import Domain

// MARK: - Biometric app lock runtime (docs/07 §9.x, docs/02 §12)
//
// Wires the M7 Settings "Require Face ID / Touch ID" toggle to a real
// LocalAuthentication gate. When `biometricLockEnabled` is on, a glass
// "Unlock Finmate" overlay covers RootView on launch and whenever the app
// returns from the background, until the user authenticates. The app auto-locks
// when it leaves the foreground. When the toggle is OFF (the default) this is a
// complete no-op — the overlay never shows and the build/boot is unaffected.

/// Authentication backend abstraction so the controller is testable and so the
/// LAContext detail stays in one place. Returns `.deviceOwnerAuthenticationWithBiometrics`
/// when available, falling back to `.deviceOwnerAuthentication` (device passcode).
protocol BiometricAuthenticator: Sendable {
    func authenticate(reason: String) async -> Bool
}

/// LocalAuthentication-backed authenticator (LAContext).
struct LocalAuthenticationAuthenticator: BiometricAuthenticator {
    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Enter Passcode"

        // Prefer biometrics; fall back to passcode (covers no-biometrics devices,
        // lockout, and simulators) per docs/07.
        var policy: LAPolicy = .deviceOwnerAuthenticationWithBiometrics
        var error: NSError?
        if !context.canEvaluatePolicy(policy, error: &error) {
            policy = .deviceOwnerAuthentication
        }

        do {
            return try await context.evaluatePolicy(policy, localizedReason: reason)
        } catch {
            return false
        }
    }
}

/// Drives the locked/unlocked state. `@MainActor @Observable` so the overlay
/// binds to `isLocked` directly. No-op while `preferencesStore.biometricLockEnabled`
/// is false.
@MainActor
@Observable
final class AppLockController {
    /// True when the lock overlay should cover the app. Starts `false`; `start()`
    /// locks immediately if the preference is on.
    private(set) var isLocked = false
    /// True while an authentication prompt is in flight (debounces taps / phase churn).
    private(set) var isAuthenticating = false

    private let preferencesStore: PreferencesStore
    private let authenticator: BiometricAuthenticator

    init(preferencesStore: PreferencesStore,
         authenticator: BiometricAuthenticator = LocalAuthenticationAuthenticator()) {
        self.preferencesStore = preferencesStore
        self.authenticator = authenticator
    }

    private var lockEnabled: Bool { preferencesStore.preferences.biometricLockEnabled }

    /// Called once at launch (after preferences load). Locks if enabled, then
    /// triggers the first authentication.
    func start() {
        guard lockEnabled else { isLocked = false; return }
        isLocked = true
        Task { await authenticate() }
    }

    /// Lock when leaving the foreground (background/inactive). No-op when disabled.
    func lockForBackground() {
        guard lockEnabled else { isLocked = false; return }
        isLocked = true
    }

    /// Returning to the foreground: if locked, prompt to unlock.
    func didBecomeActive() {
        guard lockEnabled else { isLocked = false; return }
        if isLocked { Task { await authenticate() } }
    }

    /// Run the LocalAuthentication prompt; unlock on success. Re-entrant-safe.
    func authenticate() async {
        guard lockEnabled, isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        let ok = await authenticator.authenticate(reason: "Unlock Finmate to view your finances")
        isAuthenticating = false
        if ok { isLocked = false }
    }
}

// MARK: - Locked overlay UI (Liquid Glass)

/// The "Unlock Finmate" cover shown while `AppLockController.isLocked`.
struct AppLockOverlay: View {
    let controller: AppLockController

    /// Lock-glyph size — scales with Dynamic Type alongside the title.
    @ScaledMetric(relativeTo: .title2) private var lockIconSize: CGFloat = 44

    var body: some View {
        ZStack {
            FinmateBackground().ignoresSafeArea()
            GlassCard {
                VStack(spacing: FinmateSpacing.lg) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: lockIconSize, weight: .semibold))
                        .foregroundStyle(FinmateColor.bronze)
                        .accessibilityHidden(true)
                    Text("Finmate is locked")
                        .font(FinmateType.title2.weight(.bold))
                    Text("Authenticate to view your finances.")
                        .font(FinmateType.subheadline)
                        .foregroundStyle(FinmateColor.labelSecondary)
                        .multilineTextAlignment(.center)
                    Button {
                        Task { await controller.authenticate() }
                    } label: {
                        Label("Unlock with Face ID", systemImage: "faceid")
                            .frame(maxWidth: .infinity)
                    }
                    .finmateProminent()
                    .controlSize(.large)
                    .disabled(controller.isAuthenticating)
                    .accessibilityLabel("Unlock Finmate with Face ID or Touch ID")
                }
                .padding(.vertical, FinmateSpacing.sm)
            }
            .padding(.horizontal, FinmateSpacing.xxxl)
            .frame(maxWidth: 400)
        }
        .transition(.opacity)
        // Privacy: hide content from VoiceOver behind the lock.
        .accessibilityAddTraits(.isModal)
    }
}
