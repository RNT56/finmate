import Foundation
import Supabase
import Domain
import Shared

// MARK: - Category DTO ↔ Domain (docs/05 §3.2)
// Categories are read through the `get_user_categories(p_kind)` RPC (docs/05 §5.1),
// which returns rows scoped to `auth.uid()` with live usage counts. We map the
// `kind` text back to the Domain `CategoryKind` (subscription | expense).

struct CategoryDTO: Codable, Sendable {
    let id: UUID
    let kind: String
    let name: String
    let slug: String
    let isProtected: Bool

    enum CodingKeys: String, CodingKey {
        case id, kind, name, slug
        case isProtected = "is_protected"
    }

    func toDomain() -> Domain.Category {
        Domain.Category(
            id: id,
            name: name,
            slug: slug,
            kind: CategoryKind(rawValue: kind) ?? .subscription,
            isProtected: isProtected
        )
    }
}

// MARK: - SupabaseCategoryRepository

public struct SupabaseCategoryRepository: CategoryRepository {
    private let provider: SupabaseClientProvider
    public init(provider: SupabaseClientProvider) { self.provider = provider }

    public func categories(kind: CategoryKind) async throws -> [Domain.Category] {
        let client = await provider.client()
        let rows: [CategoryDTO] = try await client
            .rpc("get_user_categories", params: KindParams(kind: kind.rawValue))
            .execute().value
        return rows.map { $0.toDomain() }
    }

    private struct KindParams: Encodable, Sendable {
        let kind: String
        enum CodingKeys: String, CodingKey { case kind = "p_kind" }
    }
}
