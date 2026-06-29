import SwiftUI
import UserNotifications
import Domain

// MARK: - M4 Payday Calendar (docs/02 §7, docs/13 §11)
// Month grid of Liquid Glass day cells with colored event dots, a day-detail
// list, and a local-notification scheduler. Events are projected through the
// pure Domain `PaydayCalendar` engine over the visible month window.

// MARK: Event-kind presentation (one design language; dots only — docs/06)

extension CalendarEventKind {
    /// Obsidian dots: income = up-green, subscription = bronze accent,
    /// fixedExpense = bronze-deep (docs/06).
    var dotColor: Color {
        switch self {
        case .income:       return FinmateColor.up
        case .subscription: return FinmateColor.bronze
        case .fixedExpense: return FinmateColor.bronzeDeep
        }
    }

    var symbol: String {
        switch self {
        case .income:       return "arrow.down.circle.fill"
        case .subscription: return "creditcard.fill"
        case .fixedExpense: return "house.fill"
        }
    }

    var label: String {
        switch self {
        case .income:       return "Income"
        case .subscription: return "Subscription"
        case .fixedExpense: return "Fixed expense"
        }
    }
}

// MARK: - Notification scheduling (docs/13 §11.5, ADR-0013 — LOCAL only in v1)

/// Abstracts local reminder scheduling so the calendar feature stays testable and
/// decoupled from `UNUserNotificationCenter`. Implementations schedule one
/// `UNCalendarNotificationTrigger` per upcoming event (fire date in the future).
protocol NotificationScheduler: Sendable {
    /// Requests notification authorization (deferred to first opt-in, never on cold
    /// launch — docs/13 §11.5). Returns whether permission is granted.
    func requestAuthorization() async -> Bool

    /// Schedules lead-time reminders for `events`. `now` gates out past fire dates.
    func scheduleReminders(for events: [CalendarEvent], leadTimeDays: Int,
                           calendar: Calendar, now: Date) async

    /// Cancels all previously scheduled Finmate reminders.
    func cancelAll() async
}

