// TS mirror of Domain/SubscriptionPredictor.swift (docs/13 §10, ported from Substimate).
// Exact name match first, then case-insensitive substring; names < 2 chars never predict.

export interface SubscriptionPrediction {
  vendorURL: string | null;
  icon: string | null;
  /** Suggested cost in EUR minor units (cents). */
  suggestedAmountMinor: number | null;
  category: string;
}

interface Seed {
  url: string;
  icon: string;
  amountMinor: number | null;
}

const seed: Record<string, Seed> = {
  netflix: { url: 'netflix.com', icon: 'play.tv', amountMinor: 1299 },
  spotify: { url: 'spotify.com', icon: 'music.note', amountMinor: 1099 },
  chatgpt: { url: 'openai.com', icon: 'message', amountMinor: 2000 },
  openai: { url: 'openai.com', icon: 'message', amountMinor: 2000 },
  claude: { url: 'claude.com', icon: 'sparkles', amountMinor: 2000 },
  cursor: { url: 'cursor.sh', icon: 'code', amountMinor: 2000 },
  github: { url: 'github.com', icon: 'code', amountMinor: 1000 },
  midjourney: { url: 'midjourney.com', icon: 'photo', amountMinor: 1000 },
  notion: { url: 'notion.so', icon: 'doc', amountMinor: 1000 },
  figma: { url: 'figma.com', icon: 'ruler', amountMinor: 1500 },
  adobe: { url: 'adobe.com', icon: 'paintbrush', amountMinor: 5999 },
};

/** Ordered keyword -> category. First substring hit wins; default "Other". */
const keywordCategory: ReadonlyArray<readonly [kw: string, category: string]> = [
  ['chatgpt', 'AI Chat'],
  ['openai', 'AI Chat'],
  ['claude', 'AI Chat'],
  ['gemini', 'AI Chat'],
  ['cursor', 'Coding'],
  ['copilot', 'Coding'],
  ['github', 'Coding'],
  ['midjourney', 'Diffusion'],
  ['runway', 'Diffusion'],
  ['leonardo', 'Diffusion'],
  ['stable diffusion', 'Diffusion'],
  ['netflix', 'Streaming'],
  ['disney', 'Streaming'],
  ['hbo', 'Streaming'],
  ['prime video', 'Streaming'],
  ['spotify', 'Music'],
  ['apple music', 'Music'],
  ['tidal', 'Music'],
  ['notion', 'Productivity'],
  ['linear', 'Productivity'],
  ['trello', 'Productivity'],
  ['adobe', 'Creative'],
  ['figma', 'Creative'],
];

export function inferCategory(name: string): string {
  const n = name.toLowerCase();
  for (const [kw, category] of keywordCategory) {
    if (n.includes(kw)) return category;
  }
  return 'Other';
}

/**
 * Predict a prefill from a service name. Returns null only for names shorter
 * than 2 characters. Otherwise always returns at least an inferred category.
 */
export function predict(name: string): SubscriptionPrediction | null {
  const n = name.toLowerCase().trim();
  if (n.length < 2) return null;

  const exact = seed[n];
  if (exact) {
    return {
      vendorURL: exact.url,
      icon: exact.icon,
      suggestedAmountMinor: exact.amountMinor,
      category: inferCategory(n),
    };
  }
  for (const key of Object.keys(seed)) {
    if (n.includes(key)) {
      const s = seed[key];
      return {
        vendorURL: s.url,
        icon: s.icon,
        suggestedAmountMinor: s.amountMinor,
        category: inferCategory(n),
      };
    }
  }
  return { vendorURL: null, icon: null, suggestedAmountMinor: null, category: inferCategory(n) };
}

/**
 * Locale-aware number-string normalization (docs/13 §9.1). Turns user/CSV input
 * with grouping separators into a canonical POSIX `.`-decimal string for parseMoney.
 *
 * Heuristic: the LAST `.` or `,` is the decimal separator iff it is followed by
 * 1-2 fractional digits and there is exactly one such candidate; otherwise the
 * trailing group is treated as thousands. "1.234,56" and "1,234.56" both -> "1234.56".
 * Ambiguous "1,234" (a single separator with exactly 3 trailing digits and no
 * other separator) is left untouched so parseMoney REJECTS it — it could be a US
 * thousands group (1234) or a European decimal (1.234), and guessing would be lossy.
 */
export function normalizeNumberString(input: string): string {
  const t = input.trim();
  const lastDot = t.lastIndexOf('.');
  const lastComma = t.lastIndexOf(',');

  if (lastDot < 0 && lastComma < 0) return t;

  // The decimal separator is whichever of `.`/`,` appears LAST.
  const decimalSep = lastDot > lastComma ? '.' : ',';
  const groupSep = decimalSep === '.' ? ',' : '.';
  const decimalIndex = decimalSep === '.' ? lastDot : lastComma;
  const hasGroupSep = t.indexOf(groupSep) >= 0;
  const fractionLen = t.length - decimalIndex - 1;

  // Unambiguous decimal: both separators present (e.g. "1.234,56" / "1,234.56"),
  // or a lone separator with 1-2 trailing digits (e.g. "12,99" / "12.5").
  if (hasGroupSep || fractionLen <= 2) {
    const intPart = t.slice(0, decimalIndex).split(groupSep).join('');
    const fracPart = t.slice(decimalIndex + 1);
    return `${intPart}.${fracPart}`;
  }

  // Ambiguous single separator with 3 trailing digits (e.g. "1,234"): leave the
  // separator in place so parseMoney throws invalidNumber rather than guessing.
  return t;
}
