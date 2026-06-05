"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { ListFilters } from "@/components/ui/list-filters"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Badge } from "@/components/ui/badge"
import { Plus, Loader2, Receipt, CheckCircle2, XCircle, Tag, Truck } from "lucide-react"
import Link from "next/link"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { SupplierSelect } from "@/components/water/supplier-select"
import { ExpenseSourceLink } from "@/components/water/expense-source-link"
import {
  listWaterExpenses, createWaterExpense, submitWaterExpense, approveWaterExpense, cancelWaterExpense,
  listWaterExpenseCategories, createWaterExpenseCategory,
  listWaterCashAccounts,
  listWaterDeliveryExpenses,
  type WaterExpense, type WaterExpenseInput, type WaterExpenseCategory, type WaterCashAccount,
  type WaterDeliveryExpense,
} from "@/lib/api/water"

// Migration 085 — unified Expenses ledger. The page now shows both regular
// WaterExpenses ("Direct") and per-delivery WaterDeliveryExpenses ("Delivery")
// — previously the latter were stored on driver returns and never surfaced
// here, which surprised operators who'd recorded Step 4 expenses but couldn't
// find them.
type UnifiedExpense =
  | { kind: "Direct";   row: WaterExpense }
  | { kind: "Delivery"; row: WaterDeliveryExpense }

function unifiedDate(e: UnifiedExpense): string {
  return e.kind === "Direct"
    ? e.row.expenseDate
    : (e.row.returnDate ?? e.row.createdAt)
}
function unifiedAmount(e: UnifiedExpense): number {
  return e.kind === "Direct" ? e.row.amount : e.row.amount
}
function unifiedStatus(e: UnifiedExpense): string {
  // Delivery expenses don't have their own approval lifecycle; their state
  // reflects whether the operator ticked "Approved" on the row + whether the
  // parent driver return has been reconciled.
  if (e.kind === "Direct") return e.row.status
  if (!e.row.isApproved) return "Draft"
  return e.row.returnStatus === "Reconciled" ? "Approved" : "Submitted"
}

const EMPTY: WaterExpenseInput = {
  waterExpenseCategoryId: 0,
  description: "",
  amount: 0,
  paidTo: "",
  supplierId: null,
  paymentMethod: "Cash",
  waterCashAccountId: null,
  notes: "",
}

// Display rule: prefer the joined supplierName (master list) and fall back
// to the legacy freetext paidTo. Auto-generated rows from Payroll set
// neither; their "paid to" reads from the SourceType via the Source column.
function paidToLabel(e: WaterExpense): string {
  return e.supplierName?.trim() || e.paidTo?.trim() || "—"
}

const STATUS_COLORS: Record<string, string> = {
  Draft: "bg-slate-100 text-slate-700",
  Submitted: "bg-blue-100 text-blue-700",
  Approved: "bg-green-100 text-green-700",
  Rejected: "bg-rose-100 text-rose-700",
  Cancelled: "bg-amber-100 text-amber-700",
}

