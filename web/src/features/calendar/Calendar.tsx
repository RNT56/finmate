// Payday Calendar (M4) — a month grid with event dots per kind and a day-detail
// panel listing events for the selected day. Events come from the shared sample
// data via the pure core/recurrence engine (docs/13 §11). One glass language.
//
// Notifications: lead-time reminders are computed purely by the engine
// (reminderDates); actual scheduling is iOS-local (UNUserNotificationCenter) per
// ADR-0013. The web client shows the schedule but does NOT raise web push —
// remote push is post-v1.

import { useMemo, useState, type CSSProperties } from 'react';
import { GlassCard } from '../../components/GlassCard';
import { Page } from '../../components/AppShell';
import { formatMoney } from '../../core/money';
import { daysInMonth, type CalendarEvent, type EventKind } from '../../core/recurrence';
import { useCalendar } from './useCalendar';

const EUR_LOCALE = 'de-DE';
const WEEKDAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const MONTHS = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const KIND_COLOR: Record<EventKind, string> = {
  income: 'var(--fm-up)',
  subscription: 'var(--fm-accent)',
  fixedExpense: 'var(--fm-warning)',
};

const KIND_LABEL: Record<EventKind, string> = {
  income: 'Income',
  subscription: 'Subscription',
  fixedExpense: 'Fixed expense',
};

/** Monday-first weekday index (0 = Mon … 6 = Sun) for a 1-based y/m/day. */
function weekdayMondayFirst(year: number, month1: number, day: number): number {
  const js = new Date(Date.UTC(year, month1 - 1, day)).getUTCDay(); // 0 = Sun
  return (js + 6) % 7;
}

