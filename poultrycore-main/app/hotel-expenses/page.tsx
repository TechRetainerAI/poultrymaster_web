"use client"
import { useEffect, useState, useMemo } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Loader2, Wallet, Plus, Tag, CheckCircle2, XCircle, Send } from "lucide-react"
import { PaginationControls } from "@/components/ui/pagination-controls"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listHotelExpenses, createHotelExpense, submitHotelExpense, approveHotelExpense, cancelHotelExpense,
  listHotelExpenseCategories, createHotelExpenseCategory,
  listHotelCashAccounts,
  type HotelExpense, type HotelExpenseCategory, type HotelCashAccount,
} from "@/lib/api/hotel"

const STATUS_COLORS: Record<string, string> = {
  Draft: "bg-slate-100 text-slate-700",
  Submitted: "bg-blue-100 text-blue-700",
  Approved: "bg-emerald-100 text-emerald-700",
  Rejected: "bg-rose-100 text-rose-700",
  Cancelled: "bg-amber-100 text-amber-700",
}

function todayLocal(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
}

export default function HotelExpensesPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [expenses, setExpenses] = useState<HotelExpense[]>([])
  const [categories, setCategories] = useState<HotelExpenseCategory[]>([])
  const [accounts, setAccounts] = useState<HotelCashAccount[]>([])
  const [loading, setLoading] = useState(true)

  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [statusFilter, setStatusFilter] = useState("ALL")
  const [page, setPage] = useState(1); const [pageSize, setPageSize] = useState(20)

  const [open, setOpen] = useState(false); const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({ category: "", description: "", amount: 0, expenseDate: "", vendor: "", notes: "", paymentMethod: "Cash", hotelCashAccountId: null as number | null, paidTo: "", hotelExpenseCategoryId: null as number | null })

  const [catDlg, setCatDlg] = useState(false); const [newCatName, setNewCatName] = useState("")
  const [cancelTarget, setCancelTarget] = useState<any>(null)
  const [cancelReason, setCancelReason] = useState("")

  useEffect(() => {
    if (!activeFarmType) return
    if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    load()
  }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try {
      const [es, cs, accs] = await Promise.all([listHotelExpenses(), listHotelExpenseCategories(), listHotelCashAccounts()])
      setExpenses(es); setCategories(cs); setAccounts(accs)
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openNew() {
    const firstCat = categories.find((c: any) => c.isActive ?? c.isactive ?? true) as any
    setForm({
      category: firstCat?.name ?? "", description: "", amount: 0, expenseDate: todayLocal(),
      vendor: "", notes: "", paymentMethod: "Cash", hotelCashAccountId: null, paidTo: "",
      hotelExpenseCategoryId: firstCat?.hotelExpenseCategoryId ?? firstCat?.hotelexpensecategoryid ?? null,
    })
    setOpen(true)
  }

  async function save() {
    if (!form.description.trim()) { toast({ title: "Description required", variant: "destructive" }); return }
    if (form.amount <= 0) { toast({ title: "Amount must be > 0", variant: "destructive" }); return }
    if (form.paymentMethod !== "Credit" && !form.hotelCashAccountId) { toast({ title: "Select a cash account", variant: "destructive" }); return }
    setSaving(true)
    try {
      await createHotelExpense(form)
      toast({ title: "Expense saved as Draft" })
      setOpen(false); await load()
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function doAction(e: any, action: "submit" | "approve") {
    const id = e.hotelExpenseId ?? e.hotelexpenseid
    try {
      if (action === "submit") await submitHotelExpense(id)
      if (action === "approve") await approveHotelExpense(id)
      toast({ title: `Expense ${action === "submit" ? "submitted" : "approved"}` })
      await load()
    } catch (err: any) { toast({ title: `${action} failed`, description: err?.message, variant: "destructive" }) }
  }

  async function confirmCancel() {
    if (!cancelTarget) return
    const id = cancelTarget.hotelExpenseId ?? cancelTarget.hotelexpenseid
    try {
      await cancelHotelExpense(id, cancelReason || undefined)
      toast({ title: "Expense cancelled" })
      setCancelTarget(null); setCancelReason(""); await load()
    } catch (e: any) { toast({ title: "Cancel failed", description: e?.message, variant: "destructive" }) }
  }

  async function addCategory() {
    if (!newCatName.trim()) return
    try {
      await createHotelExpenseCategory({ name: newCatName.trim() })
      setNewCatName(""); setCatDlg(false); await load()
      toast({ title: "Category added" })
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  // Filter
  const filtered = useMemo(() => {
    return expenses.filter((e: any) => {
      const status = e.status ?? e.Status ?? "Draft"
      if (statusFilter !== "ALL" && status !== statusFilter) return false
      const d = (e.expenseDate ?? e.expensedate ?? "").slice(0, 10)
      if (dateFrom && d < dateFrom) return false
      if (dateTo && d > dateTo) return false
      if (search) {
        const q = search.toLowerCase()
        const hay = [e.category, e.description, e.vendor, e.paidTo ?? e.paidto, e.notes].filter(Boolean).join(" ").toLowerCase()
        if (!hay.includes(q)) return false
      }
      return true
    })
  }, [expenses, statusFilter, dateFrom, dateTo, search])

  const paginatedItems = filtered.slice((page - 1) * pageSize, page * pageSize)

  const approvedTotal = filtered.filter((e: any) => (e.status ?? "Draft") === "Approved").reduce((s: number, e: any) => s + Number(e.amount ?? 0), 0)
  const statusCounts = { Draft: 0, Submitted: 0, Approved: 0, Cancelled: 0 }
  expenses.forEach((e: any) => { const s = e.status ?? "Draft"; if (s in statusCounts) (statusCounts as any)[s]++ })

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
          <div className="flex items-center gap-3">
            <Wallet className="h-6 w-6 text-violet-600" />
            <h1 className="text-2xl font-bold">Expenses</h1>
          </div>
          <div className="flex gap-2">
            <Button variant="outline" onClick={() => setCatDlg(true)}><Tag className="h-4 w-4 mr-1" /> Categories</Button>
            <Button onClick={openNew} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> Record Expense</Button>
          </div>
        </div>

        {/* Status filter badges */}
        <div className="flex gap-2 flex-wrap mb-3">
          {[{ s: "ALL", l: "All", c: expenses.length }, { s: "Draft", l: "Draft", c: statusCounts.Draft }, { s: "Submitted", l: "Submitted", c: statusCounts.Submitted }, { s: "Approved", l: "Approved", c: statusCounts.Approved }, { s: "Cancelled", l: "Cancelled", c: statusCounts.Cancelled }].map(f => (
            <Button key={f.s} variant={statusFilter === f.s ? "default" : "outline"} size="sm" onClick={() => { setStatusFilter(f.s); setPage(1) }} className={statusFilter === f.s ? "bg-violet-600" : ""}>
              {f.l} ({f.c})
            </Button>
          ))}
        </div>

        {/* Search and date filters */}
        <div className="flex gap-3 flex-wrap mb-3">
          <Input placeholder="Search category, description, vendor..." className="max-w-xs" value={search} onChange={(e) => { setSearch(e.target.value); setPage(1) }} />
          <Input type="date" value={dateFrom} onChange={(e) => { setDateFrom(e.target.value); setPage(1) }} className="w-40" />
          <Input type="date" value={dateTo} onChange={(e) => { setDateTo(e.target.value); setPage(1) }} className="w-40" />
        </div>

        {/* Summary cards */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4">
          <Card><CardContent className="p-3"><div className="text-xs text-slate-500">Approved Total</div><div className="text-xl font-bold text-emerald-700">{approvedTotal.toFixed(2)}</div></CardContent></Card>
          <Card><CardContent className="p-3"><div className="text-xs text-slate-500">Showing</div><div className="text-xl font-bold">{filtered.length}</div></CardContent></Card>
          <Card><CardContent className="p-3"><div className="text-xs text-slate-500">Pending Review</div><div className="text-xl font-bold text-blue-700">{statusCounts.Draft + statusCounts.Submitted}</div></CardContent></Card>
          <Card><CardContent className="p-3"><div className="text-xs text-slate-500">Categories</div><div className="text-xl font-bold">{categories.length}</div></CardContent></Card>
        </div>

        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
          <Card><CardContent className="p-0">
            <table className="w-full text-sm">
              <thead className="bg-slate-50 border-b"><tr>
                <th className="text-left p-3">Date</th>
                <th className="text-left p-3">Category</th>
                <th className="text-left p-3">Description</th>
                <th className="text-right p-3">Amount</th>
                <th className="text-left p-3">Paid To</th>
                <th className="text-left p-3">Method</th>
                <th className="text-left p-3">Account</th>
                <th className="text-left p-3">Status</th>
                <th className="text-right p-3">Actions</th>
              </tr></thead>
              <tbody>
                {paginatedItems.map((e: any) => {
                  const id = e.hotelExpenseId ?? e.hotelexpenseid
                  const status = e.status ?? "Draft"
                  const acct = accounts.find((a: any) => (a.hotelCashAccountId ?? a.hotelcashaccountid) === (e.hotelCashAccountId ?? e.hotelcashaccountid))
                  return (
                    <tr key={id} className="border-b hover:bg-slate-50">
                      <td className="p-3 whitespace-nowrap">{(e.expenseDate ?? e.expensedate)?.slice?.(0, 10)}</td>
                      <td className="p-3">{e.category}</td>
                      <td className="p-3 max-w-[200px] truncate">{e.description}</td>
                      <td className="p-3 text-right font-semibold">{Number(e.amount).toFixed(2)}</td>
                      <td className="p-3">{e.paidTo ?? e.paidto ?? e.vendor ?? "—"}</td>
                      <td className="p-3">{e.paymentMethod ?? e.paymentmethod ?? "Cash"}</td>
                      <td className="p-3 text-xs">{(acct as any)?.accountName ?? (acct as any)?.accountname ?? "—"}</td>
                      <td className="p-3"><Badge className={STATUS_COLORS[status] ?? ""}>{status}</Badge></td>
                      <td className="p-3 text-right whitespace-nowrap">
                        {status === "Draft" && <Button size="sm" variant="ghost" onClick={() => doAction(e, "submit")} title="Submit"><Send className="h-4 w-4 text-blue-600" /></Button>}
                        {(status === "Draft" || status === "Submitted") && <Button size="sm" variant="ghost" onClick={() => doAction(e, "approve")} title="Approve"><CheckCircle2 className="h-4 w-4 text-emerald-600" /></Button>}
                        {status !== "Cancelled" && status !== "Approved" && <Button size="sm" variant="ghost" onClick={() => setCancelTarget(e)} title="Cancel"><XCircle className="h-4 w-4 text-red-500" /></Button>}
                      </td>
                    </tr>
                  )
                })}
                {filtered.length === 0 && <tr><td colSpan={9} className="p-8 text-center text-slate-400">No expenses found.</td></tr>}
              </tbody>
            </table>
            <PaginationControls page={page} pageSize={pageSize} total={filtered.length} onPageChange={setPage} onPageSizeChange={(ps) => { setPageSize(ps); setPage(1) }} />
          </CardContent></Card>
        )}

        {/* Create Expense Dialog */}
        <Dialog open={open} onOpenChange={setOpen}>
          <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
            <DialogHeader>
              <DialogTitle className="flex items-center gap-2"><Wallet className="h-5 w-5 text-violet-600" /> Record Expense</DialogTitle>
              <DialogDescription>Log a new expense for review and approval</DialogDescription>
            </DialogHeader>
            <div className="space-y-4">
              <FormSection title="Expense Details" color="indigo" columns={1}>
                <FormField label="Expense date *">
                  <Input type="date" value={form.expenseDate} max={todayLocal()} onChange={(e) => setForm({ ...form, expenseDate: e.target.value })} />
                </FormField>
                <FormField label="Category *">
                  <Select value={form.hotelExpenseCategoryId ? String(form.hotelExpenseCategoryId) : undefined} onValueChange={(v) => {
                    const cat = categories.find((c: any) => (c.hotelExpenseCategoryId ?? c.hotelexpensecategoryid) === Number(v))
                    setForm({ ...form, hotelExpenseCategoryId: Number(v), category: (cat as any)?.name ?? "" })
                  }}>
                    <SelectTrigger><SelectValue placeholder="Pick category" /></SelectTrigger>
                    <SelectContent>
                      {categories.filter((c: any) => c.isActive ?? c.isactive ?? true).map((c: any) => <SelectItem key={c.hotelExpenseCategoryId ?? c.hotelexpensecategoryid} value={String(c.hotelExpenseCategoryId ?? c.hotelexpensecategoryid)}>{c.name}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </FormField>
                <FormField label="Description *">
                  <Input value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} placeholder="e.g. Laundry detergent" />
                </FormField>
              </FormSection>

              <FormSection title="Payment" color="amber">
                <FormField label="Amount *">
                  <Input type="number" min={0} step="0.01" value={form.amount || ""} onChange={(e) => setForm({ ...form, amount: Number(e.target.value) || 0 })} />
                </FormField>
                <FormField label="Payment method">
                  <Select value={form.paymentMethod} onValueChange={(v) => setForm({ ...form, paymentMethod: v })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="Cash">Cash</SelectItem>
                      <SelectItem value="MobileMoney">Mobile Money</SelectItem>
                      <SelectItem value="Bank">Bank Transfer</SelectItem>
                      <SelectItem value="Card">Card</SelectItem>
                      <SelectItem value="Credit">Credit (no cash account)</SelectItem>
                    </SelectContent>
                  </Select>
                </FormField>
                {form.paymentMethod !== "Credit" && (
                  <FormField label="Cash account (debit from) *" full>
                    <Select value={form.hotelCashAccountId ? String(form.hotelCashAccountId) : undefined} onValueChange={(v) => setForm({ ...form, hotelCashAccountId: Number(v) })}>
                      <SelectTrigger><SelectValue placeholder="Pick account to debit" /></SelectTrigger>
                      <SelectContent>
                        {accounts.filter((a: any) => a.isActive ?? a.isactive ?? true).map((a: any) => {
                          const purpose = a.purpose ?? null
                          const purposeLabel = purpose === "FrontDesk" ? " [Front Desk]" : purpose === "Expenses" ? " [Expenses]" : purpose === "POS" ? " [POS]" : purpose === "Payroll" ? " [Payroll]" : ""
                          return (
                            <SelectItem key={a.hotelCashAccountId ?? a.hotelcashaccountid} value={String(a.hotelCashAccountId ?? a.hotelcashaccountid)}>
                              {a.accountName ?? a.accountname}{purposeLabel} — Bal: {Number(a.currentBalance ?? a.currentbalance ?? 0).toFixed(2)}
                            </SelectItem>
                          )
                        })}
                      </SelectContent>
                    </Select>
                  </FormField>
                )}
              </FormSection>

              <FormSection title="Details" color="slate" columns={1}>
                <FormField label="Paid to / Vendor">
                  <Input value={form.paidTo} onChange={(e) => setForm({ ...form, paidTo: e.target.value })} placeholder="Supplier name" />
                </FormField>
                <FormField label="Notes">
                  <Textarea value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} />
                </FormField>
              </FormSection>

              <div className="flex gap-3 justify-end pt-2">
                <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
                <Button onClick={save} disabled={saving} className="bg-violet-600 hover:bg-violet-700">
                  {saving ? <><Loader2 className="h-4 w-4 mr-1 animate-spin" />Saving...</> : "Save as Draft"}
                </Button>
              </div>
            </div>
          </DialogContent>
        </Dialog>

        {/* Categories Dialog */}
        <Dialog open={catDlg} onOpenChange={setCatDlg}>
          <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
            <DialogHeader>
              <DialogTitle className="flex items-center gap-2"><Tag className="h-5 w-5 text-violet-600" /> Expense Categories</DialogTitle>
              <DialogDescription>Manage categories for hotel expenses</DialogDescription>
            </DialogHeader>
            <div className="space-y-4">
              <div className="space-y-2 max-h-64 overflow-auto">
                {categories.map((c: any) => (
                  <div key={c.hotelExpenseCategoryId ?? c.hotelexpensecategoryid} className="flex items-center justify-between rounded border p-2">
                    <span>{c.name}</span>
                    {!(c.isActive ?? c.isactive ?? true) && <Badge variant="outline">inactive</Badge>}
                  </div>
                ))}
                {categories.length === 0 && <div className="text-center text-slate-400 py-4">No categories yet</div>}
              </div>
              <div className="flex gap-2">
                <Input value={newCatName} onChange={(e) => setNewCatName(e.target.value)} placeholder="New category name" onKeyDown={(e) => e.key === "Enter" && addCategory()} />
                <Button onClick={addCategory} className="bg-violet-600 hover:bg-violet-700">Add</Button>
              </div>
            </div>
          </DialogContent>
        </Dialog>

        {/* Cancel Dialog */}
        <Dialog open={!!cancelTarget} onOpenChange={(v) => { if (!v) { setCancelTarget(null); setCancelReason("") } }}>
          <DialogContent>
            <DialogHeader><DialogTitle>Cancel Expense</DialogTitle></DialogHeader>
            <div className="space-y-3">
              <p className="text-sm text-slate-600">This expense will be marked as Cancelled.</p>
              <div><Label>Reason (optional)</Label><Input value={cancelReason} onChange={(e) => setCancelReason(e.target.value)} placeholder="e.g. duplicate entry" /></div>
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => { setCancelTarget(null); setCancelReason("") }}>Keep</Button>
              <Button variant="destructive" onClick={confirmCancel}>Cancel Expense</Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </main></div></div>
  )
}
