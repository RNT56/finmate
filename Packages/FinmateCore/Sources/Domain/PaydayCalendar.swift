import Foundation
import Shared

// MARK: - Payday calendar & recurrence engine (docs/13 §11)
//
// Pure, deterministic date math: every entry point takes an explicit reference
// `Date` (window) and an explicit `Calendar` argument — it never calls
// `Date.now` / `Calendar.current` internally, so unit tests are reproducible.
// Day-of-month clamping (e.g. a Jan-31 monthly anchor → Feb 28 / Feb 29) falls
// out of `Calendar.date(byAdding:)` against the original anchor; we verify the
// Feb-clamp vectors below. No money rounding here — amounts are already minor units.

/// The kind of a projected calendar event (drives the colored dot in the grid).
public enum CalendarEventKind: String, Codable, Sendable, CaseIterable, Comparable {
    case income
    case subscription
    case fixedExpense

    // Stable ordering for the secondary sort key (income < subscription < fixedExpense).
    private var order: Int {
        switch self {
        case .income: return 0
        case .subscription: return 1
        case .fixedExpense: return 2
        }
    }

    public static func < (lhs: CalendarEventKind, rhs: CalendarEventKind) -> Bool {
        lhs.order < rhs.order
    }
}

/// A single projected occurrence placed on a day in the calendar window.
public struct CalendarEvent: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let kind: CalendarEventKind
    public let title: String
    public let amountMinor: Int64
    public let currency: CurrencyCode

    public init(id: UUID = UUID(), date: Date, kind: CalendarEventKind,
                title: String, amountMinor: Int64, currency: CurrencyCode) {
        self.id = id; self.date = date; self.kind = kind
        self.title = title; self.amountMinor = amountMinor; self.currency = currency
    }

    public var money: Money { Money(minorUnits: amountMinor, currency: currency) }
}

/// An inclusive date window `[start, end]` for projection (typically one month).
public struct DateWindow: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public init(start: Date, end: Date) { self.start = start; self.end = end }

    public func contains(_ date: Date) -> Bool { date >= start && date <= end }

    /// Build the inclusive window covering the calendar month that contains `date`.
    public static func month(containing date: Date, calendar: Calendar) -> DateWindow {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let first = calendar.date(from: comps) ?? date
        let range = calendar.range(of: .day, in: .month, for: first)?.count ?? 28
        var endComps = comps
        endComps.day = range
        let last = calendar.date(from: endComps) ?? date
        return DateWindow(start: calendar.startOfDay(for: first),
                          end: calendar.startOfDay(for: last))
    }
}

/// Recurrence + event projection per docs/13 §11. All-static; no stored state.
public enum PaydayCalendar {

    // MARK: Stepping primitives

    /// The component and per-step magnitude for a billing period.
    private static func stepUnit(_ period: BillingPeriod) -> (Calendar.Component, Int) {
        switch period {
        case .weekly:    return (.day, 7)
        case .monthly:   return (.month, 1)
        case .quarterly: return (.month, 3)
        case .yearly:    return (.year, 1)
        }
    }

    private static func stepUnit(_ frequency: IncomeFrequency) -> (Calendar.Component, Int)? {
        switch frequency {
        case .weekly:  return (.day, 7)
        case .monthly: return (.month, 1)
        case .yearly:  return (.year, 1)
        case .oneTime: return nil
        }
    }

    /// Roll `anchor` forward, emitting every occurrence whose start-of-day falls
    /// within the window. Each occurrence is computed as `anchor + n·unit` from
    /// the **original** anchor (not the previous clamped value), so day-of-month
    /// clamping does not drift: a Jan-31 monthly anchor renders Feb 28, Mar 31,
    /// Apr 30 (March still uses the 31st). `Calendar.date(byAdding:)` performs the
    /// clamp. Bounded by a hard iteration cap for safety.
    private static func occurrences(anchor: Date,
                                    component: Calendar.Component,
                                    magnitude: Int,
                                    window: DateWindow,
                                    calendar: Calendar) -> [Date] {
        var result: [Date] = []
        let windowStart = calendar.startOfDay(for: window.start)
        let cap = 100_000
        var n = 0
        while n < cap {
            guard let occ = calendar.date(byAdding: component, value: magnitude * n, to: anchor) else { break }
            let day = calendar.startOfDay(for: occ)
            if day > window.end { break }
            if day >= windowStart { result.append(day) }
            n += 1
        }
        return result
    }

    // MARK: Subscription charges (docs/13 §11.1)

