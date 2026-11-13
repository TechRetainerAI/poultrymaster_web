"use client"

export const dynamic = "force-dynamic"

import { Suspense, useEffect, useMemo, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { Check, DollarSign, Loader2, Plus } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useGenericModules } from "@/hooks/use-generic-modules"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  approveExpense, getExpenses, createExpense, getCashAccounts, getExpenseCategories, getSuppliers,
  type GenericExpense, type GenericCashAccount, type GenericExpenseCategory, type GenericSupplier,
} from "@/lib/api/generic"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { fmtDateTime } from "@/lib/utils/company-datetime"

const STATUS_FILTERS = ["All", "Draft", "Approved", "Rejected"] as const

const PAY_METHODS: Array<{ value: string; label: string }> = [
  { value: "Cash",   label: "Cash" },
  { value: "MoMo",   label: "Mobile Money" },
  { value: "Bank",   label: "Bank" },
  { value: "Card",   label: "Card" },
  { value: "Credit", label: "Credit" },
]

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}

function badgeClass(s: string) {
  switch (s) {
    case "Approved":  return "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"
    case "Rejected":  return "bg-rose-100 text-rose-800 hover:bg-rose-100"
    case "Submitted": return "bg-sky-100 text-sky-800 hover:bg-sky-100"
    case "Cancelled": return "bg-slate-100 text-slate-700 hover:bg-slate-100"
    default:          return "bg-slate-100 text-slate-800 hover:bg-slate-100"
  }
}

const EMPTY_FORM = {
  expenseDate: new Date().toISOString().slice(0, 10),
  genericExpenseCategoryId: "",
  description: "",
  amount: "0",
  paidTo: "",
  paymentMethod: "Cash",
  genericCashAccountId: "",
  genericSupplierId: "",
  notes: "",
}

