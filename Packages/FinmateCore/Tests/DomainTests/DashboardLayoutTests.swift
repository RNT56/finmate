import Testing
import Foundation
@testable import Domain

// docs/02 §3 / docs/05 §3.11 — customizable Home dashboard layout: default order,
// reorder persistence, unknown-id dropping, new-default appending, hide/show.
@Suite struct DashboardLayoutTests {

    // MARK: Defaults

    @Test func defaultLayoutIsCanonicalOrderAllVisible() {
        let layout = DashboardLayout.defaults
        #expect(layout.cardOrder == DashboardCardID.defaultOrder)
        #expect(layout.hidden.isEmpty)
        #expect(layout.cardOrder.count == DashboardCardID.allCases.count)
        for id in DashboardCardID.allCases { #expect(layout.isVisible(id)) }
    }

    @Test func defaultOrderMatchesSpec() {
        #expect(DashboardCardID.defaultOrder == [
            .monthlySubscriptions, .netCashFlow, .savingsRate,
            .portfolioValue, .upcomingCharges, .activeServices,
        ])
    }

    @Test func rawValuesAreStableTokens() {
        #expect(DashboardCardID.monthlySubscriptions.rawValue == "monthly_subscriptions")
        #expect(DashboardCardID.netCashFlow.rawValue == "net_cash_flow")
        #expect(DashboardCardID.savingsRate.rawValue == "savings_rate")
        #expect(DashboardCardID.portfolioValue.rawValue == "portfolio_value")
        #expect(DashboardCardID.upcomingCharges.rawValue == "upcoming_charges")
        #expect(DashboardCardID.activeServices.rawValue == "active_services")
    }

    // MARK: Reorder persists

    @Test func reorderPersistsThroughRepository() async throws {
        var layout = DashboardLayout.defaults
        // Move the first card (monthlySubscriptions) to the end.
        layout.move(fromOffsets: IndexSet(integer: 0), toOffset: layout.cardOrder.count)
        #expect(layout.cardOrder.last == .monthlySubscriptions)
        #expect(layout.cardOrder.first == .netCashFlow)

        let repo = InMemoryDashboardLayoutRepository()
        try await repo.save(layout)
        let loaded = try await repo.load()
        #expect(loaded.cardOrder == layout.cardOrder)
    }

    // MARK: Unknown id dropped

    @Test func resolvedDropsUnknownIDs() {
        let raw = ["net_cash_flow", "made_up_card", "savings_rate"]
        let layout = DashboardLayout.resolved(order: raw)
        // Unknown token dropped; the two known ones keep their stored order first.
        #expect(layout.cardOrder.prefix(2) == [.netCashFlow, .savingsRate])
        #expect(!layout.cardOrder.contains(where: { $0.rawValue == "made_up_card" }))
        #expect(layout.cardOrder.count == DashboardCardID.allCases.count)
    }

    @Test func resolvedDropsDuplicateIDs() {
        let raw = ["savings_rate", "savings_rate", "net_cash_flow"]
        let layout = DashboardLayout.resolved(order: raw)
        #expect(layout.cardOrder.filter { $0 == .savingsRate }.count == 1)
        #expect(layout.cardOrder.prefix(2) == [.savingsRate, .netCashFlow])
    }

    // MARK: New default appended

    @Test func resolvedAppendsNewDefaultCards() {
        // A stored order from "before" portfolioValue / activeServices shipped.
        let raw = ["monthly_subscriptions", "net_cash_flow"]
        let layout = DashboardLayout.resolved(order: raw)
        #expect(layout.cardOrder.prefix(2) == [.monthlySubscriptions, .netCashFlow])
        // The remaining default cards are appended in default order.
        #expect(layout.cardOrder.count == DashboardCardID.allCases.count)
        #expect(layout.isVisible(.portfolioValue))
        #expect(layout.isVisible(.activeServices))
        // Appended tail preserves canonical default ordering.
        #expect(layout.cardOrder.suffix(4) == [
            .savingsRate, .portfolioValue, .upcomingCharges, .activeServices,
        ])
    }

    @Test func resolvedEmptyYieldsFullDefaults() {
        let layout = DashboardLayout.resolved(order: [])
        #expect(layout.cardOrder == DashboardCardID.defaultOrder)
    }

    // MARK: Hide / show

    @Test func hideRemovesFromOrder() {
        var layout = DashboardLayout.defaults
        layout.setVisible(.portfolioValue, false)
        #expect(!layout.isVisible(.portfolioValue))
        #expect(layout.hidden == [.portfolioValue])
        #expect(layout.cardOrder.count == DashboardCardID.allCases.count - 1)
    }

    @Test func showAppendsAtEnd() {
        var layout = DashboardLayout(cardOrder: [.netCashFlow, .savingsRate])
        #expect(!layout.isVisible(.portfolioValue))
        layout.setVisible(.portfolioValue, true)
        #expect(layout.cardOrder.last == .portfolioValue)
        #expect(layout.isVisible(.portfolioValue))
    }

    @Test func toggleFlipsVisibility() {
        var layout = DashboardLayout.defaults
        layout.toggle(.activeServices)
        #expect(!layout.isVisible(.activeServices))
        layout.toggle(.activeServices)
        #expect(layout.isVisible(.activeServices))
        #expect(layout.cardOrder.last == .activeServices)
    }

    @Test func setVisibleIsIdempotent() {
        var layout = DashboardLayout.defaults
        let before = layout.cardOrder
        layout.setVisible(.netCashFlow, true)   // already visible — no dup
        #expect(layout.cardOrder == before)
        layout.setVisible(.netCashFlow, false)
        layout.setVisible(.netCashFlow, false)  // already hidden — no-op
        #expect(!layout.isVisible(.netCashFlow))
        #expect(layout.cardOrder.filter { $0 == .netCashFlow }.isEmpty)
    }

    // MARK: rawOrder round-trip

    @Test func rawOrderRoundTrips() {
        var layout = DashboardLayout.defaults
        layout.setVisible(.upcomingCharges, false)
        let restored = DashboardLayout.resolved(order: layout.rawOrder)
        // Hidden card is appended back (it's a default), so visible set differs,
        // but the stored raw tokens reflect exactly the visible cards.
        #expect(layout.rawOrder == layout.cardOrder.map(\.rawValue))
        #expect(restored.isVisible(.upcomingCharges)) // re-appended as a new default
    }
}