    /// Charge dates for a subscription within `window`, stepping from `startDate`
    /// by `billingPeriod` with day-of-month clamping. A sub that has not started
    /// by `window.end`, or whose `endDate` precedes an occurrence, emits nothing
    /// past that bound.
    public static func subscriptionCharges(_ sub: Subscription,
                                           in window: DateWindow,
                                           calendar: Calendar) -> [CalendarEvent] {
        if sub.startDate > window.end { return [] }
        let cap = min(window.end, calendar.startOfDay(for: sub.endDate ?? window.end))
        let capped = DateWindow(start: window.start, end: cap)
        let (unit, mag) = stepUnit(sub.billingPeriod)
        let dates = occurrences(anchor: sub.startDate, component: unit, magnitude: mag,
                                window: capped, calendar: calendar)
        return dates.map {
            CalendarEvent(date: $0, kind: .subscription, title: sub.name,
                          amountMinor: sub.amountMinor, currency: sub.currency)
        }
    }

    // MARK: Income paydays (docs/13 §11.2)

    /// Payday markers for an income source within `window`. `oneTime` produces a
    /// single marker iff its `nextPayment` is in-window; recurring frequencies
    /// step from the anchor (`nextPayment ?? window.start`) with clamping.
    public static func incomePaydays(_ src: IncomeSource,
                                     in window: DateWindow,
                                     calendar: Calendar) -> [CalendarEvent] {
        let anchor = src.nextPayment ?? window.start
        let dates: [Date]
        if src.frequency == .oneTime {
            guard let payment = src.nextPayment else { return [] }
            let day = calendar.startOfDay(for: payment)
            dates = window.contains(day) ? [day] : []
        } else if let (unit, mag) = stepUnit(src.frequency) {
            dates = occurrences(anchor: anchor, component: unit, magnitude: mag,
                                window: window, calendar: calendar)
        } else {
            dates = []
        }
        return dates.map {
            CalendarEvent(date: $0, kind: .income, title: src.name,
                          amountMinor: src.amountMinor, currency: src.currency)
        }
    }

    // MARK: Fixed-expense due dates (docs/13 §11.1, by BillingPeriod)

    /// Due dates for a fixed expense within `window`, stepping from `dueDate`
    /// by `frequency` with clamping. No `dueDate` → no events.
    public static func fixedExpenseDueDates(_ expense: FixedExpense,
                                            in window: DateWindow,
                                            calendar: Calendar) -> [CalendarEvent] {
        guard let due = expense.dueDate else { return [] }
        let (unit, mag) = stepUnit(expense.frequency)
        let dates = occurrences(anchor: due, component: unit, magnitude: mag,
                                window: window, calendar: calendar)
        return dates.map {
            CalendarEvent(date: $0, kind: .fixedExpense, title: expense.name,
                          amountMinor: expense.amountMinor, currency: expense.currency)
        }
    }

    // MARK: Aggregate projection

    /// All events for the window across the supplied entities, sorted by date
    /// then by kind (income < subscription < fixedExpense), then by title.
    public static func events(in window: DateWindow,
                              incomes: [IncomeSource],
                              subscriptions: [Subscription],
                              fixedExpenses: [FixedExpense],
                              calendar: Calendar) -> [CalendarEvent] {
        var all: [CalendarEvent] = []
        for src in incomes { all += incomePaydays(src, in: window, calendar: calendar) }
        for sub in subscriptions { all += subscriptionCharges(sub, in: window, calendar: calendar) }
        for ex in fixedExpenses { all += fixedExpenseDueDates(ex, in: window, calendar: calendar) }
        return all.sorted { a, b in
            if a.date != b.date { return a.date < b.date }
            if a.kind != b.kind { return a.kind < b.kind }
            return a.title < b.title
        }
    }

    // MARK: Lead-time reminders (docs/13 §11.5)

    /// Maps each event to its reminder fire date = startOfDay(event.date) − leadTimeDays.
    /// Pure; scheduling/`now`-filtering is the caller's concern (docs/13 §11.5).
    public static func reminderDates(events: [CalendarEvent],
                                     leadTimeDays: Int,
                                     calendar: Calendar) -> [(event: CalendarEvent, fireDate: Date)] {
        events.compactMap { event in
            let startOfDay = calendar.startOfDay(for: event.date)
            guard let fire = calendar.date(byAdding: .day, value: -leadTimeDays, to: startOfDay) else {
                return nil
            }
            return (event, fire)
        }
    }
}