function GenericExpensesPageInner() {
  const router = useRouter()
  const sp = useSearchParams()
  const status = sp.get("status") || "All"
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const modules = useGenericModules()
  const logout = useLogout()
  const { toast } = useToast()
  const [rows, setRows] = useState<GenericExpense[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [loading, setLoading] = useState(true)

  // Add expense dialog state
  const [addOpen, setAddOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [categories, setCategories] = useState<GenericExpenseCategory[]>([])
  const [suppliers, setSuppliers] = useState<GenericSupplier[]>([])
  const [cashAccounts, setCashAccounts] = useState<GenericCashAccount[]>([])
  const [optionsLoaded, setOptionsLoaded] = useState(false)
  const [form, setForm] = useState(EMPTY_FORM)

  const load = async () => {
    setLoading(true)
    try { setRows(await getExpenses(status === "All" ? null : status)) }
    catch (e: any) { toast({ title: "Could not load expenses", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router, status])

  // Load form options when dialog opens
  useEffect(() => {
    if (!addOpen || optionsLoaded) return
    let cancelled = false
    ;(async () => {
      try {
        const [cs, ss, as] = await Promise.all([getExpenseCategories(), getSuppliers(), getCashAccounts()])
        if (cancelled) return
        setCategories(cs); setSuppliers(ss); setCashAccounts(as)
        const expenseDefaultId = modules.businessSettings?.defaultExpenseCashAccountId
        const paymentDefaultId = modules.businessSettings?.defaultCashAccountForPayments
        const defaultAccount = (expenseDefaultId ? as.find((a) => a.genericCashAccountId === expenseDefaultId && a.isActive) : null)
          ?? (paymentDefaultId ? as.find((a) => a.genericCashAccountId === paymentDefaultId && a.isActive) : null)
        const firstCash = defaultAccount ?? as.find((a) => a.isActive)
        if (firstCash) setForm((f) => ({ ...f, genericCashAccountId: String(firstCash.genericCashAccountId) }))
        setOptionsLoaded(true)
      } catch (e: any) {
        if (!cancelled) toast({ title: "Could not load options", description: e?.message ?? String(e), variant: "destructive" })
      }
    })()
    return () => { cancelled = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [addOpen])

  const visibleRows = useMemo(
    () => filterByDateAndSearch(rows, {
      search, dateFrom, dateTo,
      searchKeys: ["categoryName", "description", "paidTo", "notes"],
      dateKey: "expenseDate",
    }),
    [rows, search, dateFrom, dateTo],
  )

  const onApprove = async (id: number) => {
    try {
      await approveExpense(id)
      toast({ title: `Expense #${id} approved.` })
      await load()
    } catch (e: any) {
      toast({ title: "Approve failed", description: e?.message ?? String(e), variant: "destructive" })
    }
  }

  const isCredit = form.paymentMethod === "Credit"
  const approvalThreshold = modules.businessSettings?.requireApprovalAboveAmount ?? null
  const amount = Number(form.amount) || 0
  const exceedsThreshold = approvalThreshold !== null && approvalThreshold > 0 && amount > approvalThreshold

  const isValid = useMemo(() => {
    if (amount <= 0) return false
    if (!form.genericExpenseCategoryId) return false
    if (isCredit && !form.genericSupplierId) return false
    if (!isCredit && !form.genericCashAccountId) return false
    return true
  }, [form, isCredit, amount])

  function openAddDialog() {
    setForm({ ...EMPTY_FORM, expenseDate: new Date().toISOString().slice(0, 10) })
    setAddOpen(true)
  }

  const onSave = async () => {
    if (!isValid) {
      toast({ title: "Fill required fields", description: isCredit ? "Credit expense needs a supplier." : "Non-credit expense needs a cash account.", variant: "destructive" })
      return
    }
    setSaving(true)
    try {
      const created = await createExpense({
        expenseDate: form.expenseDate,
        genericExpenseCategoryId: Number(form.genericExpenseCategoryId),
        genericSupplierId: isCredit ? Number(form.genericSupplierId) : (form.genericSupplierId ? Number(form.genericSupplierId) : null),
        description: form.description || null,
        amount: Number(form.amount) || 0,
        paidTo: form.paidTo || null,
        paymentMethod: form.paymentMethod,
        genericCashAccountId: isCredit ? null : Number(form.genericCashAccountId),
        notes: form.notes || null,
      })
      if (created) {
        toast({ title: `Expense #${created.genericExpenseId} created as Draft`, description: "Approve to charge cash or post to the supplier ledger." })
        setAddOpen(false)
        await load()
      }
    } catch (e: any) {
      toast({ title: "Could not create expense", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <DollarSign className="h-6 w-6 text-amber-600" /> Expenses
              </h1>
              <p className="text-sm text-slate-500">{rows.length} expense(s)</p>
            </div>
            <Button onClick={openAddDialog} className="w-full sm:w-auto h-11 sm:h-10"><Plus className="h-4 w-4 mr-1" />New expense</Button>
          </div>

          <div className="flex gap-1 mb-3 flex-wrap">
            {STATUS_FILTERS.map((s) => (
              <Button key={s} size="sm" variant={s === status ? "default" : "outline"}
                onClick={() => router.replace(s === "All" ? "/generic-expenses" : `/generic-expenses?status=${s}`)}>{s}</Button>
            ))}
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading...</div>
          ) : rows.length === 0 ? (
            <Card><CardContent className="py-8 text-center text-slate-500">No expenses yet.</CardContent></Card>
          ) : (
            <>
            <ListFilters
              search={search} setSearch={setSearch}
              dateFrom={dateFrom} setDateFrom={setDateFrom}
              dateTo={dateTo} setDateTo={setDateTo}
              searchPlaceholder="Search category, description, paid to or notes"
            />
            <Card>
              <CardContent className="p-0">
                <MobileCardList
                  items={visibleRows}
                  getKey={(e) => e.genericExpenseId}
                  primary={(e) => `#${e.genericExpenseId} · ${e.categoryName ?? e.description ?? "Expense"}`}
                  secondary={(e) => (
                    <>
                      <span>{fmtDateTime(e.expenseDate, e)}</span>
                      <span>·</span>
                      <span className="text-xs">{e.paymentMethod}</span>
                    </>
                  )}
                  trailing={(e) => <Badge className={badgeClass(e.status)}>{e.status}</Badge>}
                  details={(e) => [
                    { label: "Date", value: fmtDateTime(e.expenseDate, e) },
                    { label: "Category", value: e.categoryName ?? "–" },
                    { label: "Description", value: e.description ?? "–" },
                    { label: "Supplier", value: e.supplierName ?? "–" },
                    { label: "Paid via", value: e.paymentMethod },
                    { label: "Amount", value: fmt(e.amount) },
                  ]}
                  actions={(e) => (
                    <>
                      {(e.status === "Draft" || e.status === "Submitted") && (
                        <Button size="sm" variant="outline" className="flex-1 h-10 text-emerald-700 border-emerald-200" onClick={() => onApprove(e.genericExpenseId)}>
                          <Check className="h-4 w-4 mr-1" /> Approve
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
                          <TableHead>Category</TableHead>
                          <TableHead>Description</TableHead>
                          <TableHead>Supplier</TableHead>
                          <TableHead>Paid via</TableHead>
                          <TableHead className="text-right">Amount</TableHead>
                          <TableHead>Status</TableHead>
                          <TableHead></TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {visibleRows.map((e) => (
                          <TableRow key={e.genericExpenseId}>
                            <TableCell>#{e.genericExpenseId}</TableCell>
                            <TableCell>{fmtDateTime(e.expenseDate, e)}</TableCell>
                            <TableCell>{e.categoryName ?? "–"}</TableCell>
                            <TableCell>{e.description ?? "–"}</TableCell>
                            <TableCell>{e.supplierName ?? "–"}</TableCell>
                            <TableCell className="text-xs text-slate-500">{e.paymentMethod}</TableCell>
                            <TableCell className="text-right">{fmt(e.amount)}</TableCell>
                            <TableCell><Badge className={badgeClass(e.status)}>{e.status}</Badge></TableCell>
                            <TableCell>
                              {(e.status === "Draft" || e.status === "Submitted") && (
                                <Button size="sm" variant="default" className="bg-emerald-600 hover:bg-emerald-700" onClick={() => onApprove(e.genericExpenseId)}>
                                  <Check className="h-3 w-3 mr-1" />Approve
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
        </main>
      </div>

      {/* Add Expense Dialog (popup modal like poultry side) */}
      <Dialog open={addOpen} onOpenChange={setAddOpen}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <DollarSign className="w-5 h-5 text-amber-600" /> New expense
            </DialogTitle>
            <DialogDescription>Record a new expense. It will be created as Draft.</DialogDescription>
          </DialogHeader>

          {!optionsLoaded ? (
            <div className="flex items-center gap-2 text-slate-500 py-6 justify-center"><Loader2 className="h-4 w-4 animate-spin" /> Loading options…</div>
          ) : (
            <div className="space-y-3">
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <Label className="text-xs">Date</Label>
                  <Input type="date" value={form.expenseDate} onChange={(e) => setForm((f) => ({ ...f, expenseDate: e.target.value }))} />
                </div>
                <div>
                  <Label className="text-xs">Category *</Label>
                  <Select value={form.genericExpenseCategoryId} onValueChange={(v) => setForm((f) => ({ ...f, genericExpenseCategoryId: v }))}>
                    <SelectTrigger><SelectValue placeholder="Choose category…" /></SelectTrigger>
                    <SelectContent>
                      {categories.map((c) => <SelectItem key={c.genericExpenseCategoryId} value={String(c.genericExpenseCategoryId)}>{c.name}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
              </div>

              <div>
                <Label className="text-xs">Description</Label>
                <Input value={form.description} maxLength={500} onChange={(e) => setForm((f) => ({ ...f, description: e.target.value }))} placeholder="e.g. November rent, fuel for delivery, etc." />
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <Label className="text-xs">Amount *</Label>
                  <NumberInput step="0.01" min="0" value={form.amount} onChange={(e) => setForm((f) => ({ ...f, amount: e.target.value }))} />
                  {exceedsThreshold && (
                    <p className="text-xs text-amber-600 mt-1">
                      Exceeds approval threshold — will require manager approval.
                    </p>
                  )}
                </div>
                <div>
                  <Label className="text-xs">Paid to</Label>
                  <Input value={form.paidTo} maxLength={200} onChange={(e) => setForm((f) => ({ ...f, paidTo: e.target.value }))} placeholder="Optional payee name" />
                </div>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <Label className="text-xs">Payment method *</Label>
                  <Select value={form.paymentMethod} onValueChange={(v) => setForm((f) => ({ ...f, paymentMethod: v }))}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>{PAY_METHODS.map((p) => <SelectItem key={p.value} value={p.value}>{p.label}</SelectItem>)}</SelectContent>
                  </Select>
                </div>
                {!isCredit ? (
                  <div>
                    <Label className="text-xs">Cash account *</Label>
                    <Select value={form.genericCashAccountId} onValueChange={(v) => setForm((f) => ({ ...f, genericCashAccountId: v }))}>
                      <SelectTrigger><SelectValue placeholder="Pick account…" /></SelectTrigger>
                      <SelectContent>
                        {cashAccounts.filter((a) => a.isActive).map((a) => <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>{a.accountName} ({a.accountType})</SelectItem>)}
                      </SelectContent>
                    </Select>
                  </div>
                ) : (
                  <div>
                    <Label className="text-xs">Supplier (credit) *</Label>
                    <Select value={form.genericSupplierId} onValueChange={(v) => setForm((f) => ({ ...f, genericSupplierId: v }))}>
                      <SelectTrigger><SelectValue placeholder="Pick supplier…" /></SelectTrigger>
                      <SelectContent>
                        {suppliers.map((s) => <SelectItem key={s.genericSupplierId} value={String(s.genericSupplierId)}>{s.supplierName}</SelectItem>)}
                      </SelectContent>
                    </Select>
                  </div>
                )}
              </div>

              {!isCredit && (
                <div>
                  <Label className="text-xs">Supplier (optional)</Label>
                  <Select value={form.genericSupplierId || "none"} onValueChange={(v) => setForm((f) => ({ ...f, genericSupplierId: v === "none" ? "" : v }))}>
                    <SelectTrigger><SelectValue placeholder="Link to a supplier (optional)" /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="none">None</SelectItem>
                      {suppliers.map((s) => <SelectItem key={s.genericSupplierId} value={String(s.genericSupplierId)}>{s.supplierName}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
              )}

              <div>
                <Label className="text-xs">Notes</Label>
                <Textarea rows={2} value={form.notes} maxLength={1000} onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} />
              </div>

              <div className="flex justify-end gap-2 pt-2">
                <Button variant="outline" onClick={() => setAddOpen(false)}>Cancel</Button>
                <Button onClick={onSave} disabled={saving || !isValid}>
                  {saving && <Loader2 className="h-4 w-4 animate-spin mr-2" />}Create as Draft
                </Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}

export default function GenericExpensesPage() {
  return (
    <Suspense fallback={<div className="p-6 text-slate-500">Loading...</div>}>
      <GenericExpensesPageInner />
    </Suspense>
  )
}
