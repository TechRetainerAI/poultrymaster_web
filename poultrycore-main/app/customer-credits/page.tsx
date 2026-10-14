"use client"

// Poultry Customer Credits (Sales & Money -> Customer Credits).
//
// Money the business RECEIVED and still holds for a customer, with no active
// sale to apply it to -- usually a payment kept when its sale was reversed.
// Its own page so it can be worked through (where it came from, refund it,
// past refunds); Customer Balances keeps its credit panel too, because "owes
// us" and "we hold their money" are read side by side there and never netted.
//
// Everything is derived on the server (351): payment - active allocations -
// refunds. Using credit on a sale is done from the sale (Add Sale's "Use
// customer credit", or the Pay dialog); refunding is real Money Out.
//
// 363: the owner or an admin can also ADD credit by hand -- an opening
// balance, a deposit (real cash in) or a credit note (a cost on P&L) -- and
// reverse it. Those documents have their own tab.

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { HandCoins, History, Loader2, PenLine, PiggyBank, Plus, RefreshCw, Search, ShoppingCart, Undo2, Users } from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { tabCountCls, tabListCls, tabTriggerCls } from "@/lib/ui/tab-styles"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { usePermissions } from "@/hooks/use-permissions"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useCurrency } from "@/lib/currency"
import { formatCurrency, getSelectedCurrency } from "@/lib/utils/currency"
import { fmtDateTime } from "@/lib/utils/company-datetime"
import {
  getCustomerCredit, listCustomerCredit, listCustomerRefunds, listManualCredits, reverseManualCredit,
  MANUAL_CREDIT_KIND_LABEL,
  type CustomerCreditRow, type CustomerCreditSummaryRow, type CustomerRefundRow, type ManualCreditRow,
} from "@/lib/api/customer-credit"
import { RefundCreditDialog, type RefundTarget } from "@/components/sales/refund-credit-dialog"
import { ManualCreditDialog } from "@/components/sales/manual-credit-dialog"

type Tab = "held" | "manual" | "refunds"

function sourceLabel(r: CustomerCreditRow): string {
  if (r.sourceType === "OpeningCredit") return "Opening balance (added by hand)"
  if (r.sourceType === "Deposit") return "Deposit (paid in advance)"
  if (r.sourceType === "CreditNote") return "Credit note"
  if (r.saleStatus === "Reversed") return `Kept from reversed sale #${r.saleId}`
  if (r.sourceType === "CustomerBalances") return "Paid more than was owed"
  return r.saleId ? `Paid on sale #${r.saleId}` : "Customer payment"
}

const KIND_TONE: Record<string, string> = {
  OpeningCredit: "border-slate-300 text-slate-700",
  Deposit: "border-emerald-300 text-emerald-700",
  CreditNote: "border-amber-300 text-amber-700",
}

