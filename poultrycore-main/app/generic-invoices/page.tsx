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
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Checkbox } from "@/components/ui/checkbox"
import { Label } from "@/components/ui/label"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import {
  ArrowLeft, Loader2, FileText, Check, AlertTriangle, Eye, Plus, Receipt,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { useGenericModules } from "@/hooks/use-generic-modules"
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
  id: string // unique key
  type: "document" | "subscription"
  // Document invoices
  docId?: number
  // Subscription invoices
  saleId?: number
  // Common display
  invoiceNumber: string
  customerName: string
  issueDate: string
  dueDate: string | null
  billingPeriod: string | null
  projectName: string | null
  totalAmount: number
  amountPaid: number
  balance: number
  documentStatus: string // Draft | Issued | Voided (documents) or Draft | Approved | Cancelled (subscriptions)
  paymentStatus: string // Unpaid | PartiallyPaid | Paid
  isOverdue: boolean
  daysUntilDue: number | null
}

function mergeRows(
  docs: InvoiceDocumentRow[],
  subs: GenericInvoiceRow[],
): UnifiedInvoiceRow[] {
  const docSaleIds = new Set(docs.map((d) => d.genericSaleId))
  const rows: UnifiedInvoiceRow[] = []

  // Document invoices first
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

  // Subscription invoices — skip any that have a document invoice (avoid double-counting)
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

const DOC_STATUS_STYLES: Record<string, string> = {
  Draft:     "bg-slate-100 text-slate-600 hover:bg-slate-100",
  Issued:    "bg-indigo-100 text-indigo-800 hover:bg-indigo-100",
  Approved:  "bg-emerald-100 text-emerald-800 hover:bg-emerald-100",
  Voided:    "bg-rose-100 text-rose-700 hover:bg-rose-100",
  Cancelled: "bg-slate-200 text-slate-700 hover:bg-slate-200",
  Refunded:  "bg-amber-100 text-amber-800 hover:bg-amber-100",
}

const PAY_STATUS_STYLES: Record<string, string> = {
  Paid:          "bg-emerald-50 text-emerald-700 hover:bg-emerald-50",
  PartiallyPaid: "bg-amber-50 text-amber-700 hover:bg-amber-50",
  Unpaid:        "bg-rose-50 text-rose-700 hover:bg-rose-50",
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
  const { showNew, labels, isSubscriptionBusiness } = useGenericModules()
  const hasSubscriptions = showNew("enableSubscriptions")

  const [docRows, setDocRows] = useState<InvoiceDocumentRow[]>([])
  const [subRows, setSubRows] = useState<GenericInvoiceRow[]>([])
  const [industry, setIndustry] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [approving, setApproving] = useState<number | null>(null)

  // Filters
  const [search, setSearch] = useState("")
  const [docStatusFilter, setDocStatusFilter] = useState("All")
  const [payStatusFilter, setPayStatusFilter] = useState("All")
  const [subsOnly, setSubsOnly] = useState(false)
  const [overdueOnly, setOverdueOnly] = useState(false)

  const tl = templateLabels(industry)

  const load = async () => {
    setLoading(true)
    try {
      const [docs, subs, template] = await Promise.all([
        getInvoiceDocuments({
          documentStatus: docStatusFilter !== "All" ? docStatusFilter : undefined,
          paymentStatus: payStatusFilter !== "All" ? payStatusFilter : undefined,
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
  }, [activeFarmType, router, docStatusFilter, payStatusFilter, subsOnly, overdueOnly])

  const allRows = useMemo(() => mergeRows(docRows, subRows), [docRows, subRows])

  const visible = useMemo(
    () => filterByDateAndSearch(allRows, {
      search,
      searchKeys: ["invoiceNumber", "customerName", "projectName"],
    }),
    [allRows, search],
  )
  const pg = usePagination(visible)

  // KPI calculations
  const kpis = useMemo(() => {
    const active = allRows.filter((r) => r.documentStatus !== "Voided" && r.documentStatus !== "Cancelled")
    return {
      totalInvoiced: active.reduce((s, r) => s + r.totalAmount, 0),
      totalOutstanding: active.reduce((s, r) => s + r.balance, 0),
      totalOverdue: active.filter((r) => r.isOverdue).reduce((s, r) => s + r.balance, 0),
      totalCollected: active.reduce((s, r) => s + r.amountPaid, 0),
      draftCount: active.filter((r) => r.documentStatus === "Draft").length,
      unpaidCount: active.filter((r) => r.balance > 0).length,
    }
  }, [allRows])

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

  const statusCell = (r: UnifiedInvoiceRow) => (
    <div className="flex items-center gap-1 flex-wrap">
      <Badge className={DOC_STATUS_STYLES[r.documentStatus] ?? DOC_STATUS_STYLES.Draft}>
        {r.documentStatus}
      </Badge>
      {r.balance > 0 && r.documentStatus !== "Voided" && r.documentStatus !== "Cancelled" && (
        <Badge className={PAY_STATUS_STYLES[r.paymentStatus] ?? PAY_STATUS_STYLES.Unpaid}>
          {r.paymentStatus === "PartiallyPaid" ? "Partial" : r.paymentStatus}
        </Badge>
      )}
      {r.isOverdue && (
        <Badge className="bg-rose-100 text-rose-800 hover:bg-rose-100">
          <AlertTriangle className="h-3 w-3 mr-0.5" /> Overdue
        </Badge>
      )}
    </div>
  )

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          {/* Header */}
          <div className="mb-4 flex items-center justify-between flex-wrap gap-2">
            <div>
              <button onClick={() => router.back()} className="rounded-full p-1 hover:bg-slate-200 transition" title="Go back">
                <ArrowLeft className="w-5 h-5 text-slate-600" />
              </button>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <FileText className="h-6 w-6 text-indigo-600" /> {tl.invoicePlural}
              </h1>
              <p className="text-sm text-slate-500">
                Create, issue, track, and collect payments for invoices across your business.
              </p>
            </div>
            <div className="flex gap-2">
              {hasSubscriptions && (
                <Link href="/generic-billing-runs">
                  <Button variant="outline" className="h-11 sm:h-10"><Receipt className="h-4 w-4 mr-1" /> Billing runs</Button>
                </Link>
              )}
              <Link href="/generic-customer-balances">
                <Button variant="outline" className="h-11 sm:h-10">{tl.customerBalance}</Button>
              </Link>
            </div>
          </div>

          {/* KPI cards */}
          {!loading && allRows.length > 0 && (
            <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-3 mb-4">
              <Card><CardContent className="py-3 px-4">
                <div className="text-xs text-slate-500">Total invoiced</div>
                <div className="text-lg font-semibold">{fmt(kpis.totalInvoiced)}</div>
              </CardContent></Card>
              <Card><CardContent className="py-3 px-4">
                <div className="text-xs text-slate-500">Outstanding</div>
                <div className="text-lg font-semibold text-rose-700">{fmt(kpis.totalOutstanding)}</div>
              </CardContent></Card>
              <Card><CardContent className="py-3 px-4">
                <div className="text-xs text-slate-500">Overdue</div>
                <div className={`text-lg font-semibold ${kpis.totalOverdue > 0 ? "text-rose-700" : ""}`}>{fmt(kpis.totalOverdue)}</div>
              </CardContent></Card>
              <Card><CardContent className="py-3 px-4">
                <div className="text-xs text-slate-500">Collected</div>
                <div className="text-lg font-semibold text-emerald-700">{fmt(kpis.totalCollected)}</div>
              </CardContent></Card>
              <Card><CardContent className="py-3 px-4">
                <div className="text-xs text-slate-500">Unpaid</div>
                <div className="text-lg font-semibold">{kpis.unpaidCount}</div>
              </CardContent></Card>
              <Card><CardContent className="py-3 px-4">
                <div className="text-xs text-slate-500">Draft</div>
                <div className="text-lg font-semibold">{kpis.draftCount}</div>
              </CardContent></Card>
            </div>
          )}

          {/* Filters */}
          <div className="flex flex-wrap items-end gap-3 mb-3">
            <div className="flex-1 min-w-[220px]">
              <ListFilters
                search={search}
                setSearch={setSearch}
                searchOnly
                searchPlaceholder={`Search number, ${tl.customer.toLowerCase()}, or project`}
              />
            </div>
            <Select value={docStatusFilter} onValueChange={setDocStatusFilter}>
              <SelectTrigger className="w-[150px]">
                <SelectValue placeholder="Doc status" />
              </SelectTrigger>
              <SelectContent>
                {["All", "Draft", "Issued", "Approved", "Voided", "Cancelled"].map((s) => (
                  <SelectItem key={s} value={s}>{s}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Select value={payStatusFilter} onValueChange={setPayStatusFilter}>
              <SelectTrigger className="w-[150px]">
                <SelectValue placeholder="Payment" />
              </SelectTrigger>
              <SelectContent>
                {["All", "Unpaid", "PartiallyPaid", "Paid"].map((s) => (
                  <SelectItem key={s} value={s}>{s === "PartiallyPaid" ? "Partial" : s}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            <div className="flex items-center gap-4 h-10">
              <div className="flex items-center gap-2">
                <Checkbox id="overdueOnly" checked={overdueOnly} onCheckedChange={(v) => setOverdueOnly(v === true)} />
                <Label htmlFor="overdueOnly" className="cursor-pointer text-sm">Overdue only</Label>
              </div>
              {hasSubscriptions && (
                <div className="flex items-center gap-2">
                  <Checkbox id="subsOnly" checked={subsOnly} onCheckedChange={(v) => setSubsOnly(v === true)} />
                  <Label htmlFor="subsOnly" className="cursor-pointer text-sm">Subscriptions only</Label>
                </div>
              )}
            </div>
          </div>

          {/* Content */}
          {loading ? (
            <div className="flex items-center gap-2 text-slate-500">
              <Loader2 className="h-4 w-4 animate-spin" /> Loading…
            </div>
          ) : allRows.length === 0 ? (
            <Card>
              <CardContent className="py-8 text-center text-slate-500">
                <FileText className="h-10 w-10 text-slate-300 mx-auto mb-3" />
                <p className="font-medium text-slate-700">No invoices yet</p>
                <p className="mt-1">
                  Generate an invoice from a recorded sale to begin.{" "}
                  <Link href="/generic-sales" className="text-indigo-600 underline">Go to Sales</Link>
                </p>
              </CardContent>
            </Card>
          ) : (
            <Card>
              <CardContent className="p-0">
                <MobileCardList
                  items={pg.pageItems}
                  getKey={(r) => r.id}
                  primary={(r) => (
                    <Link href={rowLink(r)} className="text-indigo-700 underline font-mono text-xs">
                      {r.invoiceNumber}
                    </Link>
                  )}
                  secondary={(r) => (
                    <>
                      <span>{r.customerName}</span>
                      <span> · {fmt(r.totalAmount)}</span>
                    </>
                  )}
                  trailing={(r) => statusCell(r)}
                  details={(r) => [
                    { label: "Date", value: fmtDateTime(r.issueDate, r) },
                    { label: "Due", value: r.dueDate ?? "—" },
                    ...(r.billingPeriod ? [{ label: "Period", value: r.billingPeriod }] : []),
                    ...(r.projectName ? [{ label: "Project", value: r.projectName }] : []),
                    { label: "Paid", value: fmt(r.amountPaid) },
                    { label: "Balance", value: (
                      <span className={r.balance > 0 ? "text-rose-700 font-semibold" : ""}>{fmt(r.balance)}</span>
                    )},
                  ]}
                  actions={(r) => (
                    <div className="flex gap-2">
                      <Button asChild size="sm" variant="outline" className="flex-1 h-10">
                        <Link href={rowLink(r)}><Eye className="h-4 w-4 mr-1" /> View</Link>
                      </Button>
                      {r.type === "subscription" && r.documentStatus === "Draft" && (
                        <Button
                          size="sm"
                          className="flex-1 h-10"
                          disabled={approving === r.saleId}
                          onClick={() => onApprove(r)}
                        >
                          {approving === r.saleId
                            ? <Loader2 className="h-4 w-4 mr-1 animate-spin" />
                            : <Check className="h-4 w-4 mr-1" />}
                          Approve
                        </Button>
                      )}
                    </div>
                  )}
                  pagination={pg.paginationProps}
                  desktopTable={
                    <div className="overflow-x-auto">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Invoice #</TableHead>
                            <TableHead>{tl.customer}</TableHead>
                            <TableHead>Date</TableHead>
                            <TableHead>Due</TableHead>
                            {hasSubscriptions && <TableHead>Period</TableHead>}
                            <TableHead className="text-right">Total</TableHead>
                            <TableHead className="text-right">Paid</TableHead>
                            <TableHead className="text-right">Balance</TableHead>
                            <TableHead>Status</TableHead>
                            <TableHead className="text-right">Actions</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {pg.pageItems.map((r) => (
                            <TableRow key={r.id}>
                              <TableCell>
                                <Link href={rowLink(r)} className="text-indigo-700 underline font-mono text-xs">
                                  {r.invoiceNumber}
                                </Link>
                                {r.projectName && <div className="text-[11px] text-indigo-600">{r.projectName}</div>}
                              </TableCell>
                              <TableCell className="font-medium">{r.customerName}</TableCell>
                              <TableCell>{fmtDateTime(r.issueDate, r)}</TableCell>
                              <TableCell className={r.isOverdue ? "text-rose-700 font-medium" : ""}>
                                {r.dueDate ?? "—"}
                              </TableCell>
                              {hasSubscriptions && (
                                <TableCell className="whitespace-nowrap text-xs text-slate-600">
                                  {r.billingPeriod || "—"}
                                </TableCell>
                              )}
                              <TableCell className="text-right">{fmt(r.totalAmount)}</TableCell>
                              <TableCell className="text-right text-emerald-700">{fmt(r.amountPaid)}</TableCell>
                              <TableCell className="text-right">
                                <span className={r.balance > 0 ? "text-rose-700 font-semibold" : ""}>
                                  {fmt(r.balance)}
                                </span>
                              </TableCell>
                              <TableCell>{statusCell(r)}</TableCell>
                              <TableCell className="text-right whitespace-nowrap">
                                <Tooltip>
                                  <TooltipTrigger asChild>
                                    <Button asChild variant="ghost" size="sm" aria-label="View invoice">
                                      <Link href={rowLink(r)}><Eye className="h-4 w-4" /></Link>
                                    </Button>
                                  </TooltipTrigger>
                                  <TooltipContent side="top">View invoice</TooltipContent>
                                </Tooltip>
                                {r.type === "subscription" && r.documentStatus === "Draft" && (
                                  <Tooltip>
                                    <TooltipTrigger asChild>
                                      <Button
                                        variant="ghost"
                                        size="sm"
                                        className="text-emerald-700"
                                        disabled={approving === r.saleId}
                                        onClick={() => onApprove(r)}
                                        aria-label="Approve"
                                      >
                                        {approving === r.saleId
                                          ? <Loader2 className="h-4 w-4 animate-spin" />
                                          : <Check className="h-4 w-4" />}
                                      </Button>
                                    </TooltipTrigger>
                                    <TooltipContent side="top">Approve invoice</TooltipContent>
                                  </Tooltip>
                                )}
                              </TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                      <DataPagination {...pg.paginationProps} />
                    </div>
                  }
                />
              </CardContent>
            </Card>
          )}
        </main>
      </div>
    </div>
  )
}
