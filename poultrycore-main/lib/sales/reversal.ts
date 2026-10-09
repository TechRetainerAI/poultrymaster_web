// Pure helpers for the Reverse Sale dialog (migration 351).
//
// The server decides everything that matters -- what each payment is allowed
// to do, the amounts, the blockers -- and re-checks it all when the reversal
// is confirmed. These only turn the preview plus the user's choices into the
// words and totals the dialog shows, so they can be tested without a page.

import type { PaymentAction, ReversalPaymentItem, SaleReversalPreview } from "@/lib/api/sale"

export type Handling = Record<string, PaymentAction>

/** The choices the dialog opens with: each payment's server default. */
export function defaultHandling(preview: Pick<SaleReversalPreview, "payments">): Handling {
  const h: Handling = {}
  for (const p of preview.payments) h[p.key] = p.default
  return h
}

/** A choice the server would refuse is never sent: fall back to the default. */
export function effectiveAction(item: ReversalPaymentItem, handling: Handling): PaymentAction {
  const chosen = handling[item.key]
  return chosen && item.allowed.includes(chosen) ? chosen : item.default
}

export interface ReversalOutcome {
  /** Becomes customer credit: the business still holds it. Cash unchanged. */
  creditCreated: number
  /** Paid back out of the original account(s): Money Out in Cash Flow. */
  cashOut: number
  /** Money Out per account name, for "Main Cash will decrease by ...". */
  cashOutByAccount: { account: string; amount: number }[]
}

const round2 = (n: number) => Math.round(n * 100) / 100

export function reversalOutcome(preview: Pick<SaleReversalPreview, "payments">, handling: Handling): ReversalOutcome {
  let credit = 0
  let out = 0
  const byAccount = new Map<string, number>()
  for (const p of preview.payments) {
    const amount = Number(p.allocated) || 0
    if (effectiveAction(p, handling) === "ReversePayment") {
      out += amount
      const name = p.cashAccountName || "its cash account"
      byAccount.set(name, (byAccount.get(name) ?? 0) + amount)
    } else {
      credit += amount
    }
  }
  return {
    creditCreated: round2(credit),
    cashOut: round2(out),
    cashOutByAccount: [...byAccount.entries()].map(([account, amount]) => ({ account, amount: round2(amount) })),
  }
}

/** How a payment's origin reads on the dialog. */
export function paymentSourceLabel(item: Pick<ReversalPaymentItem, "source" | "saleGenerated" | "recordedAtReversal">): string {
  if (item.recordedAtReversal) return "Received at the sale"
  if (item.source === "SaleEntry" && item.saleGenerated) return "Paid with this sale"
  if (item.source === "SaleEntry") return "Paid with this sale (shared)"
  if (item.source === "CustomerBalances") return "Customer payment"
  return item.source || "Payment"
}

/** "Restore 300 eggs (Large)" / "Restore 10 birds". */
export function restoreLabel(line: { restoreQuantity: number; restoreUnit: string | null; restoreProductName: string | null }): string | null {
  const qty = Number(line.restoreQuantity) || 0
  if (qty <= 0) return null
  const unit = line.restoreUnit === "birds" ? "birds" : "eggs"
  const n = Number.isInteger(qty) ? qty.toLocaleString() : qty.toLocaleString(undefined, { maximumFractionDigits: 3 })
  return line.restoreUnit === "birds" || !line.restoreProductName
    ? `${n} ${unit}`
    : `${n} ${unit} (${line.restoreProductName})`
}

/** A sale list filter value, applied to one row. */
export type SaleStatusFilter = "Active" | "Pending" | "Partial" | "Paid" | "Reversed" | "All"

export const SALE_STATUS_FILTERS: { value: SaleStatusFilter; label: string }[] = [
  { value: "Active", label: "Active" },
  { value: "Pending", label: "Pending" },
  { value: "Partial", label: "Partially paid" },
  { value: "Paid", label: "Paid" },
  { value: "Reversed", label: "Reversed" },
  { value: "All", label: "All" },
]

export function matchesStatusFilter(
  sale: { status?: string | null },
  paymentStatus: "Paid" | "Partial" | "Pending",
  filter: SaleStatusFilter,
): boolean {
  const reversed = sale.status === "Reversed"
  switch (filter) {
    case "All": return true
    case "Reversed": return reversed
    case "Active": return !reversed
    default: return !reversed && paymentStatus === filter
  }
}
