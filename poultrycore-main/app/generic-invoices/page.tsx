"use client"

// Invoices — the unified invoice management workspace.
//
// Displays BOTH types of invoices that exist in the system:
//   1. Invoice Documents (migration 494) — formal billing records generated
//      from posted Sales via the "Generate Invoice" action.
//   2. Subscription Invoices (migration 243) — genericsales rows raised by
//      billing runs with due dates and subscription links.
//
// For subscription businesses, both coexist. For retail businesses without
// subscriptions, only invoice documents appear.

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { SortableHeader, sortData, toggleSort, type SortDirection } from "@/components/ui/sortable-header"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { ListFilters } from "@/components/ui/list-filters"
import { Checkbox } from "@/components/ui/checkbox"
import { Label } from "@/components/ui/label"
import {
  AlertTriangle, Banknote, Check, Clock, Eye, FileText,
  Loader2, Receipt, ShoppingCart, TrendingUp,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { useGenericModules } from "@/hooks/use-generic-modules"
import { cn } from "@/lib/utils"
import {
  getInvoices, getBusinessTemplate, type GenericInvoiceRow,
} from "@/lib/api/generic-subscriptions"
import {
  getInvoiceDocuments, type InvoiceDocumentRow,
} from "@/lib/api/generic-invoice-documents"
import { approveSale } from "@/lib/api/generic"
import { templateLabels } from "@/lib/generic/template-labels"
import { fmtDateTime } from "@/lib/utils/company-datetime"

// =============================================================================
// Unified row type — merges subscription invoices and document invoices
// =============================================================================

interface UnifiedInvoiceRow {
  id: string
  type: "document" | "subscription"
  docId?: number
  saleId?: number
  invoiceNumber: string
  customerName: string
  issueDate: string
  dueDate: string | null
  billingPeriod: string | null
  projectName: string | null
  totalAmount: number
  amountPaid: number
  balance: number
  documentStatus: string
  paymentStatus: string
  isOverdue: boolean
  daysUntilDue: number | null
}

function mergeRows(
  docs: InvoiceDocumentRow[],
  subs: GenericInvoiceRow[],
): UnifiedInvoiceRow[] {
  const docSaleIds = new Set(docs.map((d) => d.genericSaleId))
  const rows: UnifiedInvoiceRow[] = []

  for (const d of docs) {
    rows.push({
      id: `doc-${d.genericInvoiceDocumentId}`,
      type: "document",
      docId: d.genericInvoiceDocumentId,
      saleId: d.genericSaleId,
      invoiceNumber: d.invoiceNumber,
      customerName: d.customerBillingName || "—",
      issueDate: d.issueDate,
      dueDate: d.dueDate,
      billingPeriod: null,
      projectName: d.projectName,
      totalAmount: d.totalAmount,
      amountPaid: d.amountPaid,
      balance: d.balance,
      documentStatus: d.documentStatus,
      paymentStatus: d.paymentStatus || (d.balance <= 0 ? "Paid" : d.amountPaid > 0 ? "PartiallyPaid" : "Unpaid"),
      isOverdue: d.isOverdue,
      daysUntilDue: d.daysUntilDue,
    })
  }

  for (const s of subs) {
    if (docSaleIds.has(s.genericSaleId)) continue
    rows.push({
      id: `sub-${s.genericSaleId}`,
      type: "subscription",
      saleId: s.genericSaleId,
      invoiceNumber: s.receiptNumber || `#${s.genericSaleId}`,
      customerName: displayCustomer(s),
      issueDate: typeof s.saleDate === "string" ? s.saleDate : new Date(s.saleDate).toISOString(),
      dueDate: s.dueDate || null,
      billingPeriod: s.billingPeriodStart && s.billingPeriodEnd
        ? `${s.billingPeriodStart} → ${s.billingPeriodEnd}` : null,
      projectName: null,
      totalAmount: s.totalAmount,
      amountPaid: s.amountPaid,
      balance: s.balance,
      documentStatus: s.status,
      paymentStatus: s.paymentStatus || (s.balance <= 0 ? "Paid" : s.amountPaid > 0 ? "PartiallyPaid" : "Unpaid"),
      isOverdue: s.isOverdue,
      daysUntilDue: null,
    })
  }

  return rows
}

function displayCustomer(i: { customerName?: string | null; notes?: string | null }): string {
  if (i.customerName) return i.customerName
  if (i.notes?.startsWith("Customer: ")) {
    const pipe = i.notes.indexOf(" | ")
    return pipe > 0 ? i.notes.slice(10, pipe) : i.notes.slice(10)
  }
  return "—"
}

// =============================================================================
// Status helpers
// =============================================================================

function docStatusBadge(status: string) {
  const styles: Record<string, string> = {
    Draft:     "border-slate-300 bg-slate-50 text-slate-600",
    Issued:    "border-indigo-300 bg-indigo-50 text-indigo-700",
    Approved:  "border-emerald-300 bg-emerald-50 text-emerald-700",
    Voided:    "border-rose-300 bg-rose-50 text-rose-700",
    Cancelled: "border-slate-300 bg-slate-100 text-slate-500",
  }
  return <Badge variant="outline" className={styles[status] ?? styles.Draft}>{status}</Badge>
}

function payStatusBadge(status: string, balance: number, docStatus: string) {
  if (docStatus === "Voided" || docStatus === "Cancelled") return null
  if (balance <= 0) return <Badge variant="outline" className="border-emerald-300 bg-emerald-50 text-emerald-700">Paid</Badge>
  if (status === "PartiallyPaid") return <Badge variant="outline" className="border-amber-300 bg-amber-50 text-amber-700">Partial</Badge>
  return <Badge variant="outline" className="border-rose-300 bg-rose-50 text-rose-700">Unpaid</Badge>
}

// =============================================================================
// Page
// =============================================================================

export default function GenericInvoicesPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()
  const { showNew, labels } = useGenericModules()
  const hasSubscriptions = showNew("enableSubscriptions")

  const [docRows, setDocRows] = useState<InvoiceDocumentRow[]>([])
  const [subRows, setSubRows] = useState<GenericInvoiceRow[]>([])
  const [industry, setIndustry] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [approving, setApproving] = useState<number | null>(null)

  // Filters
  const [search, setSearch] = useState("")
  const [from, setFrom] = useState("")
  const [to, setTo] = useState("")
  const [docStatusFilter, setDocStatusFilter] = useState("All")
  const [payStatusFilter, setPayStatusFilter] = useState("All")
  const [subsOnly, setSubsOnly] = useState(false)
  const [overdueOnly, setOverdueOnly] = useState(false)

  // Sort
  const [sortKey, setSortKey] = useState<string | null>(null)
  const [sortDirection, setSortDirection] = useState<SortDirection>(null)
  const handleSort = (key: string) => {
    const next = toggleSort(key, sortKey, sortDirection)
    setSortKey(next.key)
    setSortDirection(next.direction)
  }

  const tl = templateLabels(industry)

  const load = async () => {
    setLoading(true)
    try {
      const [docs, subs, template] = await Promise.all([
        getInvoiceDocuments({
          documentStatus: docStatusFilter !== "All" ? docStatusFilter : undefined,
          paymentStatus: payStatusFilter !== "All" ? payStatusFilter : undefined,
          from: from || undefined,
          to: to || undefined,
          overdueOnly,
        }).catch(() => []),
        hasSubscriptions
          ? getInvoices({ status: docStatusFilter, subscriptionOnly: subsOnly }).catch(() => [])
          : Promise.resolve([]),
        getBusinessTemplate().catch(() => null),
      ])
      setDocRows(docs)
      setSubRows(subs)
      setIndustry(template?.genericIndustryTemplate ?? null)
    } catch (e: any) {
      toast({ title: "Could not load invoices", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router, docStatusFilter, payStatusFilter, subsOnly, overdueOnly, from, to])

  const allRows = useMemo(() => mergeRows(docRows, subRows), [docRows, subRows])

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase()
    return allRows.filter((r) => {
      if (q) {
        const hay = [r.invoiceNumber, r.customerName, r.projectName]
          .filter(Boolean).join(" ").toLowerCase()
        if (!hay.includes(q)) return false
      }
      return true
    })
  }, [allRows, search])

  const sorted = useMemo(
    () => sortData(filtered, sortKey, sortDirection, (r, key) => {
      switch (key) {
        case "invoice": return r.invoiceNumber
        case "customer": return r.customerName
        case "date": return r.issueDate
        case "due": return r.dueDate ?? ""
        case "total": return r.totalAmount
        case "paid": return r.amountPaid
        case "balance": return r.balance
        case "status": return r.documentStatus
        default: return null
      }
    }),
    [filtered, sortKey, sortDirection],
  )

  const pg = usePagination(sorted)

  // KPI calculations
  const kpis = useMemo(() => {
    const active = allRows.filter((r) => r.documentStatus !== "Voided" && r.documentStatus !== "Cancelled")
    return {
      totalInvoiced: active.reduce((s, r) => s + r.totalAmount, 0),
      totalOutstanding: active.reduce((s, r) => s + r.balance, 0),
      totalOverdue: active.filter((r) => r.isOverdue).reduce((s, r) => s + r.balance, 0),
      totalCollected: active.reduce((s, r) => s + r.amountPaid, 0),
      overdueCount: active.filter((r) => r.isOverdue).length,
      draftCount: active.filter((r) => r.documentStatus === "Draft").length,
    }
  }, [allRows])

  const collectionRate = kpis.totalInvoiced > 0
    ? Math.round((kpis.totalCollected / kpis.totalInvoiced) * 100) : 0

  const onApprove = async (inv: UnifiedInvoiceRow) => {
    if (!inv.saleId) return
    setApproving(inv.saleId)
    try {
      await approveSale(inv.saleId)
      toast({
        title: `${inv.invoiceNumber} approved.`,
        description: `${fmt(inv.totalAmount)} is now owed by ${inv.customerName}.`,
      })
      await load()
    } catch (e: any) {
      toast({ title: "Could not approve", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setApproving(null)
    }
  }

  const rowLink = (r: UnifiedInvoiceRow): string =>
    r.type === "document" && r.docId
      ? `/generic-invoice-documents/${r.docId}`
      : `/generic-sales/${r.saleId}`

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          {/* Header */}
          <div className="mb-1 flex flex-wrap items-start justify-between gap-2">
            <h1 className="flex items-center gap-2 text-2xl font-semibold text-slate-900">
              <FileText className="h-6 w-6 text-indigo-600" /> {tl.invoicePlural}
            </h1>
            <div className="flex gap-2">
              {hasSubscriptions && (
                <Button asChild variant="outline" className="h-10">
                  <Link href="/generic-billing-runs"><Receipt className="mr-1.5 h-4 w-4" /> Billing runs</Link>
                </Button>
              )}
              <Button asChild variant="outline" className="h-10">
                <Link href="/generic-sales"><ShoppingCart className="mr-1.5 h-4 w-4" /> Sales</Link>
              </Button>
            </div>
          </div>
          <p className="mb-4 text-sm text-slate-500">
            Track and manage invoices generated from your sales. Issue, collect, and monitor overdue payments.
          </p>

          {/* KPI cards */}
          {!loading && (
            <div className="mb-4 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
              <div className="rounded-lg border bg-white p-3">
                <div className="flex items-center gap-1.5 text-xs text-slate-500">
                  <FileText className="h-3.5 w-3.5" /> Total invoiced
                </div>
                <div className="mt-1 text-xl font-bold tabular-nums">{fmt(kpis.totalInvoiced)}</div>
              </div>
              <div className="rounded-lg border bg-white p-3">
                <div className="flex items-center gap-1.5 text-xs text-slate-500">
                  <Clock className="h-3.5 w-3.5" /> Outstanding
                </div>
                <div className="mt-1 text-xl font-bold tabular-nums text-amber-700">{fmt(kpis.totalOutstanding)}</div>
              </div>
              <div className="rounded-lg border bg-white p-3">
                <div className="flex items-center gap-1.5 text-xs text-rose-500">
                  <AlertTriangle className="h-3.5 w-3.5" /> Overdue
                </div>
                <div className={cn("mt-1 text-xl font-bold tabular-nums", kpis.totalOverdue > 0 ? "text-rose-700" : "text-slate-900")}>
                  {fmt(kpis.totalOverdue)}
                </div>
                {kpis.overdueCount > 0 && (
                  <div className="mt-0.5 text-[11px] text-rose-600">{kpis.overdueCount} invoice{kpis.overdueCount !== 1 ? "s" : ""}</div>
                )}
              </div>
              <div className="rounded-lg border bg-white p-3">
                <div className="flex items-center gap-1.5 text-xs text-slate-500">
                  <Banknote className="h-3.5 w-3.5" /> Collected
                </div>
                <div className="mt-1 text-xl font-bold tabular-nums text-emerald-700">{fmt(kpis.totalCollected)}</div>
              </div>
              <div className="rounded-lg border bg-white p-3">
                <div className="flex items-center gap-1.5 text-xs text-slate-500">
                  <TrendingUp className="h-3.5 w-3.5" /> Collection rate
                </div>
                <div className={cn("mt-1 text-xl font-bold tabular-nums", collectionRate >= 80 ? "text-emerald-700" : collectionRate >= 50 ? "text-amber-700" : "text-rose-700")}>
                  {collectionRate}%
                </div>
              </div>
              <div className="rounded-lg border bg-white p-3">
                <div className="flex items-center gap-1.5 text-xs text-slate-500">
                  <FileText className="h-3.5 w-3.5" /> Draft
                </div>
                <div className="mt-1 text-xl font-bold tabular-nums">{kpis.draftCount}</div>
              </div>
            </div>
          )}

          {/* Filters */}
          <ListFilters
            search={search} setSearch={setSearch}
            dateFrom={from} setDateFrom={setFrom}
            dateTo={to} setDateTo={setTo}
            searchPlaceholder={`Search invoice, ${tl.customer.toLowerCase()}, project…`}
            searchWidthClassName="sm:w-[180px]"
            extras={
              <>
                <div className="w-full sm:w-[140px]">
                  <Label className="text-xs text-slate-500">Doc status</Label>
                  <Select value={docStatusFilter} onValueChange={setDocStatusFilter}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {["All", "Draft", "Issued", "Approved", "Voided", "Cancelled"].map((s) => (
                        <SelectItem key={s} value={s}>{s}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="w-full sm:w-[140px]">
                  <Label className="text-xs text-slate-500">Payment</Label>
                  <Select value={payStatusFilter} onValueChange={setPayStatusFilter}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {["All", "Unpaid", "PartiallyPaid", "Paid"].map((s) => (
                        <SelectItem key={s} value={s}>{s === "PartiallyPaid" ? "Partial" : s}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="flex items-end gap-4 pb-1">
                  <label className="flex items-center gap-1.5 text-sm cursor-pointer">
                    <Checkbox checked={overdueOnly} onCheckedChange={(v) => setOverdueOnly(v === true)} />
                    Overdue
                  </label>
                  {hasSubscriptions && (
                    <label className="flex items-center gap-1.5 text-sm cursor-pointer">
                      <Checkbox checked={subsOnly} onCheckedChange={(v) => setSubsOnly(v === true)} />
                      Subs only
                    </label>
                  )}
                </div>
              </>
            }
          />

          {/* Content */}
          <Card className="mt-1">
            <CardContent className="p-0">
              {loading ? (
                <div className="flex items-center gap-2 p-6 text-slate-500">
                  <Loader2 className="h-4 w-4 animate-spin" /> Loading…
                </div>
              ) : filtered.length === 0 ? (
                <div className="p-8 text-center text-slate-500">
                  {allRows.length === 0 ? (
                    <>
                      <FileText className="mx-auto mb-3 h-10 w-10 text-slate-300" />
                      <p className="font-medium text-slate-700">No invoices yet</p>
                      <p className="mt-1">
                        Generate an invoice from a recorded sale to begin.{" "}
                        <Link href="/generic-sales" className="text-indigo-600 underline">Go to Sales</Link>
                      </p>
                    </>
                  ) : "No invoices match those filters."}
                </div>
              ) : (
                <>
                  {/* Mobile cards */}
                  <div className="space-y-2 p-3 lg:hidden">
                    {pg.pageItems.map((r, idx) => {
                      const stripe = idx % 2 === 0
                      return (
                        <div
                          key={r.id}
                          className={cn(
                            "overflow-hidden rounded-xl border p-3 shadow-sm",
                            stripe ? "border-indigo-200 bg-indigo-50/60" : "border-slate-200 bg-white",
                          )}
                        >
                          <div className="flex items-start justify-between gap-2">
                            <div className="min-w-0 flex-1">
                              <Link href={rowLink(r)} className="font-mono text-sm font-semibold text-indigo-700 hover:underline">
                                {r.invoiceNumber}
                              </Link>
                              <div className="mt-0.5 truncate text-sm text-slate-700">{r.customerName}</div>
                            </div>
                            <div className="text-right">
                              <div className="font-semibold tabular-nums">{fmt(r.totalAmount)}</div>
                              {r.balance > 0 && (
                                <div className="text-xs font-medium tabular-nums text-rose-700">
                                  {fmt(r.balance)} owed
                                </div>
                              )}
                            </div>
                          </div>

                          <div className="mt-2 flex flex-wrap items-center gap-1">
                            {docStatusBadge(r.documentStatus)}
                            {payStatusBadge(r.paymentStatus, r.balance, r.documentStatus)}
                            {r.isOverdue && (
                              <Badge variant="outline" className="border-rose-300 bg-rose-50 text-rose-700">
                                <AlertTriangle className="mr-0.5 h-3 w-3" /> Overdue
                                {r.daysUntilDue != null && r.daysUntilDue < 0 ? ` ${-r.daysUntilDue}d` : ""}
                              </Badge>
                            )}
                          </div>

                          <div className="mt-2 grid grid-cols-2 gap-x-3 gap-y-1 text-xs text-slate-500">
                            <span>Issued: {fmtDateTime(r.issueDate, r)}</span>
                            <span className="text-right">Due: {r.dueDate ?? "—"}</span>
                            {r.projectName && <span className="col-span-2 truncate text-indigo-600">{r.projectName}</span>}
                            {r.billingPeriod && <span className="col-span-2 truncate">{r.billingPeriod}</span>}
                            <span className="text-emerald-700">Paid: {fmt(r.amountPaid)}</span>
                          </div>

                          <div className="mt-2 flex gap-2">
                            <Button asChild size="sm" variant="outline" className="h-9 flex-1 bg-white">
                              <Link href={rowLink(r)}><Eye className="mr-1 h-3.5 w-3.5" /> View</Link>
                            </Button>
                            {r.type === "subscription" && r.documentStatus === "Draft" && (
                              <Button
                                size="sm"
                                className="h-9 flex-1 bg-emerald-600 hover:bg-emerald-700"
                                disabled={approving === r.saleId}
                                onClick={() => onApprove(r)}
                              >
                                {approving === r.saleId
                                  ? <Loader2 className="mr-1 h-3.5 w-3.5 animate-spin" />
                                  : <Check className="mr-1 h-3.5 w-3.5" />}
                                Approve
                              </Button>
                            )}
                          </div>
                        </div>
                      )
                    })}
                    <div className="px-3 py-3">
                      <DataPagination {...pg.paginationProps} />
                    </div>
                  </div>

                  {/* Desktop table */}
                  <div className="hidden lg:block">
                    <Table className="w-full [&_td]:whitespace-normal [&_th]:whitespace-normal">
                      <TableHeader>
                        <TableRow>
                          <SortableHeader label="Invoice" sortKey="invoice" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} />
                          <SortableHeader label={tl.customer} sortKey="customer" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} />
                          <SortableHeader label="Date" sortKey="date" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} />
                          <SortableHeader label="Due" sortKey="due" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} />
                          {hasSubscriptions && <TableHead>Period</TableHead>}
                          <SortableHeader label="Total" sortKey="total" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="text-right" />
                          <SortableHeader label="Paid" sortKey="paid" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="text-right" />
                          <SortableHeader label="Balance" sortKey="balance" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="text-right" />
                          <SortableHeader label="Status" sortKey="status" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} />
                          <TableHead className="w-20 text-right"><span className="sr-only">Actions</span></TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {pg.pageItems.map((r) => (
                          <TableRow key={r.id} className={r.documentStatus === "Voided" ? "text-slate-400" : undefined}>
                            <TableCell className="whitespace-nowrap!">
                              <Link href={rowLink(r)} className="font-mono text-sm font-medium text-indigo-700 hover:underline">
                                {r.invoiceNumber}
                              </Link>
                              {r.projectName && <div className="text-[11px] text-indigo-500">{r.projectName}</div>}
                            </TableCell>
                            <TableCell className="font-medium">{r.customerName}</TableCell>
                            <TableCell className="whitespace-nowrap!">{fmtDateTime(r.issueDate, r)}</TableCell>
                            <TableCell className={cn("whitespace-nowrap!", r.isOverdue && "text-rose-700 font-medium")}>
                              {r.dueDate ?? "—"}
                              {r.isOverdue && r.daysUntilDue != null && r.daysUntilDue < 0 && (
                                <span className="ml-1 rounded bg-rose-100 px-1 py-0.5 text-[10px] font-medium text-rose-700">
                                  {-r.daysUntilDue}d late
                                </span>
                              )}
                            </TableCell>
                            {hasSubscriptions && (
                              <TableCell className="whitespace-nowrap text-xs text-slate-600">
                                {r.billingPeriod || "—"}
                              </TableCell>
                            )}
                            <TableCell className="whitespace-nowrap! text-right tabular-nums font-semibold">
                              {fmt(r.totalAmount)}
                            </TableCell>
                            <TableCell className="whitespace-nowrap! text-right tabular-nums text-emerald-700">
                              {fmt(r.amountPaid)}
                            </TableCell>
                            <TableCell className="whitespace-nowrap! text-right tabular-nums">
                              <span className={cn(r.balance > 0 ? "font-semibold text-rose-700" : "text-emerald-700")}>
                                {r.balance > 0 ? fmt(r.balance) : "Settled"}
                              </span>
                            </TableCell>
                            <TableCell>
                              <div className="flex items-center gap-1 flex-wrap">
                                {docStatusBadge(r.documentStatus)}
                                {payStatusBadge(r.paymentStatus, r.balance, r.documentStatus)}
                                {r.isOverdue && (
                                  <Badge variant="outline" className="border-rose-300 bg-rose-50 text-rose-700">
                                    <AlertTriangle className="mr-0.5 h-3 w-3" /> Overdue
                                  </Badge>
                                )}
                              </div>
                            </TableCell>
                            <TableCell className="whitespace-nowrap! text-right">
                              <Button asChild variant="ghost" size="icon" className="h-8 w-8"
                                      aria-label="View invoice" title="View invoice">
                                <Link href={rowLink(r)}><Eye className="h-3.5 w-3.5" /></Link>
                              </Button>
                              {r.type === "subscription" && r.documentStatus === "Draft" && (
                                <Button
                                  variant="ghost"
                                  size="icon"
                                  className="h-8 w-8 text-emerald-700"
                                  disabled={approving === r.saleId}
                                  onClick={() => onApprove(r)}
                                  aria-label="Approve" title="Approve invoice"
                                >
                                  {approving === r.saleId
                                    ? <Loader2 className="h-3.5 w-3.5 animate-spin" />
                                    : <Check className="h-3.5 w-3.5" />}
                                </Button>
                              )}
                            </TableCell>
                          </TableRow>
                        ))}
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
    </div>
  )
}
