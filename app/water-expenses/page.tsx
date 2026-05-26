"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Badge } from "@/components/ui/badge"
import { Plus, Loader2, Receipt, AlertCircle, CheckCircle2, XCircle, Trash2, Tag } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterExpenses, createWaterExpense, submitWaterExpense, approveWaterExpense, cancelWaterExpense,
  listWaterExpenseCategories, createWaterExpenseCategory,
  listWaterCashAccounts,
  type WaterExpense, type WaterExpenseInput, type WaterExpenseCategory, type WaterCashAccount,
} from "@/lib/api/water"

const EMPTY: WaterExpenseInput = {
  waterExpenseCategoryId: 0,
  description: "",
  amount: 0,
  paidTo: "",
  paymentMethod: "Cash",
  waterCashAccountId: null,
  notes: "",
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
  const [categories, setCategories] = useState<WaterExpenseCategory[]>([])
  const [accounts, setAccounts] = useState<WaterCashAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [statusFilter, setStatusFilter] = useState<string>("ALL")

  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<WaterExpenseInput>(EMPTY)
  const [saving, setSaving] = useState(false)

  const [catDlg, setCatDlg] = useState(false)
  const [newCatName, setNewCatName] = useState("")

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, statusFilter])

  async function load() {
    setLoading(true); setError(null)
    try {
      const [es, cs, accs] = await Promise.all([
        listWaterExpenses(statusFilter === "ALL" ? undefined : { status: statusFilter }),
        listWaterExpenseCategories(),
        listWaterCashAccounts(),
      ])
      setExpenses(es); setCategories(cs); setAccounts(accs)
    } catch (e: any) { setError(e?.message ?? String(e)) }
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

  async function doAction(e: WaterExpense, action: "submit" | "approve" | "cancel") {
    try {
      if (action === "submit") await submitWaterExpense(e.waterExpenseId)
      if (action === "approve") await approveWaterExpense(e.waterExpenseId)
      if (action === "cancel") {
        const r = window.prompt("Reason for cancellation? (optional)") ?? undefined
        await cancelWaterExpense(e.waterExpenseId, r)
      }
      toast({ title: `Expense ${action}d` })
      await load()
    } catch (err: any) { toast({ title: `${action} failed`, description: err?.message, variant: "destructive" }) }
  }

  async function addCategory() {
    if (!newCatName.trim()) return
    try {
      await createWaterExpenseCategory({ name: newCatName.trim() })
      setNewCatName(""); setCatDlg(false); await load()
      toast({ title: "Category added" })
    } catch (e: any) { toast({ title: "Add failed", description: e?.message, variant: "destructive" }) }
  }

  const totals = useMemo(() => {
    const approved = expenses.filter(e => e.status === "Approved").reduce((s, e) => s + e.amount, 0)
    return { approved, count: expenses.length }
  }, [expenses])

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

          <div className="mb-3 grid grid-cols-2 md:grid-cols-4 gap-3">
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Approved total</div><div className="text-xl font-semibold tabular-nums">{totals.approved.toFixed(2)}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Rows shown</div><div className="text-xl font-semibold">{totals.count}</div></CardContent></Card>
            <Card className="md:col-span-2"><CardContent className="p-4 flex items-end gap-3">
              <div className="flex-1"><Label className="text-xs">Status filter</Label>
                <Select value={statusFilter} onValueChange={setStatusFilter}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="ALL">All</SelectItem>
                    <SelectItem value="Draft">Draft</SelectItem>
                    <SelectItem value="Submitted">Submitted</SelectItem>
                    <SelectItem value="Approved">Approved</SelectItem>
                    <SelectItem value="Rejected">Rejected</SelectItem>
                    <SelectItem value="Cancelled">Cancelled</SelectItem>
                  </SelectContent>
                </Select></div>
            </CardContent></Card>
          </div>

          {error && (
            <Card className="border-red-200 bg-red-50 mb-4">
              <CardContent className="flex items-center gap-2 p-3 text-red-700"><AlertCircle className="h-4 w-4" /> {error}</CardContent>
            </Card>
          )}

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : expenses.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No expenses {statusFilter !== "ALL" && `with status "${statusFilter}"`} yet.</div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Date</TableHead>
                      <TableHead>Category</TableHead>
                      <TableHead>Description</TableHead>
                      <TableHead className="text-right">Amount</TableHead>
                      <TableHead>Paid to</TableHead>
                      <TableHead>Method</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead className="text-right">Actions</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {expenses.map((e) => (
                      <TableRow key={e.waterExpenseId}>
                        <TableCell className="whitespace-nowrap">{e.expenseDate.split("T")[0]}</TableCell>
                        <TableCell>{e.categoryName ?? "—"}</TableCell>
                        <TableCell className="max-w-xs truncate">{e.description ?? "—"}</TableCell>
                        <TableCell className="text-right tabular-nums">{e.amount.toFixed(2)}</TableCell>
                        <TableCell>{e.paidTo ?? "—"}</TableCell>
                        <TableCell>{e.paymentMethod}</TableCell>
                        <TableCell><Badge className={STATUS_COLORS[e.status] ?? ""}>{e.status}</Badge></TableCell>
                        <TableCell className="text-right">
                          {e.status === "Draft" && <Button size="sm" variant="ghost" onClick={() => doAction(e, "submit")}>Submit</Button>}
                          {(e.status === "Draft" || e.status === "Submitted") && <Button size="sm" variant="ghost" onClick={() => doAction(e, "approve")}><CheckCircle2 className="h-4 w-4 text-green-600" /></Button>}
                          {e.status !== "Cancelled" && e.status !== "Rejected" && <Button size="sm" variant="ghost" onClick={() => doAction(e, "cancel")}><XCircle className="h-4 w-4 text-rose-500" /></Button>}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>
        </main>
      </div>

      {/* Create dialog */}
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle>Record water expense</DialogTitle></DialogHeader>
          <div className="grid grid-cols-2 gap-3">
            <div className="col-span-2"><Label>Category *</Label>
              <Select value={String(form.waterExpenseCategoryId)} onValueChange={(v) => setForm({ ...form, waterExpenseCategoryId: Number(v) })}>
                <SelectTrigger><SelectValue placeholder="Pick category" /></SelectTrigger>
                <SelectContent>
                  {categories.filter(c => c.isActive).map(c => <SelectItem key={c.waterExpenseCategoryId} value={String(c.waterExpenseCategoryId)}>{c.name}</SelectItem>)}
                </SelectContent>
              </Select></div>

            <div><Label>Amount *</Label>
              <Input type="number" min={0} step="0.01" value={form.amount} onChange={(e) => setForm({ ...form, amount: Number(e.target.value) || 0 })} /></div>
            <div><Label>Payment method</Label>
              <Select value={form.paymentMethod} onValueChange={(v) => setForm({ ...form, paymentMethod: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="Cash">Cash</SelectItem>
                  <SelectItem value="MoMo">MoMo</SelectItem>
                  <SelectItem value="Bank">Bank</SelectItem>
                  <SelectItem value="Card">Card</SelectItem>
                  <SelectItem value="Credit">Credit</SelectItem>
                  <SelectItem value="Mixed">Mixed</SelectItem>
                </SelectContent>
              </Select></div>

            <div className="col-span-2"><Label>Cash account {form.paymentMethod !== "Credit" && "*"}</Label>
              <Select value={String(form.waterCashAccountId ?? "")} onValueChange={(v) => setForm({ ...form, waterCashAccountId: v ? Number(v) : null })}>
                <SelectTrigger><SelectValue placeholder={form.paymentMethod === "Credit" ? "(not required for credit)" : "Pick account"} /></SelectTrigger>
                <SelectContent>
                  {accounts.filter(a => a.isActive).map(a => <SelectItem key={a.waterCashAccountId} value={String(a.waterCashAccountId)}>{a.accountName} ({a.currentBalance.toFixed(2)})</SelectItem>)}
                </SelectContent>
              </Select></div>

            <div className="col-span-2"><Label>Description</Label>
              <Input value={form.description ?? ""} onChange={(e) => setForm({ ...form, description: e.target.value })} placeholder="e.g. Fuel for Truck 1" /></div>
            <div className="col-span-2"><Label>Paid to</Label>
              <Input value={form.paidTo ?? ""} onChange={(e) => setForm({ ...form, paidTo: e.target.value })} /></div>
            <div className="col-span-2"><Label>Notes</Label>
              <Textarea value={form.notes ?? ""} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></div>
          </div>
          <div className="flex justify-end gap-2 pt-3">
            <Button variant="ghost" onClick={() => setOpen(false)}>Cancel</Button>
            <Button onClick={save} disabled={saving}>{saving ? "Saving…" : "Save as Draft"}</Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Categories dialog */}
      <Dialog open={catDlg} onOpenChange={setCatDlg}>
        <DialogContent>
          <DialogHeader><DialogTitle>Expense categories</DialogTitle></DialogHeader>
          <div className="space-y-2 max-h-64 overflow-auto">
            {categories.map(c => (
              <div key={c.waterExpenseCategoryId} className="flex items-center justify-between rounded border p-2">
                <span>{c.name}</span>
                {!c.isActive && <Badge variant="outline">inactive</Badge>}
              </div>
            ))}
          </div>
          <div className="flex gap-2 pt-2 border-t">
            <Input value={newCatName} onChange={(e) => setNewCatName(e.target.value)} placeholder="New category name" />
            <Button onClick={addCategory}>Add</Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}
