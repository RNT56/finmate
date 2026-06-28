import Foundation

// MARK: - Customizable Home dashboard (docs/02 §3, docs/05 §3.11) — M7-HOME
// Pure value model for the reorderable/hideable Home dashboard. The persisted
// `card_order text[]` column (docs/05 §3.11) maps to `DashboardLayout.cardOrder`
// (one rawValue per visible card, in order). Hidden cards are simply absent from
// `cardOrder` — the column stores the *visible* set in order, which keeps the
// schema a single array and makes "hide" == "remove from order".

/// Identity of a Home dashboard card. The `rawValue` is the stable token persisted
/// in `dashboard_layouts.card_order` — never rename a case's rawValue.
public enum DashboardCardID: String, CaseIterable, Codable, Sendable, Identifiable {
    case monthlySubscriptions = "monthly_subscriptions"
    case netCashFlow = "net_cash_flow"
    case savingsRate = "savings_rate"
    case portfolioValue = "portfolio_value"
    case upcomingCharges = "upcoming_charges"
    case activeServices = "active_services"

    public var id: String { rawValue }

    /// The canonical default order + visibility for a brand-new user (docs/02 §3).
    public static let defaultOrder: [DashboardCardID] = [
        .monthlySubscriptions, .netCashFlow, .savingsRate,
        .portfolioValue, .upcomingCharges, .activeServices,
    ]

    /// Human title for the card (used by the editor list + accessibility).
    public var title: String {
        switch self {
        case .monthlySubscriptions: return "Monthly subscriptions"
        case .netCashFlow:          return "Net cash flow"
        case .savingsRate:          return "Savings rate"
        case .portfolioValue:       return "Portfolio value"
        case .upcomingCharges:      return "Upcoming charges"
        case .activeServices:       return "Active services"
        }
    }
}

/// The persisted Home layout: an ordered list of *visible* card ids. A card is
/// "hidden" precisely when it is absent from `cardOrder`. Stored as `text[]`
/// (docs/05 §3.11) — one `DashboardCardID.rawValue` per element, in order.
public struct DashboardLayout: Equatable, Sendable, Codable {
    /// Visible cards, in render order. Persisted verbatim as `card_order`.
    public private(set) var cardOrder: [DashboardCardID]

    public init(cardOrder: [DashboardCardID] = DashboardCardID.defaultOrder) {
        self.cardOrder = cardOrder
    }

    /// The default layout: every card visible in the canonical order.
    public static let defaults = DashboardLayout(cardOrder: DashboardCardID.defaultOrder)

    /// Cards not currently visible (default-order minus what's shown).
    public var hidden: [DashboardCardID] {
        DashboardCardID.defaultOrder.filter { !cardOrder.contains($0) }
    }

    /// Whether `id` is currently shown.
    public func isVisible(_ id: DashboardCardID) -> Bool { cardOrder.contains(id) }

    // MARK: Mutations

    /// Move the visible card(s) at `source` offsets to `destination`. Matches the
    /// semantics of SwiftUI's `.onMove` (`Array.move(fromOffsets:toOffset:)`) but
    /// is reimplemented here so Domain stays UI-framework-free.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { cardOrder[$0] }
        // Count removals before the insertion point to adjust the target index.
        let removedBeforeDestination = source.filter { $0 < destination }.count
        for index in source.sorted(by: >) { cardOrder.remove(at: index) }
        cardOrder.insert(contentsOf: moving, at: destination - removedBeforeDestination)
    }

    /// Show or hide a card. Showing appends to the end (preserving existing order);
    /// hiding removes it. No-ops when already in the requested state.
    public mutating func setVisible(_ id: DashboardCardID, _ visible: Bool) {
        if visible {
            if !cardOrder.contains(id) { cardOrder.append(id) }
        } else {
            cardOrder.removeAll { $0 == id }
        }
    }

    /// Toggle a card's visibility.
    public mutating func toggle(_ id: DashboardCardID) {
        setVisible(id, !isVisible(id))
    }

    // MARK: Resolution from a persisted token list

    /// Build a layout from a raw persisted `card_order` (e.g. Postgres `text[]`),
    /// dropping unknown/duplicate ids and appending any newly-shipped default
    /// cards (in default order) that the stored order didn't yet know about.
    /// This is forward-compatible: old rows gain new cards automatically.
    public static func resolved(order rawValue: [String]) -> DashboardLayout {
        var seen = Set<DashboardCardID>()
        var resolved: [DashboardCardID] = []
        for token in rawValue {
            guard let id = DashboardCardID(rawValue: token), !seen.contains(id) else { continue }
            seen.insert(id)
            resolved.append(id)
        }
        // Append cards that ship by default but weren't in the stored order.
        for id in DashboardCardID.defaultOrder where !seen.contains(id) {
            resolved.append(id)
            seen.insert(id)
        }
        return DashboardLayout(cardOrder: resolved)
    }

    /// The persisted form for the `card_order text[]` column.
    public var rawOrder: [String] { cardOrder.map(\.rawValue) }
}

// MARK: - Repository protocol (docs/03 §3 — declared in Domain, implemented in DataLayer)

public protocol DashboardLayoutRepository: Sendable {
    func load() async throws -> DashboardLayout
    func save(_ layout: DashboardLayout) async throws
}

/// In-memory `DashboardLayoutRepository` for previews/tests and the first
/// executable slice; the Supabase-backed implementation (the `dashboard_layouts`
/// table, docs/05 §3.11) swaps in behind the same protocol.
public actor InMemoryDashboardLayoutRepository: DashboardLayoutRepository {
    private var layout: DashboardLayout

    public init(seed: DashboardLayout = .defaults) {
        self.layout = seed
    }

    public func load() async throws -> DashboardLayout { layout }

    public func save(_ layout: DashboardLayout) async throws {
        // Re-resolve on save so a persisted order is always canonical (dedup +
        // unknown-id drop + default-append), matching what `load` would yield.
        self.layout = DashboardLayout.resolved(order: layout.rawOrder)
    }
}
