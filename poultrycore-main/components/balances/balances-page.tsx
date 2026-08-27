"use client"

// The Customer Balances / Supplier Balances control page.
//
// One component, six routes: the customer and supplier sides differ only in
// wording and in which endpoints they call, and the three company types differ
// only in route prefix. Everything that varies is a prop.
//
// This is a WORKING page, not a report. Every row can be acted on: open the
// party, open the underlying sale or purchase, take a payment against one line,
// or take one payment and spread it across several. The read-only, printable
// version of the same numbers lives under Reports.

import { Fragment, useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import {
  Select, SelectContent, SelectGroup, SelectItem,
  SelectSeparator, SelectTrigger, SelectValue,
} from "@/components/ui/select"
import { PERIOD_GROUPS, periodToRange, rangeToPeriod } from "@/lib/date-ranges"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import {
  AlertTriangle, ChevronDown, ChevronRight, ExternalLink, FileText,
  History, Loader2, Users, Wallet,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { useFmt } from "@/lib/currency"
import {
  BALANCE_STATUS_FILTERS, getBalanceSummary, listBalances, listOpenDocuments, listPayments,
  type BalanceFilters, type BalanceModule, type BalanceSide, type BalanceStatusFilter,
  type BalanceSummary, type OpenDocumentRow, type PartyBalanceRow,
} from "@/lib/api/balances"
import { RecordPaymentDialog, type CashAccountOption } from "./record-payment-dialog"
import { StatementDialog } from "./statement-dialog"
import { PaymentHistoryDialog } from "./payment-history-dialog"

export interface BalancesPageProps {
  module: BalanceModule
  side: BalanceSide
  /** Company type this page belongs to; other types are redirected away. */
  companyType: "Poultry" | "Water" | "Generic"
  /** Loads the cash accounts offered in the payment dialog. */
  loadCashAccounts: () => Promise<CashAccountOption[]>
  /** Route to a party's profile, e.g. (id) => `/customers/${id}`. */
  partyHref: (partyId: number) => string
  /** Route to an underlying document, or null when it has no page of its own. */
  documentHref: (doc: OpenDocumentRow) => string | null
  /** IAM keys gating this page. */
  permissions: { view: string; pay: string; reverse: string; statement: string }
}

export function BalancesPage({
  module, side, companyType, loadCashAccounts, partyHref, documentHref, permissions,
}: BalancesPageProps) {
  const fmt = useFmt()
  const router = useRouter()
  const { toast } = useToast()
  const logout = useLogout()
  const { can, isLoading: permsLoading } = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const isCustomer = side === "customer"
  const partyWord = isCustomer ? "customer" : "supplier"
  const docWord = isCustomer ? "sale" : "purchase"

  const [rows, setRows] = useState<PartyBalanceRow[]>([])
  const [summary, setSummary] = useState<BalanceSummary | null>(null)
  const [loading, setLoading] = useState(true)
  const [cashAccounts, setCashAccounts] = useState<CashAccountOption[]>([])

  // Expanded party -> its open documents. Fetched on demand: a farm with 200
  // customers should not pull 200 sale lists to render a summary table.
  const [expanded, setExpanded] = useState<number | null>(null)
  const [docs, setDocs] = useState<Record<number, OpenDocumentRow[]>>({})
  const [docsLoading, setDocsLoading] = useState<number | null>(null)

  const [search, setSearch] = useState("")
  const [status, setStatus] = useState<BalanceStatusFilter>("All")
  const [from, setFrom] = useState("")
  const [to, setTo] = useState("")
  const [minBalance, setMinBalance] = useState("")
  // Pick one party instead of typing a name. Server-side: the list endpoint has
  // always taken a partyId, the page just never offered it.
  const [partyFilter, setPartyFilter] = useState("all")
  // Payment method. NOT a property of an outstanding balance -- a balance is
  // what is still unpaid -- so this filters parties by the method their POSTED
  // payments actually used, resolved from the payment list below.
  const [methodFilter, setMethodFilter] = useState("all")

  // Every party that has a balance, for the dropdown. Seeded from the first
  // (unfiltered) load and then left alone: options that vanish as you filter
  // would make the filter impossible to change your mind about.
  const [partyOptions, setPartyOptions] = useState<{ id: number; name: string }[]>([])
  // partyId -> the distinct methods that party has paid with, and every method
  // seen on this farm. Built from one payments read, not one per party.
  const [methodsByParty, setMethodsByParty] = useState<Record<number, string[]>>({})
  const [methodOptions, setMethodOptions] = useState<string[]>([])
  // Bumped after a payment is posted or reversed so the method map refetches.
  const [paymentsVersion, setPaymentsVersion] = useState(0)

  const [payFor, setPayFor] = useState<{ party: PartyBalanceRow; doc: OpenDocumentRow | null } | null>(null)
  const [statementFor, setStatementFor] = useState<PartyBalanceRow | null>(null)
  const [historyFor, setHistoryFor] = useState<{ party: PartyBalanceRow | null; doc: OpenDocumentRow | null } | null>(null)

  const canView = can(permissions.view)
  const canPay = can(permissions.pay)
  const canReverse = can(permissions.reverse)
  const canStatement = can(permissions.statement)

  const filters: BalanceFilters = useMemo(() => ({
    from: from || null,
    to: to || null,
    partyId: partyFilter === "all" ? null : Number(partyFilter),
    status,
    minBalance: minBalance ? Number(minBalance) : null,
    search: search.trim() || null,
  }), [from, to, partyFilter, status, minBalance, search])

  // Same Period dropdown the reports use (lib/date-ranges). It is a shortcut for
  // From/To, not a filter of its own: picking a preset fills both dates, and
  // editing either date by hand drops it back to Custom. Empty dates mean no
  // date filter at all, which is this page's default — so it reads as Custom
  // until a period is picked.
  const period = from && to ? rangeToPeriod(from, to) : "custom"

  /** True while nothing has been narrowed — the only time `rows` is every party. */
  const filtersAreEmpty =
    !from && !to && partyFilter === "all" && status === "All" && !minBalance && !search.trim()

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [list, sum] = await Promise.all([
        listBalances(module, side, filters),
        getBalanceSummary(module, side),
      ])
      setRows(list)
      setSummary(sum)
      // An unfiltered list IS the full set of parties, so take the dropdown's
      // options from it rather than spending a second request on them.
      if (filtersAreEmpty) {
        setPartyOptions(list.map((r) => ({ id: r.partyId, name: r.partyName })))
      }
      // Any cached document list is stale once a payment has moved balances.
      setDocs({})
    } catch (e: any) {
      toast({ title: `Could not load ${partyWord} balances`, description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setLoading(false)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [module, side, filters])

  useEffect(() => {
    if (activeFarmType && activeFarmType !== companyType) { router.replace("/dashboard"); return }
    void load()
  }, [activeFarmType, companyType, router, load])

  // One read of the farm's payments, turned into party -> methods. Deliberately
  // NOT part of load(): load() re-runs on every filter change (every keystroke
  // in Search), and the method map does not depend on the filters. It refreshes
  // only when a payment is posted or reversed.
  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const payments = await listPayments(module, side, {})
        if (cancelled) return
        const byParty: Record<number, string[]> = {}
        const seen = new Set<string>()
        for (const p of payments) {
          // A reversed payment was undone; treating it as evidence of a method
          // would keep a party in the filter for money they never kept.
          if ((p.status ?? "Posted") !== "Posted") continue
          const method = (p.paymentMethod ?? "").trim()
          if (!method) continue
          seen.add(method)
          if (p.partyId == null) continue
          const list = byParty[p.partyId] ?? (byParty[p.partyId] = [])
          if (!list.includes(method)) list.push(method)
        }
        setMethodsByParty(byParty)
        setMethodOptions(Array.from(seen).sort())
      } catch {
        // The balances themselves do not depend on this. Leave the dropdown
        // empty rather than failing the page over a filter.
        if (!cancelled) { setMethodsByParty({}); setMethodOptions([]) }
      }
    })()
    return () => { cancelled = true }
  }, [module, side, paymentsVersion])

  // Applied here rather than server-side: the balances endpoint has no notion of
  // a payment method, and the map above already has the answer.
  const visibleRows = useMemo(
    () => (methodFilter === "all"
      ? rows
      : rows.filter((r) => (methodsByParty[r.partyId] ?? []).includes(methodFilter))),
    [rows, methodFilter, methodsByParty],
  )

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const accounts = await loadCashAccounts()
        if (!cancelled) setCashAccounts(accounts)
      } catch {
        // A farm with no cash accounts set up can still record payments; the
        // dialog just cannot offer an account. Not worth a toast on page load.
        if (!cancelled) setCashAccounts([])
      }
    })()
    return () => { cancelled = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [module])

  const toggleParty = async (party: PartyBalanceRow) => {
    if (expanded === party.partyId) { setExpanded(null); return }
    setExpanded(party.partyId)
    if (docs[party.partyId]) return
    setDocsLoading(party.partyId)
    try {
      const list = await listOpenDocuments(module, side, party.partyId, { from: from || null, to: to || null, status })
      setDocs((prev) => ({ ...prev, [party.partyId]: list }))
    } catch (e: any) {
      toast({ title: `Could not load open ${docWord}s`, description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setDocsLoading(null)
    }
  }

  const openDocument = (doc: OpenDocumentRow) => {
    const href = documentHref(doc)
    if (href) router.push(href)
    else toast({ title: "No page for this record", description: `${doc.documentType} #${doc.documentId} has no detail page.` })
  }

  if (!permsLoading && !canView) {
    return (
      <div className="flex h-screen bg-slate-50">
        <DashboardSidebar onLogout={logout} />
        <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
          <DashboardHeader />
          <main className="flex-1 overflow-auto p-6">
            <Card><CardContent className="p-8 text-center text-slate-500">
              You do not have access to {partyWord} balances.
            </CardContent></Card>
          </main>
        </div>
      </div>
    )
  }

  const cards: { label: string; value: string; tone?: "danger" }[] = summary ? [
    { label: isCustomer ? "Total customer balance" : "Total supplier balance", value: fmt(summary.totalBalance) },
    { label: isCustomer ? "Customers owing" : "Suppliers owed", value: String(summary.partyCount) },
    { label: isCustomer ? "Overdue balance" : "Overdue payables", value: fmt(summary.overdueBalance), tone: summary.overdueBalance > 0 ? "danger" : undefined },
    { label: isCustomer ? "Received today" : "Paid today", value: fmt(summary.paymentsToday) },
    { label: isCustomer ? "Largest balance" : "Largest payable", value: fmt(summary.largestBalance) },
  ] : []

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <h1 className="mb-1 flex items-center gap-2 text-2xl font-semibold text-slate-900">
            {isCustomer ? <Users className="h-6 w-6 text-sky-600" /> : <Wallet className="h-6 w-6 text-amber-600" />}
            {isCustomer ? "Customer Balances" : "Supplier Balances"}
          </h1>
          <p className="mb-4 text-sm text-slate-500">
            {isCustomer
              ? "Who owes money, which sales it is owed on, and how to collect it. Payments recorded here apply straight back to those sales."
              : "Who we owe, which purchases it is owed on, and how to settle it. Payments recorded here apply straight back to those purchases."}
          </p>

          <div className="mb-4 grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-5">
            {cards.map((c) => (
              <Card key={c.label}>
                <CardContent className="p-4">
                  <div className="text-xs text-slate-500">{c.label}</div>
                  <div className={`mt-1 text-lg font-semibold ${c.tone === "danger" ? "text-red-600" : "text-slate-900"}`}>
                    {c.value}
                  </div>
                </CardContent>
              </Card>
            ))}
            {summary?.largestBalanceParty && (
              <div className="col-span-2 self-center text-xs text-slate-500 md:col-span-3 xl:col-span-5">
                Largest balance: <span className="font-medium text-slate-700">{summary.largestBalanceParty}</span>
              </div>
            )}
          </div>

          {/* Two rows of four, not one wrapping row of eight. The controls grew
              one at a time into a flex-wrap bar with four different fixed widths,
              which re-flowed into a different ragged shape at every viewport.
              A fixed grid keeps the columns aligned, and the two rows carry
              meaning: row 1 is WHO and WHAT STATE, row 2 is WHEN and HOW MUCH. */}
          <Card className="mb-4">
            <CardContent className="space-y-4 p-4">
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
                <div className="space-y-1.5">
                  <Label htmlFor="bal-search">Search</Label>
                  <Input
                    id="bal-search" value={search} onChange={(e) => setSearch(e.target.value)}
                    placeholder={`${isCustomer ? "Customer" : "Supplier"} name or phone`}
                  />
                </div>
                <div className="space-y-1.5">
                  <Label>{isCustomer ? "Customer" : "Supplier"}</Label>
                  <Select value={partyFilter} onValueChange={setPartyFilter}>
                    <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">All {partyWord}s</SelectItem>
                      {partyOptions.map((p) => (
                        <SelectItem key={p.id} value={String(p.id)}>{p.name}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-1.5">
                  <Label>Payment method</Label>
                  <Select value={methodFilter} onValueChange={setMethodFilter}>
                    <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">Any method</SelectItem>
                      {methodOptions.map((m) => (
                        <SelectItem key={m} value={m}>{m}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-1.5">
                  <Label>Status</Label>
                  <Select value={status} onValueChange={(v) => setStatus(v as BalanceStatusFilter)}>
                    <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {BALANCE_STATUS_FILTERS.map((s) => (
                        <SelectItem key={s} value={s}>
                          {s === "All" ? "All with balance" : s === "Partial" ? "Partially paid" : s}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-1.5">
                  <Label>Period</Label>
                  <Select
                    value={period}
                    onValueChange={(v) => {
                      const r = periodToRange(v as never)
                      // "custom" resolves to null — leave the dates the user typed.
                      if (r) { setFrom(r.from); setTo(r.to) }
                    }}
                  >
                    <SelectTrigger className="w-full"><SelectValue placeholder="Select period" /></SelectTrigger>
                    <SelectContent>
                      {/* Grouped by separators rather than headings, matching the
                          reports' Period dropdown exactly. */}
                      {PERIOD_GROUPS.map((g, gi) => (
                        <SelectGroup key={g.label}>
                          {gi > 0 && <SelectSeparator />}
                          {g.options.map((o) => (
                            <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>
                          ))}
                        </SelectGroup>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="bal-from">From</Label>
                  <Input id="bal-from" type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="bal-to">To</Label>
                  <Input id="bal-to" type="date" value={to} onChange={(e) => setTo(e.target.value)} />
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="bal-min">Min balance</Label>
                  <Input
                    id="bal-min" type="number" min="0" step="0.01"
                    value={minBalance} onChange={(e) => setMinBalance(e.target.value)} placeholder="0.00"
                  />
                </div>
              </div>

              {/* Actions live below a rule, not inline with the inputs: they act
                  ON the filters rather than being one. */}
              <div className="flex flex-wrap items-center justify-end gap-2 border-t pt-3">
                <Button
                  variant="ghost"
                  onClick={() => {
                    setSearch(""); setStatus("All"); setFrom(""); setTo(""); setMinBalance("")
                    setPartyFilter("all"); setMethodFilter("all")
                  }}
                >
                  Reset
                </Button>
                {!isCustomer || canStatement ? (
                  <Button variant="outline" onClick={() => setHistoryFor({ party: null, doc: null })}>
                    <History className="mr-1.5 h-4 w-4" /> All payments
                  </Button>
                ) : null}
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="flex items-center gap-2 p-6 text-slate-500">
                  <Loader2 className="h-4 w-4 animate-spin" /> Loading…
                </div>
              ) : visibleRows.length === 0 ? (
                <div className="p-8 text-center text-slate-500">
                  {methodFilter !== "all" && rows.length > 0
                    ? <>No {partyWord} has paid by <span className="font-medium text-slate-700">{methodFilter}</span> under these filters.</>
                    : <>Nothing outstanding. Every {docWord} is fully paid.</>}
                </div>
              ) : (
                <div className="overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead className="w-8" />
                        <TableHead>{isCustomer ? "Customer" : "Supplier"}</TableHead>
                        <TableHead>Phone</TableHead>
                        <TableHead className="text-right">Balance</TableHead>
                        <TableHead className="text-right">Open {docWord}s</TableHead>
                        <TableHead>Oldest</TableHead>
                        <TableHead>Last payment</TableHead>
                        <TableHead className="text-right">Overdue</TableHead>
                        <TableHead className="text-right">Actions</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {visibleRows.map((party) => {
                        const isOpen = expanded === party.partyId
                        const lines = docs[party.partyId]
                        return (
                          <Fragment key={party.partyId}>
                            <TableRow>
                              <TableCell>
                                <button type="button" onClick={() => toggleParty(party)} aria-label={`Show open ${docWord}s`}>
                                  {isOpen ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
                                </button>
                              </TableCell>
                              <TableCell className="font-medium">
                                <button type="button" className="hover:underline" onClick={() => router.push(partyHref(party.partyId))}>
                                  {party.partyName}
                                </button>
                              </TableCell>
                              <TableCell className="text-slate-500">{party.contactPhone ?? "—"}</TableCell>
                              <TableCell className="text-right font-semibold">{fmt(party.totalBalance)}</TableCell>
                              <TableCell className="text-right">{party.openDocumentCount}</TableCell>
                              <TableCell className="whitespace-nowrap text-slate-500">
                                {party.oldestDocumentDate ? new Date(party.oldestDocumentDate).toLocaleDateString() : "—"}
                              </TableCell>
                              <TableCell className="whitespace-nowrap text-slate-500">
                                {party.lastPaymentDate ? new Date(party.lastPaymentDate).toLocaleDateString() : "Never"}
                              </TableCell>
                              <TableCell className="text-right">
                                {party.overdueAmount > 0
                                  ? <span className="font-medium text-red-600">{fmt(party.overdueAmount)}</span>
                                  : <span className="text-slate-400">—</span>}
                              </TableCell>
                              <TableCell className="text-right">
                                <div className="flex justify-end gap-1">
                                  {canPay && (
                                    <Button size="sm" onClick={() => setPayFor({ party, doc: null })}>
                                      {isCustomer ? "Receive bulk payment" : "Record bulk payment"}
                                    </Button>
                                  )}
                                  {canStatement && (
                                    <Button size="sm" variant="outline" onClick={() => setStatementFor(party)}>
                                      <FileText className="h-3.5 w-3.5" />
                                      <span className="sr-only">View statement</span>
                                    </Button>
                                  )}
                                  <Button size="sm" variant="ghost" onClick={() => setHistoryFor({ party, doc: null })}>
                                    <History className="h-3.5 w-3.5" />
                                    <span className="sr-only">Payment history</span>
                                  </Button>
                                </div>
                              </TableCell>
                            </TableRow>

                            {/* The open documents for one party. Tinted band + a white
                                card so the nested table reads as a detail OF the row
                                above rather than as more rows in the same list — the
                                two share a column count but not a meaning. Both the
                                base and hover colours are set, or TableRow's own
                                hover:bg-muted/50 repaints the band on hover. */}
                            {isOpen && (
                              <TableRow className="bg-blue-50 hover:bg-blue-50">
                                <TableCell />
                                <TableCell colSpan={8} className="py-3 pr-4">
                                  {docsLoading === party.partyId || !lines ? (
                                    <span className="flex items-center gap-2 text-sm text-slate-500">
                                      <Loader2 className="h-3.5 w-3.5 animate-spin" /> Loading open {docWord}s…
                                    </span>
                                  ) : lines.length === 0 ? (
                                    <span className="text-sm text-slate-500">No open {docWord}s match the current filters.</span>
                                  ) : (
                                    <div className="overflow-hidden rounded-md border border-blue-200 bg-white shadow-sm">
                                    <Table>
                                      <TableHeader>
                                        <TableRow className="bg-blue-100 hover:bg-blue-100">
                                          <TableHead>{isCustomer ? "Sale" : "Purchase"}</TableHead>
                                          {/* What was sold or bought, in its own
                                              column. It used to sit stacked under
                                              the reference, which read as one
                                              two-line value under a header that
                                              only named the first half of it. */}
                                          <TableHead>{isCustomer ? "Product" : "Item"}</TableHead>
                                          <TableHead>Date</TableHead>
                                          <TableHead className="text-right">Total</TableHead>
                                          <TableHead className="text-right">Paid</TableHead>
                                          <TableHead className="text-right">Balance</TableHead>
                                          <TableHead>Due</TableHead>
                                          <TableHead className="text-right">Age</TableHead>
                                          <TableHead>Status</TableHead>
                                          <TableHead className="text-right">Actions</TableHead>
                                        </TableRow>
                                      </TableHeader>
                                      <TableBody>
                                        {lines.map((d) => (
                                          <TableRow key={`${d.documentType}:${d.documentId}`}>
                                            <TableCell className="font-medium whitespace-nowrap">
                                              {d.reference ?? d.documentId}
                                            </TableCell>
                                            <TableCell className="text-slate-600">
                                              {d.label ?? d.description ?? "—"}
                                            </TableCell>
                                            <TableCell className="whitespace-nowrap">{new Date(d.documentDate).toLocaleDateString()}</TableCell>
                                            <TableCell className="text-right">{fmt(d.totalAmount)}</TableCell>
                                            <TableCell className="text-right text-slate-500">{fmt(d.amountPaid)}</TableCell>
                                            <TableCell className="text-right font-medium">{fmt(d.balance)}</TableCell>
                                            <TableCell className="whitespace-nowrap text-slate-500">
                                              {d.dueDate ? new Date(d.dueDate).toLocaleDateString() : "—"}
                                            </TableCell>
                                            <TableCell className="text-right">{d.ageDays}d</TableCell>
                                            <TableCell>
                                              {d.isOverdue
                                                ? <Badge variant="destructive" className="gap-1"><AlertTriangle className="h-3 w-3" /> Overdue</Badge>
                                                : <Badge variant="secondary">{d.status}</Badge>}
                                            </TableCell>
                                            <TableCell className="text-right">
                                              <div className="flex justify-end gap-1">
                                                {canPay && (
                                                  <Button size="sm" variant="outline" onClick={() => setPayFor({ party, doc: d })}>
                                                    {isCustomer ? "Receive payment" : "Record payment"}
                                                  </Button>
                                                )}
                                                <Button size="sm" variant="ghost" onClick={() => openDocument(d)}>
                                                  <ExternalLink className="h-3.5 w-3.5" />
                                                  <span className="sr-only">Open {docWord}</span>
                                                </Button>
                                                <Button size="sm" variant="ghost" onClick={() => setHistoryFor({ party, doc: d })}>
                                                  <History className="h-3.5 w-3.5" />
                                                  <span className="sr-only">Payment history</span>
                                                </Button>
                                              </div>
                                            </TableCell>
                                          </TableRow>
                                        ))}
                                      </TableBody>
                                    </Table>
                                    </div>
                                  )}
                                </TableCell>
                              </TableRow>
                            )}
                          </Fragment>
                        )
                      })}
                    </TableBody>
                  </Table>
                </div>
              )}
            </CardContent>
          </Card>
        </main>
      </div>

      <RecordPaymentDialog
        open={payFor !== null}
        onOpenChange={(o) => { if (!o) setPayFor(null) }}
        module={module}
        side={side}
        party={payFor?.party ?? null}
        singleDocument={payFor?.doc ?? null}
        cashAccounts={cashAccounts}
        onPosted={() => { setExpanded(null); setPaymentsVersion((v) => v + 1); void load() }}
      />

      <StatementDialog
        open={statementFor !== null}
        onOpenChange={(o) => { if (!o) setStatementFor(null) }}
        module={module}
        side={side}
        party={statementFor}
      />

      <PaymentHistoryDialog
        open={historyFor !== null}
        onOpenChange={(o) => { if (!o) setHistoryFor(null) }}
        module={module}
        side={side}
        partyId={historyFor?.party?.partyId ?? null}
        partyName={historyFor?.party?.partyName ?? null}
        documentType={historyFor?.doc?.documentType ?? null}
        documentId={historyFor?.doc?.documentId ?? null}
        canReverse={canReverse}
        onReversed={() => { setExpanded(null); setPaymentsVersion((v) => v + 1); void load() }}
      />
    </div>
  )
}