export default function WaterExpensesPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [expenses, setExpenses] = useState<WaterExpense[]>([])
  const [deliveryExpenses, setDeliveryExpenses] = useState<WaterDeliveryExpense[]>([])
  const [categories, setCategories] = useState<WaterExpenseCategory[]>([])
  const [accounts, setAccounts] = useState<WaterCashAccount[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [loading, setLoading] = useState(true)
  const [statusFilter, setStatusFilter] = useState<string>("ALL")

  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<WaterExpenseInput>(EMPTY)
  const [saving, setSaving] = useState(false)

  const [catDlg, setCatDlg] = useState(false)
  const [newCatName, setNewCatName] = useState("")
  // Cancel target — opens the PromptDialog. Replaces the old window.prompt
  // (system-looking dialog operators kept dismissing by accident).
  const [cancelTarget, setCancelTarget] = useState<WaterExpense | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, statusFilter])

  async function load() {
    setLoading(true)
    try {
      // Pull both expense streams in parallel; delivery expenses always come
      // back unfiltered (status filter doesn't apply — they have no direct
      // approval lifecycle of their own). The client-side status filter below
      // hides/shows them as appropriate.
      const [es, des, cs, accs] = await Promise.all([
        listWaterExpenses(statusFilter === "ALL" ? undefined : { status: statusFilter }),
        listWaterDeliveryExpenses(),
        listWaterExpenseCategories(),
        listWaterCashAccounts(),
      ])
      setExpenses(es); setDeliveryExpenses(des); setCategories(cs); setAccounts(accs)
    } catch (e: any) { toast({ title: "Could not load expenses", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openNew() {
    setForm({ ...EMPTY, waterExpenseCategoryId: categories.find(c => c.isActive)?.waterExpenseCategoryId ?? 0 })
    setOpen(true)
  }

  async function save() {
    if (!form.waterExpenseCategoryId) return toast({ title: "Pick a category", variant: "destructive" })
    if (!form.amount || form.amount <= 0) return toast({ title: "Amount must be greater than zero", variant: "destructive" })
    if (form.paymentMethod !== "Credit" && !form.waterCashAccountId) return toast({ title: "Cash account required for non-credit expenses", variant: "destructive" })
    setSaving(true)
    try {
      await createWaterExpense(form)
      toast({ title: "Expense recorded as Draft" })
      setOpen(false); setForm(EMPTY); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function doAction(e: WaterExpense, action: "submit" | "approve") {
    try {
      if (action === "submit") await submitWaterExpense(e.waterExpenseId)
      if (action === "approve") await approveWaterExpense(e.waterExpenseId)
      toast({ title: `Expense ${action}d` })
      await load()
    } catch (err: any) { toast({ title: `${action} failed`, description: err?.message, variant: "destructive" }) }
  }

  async function confirmCancel(reason: string) {
    if (!cancelTarget) return
    try {
      await cancelWaterExpense(cancelTarget.waterExpenseId, reason || undefined)
      toast({ title: "Expense canceled" })
      setCancelTarget(null); await load()
    } catch (err: any) {
      toast({ title: "Cancel failed", description: err?.message, variant: "destructive" })
      throw err
    }
  }

  async function addCategory() {
    if (!newCatName.trim()) return
    try {
      await createWaterExpenseCategory({ name: newCatName.trim() })
      setNewCatName(""); setCatDlg(false); await load()
      toast({ title: "Category added" })
    } catch (e: any) { toast({ title: "Add failed", description: e?.message, variant: "destructive" }) }
  }

  // Merge both expense streams into a unified ledger sorted by date desc.
  // Delivery expenses are tagged kind:"Delivery" so the table can render a
  // distinct Source cell linking back to the driver return.
  const unifiedAll = useMemo<UnifiedExpense[]>(() => {
    const merged: UnifiedExpense[] = [
      ...expenses.map((row) => ({ kind: "Direct" as const, row })),
      ...deliveryExpenses.map((row) => ({ kind: "Delivery" as const, row })),
    ]
    // Sort by date desc; ties broken by id for deterministic order.
    merged.sort((a, b) => {
      const ad = unifiedDate(a), bd = unifiedDate(b)
      if (ad === bd) {
        const aid = a.kind === "Direct" ? a.row.waterExpenseId : a.row.waterDeliveryExpenseId
        const bid = b.kind === "Direct" ? b.row.waterExpenseId : b.row.waterDeliveryExpenseId
        return bid - aid
      }
      return ad < bd ? 1 : -1
    })
    return merged
  }, [expenses, deliveryExpenses])

  // Status filter only applies to direct expenses (delivery rows have no
  // direct approval lifecycle). When the filter is restrictive, hide delivery
  // rows whose derived status doesn't match.
  const unifiedFiltered = useMemo<UnifiedExpense[]>(() => {
    if (statusFilter === "ALL") return unifiedAll
    return unifiedAll.filter((e) => unifiedStatus(e) === statusFilter)
  }, [unifiedAll, statusFilter])

  const totals = useMemo(() => {
    const approved = unifiedFiltered
      .filter((e) => unifiedStatus(e) === "Approved")
      .reduce((s, e) => s + unifiedAmount(e), 0)
    return { approved, count: unifiedFiltered.length }
  }, [unifiedFiltered])

  // The original page used filterByDateAndSearch over WaterExpense; do the
  // same fields client-side on the unified list. Search hits category,
  // description, paid-to and notes for both kinds.
  const visibleExpenses = useMemo<UnifiedExpense[]>(() => {
    const s = search.trim().toLowerCase()
    return unifiedFiltered.filter((e) => {
      const d = unifiedDate(e).split("T")[0]
      if (dateFrom && d < dateFrom) return false
      if (dateTo   && d > dateTo)   return false
      if (!s) return true
      const haystack = e.kind === "Direct"
        ? [e.row.categoryName, e.row.description, e.row.paidTo, e.row.supplierName, e.row.notes]
        : [e.row.expenseCategory, e.row.description, e.row.driverName, e.row.vehicleNumber, e.row.notes]
      return haystack.some((v) => v?.toLowerCase().includes(s))
    })
  }, [unifiedFiltered, search, dateFrom, dateTo])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <Receipt className="h-6 w-6 text-sky-600" /> Water expenses
            </h1>
            <div className="flex gap-2">
              <Button variant="outline" onClick={() => setCatDlg(true)}><Tag className="h-4 w-4 mr-1" /> Categories</Button>
              <Button onClick={openNew}><Plus className="h-4 w-4 mr-1" /> Record expense</Button>
            </div>
          </div>

          {/* Prompt 2 Part 2 §3 — filters above score cards. */}
          <ListFilters
            search={search} setSearch={setSearch}
            dateFrom={dateFrom} setDateFrom={setDateFrom}
            dateTo={dateTo} setDateTo={setDateTo}
            searchPlaceholder="Search category, description, paid to or notes"
            extras={(
              <Select value={statusFilter} onValueChange={setStatusFilter}>
                <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="ALL">All statuses</SelectItem>
                  <SelectItem value="Draft">Draft</SelectItem>
                  <SelectItem value="Submitted">Submitted</SelectItem>
                  <SelectItem value="Approved">Approved</SelectItem>
                  <SelectItem value="Rejected">Rejected</SelectItem>
                  <SelectItem value="Cancelled">Cancelled</SelectItem>
                </SelectContent>
              </Select>
            )}
          />

          <div className="mt-3 mb-3 grid grid-cols-2 md:grid-cols-2 gap-3">
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Approved total</div><div className="text-xl font-semibold tabular-nums">{totals.approved.toFixed(2)}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Rows shown</div><div className="text-xl font-semibold">{totals.count}</div></CardContent></Card>
          </div>

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : unifiedAll.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No expenses {statusFilter !== "ALL" && `with status "${statusFilter}"`} yet.</div>
              ) : (
                <MobileCardList
                  items={visibleExpenses}
                  getKey={(e) => e.kind === "Direct" ? `exp-${e.row.waterExpenseId}` : `del-${e.row.waterDeliveryExpenseId}`}
                  primary={(e) => {
                    if (e.kind === "Direct") return `${e.row.categoryName ?? "—"} · ${e.row.amount.toFixed(2)}`
                    return `${e.row.expenseCategory} · ${e.row.amount.toFixed(2)}`
                  }}
                  secondary={(e) => (
                    <>
                      <span>{unifiedDate(e).split("T")[0]}</span>
                      <Badge className={STATUS_COLORS[unifiedStatus(e)] ?? ""}>{unifiedStatus(e)}</Badge>
                      <Badge variant="outline" className="text-[10px]">{e.kind === "Direct" ? "Direct" : "Delivery"}</Badge>
                    </>
                  )}
                  details={(e) => e.kind === "Direct" ? [
                    { label: "Date", value: e.row.expenseDate.split("T")[0] },
                    { label: "Category", value: e.row.categoryName ?? "—" },
                    { label: "Amount", value: e.row.amount.toFixed(2) },
                    { label: "Paid to", value: paidToLabel(e.row) },
                    { label: "Source",  value: <ExpenseSourceLink sourceType={e.row.sourceType} sourceId={e.row.sourceId} linkedWaterProductionBatchId={e.row.linkedWaterProductionBatchId} /> },
                    { label: "Method", value: e.row.paymentMethod },
                    { label: "Status", value: e.row.status },
                    { label: "Description", value: e.row.description ?? "—" },
                  ] : [
                    { label: "Date", value: unifiedDate(e).split("T")[0] },
                    { label: "Category", value: e.row.expenseCategory },
                    { label: "Amount", value: e.row.amount.toFixed(2) },
                    { label: "Paid to", value: e.row.driverName ?? "—" },
                    {
                      label: "Source",
                      value: e.row.waterDriverReturnId ? (
                        <Link
                          href={`/water-driver-returns/${e.row.waterDriverReturnId}`}
                          className="inline-flex items-center gap-1 text-rose-700 hover:underline"
                        >
                          <Truck className="h-3.5 w-3.5" /> Delivery #{e.row.waterDriverReturnId}
                        </Link>
                      ) : "Delivery",
                    },
                    { label: "Method", value: "—" },
                    { label: "Status", value: unifiedStatus(e) },
                    { label: "Description", value: e.row.description ?? "—" },
                  ]}
                  actions={(e) => {
                    // Delivery rows are read-only here — their lifecycle is
                    // governed by the parent driver return, which is where
                    // the operator should edit/cancel them.
                    if (e.kind !== "Direct") return null
                    const d = e.row
                    return (
                      <>
                        {d.status === "Draft" && (
                          <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => doAction(d, "submit")}>Submit</Button>
                        )}
                        {(d.status === "Draft" || d.status === "Submitted") && (
                          <Button size="sm" variant="outline" className="flex-1 h-10 text-green-700 border-green-200" onClick={() => doAction(d, "approve")}>
                            <CheckCircle2 className="h-4 w-4 mr-1" /> Approve
                          </Button>
                        )}
                        {d.status !== "Cancelled" && d.status !== "Rejected" && (
                          <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => setCancelTarget(d)}>
                            <XCircle className="h-4 w-4 mr-1" /> Cancel
                          </Button>
                        )}
                      </>
                    )
                  }}
                  desktopTable={
                    <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Date</TableHead>
                          <TableHead>Category</TableHead>
                          <TableHead>Description</TableHead>
                          <TableHead className="text-right">Amount</TableHead>
                          <TableHead>Paid to</TableHead>
                          <TableHead>Method</TableHead>
                          <TableHead>Source</TableHead>
                          <TableHead>Status</TableHead>
                          <TableHead className="text-right">Actions</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {visibleExpenses.map((e) => {
                          if (e.kind === "Direct") {
                            const d = e.row
                            return (
                              <TableRow key={`exp-${d.waterExpenseId}`}>
                                <TableCell className="whitespace-nowrap">{d.expenseDate.split("T")[0]}</TableCell>
                                <TableCell>{d.categoryName ?? "—"}</TableCell>
                                {/* Wrap long descriptions instead of ellipsis-truncating. */}
                                <TableCell className="max-w-sm whitespace-normal break-words align-top">{d.description ?? "—"}</TableCell>
                                <TableCell className="text-right tabular-nums">{d.amount.toFixed(2)}</TableCell>
                                <TableCell>{paidToLabel(d)}</TableCell>
                                <TableCell>{d.paymentMethod}</TableCell>
                                <TableCell className="whitespace-nowrap">
                                  <ExpenseSourceLink
                                    sourceType={d.sourceType}
                                    sourceId={d.sourceId}
                                    linkedWaterProductionBatchId={d.linkedWaterProductionBatchId}
                                  />
                                </TableCell>
                                <TableCell><Badge className={STATUS_COLORS[d.status] ?? ""}>{d.status}</Badge></TableCell>
                                <TableCell className="text-right">
                                  {d.status === "Draft" && <Button size="sm" variant="ghost" onClick={() => doAction(d, "submit")}>Submit</Button>}
                                  {(d.status === "Draft" || d.status === "Submitted") && <Button size="sm" variant="ghost" onClick={() => doAction(d, "approve")}><CheckCircle2 className="h-4 w-4 text-green-600" /></Button>}
                                  {d.status !== "Cancelled" && d.status !== "Rejected" && <Button size="sm" variant="ghost" onClick={() => setCancelTarget(d)}><XCircle className="h-4 w-4 text-rose-500" /></Button>}
                                </TableCell>
                              </TableRow>
                            )
                          }
                          // Delivery row — sourced from a driver return.
                          const d = e.row
                          const status = unifiedStatus(e)
                          return (
                            <TableRow key={`del-${d.waterDeliveryExpenseId}`} className="bg-rose-50/30">
                              <TableCell className="whitespace-nowrap">{unifiedDate(e).split("T")[0]}</TableCell>
                              <TableCell>{d.expenseCategory}</TableCell>
                              <TableCell className="max-w-sm whitespace-normal break-words align-top">{d.description ?? "—"}</TableCell>
                              <TableCell className="text-right tabular-nums">{d.amount.toFixed(2)}</TableCell>
                              <TableCell className="whitespace-nowrap">{d.driverName ?? "—"}</TableCell>
                              <TableCell>—</TableCell>
                              <TableCell className="whitespace-nowrap">
                                {d.waterDriverReturnId ? (
                                  <Link
                                    href={`/water-driver-returns/${d.waterDriverReturnId}`}
                                    className="inline-flex items-center gap-1 text-rose-700 hover:underline"
                                  >
                                    <Truck className="h-3.5 w-3.5" /> Delivery #{d.waterDriverReturnId}
                                  </Link>
                                ) : (
                                  <span className="inline-flex items-center gap-1 text-rose-700">
                                    <Truck className="h-3.5 w-3.5" /> Delivery
                                  </span>
                                )}
                              </TableCell>
                              <TableCell><Badge className={STATUS_COLORS[status] ?? ""}>{status}</Badge></TableCell>
                              <TableCell className="text-right text-xs text-slate-400">on return</TableCell>
                            </TableRow>
                          )
                        })}
                      </TableBody>
                    </Table>
                    </div>
                  }
                />
              )}
            </CardContent>
          </Card>
        </main>
      </div>

      {/* Create dialog */}
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Receipt className="w-5 h-5 text-blue-600" /> Record water expense
            </DialogTitle>
            <DialogDescription>Log a new expense for review and approval</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormSection title="Basics" color="indigo" columns={1}>
              <FormField label="Category *">
                <Select value={String(form.waterExpenseCategoryId)} onValueChange={(v) => setForm({ ...form, waterExpenseCategoryId: Number(v) })}>
                  <SelectTrigger><SelectValue placeholder="Pick category" /></SelectTrigger>
                  <SelectContent>
                    {categories.filter(c => c.isActive).map(c => <SelectItem key={c.waterExpenseCategoryId} value={String(c.waterExpenseCategoryId)}>{c.name}</SelectItem>)}
                  </SelectContent>
                </Select>
              </FormField>
            </FormSection>

            <FormSection title="Payment" color="amber">
              <FormField label="Amount *">
                <NumberInput min={0} step="0.01" value={form.amount} onChange={(e) => setForm({ ...form, amount: Number(e.target.value) || 0 })} />
              </FormField>
              <FormField label="Payment method">
                <Select value={form.paymentMethod} onValueChange={(v) => setForm({ ...form, paymentMethod: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="Cash">Cash</SelectItem>
                    {/* Value stays "MoMo" so existing DB rows / SP filters still match;
                        only the label changes to the more descriptive "Mobile Money" the
                        rest of the app uses (James 2026-05-27). */}
                    <SelectItem value="MoMo">Mobile Money</SelectItem>
                    <SelectItem value="Bank">Bank</SelectItem>
                    <SelectItem value="Card">Card</SelectItem>
                    <SelectItem value="Credit">Credit</SelectItem>
                    <SelectItem value="Mixed">Mixed</SelectItem>
                  </SelectContent>
                </Select>
              </FormField>
              <FormField label={`Cash account${form.paymentMethod !== "Credit" ? " *" : ""}`} full>
                <Select value={String(form.waterCashAccountId ?? "")} onValueChange={(v) => setForm({ ...form, waterCashAccountId: v ? Number(v) : null })}>
                  <SelectTrigger><SelectValue placeholder={form.paymentMethod === "Credit" ? "(not required for credit)" : "Pick account"} /></SelectTrigger>
                  <SelectContent>
                    {accounts.filter(a => a.isActive).map(a => <SelectItem key={a.waterCashAccountId} value={String(a.waterCashAccountId)}>{a.accountName} ({a.currentBalance.toFixed(2)})</SelectItem>)}
                  </SelectContent>
                </Select>
              </FormField>
            </FormSection>

            <FormSection title="Details" color="slate" columns={1}>
              <FormField label="Description">
                <Input value={form.description ?? ""} onChange={(e) => setForm({ ...form, description: e.target.value })} placeholder="e.g. Fuel for Truck 1" />
              </FormField>
              <FormField label="Paid to (Supplier)">
                <SupplierSelect
                  value={form.supplierId ?? null}
                  onChange={(id) => setForm({ ...form, supplierId: id })}
                  noneLabel="No supplier / Other (use freetext below)"
                />
              </FormField>
              {/* Freetext fallback for one-off payees not worth saving as a
                  supplier. Backend prefers the SupplierId join if both are
                  set, so writing here when a supplier is also picked is
                  harmless. */}
              <FormField label="Paid to (freetext, optional)">
                <Input
                  value={form.paidTo ?? ""}
                  onChange={(e) => setForm({ ...form, paidTo: e.target.value })}
                  placeholder="Used only if no supplier picked above"
                />
              </FormField>
              <FormField label="Notes">
                <Textarea value={form.notes ?? ""} onChange={(e) => setForm({ ...form, notes: e.target.value })} />
              </FormField>
            </FormSection>

            <div className="flex gap-3 justify-end pt-2">
              <Button type="button" onClick={() => setOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
              <Button onClick={save} disabled={saving}>
                {saving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : "Save as Draft"}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Categories dialog */}
      <Dialog open={catDlg} onOpenChange={setCatDlg}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Tag className="w-5 h-5 text-blue-600" /> Expense categories
            </DialogTitle>
            <DialogDescription>Manage the categories used to organise expenses</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormSection title="Existing categories" color="indigo" columns={1}>
              <div className="space-y-2 max-h-64 overflow-auto">
                {categories.map(c => (
                  <div key={c.waterExpenseCategoryId} className="flex items-center justify-between rounded border p-2">
                    <span>{c.name}</span>
                    {!c.isActive && <Badge variant="outline">inactive</Badge>}
                  </div>
                ))}
              </div>
            </FormSection>
            <FormSection title="Add new" color="green" columns={1}>
              <div className="flex gap-2">
                <Input value={newCatName} onChange={(e) => setNewCatName(e.target.value)} placeholder="New category name" />
                <Button onClick={addCategory}>Add</Button>
              </div>
            </FormSection>
          </div>
        </DialogContent>
      </Dialog>

      <PromptDialog
        open={!!cancelTarget}
        onOpenChange={(v) => { if (!v) setCancelTarget(null) }}
        title="Cancel expense"
        description={cancelTarget ? `Expense #${cancelTarget.waterExpenseId} will be moved to Cancelled. Optionally tell the team why.` : ""}
        label="Reason (optional)"
        placeholder="e.g. duplicate entry, wrong amount, supplier refunded…"
        confirmLabel="Cancel expense"
        confirmVariant="destructive"
        allowEmpty
        onSubmit={confirmCancel}
      />
    </div>
  )
}
