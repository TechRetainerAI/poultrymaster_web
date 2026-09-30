"use client"

// Stock days-of-supply on the poultry dashboard (migration 337): the items that
// will run out soonest, each with how long it lasts at its actual usage and a
// Restock button. Derived on each load; nothing is stored, so there is nothing
// to repeat or spam. Hidden when the company has no raw materials.

import { useEffect, useState } from "react"
import Link from "next/link"
import { CheckCircle2, Loader2, Package } from "lucide-react"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { cn } from "@/lib/utils"
import { useAuthStore } from "@/lib/store/auth-store"
import { getStockSupply } from "@/lib/api/stock-supply"
import {
  daysText,
  isActionable,
  qtyWithUnit,
  restockHref,
  sortBySeverity,
  stockoutText,
  supplyStatusStyle,
  type StockSupplyRow,
} from "@/lib/inventory/days-of-supply"

const SHOW = 5

export function StockSupplyCard() {
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const [rows, setRows] = useState<StockSupplyRow[] | null>(null)
  const [failed, setFailed] = useState(false)

  useEffect(() => {
    if (!activeFarmId) return
    let cancelled = false
    setRows(null)
    setFailed(false)
    getStockSupply()
      .then((r) => { if (!cancelled) setRows(sortBySeverity(r)) })
      .catch(() => { if (!cancelled) setFailed(true) })
    return () => { cancelled = true }
  }, [activeFarmId])

  // Quietly absent rather than an error box: this card is advisory.
  if (!activeFarmId || failed) return null
  if (rows == null) {
    return (
      <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
        <CardContent className="flex items-center gap-2 p-4 text-sm text-slate-500">
          <Loader2 className="h-4 w-4 animate-spin" /> Checking stock levels…
        </CardContent>
      </Card>
    )
  }
  if (rows.length === 0) return null

  const urgent = rows.filter((r) => isActionable(r.status))
  const healthy = rows.filter((r) => r.status === "Healthy").length
  const warning = rows[0]?.warningDays ?? 7

  return (
    <Card className={cn("rounded-xl border border-l-4 border-slate-200 bg-white shadow-sm",
      urgent.some((r) => supplyStatusStyle(r.status).tone === "bad") ? "border-l-rose-500"
        : urgent.length ? "border-l-amber-500" : "border-l-emerald-500")}>
      <CardContent className="space-y-3 p-4">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div className="flex items-start gap-3">
            <div className={cn("flex h-10 w-10 shrink-0 items-center justify-center rounded-lg",
              urgent.length ? "bg-amber-500" : "bg-emerald-500")}>
              <Package className="h-5 w-5 text-white" />
            </div>
            <div>
              <p className="text-xs font-medium uppercase tracking-wider text-slate-500">Stock Days of Supply</p>
              {urgent.length === 0 ? (
                <p className="mt-1 flex items-center gap-1.5 text-sm text-emerald-700">
                  <CheckCircle2 className="h-4 w-4" /> Nothing in use is expected to run out within {warning} days.
                </p>
              ) : (
                <p className="mt-1 text-sm text-slate-700">
                  <b>{urgent.length}</b> item{urgent.length === 1 ? " needs" : "s need"} attention
                  {healthy > 0 && <span className="text-slate-500"> · {healthy} healthy</span>}
                </p>
              )}
            </div>
          </div>
          <Button asChild variant="outline" size="sm">
            <Link href="/poultry-days-of-supply">View all</Link>
          </Button>
        </div>

        {urgent.length > 0 && (
          <ul className="divide-y divide-slate-100">
            {urgent.slice(0, SHOW).map((r) => {
              const st = supplyStatusStyle(r.status)
              const out = stockoutText(r)
              return (
                <li key={r.poultryRawMaterialItemId} className="flex flex-wrap items-center justify-between gap-2 py-2">
                  <div className="min-w-0">
                    <p className="text-sm">
                      <span className={cn("mr-2 rounded-full border px-2 py-0.5 text-[11px] font-medium uppercase", st.badge)}>{st.label}</span>
                      <span className="font-medium text-slate-900">{r.itemName}</span>
                      <span className="text-slate-600"> — {daysText(r)}</span>
                    </p>
                    <p className="text-xs text-slate-500">
                      {qtyWithUnit(r.currentQuantity, r.unitOfMeasure)} in stock
                      {r.avgDailyUsage != null && ` · using about ${qtyWithUnit(r.avgDailyUsage, r.unitOfMeasure)} a day`}
                      {out && ` · ${out}`}
                    </p>
                  </div>
                  <Button asChild size="sm" variant="outline" className="h-7 px-2.5 text-xs">
                    <Link href={restockHref(r.poultryRawMaterialItemId)}>Restock</Link>
                  </Button>
                </li>
              )
            })}
            {urgent.length > SHOW && (
              <li className="pt-2 text-xs text-slate-500">
                and {urgent.length - SHOW} more — <Link className="text-sky-700 underline" href="/poultry-days-of-supply">view all</Link>
              </li>
            )}
          </ul>
        )}
      </CardContent>
    </Card>
  )
}
