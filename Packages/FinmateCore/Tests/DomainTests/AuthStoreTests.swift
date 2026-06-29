import Testing
import Foundation
@testable import Domain

// MARK: - AuthStore state-transition tests (docs/02 §1–2)
//
// Exercises the AuthStore against a controllable stub AuthRepository: the session
// machine moves unknown → signedOut at launch, signedIn on sign-in / sign-up /
// Apple / demo, and back to signedOut on sign-out. Errors surface without changing
// a successful state. Pure — runs under `swift test`.

/// Stub AuthRepository: returns a fixed user (or throws) and drives a manual stream.
private actor StubAuthRepository: AuthRepository {
    enum StubError: Error, LocalizedError {
        case boom
        var errorDescription: String? { "stub failure" }
    }

    private var initial: AuthSessionState
    private let userToReturn: AuthUser
    private let shouldThrow: Bool

    init(initial: AuthSessionState = .signedOut,
         user: AuthUser = AuthUser(id: "u1", email: "a@b.com"),
         shouldThrow: Bool = false) {
        self.initial = initial
        self.userToReturn = user
        self.shouldThrow = shouldThrow
    }

    func currentState() async -> AuthSessionState { initial }

    nonisolated func stateStream() -> AsyncStream<AuthSessionState> {
        AsyncStream { $0.finish() }
    }

    private func result() throws -> AuthUser {
        if shouldThrow { throw StubError.boom }
        return userToReturn
    }

    func signInWithApple(idToken: String, nonce: String) async throws -> AuthUser { try result() }
    func signIn(email: String, password: String) async throws -> AuthUser { try result() }
    func signUp(email: String, password: String) async throws -> AuthUser { try result() }
    func signOut() async throws { if shouldThrow { throw StubError.boom } }
    func sendPasswordReset(email: String) async throws { if shouldThrow { throw StubError.boom } }
}

@MainActor
struct AuthStoreTests {
    @Test func startResolvesSignedOut() async {
        let store = AuthStore(repository: StubAuthRepository(initial: .signedOut))
        #expect(store.state == .unknown)
        await store.start()
        #expect(store.state == .signedOut)
    }

    @Test func startResolvesExistingSession() async {
        let user = AuthUser(id: "u9", email: "x@y.z")
        let store = AuthStore(repository: StubAuthRepository(initial: .signedIn(user)))
        await store.start()
        #expect(store.state == .signedIn(user))
    }

    @Test func signInTransitionsToSignedIn() async {
        let user = AuthUser(id: "u1", email: "a@b.com")
        let store = AuthStore(repository: StubAuthRepository(user: user))
        await store.signIn(email: "a@b.com", password: "secret")
        #expect(store.state == .signedIn(user))
        #expect(store.errorMessage == nil)
        #expect(store.isBusy == false)
    }

    @Test func signUpTransitionsToSignedIn() async {
        let user = AuthUser(id: "u2", email: "new@b.com")
        let store = AuthStore(repository: StubAuthRepository(user: user))
        await store.signUp(email: "new@b.com", password: "secret12")
        #expect(store.state == .signedIn(user))
    }

    @Test func appleSignInTransitionsToSignedIn() async {
        let user = AuthUser(id: "apple1", email: nil)
        let store = AuthStore(repository: StubAuthRepository(user: user))
        await store.signInWithApple(idToken: "token", nonce: "nonce")
        #expect(store.state == .signedIn(user))
    }

    @Test func signOutTransitionsToSignedOut() async {
        let user = AuthUser(id: "u1", email: "a@b.com")
        let store = AuthStore(repository: StubAuthRepository(initial: .signedIn(user)))
        await store.start()
        #expect(store.state.isSignedIn)
        await store.signOut()
        #expect(store.state == .signedOut)
    }

    @Test func failedSignInSurfacesErrorAndStaysSignedOut() async {
        let store = AuthStore(repository: StubAuthRepository(shouldThrow: true))
        await store.start()
        await store.signIn(email: "a@b.com", password: "bad")
        #expect(store.state == .signedOut)
        #expect(store.errorMessage == "stub failure")
        #expect(store.isBusy == false)
    }

    @Test func sendPasswordResetSuccessSurfacesConfirmation() async {
        let store = AuthStore(repository: StubAuthRepository())
        await store.start()
        await store.sendPasswordReset(email: "a@b.com")
        #expect(store.infoMessage == "If an account exists, a reset link has been sent.")
        #expect(store.errorMessage == nil)
        #expect(store.isBusy == false)
        // The reset must not change the session state.
        #expect(store.state == .signedOut)
    }

    @Test func failedPasswordResetSurfacesError() async {
        let store = AuthStore(repository: StubAuthRepository(shouldThrow: true))
        await store.start()
        await store.sendPasswordReset(email: "a@b.com")
        #expect(store.errorMessage == "stub failure")
        #expect(store.infoMessage == nil)
        #expect(store.isBusy == false)
    }

    @Test func demoRepositorySignsInAsDemoUser() async {
        let demo = DemoStubRepository()
        let store = AuthStore(repository: demo)
        await store.start()
        #expect(store.state == .signedOut)
        // Demo entry path goes through any sign-in action.
        await store.signIn(email: "", password: "")
        #expect(store.state == .signedIn(DemoStubRepository.demoUser))
    }
}

/// A minimal demo-style repository mirroring DemoAuthRepository's behaviour for the
/// Domain test (DataLayer's DemoAuthRepository isn't importable here).
private actor DemoStubRepository: AuthRepository {
    static let demoUser = AuthUser(id: "demo-user", email: "demo@finmate.app")
    func currentState() async -> AuthSessionState { .signedOut }
    nonisolated func stateStream() -> AsyncStream<AuthSessionState> { AsyncStream { $0.finish() } }
    func signInWithApple(idToken: String, nonce: String) async throws -> AuthUser { Self.demoUser }
    func signIn(email: String, password: String) async throws -> AuthUser { Self.demoUser }
    func signUp(email: String, password: String) async throws -> AuthUser { Self.demoUser }
    func signOut() async throws {}
    func sendPasswordReset(email: String) async throws {}
}
