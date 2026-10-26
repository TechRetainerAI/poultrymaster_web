"use client"

// Poultry Supplier Credits & Advances (Sales & Money -> Supplier Credits).
//
// Money a supplier holds for the business, or owes it: an advance paid before
// delivery, the part of a payment not applied, or a credit added by hand
// (credit note, opening credit). The supplier side of Customer Credits (370).
//
// Everything is derived on the server: a payment's amount - what is applied -
// what the supplier refunded. Applying credit to a purchase moves no cash (it
// left with the advance); a supplier refund is real Money In.

import { REVERSAL_REASONS } from "@/lib/reversal-reasons"
import { ReasonSelect } from "@/components/ui/reason-select"
import { Fragment, useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import {
  ArrowDownToLine, ChevronDown, ChevronRight, Link2, Loader2, Plus, RefreshCw, Search, Truck, Undo2, Wallet,
} from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import {
  Dialog, DialogContent, DialogDescription, DialogHeader,
} from "@/components/ui/dialog"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { FORM_DIALOG_CONTENT, FORM_DIALOG_PRIMARY, FormDialogFooter, FormDialogTitle } from "@/components/ui/form-dialog"
import { FormSection } from "@/components/ui/form-section"
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
import { cn } from "@/lib/utils"
import {
  listSupplierCredit, listSupplierCreditApplications, listSupplierCreditEvents, listSupplierRefunds,
  reverseSupplierCredit, reverseSupplierRefund, unapplySupplierCredit, SUPPLIER_CREDIT_KIND_LABEL,
  type SupplierCreditApplication, type SupplierCreditEvent, type SupplierCreditSummaryRow, type SupplierRefundRow,
} from "@/lib/api/supplier-credit"
import {
  ApplySupplierCreditDialog, PaySupplierAdvanceDialog, SupplierCreditDialog, SupplierRefundDialog,
} from "@/components/suppliers/supplier-credit-dialogs"

type Tab = "held" | "applied" | "refunds"

const STATUS_TONE: Record<string, string> = {
  Available: "border-blue-300 text-blue-700",
  "Partly used": "border-amber-300 text-amber-700",
  Used: "border-slate-300 text-slate-500",
  Refunded: "border-slate-300 text-slate-500",
}

/** One reversal dialog for the three kinds of thing this page reverses. */
type ReverseTarget =
  | { kind: "credit"; event: SupplierCreditEvent }
  | { kind: "application"; app: SupplierCreditApplication }
  | { kind: "refund"; refund: SupplierRefundRow }

export default function SupplierCreditsPage() {
  const logout = useLogout()
  const { toast } = useToast()
  const { can, isAdmin, isLoading: permsLoading } = usePermissions()
  const { code } = useCurrency()
  const currencyCode = code || getSelectedCurrency()
  const money = (n: number) => formatCurrency(Number(n) || 0, currencyCode)

  const canView = can("poultry.supplier-balances.view")
  // Paying an advance, applying credit and taking a refund are supplier-payment actions.
  const canPay = can("poultry.supplier-payments.create")
  // Added by hand, and every reversal or unapply: the owner / an admin.
  const canManage = isAdmin

  const [tab, setTab] = useState<Tab>("held")
  const [rows, setRows] = useState<SupplierCreditSummaryRow[]>([])
  const [apps, setApps] = useState<SupplierCreditApplication[]>([])
  const [refunds, setRefunds] = useState<SupplierRefundRow[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [search, setSearch] = useState("")
  const [expanded, setExpanded] = useState<Set<number>>(new Set())
  const [events, setEvents] = useState<Record<number, SupplierCreditEvent[] | undefined>>({})
  const [eventsFor, setEventsFor] = useState<SupplierCreditSummaryRow | null>(null)
  const [advanceOpen, setAdvanceOpen] = useState(false)
  const [creditOpen, setCreditOpen] = useState(false)
  const [applyFor, setApplyFor] = useState<SupplierCreditEvent | null>(null)
  const [refundFor, setRefundFor] = useState<SupplierCreditEvent | null>(null)
  const [reverse, setReverse] = useState<ReverseTarget | null>(null)
  const [reason, setReason] = useState("")
  const [reversing, setReversing] = useState(false)
  const [reverseError, setReverseError] = useState<string | null>(null)

  const loadEvents = useCallback(async (supplierId: number) => {
    setEvents((p) => ({ ...p, [supplierId]: undefined }))
    try {
      const list = await listSupplierCreditEvents(supplierId)
      setEvents((p) => ({ ...p, [supplierId]: list }))
    } catch {
      setEvents((p) => ({ ...p, [supplierId]: [] }))
    }
  }, [])

  const load = useCallback(async () => {
    setLoading(true); setError(null)
    try {
      const [summary, appRows, refundRows] = await Promise.all([
        listSupplierCredit(), listSupplierCreditApplications(), listSupplierRefunds(),
      ])
      setRows(summary); setApps(appRows); setRefunds(refundRows); setEvents({})
    } catch (e: any) {
      setError(e?.message ?? "Could not load supplier credit.")
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { if (canView) void load() }, [canView, load])

  useEffect(() => {
    const want = new Set(expanded)
    if (eventsFor) want.add(eventsFor.supplierId)
    want.forEach((id) => { if (!(id in events)) void loadEvents(id) })
  }, [expanded, eventsFor, events, loadEvents])

  const toggle = (id: number) =>
    setExpanded((p) => { const n = new Set(p); if (n.has(id)) n.delete(id); else n.add(id); return n })

  const q = search.trim().toLowerCase()
  const heldRows = useMemo(() => rows.filter((r) => !q || r.supplierName.toLowerCase().includes(q)), [rows, q])
  const appRows = useMemo(() => apps.filter((r) => !q || (r.supplierName ?? "").toLowerCase().includes(q) || (r.reference ?? "").toLowerCase().includes(q)), [apps, q])
  const refundRows = useMemo(() => refunds.filter((r) => !q || (r.supplierName ?? "").toLowerCase().includes(q) || r.refundNumber.toLowerCase().includes(q)), [refunds, q])
  const heldPg = usePagination(heldRows)
  const appPg = usePagination(appRows)
  const refundPg = usePagination(refundRows)

  const totalHeld = rows.reduce((t, r) => t + (Number(r.availableCredit) || 0), 0)
  const totalOwed = rows.reduce((t, r) => t + (Number(r.owed) || 0), 0)
  const totalReturned = refunds.filter((r) => r.status === "Posted").reduce((t, r) => t + (Number(r.amount) || 0), 0)

  const openReverse = (t: ReverseTarget) => { setReverse(t); setReason(""); setReverseError(null) }

  const doReverse = async () => {
    if (!reverse || !reason.trim()) return
    setReversing(true); setReverseError(null)
    try {
      if (reverse.kind === "credit") {
        await reverseSupplierCredit(reverse.event.poultrySupplierPaymentId, reason.trim())
        toast({ title: "Credit reversed", description: `${reverse.event.creditNumber} for ${reverse.event.supplierName ?? "the supplier"} was reversed.` })
      } else if (reverse.kind === "application") {
        await unapplySupplierCredit(reverse.app.allocationId, reason.trim())
        toast({ title: "Credit unapplied", description: `${money(reverse.app.amount)} is back on ${reverse.app.creditNumber}; ${reverse.app.reference ?? "the item"} is owed again.` })
      } else {
        await reverseSupplierRefund(reverse.refund.refundId, reason.trim())
        toast({ title: "Refund reversed", description: `${reverse.refund.refundNumber}: the credit is back and ${reverse.refund.accountName ?? "the account"} goes down by ${money(reverse.refund.amount)}.` })
      }
      setReverse(null)
      void load()
    } catch (e: any) {
      setReverseError(e?.message ?? String(e))
    } finally {
      setReversing(false)
    }
  }

  if (!permsLoading && !canView) {
    return (
      <div className="flex h-screen bg-slate-50">
        <DashboardSidebar onLogout={logout} />
        <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
          <DashboardHeader />
          <main className="flex-1 overflow-auto p-6">
            <Card><CardContent className="p-8 text-center text-slate-500">You do not have access to supplier credits.</CardContent></Card>
          </main>
        </div>
      </div>
    )
  }

  const eventActions = (e: SupplierCreditEvent, mobile = false) => (
    <>
      {canPay && e.available > 0 && (
        <Button size="sm" variant="outline" className={mobile ? "flex-1 h-10" : "h-8"} onClick={() => setApplyFor(e)}>
          <Link2 className="mr-1.5 h-4 w-4" /> Apply
        </Button>
      )}
      {canPay && e.available > 0 && e.sourceType && !["SupplierCreditNote", "SupplierOpeningCredit", "SupplierManualCredit"].includes(e.sourceType) && (
        <Button size="sm" variant="outline" className={mobile ? "flex-1 h-10" : "h-8"} onClick={() => setRefundFor(e)}>
          <ArrowDownToLine className="mr-1.5 h-4 w-4" /> Refund
        </Button>
      )}
      {canManage && e.isManual && e.applied === 0 && e.refunded === 0 && (
        <Button size="sm" variant="outline" className={mobile ? "flex-1 h-10" : "h-8"} onClick={() => openReverse({ kind: "credit", event: e })}>
          <Undo2 className="mr-1.5 h-4 w-4" /> Reverse
        </Button>
      )}
    </>
  )

  const eventsTable = (supplierId: number) => {
    const list = events[supplierId]
    if (list === undefined) return <div className="flex items-center gap-2 p-4 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading credits…</div>
    if (list.length === 0) return <p className="p-4 text-sm text-slate-500">Nothing held any more.</p>
    return (
      <div className="overflow-x-auto">
        <table className="w-full min-w-[62rem] text-sm">
          <thead className="text-left text-xs uppercase tracking-wider text-slate-500">
            <tr className="whitespace-nowrap">
              <th className="px-3 py-2 font-medium">Date</th>
              <th className="px-3 py-2 font-medium">Credit</th>
              <th className="px-3 py-2 font-medium">Source</th>
              <th className="px-3 py-2 font-medium">Reference</th>
              <th className="px-3 py-2 text-right font-medium">Original</th>
              <th className="px-3 py-2 text-right font-medium">Applied</th>
              <th className="px-3 py-2 text-right font-medium">Refunded</th>
              <th className="px-3 py-2 text-right font-medium">Available</th>
              <th className="px-3 py-2 font-medium">Status</th>
              <th className="px-3 py-2 text-right font-medium">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100">
            {list.map((e) => (
              <tr key={e.poultrySupplierPaymentId} className="whitespace-nowrap">
                <td className="px-3 py-2">{fmtDateTime(e.creditDate)}</td>
                <td className="px-3 py-2 font-medium">{e.creditNumber}</td>
                <td className="px-3 py-2">{e.source}{e.accountName ? <span className="block text-xs text-slate-500">{e.accountName}</span> : null}</td>
                <td className="max-w-[12rem] truncate px-3 py-2 text-slate-600" title={[e.reference, e.notes].filter(Boolean).join(" · ") || undefined}>{e.reference ?? e.notes ?? "—"}</td>
                <td className="px-3 py-2 text-right tabular-nums">{money(e.originalAmount)}</td>
                <td className="px-3 py-2 text-right tabular-nums">{money(e.applied)}</td>
                <td className="px-3 py-2 text-right tabular-nums">{money(e.refunded)}</td>
                <td className="px-3 py-2 text-right font-semibold tabular-nums text-blue-700">{money(e.available)}</td>
                <td className="px-3 py-2"><Badge variant="outline" className={STATUS_TONE[e.status]}>{e.status}</Badge></td>
                <td className="px-3 py-2 text-right"><div className="flex justify-end gap-2">{eventActions(e)}</div></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    )
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6 space-y-4">
          <div className="flex flex-wrap items-start justify-between gap-2">
            <div>
              <h1 className="flex items-center gap-2 text-2xl font-semibold text-slate-900">
                <Wallet className="h-6 w-6 text-amber-600" /> Supplier Credits &amp; Advances
              </h1>
              <p className="max-w-2xl text-sm text-slate-600">
                Money a supplier holds for you: advances paid before delivery, the part of a payment not used on a purchase,
                and credit notes. Apply it to their purchases (no money moves), or record money they send back.
                Open a supplier to see each credit.
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              {canPay && (
                <Button onClick={() => setAdvanceOpen(true)} className="h-10 bg-amber-600 hover:bg-amber-700">
                  <Wallet className="mr-1 h-4 w-4" /> Pay advance
                </Button>
              )}
              {canManage && (
                <Button onClick={() => setCreditOpen(true)} className="h-10 bg-blue-600 hover:bg-blue-700">
                  <Plus className="mr-1 h-4 w-4" /> Add credit
                </Button>
              )}
              <Button asChild variant="outline" className="h-10">
                <Link href="/supplier-balances"><Truck className="mr-1 h-4 w-4" /> Supplier Balances</Link>
              </Button>
              <Button variant="outline" onClick={load} disabled={loading} className="h-10">
                <RefreshCw className={loading ? "mr-1 h-4 w-4 animate-spin" : "mr-1 h-4 w-4"} /> Refresh
              </Button>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <Card><CardContent className="p-4">
              <div className="text-xs text-slate-500">Available credit with suppliers</div>
              <div className="text-2xl font-semibold tabular-nums text-blue-700">{money(totalHeld)}</div>
            </CardContent></Card>
            <Card><CardContent className="p-4">
              <div className="text-xs text-slate-500">Suppliers with credit</div>
              <div className="text-2xl font-semibold tabular-nums">{rows.length}</div>
            </CardContent></Card>
            <Card><CardContent className="p-4">
              <div className="text-xs text-slate-500">You still owe them (not netted)</div>
              <div className="text-2xl font-semibold tabular-nums text-amber-700">{money(totalOwed)}</div>
            </CardContent></Card>
            <Card><CardContent className="p-4">
              <div className="text-xs text-slate-500">Sent back by suppliers</div>
              <div className="text-2xl font-semibold tabular-nums">{money(totalReturned)}</div>
            </CardContent></Card>
          </div>

          {error && <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</div>}

          <Tabs value={tab} onValueChange={(v) => setTab(v as Tab)} className="space-y-3">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <TabsList className={tabListCls}>
                <TabsTrigger value="held" className={tabTriggerCls}><Wallet className="h-4 w-4" /> Available credit <span className={tabCountCls}>{rows.length}</span></TabsTrigger>
                <TabsTrigger value="applied" className={tabTriggerCls}><Link2 className="h-4 w-4" /> Applied <span className={tabCountCls}>{apps.length}</span></TabsTrigger>
                <TabsTrigger value="refunds" className={tabTriggerCls}><ArrowDownToLine className="h-4 w-4" /> Refunds <span className={tabCountCls}>{refunds.length}</span></TabsTrigger>
              </TabsList>
              <div className="relative w-full sm:w-72">
                <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
                <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search supplier" className="h-10 pl-9" />
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
                    getKey={(r) => r.supplierId}
                    primary={(r) => r.supplierName}
                    secondary={(r) => <span>{r.creditCount} credit{r.creditCount === 1 ? "" : "s"}</span>}
                    highlights={(r) => [
                      { label: "Available", value: money(r.availableCredit), accent: "blue" },
                      { label: "You owe", value: money(r.owed), accent: Number(r.owed) > 0 ? "amber" : "slate" },
                    ]}
                    actions={(r) => (
                      <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => setEventsFor(r)}>
                        <Wallet className="mr-1.5 h-4 w-4" /> Credits
                      </Button>
                    )}
                    emptyState={<div className="p-8 text-center text-sm text-slate-500">{q ? "No supplier matches." : "No supplier holds credit for you."}</div>}
                    desktopTable={
                      <>
                        <Table>
                          <TableHeader>
                            <TableRow>
                              <TableHead className="w-10" />
                              <TableHead>Supplier</TableHead>
                              <TableHead className="text-right">Available credit</TableHead>
                              <TableHead className="text-right">Credits</TableHead>
                              <TableHead className="text-right">You still owe</TableHead>
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {heldPg.pageItems.length === 0 ? (
                              <TableRow><TableCell colSpan={5} className="py-8 text-center text-sm text-slate-500">
                                {q ? "No supplier matches." : "No supplier holds credit for you."}
                              </TableCell></TableRow>
                            ) : heldPg.pageItems.map((r) => {
                              const open = expanded.has(r.supplierId)
                              return (
                                <Fragment key={r.supplierId}>
                                  <TableRow className={cn("cursor-pointer", open && "bg-amber-50/40")} onClick={() => toggle(r.supplierId)}>
                                    <TableCell className="w-10 text-slate-500">{open ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}</TableCell>
                                    <TableCell className="font-medium">{r.supplierName}</TableCell>
                                    <TableCell className="text-right font-semibold tabular-nums text-blue-700">{money(r.availableCredit)}</TableCell>
                                    <TableCell className="text-right tabular-nums">{r.creditCount}</TableCell>
                                    <TableCell className="text-right tabular-nums">{money(r.owed)}</TableCell>
                                  </TableRow>
                                  {open && (
                                    <TableRow className="hover:bg-transparent">
                                      <TableCell colSpan={5} className="bg-slate-50/70 p-0">{eventsTable(r.supplierId)}</TableCell>
                                    </TableRow>
                                  )}
                                </Fragment>
                              )
                            })}
                          </TableBody>
                        </Table>
                        <DataPagination {...heldPg.paginationProps} />
                      </>
                    }
                  />
                )}
              </CardContent></Card>
            </TabsContent>

            <TabsContent value="applied">
              <Card><CardContent className="p-0 sm:p-0">
                <MobileCardList
                  items={appPg.pageItems}
                  pagination={appPg.paginationProps}
                  getKey={(r) => r.allocationId}
                  primary={(r) => r.supplierName ?? `Supplier ${r.supplierId}`}
                  secondary={(r) => <span>{r.creditNumber} → {r.reference ?? `${r.documentType} #${r.documentId}`} · {fmtDateTime(r.appliedDate)}</span>}
                  trailing={(r) => r.status === "Reversed" ? <Badge variant="secondary">Undone</Badge> : null}
                  highlights={(r) => [{ label: "Applied", value: money(r.amount), accent: "blue" }]}
                  details={(r) => [
                    { label: "On", value: r.label || "—" },
                    ...(r.status === "Reversed" ? [{ label: "Undone", value: r.reversalReason || "—" }] : []),
                  ]}
                  actions={(r) => canManage && r.status === "Posted" ? (
                    <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openReverse({ kind: "application", app: r })}>
                      <Undo2 className="mr-1.5 h-4 w-4" /> Unapply
                    </Button>
                  ) : null}
                  emptyState={<div className="p-8 text-center text-sm text-slate-500">No supplier credit has been applied yet.</div>}
                  desktopTable={
                    <>
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Date</TableHead>
                            <TableHead>Supplier</TableHead>
                            <TableHead>Credit</TableHead>
                            <TableHead>Applied to</TableHead>
                            <TableHead className="text-right">Amount</TableHead>
                            <TableHead>Status</TableHead>
                            <TableHead className="text-right">Actions</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {appPg.pageItems.length === 0 ? (
                            <TableRow><TableCell colSpan={7} className="py-8 text-center text-sm text-slate-500">No supplier credit has been applied yet.</TableCell></TableRow>
                          ) : appPg.pageItems.map((r) => {
                            const undone = r.status === "Reversed"
                            return (
                              <TableRow key={r.allocationId} className={undone ? "text-slate-400" : undefined}>
                                <TableCell className="whitespace-nowrap">{fmtDateTime(r.appliedDate)}</TableCell>
                                <TableCell>{r.supplierName ?? `Supplier ${r.supplierId}`}</TableCell>
                                <TableCell className="font-medium">{r.creditNumber}</TableCell>
                                <TableCell>
                                  {r.reference ?? `${r.documentType} #${r.documentId}`}
                                  {r.label && <span className="block text-xs text-slate-500">{r.label}</span>}
                                  {undone && r.reversalReason && <span className="block text-xs">Undone: {r.reversalReason}</span>}
                                </TableCell>
                                <TableCell className={undone ? "text-right tabular-nums line-through" : "text-right tabular-nums"}>{money(r.amount)}</TableCell>
                                <TableCell><Badge variant={undone ? "secondary" : "outline"}>{undone ? "Undone" : "Applied"}</Badge></TableCell>
                                <TableCell className="text-right">
                                  {canManage && !undone && (
                                    <Button size="sm" variant="outline" onClick={() => openReverse({ kind: "application", app: r })}>
                                      <Undo2 className="mr-1.5 h-4 w-4" /> Unapply
                                    </Button>
                                  )}
                                </TableCell>
                              </TableRow>
                            )
                          })}
                        </TableBody>
                      </Table>
                      <DataPagination {...appPg.paginationProps} />
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
                  primary={(r) => r.supplierName ?? `Supplier ${r.supplierId}`}
                  secondary={(r) => <span>{r.refundNumber} · {fmtDateTime(r.refundDate)}</span>}
                  trailing={(r) => r.status === "Reversed" ? <Badge variant="secondary">Reversed</Badge> : null}
                  highlights={(r) => [{ label: "Received", value: money(r.amount), accent: "emerald" }]}
                  details={(r) => [
                    { label: "Into", value: r.accountName || "—" },
                    { label: "Credit", value: r.creditNumbers || "—" },
                    { label: "Reason", value: r.reason || "—" },
                  ]}
                  actions={(r) => canManage && r.status === "Posted" ? (
                    <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openReverse({ kind: "refund", refund: r })}>
                      <Undo2 className="mr-1.5 h-4 w-4" /> Reverse refund
                    </Button>
                  ) : null}
                  emptyState={<div className="p-8 text-center text-sm text-slate-500">No supplier has sent money back.</div>}
                  desktopTable={
                    <>
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Refund</TableHead>
                            <TableHead>Date</TableHead>
                            <TableHead>Supplier</TableHead>
                            <TableHead className="text-right">Amount</TableHead>
                            <TableHead>Received into</TableHead>
                            <TableHead>Credit</TableHead>
                            <TableHead>Reason</TableHead>
                            <TableHead>Status</TableHead>
                            <TableHead className="text-right">Actions</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {refundPg.pageItems.length === 0 ? (
                            <TableRow><TableCell colSpan={9} className="py-8 text-center text-sm text-slate-500">No supplier has sent money back.</TableCell></TableRow>
                          ) : refundPg.pageItems.map((r) => {
                            const reversed = r.status === "Reversed"
                            return (
                              <TableRow key={r.refundId} className={reversed ? "text-slate-400" : undefined}>
                                <TableCell className={reversed ? "font-medium line-through" : "font-medium"}>{r.refundNumber}</TableCell>
                                <TableCell className="whitespace-nowrap">{fmtDateTime(r.refundDate)}</TableCell>
                                <TableCell>{r.supplierName ?? `Supplier ${r.supplierId}`}</TableCell>
                                <TableCell className={reversed ? "text-right tabular-nums line-through" : "text-right tabular-nums"}>{money(r.amount)}</TableCell>
                                <TableCell>{[r.accountName, r.paymentMethod].filter(Boolean).join(" · ") || "—"}</TableCell>
                                <TableCell className="whitespace-nowrap">{r.creditNumbers || "—"}</TableCell>
                                <TableCell className="max-w-[240px]">
                                  <span className="block truncate" title={r.reason}>{r.reason}</span>
                                  {reversed && <span className="block truncate text-xs">Reversed{r.reversalDate ? ` ${fmtDateTime(r.reversalDate)}` : ""}: {r.reversalReason}</span>}
                                </TableCell>
                                <TableCell><Badge variant={reversed ? "secondary" : "outline"}>{r.status}</Badge></TableCell>
                                <TableCell className="text-right">
                                  {canManage && !reversed && (
                                    <Button size="sm" variant="outline" onClick={() => openReverse({ kind: "refund", refund: r })}>
                                      <Undo2 className="mr-1.5 h-4 w-4" /> Reverse
                                    </Button>
                                  )}
                                </TableCell>
                              </TableRow>
                            )
                          })}
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

      {/* Phones: one supplier's credits, each with its own actions. */}
      <Dialog open={!!eventsFor} onOpenChange={(o) => { if (!o) setEventsFor(null) }}>
        <DialogContent className={cn(FORM_DIALOG_CONTENT, "sm:max-w-lg")}>
          <DialogHeader>
            <FormDialogTitle icon={Wallet} color="amber">{eventsFor?.supplierName}&apos;s credits</FormDialogTitle>
            <DialogDescription>Each credit, where it came from, and what is left of it.</DialogDescription>
          </DialogHeader>
          {eventsFor && (() => {
            const list = events[eventsFor.supplierId]
            if (list === undefined) return <div className="flex items-center gap-2 py-6 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
            if (list.length === 0) return <p className="py-4 text-sm text-slate-500">Nothing held any more.</p>
            return (
              <ul className="divide-y overflow-hidden rounded-xl border border-amber-200 bg-white">
                {list.map((e) => (
                  <li key={e.poultrySupplierPaymentId} className="space-y-2 p-3">
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0">
                        <p className="text-sm font-medium text-slate-900">{e.creditNumber} · {e.source}</p>
                        <p className="text-xs text-slate-500">{fmtDateTime(e.creditDate)}{e.reference ? ` · ${e.reference}` : ""}</p>
                      </div>
                      <div className="shrink-0 text-right">
                        <p className="text-sm font-semibold tabular-nums text-blue-700">{money(e.available)}</p>
                        <p className="text-[11px] text-slate-500">of {money(e.originalAmount)}</p>
                      </div>
                    </div>
                    <p className="text-xs text-slate-600">Applied {money(e.applied)} · Refunded {money(e.refunded)} · {e.status}</p>
                    <div className="flex gap-2">{eventActions(e, true)}</div>
                  </li>
                ))}
              </ul>
            )
          })()}
          <FormDialogFooter onCancel={() => setEventsFor(null)} cancelLabel="Close" />
        </DialogContent>
      </Dialog>

      <PaySupplierAdvanceDialog
        open={advanceOpen}
        currencyCode={currencyCode}
        onOpenChange={setAdvanceOpen}
        onPaid={(a) => {
          toast({ title: "Advance paid", description: `${money(a.amount)} to ${a.supplierName}, held as their credit. It shows in Cash Flow as money out.` })
          setAdvanceOpen(false); setTab("held"); void load()
        }}
      />
      <SupplierCreditDialog
        open={creditOpen}
        currencyCode={currencyCode}
        onOpenChange={setCreditOpen}
        onCreated={(c) => {
          toast({ title: "Credit added", description: `${money(c.amount)} ${SUPPLIER_CREDIT_KIND_LABEL[c.kind].toLowerCase()} from ${c.supplierName}. No cash moved.` })
          setCreditOpen(false); setTab("held"); void load()
        }}
      />
      <ApplySupplierCreditDialog
        credit={applyFor}
        currencyCode={currencyCode}
        onOpenChange={(o) => { if (!o) setApplyFor(null) }}
        onApplied={(a) => {
          toast({ title: "Credit applied", description: `${money(a.amount)} paid on ${a.reference}. No money moved.` })
          setApplyFor(null); void load()
        }}
      />
      <SupplierRefundDialog
        credit={refundFor}
        currencyCode={currencyCode}
        onOpenChange={(o) => { if (!o) setRefundFor(null) }}
        onRefunded={(r) => {
          toast({ title: "Refund recorded", description: `${money(r.amount)} came back from the supplier. It shows in Cash Flow as money in.` })
          setRefundFor(null); void load()
        }}
      />

      <Dialog open={!!reverse} onOpenChange={(o) => { if (!o && !reversing) setReverse(null) }}>
        <DialogContent className={cn(FORM_DIALOG_CONTENT, "sm:max-w-lg")}>
          <DialogHeader>
            <FormDialogTitle icon={Undo2} color="red">
              {reverse?.kind === "credit" ? `Reverse ${reverse.event.creditNumber}?`
                : reverse?.kind === "application" ? "Unapply this credit?"
                : reverse?.kind === "refund" ? `Reverse refund ${reverse.refund.refundNumber}?` : ""}
            </FormDialogTitle>
            <DialogDescription>It stays in the history, marked as reversed.</DialogDescription>
          </DialogHeader>
          {reverse && (
            <div className="min-w-0 space-y-4 text-sm">
              <p className="rounded-md border border-amber-200 bg-amber-50 p-2.5 text-amber-900">
                {reverse.kind === "credit" && (
                  reverse.event.poultryCashAccountId
                    ? <>The advance of <b>{money(reverse.event.originalAmount)}</b> is cancelled and <b>{reverse.event.accountName ?? "its account"}</b> goes back up by the same amount. Only continue if it was entered by mistake.</>
                    : <>The {reverse.event.source.toLowerCase()} of <b>{money(reverse.event.originalAmount)}</b> is cancelled. No cash moves.</>
                )}
                {reverse.kind === "application" && (
                  <><b>{money(reverse.app.amount)}</b> goes back on {reverse.app.creditNumber}, and {reverse.app.reference ?? "the item"} is owed again. No cash moves.</>
                )}
                {reverse.kind === "refund" && (
                  <>The credit gets <b>{money(reverse.refund.amount)}</b> back and <b>{reverse.refund.accountName ?? "the account"}</b> goes down by the same amount.
                  Only continue if the refund was entered by mistake or the money was returned to the supplier.</>
                )}
              </p>
              <FormSection title="Reason" color="slate" tinted columns={1}>
                <div className="min-w-0 space-y-1">
                  <Label htmlFor="sup-reverse-reason">Reason *</Label>
                  <ReasonSelect id="sup-reverse-reason" options={REVERSAL_REASONS} value={reason} onChange={setReason} />
                </div>
              </FormSection>
              {reverseError && <p className="rounded-md bg-red-50 p-2.5 text-red-700">{reverseError}</p>}
            </div>
          )}
          <FormDialogFooter onCancel={() => setReverse(null)} cancelDisabled={reversing}>
            <Button className={cn("px-6", FORM_DIALOG_PRIMARY.red)} onClick={doReverse} disabled={reversing || !reason.trim()}>
              {reversing && <Loader2 className="mr-2 h-4 w-4 animate-spin" />} {reverse?.kind === "application" ? "Unapply" : "Reverse"}
            </Button>
          </FormDialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
