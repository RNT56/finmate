import Foundation
import Supabase

// MARK: - Config (docs/07 §3 — anon key only ships in the client)
//
// Read `SUPABASE_URL` + `SUPABASE_ANON_KEY` from the app's Info.plist (xcconfig-fed)
// or the process environment. Absent ⇒ `nil` ⇒ the composition root falls back to
// the in-memory sample repositories so the app still builds/runs offline.

/// Resolved Supabase configuration: a project URL + the public anon key.
public struct FinmateConfig: Sendable, Equatable {
    public let url: URL
    public let anonKey: String

    public init(url: URL, anonKey: String) {
        self.url = url
        self.anonKey = anonKey
    }

    /// Resolve config from Info.plist first (`SUPABASE_URL` / `SUPABASE_ANON_KEY`),
    /// then `ProcessInfo` environment. Returns `nil` when either value is missing
    /// or blank — the signal for the composition root to use in-memory repos.
    public static func resolve(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> FinmateConfig? {
        func value(_ key: String) -> String? {
            if let s = bundle.object(forInfoDictionaryKey: key) as? String, !s.isBlank {
                return s.trimmed
            }
            if let s = environment[key], !s.isBlank {
                return s.trimmed
            }
            return nil
        }
        guard
            let rawURL = value("SUPABASE_URL"),
            let url = URL(string: rawURL),
            let anonKey = value("SUPABASE_ANON_KEY")
        else { return nil }
        return FinmateConfig(url: url, anonKey: anonKey)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var isBlank: Bool { trimmed.isEmpty }
}

// MARK: - SupabaseClientProvider (actor)
//
// Builds and owns the single `SupabaseClient`, wiring Keychain-backed auth storage.
// An actor so the shared client is created once and handed out concurrency-safely.

public actor SupabaseClientProvider {
    public let config: FinmateConfig
    private let storage: any AuthLocalStorage
    private var cachedClient: SupabaseClient?

    public init(config: FinmateConfig, storage: any AuthLocalStorage = KeychainAuthStorage()) {
        self.config = config
        self.storage = storage
    }

    /// The lazily-constructed shared client (tokens persisted via the Keychain storage).
    public func client() -> SupabaseClient {
        if let cachedClient { return cachedClient }
        let options = SupabaseClientOptions(
            auth: SupabaseClientOptions.AuthOptions(storage: storage)
        )
        let client = SupabaseClient(
            supabaseURL: config.url,
            supabaseKey: config.anonKey,
            options: options
        )
        cachedClient = client
        return client
    }
}
