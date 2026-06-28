import Testing
import Foundation
@testable import Domain

// docs/13 §11 — Payday calendar & recurrence. Deterministic vectors: all dates
// are built from DateComponents in a fixed UTC Gregorian calendar so iOS and web
// agree exactly (same vectors as the web Vitest suite).
@Suite struct PaydayCalendarTests {

    // A fixed UTC Gregorian calendar — no DST / locale drift.
    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private var cal: Calendar { Self.utc }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        comps.hour = 0; comps.minute = 0; comps.second = 0
        return Self.utc.date(from: comps)!
    }

    private func window(_ start: (Int, Int, Int), _ end: (Int, Int, Int)) -> DateWindow {
        DateWindow(start: date(start.0, start.1, start.2), end: date(end.0, end.1, end.2))
    }

    private func sub(_ name: String, amount: Int64, period: BillingPeriod,
                     start: Date, end: Date? = nil) -> Subscription {
        Subscription(name: name, amountMinor: amount, currency: .eur,
                     billingPeriod: period, startDate: start, endDate: end)
    }

    // MARK: T11.a — monthly day-of-month within June window

    @Test func calendar_monthlyDayOfMonth() {
        let s = sub("MonthlySub", amount: 1000, period: .monthly, start: date(2026, 1, 15))
        let events = PaydayCalendar.subscriptionCharges(s, in: window((2026, 6, 1), (2026, 6, 30)), calendar: cal)
        #expect(events.map(\.date) == [date(2026, 6, 15)])
    }

    // MARK: T11.b — yearly anniversary appears once in its month

    @Test func calendar_yearlyAnniversaryOnce() {
        let s = sub("YearlySub", amount: 5000, period: .yearly, start: date(2025, 3, 10))
        let events = PaydayCalendar.subscriptionCharges(s, in: window((2026, 1, 1), (2026, 12, 31)), calendar: cal)
        #expect(events.map(\.date) == [date(2026, 3, 10)])
    }

    // MARK: T11.c — Jan 31 monthly clamps to Feb 28 (non-leap 2026)

    @Test func calendar_clampJan31ToFeb28() {
        let s = sub("Clamp", amount: 1000, period: .monthly, start: date(2026, 1, 31))
        let events = PaydayCalendar.subscriptionCharges(s, in: window((2026, 2, 1), (2026, 2, 28)), calendar: cal)
        #expect(events.map(\.date) == [date(2026, 2, 28)])
    }

    // MARK: shared spec — Jan 31 monthly → 02-28, 03-31, 04-30 (anchor does not drift)

    @Test func calendar_jan31SequenceDoesNotDrift() {
        let s = sub("Clamp", amount: 1000, period: .monthly, start: date(2026, 1, 31))
        let events = PaydayCalendar.subscriptionCharges(s, in: window((2026, 2, 1), (2026, 4, 30)), calendar: cal)
        #expect(events.map(\.date) == [date(2026, 2, 28), date(2026, 3, 31), date(2026, 4, 30)])
    }

    // MARK: T11.d — Jan 31 monthly clamps to Feb 29 in a leap year (2024)

    @Test func calendar_clampLeapFeb29() {
        let s = sub("Clamp", amount: 1000, period: .monthly, start: date(2024, 1, 31))
        let events = PaydayCalendar.subscriptionCharges(s, in: window((2024, 2, 1), (2024, 2, 29)), calendar: cal)
        #expect(events.map(\.date) == [date(2024, 2, 29)])
    }

    // MARK: T11.g — weekly steps

    @Test func calendar_weeklySteps() {
        let s = sub("Weekly", amount: 100, period: .weekly, start: date(2026, 6, 1))
        let events = PaydayCalendar.subscriptionCharges(s, in: window((2026, 6, 1), (2026, 6, 30)), calendar: cal)
        #expect(events.map(\.date) == [
            date(2026, 6, 1), date(2026, 6, 8), date(2026, 6, 15), date(2026, 6, 22), date(2026, 6, 29),
        ])
    }

    // MARK: Window filtering — out-of-range occurrences excluded

    @Test func windowFilteringExcludesOutOfRange() {
        let s = sub("Monthly", amount: 1000, period: .monthly, start: date(2026, 1, 10))
        // July window only: Jan–Jun occurrences must be excluded, Aug+ not yet reached.
        let events = PaydayCalendar.subscriptionCharges(s, in: window((2026, 7, 1), (2026, 7, 31)), calendar: cal)
        #expect(events.map(\.date) == [date(2026, 7, 10)])
    }

    // MARK: endDate caps the projection

    @Test func endDateCapsProjection() {
        let s = sub("Ending", amount: 1000, period: .monthly,
                    start: date(2026, 1, 10), end: date(2026, 6, 20))
        // July window after the sub ended in June → no events.
        let events = PaydayCalendar.subscriptionCharges(s, in: window((2026, 7, 1), (2026, 7, 31)), calendar: cal)
        #expect(events.isEmpty)
    }

    // MARK: Income — monthly on the 15th

    @Test func income_monthlyOnFifteenth() {
        let src = IncomeSource(name: "Salary", amountMinor: 320_000, currency: .eur,
                               frequency: .monthly, nextPayment: date(2026, 1, 15))
        let events = PaydayCalendar.incomePaydays(src, in: window((2026, 1, 1), (2026, 3, 31)), calendar: cal)
        #expect(events.map(\.date) == [date(2026, 1, 15), date(2026, 2, 15), date(2026, 3, 15)])
        #expect(events.allSatisfy { $0.kind == .income })
    }

    // MARK: T11.h — one_time income, single marker only if in-window

    @Test func income_oneTimeSingleMarker() {
        let src = IncomeSource(name: "Refund", amountMinor: 500_000, currency: .eur,
                               frequency: .oneTime, nextPayment: date(2026, 6, 30))
        let inWindow = PaydayCalendar.incomePaydays(src, in: window((2026, 6, 1), (2026, 6, 30)), calendar: cal)
        #expect(inWindow.map(\.date) == [date(2026, 6, 30)])
    }

    @Test func income_oneTimeOutOfWindowExcluded() {
        let src = IncomeSource(name: "Refund", amountMinor: 500_000, currency: .eur,
                               frequency: .oneTime, nextPayment: date(2026, 6, 30))
        let outOfWindow = PaydayCalendar.incomePaydays(src, in: window((2026, 7, 1), (2026, 7, 31)), calendar: cal)
        #expect(outOfWindow.isEmpty)
    }

    // MARK: Fixed expense due dates

    @Test func fixedExpense_monthlyDueDates() {
        let ex = FixedExpense(name: "Rent", amountMinor: 110_000, currency: .eur,
                              frequency: .monthly, dueDate: date(2026, 1, 1))
        let events = PaydayCalendar.fixedExpenseDueDates(ex, in: window((2026, 1, 1), (2026, 2, 28)), calendar: cal)
        #expect(events.map(\.date) == [date(2026, 1, 1), date(2026, 2, 1)])
        #expect(events.allSatisfy { $0.kind == .fixedExpense })
    }

    @Test func fixedExpense_noDueDateNoEvents() {
        let ex = FixedExpense(name: "Rent", amountMinor: 110_000, currency: .eur,
                              frequency: .monthly, dueDate: nil)
        let events = PaydayCalendar.fixedExpenseDueDates(ex, in: window((2026, 1, 1), (2026, 12, 31)), calendar: cal)
        #expect(events.isEmpty)
    }

    // MARK: Aggregate ordering — by date, then kind

    @Test func events_sortedByDateThenKind() {
        let income = IncomeSource(name: "Salary", amountMinor: 320_000, currency: .eur,
                                  frequency: .monthly, nextPayment: date(2026, 6, 1))
        let subscription = sub("Netflix", amount: 1299, period: .monthly, start: date(2026, 6, 1))
        let expense = FixedExpense(name: "Rent", amountMinor: 110_000, currency: .eur,
                                   frequency: .monthly, dueDate: date(2026, 6, 1))
        let all = PaydayCalendar.events(in: window((2026, 6, 1), (2026, 6, 30)),
                                        incomes: [income], subscriptions: [subscription],
                                        fixedExpenses: [expense], calendar: cal)
        // Three events on 2026-06-01, ordered income < subscription < fixedExpense.
        #expect(all.count == 3)
        #expect(all.map(\.kind) == [.income, .subscription, .fixedExpense])
        #expect(all.allSatisfy { $0.date == date(2026, 6, 1) })
    }

    // MARK: T11.e — lead time of 2 days shifts fire date back two days

    @Test func reminder_leadTimeTwoDays() {
        let event = CalendarEvent(date: date(2026, 7, 1), kind: .subscription,
                                  title: "Sub", amountMinor: 1000, currency: .eur)
        let reminders = PaydayCalendar.reminderDates(events: [event], leadTimeDays: 2, calendar: cal)
        #expect(reminders.count == 1)
        #expect(reminders[0].fireDate == date(2026, 6, 29))
    }

    @Test func reminder_zeroLeadFiresOnEventDay() {
        let event = CalendarEvent(date: date(2026, 7, 1), kind: .subscription,
                                  title: "Sub", amountMinor: 1000, currency: .eur)
        let reminders = PaydayCalendar.reminderDates(events: [event], leadTimeDays: 0, calendar: cal)
        #expect(reminders[0].fireDate == date(2026, 7, 1))
    }

    // MARK: DateWindow.month helper

    @Test func dateWindow_monthSpansFirstToLast() {
        let w = DateWindow.month(containing: date(2026, 2, 15), calendar: cal)
        #expect(w.start == date(2026, 2, 1))
        #expect(w.end == date(2026, 2, 28))
    }
}
