import Foundation
import Supabase
import Domain
import Shared

// MARK: - MarketDataRateProvider (docs/04 §6.2, docs/07 — provider keys stay server-side)
//
// Calls the `market-data` Edge Function and maps its canonical JSON
// `{ eur_usd, btc_eur, btc_usd, fetched_at }` into the Domain `ExchangeRates`.
// The client NEVER hits a market-data provider directly — that secret lives in the
// Edge Function environment (golden rule: no secrets in the client).

/// The wire shape returned by the `market-data` Edge Function.
struct MarketDataResponse: Decodable, Sendable {
    let eurUsd: Double
    let btcEur: Double
    let btcUsd: Double
    let fetchedAt: String

    enum CodingKeys: String, CodingKey {
        case eurUsd = "eur_usd"
        case btcEur = "btc_eur"
        case btcUsd = "btc_usd"
        case fetchedAt = "fetched_at"
    }

    func toDomain() -> ExchangeRates {
        ExchangeRates(
            eurUsd: Decimal(eurUsd),
            btcEur: Decimal(btcEur),
            btcUsd: Decimal(btcUsd),
            fetchedAt: SupabaseCoding.date(fromTimestamp: fetchedAt) ?? .now
        )
    }
}

public struct MarketDataRateProvider: ExchangeRateProvider {
    private let provider: SupabaseClientProvider
    public init(provider: SupabaseClientProvider) { self.provider = provider }

    public func latestRates() async throws -> ExchangeRates {
        let client = await provider.client()
        let response: MarketDataResponse = try await client.functions
            .invoke("market-data")
        return response.toDomain()
    }
}