export default function CustomerCreditsPage() {
  const logout = useLogout()
  const { toast } = useToast()
  const { can, isAdmin, isLoading: permsLoading } = usePermissions()
  const { code } = useCurrency()
  const currencyCode = code || getSelectedCurrency()
  const money = (n: number) => formatCurrency(Number(n) || 0, currencyCode)

  // Same audience as Customer Balances; refunding is a customer-payment action.
  const canView = can("poultry.customer-balances.view")
  const canRefund = can("poultry.customer-payments.create")
  // 363: adding or reversing credit by hand is the owner's / an admin's call,
  // like Setup -- the server refuses anyone else.
  const canManage = isAdmin

  const [tab, setTab] = useState<Tab>("held")
  const [rows, setRows] = useState<CustomerCreditSummaryRow[]>([])
  const [refunds, setRefunds] = useState<CustomerRefundRow[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [search, setSearch] = useState("")
  const [refundFor, setRefundFor] = useState<RefundTarget | null>(null)
  const [sourcesFor, setSourcesFor] = useState<CustomerCreditSummaryRow | null>(null)
  const [sources, setSources] = useState<CustomerCreditRow[] | null>(null)
  const [manual, setManual] = useState<ManualCreditRow[]>([])
  const [addOpen, setAddOpen] = useState(false)
  const [reverseFor, setReverseFor] = useState<ManualCreditRow | null>(null)
  const [reverseReason, setReverseReason] = useState("")
  const [reversing, setReversing] = useState(false)
  const [reverseError, setReverseError] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const [credit, refundRows, manualRows] = await Promise.all([
        listCustomerCredit(), listCustomerRefunds(),
        // An API without 363 has no such list: the tab is simply empty.
        listManualCredits().catch(() => [] as ManualCreditRow[]),
      ])
      setRows(credit)
      setRefunds(refundRows)
      setManual(manualRows)
    } catch (e: any) {
      setError(e?.message ?? "Could not load customer credit.")
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { if (canView) void load() }, [canView, load])

  useEffect(() => {
    setSources(null)
    if (!sourcesFor) return
    getCustomerCredit(sourcesFor.customerId)
      .then((r) => setSources(r.filter((x) => Number(x.unapplied) > 0)))
      .catch(() => setSources([]))
  }, [sourcesFor])

  const q = search.trim().toLowerCase()
  const heldRows = useMemo(() => rows.filter((r) => !q || r.customerName.toLowerCase().includes(q)), [rows, q])
  const refundRows = useMemo(
    () => refunds.filter((r) => !q || (r.customerName ?? "").toLowerCase().includes(q) || r.refundNumber.toLowerCase().includes(q)),
    [refunds, q],
  )
  const manualRows = useMemo(
    () => manual.filter((r) => !q || (r.customerName ?? "").toLowerCase().includes(q) || (r.paymentNumber ?? "").toLowerCase().includes(q)),
    [manual, q],
  )
  const heldPg = usePagination(heldRows)
  const manualPg = usePagination(manualRows)
  const refundPg = usePagination(refundRows)

  const doReverse = async () => {
    if (!reverseFor || !reverseReason.trim()) return
    setReversing(true); setReverseError(null)
    try {
      await reverseManualCredit(reverseFor.paymentGroupId, reverseReason.trim())
      toast({ title: "Credit reversed", description: `${reverseFor.paymentNumber ?? "The credit"} for ${reverseFor.customerName ?? "the customer"} was reversed.` })
      setReverseFor(null)
      void load()
    } catch (e: any) {
      setReverseError(e?.message ?? String(e))
    } finally {
      setReversing(false)
    }
  }

  const totalHeld = rows.reduce((t, r) => t + (Number(r.availableCredit) || 0), 0)
  const totalOwed = rows.reduce((t, r) => t + (Number(r.outstanding) || 0), 0)
  const totalRefunded = refunds.filter((r) => r.status !== "Reversed").reduce((t, r) => t + (Number(r.amount) || 0), 0)

  const openRefund = (r: CustomerCreditSummaryRow) =>
    setRefundFor({ customerId: r.customerId, customerName: r.customerName, availableCredit: Number(r.availableCredit) || 0 })

  if (!permsLoading && !canView) {
    return (
      <div className="flex h-screen bg-slate-50">
        <DashboardSidebar onLogout={logout} />
        <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
          <DashboardHeader />
          <main className="flex-1 overflow-auto p-6">
            <Card><CardContent className="p-8 text-center text-slate-500">
              You do not have access to customer credits.
            </CardContent></Card>
          </main>
        </div>
      </div>
    )
  }

  const rowActions = (r: CustomerCreditSummaryRow, mobile = false) => (
    <>
      <Button size="sm" variant="outline" className={mobile ? "flex-1 h-10" : undefined} onClick={() => setSourcesFor(r)}>
        <History className="mr-1.5 h-4 w-4" /> Where from
      </Button>
      {canRefund && (
        <Button size="sm" variant="outline" className={mobile ? "flex-1 h-10" : undefined} onClick={() => openRefund(r)}>
          <HandCoins className="mr-1.5 h-4 w-4" /> Refund
        </Button>
      )}
    </>
  )

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6 space-y-4">
          <div className="flex flex-wrap items-start justify-between gap-2">
            <div>
              <h1 className="flex items-center gap-2 text-2xl font-semibold text-slate-900">
                <PiggyBank className="h-6 w-6 text-blue-600" /> Customer Credits
              </h1>
              <p className="max-w-2xl text-sm text-slate-600">
                Money held for customers that is not on any active sale: kept when a sale was reversed, or added by hand
                (opening balance, deposit, credit note). Use it on their next sale (tick &quot;Use customer credit&quot; when
                adding the sale), or refund it.
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              {canManage && (
                <Button onClick={() => setAddOpen(true)} className="h-10 bg-blue-600 hover:bg-blue-700">
                  <Plus className="mr-1 h-4 w-4" /> Add credit
                </Button>
              )}
              <Button asChild variant="outline" className="h-10">
                <Link href="/customer-balances"><Users className="mr-1 h-4 w-4" /> Customer Balances</Link>
              </Button>
              <Button variant="outline" onClick={load} disabled={loading} className="h-10">
                <RefreshCw className={loading ? "mr-1 h-4 w-4 animate-spin" : "mr-1 h-4 w-4"} /> Refresh
              </Button>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <Card><CardContent className="p-4">
              <div className="text-xs text-slate-500">Credit held</div>
              <div className="text-2xl font-semibold tabular-nums text-blue-700">{money(totalHeld)}</div>
            </CardContent></Card>
            <Card><CardContent className="p-4">
              <div className="text-xs text-slate-500">Customers with credit</div>
              <div className="text-2xl font-semibold tabular-nums">{rows.length}</div>
            </CardContent></Card>
            <Card><CardContent className="p-4">
              <div className="text-xs text-slate-500">They still owe (not netted)</div>
              <div className="text-2xl font-semibold tabular-nums text-amber-700">{money(totalOwed)}</div>
            </CardContent></Card>
            <Card><CardContent className="p-4">
              <div className="text-xs text-slate-500">Refunded</div>
              <div className="text-2xl font-semibold tabular-nums">{money(totalRefunded)}</div>
            </CardContent></Card>
          </div>

          {error && <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</div>}

          <Tabs value={tab} onValueChange={(v) => setTab(v as Tab)} className="space-y-3">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <TabsList className={tabListCls}>
                <TabsTrigger value="held" className={tabTriggerCls}>
                  <PiggyBank className="h-4 w-4" /> Credit held
                  <span className={tabCountCls}>{rows.length}</span>
                </TabsTrigger>
                <TabsTrigger value="manual" className={tabTriggerCls}>
                  <PenLine className="h-4 w-4" /> Added by hand
                  <span className={tabCountCls}>{manual.length}</span>
                </TabsTrigger>
                <TabsTrigger value="refunds" className={tabTriggerCls}>
                  <HandCoins className="h-4 w-4" /> Refunds
                  <span className={tabCountCls}>{refunds.length}</span>
                </TabsTrigger>
              </TabsList>
              <div className="relative w-full sm:w-72">
                <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
                <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search customer" className="h-10 pl-9" />
              </div>
            </div>

            <TabsContent value="held">
              <Card><CardContent className="p-0 sm:p-0">
                {loading && rows.length === 0 ? (
                  <div className="flex items-center gap-2 p-8 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
                ) : (
                  <MobileCardList
                    items={heldPg.pageItems}
                    pagination={heldPg.paginationProps}
                    getKey={(r) => r.customerId}
                    primary={(r) => r.customerName}
                    secondary={(r) => <span>{r.paymentCount} payment{r.paymentCount === 1 ? "" : "s"}</span>}
                    highlights={(r) => [
                      { label: "Credit", value: money(r.availableCredit), accent: "blue" },
                      { label: "Owes", value: money(r.outstanding), accent: Number(r.outstanding) > 0 ? "amber" : "slate" },
                    ]}
                    actions={(r) => rowActions(r, true)}
                    emptyState={
                      <div className="p-8 text-center text-sm text-slate-500">
                        {q ? "No customer matches." : "No customer has credit. Nothing is being held for anyone."}
                      </div>
                    }
                    desktopTable={
                      <>
                        <Table>
                          <TableHeader>
                            <TableRow>
                              <TableHead>Customer</TableHead>
                              <TableHead className="text-right">Credit held</TableHead>
                              <TableHead className="text-right">Payments</TableHead>
                              <TableHead className="text-right">Still owes</TableHead>
                              <TableHead className="text-right">Actions</TableHead>
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {heldPg.pageItems.length === 0 ? (
                              <TableRow><TableCell colSpan={5} className="py-8 text-center text-sm text-slate-500">
                                {q ? "No customer matches." : "No customer has credit. Nothing is being held for anyone."}
                              </TableCell></TableRow>
                            ) : heldPg.pageItems.map((r) => (
                              <TableRow key={r.customerId}>
                                <TableCell className="font-medium">
                                  <Link href={`/customers/${r.customerId}`} className="hover:underline">{r.customerName}</Link>
                                </TableCell>
                                <TableCell className="text-right font-semibold tabular-nums text-blue-700">{money(r.availableCredit)}</TableCell>
                                <TableCell className="text-right tabular-nums">{r.paymentCount}</TableCell>
                                <TableCell className="text-right tabular-nums">{money(r.outstanding)}</TableCell>
                                <TableCell className="text-right"><div className="flex justify-end gap-2">{rowActions(r)}</div></TableCell>
                              </TableRow>
                            ))}
                          </TableBody>
                        </Table>
                        <DataPagination {...heldPg.paginationProps} />
                      </>
                    }
                  />
                )}
              </CardContent></Card>
              <p className="mt-2 flex items-center gap-1.5 text-xs text-slate-500">
                <ShoppingCart className="h-3.5 w-3.5" /> To use credit, add the customer&apos;s next sale on the Sales page and tick &quot;Use customer credit&quot;, or use the Pay dialog on a sale they owe. No new money is recorded.
              </p>
            </TabsContent>

            <TabsContent value="manual">
              <Card><CardContent className="p-0 sm:p-0">
                <MobileCardList
                  items={manualPg.pageItems}
                  pagination={manualPg.paginationProps}
                  getKey={(r) => r.paymentGroupId}
                  primary={(r) => r.customerName ?? `Customer ${r.customerId}`}
                  secondary={(r) => <span>{MANUAL_CREDIT_KIND_LABEL[r.kind] ?? r.kind} · {r.paymentNumber ?? ""} · {fmtDateTime(r.creditDate, r)}</span>}
                  trailing={(r) => r.status === "Reversed" ? <Badge variant="secondary">Reversed</Badge> : null}
                  highlights={(r) => [
                    { label: "Amount", value: money(r.amount), accent: "blue" },
                    { label: "Left", value: money(r.remaining), accent: "slate" },
                  ]}
                  details={(r) => [
                    { label: "Used on sales", value: money(r.used) },
                    { label: "Refunded", value: money(r.refunded) },
                    { label: "Cash", value: r.kind === "Deposit" ? [r.cashAccountName, r.paymentMethod].filter(Boolean).join(" · ") || "—" : "None" },
                    { label: "Reason", value: r.status === "Reversed" ? `${r.reason ?? ""} (reversed: ${r.reversalReason ?? ""})` : r.reason || "—" },
                  ]}
                  actions={(r) => canManage && r.status !== "Reversed" ? (
                    <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => { setReverseFor(r); setReverseReason(""); setReverseError(null) }}>
                      <Undo2 className="mr-1.5 h-4 w-4" /> Reverse
                    </Button>
                  ) : null}
                  emptyState={
                    <div className="p-8 text-center text-sm text-slate-500">
                      No credit has been added by hand.{canManage ? " Use Add credit for an opening balance, a deposit or a credit note." : ""}
                    </div>
                  }
                  desktopTable={
                    <>
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Number</TableHead>
                            <TableHead>Date</TableHead>
                            <TableHead>Customer</TableHead>
                            <TableHead>Kind</TableHead>
                            <TableHead className="text-right">Amount</TableHead>
                            <TableHead className="text-right">Used</TableHead>
                            <TableHead className="text-right">Left</TableHead>
                            <TableHead>Reason</TableHead>
                            <TableHead className="text-right">Actions</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {manualPg.pageItems.length === 0 ? (
                            <TableRow><TableCell colSpan={9} className="py-8 text-center text-sm text-slate-500">
                              No credit has been added by hand.{canManage ? " Use Add credit for an opening balance, a deposit or a credit note." : ""}
                            </TableCell></TableRow>
                          ) : manualPg.pageItems.map((r) => {
                            const reversed = r.status === "Reversed"
                            return (
                              <TableRow key={r.paymentGroupId} className={reversed ? "text-slate-400" : undefined}>
                                <TableCell className={reversed ? "font-medium line-through" : "font-medium"}>{r.paymentNumber ?? "—"}</TableCell>
                                <TableCell className="whitespace-nowrap">{fmtDateTime(r.creditDate, r)}</TableCell>
                                <TableCell>{r.customerName ?? `Customer ${r.customerId}`}</TableCell>
                                <TableCell>
                                  <Badge variant="outline" className={KIND_TONE[r.kind]}>{MANUAL_CREDIT_KIND_LABEL[r.kind] ?? r.kind}</Badge>
                                  {r.kind === "Deposit" && r.cashAccountName && (
                                    <span className="block text-xs text-slate-500">{[r.cashAccountName, r.paymentMethod].filter(Boolean).join(" · ")}</span>
                                  )}
                                </TableCell>
                                <TableCell className={reversed ? "text-right tabular-nums line-through" : "text-right tabular-nums"}>{money(r.amount)}</TableCell>
                                <TableCell className="text-right tabular-nums">{money(r.used + r.refunded)}</TableCell>
                                <TableCell className="text-right font-semibold tabular-nums text-blue-700">{reversed ? "—" : money(r.remaining)}</TableCell>
                                <TableCell className="max-w-[240px]">
                                  <span className="block truncate" title={r.reason ?? undefined}>{r.reason}</span>
                                  {reversed && <span className="block truncate text-xs" title={r.reversalReason ?? undefined}>Reversed: {r.reversalReason}</span>}
                                </TableCell>
                                <TableCell className="text-right">
                                  {canManage && !reversed ? (
                                    <Button size="sm" variant="outline" onClick={() => { setReverseFor(r); setReverseReason(""); setReverseError(null) }}>
                                      <Undo2 className="mr-1.5 h-4 w-4" /> Reverse
                                    </Button>
                                  ) : reversed ? <Badge variant="secondary">Reversed</Badge> : null}
                                </TableCell>
                              </TableRow>
                            )
                          })}
                        </TableBody>
                      </Table>
                      <DataPagination {...manualPg.paginationProps} />
                    </>
                  }
                />
              </CardContent></Card>
            </TabsContent>

            <TabsContent value="refunds">
              <Card><CardContent className="p-0 sm:p-0">
                <MobileCardList
                  items={refundPg.pageItems}
                  pagination={refundPg.paginationProps}
                  getKey={(r) => r.refundId}
                  primary={(r) => r.customerName ?? `Customer ${r.customerId}`}
                  secondary={(r) => <span>{r.refundNumber} · {fmtDateTime(r.refundDate, r)}</span>}
                  trailing={(r) => r.status === "Reversed" ? <Badge variant="secondary">Reversed</Badge> : null}
                  highlights={(r) => [{ label: "Refunded", value: money(r.amount), accent: "rose" }]}
                  details={(r) => [
                    { label: "From", value: r.accountName || "—" },
                    { label: "Method", value: r.paymentMethod || "—" },
                    { label: "Reason", value: r.reason || "—" },
                  ]}
                  emptyState={<div className="p-8 text-center text-sm text-slate-500">No refunds yet.</div>}
                  desktopTable={
                    <>
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Refund</TableHead>
                            <TableHead>Date</TableHead>
                            <TableHead>Customer</TableHead>
                            <TableHead className="text-right">Amount</TableHead>
                            <TableHead>Paid from</TableHead>
                            <TableHead>Reason</TableHead>
                            <TableHead>Status</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {refundPg.pageItems.length === 0 ? (
                            <TableRow><TableCell colSpan={7} className="py-8 text-center text-sm text-slate-500">No refunds yet.</TableCell></TableRow>
                          ) : refundPg.pageItems.map((r) => (
                            <TableRow key={r.refundId} className={r.status === "Reversed" ? "text-slate-400 line-through" : undefined}>
                              <TableCell className="font-medium">{r.refundNumber}</TableCell>
                              <TableCell className="whitespace-nowrap">{fmtDateTime(r.refundDate, r)}</TableCell>
                              <TableCell>{r.customerName ?? `Customer ${r.customerId}`}</TableCell>
                              <TableCell className="text-right tabular-nums">{money(r.amount)}</TableCell>
                              <TableCell>{[r.accountName, r.paymentMethod].filter(Boolean).join(" · ") || "—"}</TableCell>
                              <TableCell className="max-w-[260px] truncate" title={r.reason}>{r.reason}</TableCell>
                              <TableCell><Badge variant={r.status === "Reversed" ? "secondary" : "outline"}>{r.status}</Badge></TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                      <DataPagination {...refundPg.paginationProps} />
                    </>
                  }
                />
              </CardContent></Card>
            </TabsContent>
          </Tabs>
        </main>
      </div>

      <Dialog open={!!sourcesFor} onOpenChange={(o) => { if (!o) setSourcesFor(null) }}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2"><History className="h-5 w-5 text-blue-600" /> Where {sourcesFor?.customerName}&apos;s credit came from</DialogTitle>
            <DialogDescription>Each payment with money not yet used on an active sale.</DialogDescription>
          </DialogHeader>
          {sources === null ? (
            <div className="flex items-center gap-2 py-6 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : sources.length === 0 ? (
            <p className="py-4 text-sm text-slate-500">Nothing held any more.</p>
          ) : (
            <ul className="divide-y rounded-md border">
              {sources.map((s) => (
                <li key={s.poultryPaymentId} className="flex items-start justify-between gap-3 p-3">
                  <div className="min-w-0">
                    <p className="text-sm font-medium text-slate-900">{s.paymentNumber || `Payment ${s.poultryPaymentId}`}</p>
                    <p className="text-xs text-slate-500">
                      {sourceLabel(s)}{s.paymentDate ? ` · ${fmtDateTime(s.paymentDate)}` : ""}
                    </p>
                  </div>
                  <div className="shrink-0 text-right">
                    <p className="text-sm font-semibold tabular-nums text-blue-700">{money(s.unapplied)}</p>
                    {Number(s.amount) > Number(s.unapplied) + 0.005 && (
                      <p className="text-[11px] text-slate-500">of {money(s.amount)}</p>
                    )}
                  </div>
                </li>
              ))}
            </ul>
          )}
        </DialogContent>
      </Dialog>

      <ManualCreditDialog
        open={addOpen}
        currencyCode={currencyCode}
        onOpenChange={setAddOpen}
        onCreated={(c) => {
          toast({
            title: "Credit added",
            description: `${money(c.amount)} ${MANUAL_CREDIT_KIND_LABEL[c.kind].toLowerCase()} for ${c.customerName}${c.paymentNumber ? ` (${c.paymentNumber})` : ""}.`,
          })
          setAddOpen(false)
          setTab("manual")
          void load()
        }}
      />

      <Dialog open={!!reverseFor} onOpenChange={(o) => { if (!o && !reversing) setReverseFor(null) }}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2"><Undo2 className="h-5 w-5 text-red-600" /> Reverse {reverseFor?.paymentNumber ?? "credit"}?</DialogTitle>
            <DialogDescription>
              The credit stays in the history, marked Reversed. {reverseFor?.customerName ?? "The customer"} no longer holds it.
            </DialogDescription>
          </DialogHeader>
          {reverseFor && (
            <div className="space-y-3 text-sm">
              <ul className="list-disc space-y-1 pl-5 text-slate-700">
                <li>{money(reverseFor.amount)} {MANUAL_CREDIT_KIND_LABEL[reverseFor.kind].toLowerCase()} is cancelled.</li>
                {reverseFor.used > 0 && (
                  <li className="text-amber-800">{money(reverseFor.used)} of it was used on sales. Those sales will be owed again.</li>
                )}
                {reverseFor.kind === "Deposit" && (
                  <li>{reverseFor.cashAccountName ?? "Its cash account"} goes down by {money(reverseFor.amount)}, shown in Cash Flow as a payment reversal.</li>
                )}
                {reverseFor.kind === "CreditNote" && <li>It comes off Profit &amp; Loss.</li>}
              </ul>
              <div className="space-y-1">
                <Label htmlFor="mc-reverse-reason">Reason *</Label>
                <Textarea id="mc-reverse-reason" rows={2} value={reverseReason} onChange={(e) => setReverseReason(e.target.value)} placeholder="e.g. entered twice" />
              </div>
              {reverseError && <p className="rounded-md bg-red-50 p-2.5 text-red-700">{reverseError}</p>}
            </div>
          )}
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setReverseFor(null)} disabled={reversing}>Cancel</Button>
            <Button className="bg-red-600 hover:bg-red-700" onClick={doReverse} disabled={reversing || !reverseReason.trim()}>
              {reversing && <Loader2 className="mr-2 h-4 w-4 animate-spin" />} Reverse credit
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      <RefundCreditDialog
        target={refundFor}
        currencyCode={currencyCode}
        onOpenChange={(o) => { if (!o) setRefundFor(null) }}
        onRefunded={() => {
          toast({ title: "Refund recorded", description: `Paid back to ${refundFor?.customerName}. It shows in Cash Flow as a customer refund.` })
          setRefundFor(null)
          void load()
        }}
      />
    </div>
  )
}
