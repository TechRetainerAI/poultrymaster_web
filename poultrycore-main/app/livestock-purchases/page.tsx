"use client"

// Purchases -- stock and animals bought, what each came to, and what is still
// owed. The poultry Supply Purchases page for livestock.

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { Plus, ShoppingCart } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Switch } from "@/components/ui/switch"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { listPurchases, type Purchase } from "@/lib/api/livestock"
import { PURCHASE_STATUS } from "@/components/livestock/labels"
import { AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, StatCard, fmtDate, fmtMoney, todayIso } from "@/components/livestock/livestock-page"

const daysAgo = (n: number) => { const d = new Date(); d.setDate(d.getDate() - n); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}` }

export default function LivestockPurchasesPage() {
  const router = useRouter()
  const [rows, setRows] = useState<Purchase[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [unpaidOnly, setUnpaidOnly] = useState(false)
  const [from, setFrom] = useState(daysAgo(60))
  const [to, setTo] = useState(todayIso())

  const load = useCallback(async () => {
    setError(null)
    try { setRows(await listPurchases(unpaidOnly ? { status: "Unpaid" } : { from, to })) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [unpaidOnly, from, to])
  useEffect(() => { load() }, [load])

  const live = useMemo(() => (rows ?? []).filter((p) => !p.reversedAt), [rows])
  const total = live.reduce((s, p) => s + p.total, 0)
  const owed = live.reduce((s, p) => s + p.owed, 0)

  return (
    <LivestockPage
      title="Purchases"
      description="Feed, medicine, supplies and animals bought, and what is still owed."
      icon={ShoppingCart}
      actions={
        <>
          <Button asChild variant="outline"><Link href="/livestock-supplier-balances">Supplier balances</Link></Button>
          <Button asChild className={AMBER_BUTTON}><Link href="/livestock-purchases/new"><Plus className="h-4 w-4 mr-1" /> New purchase</Link></Button>
        </>
      }
    >
      <div className="grid grid-cols-2 lg:grid-cols-3 gap-3">
        <StatCard label={unpaidOnly ? "Unpaid purchases" : "Bought in these dates"} value={fmtMoney(total)} tone="amber" />
        <StatCard label="Still owed" value={fmtMoney(owed)} tone={owed > 0 ? "rose" : "stone"} />
      </div>
      <div className="flex items-center gap-3 flex-wrap">
        <label className="flex items-center gap-2 text-sm text-stone-600"><Switch checked={unpaidOnly} onCheckedChange={setUnpaidOnly} /> Only what is still owed</label>
        {!unpaidOnly && (
          <>
            <Input type="date" className="w-40" value={from} max={to} onChange={(e) => setFrom(e.target.value)} aria-label="From" />
            <span className="text-sm text-stone-500">to</span>
            <Input type="date" className="w-40" value={to} min={from} max={todayIso()} onChange={(e) => setTo(e.target.value)} aria-label="To" />
          </>
        )}
      </div>

      {error ? <LoadError message={error} onRetry={load} /> : !rows ? <Loading /> : rows.length === 0 ? (
        <EmptyState title={unpaidOnly ? "Nothing is owed" : "No purchases in these dates"} />
      ) : (
        <div className="rounded-md border bg-white overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Date</TableHead><TableHead>Supplier</TableHead><TableHead>What</TableHead>
                <TableHead className="text-right">Total</TableHead><TableHead className="text-right">Owed</TableHead><TableHead>Status</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((p) => (
                <TableRow key={p.purchaseId} className={`cursor-pointer hover:bg-amber-50/60 ${p.reversedAt ? "opacity-50" : ""}`} onClick={() => router.push(`/livestock-purchases/${p.purchaseId}`)}>
                  <TableCell className="whitespace-nowrap">{fmtDate(p.date)}</TableCell>
                  <TableCell>{p.supplierName ?? <span className="text-stone-400">Cash, no supplier</span>}{p.reference && <div className="text-xs text-stone-500">{p.reference}</div>}</TableCell>
                  <TableCell className="text-sm text-stone-600 max-w-xs truncate">
                    {p.lines.map((l) => l.lineType === "Item" ? l.itemName : l.lineType === "Expense" ? (l.description ?? l.expenseCategory) : `${l.quantity} ${l.speciesName?.toLowerCase()}`).join(", ")}
                  </TableCell>
                  <TableCell className="text-right">{fmtMoney(p.total)}</TableCell>
                  <TableCell className={`text-right ${p.overdue ? "text-rose-700 font-medium" : ""}`}>{p.owed > 0 ? fmtMoney(p.owed) : "—"}</TableCell>
                  <TableCell>
                    <Badge className={PURCHASE_STATUS[p.status].cls}>{PURCHASE_STATUS[p.status].label}</Badge>
                    {p.overdue && <Badge className="ml-1 bg-rose-600">Overdue</Badge>}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}
    </LivestockPage>
  )
}
