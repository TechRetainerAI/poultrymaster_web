"use client"

// Payments Received — the customer payment ledger.
//
// ONE ROW PER REAL PAYMENT. The old page listed `poultrypayments` rows, and
// that table stores one row per SALE, so a single GHC 4,820 payment split
// across two sales appeared here as two payments. It never was two payments:
// migration 223 groups the rows under a `paymentgroupid` and records how much
// of the payment each sale received in `customerpaymentallocation`, with the
// sale's balance before and after captured at the moment it was posted. This
// page reads that grouped view, so what you see is the money the customer
// actually handed over, and the allocation is the detail underneath it.
//
// A payment against one sale shows its allocation inline -- sale, and the
// balance it moved from and to -- because expanding a row to read one line is
// friction for the common case. A payment across several sales shows the count
// and expands.
//
// ONE ROW PER SALE WHERE A SALE WAS PART-PAID. Listing every instalment as its
// own row put the same sale on screen two and three times over, and the trail
// under the newest one then repeated it again. So only the newest payment for
// a sale keeps a row; the earlier ones are folded into its trail, which now
// carries their Reverse action -- nothing is lost with the row.

import { Fragment, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ListFilters } from "@/components/ui/list-filters"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { ChevronDown, ChevronRight, Loader2, Undo2, Wallet } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import {
  getPayment, listPayments, reversePayment,
  type BalanceModule, type PaymentAllocationRow, type PaymentHistoryRow,
} from "@/lib/api/balances"

// Where the payment was taken. The raw codes are what the API stores; these are
// what a person reads. Anything unrecognised falls through unchanged.
const SOURCE_LABEL: Record<string, string> = {
  SaleEntry: "Sale",
  CustomerBalances: "Balances",
  CustomerProfile: "Customer",
  PaymentsPage: "Payments",
  ImportedPayment: "Imported",
  Backfill: "Backfill",
}
const sourceLabel = (s?: string | null) => (s ? SOURCE_LABEL[s] ?? s : "—")

/**
 * The payment as a person refers to it: PAY-0001.
 *
 * Migration 240 numbers every payment per company. Until it is applied -- and
 * on the supplier side, which has no numbering -- there is only the group uuid,
 * so fall back to its first block rather than showing an empty column.
 */
const paymentRef = (row: { paymentNumber?: string | null; paymentId: string }) =>
  row.paymentNumber?.trim() || `#${String(row.paymentId).slice(0, 8)}`

export interface PaymentsReceivedPageProps {
  module: BalanceModule
  /** Guard: this page belongs to one company type. */
  companyType: string
  /** Deep link to a sale, or null when it has no page. */
  saleHref: (saleId: number) => string | null
  /** IAM keys gating this page. */
  permissions: { view: string; reverse: string }
}

