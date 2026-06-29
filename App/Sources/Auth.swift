import SwiftUI
import AuthenticationServices
import CryptoKit
import Domain
import DataLayer

// MARK: - Auth & onboarding (docs/02 §1–2, docs/07 §3)
//
// The signed-out entry point. `AuthView` offers Sign in with Apple, email/password
// (sign-in/sign-up toggle + validation), and a prominent "Try the demo" button that
// enters the app on the in-memory sample repos when no Supabase config is present.
// `OnboardingView` is the first-run setup (currency, appearance, optional biometric)
// writing through `PreferencesStore`. Routing lives in `FinmateApp`.

// MARK: - SwiftUI Environment plumbing for the shared AuthStore

private struct AuthStoreKey: EnvironmentKey {
    static let defaultValue: AuthStore? = nil
}

extension EnvironmentValues {
    /// The shared `AuthStore`, injected at the App root. Optional only to satisfy
    /// the nonisolated `EnvironmentKey` default; always set in the live app.
    var authStore: AuthStore? {
        get { self[AuthStoreKey.self] }
        set { self[AuthStoreKey.self] = newValue }
    }
}

// MARK: - AuthView

/// Local sign-in vs. sign-up mode.
private enum AuthMode: String, CaseIterable {
    case signIn = "Sign In"
    case signUp = "Sign Up"
}

struct AuthView: View {
    let store: AuthStore
    /// Whether the offline demo path is available (no Supabase config).
    let isDemo: Bool

    @State private var mode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var currentNonce: String?

    /// Whether the inline "forgot password" reset field is showing.
    @State private var showingReset = false
    /// The address typed into the reset field (kept separate from sign-in email).
    @State private var resetEmail = ""

    /// Minimal client-side validation: a plausible email + a >= 8-char password.
    private var emailIsValid: Bool {
        Self.isPlausibleEmail(email)
    }
    /// Client-side validation for the reset address.
    private var resetEmailIsValid: Bool {
        Self.isPlausibleEmail(resetEmail)
    }

    private static func isPlausibleEmail(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") && trimmed.contains(".") && trimmed.count >= 5
    }
    private var passwordIsValid: Bool { password.count >= 8 }
    private var formIsValid: Bool { emailIsValid && passwordIsValid }

