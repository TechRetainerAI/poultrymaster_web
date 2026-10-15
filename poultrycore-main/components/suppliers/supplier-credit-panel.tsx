"use client"

// Supplier credit (370), shown under the table on Poultry Supplier Balances --
// the supplier-side twin of the Customer credit panel on Customer Balances.
//
// "We owe the supplier" and "the supplier is holding our money" (advances,
// overpayments, credit notes) are different things, so they are shown side by
// side and never netted. Applying, refunding and the full history live on
// /supplier-credits; this panel only says what is held and links there.

import { useEffect, useState } from "react"
import Link from "next/link"
import { PiggyBank } from "lucide-react"
import { Card, CardContent } from "@/components/ui/card"
import { formatCurrency, getSelectedCurrency } from "@/lib/utils/currency"
import { useCurrency } from "@/lib/currency"
import { listSupplierCredit, type SupplierCreditSummaryRow } from "@/lib/api/supplier-credit"

export function SupplierCreditPanel() {
  const { code } = useCurrency()
  const currencyCode = code || getSelectedCurrency()
  const [rows, setRows] = useState<SupplierCreditSummaryRow[]>([])
  const [loaded, setLoaded] = useState(false)

  useEffect(() => {
    listSupplierCredit()
      .then((r) => setRows(r.filter((x) => (Number(x.availableCredit) || 0) > 0)))
      .catch(() => setRows([]))
      .finally(() => setLoaded(true))
  }, [])

  // Nothing held by any supplier: say nothing, the page is about what we owe.
  if (!loaded || rows.length === 0) return null

  const total = rows.reduce((t, r) => t + (Number(r.availableCredit) || 0), 0)
  const money = (n: number) => formatCurrency(Number(n) || 0, currencyCode)

  return (
    <Card className="mb-4 border-blue-200">
      <CardContent className="space-y-3 p-4">
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <h2 className="flex items-center gap-2 text-sm font-semibold text-slate-900">
            <PiggyBank className="h-4 w-4 text-blue-600" /> Supplier credit
            <span className="font-normal text-slate-500">— money suppliers are holding for us, not on any purchase</span>
          </h2>
          <span className="flex items-center gap-3">
            <span className="text-sm font-semibold tabular-nums text-blue-700">{money(total)} held</span>
            <Link href="/supplier-credits" className="text-xs font-medium text-blue-700 hover:underline">Open Supplier Credits</Link>
          </span>
        </div>
        <div className="grid gap-2 sm:grid-cols-2 xl:grid-cols-3">
          {rows.map((r) => (
            <div key={r.supplierId} className="rounded-md border p-3">
              <p className="truncate text-sm font-medium text-slate-900">{r.supplierName}</p>
              <p className="text-xs text-slate-500">
                Credit <span className="font-semibold tabular-nums text-blue-700">{money(r.availableCredit)}</span>
                {" · "}We owe <span className="tabular-nums">{money(r.owed)}</span>
              </p>
            </div>
          ))}
        </div>
        <p className="text-xs text-slate-500">
          To use credit on a purchase or get it refunded, open Supplier Credits. No new money is recorded when credit is applied.
        </p>
      </CardContent>
    </Card>
  )
}