export function PaymentsReceivedPage({
  module, companyType, saleHref, permissions,
}: PaymentsReceivedPageProps) {
  const fmt = useFmt()
  const router = useRouter()
  const { toast } = useToast()
  const logout = useLogout()
  const { can, isLoading: permsLoading } = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [rows, setRows] = useState<PaymentHistoryRow[]>([])
  const [loading, setLoading] = useState(true)
  const [allocations, setAllocations] = useState<Record<string, PaymentAllocationRow[]>>({})
  // Every payment made against one sale, keyed by sale id. A sale part-paid
  // three times is three separate one-sale payments, and the interesting thing
  // is the trail they form -- which no single row can show.
  const [saleTrails, setSaleTrails] = useState<Record<number, PaymentHistoryRow[]>>({})
  const [expanded, setExpanded] = useState<string | null>(null)
  const [reverseTarget, setReverseTarget] = useState<PaymentHistoryRow | null>(null)
  const [reason, setReason] = useState("")
  const [reversing, setReversing] = useState(false)

  // Filters
  const [search, setSearch] = useState("")
  const [from, setFrom] = useState("")
  const [to, setTo] = useState("")
  const [method, setMethod] = useState("all")
  const [source, setSource] = useState("all")
  const [status, setStatus] = useState("Posted")
  const [appliedTo, setAppliedTo] = useState("all")

  const canView = can(permissions.view)
  const canReverse = can(permissions.reverse)

  const load = async () => {
    setLoading(true)
    try {
      const list = await listPayments(module, "customer", { from: from || null, to: to || null })
      setRows(list)
      // Allocations are keyed by payment, so a reload has to drop the cache or
      // a reversed payment would keep showing its pre-reversal allocation.
      setAllocations({})
      // Same for the trails: a reversal posted from inside one would otherwise
      // keep showing that payment as posted.
      setSaleTrails({})
    } catch (e: any) {
      toast({ title: "Could not load payments", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== companyType) { router.replace("/dashboard"); return }
    if (permsLoading || !canView) return
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, companyType, permsLoading, canView, from, to])

  const methods = useMemo(
    () => Array.from(new Set(rows.map((r) => r.paymentMethod).filter(Boolean) as string[])).sort(),
    [rows],
  )
  const sources = useMemo(
    () => Array.from(new Set(rows.map((r) => r.sourceType).filter(Boolean) as string[])).sort(),
    [rows],
  )

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase()
    return rows.filter((r) => {
      if (status !== "all" && (r.status ?? "Posted") !== status) return false
      if (method !== "all" && (r.paymentMethod ?? "") !== method) return false
      if (source !== "all" && (r.sourceType ?? "") !== source) return false
      if (appliedTo === "single" && r.allocationCount !== 1) return false
      if (appliedTo === "multiple" && r.allocationCount <= 1) return false
      if (q) {
        const hay = [r.partyName, r.paymentMethod, r.reference, r.notes, paymentRef(r), r.createdBy]
          .filter(Boolean).join(" ").toLowerCase()
        if (!hay.includes(q)) return false
      }
      return true
    })
  }, [rows, search, status, method, source, appliedTo])

  // How many payments each sale has taken. Counted over every loaded row and
  // not the filtered ones, so a sale still says it was paid three times while a
  // filter hides two of them -- the trail is fetched unfiltered and shows all
  // three, so this count has to agree with the trail, not with the table.
  const payCountBySale = useMemo(() => {
    const m = new Map<number, number>()
    for (const r of rows) {
      if (r.allocationCount === 1 && r.saleId != null) m.set(r.saleId, (m.get(r.saleId) ?? 0) + 1)
    }
    return m
  }, [rows])

  // One row per part-paid sale. `filtered` is newest-first, so the first row a
  // sale reaches here is its newest surviving payment: that one keeps the row
  // and carries the trail, the rest fold into it. Folding runs before
  // pagination, so pages stay a full size, and it follows the filters -- if the
  // newest payment is filtered out the next one takes over the row, rather than
  // the sale disappearing from the ledger.
  const { visible, carriers, folded } = useMemo(() => {
    const carriers = new Map<number, string>()
    const visible: PaymentHistoryRow[] = []
    let folded = 0
    for (const r of filtered) {
      const saleId = r.allocationCount === 1 ? r.saleId : null
      if (saleId == null || (payCountBySale.get(saleId) ?? 0) < 2) { visible.push(r); continue }
      if (carriers.has(saleId)) { folded++; continue }
      carriers.set(saleId, r.paymentId)
      visible.push(r)
    }
    return { visible, carriers, folded }
  }, [filtered, payCountBySale])

  const pg = usePagination(visible)

  /** How many times this row's sale was paid, once that is more than once. */
  const payCount = (row: PaymentHistoryRow) => {
    if (row.allocationCount !== 1 || row.saleId == null) return null
    const n = payCountBySale.get(row.saleId) ?? 0
    return n > 1 ? n : null
  }

  /** The row carrying a part-paid sale's trail is the only one that opens it. */
  const hasTrail = (row: PaymentHistoryRow) =>
    row.saleId != null && carriers.get(row.saleId) === row.paymentId

  const totals = useMemo(() => {
    const posted = filtered.filter((r) => (r.status ?? "Posted") !== "Reversed")
    return {
      count: posted.length,
      amount: posted.reduce((s, r) => s + (Number(r.totalAmount) || 0), 0),
      sales: posted.reduce((s, r) => s + (r.allocationCount || 0), 0),
    }
  }, [filtered])

  // A payment's allocation, loaded when a row is opened. The one-sale case is
  // NOT fetched: migration 241 puts its sale and balances on the row itself, so
  // the page no longer makes a request per row to show them.
  const fetchAllocation = async (id: string) => {
    if (allocations[id]) return
    try {
      const detail = await getPayment(module, "customer", id)
      setAllocations((prev) => (prev[id] ? prev : { ...prev, [id]: detail.allocations }))
    } catch {
      // Silent: an inline detail that cannot load falls back to the count, and
      // a toast per row would bury the page.
    }
  }

  // Older APIs do not send the inline fields; those rows still need the fetch,
  // so the page works either side of migration 241.
  useEffect(() => {
    for (const r of pg.pageItems) {
      if (r.allocationCount === 1 && r.saleId == null) void fetchAllocation(r.paymentId)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pg.pageItems])

  const fetchTrail = async (saleId: number) => {
    if (saleTrails[saleId]) return
    try {
      // No date range: the trail is the sale's whole life, not this period's
      // slice of it.
      const list = await listPayments(module, "customer", { documentId: saleId })
      setSaleTrails((prev) => (prev[saleId] ? prev : { ...prev, [saleId]: list }))
    } catch {
      // Silent, like the allocation fetch: the row still says everything it
      // said before, and a toast per row would bury the page.
    }
  }

  const toggle = async (row: PaymentHistoryRow) => {
    if (expanded === row.paymentId) { setExpanded(null); return }
    setExpanded(row.paymentId)
    if (row.allocationCount > 1) await fetchAllocation(row.paymentId)
    else if (row.saleId != null) await fetchTrail(row.saleId)
  }

  const doReverse = async () => {
    if (!reverseTarget) return
    if (!reason.trim()) {
      toast({ title: "A reason is required", description: "Say why this payment is being reversed — it is written to the audit trail.", variant: "destructive" })
      return
    }
    setReversing(true)
    try {
      await reversePayment(module, "customer", reverseTarget.paymentId, reason.trim())
      toast({
        title: "Payment reversed",
        description: `${fmt(reverseTarget.totalAmount)} put back on ${reverseTarget.allocationCount} sale${reverseTarget.allocationCount === 1 ? "" : "s"}.`,
      })
      setReverseTarget(null)
      setReason("")
      await load()
    } catch (e: any) {
      toast({ title: "Could not reverse payment", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setReversing(false)
    }
  }

  const dateOf = (d: string) => (d ? new Date(d).toLocaleDateString() : "—")

  /**
   * The one-sale case as four values: the sale, its total, and the balance the
   * payment moved it from and to.
   *
   * Prefers what the row already carries (241) and falls back to a fetched
   * allocation, so the page renders the same on an API that has not learned to
   * send them.
   */
  const single = (row: PaymentHistoryRow) => {
    if (row.allocationCount !== 1) return null
    if (row.saleId != null) {
      return {
        saleId: row.saleId,
        saleTotal: row.saleTotal ?? null,
        before: row.balanceBefore ?? null,
        applied: row.amountApplied ?? row.totalAmount,
        after: row.balanceAfter ?? null,
      }
    }
    const a = allocations[row.paymentId]?.[0]
    if (!a) return null
    return { saleId: a.documentId, saleTotal: a.documentTotal, before: a.balanceBefore, applied: a.amountApplied, after: a.balanceAfter }
  }

  const saleLink = (saleId: number) => {
    const href = saleHref(saleId)
    return href
      ? <Link href={href} className="font-medium text-sky-700 hover:underline">#{saleId}</Link>
      : <span className="font-medium">#{saleId}</span>
  }

  /** Right-aligned money, or the em dash a multi-sale payment gets. */
  const money = (v: number | null | undefined) =>
    v == null ? <span className="text-slate-400">—</span> : <span className="tabular-nums">{fmt(v)}</span>

  // A panel, not a second full-width table. Auto layout spreads these columns
  // across the whole page and leaves each heading sitting nowhere near its own
  // numbers; declared widths put every heading directly over its column, and
  // the left rule says this belongs to the payment above it.
  const allocationTable = (list: PaymentAllocationRow[]) => (
    <div className="ml-1 border-l-2 border-slate-200 pl-3">
      <div className="mb-1 text-[11px] font-semibold uppercase tracking-wide text-slate-500">Applied to</div>
      <Table className="w-full table-fixed [&_td]:whitespace-normal [&_th]:whitespace-normal">
      <colgroup>
        <col className="w-[12%]" />
        <col className="w-[20%]" />
        <col className="w-[12%]" />
        <col className="w-[13%]" />
        <col className="w-[14%]" />
        <col className="w-[13%]" />
        <col className="w-[14%]" />
        <col className="w-[12%]" />
      </colgroup>
      <TableHeader>
        <TableRow>
          <TableHead>Sale</TableHead>
          <TableHead>Description</TableHead>
          <TableHead>Sale date</TableHead>
          <TableHead className="text-right">Sale total</TableHead>
          <TableHead className="text-right">Balance before</TableHead>
          <TableHead className="text-right">Applied</TableHead>
          <TableHead className="text-right">Balance after</TableHead>
          <TableHead>Status</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {list.map((a) => {
          const href = saleHref(a.documentId)
          return (
            <TableRow key={a.allocationId}>
              <TableCell className="font-medium">
                {href ? <Link href={href} className="text-sky-700 hover:underline">#{a.documentId}</Link> : `#${a.documentId}`}
              </TableCell>
              <TableCell className="text-slate-600">{a.label ?? a.reference ?? "—"}</TableCell>
              <TableCell className="whitespace-nowrap!">{dateOf(a.documentDate ?? "")}</TableCell>
              <TableCell className="whitespace-nowrap! text-right">{fmt(a.documentTotal)}</TableCell>
              <TableCell className="whitespace-nowrap! text-right text-slate-500">{fmt(a.balanceBefore)}</TableCell>
              <TableCell className="whitespace-nowrap! text-right font-medium">{fmt(a.amountApplied)}</TableCell>
              <TableCell className="whitespace-nowrap! text-right">{fmt(a.balanceAfter)}</TableCell>
              <TableCell>
                {a.balanceAfter <= 0
                  ? <Badge variant="secondary">Paid</Badge>
                  : <Badge variant="outline" className="text-amber-700">Part paid</Badge>}
              </TableCell>
            </TableRow>
          )
        })}
      </TableBody>
      </Table>
    </div>
  )

  // The sale's payment trail: what it was worth, and what each payment left
  // owing. The row being expanded is marked, so you can see where you are in it.
  const trailTable = (saleId: number, currentPaymentId: string) => {
    const list = saleTrails[saleId]
    if (!list) return (
      <span className="flex items-center gap-2 text-sm text-slate-500">
        <Loader2 className="h-3.5 w-3.5 animate-spin" /> Loading the sale's payments…
      </span>
    )
    const ordered = [...list].sort((a, b) => (a.paymentDate ?? "").localeCompare(b.paymentDate ?? ""))
    return (
      <div className="rounded-lg border border-indigo-300 bg-white p-2 shadow-sm">
        <div className="mb-1.5 px-1 text-[11px] font-semibold uppercase tracking-wide text-indigo-800">
          Sale #{saleId} · paid {ordered.length} times
        </div>
        <Table className="w-full table-fixed [&_td]:whitespace-normal [&_th]:whitespace-normal">
          <colgroup>
            <col className="w-[13%]" /><col className="w-[14%]" /><col className="w-[12%]" />
            <col className="w-[16%]" /><col className="w-[15%]" /><col className="w-[16%]" />
            <col className="w-[14%]" />
          </colgroup>
          <TableHeader>
            <TableRow className="border-b border-indigo-300 bg-indigo-200/70 hover:bg-indigo-200/70 [&_th]:font-semibold [&_th]:text-indigo-900">
              <TableHead>Date</TableHead>
              <TableHead>Payment</TableHead>
              <TableHead>Method</TableHead>
              <TableHead className="text-right">Balance before</TableHead>
              <TableHead className="text-right">Applied</TableHead>
              <TableHead className="text-right">Balance after</TableHead>
              <TableHead className="text-right">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {ordered.map((pmt) => {
              const isThis = pmt.paymentId === currentPaymentId
              const rev = (pmt.status ?? "Posted") === "Reversed"
              return (
                <TableRow key={pmt.paymentId} className={cn(isThis && "bg-indigo-50 font-medium", rev && "text-slate-400")}>
                  <TableCell className="whitespace-nowrap!">{dateOf(pmt.paymentDate)}</TableCell>
                  <TableCell className="whitespace-nowrap!">{paymentRef(pmt)}</TableCell>
                  <TableCell>{pmt.paymentMethod ?? "—"}</TableCell>
                  <TableCell className="whitespace-nowrap! text-right text-slate-500">{money(pmt.balanceBefore)}</TableCell>
                  {/* A bulk payment reaches this trail because it covered this
                      sale among others. Its totalAmount is the WHOLE payment,
                      so showing it here would credit this one sale with all of
                      it -- say what it is instead, and let its own row expand
                      for the split. */}
                  <TableCell className="whitespace-nowrap! text-right font-semibold text-emerald-700">
                    {pmt.allocationCount > 1
                      ? <span className="font-normal text-slate-500">across {pmt.allocationCount} sales</span>
                      : money(pmt.amountApplied ?? pmt.totalAmount)}
                  </TableCell>
                  <TableCell
                    className={cn(
                      "whitespace-nowrap! text-right font-medium",
                      pmt.balanceAfter == null ? "" : pmt.balanceAfter <= 0 ? "text-emerald-700" : "text-amber-700",
                    )}
                  >
                    {money(pmt.balanceAfter)}
                  </TableCell>
                  {/* The folded instalments have no row of their own any more,
                      so this is the only place left to reverse one. */}
                  <TableCell className="text-right">
                    {rev
                      ? <span className="text-xs text-slate-400">Reversed</span>
                      : canReverse && (
                          <Button variant="ghost" size="sm" className="h-7 px-2"
                                  onClick={() => { setReverseTarget(pmt); setReason("") }}>
                            <Undo2 className="mr-1 h-3.5 w-3.5" /> Reverse
                          </Button>
                        )}
                  </TableCell>
                </TableRow>
              )
            })}
          </TableBody>
        </Table>
      </div>
    )
  }

  const statusBadge = (row: PaymentHistoryRow) =>
    (row.status ?? "Posted") === "Reversed"
      ? <Badge variant="outline" className="text-slate-500">Reversed</Badge>
      : <Badge variant="secondary">Posted</Badge>

  if (!permsLoading && !canView) {
    return (
      <div className="flex h-screen bg-slate-50">
        <DashboardSidebar onLogout={logout} />
        <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
          <DashboardHeader />
          <main className="flex-1 overflow-auto p-6">
            <div className="rounded-lg border bg-white p-8 text-center text-slate-500">
              You do not have permission to view customer payments.
            </div>
          </main>
        </div>
      </div>
    )
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <h1 className="mb-1 flex items-center gap-2 text-2xl font-semibold text-slate-900">
            <Wallet className="h-6 w-6 text-sky-600" /> Payments received
          </h1>
          <p className="mb-4 text-sm text-slate-500">
            One row per payment the customer actually made. A payment spread over several sales is one payment
            here — open it to see how much each sale received. A sale that was part-paid keeps one row too,
            with its earlier payments inside it.
          </p>

          <ListFilters
            search={search} setSearch={setSearch}
            dateFrom={from} setDateFrom={setFrom}
            dateTo={to} setDateTo={setTo}
            searchPlaceholder="Search customer, payment, method or reference"
            extras={
              <>
                <div className="w-full sm:w-[150px]">
                  <Label className="text-xs text-slate-500">Method</Label>
                  <Select value={method} onValueChange={setMethod}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">All methods</SelectItem>
                      {methods.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
                <div className="w-full sm:w-[150px]">
                  <Label className="text-xs text-slate-500">Source</Label>
                  <Select value={source} onValueChange={setSource}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">All sources</SelectItem>
                      {sources.map((s) => <SelectItem key={s} value={s}>{sourceLabel(s)}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
                <div className="w-full sm:w-[150px]">
                  <Label className="text-xs text-slate-500">Applied to</Label>
                  <Select value={appliedTo} onValueChange={setAppliedTo}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">Any</SelectItem>
                      <SelectItem value="single">One sale</SelectItem>
                      <SelectItem value="multiple">Several sales</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="w-full sm:w-[150px]">
                  <Label className="text-xs text-slate-500">Status</Label>
                  <Select value={status} onValueChange={setStatus}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="Posted">Posted</SelectItem>
                      <SelectItem value="Reversed">Reversed</SelectItem>
                      <SelectItem value="all">All</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
              </>
            }
          />

          {/* The totals count PAYMENTS, not allocations -- the number of sales
              settled is its own figure, because the two differ the moment
              anyone pays for more than one sale at a time. */}
          <div className="mb-4 grid grid-cols-2 gap-3 sm:grid-cols-3">
            <div className="rounded-lg border bg-white p-3">
              <div className="text-xs text-slate-500">Payments</div>
              <div className="text-xl font-bold tabular-nums">{totals.count.toLocaleString()}</div>
              {/* This counts payments, and part-paid sales are shown as one
                  row, so the two disagree. Say by how much rather than let a
                  payment look like it went missing from the table. */}
              {folded > 0 && (
                <div className="mt-0.5 text-[11px] text-slate-500">
                  {folded} inside a sale&apos;s trail
                </div>
              )}
            </div>
            <div className="rounded-lg border bg-white p-3">
              <div className="text-xs text-slate-500">Total received</div>
              <div className="text-xl font-bold tabular-nums text-emerald-700">{fmt(totals.amount)}</div>
            </div>
            <div className="rounded-lg border bg-white p-3">
              <div className="text-xs text-slate-500">Sales settled</div>
              <div className="text-xl font-bold tabular-nums">{totals.sales.toLocaleString()}</div>
            </div>
          </div>

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="flex items-center gap-2 p-6 text-slate-500">
                  <Loader2 className="h-4 w-4 animate-spin" /> Loading…
                </div>
              ) : filtered.length === 0 ? (
                <div className="p-8 text-center text-slate-500">
                  {rows.length === 0 ? "No payments yet." : "No payments match those filters."}
                </div>
              ) : (
                <>
                  {/* ---- Phones: one card per payment ------------------------ */}
                  <div className="divide-y divide-slate-100 lg:hidden">
                    {pg.pageItems.map((row) => {
                      const isReversed = (row.status ?? "Posted") === "Reversed"
                      const isOpen = expanded === row.paymentId
                      const multi = row.allocationCount > 1
                      const openable = multi || hasTrail(row)
                      const times = payCount(row)
                      const one = single(row)
                      return (
                        <div key={row.paymentId} className={cn("p-3", isReversed && "text-slate-400")}>
                          {/* Same rule as the table: there is something to open
                              when the payment covers several sales, or when its
                              sale has been paid more than once. A one-sale,
                              one-payment card already shows everything below. */}
                          <button
                            type="button"
                            onClick={() => { if (openable) void toggle(row) }}
                            aria-expanded={openable ? isOpen : undefined}
                            className={cn(
                              "flex w-full items-start justify-between gap-3 text-left",
                              !openable && "cursor-default",
                            )}
                          >
                            <div className="min-w-0 flex-1">
                              <div className="flex flex-wrap items-center gap-2">
                                <span className={cn("font-semibold tabular-nums text-slate-900", isReversed && "text-slate-400 line-through")}>
                                  {fmt(row.totalAmount)}
                                </span>
                                {statusBadge(row)}
                              </div>
                              <div className="mt-0.5 truncate text-sm text-slate-600">{row.partyName ?? "Walk-in"}</div>
                              <div className="mt-1 text-xs text-slate-500">
                                {dateOf(row.paymentDate)} · {row.paymentMethod ?? "—"} ·{" "}
                                {multi ? `${row.allocationCount} sales` : "1 sale"}
                              </div>
                            </div>
                            {openable && (isOpen
                              ? <ChevronDown className="mt-0.5 h-4 w-4 shrink-0 text-slate-400" />
                              : <ChevronRight className="mt-0.5 h-4 w-4 shrink-0 text-slate-400" />)}
                          </button>

                          <div className="mt-2 grid grid-cols-2 gap-x-3 gap-y-1 text-xs text-slate-500">
                            <span className="min-w-0 truncate">{paymentRef(row)}</span>
                            <span className="min-w-0 truncate text-right">Source: {sourceLabel(row.sourceType)}</span>
                            <span className="min-w-0 truncate">Ref: {row.reference ?? "—"}</span>
                            <span className="min-w-0 truncate text-right">By: {row.createdBy ?? "—"}</span>
                          </div>

                          {!multi && one && (
                            <div className="mt-2 grid grid-cols-2 gap-x-3 gap-y-1 rounded-md bg-slate-50 p-2 text-xs">
                              <span className="text-slate-500">
                                Sale {saleLink(one.saleId)}
                                {times && <span className="ml-1 text-slate-400">(paid {times} times)</span>}
                              </span>
                              <span className="text-right text-slate-500">Total {fmt(one.saleTotal ?? 0)}</span>
                              <span className="tabular-nums text-slate-500">Before {fmt(one.before ?? 0)}</span>
                              <span className="text-right tabular-nums text-slate-500">After {fmt(one.after ?? 0)}</span>
                            </div>
                          )}

                          {isReversed && row.reversalReason && (
                            <p className="mt-2 text-xs text-slate-500">
                              Reversed{row.reversedBy ? ` by ${row.reversedBy}` : ""}
                              {row.reversedAt ? ` on ${dateOf(row.reversedAt)}` : ""}: {row.reversalReason}
                            </p>
                          )}

                          {canReverse && !isReversed && (
                            <Button variant="outline" size="sm" className="mt-2 h-10 w-full bg-white"
                                    onClick={() => { setReverseTarget(row); setReason("") }}>
                              <Undo2 className="mr-1.5 h-3.5 w-3.5" /> Reverse
                            </Button>
                          )}

                          {/* A sale paid more than once opens its trail instead
                              of an allocation -- one payment per line, oldest
                              first, with the one you opened marked. */}
                          {isOpen && !multi && row.saleId != null && (
                            <div className="mt-2 space-y-2 rounded-md bg-indigo-50 p-2">
                              {!saleTrails[row.saleId] ? (
                                <span className="flex items-center gap-2 text-sm text-slate-500">
                                  <Loader2 className="h-3.5 w-3.5 animate-spin" /> Loading the sale&apos;s payments…
                                </span>
                              ) : (
                                <>
                                  <div className="px-1 text-[11px] font-semibold uppercase tracking-wide text-indigo-800">
                                    Sale #{row.saleId} · paid {saleTrails[row.saleId].length} times
                                  </div>
                                  {[...saleTrails[row.saleId]]
                                    .sort((a, b) => (a.paymentDate ?? "").localeCompare(b.paymentDate ?? ""))
                                    .map((pmt) => (
                                      <div
                                        key={pmt.paymentId}
                                        className={cn(
                                          "rounded-md border bg-white p-2.5 text-xs",
                                          pmt.paymentId === row.paymentId
                                            ? "border-indigo-400"
                                            : "border-slate-200",
                                        )}
                                      >
                                        <div className="flex items-start justify-between gap-2">
                                          <span className="min-w-0 truncate font-medium text-slate-900">
                                            {paymentRef(pmt)}
                                            <span className="ml-1.5 font-normal text-slate-500">{dateOf(pmt.paymentDate)}</span>
                                          </span>
                                          <span className="shrink-0 font-semibold tabular-nums text-emerald-700">
                                            {pmt.allocationCount > 1
                                              ? <span className="font-normal text-slate-500">across {pmt.allocationCount} sales</span>
                                              : fmt(pmt.amountApplied ?? pmt.totalAmount)}
                                          </span>
                                        </div>
                                        <div className="mt-1.5 grid grid-cols-2 gap-x-3 gap-y-1 text-slate-500">
                                          <span className="tabular-nums">Before {money(pmt.balanceBefore)}</span>
                                          <span
                                            className={cn(
                                              "text-right tabular-nums",
                                              pmt.balanceAfter == null ? "" : pmt.balanceAfter <= 0 ? "text-emerald-700" : "text-amber-700",
                                            )}
                                          >
                                            After {money(pmt.balanceAfter)}
                                          </span>
                                        </div>
                                        {/* As in the table: a folded payment has
                                            no row of its own, so its Reverse
                                            lives here. */}
                                        {(pmt.status ?? "Posted") === "Reversed"
                                          ? <div className="mt-1.5 text-[11px] text-slate-400">Reversed</div>
                                          : canReverse && (
                                              <Button variant="outline" size="sm" className="mt-2 h-8 w-full bg-white"
                                                      onClick={() => { setReverseTarget(pmt); setReason("") }}>
                                                <Undo2 className="mr-1.5 h-3.5 w-3.5" /> Reverse
                                              </Button>
                                            )}
                                      </div>
                                    ))}
                                </>
                              )}
                            </div>
                          )}

                          {isOpen && multi && (
                            <div className="mt-2 space-y-2 rounded-md bg-slate-50 p-2">
                              {!allocations[row.paymentId] ? (
                                <span className="flex items-center gap-2 text-sm text-slate-500">
                                  <Loader2 className="h-3.5 w-3.5 animate-spin" /> Loading allocation…
                                </span>
                              ) : allocations[row.paymentId].map((a) => (
                                <div key={a.allocationId} className="rounded-md border border-slate-200 bg-white p-2.5 text-xs">
                                  <div className="flex items-start justify-between gap-2">
                                    <span className="min-w-0 truncate font-medium text-slate-900">#{a.documentId}</span>
                                    <span className="shrink-0 font-semibold tabular-nums">{fmt(a.amountApplied)}</span>
                                  </div>
                                  {a.label ? <div className="truncate text-slate-500">{a.label}</div> : null}
                                  <div className="mt-1.5 grid grid-cols-2 gap-x-3 gap-y-1 text-slate-500">
                                    <span>{dateOf(a.documentDate ?? "")}</span>
                                    <span className="text-right tabular-nums">Total {fmt(a.documentTotal)}</span>
                                    <span className="tabular-nums">Before {fmt(a.balanceBefore)}</span>
                                    <span className="text-right tabular-nums">After {fmt(a.balanceAfter)}</span>
                                  </div>
                                </div>
                              ))}
                            </div>
                          )}
                        </div>
                      )
                    })}
                    <div className="px-3 py-3">
                      <DataPagination {...pg.paginationProps} />
                    </div>
                  </div>

                  {/* ---- lg and up: the ledger ------------------------------- */}
                  {/* Cells wrap rather than scroll: <Table> is whitespace-nowrap
                      by default and wraps itself in an overflow-x-auto div, so
                      without this the ledger can only ever be scrolled
                      sideways. Money and dates keep nowrap explicitly. */}
                  <div className="hidden lg:block">
                    <Table className="w-full [&_td]:whitespace-normal [&_th]:whitespace-normal">
                      <TableHeader>
                        <TableRow>
                          <TableHead className="w-8" />
                          <TableHead>Date</TableHead>
                          <TableHead>Payment</TableHead>
                          <TableHead>Customer</TableHead>
                          <TableHead className="text-right">Amount</TableHead>
                          {/* The allocation, for the payment that settled one
                              sale. A payment across several shows the count
                              here and em dashes across the money columns --
                              there is no single balance to report -- and opens
                              for the full breakdown. */}
                          <TableHead>Sale</TableHead>
                          <TableHead className="text-right">Sale total</TableHead>
                          <TableHead className="text-right">Before</TableHead>
                          <TableHead className="text-right">Applied</TableHead>
                          <TableHead className="text-right">After</TableHead>
                          <TableHead>Method</TableHead>
                          <TableHead>Source</TableHead>
                          <TableHead>Status</TableHead>
                          <TableHead className="text-right">Actions</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {pg.pageItems.map((row) => {
                          const isReversed = (row.status ?? "Posted") === "Reversed"
                          const isOpen = expanded === row.paymentId
                          const multi = row.allocationCount > 1
                          const one = single(row)
                          const times = payCount(row)
                          return (
                            <Fragment key={row.paymentId}>
                              <TableRow className={isReversed ? "text-slate-400" : undefined}>
                                <TableCell>
                                  {/* Only a payment across several sales has
                                      anything to open. A one-sale payment
                                      already shows its sale, total, before,
                                      applied and after ON this row, so an
                                      expander there just repeats the row back
                                      at you. */}
                                  {(multi || hasTrail(row)) && (
                                    <button type="button" onClick={() => toggle(row)} aria-label="Show allocation">
                                      {isOpen ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
                                    </button>
                                  )}
                                </TableCell>
                                <TableCell className="whitespace-nowrap!">{dateOf(row.paymentDate)}</TableCell>
                                <TableCell className="whitespace-nowrap! font-medium text-slate-700" title={row.paymentId}>
                                  {paymentRef(row)}
                                </TableCell>
                                <TableCell className="font-medium">{row.partyName ?? "Walk-in"}</TableCell>
                                <TableCell className={cn("whitespace-nowrap! text-right font-semibold tabular-nums", isReversed && "line-through")}>
                                  {fmt(row.totalAmount)}
                                </TableCell>
                                <TableCell className="whitespace-nowrap!">
                                  {multi
                                    ? <span className="font-medium text-slate-700">{row.allocationCount} sales</span>
                                    : one ? (
                                        <>
                                          {saleLink(one.saleId)}
                                          {/* The earlier instalments no longer
                                              have rows of their own, so this
                                              says the sale was part-paid and the
                                              chevron opens the whole trail. */}
                                          {times && (
                                            <span className="ml-1.5 text-xs text-slate-500">
                                              paid {times} times
                                            </span>
                                          )}
                                        </>
                                      )
                                    : <span className="text-slate-400">—</span>}
                                </TableCell>
                                <TableCell className="whitespace-nowrap! text-right">{money(one?.saleTotal)}</TableCell>
                                <TableCell className="whitespace-nowrap! text-right text-slate-500">{money(one?.before)}</TableCell>
                                <TableCell className="whitespace-nowrap! text-right font-semibold text-emerald-700">{money(one?.applied)}</TableCell>
                                {/* The expander used to carry a Paid / Part paid badge for the
                                    sale. It is the same fact as this number, so it
                                    is said here instead: green when the sale ended
                                    settled, amber when something is still owed. */}
                                <TableCell
                                  className={cn(
                                    "whitespace-nowrap! text-right font-medium",
                                    one == null || one.after == null ? ""
                                      : one.after <= 0 ? "text-emerald-700" : "text-amber-700",
                                  )}
                                >
                                  {money(one?.after)}
                                </TableCell>
                                <TableCell>{row.paymentMethod ?? "—"}</TableCell>
                                <TableCell className="text-xs text-slate-500" title={row.sourceType ?? undefined}>
                                  {sourceLabel(row.sourceType)}
                                </TableCell>
                                <TableCell>{statusBadge(row)}</TableCell>
                                <TableCell className="text-right">
                                  {canReverse && !isReversed && (
                                    <Button variant="ghost" size="sm" onClick={() => { setReverseTarget(row); setReason("") }}>
                                      <Undo2 className="mr-1.5 h-3.5 w-3.5" /> Reverse
                                    </Button>
                                  )}
                                </TableCell>
                              </TableRow>

                              {isReversed && row.reversalReason && (
                                <TableRow>
                                  <TableCell />
                                  <TableCell colSpan={13} className="py-1 text-xs text-slate-500">
                                    Reversed{row.reversedBy ? ` by ${row.reversedBy}` : ""}
                                    {row.reversedAt ? ` on ${dateOf(row.reversedAt)}` : ""}: {row.reversalReason}
                                  </TableCell>
                                </TableRow>
                              )}

                              {isOpen && (
                                <TableRow>
                                  <TableCell />
                                  <TableCell colSpan={13} className="py-2">
                                    {multi
                                      ? (!allocations[row.paymentId] ? (
                                          <span className="flex items-center gap-2 text-sm text-slate-500">
                                            <Loader2 className="h-3.5 w-3.5 animate-spin" /> Loading allocation…
                                          </span>
                                        ) : allocationTable(allocations[row.paymentId]))
                                      : row.saleId != null && trailTable(row.saleId, row.paymentId)}
                                  </TableCell>
                                </TableRow>
                              )}
                            </Fragment>
                          )
                        })}
                      </TableBody>
                    </Table>
                    <div className="px-4 pb-4 pt-2">
                      <DataPagination {...pg.paginationProps} />
                    </div>
                  </div>
                </>
              )}
            </CardContent>
          </Card>
        </main>
      </div>

      {/* Reversal names every sale it will touch, because a bulk payment puts
          money back onto several balances at once and that is not obvious from
          the row. */}
      <Dialog open={!!reverseTarget} onOpenChange={(o) => { if (!o) { setReverseTarget(null); setReason("") } }}>
        <DialogContent className="w-[95vw] max-w-lg p-4 sm:p-6">
          <DialogHeader>
            <DialogTitle>Reverse payment</DialogTitle>
            <DialogDescription>
              This reverses the whole payment and restores the balance on every sale it was applied to.
            </DialogDescription>
          </DialogHeader>

          {reverseTarget && (
            <div className="space-y-3 text-sm">
              <div className="rounded-md border bg-slate-50 p-3">
                <div className="flex items-center justify-between gap-2">
                  <span className="text-slate-500">{reverseTarget.partyName ?? "Walk-in"}</span>
                  <span className="font-semibold tabular-nums">{fmt(reverseTarget.totalAmount)}</span>
                </div>
                <div className="mt-2 space-y-1 text-xs text-slate-600">
                  {!allocations[reverseTarget.paymentId] ? (
                    <span className="flex items-center gap-2 text-slate-500">
                      <Loader2 className="h-3.5 w-3.5 animate-spin" /> Loading the sales it covers…
                    </span>
                  ) : (
                    allocations[reverseTarget.paymentId].map((a) => (
                      <div key={a.allocationId} className="flex items-center justify-between gap-2">
                        <span>Sale #{a.documentId}</span>
                        <span className="tabular-nums">{fmt(a.amountApplied)}</span>
                      </div>
                    ))
                  )}
                </div>
              </div>

              <div className="space-y-1.5">
                <Label htmlFor="reverse-reason">Why is this being reversed?</Label>
                <Input
                  id="reverse-reason"
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  placeholder="e.g. entered twice"
                />
              </div>
              <p className="text-xs text-slate-500">
                The payment is kept and marked reversed, never deleted.
              </p>
            </div>
          )}

          <DialogFooter className="flex-col gap-2 sm:flex-row">
            <Button variant="ghost" className="h-10 w-full sm:h-9 sm:w-auto"
                    onClick={() => { setReverseTarget(null); setReason("") }}>
              Cancel
            </Button>
            <Button variant="destructive" className="h-10 w-full sm:h-9 sm:w-auto" disabled={reversing} onClick={doReverse}>
              {reversing ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : null}
              Reverse payment
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
