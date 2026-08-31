/**
 * Every world currency, for the currency pickers on the setup pages.
 *
 * The list is derived from the platform's own ICU data rather than hardcoded:
 * `Intl.supportedValuesOf("currency")` returns the full ISO 4217 set the
 * runtime knows about (~300 codes), `Intl.DisplayNames` gives each one its
 * English name, and `Intl.NumberFormat` gives its symbol. That way the list is
 * complete on day one and stays correct as ICU data updates, instead of being a
 * table someone has to remember to extend.
 *
 * ISO_4217_FALLBACK covers runtimes without `supportedValuesOf` (added in
 * Chrome 99 / Safari 15.4 / Firefox 93 / Node 18). It is the active ISO 4217
 * list, so behaviour degrades to "complete but not auto-updating" rather than
 * to "six currencies".
 *
 * Codes are what gets stored. The database columns are varchar(10) — every ISO
 * code is 3 characters and the longest symbol here is 4, so both fit.
 */

export interface CurrencyOption {
  /** ISO 4217 alphabetic code, e.g. "GHS". This is what we persist. */
  code: string
  /** English display name, e.g. "Ghanaian Cedi". */
  name: string
  /** Best-known symbol, e.g. "₵". Falls back to the code when ICU has none. */
  symbol: string
}

/**
 * Shown first in the picker. A Ghana-based product where most companies trade
 * in cedis shouldn't make the user scroll past 200 entries to find GHS, and the
 * regional and reserve currencies are the realistic next choices.
 */
const PRIORITY_CODES = [
  "GHS", "NGN", "USD", "EUR", "GBP", "XOF", "XAF", "ZAR", "KES", "UGX", "TZS", "CFA",
]

/** Active ISO 4217 codes — used only when Intl.supportedValuesOf is missing. */
const ISO_4217_FALLBACK = [
  "AED", "AFN", "ALL", "AMD", "ANG", "AOA", "ARS", "AUD", "AWG", "AZN",
  "BAM", "BBD", "BDT", "BGN", "BHD", "BIF", "BMD", "BND", "BOB", "BOV",
  "BRL", "BSD", "BTN", "BWP", "BYN", "BZD", "CAD", "CDF", "CHE", "CHF",
  "CHW", "CLF", "CLP", "CNY", "COP", "COU", "CRC", "CUP", "CVE", "CZK",
  "DJF", "DKK", "DOP", "DZD", "EGP", "ERN", "ETB", "EUR", "FJD", "FKP",
  "GBP", "GEL", "GHS", "GIP", "GMD", "GNF", "GTQ", "GYD", "HKD", "HNL",
  "HTG", "HUF", "IDR", "ILS", "INR", "IQD", "IRR", "ISK", "JMD", "JOD",
  "JPY", "KES", "KGS", "KHR", "KMF", "KPW", "KRW", "KWD", "KYD", "KZT",
  "LAK", "LBP", "LKR", "LRD", "LSL", "LYD", "MAD", "MDL", "MGA", "MKD",
  "MMK", "MNT", "MOP", "MRU", "MUR", "MVR", "MWK", "MXN", "MXV", "MYR",
  "MZN", "NAD", "NGN", "NIO", "NOK", "NPR", "NZD", "OMR", "PAB", "PEN",
  "PGK", "PHP", "PKR", "PLN", "PYG", "QAR", "RON", "RSD", "RUB", "RWF",
  "SAR", "SBD", "SCR", "SDG", "SEK", "SGD", "SHP", "SLE", "SOS", "SRD",
  "SSP", "STN", "SVC", "SYP", "SZL", "THB", "TJS", "TMT", "TND", "TOP",
  "TRY", "TTD", "TWD", "TZS", "UAH", "UGX", "USD", "UYI", "UYU", "UYW",
  "UZS", "VED", "VES", "VND", "VUV", "WST", "XAF", "XCD", "XCG", "XDR",
  "XOF", "XPF", "XSU", "XUA", "YER", "ZAR", "ZMW", "ZWG",
]

function allCodes(): string[] {
  try {
    const supported = (Intl as any)?.supportedValuesOf?.("currency")
    if (Array.isArray(supported) && supported.length > 0) return supported as string[]
  } catch {
    // supportedValuesOf exists but threw — fall through to the static list.
  }
  return ISO_4217_FALLBACK
}

function nameFor(code: string, display: Intl.DisplayNames | null): string {
  try {
    return display?.of(code) || code
  } catch {
    return code
  }
}

export function currencySymbolFor(code: string): string {
  const c = (code || "").toUpperCase()
  if (!c) return ""
  // narrowSymbol gives "$" rather than "US$" / "NGN"; not every runtime accepts
  // it, so fall back to the wide symbol and finally to the code itself.
  for (const currencyDisplay of ["narrowSymbol", "symbol"] as const) {
    try {
      const parts = new Intl.NumberFormat("en", { style: "currency", currency: c, currencyDisplay })
        .formatToParts(0)
      const sym = parts.find((p) => p.type === "currency")?.value
      if (sym) return sym
    } catch {
      // try the next display mode
    }
  }
  return c
}

let cached: CurrencyOption[] | null = null

/**
 * Every currency, priority ones first then alphabetical by code.
 * Built once and memoized — assembling ~300 entries costs a few Intl calls each.
 */
export function getAllCurrencies(): CurrencyOption[] {
  if (cached) return cached

  let display: Intl.DisplayNames | null = null
  try {
    display = new Intl.DisplayNames(["en"], { type: "currency" })
  } catch {
    display = null
  }

  const codes = Array.from(new Set(allCodes().map((c) => c.toUpperCase()))).sort()
  const options = codes.map<CurrencyOption>((code) => ({
    code,
    name: nameFor(code, display),
    symbol: currencySymbolFor(code),
  }))

  const rank = (code: string) => {
    const i = PRIORITY_CODES.indexOf(code)
    return i === -1 ? PRIORITY_CODES.length : i
  }
  options.sort((a, b) => rank(a.code) - rank(b.code) || a.code.localeCompare(b.code))

  cached = options
  return options
}

/** Look up one currency; returns undefined for a code the runtime doesn't know. */
export function findCurrency(code: string | null | undefined): CurrencyOption | undefined {
  if (!code) return undefined
  const c = code.toUpperCase()
  return getAllCurrencies().find((o) => o.code === c)
}

/** "GHS — Ghanaian Cedi (₵)", for triggers and summaries. */
export function formatCurrencyOption(o: CurrencyOption): string {
  return o.symbol && o.symbol !== o.code ? `${o.code} — ${o.name} (${o.symbol})` : `${o.code} — ${o.name}`
}
