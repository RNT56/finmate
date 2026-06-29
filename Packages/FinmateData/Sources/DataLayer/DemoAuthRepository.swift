import Foundation
import Domain

// MARK: - DemoAuthRepository (docs/02 §1 "Try the demo") — offline, in-memory
//
// Backs the no-credentials / "Try the demo" path: when no Supabase config resolves,
// the Auth screen offers a demo entry that signs the user in as a synthetic local
// user against the in-memory sample repositories. No network, no tokens, no
// Keychain — the app is fully usable offline exactly as before.

public actor DemoAuthRepository: AuthRepository {
    /// The synthetic demo identity.
    public static let demoUser = AuthUser(id: "demo-user", email: "demo@finmate.app")

    private var state: AuthSessionState
    private var continuations: [UUID: AsyncStream<AuthSessionState>.Continuation] = [:]

    public init(signedIn: Bool = false) {
        self.state = signedIn ? .signedIn(DemoAuthRepository.demoUser) : .signedOut
    }

    public func currentState() async -> AuthSessionState { state }

    public nonisolated func stateStream() -> AsyncStream<AuthSessionState> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.register(id: id, continuation: continuation) }
            continuation.onTermination = { _ in
                Task { await self.unregister(id: id) }
            }
        }
    }

    private func register(id: UUID, continuation: AsyncStream<AuthSessionState>.Continuation) {
        continuations[id] = continuation
        continuation.yield(state)
    }

    private func unregister(id: UUID) {
        continuations[id] = nil
    }

    private func emit(_ next: AuthSessionState) {
        state = next
        for continuation in continuations.values { continuation.yield(next) }
    }

    @discardableResult
    public func signInWithApple(idToken: String, nonce: String) async throws -> AuthUser {
        enterDemo()
    }

    @discardableResult
    public func signIn(email: String, password: String) async throws -> AuthUser {
        enterDemo()
    }

    @discardableResult
    public func signUp(email: String, password: String) async throws -> AuthUser {
        enterDemo()
    }

    /// Explicit "Try the demo" entry — signs in as the demo user.
    @discardableResult
    public func enterDemo() -> AuthUser {
        emit(.signedIn(DemoAuthRepository.demoUser))
        return DemoAuthRepository.demoUser
    }

    public func signOut() async throws {
        emit(.signedOut)
    }

    /// No-op success: the offline demo path has no backend to email, so a reset
    /// request simply succeeds (the UI shows the neutral confirmation).
    public func sendPasswordReset(email: String) async throws {}
}