/// `UNUserNotificationCenter`-backed scheduler. Compiles and is correct; runtime
/// firing needs user permission (request via `requestAuthorization`).
struct UserNotificationScheduler: NotificationScheduler {
    private let identifierPrefix = "finmate.reminder."

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func scheduleReminders(for events: [CalendarEvent], leadTimeDays: Int,
                           calendar: Calendar, now: Date) async {
        let center = UNUserNotificationCenter.current()
        // docs/13 §11.5: only schedule fire dates that are still in the future.
        let reminders = PaydayCalendar.reminderDates(events: events,
                                                     leadTimeDays: leadTimeDays,
                                                     calendar: calendar)
            .filter { $0.fireDate >= now }

        for (event, fireDate) in reminders {
            let content = UNMutableNotificationContent()
            content.title = "\(event.kind.label): \(event.title)"
            content.body = "\(event.money.formatted()) due \(Self.dayFormatter.string(from: event.date))"
            content.sound = .default

            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(
                identifier: identifierPrefix + event.id.uuidString,
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}

// MARK: - Store (@Observable, MainActor)

@MainActor
@Observable
final class CalendarStore {
    /// The first-of-month anchor for the currently displayed month.
    private(set) var visibleMonth: Date
    private(set) var events: [CalendarEvent] = []
    var selectedDay: Date?
    var remindersEnabled = false

    let calendar: Calendar
    private let scheduler: NotificationScheduler
    private let leadTimeDays = 2 // docs/13 §11.5 default

    private let incomes: [IncomeSource]
    private let subscriptions: [Subscription]
    private let fixedExpenses: [FixedExpense]

    init(referenceDate: Date = .now,
         calendar: Calendar = .current,
         incomes: [IncomeSource] = CashFlowSampleData.income,
         subscriptions: [Subscription] = SampleData.subscriptions,
         fixedExpenses: [FixedExpense] = CashFlowSampleData.fixedExpenses,
         scheduler: NotificationScheduler = UserNotificationScheduler()) {
        self.calendar = calendar
        self.incomes = incomes
        self.subscriptions = subscriptions
        self.fixedExpenses = fixedExpenses
        self.scheduler = scheduler
        let comps = calendar.dateComponents([.year, .month], from: referenceDate)
        self.visibleMonth = calendar.date(from: comps) ?? referenceDate
        reproject()
    }

    var window: DateWindow { DateWindow.month(containing: visibleMonth, calendar: calendar) }

    var monthTitle: String {
        let f = DateFormatter()
        f.calendar = calendar
        f.dateFormat = "LLLL yyyy"
        return f.string(from: visibleMonth)
    }

    /// Events grouped by start-of-day for quick grid lookup.
    private(set) var eventsByDay: [Date: [CalendarEvent]] = [:]

    func events(on day: Date) -> [CalendarEvent] {
        eventsByDay[calendar.startOfDay(for: day)] ?? []
    }

    func reproject() {
        events = PaydayCalendar.events(in: window,
                                       incomes: incomes,
                                       subscriptions: subscriptions,
                                       fixedExpenses: fixedExpenses,
                                       calendar: calendar)
        eventsByDay = Dictionary(grouping: events) { calendar.startOfDay(for: $0.date) }
    }

    func step(months: Int) {
        if let next = calendar.date(byAdding: .month, value: months, to: visibleMonth) {
            visibleMonth = next
            selectedDay = nil
            reproject()
        }
    }

    /// Toggle reminders; on enable, request permission then schedule upcoming events.
    func setReminders(enabled: Bool) async {
        remindersEnabled = enabled
        if enabled {
            let granted = await scheduler.requestAuthorization()
            remindersEnabled = granted
            if granted {
                await scheduler.scheduleReminders(for: events, leadTimeDays: leadTimeDays,
                                                  calendar: calendar, now: .now)
            }
        } else {
            await scheduler.cancelAll()
        }
    }
}

// MARK: - Calendar screen

struct CalendarView: View {
    @State private var store = CalendarStore()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FinmateTokens.spacing) {
                    monthHeader
                    weekdayRow
                    monthGrid
                    legend
                    reminderToggle
                    dayDetail
                }
                .padding()
            }
            .navigationTitle("Calendar")
            .background(FinmateBackground())
        }
    }

    // MARK: Header + controls

    private var monthHeader: some View {
        HStack {
            Button { store.step(months: -1) } label: {
                Image(systemName: "chevron.left").font(.headline)
            }
            .accessibilityLabel("Previous month")
            Spacer()
            Text(store.monthTitle)
                .font(.system(.title3, design: .rounded).weight(.semibold))
            Spacer()
            Button { store.step(months: 1) } label: {
                Image(systemName: "chevron.right").font(.headline)
            }
            .accessibilityLabel("Next month")
        }
    }

    private var weekdayRow: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Grid

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                if let day {
                    DayCell(
                        day: day,
                        calendar: store.calendar,
                        events: store.events(on: day),
                        isSelected: store.selectedDay.map { store.calendar.isDate($0, inSameDayAs: day) } ?? false
                    )
                    .onTapGesture {
                        withAnimation(reduceMotion ? nil : .snappy) { store.selectedDay = day }
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Shows events for this day")
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
    }

    /// Leading nil-padding for the first weekday offset, then each day of the month.
    private var gridDays: [Date?] {
        let cal = store.calendar
        let w = store.window
        let firstWeekday = cal.component(.weekday, from: w.start) // 1 = Sunday
        let leading = firstWeekday - cal.firstWeekday
        let pad = (leading + 7) % 7
        let dayCount = cal.range(of: .day, in: .month, for: w.start)?.count ?? 30
        var cells: [Date?] = Array(repeating: nil, count: pad)
        for offset in 0..<dayCount {
            cells.append(cal.date(byAdding: .day, value: offset, to: w.start))
        }
        return cells
    }

    // MARK: Legend + toggle

    private var legend: some View {
        HStack(spacing: 16) {
            ForEach(CalendarEventKind.allCases, id: \.self) { kind in
                HStack(spacing: 5) {
                    Circle().fill(kind.dotColor).frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(kind.label).font(.caption2).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(kind.label) legend")
            }
        }
    }

    private var reminderToggle: some View {
        GlassCard {
            Toggle(isOn: Binding(
                get: { store.remindersEnabled },
                set: { newValue in Task { await store.setReminders(enabled: newValue) } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Payment reminders").font(.subheadline.weight(.medium))
                    Text("Local notifications, 2 days ahead")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Day detail

    @ViewBuilder private var dayDetail: some View {
        if let day = store.selectedDay {
            let dayEvents = store.events(on: day)
            VStack(alignment: .leading, spacing: FinmateTokens.spacing) {
                Text(Self.detailTitle(day, calendar: store.calendar))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if dayEvents.isEmpty {
                    GlassCard {
                        VStack(spacing: 8) {
                            Image(systemName: "calendar.badge.checkmark")
                                .font(.title)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text("No events on this day")
                                .font(.subheadline.weight(.medium))
                            Text("No income, subscriptions, or bills are due.")
                                .font(.caption).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("No events on this day")
                } else {
                    ForEach(dayEvents) { event in
                        GlassCard {
                            HStack(spacing: 12) {
                                Image(systemName: event.kind.symbol)
                                    .foregroundStyle(event.kind.dotColor)
                                    .font(.title3)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title).font(.subheadline.weight(.medium))
                                    Text(event.kind.label).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(event.money.formatted())
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundStyle(event.kind == .income ? FinmateColor.up : .primary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(event.kind.label), \(event.title), \(event.money.formatted())")
                    }
                }
            }
        }
    }

    private static func detailTitle(_ day: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.dateStyle = .full
        f.timeStyle = .none
        return f.string(from: day)
    }
}

// MARK: - Day cell

private struct DayCell: View {
    let day: Date
    let calendar: Calendar
    let events: [CalendarEvent]
    let isSelected: Bool

    private var dayNumber: String { "\(calendar.component(.day, from: day))" }

    /// Distinct kinds present, in canonical order, capped to keep the cell tidy.
    private var dotKinds: [CalendarEventKind] {
        CalendarEventKind.allCases.filter { kind in events.contains { $0.kind == kind } }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(dayNumber)
                .font(.callout.weight(isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? FinmateColor.bronze : .primary)
            HStack(spacing: 3) {
                ForEach(dotKinds, id: \.self) { kind in
                    Circle().fill(kind.dotColor).frame(width: 5, height: 5)
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .modifier(GlassBackground(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(FinmateColor.bronze, lineWidth: isSelected ? 2 : 0)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let base = "Day \(dayNumber)"
        guard !events.isEmpty else { return base }
        return base + ", " + events.map(\.kind.label).joined(separator: ", ")
    }
}