    var body: some View {
        ScrollView {
            VStack(spacing: FinmateTokens.spacing) {
                header

                GlassCard {
                    VStack(spacing: 16) {
                        Picker("Mode", selection: $mode) {
                            ForEach(AuthMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Sign in or sign up")

                        emailPasswordFields
                        submitButton

                        if mode == .signIn {
                            forgotPasswordSection
                        }

                        if let error = store.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityLabel("Error: \(error)")
                        }
                        if let info = store.infoMessage {
                            Text(info)
                                .font(.footnote)
                                .foregroundStyle(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityLabel(info)
                        }

                        dividerOr
                        appleButton
                    }
                }

                if isDemo {
                    demoButton
                }
                Spacer(minLength: 0)
            }
            .padding()
        }
        .background(FinmateGradient())
        .disabled(store.isBusy)
        .overlay {
            if store.isBusy { ProgressView().controlSize(.large) }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "creditcard.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Finmate")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
            Text("Private-first personal finance.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }

    private var emailPasswordFields: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Email address")
            SecureField("Password", text: $password)
                .textContentType(mode == .signUp ? .newPassword : .password)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Password")
            if !password.isEmpty && !passwordIsValid {
                Text("Password must be at least 8 characters.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var submitButton: some View {
        Button {
            Task {
                switch mode {
                case .signIn: await store.signIn(email: email, password: password)
                case .signUp: await store.signUp(email: email, password: password)
                }
            }
        } label: {
            Text(mode.rawValue)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!formIsValid)
    }

    /// "Forgot password?" affordance + an inline reset field that posts the email
    /// to `AuthStore.sendPasswordReset`. The confirmation surfaces via `infoMessage`.
    @ViewBuilder
    private var forgotPasswordSection: some View {
        if showingReset {
            VStack(spacing: 10) {
                TextField("Email for reset link", text: $resetEmail)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Email for password reset")
                Button {
                    Task { await store.sendPasswordReset(email: resetEmail) }
                } label: {
                    Text("Send reset link").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!resetEmailIsValid)
                .accessibilityIdentifier("auth.sendReset")
            }
            .transition(.opacity)
        } else {
            Button("Forgot password?") {
                resetEmail = email
                withAnimation { showingReset = true }
            }
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityIdentifier("auth.forgotPassword")
        }
    }

    private var dividerOr: some View {
        HStack {
            VStack { Divider() }
            Text("or").font(.caption).foregroundStyle(.secondary)
            VStack { Divider() }
        }
    }

    private var appleButton: some View {
        SignInWithAppleButton(.signIn) { request in
            let nonce = Self.randomNonce()
            currentNonce = nonce
            request.requestedScopes = [.email]
            request.nonce = Self.sha256(nonce)
        } onCompletion: { result in
            handleApple(result)
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 48)
        .accessibilityLabel("Sign in with Apple")
    }

    private var demoButton: some View {
        Button {
            // Any sign-in action against the demo repo enters as the demo user.
            Task { await store.signIn(email: "demo", password: "demo") }
        } label: {
            Label("Try the demo", systemImage: "play.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityIdentifier("auth.tryDemo")
        .accessibilityHint("Explore the app offline with sample data, no account needed")
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(auth):
            guard
                let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce = currentNonce
            else {
                return // malformed credential; stay signed out
            }
            Task { await store.signInWithApple(idToken: idToken, nonce: nonce) }
        case .failure:
            break // user cancelled or error; AuthView stays signed out
        }
    }

    // MARK: Nonce helpers (Sign in with Apple replay protection)

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - OnboardingView (first run — docs/02 §2)

/// First-run setup: pick a default display currency, appearance, and (optionally)
/// enable biometric lock. Writes through `PreferencesStore`. On completion the
/// caller records the first-run flag so subsequent launches skip straight to Root.
struct OnboardingView: View {
    @Environment(PreferencesStore.self) private var preferences
    let onComplete: () -> Void

    @State private var currency: CurrencyCode = .eur
    @State private var appearance: Appearance = .system
    @State private var biometric = false

    var body: some View {
        ScrollView {
            VStack(spacing: FinmateTokens.spacing) {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 48)).foregroundStyle(.tint)
                    Text("Welcome to Finmate")
                        .font(.system(.title, design: .rounded).weight(.bold))
                    Text("A couple of quick choices to get started.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 16)
                .accessibilityElement(children: .combine)

                GlassCard {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Display currency").font(.headline)
                            Picker("Display currency", selection: $currency) {
                                ForEach([CurrencyCode.eur, .usd, .btc], id: \.self) {
                                    Text($0.displayLabel).tag($0)
                                }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityLabel("Default display currency")
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Appearance").font(.headline)
                            Picker("Appearance", selection: $appearance) {
                                ForEach(Appearance.allCases, id: \.self) {
                                    Text($0.label).tag($0)
                                }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityLabel("Appearance theme")
                        }
                        Toggle(isOn: $biometric) {
                            Label("Require Face ID / Touch ID", systemImage: "faceid")
                        }
                        .accessibilityLabel("Require biometrics to unlock")
                    }
                }

                Button {
                    preferences.setDefaultCurrency(currency)
                    preferences.setAppearance(appearance)
                    preferences.setBiometricLock(biometric)
                    onComplete()
                } label: {
                    Text("Get started").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("onboarding.continue")
            }
            .padding()
        }
        .background(FinmateGradient())
        .onAppear {
            currency = preferences.preferences.defaultCurrency
            appearance = preferences.appearance
            biometric = preferences.preferences.biometricLockEnabled
        }
    }
}
