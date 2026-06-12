
export type CurrencyCode = string

export function getSelectedCurrency(): CurrencyCode {
  if (typeof window === "undefined") return "GHS"
  const code = localStorage.getItem("currency") || "GHS"
  return code.toUpperCase()
}

export function setSelectedCurrency(code: CurrencyCode) {
  if (typeof window === "undefined") return
  localStorage.setItem("currency", code.toUpperCase())
}

export function getCurrencySymbol(code: CurrencyCode): string {
  const map: Record<string, string> = {
    GHS: "₵",
    USD: "$",
    EUR: "€",
    GBP: "£",
    NGN: "₦",
    KES: "KSh",
  }
  return map[code.toUpperCase()] || code.toUpperCase() + " "
}

export function formatCurrency(amount: number, code?: CurrencyCode): string {
  const currency = (code || getSelectedCurrency()).toUpperCase()
  const value = Number(amount || 0)
  const formatted = value.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })

  // Force Ghana cedi symbol output instead of locale-specific "GHS" text.
  if (currency === "GHS") {
    return `₵ ${formatted}`
  }

  try {
    // Prefer Intl if the currency is known
    return new Intl.NumberFormat(undefined, { style: "currency", currency }).format(value)
  } catch {
    // Fallback for unknown currencies
    const symbol = getCurrencySymbol(currency)
    return `${symbol}${formatted}`
  }
}


