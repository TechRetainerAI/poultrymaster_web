"use client"

export const dynamic = "force-dynamic"

import { Suspense, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter, useSearchParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { Loader2, Plus, ShoppingCart, AlertCircle, ArrowLeft, Eye, Undo2, RotateCcw, FileText } from "lucide-react"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { useGenericModules } from "@/hooks/use-generic-modules"
// 483: a sale is reversed from the list too, with the same dialog as Poultry / Water.
import { ReverseSaleDialog } from "@/components/sales/reverse-sale-dialog"
import { getUserContext } from "@/lib/api/config"
import { getSelectedCurrency } from "@/lib/utils/currency"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { getSales, type GenericSale } from "@/lib/api/generic"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { fmtDateTime } from "@/lib/utils/company-datetime"
import { ProjectFilter } from "@/components/generic/projects/project-filter"
import { useProjectLabels } from "@/hooks/use-project-labels"
import { ALL_PROJECTS, type ProjectFilterValue } from "@/lib/generic/project-math"

// "Reversed" (484) = reversed sales; "Cancelled" = cancelled drafts, not reversals.
const STATUS_FILTERS = ["All", "Draft", "Approved", "Reversed", "Refunded", "Cancelled"] as const

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}

function displayCustomer(s: GenericSale): string {
  if (s.customerName) return s.customerName
  if (s.notes?.startsWith("Customer: ")) {
    const pipe = s.notes.indexOf(" | ")
    return pipe > 0 ? s.notes.slice(10, pipe) : s.notes.slice(10)
  }
  return "Walk-in"
}

/** A reversed sale is stored as "Cancelled" + a reversal (483); show it as "Reversed". */
const shownStatus = (s: GenericSale) => (s.saleReversalId ? "Reversed" : s.status)

function statusBadgeClass(s: string) {
  switch (s) {
    case "Reversed":  return "bg-slate-200 text-slate-800 hover:bg-slate-200"
    case "Approved":  return "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"
    case "Cancelled": return "bg-rose-100 text-rose-800 hover:bg-rose-100"
    case "Refunded":  return "bg-amber-100 text-amber-800 hover:bg-amber-100"
    default:          return "bg-slate-100 text-slate-800 hover:bg-slate-100"
  }
}

function paymentBadgeClass(s: string) {
  switch (s) {
    case "Paid":           return "bg-emerald-50 text-emerald-700 hover:bg-emerald-50"
    case "PartiallyPaid":  return "bg-amber-50 text-amber-700 hover:bg-amber-50"
    case "Unpaid":         return "bg-rose-50 text-rose-700 hover:bg-rose-50"
    case "Overdue":        return "bg-red-100 text-red-800 hover:bg-red-100"
    default:               return "bg-slate-50 text-slate-600 hover:bg-slate-50"
  }
}

