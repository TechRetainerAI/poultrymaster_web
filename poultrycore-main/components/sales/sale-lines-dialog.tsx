"use client"

// What was sold inside one or more poultry sales (358 sale lines), read-only.
//
// Opened from wherever a sale shows up as a single money row -- Customer
// Balances, Payments Received, Invoices -- so "Fresh Eggs · 2 lines" can be
// read as "Jumbo 10 crates, Large 5 crates" without leaving the page.
// Each sale is fetched fresh (GET Sale/{id} carries its lines).

import { useEffect, useState } from "react"
import { ExternalLink, Loader2 } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import { Table, TableBody, TableCell, TableFooter, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { useFmt } from "@/lib/currency"
import { formatDateShort } from "@/lib/utils"
import { getUserContext } from "@/lib/utils/user-context"
import { getSale, type Sale, type SaleLine } from "@/lib/api/sale"
import { getEggClasses, type EggClass } from "@/lib/api/egg-sorting"
import { EGGS_PER_CRATE } from "@/lib/production/production-record-calc"
import { useEggsPerCrate } from "@/hooks/use-eggs-per-crate"
import { byproductRole } from "@/lib/poultry/byproducts"

interface Props {
  /** The sales to show; null closes the dialog. */
  saleIds: number[] | null
  /** Optional heading, e.g. the payment number the sales were paid by. */
  title?: string
  onOpenChange: (open: boolean) => void
  /** Offered as "Open on Sales page" per sale when given. */
  onOpenSale?: (saleId: number) => void
}

const isEgg = (product: string | null | undefined) => (product ?? "").toLowerCase().includes("egg") && byproductRole(product) == null

/** "10 crates + 5 pcs" for eggs; the plain number otherwise. */
export function saleLineQuantityLabel(line: Pick<SaleLine, "product" | "quantity">): string {
  const q = Number(line.quantity) || 0
  if (!isEgg(line.product) || EGGS_PER_CRATE <= 0) return q.toLocaleString()
  const crates = Math.floor(q / EGGS_PER_CRATE)
  const pieces = q % EGGS_PER_CRATE
  const parts: string[] = []
  if (crates > 0) parts.push(`${crates.toLocaleString()} crate${crates === 1 ? "" : "s"}`)
  if (pieces > 0) parts.push(`${pieces} pc${pieces === 1 ? "" : "s"}`)
  return parts.length ? `${parts.join(" + ")} (${q.toLocaleString()} eggs)` : "0"
}

export function SaleLinesDialog({ saleIds, title, onOpenChange, onOpenSale }: Props) {
  useEggsPerCrate()
  const fmt = useFmt()
  const [sales, setSales] = useState<Sale[]>([])
  const [classes, setClasses] = useState<EggClass[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const key = saleIds?.join(",") ?? ""

  useEffect(() => {
    if (!saleIds?.length) { setSales([]); return }
    let cancelled = false
    setLoading(true)
    setError(null)
    const { userId, farmId } = getUserContext()
    ;(async () => {
      try {
        const [results, eggClasses] = await Promise.all([
          Promise.all(saleIds.map((id) => getSale(id, userId, farmId))),
          getEggClasses().catch(() => [] as EggClass[]),
        ])
        if (cancelled) return
        const found = results.filter((r) => r.success && r.data).map((r) => r.data as Sale)
        setSales(found)
        setClasses(eggClasses)
        if (!found.length) setError("This sale could not be loaded.")
      } catch (e: any) {
        if (!cancelled) setError(e?.message ?? "This sale could not be loaded.")
      } finally {
        if (!cancelled) setLoading(false)
      }
    })()
    return () => { cancelled = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key])

  const classLabel = (l: SaleLine) => {
    if (!isEgg(l.product)) return l.size || "—"
    const c = classes.find((x) => x.poultryProductId === l.eggProductId)
    if (c) return c.classKind === "Unsorted" ? "Unsorted" : c.name
    return l.size || "Unsorted"
  }

  return (
    <Dialog open={!!saleIds?.length} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-3xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{title ?? (saleIds && saleIds.length > 1 ? `${saleIds.length} sales` : "Sale details")}</DialogTitle>
          <DialogDescription>What was sold on {saleIds && saleIds.length > 1 ? "these sales" : "this sale"}, line by line.</DialogDescription>
        </DialogHeader>

        {loading ? (
          <div className="flex items-center gap-2 py-6 text-sm text-slate-500">
            <Loader2 className="h-4 w-4 animate-spin" /> Loading sale lines…
          </div>
        ) : error ? (
          <p className="py-6 text-sm text-red-600">{error}</p>
        ) : (
          <div className="space-y-5">
            {sales.map((s) => {
              // An older payload without lines reads as one line (the header).
              const lines: SaleLine[] = s.lines?.length ? s.lines : [{
                saleLineId: 0, lineNo: 1, product: s.product, eggProductId: s.eggProductId, size: s.size,
                quantity: s.quantity, unitPrice: s.unitPrice, totalAmount: s.totalAmount,
              }]
              const total = Number(s.totalAmount) || 0
              const paid = Number(s.amountPaid ?? (s.paid === false ? 0 : total)) || 0
              const reversed = s.status === "Reversed"
              return (
                <section key={s.saleId} className="space-y-2">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div className="flex items-center gap-2">
                      <span className="font-semibold text-slate-900">Sale {s.saleGroupNo ?? `#${s.saleId}`}</span>
                      {reversed
                        ? <Badge variant="outline" className="border-red-300 bg-red-50 text-red-700">Reversed</Badge>
                        : <Badge variant="outline" className="border-emerald-300 bg-emerald-50 text-emerald-700">Posted</Badge>}
                    </div>
                    {onOpenSale && (
                      <Button size="sm" variant="ghost" onClick={() => onOpenSale(s.saleId)}>
                        <ExternalLink className="mr-1.5 h-3.5 w-3.5" /> Open on Sales page
                      </Button>
                    )}
                  </div>
                  <div className="grid grid-cols-2 gap-x-4 gap-y-1 rounded-md border bg-slate-50 p-3 text-sm sm:grid-cols-4">
                    <div><span className="text-slate-500">Date</span><div className="font-medium">{formatDateShort(s.saleDate)}</div></div>
                    <div><span className="text-slate-500">Customer</span><div className="font-medium">{s.customerName || "Walk-in"}</div></div>
                    <div><span className="text-slate-500">Paid</span><div className="font-medium tabular-nums">{fmt(paid)}</div></div>
                    <div><span className="text-slate-500">Balance</span><div className="font-semibold tabular-nums">{reversed ? "—" : fmt(Math.max(0, total - paid))}</div></div>
                  </div>
                  <div className="overflow-x-auto rounded-md border">
                    <Table>
                      <TableHeader>
                        <TableRow className="bg-slate-100 hover:bg-slate-100">
                          <TableHead className="w-10">#</TableHead>
                          <TableHead>Product</TableHead>
                          <TableHead>Size / class</TableHead>
                          <TableHead className="text-right">Quantity</TableHead>
                          <TableHead className="text-right">Unit price</TableHead>
                          <TableHead className="text-right">Amount</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {lines.map((l) => (
                          <TableRow key={`${s.saleId}:${l.lineNo}`}>
                            <TableCell className="text-slate-500">{l.lineNo}</TableCell>
                            <TableCell className="font-medium">{l.product}</TableCell>
                            <TableCell>{classLabel(l)}</TableCell>
                            <TableCell className="text-right tabular-nums whitespace-nowrap">{saleLineQuantityLabel(l)}</TableCell>
                            <TableCell className="text-right tabular-nums">
                              {fmt(Number(l.unitPrice) || 0)}{isEgg(l.product) ? <span className="text-xs text-slate-500"> /crate</span> : null}
                            </TableCell>
                            <TableCell className="text-right font-medium tabular-nums">{fmt(Number(l.totalAmount) || 0)}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                      <TableFooter>
                        <TableRow>
                          <TableCell colSpan={5} className="text-right">Total</TableCell>
                          <TableCell className="text-right tabular-nums">{fmt(total)}</TableCell>
                        </TableRow>
                      </TableFooter>
                    </Table>
                  </div>
                </section>
              )
            })}
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}
