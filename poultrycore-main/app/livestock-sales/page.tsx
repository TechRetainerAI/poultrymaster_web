"use client"

// Sales -- animals, eggs, milk and other produce sold, and what is still owed.

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { Plus, ShoppingBag } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Switch } from "@/components/ui/switch"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { listSales, type Sale } from "@/lib/api/livestock"
import { PURCHASE_STATUS as STATUS, saleLineText } from "@/components/livestock/labels"
import { AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, StatCard, fmtDate, fmtMoney, todayIso } from "@/components/livestock/livestock-page"

const daysAgo = (n: number) => { const d = new Date(); d.setDate(d.getDate() - n); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}` }

export default function LivestockSalesPage() {
  const router = useRouter()
  const [rows, setRows] = useState<Sale[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [unpaidOnly, setUnpaidOnly] = useState(false)
  const [from, setFrom] = useState(daysAgo(30))
  const [to, setTo] = useState(todayIso())

  const load = useCallback(async () => {
    setError(null)
    try { setRows(await listSales(unpaidOnly ? { status: "Unpaid" } : { from, to })) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [unpaidOnly, from, to])
  useEffect(() => { load() }, [load])

  const live = useMemo(() => (rows ?? []).filter((s) => !s.reversedAt), [rows])
  const total = live.reduce((s, x) => s + x.total, 0)
  const owed = live.reduce((s, x) => s + x.owed, 0)
  const received = live.reduce((s, x) => s + x.paid, 0)

  return (
    <LivestockPage title="Sales" description="Animals, eggs, milk and other produce sold." icon={ShoppingBag}
      actions={
        <>
          <Button asChild variant="outline"><Link href="/livestock-customer-balances">Customer balances</Link></Button>
          <Button asChild className={AMBER_BUTTON}><Link href="/livestock-sales/new"><Plus className="h-4 w-4 mr-1" /> New sale</Link></Button>
        </>
      }>
      <div className="grid grid-cols-2 lg:grid-cols-3 gap-3">
        <StatCard label={unpaidOnly ? "Unpaid sales" : "Sold in these dates"} value={fmtMoney(total)} tone="amber" />
        <StatCard label="Received" value={fmtMoney(received)} tone="emerald" />
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
        <EmptyState title={unpaidOnly ? "Nothing is owed" : "No sales in these dates"} />
      ) : (
        <div className="rounded-md border bg-white overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow><TableHead>Date</TableHead><TableHead>Customer</TableHead><TableHead>What</TableHead><TableHead className="text-right">Total</TableHead><TableHead className="text-right">Owed</TableHead><TableHead>Status</TableHead></TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((s) => (
                <TableRow key={s.saleId} className={`cursor-pointer hover:bg-amber-50/60 ${s.reversedAt ? "opacity-50" : ""}`} onClick={() => router.push(`/livestock-sales/${s.saleId}`)}>
                  <TableCell className="whitespace-nowrap">{fmtDate(s.date)}</TableCell>
                  <TableCell>{s.customerName ?? <span className="text-stone-400">Walk-in</span>}</TableCell>
                  <TableCell className="text-sm text-stone-600 max-w-xs truncate">{s.lines.map(saleLineText).join(", ")}</TableCell>
                  <TableCell className="text-right">{fmtMoney(s.total)}</TableCell>
                  <TableCell className={`text-right ${s.overdue ? "text-rose-700 font-medium" : ""}`}>{s.owed > 0 ? fmtMoney(s.owed) : "—"}</TableCell>
                  <TableCell><Badge className={STATUS[s.status].cls}>{STATUS[s.status].label}</Badge>{s.overdue && <Badge className="ml-1 bg-rose-600">Overdue</Badge>}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}
    </LivestockPage>
  )
}