function GenericSalesPageInner() {
  const router = useRouter()
  const sp = useSearchParams()
  const status = sp.get("status") || "All"
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const [rows, setRows] = useState<GenericSale[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [loading, setLoading] = useState(true)
  // 483/485: Reverse, or Correct (reverse, then New sale filled in from it).
  const [reverseTarget, setReverseTarget] = useState<{ sale: GenericSale; mode: "reverse" | "correct" } | null>(null)
  /** Edit & repost: New sale filled in from a reversed sale, linked to it. */
  const repost = (saleId: number) => router.push(`/generic-sales/new?corrects=${saleId}`)
  /** A reversed sale nothing has replaced yet (a cancelled correcting draft does not count). */
  const canRepost = (s: GenericSale) => !!s.saleReversalId && !s.correctedBySaleId
  // Bumped after a reversal so the list reloads with the sale's new status.
  const [reloadKey, setReloadKey] = useState(0)
  const { showNew } = useGenericModules()
  const invoicingEnabled = showNew("enableInvoices")

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    let cancelled = false
    ;(async () => {
      try {
        const data = await getSales(status === "All" ? null : status)
        if (!cancelled) setRows(data)
      } catch (e: any) {
        if (!cancelled) toast({ title: "Could not load sales", description: e?.message ?? String(e), variant: "destructive" })
      } finally { if (!cancelled) setLoading(false) }
    })()
    return () => { cancelled = true }
  }, [activeFarmType, router, status, toast, reloadKey])

  // 483: Project / Contract filter (hidden unless the module is on).
  const [projectFilter, setProjectFilter] = useState<ProjectFilterValue>(ALL_PROJECTS)
  const projectLabels = useProjectLabels("Sale", rows)
  const visibleRows = useMemo(
    () => filterByDateAndSearch(rows, {
      search, dateFrom, dateTo,
      searchKeys: ["customerName", "status", "notes"],
      dateKey: "saleDate",
    }).filter((s) => projectLabels.matches(s.genericSaleId, projectFilter)),
    [rows, search, dateFrom, dateTo, projectLabels, projectFilter],
  )

  // Accounts receivable summary — total outstanding across all approved sales
  const creditSummary = useMemo(() => {
    let totalSales = 0, totalPaid = 0, totalOutstanding = 0, creditCount = 0
    for (const s of rows) {
      if (s.status === "Approved" || s.status === "Draft") {
        totalSales += s.totalAmount
        totalPaid += s.amountPaid
        if (s.balance > 0) { totalOutstanding += s.balance; creditCount++ }
      }
    }
    return { totalSales, totalPaid, totalOutstanding, creditCount }
  }, [rows])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center justify-between flex-wrap gap-2">
            <div>
              <button onClick={() => router.back()} className="rounded-full p-1 hover:bg-slate-200 transition" title="Go back"><ArrowLeft className="w-5 h-5 text-slate-600" /></button>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <ShoppingCart className="h-6 w-6 text-emerald-600" /> Sales
              </h1>
              <p className="text-sm text-slate-500">{rows.length} {status === "All" ? "" : status.toLowerCase()} sale(s)</p>
            </div>
            <Button asChild className="w-full sm:w-auto h-11 sm:h-10">
              <Link href="/generic-sales/new"><Plus className="h-4 w-4 mr-1" />New sale</Link>
            </Button>
          </div>

          {/* Accounts receivable summary */}
          {!loading && creditSummary.creditCount > 0 && (
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4">
              <Card><CardContent className="py-3 px-4"><div className="text-xs text-slate-500">Total sales</div><div className="text-lg font-semibold">{fmt(creditSummary.totalSales)}</div></CardContent></Card>
              <Card><CardContent className="py-3 px-4"><div className="text-xs text-slate-500">Total received</div><div className="text-lg font-semibold text-emerald-700">{fmt(creditSummary.totalPaid)}</div></CardContent></Card>
              <Card><CardContent className="py-3 px-4"><div className="text-xs text-slate-500">Outstanding (A/R)</div><div className="text-lg font-semibold text-rose-700">{fmt(creditSummary.totalOutstanding)}</div></CardContent></Card>
              <Card><CardContent className="py-3 px-4"><div className="text-xs text-slate-500">Unpaid invoices</div><div className="text-lg font-semibold">{creditSummary.creditCount}</div></CardContent></Card>
            </div>
          )}

          <div className="flex gap-1 mb-3 flex-wrap">
            {STATUS_FILTERS.map((s) => (
              <Button
                key={s}
                size="sm"
                variant={s === status ? "default" : "outline"}
                onClick={() => router.replace(s === "All" ? "/generic-sales" : `/generic-sales?status=${s}`)}
              >
                {s}
              </Button>
            ))}
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading...</div>
          ) : rows.length === 0 ? (
            <Card><CardContent className="py-8 text-center text-slate-500">No sales yet. <Link href="/generic-sales/new" className="text-emerald-700 underline">Record your first one â†’</Link></CardContent></Card>
          ) : (
            <>
            <ListFilters
              search={search} setSearch={setSearch}
              dateFrom={dateFrom} setDateFrom={setDateFrom}
              dateTo={dateTo} setDateTo={setDateTo}
              searchPlaceholder="Search customer, status or notes"
              extras={<ProjectFilter value={projectFilter} onChange={setProjectFilter} />}
            />
            <Card>
              <CardContent className="p-0">
                <MobileCardList
                  items={visibleRows}
                  getKey={(s) => s.genericSaleId}
                  primary={(s) => (
                    <Link href={`/generic-sales/${s.genericSaleId}`} className="text-emerald-700 underline">
                      #{s.genericSaleId} · {displayCustomer(s)}
                    </Link>
                  )}
                  secondary={(s) => (
                    <>
                      <span>{fmtDateTime(s.saleDate, s)}</span>
                      <span>·</span>
                      <span className="text-xs">{s.salesType}</span>
                    </>
                  )}
                  trailing={(s) => <Badge className={statusBadgeClass(shownStatus(s))}>{shownStatus(s)}</Badge>}
                  details={(s) => [
                    { label: "Date", value: fmtDateTime(s.saleDate, s) },
                    { label: "Customer", value: displayCustomer(s) },
                    { label: "Type", value: s.salesType },
                    { label: "Total", value: fmt(s.totalAmount) },
                    { label: "Paid", value: fmt(s.amountPaid) },
                    { label: "Balance", value: <span className={s.balance > 0 ? "text-rose-700 font-semibold" : ""}>{fmt(s.balance)}</span> },
                    ...(s.paymentStatus ? [{ label: "Payment", value: <Badge className={paymentBadgeClass(s.paymentStatus)}>{s.paymentStatus}</Badge> }] : []),
                  ]}
                  actions={(s) => (
                    <>
                      <Button asChild size="sm" variant="outline" className="flex-1 h-10">
                        <Link href={`/generic-sales/${s.genericSaleId}`}><Eye className="h-4 w-4 mr-1" />View</Link>
                      </Button>
                      {s.status === "Approved" && (
                        <>
                          <Button size="sm" variant="outline" className="flex-1 h-10 text-blue-700" onClick={() => setReverseTarget({ sale: s, mode: "correct" })}>
                            <RotateCcw className="h-4 w-4 mr-1" />Correct
                          </Button>
                          <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 hover:text-red-700" onClick={() => setReverseTarget({ sale: s, mode: "reverse" })}>
                            <Undo2 className="h-4 w-4 mr-1" />Reverse
                          </Button>
                        </>
                      )}
                      {canRepost(s) && (
                        <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => repost(s.genericSaleId)}>
                          <RotateCcw className="h-4 w-4 mr-1" />Edit &amp; repost
                        </Button>
                      )}
                    </>
                  )}
                  desktopTable={
                    <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>#</TableHead>
                          <TableHead>Date</TableHead>
                          <TableHead>Customer</TableHead>
                          <TableHead>Type</TableHead>
                          <TableHead className="text-right">Total</TableHead>
                          <TableHead className="text-right">Paid</TableHead>
                          <TableHead className="text-right">Balance</TableHead>
                          <TableHead>Payment</TableHead>
                          <TableHead>Status</TableHead>
                          <TableHead className="text-right">Actions</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {visibleRows.map((s) => (
                          <TableRow key={s.genericSaleId}>
                            <TableCell><Link href={`/generic-sales/${s.genericSaleId}`} className="text-emerald-700 underline">#{s.genericSaleId}</Link>{projectLabels.labelOf(s.genericSaleId) && <div className="text-[11px] text-indigo-700">{projectLabels.labelOf(s.genericSaleId)}</div>}</TableCell>
                            <TableCell>{fmtDateTime(s.saleDate, s)}</TableCell>
                            <TableCell>{s.customerName ? s.customerName : <span className="text-slate-500">{displayCustomer(s)}</span>}</TableCell>
                            <TableCell className="text-xs text-slate-500">{s.salesType}</TableCell>
                            <TableCell className="text-right">{fmt(s.totalAmount)}</TableCell>
                            <TableCell className="text-right">{fmt(s.amountPaid)}</TableCell>
                            <TableCell className={`text-right ${s.balance > 0 ? "text-rose-700 font-semibold" : ""}`}>{fmt(s.balance)}</TableCell>
                            <TableCell>{s.paymentStatus && <Badge className={paymentBadgeClass(s.paymentStatus)}>{s.paymentStatus}</Badge>}</TableCell>
                            <TableCell>
                              <Badge className={statusBadgeClass(shownStatus(s))}>{shownStatus(s)}</Badge>
                              {s.correctedBySaleId && (
                                <Link href={`/generic-sales/${s.correctedBySaleId}`} className="block text-[11px] text-blue-700 hover:underline">Corrected by #{s.correctedBySaleId}</Link>
                              )}
                              {s.correctsSaleId && (
                                <Link href={`/generic-sales/${s.correctsSaleId}`} className="block text-[11px] text-slate-500 hover:underline">Corrects #{s.correctsSaleId}</Link>
                              )}
                            </TableCell>
                            <TableCell className="text-right whitespace-nowrap">
                              <Tooltip>
                                <TooltipTrigger asChild>
                                  <Button asChild variant="ghost" size="sm" aria-label="View sale">
                                    <Link href={`/generic-sales/${s.genericSaleId}`}><Eye className="h-4 w-4" /></Link>
                                  </Button>
                                </TooltipTrigger>
                                <TooltipContent side="top">View sale</TooltipContent>
                              </Tooltip>
                              {invoicingEnabled && s.status === "Approved" && !s.saleReversalId && (
                                <Tooltip>
                                  <TooltipTrigger asChild>
                                    <Button asChild variant="ghost" size="sm" className="text-indigo-700 hover:text-indigo-800 hover:bg-indigo-50" aria-label="Invoice">
                                      <Link href={`/generic-sales/${s.genericSaleId}`}><FileText className="h-4 w-4" /></Link>
                                    </Button>
                                  </TooltipTrigger>
                                  <TooltipContent side="top">Generate or view invoice</TooltipContent>
                                </Tooltip>
                              )}
                              {s.status === "Approved" && (
                                <>
                                  <Tooltip>
                                    <TooltipTrigger asChild>
                                      <Button
                                        variant="ghost"
                                        size="sm"
                                        className="text-blue-700 hover:text-blue-800 hover:bg-blue-50"
                                        onClick={() => setReverseTarget({ sale: s, mode: "correct" })}
                                        aria-label="Correct sale"
                                      >
                                        <RotateCcw className="h-4 w-4" />
                                      </Button>
                                    </TooltipTrigger>
                                    <TooltipContent side="top">Correct sale (reverse it and enter it again)</TooltipContent>
                                  </Tooltip>
                                  <Tooltip>
                                    <TooltipTrigger asChild>
                                      <Button
                                        variant="ghost"
                                        size="sm"
                                        className="text-red-600 hover:text-red-700 hover:bg-red-50"
                                        onClick={() => setReverseTarget({ sale: s, mode: "reverse" })}
                                        aria-label="Reverse sale"
                                      >
                                        <Undo2 className="h-4 w-4" />
                                      </Button>
                                    </TooltipTrigger>
                                    <TooltipContent side="top">Reverse sale</TooltipContent>
                                  </Tooltip>
                                </>
                              )}
                              {canRepost(s) && (
                                <Button size="sm" variant="outline" className="h-8 ml-1" onClick={() => repost(s.genericSaleId)} title="Enter this sale again, corrected">
                                  <RotateCcw className="h-4 w-4 mr-1" />Edit &amp; repost
                                </Button>
                              )}
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                    </div>
                  }
                />
              </CardContent>
            </Card>
            </>
          )}

          <ReverseSaleDialog
            open={!!reverseTarget}
            module="generic"
            mode={reverseTarget?.mode ?? "reverse"}
            saleId={reverseTarget ? reverseTarget.sale.genericSaleId : null}
            saleLabel={reverseTarget ? `#${reverseTarget.sale.genericSaleId}` : ""}
            farmId={getUserContext().farmId}
            userId={getUserContext().userId}
            currencyCode={getSelectedCurrency()}
            onOpenChange={(o) => { if (!o) setReverseTarget(null) }}
            onReversed={({ reversal: r }) => {
              const id = reverseTarget?.sale.genericSaleId
              const correcting = reverseTarget?.mode === "correct"
              setReverseTarget(null)
              // Correct: the sale is reversed; now enter it again, filled in.
              if (correcting && id) { repost(id); return }
              toast({
                title: `Sale #${id} reversed${r?.reversalNumber ? ` (${r.reversalNumber})` : ""}`,
                description: r
                  ? [r.cashReversed > 0 ? `${fmt(r.cashReversed)} paid back` : "", r.creditCreated > 0 ? `${fmt(r.creditCreated)} kept as credit` : ""]
                      .filter(Boolean).join(" · ") || "Stock put back; nothing had been paid."
                  : undefined,
              })
              setReloadKey((k) => k + 1)
            }}
          />
        </main>
      </div>
    </div>
  )
}

export default function GenericSalesPage() {
  return (
    <Suspense fallback={<div className="p-6 text-slate-500">Loading...</div>}>
      <GenericSalesPageInner />
    </Suspense>
  )
}
