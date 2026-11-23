"use client"

// Sales -- animals, eggs, milk and other produce sold, and what is still owed.
// Dates (or "still owed, any date") are asked of the server; search, status,
// customer, animal and what was sold narrow the loaded list here.

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { Plus, Search, ShoppingBag, X } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { DataPagination } from "@/components/ui/data-pagination"
import { PeriodSelect } from "@/components/ui/period-select"
import { rangeToPeriod, type DateRange, type PeriodKey } from "@/lib/date-ranges"
import { usePagination } from "@/hooks/use-pagination"
import { listSales, type Sale, type SaleLineType } from "@/lib/api/livestock"
import { PURCHASE_STATUS as STATUS, saleLineText } from "@/components/livestock/labels"
import { AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, StatCard, fmtDate, fmtMoney, todayIso } from "@/components/livestock/livestock-page"

const ALL = "__all"
const WALK_IN = "__walkin"
const daysAgo = (n: number) => { const d = new Date(); d.setDate(d.getDate() - n); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}` }

type StatusFilter = typeof ALL | "Owed" | "Unpaid" | "PartPaid" | "Paid" | "Overdue" | "Reversed"
const KIND_LABEL: Record<SaleLineType, string> = { Animals: "Animals from a group", Tagged: "Tagged animals", Product: "Eggs, milk, stock" }

export default function LivestockSalesPage() {
  const router = useRouter()
  const [rows, setRows] = useState<Sale[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [from, setFrom] = useState(daysAgo(30))
  const [to, setTo] = useState(todayIso())
  const [search, setSearch] = useState("")
  const [status, setStatus] = useState<StatusFilter>(ALL)
  const [customer, setCustomer] = useState(ALL)
  const [animal, setAnimal] = useState(ALL)
  const [kind, setKind] = useState<SaleLineType | typeof ALL>(ALL)

  // "Still owed" looks at every date, as the old switch did.
  const owedAnyDate = status === "Owed"
  const load = useCallback(async () => {
    setError(null)
    try { setRows(await listSales(owedAnyDate ? { status: "Unpaid" } : { from, to })) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [owedAnyDate, from, to])
  useEffect(() => { load() }, [load])

  const all = rows ?? []
  const customers = useMemo(() => {
    const m = new Map<string, string>()
    for (const s of all) if (s.customerId != null) m.set(String(s.customerId), s.customerName ?? "Customer")
    return [...m.entries()].sort((a, b) => a[1].localeCompare(b[1]))
  }, [all])
  const animals = useMemo(() => [...new Set(all.flatMap((s) => s.lines.map((l) => l.speciesName)).filter((x): x is string => !!x))].sort(), [all])

  const shown = useMemo(() => {
    const q = search.trim().toLowerCase()
    return all.filter((s) => {
      if (status === "Unpaid" || status === "PartPaid" || status === "Paid" || status === "Reversed") { if (s.status !== status) return false }
      if (status === "Overdue" && !s.overdue) return false
      if (customer === WALK_IN ? s.customerId != null : customer !== ALL && String(s.customerId) !== customer) return false
      if (animal !== ALL && !s.lines.some((l) => l.speciesName === animal)) return false
      if (kind !== ALL && !s.lines.some((l) => l.lineType === kind)) return false
      if (q && ![s.reference, s.customerName ?? "Walk-in", s.notes, ...s.lines.map(saleLineText)].some((v) => v?.toLowerCase().includes(q))) return false
      return true
    })
  }, [all, search, status, customer, animal, kind])

  const live = useMemo(() => shown.filter((s) => !s.reversedAt), [shown])
  const total = live.reduce((s, x) => s + x.total, 0)
  const owed = live.reduce((s, x) => s + x.owed, 0)
  const received = live.reduce((s, x) => s + x.paid, 0)
  const pg = usePagination(shown, 10)

  const filtering = !!search || status !== ALL || customer !== ALL || animal !== ALL || kind !== ALL || from !== daysAgo(30) || to !== todayIso()
  const clear = () => { setSearch(""); setStatus(ALL); setCustomer(ALL); setAnimal(ALL); setKind(ALL); setFrom(daysAgo(30)); setTo(todayIso()) }
  const periodOf = (f: string, t: string): PeriodKey => (!f && !t ? "allTime" : rangeToPeriod(f, t))
  const applyPeriod = (p: PeriodKey, rg: DateRange | null) => {
    if (p === "allTime") { setFrom(""); setTo("") } else if (rg) { setFrom(rg.from); setTo(rg.to) }
  }

  return (
    <LivestockPage title="Sales" description="Animals, eggs, milk and other produce sold." icon={ShoppingBag}
      actions={
        <>
          <Button asChild variant="outline"><Link href="/livestock-customer-balances">Customer balances</Link></Button>
          <Button asChild className={AMBER_BUTTON}><Link href="/livestock-sales/new"><Plus className="h-4 w-4 mr-1" /> New sale</Link></Button>
        </>
      }>
      <div className="grid grid-cols-2 lg:grid-cols-3 gap-3">
        <StatCard label={owedAnyDate ? "Sales still owed" : "Sold"} value={fmtMoney(total)} tone="amber" />
        <StatCard label="Received" value={fmtMoney(received)} tone="emerald" />
        <StatCard label="Still owed" value={fmtMoney(owed)} tone={owed > 0 ? "rose" : "stone"} />
      </div>

      <div className="flex flex-wrap items-center gap-2 rounded-lg border bg-white p-2">
        <div className="relative min-w-[180px] flex-[1.4]">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-stone-400" />
          <Input className="pl-9" placeholder="Sale no., customer or item" value={search} onChange={(e) => setSearch(e.target.value)} />
        </div>
        {!owedAnyDate && (
          <>
            <PeriodSelect label={null} className="w-40" value={periodOf(from, to)} onChange={applyPeriod} />
            <Input type="date" className="w-[140px]" value={from} max={to || todayIso()} onChange={(e) => setFrom(e.target.value)} aria-label="From" />
            <Input type="date" className="w-[140px]" value={to} min={from} max={todayIso()} onChange={(e) => setTo(e.target.value)} aria-label="To" />
          </>
        )}
        <Select value={status} onValueChange={(v) => setStatus(v as StatusFilter)}>
          <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>Any status</SelectItem>
            <SelectItem value="Owed">Still owed (any date)</SelectItem>
            <SelectItem value="Unpaid">Not paid</SelectItem>
            <SelectItem value="PartPaid">Part paid</SelectItem>
            <SelectItem value="Paid">Paid</SelectItem>
            <SelectItem value="Overdue">Overdue</SelectItem>
            <SelectItem value="Reversed">Reversed</SelectItem>
          </SelectContent>
        </Select>
        <Select value={customer} onValueChange={setCustomer}>
          <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>All customers</SelectItem>
            <SelectItem value={WALK_IN}>Walk-in</SelectItem>
            {customers.map(([id, name]) => <SelectItem key={id} value={id}>{name}</SelectItem>)}
          </SelectContent>
        </Select>
        <Select value={animal} onValueChange={setAnimal}>
          <SelectTrigger className="w-36"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>All animals</SelectItem>
            {animals.map((a) => <SelectItem key={a} value={a}>{a}</SelectItem>)}
          </SelectContent>
        </Select>
        <Select value={kind} onValueChange={(v) => setKind(v as SaleLineType | typeof ALL)}>
          <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>Anything sold</SelectItem>
            {(Object.keys(KIND_LABEL) as SaleLineType[]).map((k) => <SelectItem key={k} value={k}>{KIND_LABEL[k]}</SelectItem>)}
          </SelectContent>
        </Select>
        {filtering && <Button variant="ghost" size="sm" className="text-amber-800" onClick={clear}><X className="h-4 w-4 mr-1" />Clear filters</Button>}
        {rows && <span className="ml-auto pr-1 text-sm text-stone-500">{shown.length === all.length ? `${all.length} sales` : `${shown.length} of ${all.length} sales`}</span>}
      </div>

      {error ? <LoadError message={error} onRetry={load} /> : !rows ? <Loading /> : shown.length === 0 ? (
        <EmptyState title={filtering ? "No sale matches" : "No sales in these dates"}>{filtering ? "Try other filters, or clear them." : undefined}</EmptyState>
      ) : (
        <div className="rounded-md border bg-white overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow><TableHead>Sale no.</TableHead><TableHead>Date</TableHead><TableHead>Customer</TableHead><TableHead>What</TableHead><TableHead className="text-right">Total</TableHead><TableHead className="text-right">Owed</TableHead><TableHead>Status</TableHead></TableRow>
            </TableHeader>
            <TableBody>
              {pg.pageItems.map((s) => (
                <TableRow key={s.saleId} className={`cursor-pointer hover:bg-amber-50/60 ${s.reversedAt ? "opacity-50" : ""}`} onClick={() => router.push(`/livestock-sales/${s.saleId}`)}>
                  <TableCell className="font-medium whitespace-nowrap">{s.reference ?? "—"}</TableCell>
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
          <DataPagination {...pg.paginationProps} variant="records" />
        </div>
      )}
    </LivestockPage>
  )
}
