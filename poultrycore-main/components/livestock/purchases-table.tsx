"use client"

// The purchases list, shared by Purchases (/livestock-purchases) and the
// Purchases tab on Feed & stock. Shows what each came to, what was paid and
// what is still owed. A row opens the purchase.

import { useRouter } from "next/navigation"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import type { Purchase, PurchaseLine } from "@/lib/api/livestock"
import { PURCHASE_STATUS } from "@/components/livestock/labels"
import { StatCard, fmtDate, fmtMoney, fmtNum } from "@/components/livestock/livestock-page"

function lineText(l: PurchaseLine, withQty: boolean) {
  if (l.lineType === "Item") return withQty ? `${l.itemName} · ${fmtNum(l.quantity)} ${l.unit ?? ""}`.trim() : l.itemName
  if (l.lineType === "Expense") return l.description ?? l.expenseCategory
  return `${l.quantity} ${l.speciesName?.toLowerCase()}`
}

/** Bought / Paid / Still owed for the purchases shown (reversed ones left out). */
export function PurchaseTotals({ rows, boughtLabel = "Bought" }: { rows: Purchase[]; boughtLabel?: string }) {
  const live = rows.filter((p) => !p.reversedAt)
  const total = live.reduce((s, p) => s + p.total, 0)
  const paid = live.reduce((s, p) => s + p.paid, 0)
  const owed = live.reduce((s, p) => s + p.owed, 0)
  return (
    <div className="grid grid-cols-2 lg:grid-cols-3 gap-3">
      <StatCard label={boughtLabel} value={fmtMoney(total)} tone="amber" />
      <StatCard label="Paid" value={fmtMoney(paid)} tone="emerald" />
      <StatCard label="Still owed" value={fmtMoney(owed)} tone={owed > 0 ? "rose" : "stone"} />
    </div>
  )
}

export function PurchasesTable({ rows, itemsOnly = false }: { rows: Purchase[]; itemsOnly?: boolean }) {
  const router = useRouter()
  return (
    <div className="rounded-md border bg-white overflow-x-auto">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Date</TableHead>
            <TableHead>Invoice no.</TableHead>
            <TableHead>Supplier</TableHead>
            <TableHead>What</TableHead>
            <TableHead className="text-right">Total</TableHead>
            <TableHead className="text-right">Paid</TableHead>
            <TableHead className="text-right">Owed</TableHead>
            <TableHead>Status</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((p) => {
            const lines = itemsOnly ? p.lines.filter((l) => l.lineType === "Item") : p.lines
            return (
              <TableRow key={p.purchaseId} className={`cursor-pointer hover:bg-amber-50/60 ${p.reversedAt ? "opacity-50" : ""}`}
                onClick={() => router.push(`/livestock-purchases/${p.purchaseId}`)}>
                <TableCell className="whitespace-nowrap">{fmtDate(p.date)}</TableCell>
                <TableCell className="whitespace-nowrap font-medium">{p.reference ?? "—"}</TableCell>
                <TableCell>{p.supplierName ?? <span className="text-stone-400">Cash, no supplier</span>}</TableCell>
                <TableCell className="text-sm text-stone-600 max-w-xs truncate">{lines.map((l) => lineText(l, itemsOnly)).join(", ")}</TableCell>
                <TableCell className="text-right">{fmtMoney(p.total)}</TableCell>
                <TableCell className="text-right text-emerald-700">{p.paid > 0 ? fmtMoney(p.paid) : "—"}</TableCell>
                <TableCell className={`text-right ${p.overdue ? "text-rose-700 font-medium" : ""}`}>{p.owed > 0 ? fmtMoney(p.owed) : "—"}</TableCell>
                <TableCell className="whitespace-nowrap">
                  <Badge className={PURCHASE_STATUS[p.status].cls}>{PURCHASE_STATUS[p.status].label}</Badge>
                  {p.overdue && <Badge className="ml-1 bg-rose-600">Overdue</Badge>}
                </TableCell>
              </TableRow>
            )
          })}
        </TableBody>
      </Table>
    </div>
  )
}
