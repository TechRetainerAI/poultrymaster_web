"use client"

/**
 * Currency formatting for the poultry pages.
 *
 * There used to be TWO currency stores in this app and they did not agree:
 *
 *   * lib/currency.ts  — the Farms row (currencyCode / currencySymbol /
 *     showCurrencySymbol), written by the setup pages and read by ~80 files
 *     through fmtMoney().
 *   * this file — a bare code in localStorage under "currency", read by
 *     /sales, /cash, /expenses, the dashboard metrics cards, the poultry
 *     dashboard view and the monthly financial statement.
 *
 * Picking a currency in setup therefore changed most of the app but left those
 * six screens on whatever the old /settings page had written, and the two
 * rendered differently anyway — Intl's "GH₵1,234.50" versus fmtMoney's
 * "GHC 1,234.50".
 *
 * The Farms row is now the single source of truth. These helpers keep their old
 * signatures so their callers did not have to change, but they read the store
 * and render exactly what fmtMoney() renders, including the operator's own
 * symbol text and their show/hide choice.
 */

import { useFarmSettingsStore } from "@/lib/currency"
import { currencySymbolFor } from "@/lib/constants/currencies"

export type CurrencyCode = string

const DEFAULTS = { currencyCode: "GHS", currencySymbol: "GHC", showCurrencySymbol: true }

/**
 * The active company's currency settings. Falls back to the legacy localStorage
 * key while the store is still loading (or for a company that has never been
 * through setup) so nothing renders blank on first paint.
 */
function farmSettings(): { currencyCode: string; currencySymbol: string; showCurrencySymbol: boolean } {
  if (typeof window === "undefined") return DEFAULTS
  const s = useFarmSettingsStore.getState().settings
  if (s?.currencyCode) return s
  const legacy = localStorage.getItem("currency")
  if (legacy) {
    const code = legacy.toUpperCase()
    return { currencyCode: code, currencySymbol: currencySymbolFor(code), showCurrencySymbol: true }
  }
  return DEFAULTS
}

/** The company's currency code, e.g. "GHS". */
export function getSelectedCurrency(): CurrencyCode {
  return (farmSettings().currencyCode || DEFAULTS.currencyCode).toUpperCase()
}

/**
 * Symbol for a code. Returns the operator's own symbol text when asked for the
 * company's currency — they may write "GHC" where ICU says "GH₵" — and the ICU
 * symbol for anything else.
 */
export function getCurrencySymbol(code: CurrencyCode): string {
  const c = (code || "").toUpperCase()
  const s = farmSettings()
  if (c && c === s.currencyCode.toUpperCase() && s.currencySymbol) return s.currencySymbol
  const sym = currencySymbolFor(c)
  return sym === c ? c + " " : sym
}

/**
 * formatCurrency(1234.5) → "GHC 1,234.50", identical to fmtMoney().
 *
 * Passing an explicit code formats in that currency instead — used where a
 * screen genuinely shows a foreign amount rather than the company's own.
 */
export function formatCurrency(amount: number, code?: CurrencyCode): string {
  const s = farmSettings()
  const currency = (code || s.currencyCode || DEFAULTS.currencyCode).toUpperCase()
  const value = Number(amount || 0)
  const formatted = value.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })

  // The company's own currency: mirror fmtMoney() exactly. This is what keeps
  // /sales, /cash and /expenses reading the same as every report.
  if (currency === s.currencyCode.toUpperCase()) {
    return s.showCurrencySymbol ? `${s.currencySymbol} ${formatted}` : formatted
  }

  return `${currencySymbolFor(currency)} ${formatted}`
}