function dayKey(year: number, month1: number, day: number): string {
  return `${year}-${String(month1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

export function Calendar() {
  const { loading, view, eventsByDay, goPrevMonth, goNextMonth } = useCalendar();
  const [selectedDay, setSelectedDay] = useState<number | null>(null);

  const totalDays = daysInMonth(view.year, view.month);
  const leadingBlanks = weekdayMondayFirst(view.year, view.month, 1);

  // Reset selection if it falls outside the current month after navigation.
  const validSelection = selectedDay !== null && selectedDay <= totalDays ? selectedDay : null;

  const cells = useMemo(() => {
    const out: Array<{ day: number | null }> = [];
    for (let i = 0; i < leadingBlanks; i += 1) out.push({ day: null });
    for (let d = 1; d <= totalDays; d += 1) out.push({ day: d });
    return out;
  }, [leadingBlanks, totalDays]);

  const selectedEvents: CalendarEvent[] =
    validSelection === null
      ? []
      : eventsByDay.get(dayKey(view.year, view.month, validSelection)) ?? [];

  const fmt = (minor: number, currency: CalendarEvent['currency']) =>
    formatMoney(minor, currency, currency === 'EUR' ? EUR_LOCALE : undefined);

  return (
    <Page title="Calendar">
      <div className="fm-stack">
        <GlassCard>
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              marginBottom: 16,
            }}
          >
            <NavButton label="Previous month" glyph="‹" onClick={() => { setSelectedDay(null); goPrevMonth(); }} />
            <div style={{ fontWeight: 700, fontSize: 18 }} aria-live="polite">
              {MONTHS[view.month - 1]} {view.year}
            </div>
            <NavButton label="Next month" glyph="›" onClick={() => { setSelectedDay(null); goNextMonth(); }} />
          </div>

          <div
            role="grid"
            aria-label={`${MONTHS[view.month - 1]} ${view.year}`}
            style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 6 }}
          >
            {WEEKDAYS.map((w) => (
              <div
                key={w}
                role="columnheader"
                className="fm-secondary"
                style={{ textAlign: 'center', fontSize: 12, fontWeight: 600, paddingBottom: 4 }}
              >
                {w}
              </div>
            ))}

            {cells.map((cell, idx) => {
              if (cell.day === null) {
                return <div key={`blank-${idx}`} aria-hidden="true" />;
              }
              const dayEvents = eventsByDay.get(dayKey(view.year, view.month, cell.day)) ?? [];
              const isSelected = validSelection === cell.day;
              const kinds = uniqueKinds(dayEvents);
              return (
                <button
                  key={cell.day}
                  role="gridcell"
                  type="button"
                  onClick={() => setSelectedDay(cell.day)}
                  aria-pressed={isSelected}
                  aria-label={`${MONTHS[view.month - 1]} ${cell.day}, ${dayEvents.length} event${dayEvents.length === 1 ? '' : 's'}`}
                  style={dayCellStyle(isSelected)}
                >
                  <span style={{ fontSize: 14, fontWeight: isSelected ? 700 : 500 }}>{cell.day}</span>
                  <span style={{ display: 'flex', gap: 3, minHeight: 8, justifyContent: 'center' }}>
                    {kinds.map((k) => (
                      <span
                        key={k}
                        aria-hidden="true"
                        style={{
                          width: 6,
                          height: 6,
                          borderRadius: '50%',
                          background: KIND_COLOR[k],
                          display: 'inline-block',
                        }}
                      />
                    ))}
                  </span>
                </button>
              );
            })}
          </div>

          <Legend />
        </GlassCard>

        <GlassCard>
          <div className="fm-secondary" style={{ fontWeight: 600, fontSize: 14, marginBottom: 8 }}>
            {validSelection === null
              ? 'Select a day'
              : `${MONTHS[view.month - 1]} ${validSelection}, ${view.year}`}
          </div>
          {validSelection === null ? (
            <div className="fm-secondary" style={{ padding: '8px 0' }}>
              {loading ? 'Loading…' : 'Tap a day to see its income, subscriptions and bills.'}
            </div>
          ) : selectedEvents.length === 0 ? (
            <div className="fm-secondary" style={{ padding: '8px 0' }}>
              No events on this day.
            </div>
          ) : (
            <ul style={{ listStyle: 'none', margin: 0, padding: 0 }}>
              {selectedEvents.map((e, i) => (
                <li
                  key={`${e.kind}-${e.title}-${i}`}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'space-between',
                    padding: '10px 0',
                    borderTop: i === 0 ? 'none' : '1px solid var(--fm-glass-border)',
                  }}
                >
                  <span style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                    <span
                      aria-hidden="true"
                      style={{ width: 10, height: 10, borderRadius: '50%', background: KIND_COLOR[e.kind] }}
                    />
                    <span>
                      <span style={{ fontWeight: 600 }}>{e.title}</span>
                      <span className="fm-secondary" style={{ display: 'block', fontSize: 12 }}>
                        {KIND_LABEL[e.kind]}
                      </span>
                    </span>
                  </span>
                  <span
                    className="fm-amount"
                    style={{ color: e.kind === 'income' ? 'var(--fm-up)' : 'inherit' }}
                  >
                    {e.kind === 'income' ? '+' : '−'}
                    {fmt(e.amountMinor, e.currency)}
                  </span>
                </li>
              ))}
            </ul>
          )}
          <div className="fm-secondary" style={{ fontSize: 12, marginTop: 10 }}>
            Reminders are delivered as local notifications on iPhone. Remote push is post-v1.
          </div>
        </GlassCard>
      </div>
    </Page>
  );
}

function uniqueKinds(events: CalendarEvent[]): EventKind[] {
  const order: EventKind[] = ['income', 'subscription', 'fixedExpense'];
  return order.filter((k) => events.some((e) => e.kind === k));
}

function dayCellStyle(selected: boolean): CSSProperties {
  return {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    gap: 4,
    padding: '8px 0 6px',
    borderRadius: 'var(--fm-radius-sm)',
    border: selected ? '1px solid var(--fm-accent)' : '1px solid transparent',
    background: selected ? 'color-mix(in srgb, var(--fm-accent) 14%, transparent)' : 'transparent',
    color: 'var(--fm-label)',
    cursor: 'pointer',
    font: 'inherit',
  };
}

function NavButton({ label, glyph, onClick }: { label: string; glyph: string; onClick: () => void }) {
  return (
    <button
      type="button"
      aria-label={label}
      onClick={onClick}
      style={{
        width: 36,
        height: 36,
        borderRadius: 'var(--fm-radius-sm)',
        border: '1px solid var(--fm-glass-border)',
        background: 'var(--fm-glass-fill)',
        color: 'var(--fm-label)',
        cursor: 'pointer',
        fontSize: 20,
        lineHeight: 1,
      }}
    >
      {glyph}
    </button>
  );
}

function Legend() {
  const items: EventKind[] = ['income', 'subscription', 'fixedExpense'];
  return (
    <div style={{ display: 'flex', gap: 16, marginTop: 14, flexWrap: 'wrap' }}>
      {items.map((k) => (
        <span key={k} style={{ display: 'flex', alignItems: 'center', gap: 6 }} className="fm-secondary">
          <span
            aria-hidden="true"
            style={{ width: 8, height: 8, borderRadius: '50%', background: KIND_COLOR[k] }}
          />
          <span style={{ fontSize: 12 }}>{KIND_LABEL[k]}</span>
        </span>
      ))}
    </div>
  );
}
