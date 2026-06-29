import Foundation
import Observation

// MARK: - Auth (docs/02 §1–2, docs/07 §3) — pure Domain, no SDK imports
//
// The authentication seam. `AuthRepository` is the protocol Stores depend on; the
// Supabase-backed and demo (in-memory) implementations live in DataLayer / the app.
// `AuthUser` is the minimal identity the UI needs; `AuthSessionState` is the
// observable session machine the router switches on (signedOut → AuthView,
// signedIn → Onboarding/Root).

/// Minimal authenticated identity surfaced to the UI. Backed by the provider's
/// user (id + optional email); no tokens — those live in the Keychain (docs/07 §3).
public struct AuthUser: Equatable, Sendable, Identifiable, Codable {
    public let id: String
    public let email: String?

    public init(id: String, email: String? = nil) {
        self.id = id
        self.email = email
    }
}

/// The session machine the app routes on. `unknown` is the launch state before the
/// stored session resolves; the router shows a neutral splash until it settles.
public enum AuthSessionState: Equatable, Sendable {
    case unknown
    case signedOut
    case signedIn(AuthUser)

    public var user: AuthUser? {
        if case let .signedIn(user) = self { return user }
        return nil
    }

    public var isSignedIn: Bool {
        if case .signedIn = self { return true }
        return false
    }
}

/// Data-access seam for authentication (docs/03 §3 — declared in Domain, implemented
/// in DataLayer/app). Pure: no Supabase types leak through. Implementations persist
/// tokens in the Keychain and never store them in `UserDefaults`.
public protocol AuthRepository: Sendable {
    /// Resolve the current session once (used at launch to leave `.unknown`).
    func currentState() async -> AuthSessionState

    /// Observe session changes (sign-in / sign-out / token refresh). The stream
    /// emits the current state on subscription, then on every change.
    func stateStream() -> AsyncStream<AuthSessionState>

    /// Sign in with an Apple identity token + the nonce used to obtain it.
    @discardableResult
    func signInWithApple(idToken: String, nonce: String) async throws -> AuthUser

    /// Sign in an existing user with email + password.
    @discardableResult
    func signIn(email: String, password: String) async throws -> AuthUser

    /// Register a new user with email + password.
    @discardableResult
    func signUp(email: String, password: String) async throws -> AuthUser

    /// Sign out, clearing the persisted session.
    func signOut() async throws

    /// Send a password-reset email. Implementations should not reveal whether an
    /// account exists for the address (the UI shows a neutral confirmation). The
    /// demo / no-config path acknowledges without any network call.
    func sendPasswordReset(email: String) async throws
}

// MARK: - AuthStore (@MainActor @Observable) — unidirectional MVVM (docs/03)
//
// Wraps an `AuthRepository`: holds the observable `state` + the in-flight/error UI
// flags, and exposes the sign-in/up/out/demo actions. Lives in Domain (not the app)
// so its state transitions are unit-testable via `swift test` against a stub repo.
// `@Observable` comes from the Observation framework — no SwiftUI dependency.

@MainActor
@Observable
public final class AuthStore {
    /// The current session state the router switches on.
    public private(set) var state: AuthSessionState = .unknown
    /// True while a sign-in / sign-up / sign-out request is in flight.
    public private(set) var isBusy: Bool = false
    /// Last action error, surfaced to the UI; cleared on the next attempt.
    public private(set) var errorMessage: String?
    /// Last non-error confirmation surfaced to the UI (e.g. password-reset sent);
    /// cleared on the next attempt.
    public private(set) var infoMessage: String?

    private let repository: any AuthRepository
    private var observation: Task<Void, Never>?

    public init(repository: any AuthRepository) {
        self.repository = repository
    }

    /// Stop observing the repository's session stream (e.g. on teardown).
    public func stopObserving() {
        observation?.cancel()
        observation = nil
    }

    /// Resolve the stored session, then keep `state` in sync with the repository.
    public func start() async {
        state = await repository.currentState()
        observation?.cancel()
        let stream = repository.stateStream()
        observation = Task { [weak self] in
            for await next in stream {
                await MainActor.run { self?.state = next }
            }
        }
    }

    public func signInWithApple(idToken: String, nonce: String) async {
        await perform { try await self.repository.signInWithApple(idToken: idToken, nonce: nonce) }
    }

    public func signIn(email: String, password: String) async {
        await perform { try await self.repository.signIn(email: email, password: password) }
    }

    public func signUp(email: String, password: String) async {
        await perform { try await self.repository.signUp(email: email, password: password) }
    }

    public func signOut() async {
        errorMessage = nil
        infoMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await repository.signOut()
            state = .signedOut
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    /// Request a password-reset email. On success surfaces a neutral confirmation
    /// (we never reveal whether the account exists); on failure surfaces the error.
    /// Guarded by `isBusy` so it can't overlap another in-flight action.
    public func sendPasswordReset(email: String) async {
        guard !isBusy else { return }
        errorMessage = nil
        infoMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await repository.sendPasswordReset(email: email)
            infoMessage = "If an account exists, a reset link has been sent."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    /// Shared action runner: clears the error, flips `isBusy`, and on success sets
    /// `state` to `.signedIn`. The repository's stream also reflects this, but we
    /// set it directly so callers (and the demo repo) transition deterministically.
    private func perform(_ action: @escaping () async throws -> AuthUser) async {
        errorMessage = nil
        infoMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            let user = try await action()
            state = .signedIn(user)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}
