"use client"

// Invoices — everything this company has billed, and who still owes it.
//
// An invoice IS a sale. There is no separate invoice table: subscription
// billing writes genericsales rows with a due date, a subscription link and a
// billing period, so an invoice a billing run raised and a counter sale that is
// still owed sit in the same list and settle through the same payment.
//
// Creating and cancelling still live on the Sales page, which owns the row.
// What this page adds is the invoice lens: due dates, overdue, and Approve —
// the step that turns a draft into money someone owes.

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
import { Loader2, FileText, Check, AlertTriangle } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  getInvoices, getBusinessTemplate, type GenericInvoiceRow,
} from "@/lib/api/generic-subscriptions"
import { approveSale } from "@/lib/api/generic"
import { templateLabels } from "@/lib/generic/template-labels"

const STATUS_STYLES: Record<string, string> = {
  Draft: "bg-slate-100 text-slate-600 hover:bg-slate-100",
  Approved: "bg-emerald-100 text-emerald-800 hover:bg-emerald-100",
  Cancelled: "bg-slate-200 text-slate-700 hover:bg-slate-200",
  Refunded: "bg-amber-100 text-amber-800 hover:bg-amber-100",
}

export default function GenericInvoicesPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  const [rows, setRows] = useState<GenericInvoiceRow[]>([])
  const [industry, setIndustry] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [approving, setApproving] = useState<number | null>(null)
  const [search, setSearch] = useState("")
  const [statusFilter, setStatusFilter] = useState("All")
  const [subsOnly, setSubsOnly] = useState(false)

  const labels = templateLabels(industry)

  const load = async () => {
    setLoading(true)
    try {
      const [invoices, template] = await Promise.all([
        getInvoices({ status: statusFilter, subscriptionOnly: subsOnly }),
        getBusinessTemplate().catch(() => null),
      ])
      setRows(invoices)
      setIndustry(template?.genericIndustryTemplate ?? null)
    } catch (e: any) {
      toast({
        title: "Could not load invoices",
        description: e?.message ?? String(e),
        variant: "destructive",
      })
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") {
      router.replace("/dashboard")
      return
    }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router, statusFilter, subsOnly])

  const visible = useMemo(
    () =>
      filterByDateAndSearch(rows, {
        search,
        searchKeys: ["receiptNumber", "customerName", "subscriptionNumber"],
      }),
    [rows, search],
  )
  const pg = usePagination(visible)

  const totals = useMemo(
    () => ({
      drafts: rows.filter((r) => r.status === "Draft").length,
      owed: rows.filter((r) => r.status === "Approved").reduce((s, r) => s + r.balance, 0),
      overdue: rows.filter((r) => r.isOverdue).reduce((s, r) => s + r.balance, 0),
    }),
    [rows],
  )

  const onApprove = async (inv: GenericInvoiceRow) => {
    setApproving(inv.genericSaleId)
    try {
      await approveSale(inv.genericSaleId)
      toast({
        title: `${inv.receiptNumber ?? labels.invoice} approved.`,
        description: `${fmt(inv.totalAmount)} is now owed by ${inv.customerName ?? `#${inv.genericCustomerId}`}.`,
      })
      await load()
    } catch (e: any) {
      toast({
        title: "Could not approve",
        description: e?.message ?? String(e),
        variant: "destructive",
      })
    } finally {
      setApproving(null)
    }
  }

  const statusCell = (inv: GenericInvoiceRow) => (
    <div className="flex items-center gap-1">
      <Badge className={STATUS_STYLES[inv.status] ?? "bg-slate-100 text-slate-600"}>
        {inv.status}
      </Badge>
      {inv.isOverdue && (
        <Badge className="bg-rose-100 text-rose-800 hover:bg-rose-100">
          <AlertTriangle className="h-3 w-3 mr-1" /> Overdue
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
          <div className="mb-4 flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <FileText className="h-6 w-6 text-indigo-600" /> {labels.invoicePlural}
              </h1>
              <p className="text-sm text-slate-500">
                {totals.drafts} draft · {fmt(totals.owed)} owed
                {totals.overdue > 0 && (
                  <span className="text-rose-700"> · {fmt(totals.overdue)} overdue</span>
                )}
              </p>
            </div>
            <div className="flex gap-2">
              <Link href="/generic-billing-runs">
                <Button variant="outline" className="h-11 sm:h-10">Billing runs</Button>
              </Link>
              <Link href="/generic-customer-balances">
                <Button variant="outline" className="h-11 sm:h-10">{labels.customerBalance}</Button>
              </Link>
            </div>
          </div>

          <div className="flex flex-wrap items-end gap-3 mb-3">
            <div className="flex-1 min-w-[220px]">
              <ListFilters
                search={search}
                setSearch={setSearch}
                searchOnly
                searchPlaceholder={`Search number or ${labels.customer.toLowerCase()}`}
              />
            </div>
            <Select value={statusFilter} onValueChange={setStatusFilter}>
              <SelectTrigger className="w-[160px]">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {["All", "Draft", "Approved", "Cancelled", "Refunded"].map((s) => (
                  <SelectItem key={s} value={s}>
                    {s}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <div className="flex items-center gap-2 h-10">
              <Checkbox
                id="subsOnly"
                checked={subsOnly}
                onCheckedChange={(v) => setSubsOnly(v === true)}
              />
              <Label htmlFor="subsOnly" className="cursor-pointer">
                From {labels.subscriptionPlural.toLowerCase()} only
              </Label>
            </div>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500">
              <Loader2 className="h-4 w-4 animate-spin" /> Loading…
            </div>
          ) : rows.length === 0 ? (
            <Card>
              <CardContent className="py-8 text-center text-slate-500">
                No {labels.invoicePlural.toLowerCase()} here yet. A billing run raises them from{" "}
                {labels.subscriptionPlural.toLowerCase()}.
              </CardContent>
            </Card>
          ) : (
            <Card>
              <CardContent className="p-0">
                <MobileCardList
                  items={pg.pageItems}
                  getKey={(i) => i.genericSaleId}
                  primary={(i) => i.receiptNumber ?? `#${i.genericSaleId}`}
                  secondary={(i) => (
                    <>
                      <span>{i.customerName ?? "—"}</span>
                      <span> · {fmt(i.totalAmount)}</span>
                    </>
                  )}
                  trailing={(i) => statusCell(i)}
                  details={(i) => [
                    { label: "Date", value: new Date(i.saleDate).toLocaleDateString() },
                    { label: "Due", value: i.dueDate ?? "—" },
                    {
                      label: "Period",
                      value:
                        i.billingPeriodStart && i.billingPeriodEnd
                          ? `${i.billingPeriodStart} → ${i.billingPeriodEnd}`
                          : "—",
                    },
                    { label: "Paid", value: fmt(i.amountPaid) },
                    {
                      label: "Balance",
                      value: (
                        <span className={i.balance > 0 ? "text-rose-700 font-semibold" : ""}>
                          {fmt(i.balance)}
                        </span>
                      ),
                    },
                  ]}
                  actions={(i) =>
                    i.status === "Draft" ? (
                      <Button
                        size="sm"
                        className="flex-1 h-10"
                        disabled={approving === i.genericSaleId}
                        onClick={() => onApprove(i)}
                      >
                        {approving === i.genericSaleId ? (
                          <Loader2 className="h-4 w-4 mr-1 animate-spin" />
                        ) : (
                          <Check className="h-4 w-4 mr-1" />
                        )}
                        Approve
                      </Button>
                    ) : null
                  }
                  pagination={pg.paginationProps}
                  desktopTable={
                    <div className="overflow-x-auto">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Number</TableHead>
                            <TableHead>{labels.customer}</TableHead>
                            <TableHead>Date</TableHead>
                            <TableHead>Period</TableHead>
                            <TableHead>Due</TableHead>
                            <TableHead className="text-right">Total</TableHead>
                            <TableHead className="text-right">Balance</TableHead>
                            <TableHead>Status</TableHead>
                            <TableHead />
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {pg.pageItems.map((i) => (
                            <TableRow key={i.genericSaleId}>
                              <TableCell className="font-mono text-xs">
                                {i.receiptNumber ?? `#${i.genericSaleId}`}
                              </TableCell>
                              <TableCell className="font-medium">{i.customerName ?? "—"}</TableCell>
                              <TableCell>{new Date(i.saleDate).toLocaleDateString()}</TableCell>
                              <TableCell className="whitespace-nowrap text-xs text-slate-600">
                                {i.billingPeriodStart && i.billingPeriodEnd
                                  ? `${i.billingPeriodStart} → ${i.billingPeriodEnd}`
                                  : "—"}
                              </TableCell>
                              <TableCell className={i.isOverdue ? "text-rose-700 font-medium" : ""}>
                                {i.dueDate ?? "—"}
                              </TableCell>
                              <TableCell className="text-right">{fmt(i.totalAmount)}</TableCell>
                              <TableCell className="text-right">
                                <span className={i.balance > 0 ? "text-rose-700 font-semibold" : ""}>
                                  {fmt(i.balance)}
                                </span>
                              </TableCell>
                              <TableCell>{statusCell(i)}</TableCell>
                              <TableCell className="text-right">
                                {i.status === "Draft" && (
                                  <Button
                                    size="sm"
                                    disabled={approving === i.genericSaleId}
                                    onClick={() => onApprove(i)}
                                  >
                                    {approving === i.genericSaleId ? (
                                      <Loader2 className="h-4 w-4 mr-1 animate-spin" />
                                    ) : (
                                      <Check className="h-4 w-4 mr-1" />
                                    )}
                                    Approve
                                  </Button>
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
