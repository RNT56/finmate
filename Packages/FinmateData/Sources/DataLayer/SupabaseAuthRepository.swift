import Foundation
import Supabase
import Domain

// MARK: - SupabaseAuthRepository (docs/07 §3) — live auth over supabase-swift
//
// Implements the Domain `AuthRepository` protocol on top of `client.auth`:
// Sign in with Apple (signInWithIdToken(.apple)), email/password sign-in + sign-up,
// sign-out, and the `authStateChanges` stream. Tokens persist via the provider's
// Keychain-backed `AuthLocalStorage` (KeychainAuthStorage). No tokens are exposed
// through the protocol — only the minimal `AuthUser` (id + email).

public struct SupabaseAuthRepository: AuthRepository {
    private let provider: SupabaseClientProvider

    public init(provider: SupabaseClientProvider) {
        self.provider = provider
    }

    private func mapUser(_ user: User) -> AuthUser {
        AuthUser(id: user.id.uuidString, email: user.email)
    }

    public func currentState() async -> AuthSessionState {
        let client = await provider.client()
        if let user = client.auth.currentUser {
            return .signedIn(mapUser(user))
        }
        return .signedOut
    }

    public func stateStream() -> AsyncStream<AuthSessionState> {
        AsyncStream { continuation in
            let task = Task {
                let client = await provider.client()
                for await change in client.auth.authStateChanges {
                    switch change.event {
                    case .signedIn, .initialSession, .tokenRefreshed, .userUpdated:
                        if let user = change.session?.user {
                            continuation.yield(.signedIn(mapUser(user)))
                        } else {
                            continuation.yield(.signedOut)
                        }
                    case .signedOut:
                        continuation.yield(.signedOut)
                    default:
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    @discardableResult
    public func signInWithApple(idToken: String, nonce: String) async throws -> AuthUser {
        let client = await provider.client()
        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
        )
        return mapUser(session.user)
    }

    @discardableResult
    public func signIn(email: String, password: String) async throws -> AuthUser {
        let client = await provider.client()
        let session = try await client.auth.signIn(email: email, password: password)
        return mapUser(session.user)
    }

    @discardableResult
    public func signUp(email: String, password: String) async throws -> AuthUser {
        let client = await provider.client()
        let response = try await client.auth.signUp(email: email, password: password)
        return mapUser(response.user)
    }

    public func signOut() async throws {
        let client = await provider.client()
        try await client.auth.signOut()
    }
}
