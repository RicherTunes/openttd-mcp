/**
 * Shared utility functions.
 */

// OpenTTD stores money in GBP (base unit). Client displays with currency multiplier.
// Set OPENTTD_CURRENCY env var to match your in-game currency setting.
const CURRENCY = process.env.OPENTTD_CURRENCY ?? "GBP";
const RATES: Record<string, { symbol: string; rate: number }> = {
  GBP: { symbol: "\u00a3", rate: 1 },
  USD: { symbol: "$", rate: 2 },
  EUR: { symbol: "\u20ac", rate: 2 },
};
const { symbol, rate } = RATES[CURRENCY] ?? RATES.GBP;

export const CURRENCY_SYMBOL = symbol;
export const CURRENCY_RATE = rate;

export function formatMoney(baseAmount: number | string | bigint): string {
  const num =
    typeof baseAmount === "bigint"
      ? Number(baseAmount)
      : typeof baseAmount === "string"
        ? parseInt(baseAmount, 10)
        : baseAmount;
  return `${symbol}${(num * rate).toLocaleString()}`;
}
