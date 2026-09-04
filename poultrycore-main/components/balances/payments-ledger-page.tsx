"use client"

// The Supplier Payments ledger.
//
// One row per REAL PAYMENT. That is the whole point of the page: a single
// GHC 1,000,000 payment spread across two purchases is one thing that happened
// at the bank, and it is shown as one line — not two, and not one line per
// allocation. Supplier Balances answers "who do we owe"; this answers "what did
// we actually pay, out of which account, and against what".
//
// The expand/inline rule (spec §32) is deliberate and worth stating:
//
//   allocationCount === 1  the allocation IS the payment, so its payable number,
//                          total and before/applied/after sit directly on the
//                          row. Making the user expand a row to see one line
//                          would be a click that never tells them anything new.
//   allocationCount  > 1   there is no single payable to name, so those columns
//                          read "Multiple" / "—" and the row expands.
//
// Built on the same module/side props as BalancesPage, so poultry and water are
// two thin route wrappers rather than two copies of this file.

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
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { PERIOD_GROUPS, periodToRange, rangeToPeriod } from "@/lib/date-ranges"
import {
  ChevronDown, ChevronRight, Download, ExternalLink, FileText,
  Loader2, Receipt, Undo2,
} from "lucide-react"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { useFmt } from "@/lib/currency"
import { useAuthStore } from "@/lib/store/auth-store"
import { exportTableToPdf } from "@/lib/utils/pdf-export"
import { downloadCsv } from "@/lib/utils/download-csv"
import {
  getPayment, listPayments, reversePayment,
  type BalanceModule, type PaymentAllocationRow, type PaymentHistoryRow,
} from "@/lib/api/balances"

/** Where a payment was entered from. Matches the sourcetype values the SPs write. */
const SOURCE_FILTERS = [
  "SupplierBalances",
  "PurchaseEntry",
  "ExpenseEntry",
  "SupplierPaymentsPage",
] as const

const PAYABLE_TYPE_LABELS: Record<string, string> = {
  RawMaterialPurchase: "Purchase",
  FlockBatch: "Flock batch",
  Expense: "Expense",
  Purchase: "Purchase",
}

export function payableTypeLabel(t: string | null | undefined): string {
  const s = (t ?? "").trim()
  if (!s) return "—"
  return PAYABLE_TYPE_LABELS[s] ?? s
}

export interface PaymentsLedgerPageProps {
  module: BalanceModule
  /** Company type this page belongs to; other types are redirected away. */
  companyType: "Poultry" | "Water" | "Generic"
  /** Route to a supplier's profile. */
  partyHref: (partyId: number) => string
  /** Route to a payable document, or null when it has no page of its own. */
  documentHref: (allocation: Pick<PaymentAllocationRow, "documentType" | "documentId">) => string | null
  /** Names for the cash accounts payments were made from. */
  loadCashAccounts: () => Promise<{ id: number; name: string }[]>
  permissions: { view: string; reverse: string }
}

export function PaymentsLedgerPage({
  module, companyType, partyHref, documentHref, loadCashAccounts, permissions,
}: PaymentsLedgerPageProps) {
  const fmt = useFmt()
  const router = useRouter()
  const { toast } = useToast()
  const logout = useLogout()
  const { can, isLoading: permsLoading } = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [rows, setRows] = useState<PaymentHistoryRow[]>([])
  const [loading, setLoading] = useState(true)
  const [accounts, setAccounts] = useState<{ id: number; name: string }[]>([])

  // paymentId -> its allocations. Filled lazily: on expand for a multi-item
  // payment, and eagerly for the single-item payments on the CURRENT PAGE so
  // their inline columns can be filled. Bounded by the page size, and cached, so
  // a farm with 2,000 payments does not make 2,000 requests.
  const [allocations, setAllocations] = useState<Record<string, PaymentAllocationRow[]>>({})
  const [expanded, setExpanded] = useState<string | null>(null)

  const [reversing, setReversing] = useState<string | null>(null)
  const [reason, setReason] = useState("")

  const [search, setSearch] = useState("")
  const [period, setPeriod] = useState("all")
  const [from, setFrom] = useState("")
  const [to, setTo] = useState("")
  const [supplierFilter, setSupplierFilter] = useState("all")
  const [methodFilter, setMethodFilter] = useState("all")
  const [accountFilter, setAccountFilter] = useState("all")
  const [sourceFilter, setSourceFilter] = useState("all")
  const [statusFilter, setStatusFilter] = useState("all")
  const [appliedToFilter, setAppliedToFilter] = useState("all")
  const [payableTypeFilter, setPayableTypeFilter] = useState("all")
  const [minAmount, setMinAmount] = useState("")
  const [maxAmount, setMaxAmount] = useState("")

  const canView = can(permissions.view)
  const canReverse = can(permissions.reverse)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      // Only the date range goes to the server — it is the only filter the
      // history SP takes, and it is the one that actually bounds the result set.
      // Everything else is applied below over rows already in hand, which is how
      // BalancesPage filters payment method too.
      const list = await listPayments(module, "supplier", { from: from || null, to: to || null })
      setRows(list)
      // Allocations belong to payments; a refetch must not leave stale ones behind.
      setAllocations({})
      setExpanded(null)
    } catch (e: any) {
      toast({ title: "Could not load payments", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setLoading(false)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [module, from, to])

  useEffect(() => { void load() }, [load])

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const list = await loadCashAccounts()
        if (!cancelled) setAccounts(list)
      } catch {
        if (!cancelled) setAccounts([])
      }
    })()
    return () => { cancelled = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [module])

  const accountName = useCallback(
    (id?: number | null) => (id ? (accounts.find((a) => a.id === id)?.name ?? `Account #${id}`) : "—"),
    [accounts],
  )

  // Options come from the whole loaded set, not the filtered view: options that
  // disappear as you filter make the filter impossible to change your mind about.
  const supplierOptions = useMemo(() => {
    const seen = new Map<number, string>()
    for (const r of rows) if (r.partyId) seen.set(r.partyId, r.partyName ?? `Supplier #${r.partyId}`)
    return [...seen].map(([id, name]) => ({ id, name })).sort((a, b) => a.name.localeCompare(b.name))
  }, [rows])

  const methodOptions = useMemo(
    () => [...new Set(rows.map((r) => (r.paymentMethod ?? "").trim()).filter(Boolean))].sort(),
    [rows],
  )

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase()
    const min = minAmount.trim() === "" ? null : Number(minAmount)
    const max = maxAmount.trim() === "" ? null : Number(maxAmount)

    return rows.filter((r) => {
      if (supplierFilter !== "all" && String(r.partyId ?? "") !== supplierFilter) return false
      if (methodFilter !== "all" && (r.paymentMethod ?? "") !== methodFilter) return false
      if (accountFilter !== "all" && String(r.cashAccountId ?? "") !== accountFilter) return false
      if (sourceFilter !== "all" && (r.sourceType ?? "") !== sourceFilter) return false
      if (statusFilter !== "all" && r.status !== statusFilter) return false
      if (appliedToFilter === "single" && r.allocationCount !== 1) return false
      if (appliedToFilter === "multiple" && r.allocationCount <= 1) return false
      if (min !== null && !Number.isNaN(min) && r.totalAmount < min) return false
      if (max !== null && !Number.isNaN(max) && r.totalAmount > max) return false

      // Payable type can only be judged once the allocation is known. A row whose
      // allocation has not been fetched is KEPT rather than hidden — filtering a
      // row out because we have not looked at it yet would silently change the
      // totals as the page loads.
      if (payableTypeFilter !== "all") {
        const allocs = allocations[r.paymentId]
        if (allocs && !allocs.some((a) => a.documentType === payableTypeFilter)) return false
      }

      if (q) {
        const allocs = allocations[r.paymentId] ?? []
        const hay = [
          r.partyName, r.reference, r.notes, r.sourceType, r.paymentId,
          ...allocs.map((a) => a.reference), ...allocs.map((a) => a.label),
        ]
          .filter(Boolean)
          .join(" ")
          .toLowerCase()
        if (!hay.includes(q)) return false
      }
      return true
    })
  }, [
    rows, search, supplierFilter, methodFilter, accountFilter, sourceFilter,
    statusFilter, appliedToFilter, payableTypeFilter, minAmount, maxAmount, allocations,
  ])

  const pg = usePagination(filtered, 10)

  // Fill in the inline allocation columns for the single-item payments on this
  // page. One small request each, once per payment for the life of the page.
  useEffect(() => {
    const wanted = pg.pageItems.filter((r) => r.allocationCount === 1 && !allocations[r.paymentId])
    if (wanted.length === 0) return
    let cancelled = false
    ;(async () => {
      const results = await Promise.all(
        wanted.map(async (r) => {
          try {
            const detail = await getPayment(module, "supplier", r.paymentId)
            return [r.paymentId, detail.allocations] as const
          } catch {
            // A row whose allocation will not load still shows its payment
            // columns; the inline detail just stays blank.
            return [r.paymentId, [] as PaymentAllocationRow[]] as const
          }
        }),
      )
      if (cancelled) return
      setAllocations((prev) => {
        const next = { ...prev }
        for (const [id, allocs] of results) next[id] = allocs
        return next
      })
    })()
    return () => { cancelled = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pg.pageItems, module])

  const toggle = async (row: PaymentHistoryRow) => {
    if (expanded === row.paymentId) { setExpanded(null); return }
    setExpanded(row.paymentId)
    if (allocations[row.paymentId]) return
    try {
      const detail = await getPayment(module, "supplier", row.paymentId)
      setAllocations((prev) => ({ ...prev, [row.paymentId]: detail.allocations }))
    } catch (e: any) {
      toast({ title: "Could not load allocation", description: e?.message ?? String(e), variant: "destructive" })
    }
  }

  /** The one allocation behind a single-item payment, if we have it yet. */
  const soleAllocation = (row: PaymentHistoryRow): PaymentAllocationRow | null => {
    if (row.allocationCount !== 1) return null
    const allocs = allocations[row.paymentId]
    return allocs && allocs.length === 1 ? allocs[0] : null
  }

  const doReverse = async (row: PaymentHistoryRow) => {
    if (!reason.trim()) {
      toast({
        title: "A reason is required",
        description: "Say why this payment is being reversed — it is written to the audit trail.",
        variant: "destructive",
      })
      return
    }
    try {
      await reversePayment(module, "supplier", row.paymentId, reason.trim())
      toast({ title: "Payment reversed", description: `${fmt(row.totalAmount)} put back on the balance.` })
      setReversing(null)
      setReason("")
      await load()
    } catch (e: any) {
      toast({ title: "Could not reverse payment", description: e?.message ?? String(e), variant: "destructive" })
    }
  }

  const resetFilters = () => {
    setSearch(""); setPeriod("all"); setFrom(""); setTo("")
    setSupplierFilter("all"); setMethodFilter("all"); setAccountFilter("all")
    setSourceFilter("all"); setStatusFilter("all"); setAppliedToFilter("all")
    setPayableTypeFilter("all"); setMinAmount(""); setMaxAmount("")
  }

  const EXPORT_HEADERS = [
    "Date", "Payment #", "Supplier", "Payable #", "Payable type", "Payable total",
    "Payment amount", "Balance before", "Applied", "Balance after", "Applied to",
    "Method", "Cash account", "Reference", "Source", "Paid by", "Status",
  ]

  const exportRows = () =>
    filtered.map((r) => {
      const a = soleAllocation(r)
      const multi = r.allocationCount > 1
      return [
        new Date(r.paymentDate).toLocaleDateString(),
        r.paymentId,
        r.partyName ?? "—",
        multi ? "Multiple" : (a?.reference ?? a?.documentId ?? "—"),
        multi ? "Multiple" : payableTypeLabel(a?.documentType),
        multi ? "" : (a ? a.documentTotal.toFixed(2) : ""),
        r.totalAmount.toFixed(2),
        multi ? "" : (a ? a.balanceBefore.toFixed(2) : ""),
        multi ? r.totalAmount.toFixed(2) : (a ? a.amountApplied.toFixed(2) : ""),
        multi ? "" : (a ? a.balanceAfter.toFixed(2) : ""),
        `${r.allocationCount} item${r.allocationCount === 1 ? "" : "s"}`,
        r.paymentMethod ?? "—",
        accountName(r.cashAccountId),
        r.reference ?? "—",
        r.sourceType ?? "—",
        r.createdBy ?? "—",
        r.status,
      ]
    })

  const onExportCsv = () => downloadCsv("supplier-payments", EXPORT_HEADERS, exportRows())

  const onExportPdf = async () => {
    const posted = filtered.filter((r) => r.status === "Posted")
    await exportTableToPdf({
      title: "Supplier Payments",
      filename: "supplier-payments",
      orientation: "landscape",
      fromDate: from || undefined,
      toDate: to || undefined,
      summaryCards: [
        { label: "Payments", value: String(filtered.length) },
        { label: "Total paid", value: fmt(posted.reduce((s, r) => s + r.totalAmount, 0)), accent: "rose" },
        { label: "Reversed", value: String(filtered.filter((r) => r.status === "Reversed").length) },
      ],
      columns: EXPORT_HEADERS.map((h) => ({ header: h, dataKey: h })),
      rows: exportRows(),
    })
  }

  if (!permsLoading && !canView) {
    return (
      <div className="flex h-screen bg-slate-50">
        <DashboardSidebar onLogout={logout} />
        <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
          <DashboardHeader />
          <main className="flex-1 overflow-auto p-6">
            <Card><CardContent className="p-8 text-center text-slate-500">
              You do not have access to supplier payments.
            </CardContent></Card>
          </main>
        </div>
      </div>
    )
  }

  const postedTotal = filtered
    .filter((r) => r.status === "Posted")
    .reduce((s, r) => s + r.totalAmount, 0)

  const desktopTable = (
    <div className="overflow-x-auto">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead className="w-8" />
            <TableHead>Date</TableHead>
            <TableHead>Payment #</TableHead>
            <TableHead>Supplier</TableHead>
            <TableHead>Purchase / Expense #</TableHead>
            <TableHead>Payable type</TableHead>
            <TableHead className="text-right">Payable total</TableHead>
            <TableHead className="text-right">Payment</TableHead>
            <TableHead className="text-right">Balance before</TableHead>
            <TableHead className="text-right">Applied</TableHead>
            <TableHead className="text-right">Balance after</TableHead>
            <TableHead>Applied to</TableHead>
            <TableHead>Method</TableHead>
            <TableHead>Cash account</TableHead>
            <TableHead>Reference</TableHead>
            <TableHead>Source</TableHead>
            <TableHead>Paid by</TableHead>
            <TableHead>Status</TableHead>
            <TableHead />
          </TableRow>
        </TableHeader>
        <TableBody>
          {pg.pageItems.map((row) => {
            const isReversed = row.status === "Reversed"
            const multi = row.allocationCount > 1
            const a = soleAllocation(row)
            const isOpen = expanded === row.paymentId
            const allocs = allocations[row.paymentId]

            return (
              <Fragment key={row.paymentId}>
                <TableRow className={isReversed ? "text-slate-400" : undefined}>
                  <TableCell>
                    {multi && (
                      <button type="button" onClick={() => toggle(row)} aria-label="Show allocation">
                        {isOpen ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
                      </button>
                    )}
                  </TableCell>
                  <TableCell className="whitespace-nowrap">
                    {new Date(row.paymentDate).toLocaleDateString()}
                  </TableCell>
                  <TableCell className="font-medium whitespace-nowrap">SPAY-{row.paymentId}</TableCell>
                  <TableCell className="whitespace-nowrap">
                    {row.partyId ? (
                      <button
                        type="button"
                        className="text-sky-700 hover:underline"
                        onClick={() => router.push(partyHref(row.partyId!))}
                      >
                        {row.partyName ?? `#${row.partyId}`}
                      </button>
                    ) : (
                      <span className="text-slate-400">No supplier</span>
                    )}
                  </TableCell>

                  {/* Inline for one item, "Multiple" for many — see the header. */}
                  <TableCell className="whitespace-nowrap">
                    {multi ? <span className="text-slate-500">Multiple</span> : (a?.reference ?? (a ? `#${a.documentId}` : "—"))}
                  </TableCell>
                  <TableCell className="whitespace-nowrap">
                    {multi ? <span className="text-slate-500">Multiple</span> : payableTypeLabel(a?.documentType)}
                  </TableCell>
                  <TableCell className="text-right">{multi || !a ? "—" : fmt(a.documentTotal)}</TableCell>
                  <TableCell className={`text-right font-semibold ${isReversed ? "line-through" : ""}`}>
                    {fmt(row.totalAmount)}
                  </TableCell>
                  <TableCell className="text-right text-slate-500">
                    {multi || !a ? "—" : fmt(a.balanceBefore)}
                  </TableCell>
                  <TableCell className="text-right">
                    {multi ? fmt(row.totalAmount) : a ? fmt(a.amountApplied) : "—"}
                  </TableCell>
                  <TableCell className="text-right">{multi || !a ? "—" : fmt(a.balanceAfter)}</TableCell>
                  <TableCell className="whitespace-nowrap">
                    {row.allocationCount} item{row.allocationCount === 1 ? "" : "s"}
                  </TableCell>
                  <TableCell className="whitespace-nowrap">{row.paymentMethod ?? "—"}</TableCell>
                  <TableCell className="whitespace-nowrap">{accountName(row.cashAccountId)}</TableCell>
                  <TableCell className="whitespace-nowrap">{row.reference ?? "—"}</TableCell>
                  <TableCell className="whitespace-nowrap text-xs text-slate-500">{row.sourceType ?? "—"}</TableCell>
                  <TableCell className="whitespace-nowrap text-xs text-slate-500">{row.createdBy ?? "—"}</TableCell>
                  <TableCell>
                    {isReversed
                      ? <Badge variant="outline" className="text-slate-500">Reversed</Badge>
                      : <Badge variant="secondary">Posted</Badge>}
                  </TableCell>
                  <TableCell className="text-right whitespace-nowrap">
                    {!multi && a && documentHref(a) && (
                      <Button variant="ghost" size="sm" onClick={() => router.push(documentHref(a)!)} title="Open the item this paid">
                        <ExternalLink className="h-3.5 w-3.5" />
                      </Button>
                    )}
                    {canReverse && !isReversed && (
                      <Button variant="ghost" size="sm" onClick={() => { setReversing(row.paymentId); setReason("") }}>
                        <Undo2 className="mr-1.5 h-3.5 w-3.5" /> Reverse
                      </Button>
                    )}
                  </TableCell>
                </TableRow>

                {isReversed && row.reversalReason && (
                  <TableRow>
                    <TableCell />
                    <TableCell colSpan={18} className="py-1 text-xs text-slate-500">
                      Reversed{row.reversedBy ? ` by ${row.reversedBy}` : ""}
                      {row.reversedAt ? ` on ${new Date(row.reversedAt).toLocaleDateString()}` : ""}: {row.reversalReason}
                    </TableCell>
                  </TableRow>
                )}

                {reversing === row.paymentId && (
                  <TableRow className="bg-amber-50">
                    <TableCell />
                    <TableCell colSpan={18} className="py-3">
                      <div className="flex flex-wrap items-end gap-2">
                        <div className="min-w-[18rem] flex-1 space-y-1.5">
                          <Label htmlFor={`sp-reason-${row.paymentId}`}>Why is this being reversed?</Label>
                          <Input
                            id={`sp-reason-${row.paymentId}`}
                            value={reason}
                            onChange={(e) => setReason(e.target.value)}
                            placeholder="e.g. paid the wrong supplier"
                          />
                        </div>
                        <Button size="sm" variant="destructive" onClick={() => doReverse(row)}>Reverse payment</Button>
                        <Button size="sm" variant="ghost" onClick={() => setReversing(null)}>Cancel</Button>
                      </div>
                      <p className="mt-2 text-xs text-slate-500">
                        This reverses the whole payment and restores the balance on
                        {row.allocationCount === 1 ? " the item" : ` all ${row.allocationCount} items`} it was applied to.
                        The cash movement is undone. The payment is kept and marked reversed, never deleted.
                      </p>
                    </TableCell>
                  </TableRow>
                )}

                {isOpen && multi && (
                  <TableRow>
                    <TableCell />
                    <TableCell colSpan={18} className="py-2">
                      {!allocs ? (
                        <span className="flex items-center gap-2 text-sm text-slate-500">
                          <Loader2 className="h-3.5 w-3.5 animate-spin" /> Loading allocation…
                        </span>
                      ) : (
                        <Table>
                          <TableHeader>
                            <TableRow>
                              <TableHead>Type</TableHead>
                              <TableHead>Purchase / Expense #</TableHead>
                              <TableHead>Item</TableHead>
                              <TableHead>Date</TableHead>
                              <TableHead className="text-right">Payable total</TableHead>
                              <TableHead className="text-right">Balance before</TableHead>
                              <TableHead className="text-right">Applied</TableHead>
                              <TableHead className="text-right">Balance after</TableHead>
                              <TableHead>Status</TableHead>
                              <TableHead />
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {allocs.map((al) => (
                              <TableRow key={al.allocationId}>
                                <TableCell>{payableTypeLabel(al.documentType)}</TableCell>
                                <TableCell className="font-medium">{al.reference ?? `#${al.documentId}`}</TableCell>
                                <TableCell className="text-slate-600">{al.label ?? "—"}</TableCell>
                                <TableCell>{al.documentDate ? new Date(al.documentDate).toLocaleDateString() : "—"}</TableCell>
                                <TableCell className="text-right">{fmt(al.documentTotal)}</TableCell>
                                <TableCell className="text-right text-slate-500">{fmt(al.balanceBefore)}</TableCell>
                                <TableCell className="text-right font-medium">{fmt(al.amountApplied)}</TableCell>
                                <TableCell className="text-right">{fmt(al.balanceAfter)}</TableCell>
                                <TableCell>
                                  {al.status === "Reversed"
                                    ? <Badge variant="outline" className="text-slate-500">Reversed</Badge>
                                    : <Badge variant="secondary">Posted</Badge>}
                                </TableCell>
                                <TableCell className="text-right">
                                  {documentHref(al) && (
                                    <Button variant="ghost" size="sm" onClick={() => router.push(documentHref(al)!)}>
                                      <ExternalLink className="h-3.5 w-3.5" />
                                    </Button>
                                  )}
                                </TableCell>
                              </TableRow>
                            ))}
                          </TableBody>
                        </Table>
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
  )

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <h1 className="mb-1 flex items-center gap-2 text-2xl font-semibold text-slate-900">
            <Receipt className="h-6 w-6 text-amber-600" />
            Supplier Payments
          </h1>
          <p className="mb-4 text-sm text-slate-500">
            Track payments made to suppliers and apply them to unpaid or partially paid purchases and expenses.
          </p>

          <div className="mb-4 grid grid-cols-2 gap-3 md:grid-cols-4">
            <Card><CardContent className="p-4">
              <div className="text-xs text-slate-500">Payments</div>
              <div className="mt-1 text-lg font-semibold text-slate-900">{filtered.length}</div>
            </CardContent></Card>
            <Card><CardContent className="p-4">
              <div className="text-xs text-slate-500">Total paid</div>
              <div className="mt-1 text-lg font-semibold text-slate-900">{fmt(postedTotal)}</div>
            </CardContent></Card>
            <Card><CardContent className="p-4">
              <div className="text-xs text-slate-500">Across several items</div>
              <div className="mt-1 text-lg font-semibold text-slate-900">
                {filtered.filter((r) => r.allocationCount > 1).length}
              </div>
            </CardContent></Card>
            <Card><CardContent className="p-4">
              <div className="text-xs text-slate-500">Reversed</div>
              <div className="mt-1 text-lg font-semibold text-slate-900">
                {filtered.filter((r) => r.status === "Reversed").length}
              </div>
            </CardContent></Card>
          </div>

          <Card className="mb-4">
            <CardContent className="space-y-4 p-4">
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
                <div className="space-y-1.5">
                  <Label htmlFor="sp-search">Search</Label>
                  <Input
                    id="sp-search" value={search} onChange={(e) => setSearch(e.target.value)}
                    placeholder="Supplier, payment #, item, reference"
                  />
                </div>
                <div className="space-y-1.5">
                  <Label>Supplier</Label>
                  <Select value={supplierFilter} onValueChange={setSupplierFilter}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">All suppliers</SelectItem>
                      {supplierOptions.map((s) => (
                        <SelectItem key={s.id} value={String(s.id)}>{s.name}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-1.5">
                  <Label>Payment method</Label>
                  <Select value={methodFilter} onValueChange={setMethodFilter}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">All methods</SelectItem>
                      {methodOptions.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-1.5">
                  <Label>Cash account</Label>
                  <Select value={accountFilter} onValueChange={setAccountFilter}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">All accounts</SelectItem>
                      {accounts.map((a) => (
                        <SelectItem key={a.id} value={String(a.id)}>{a.name}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              </div>

              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
                <div className="space-y-1.5">
                  <Label>Period</Label>
                  <Select
                    value={period}
                    onValueChange={(v) => {
                      setPeriod(v)
                      const range = periodToRange(v as any)
                      setFrom(range?.from ?? "")
                      setTo(range?.to ?? "")
                    }}
                  >
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">All time</SelectItem>
                      <SelectSeparator />
                      {PERIOD_GROUPS.map((g) => (
                        <SelectGroup key={g.label}>
                          {g.options.map((o) => (
                            <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>
                          ))}
                        </SelectGroup>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="sp-from">From</Label>
                  <Input
                    id="sp-from" type="date" value={from}
                    onChange={(e) => { setFrom(e.target.value); setPeriod(rangeToPeriod(e.target.value, to) ?? "custom") }}
                  />
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="sp-to">To</Label>
                  <Input
                    id="sp-to" type="date" value={to}
                    onChange={(e) => { setTo(e.target.value); setPeriod(rangeToPeriod(from, e.target.value) ?? "custom") }}
                  />
                </div>
                <div className="space-y-1.5">
                  <Label>Status</Label>
                  <Select value={statusFilter} onValueChange={setStatusFilter}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">All statuses</SelectItem>
                      <SelectItem value="Posted">Posted</SelectItem>
                      <SelectItem value="Reversed">Reversed</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
              </div>

              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
                <div className="space-y-1.5">
                  <Label>Source</Label>
                  <Select value={sourceFilter} onValueChange={setSourceFilter}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">All sources</SelectItem>
                      {SOURCE_FILTERS.map((s) => <SelectItem key={s} value={s}>{s}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-1.5">
                  <Label>Applied to</Label>
                  <Select value={appliedToFilter} onValueChange={setAppliedToFilter}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">Any number of items</SelectItem>
                      <SelectItem value="single">A single item</SelectItem>
                      <SelectItem value="multiple">Several items</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-1.5">
                  <Label>Payable type</Label>
                  <Select value={payableTypeFilter} onValueChange={setPayableTypeFilter}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">All types</SelectItem>
                      <SelectItem value="RawMaterialPurchase">Purchase</SelectItem>
                      <SelectItem value="FlockBatch">Flock batch</SelectItem>
                      <SelectItem value="Expense">Expense</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="grid grid-cols-2 gap-2">
                  <div className="space-y-1.5">
                    <Label htmlFor="sp-min">Min amount</Label>
                    <Input id="sp-min" type="number" value={minAmount} onChange={(e) => setMinAmount(e.target.value)} placeholder="0" />
                  </div>
                  <div className="space-y-1.5">
                    <Label htmlFor="sp-max">Max amount</Label>
                    <Input id="sp-max" type="number" value={maxAmount} onChange={(e) => setMaxAmount(e.target.value)} placeholder="Any" />
                  </div>
                </div>
              </div>

              <div className="flex flex-wrap items-center gap-2">
                <Button variant="outline" size="sm" onClick={resetFilters}>Reset filters</Button>
                <div className="flex-1" />
                <Button variant="outline" size="sm" onClick={onExportCsv} disabled={filtered.length === 0}>
                  <Download className="mr-1.5 h-3.5 w-3.5" /> CSV
                </Button>
                <Button variant="outline" size="sm" onClick={onExportPdf} disabled={filtered.length === 0}>
                  <FileText className="mr-1.5 h-3.5 w-3.5" /> PDF
                </Button>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="flex items-center gap-2 p-6 text-slate-500">
                  <Loader2 className="h-4 w-4 animate-spin" /> Loading payments…
                </div>
              ) : (
                <MobileCardList
                  items={pg.pageItems}
                  pagination={pg.paginationProps}
                  getKey={(r) => r.paymentId}
                  primary={(r) => `SPAY-${r.paymentId} · ${fmt(r.totalAmount)}`}
                  secondary={(r) => (
                    <>
                      {r.partyName ?? "No supplier"} · {new Date(r.paymentDate).toLocaleDateString()}
                    </>
                  )}
                  trailing={(r) =>
                    r.status === "Reversed"
                      ? <Badge variant="outline" className="text-slate-500">Reversed</Badge>
                      : <Badge variant="secondary">Posted</Badge>
                  }
                  details={(r) => {
                    const a = soleAllocation(r)
                    const multi = r.allocationCount > 1
                    return [
                      { label: "Applied to", value: `${r.allocationCount} item${r.allocationCount === 1 ? "" : "s"}` },
                      { label: "Purchase / Expense #", value: multi ? "Multiple" : (a?.reference ?? "—") },
                      { label: "Payable type", value: multi ? "Multiple" : payableTypeLabel(a?.documentType) },
                      { label: "Balance before", value: multi || !a ? "—" : fmt(a.balanceBefore) },
                      { label: "Applied", value: multi ? fmt(r.totalAmount) : a ? fmt(a.amountApplied) : "—" },
                      { label: "Balance after", value: multi || !a ? "—" : fmt(a.balanceAfter) },
                      { label: "Method", value: r.paymentMethod ?? "—" },
                      { label: "Cash account", value: accountName(r.cashAccountId) },
                      { label: "Reference", value: r.reference ?? "—" },
                      { label: "Source", value: r.sourceType ?? "—" },
                      { label: "Paid by", value: r.createdBy ?? "—" },
                    ]
                  }}
                  actions={(r) =>
                    canReverse && r.status === "Posted" ? (
                      <Button
                        size="sm" variant="outline" className="h-10 flex-1"
                        onClick={() => { setReversing(r.paymentId); setReason("") }}
                      >
                        <Undo2 className="mr-1.5 h-3.5 w-3.5" /> Reverse
                      </Button>
                    ) : null
                  }
                  emptyState={
                    <div className="p-8 text-center text-slate-500">
                      No supplier payments match these filters.
                    </div>
                  }
                  desktopTable={desktopTable}
                />
              )}
            </CardContent>
          </Card>
        </main>
      </div>
    </div>
  )
}
