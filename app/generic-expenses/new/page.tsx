"use client"

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { ArrowLeft, DollarSign, Loader2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  createExpense, getCashAccounts, getExpenseCategories, getSuppliers,
  type GenericCashAccount, type GenericExpenseCategory, type GenericSupplier,
} from "@/lib/api/generic"

// Each entry is [stored-value, display-label]. We keep MoMo as the stored value
// so existing DB rows / generic-cash transactions keep matching, but show
// "Mobile Money" in the UI (James 2026-05-27).
const PAY_METHODS: Array<{ value: string; label: string }> = [
  { value: "Cash",   label: "Cash" },
  { value: "MoMo",   label: "Mobile Money" },
  { value: "Bank",   label: "Bank" },
  { value: "Card",   label: "Card" },
  { value: "Credit", label: "Credit" },
]

export default function NewGenericExpensePage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [categories, setCategories] = useState<GenericExpenseCategory[]>([])
  const [suppliers, setSuppliers] = useState<GenericSupplier[]>([])
  const [cashAccounts, setCashAccounts] = useState<GenericCashAccount[]>([])

  const [form, setForm] = useState({
    expenseDate: new Date().toISOString().slice(0, 10),
    genericExpenseCategoryId: "",
    description: "",
    amount: "0",
    paidTo: "",
    paymentMethod: "Cash",
    genericCashAccountId: "",
    genericSupplierId: "",
    notes: "",
  })

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    let cancelled = false
    ;(async () => {
      try {
        const [cs, ss, as] = await Promise.all([getExpenseCategories(), getSuppliers(), getCashAccounts()])
        if (cancelled) return
        setCategories(cs); setSuppliers(ss); setCashAccounts(as)
        const firstCash = as.find((a) => a.isActive)
        if (firstCash) setForm((f) => ({ ...f, genericCashAccountId: String(firstCash.genericCashAccountId) }))
      } catch (e: any) {
        if (!cancelled) toast({ title: "Could not load options", description: e?.message ?? String(e), variant: "destructive" })
      } finally { if (!cancelled) setLoading(false) }
    })()
    return () => { cancelled = true }
  }, [activeFarmType, router, toast])

  const isCredit = form.paymentMethod === "Credit"
  const isValid = useMemo(() => {
    const amt = Number(form.amount) || 0
    if (amt <= 0) return false
    if (!form.genericExpenseCategoryId) return false
    if (isCredit && !form.genericSupplierId) return false
    if (!isCredit && !form.genericCashAccountId) return false
    return true
  }, [form, isCredit])

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
        router.push("/generic-expenses?status=Draft")
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
          <Link href="/generic-expenses" className="inline-flex items-center text-sm text-slate-500 hover:text-slate-700 mb-2">
            <ArrowLeft className="h-3 w-3 mr-1" /> Back to expenses
          </Link>
          <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2 mb-4">
            <DollarSign className="h-6 w-6 text-amber-600" /> New expense
          </h1>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : (
            <Card className="max-w-3xl">
              <CardContent className="grid grid-cols-1 md:grid-cols-2 gap-3 pt-6">
                <div>
                  <Label>Date</Label>
                  <Input type="date" value={form.expenseDate} onChange={(e) => setForm((f) => ({ ...f, expenseDate: e.target.value }))} />
                </div>
                <div>
                  <Label>Category *</Label>
                  <Select value={form.genericExpenseCategoryId} onValueChange={(v) => setForm((f) => ({ ...f, genericExpenseCategoryId: v }))}>
                    <SelectTrigger><SelectValue placeholder="Choose category…" /></SelectTrigger>
                    <SelectContent>
                      {categories.map((c) => <SelectItem key={c.genericExpenseCategoryId} value={String(c.genericExpenseCategoryId)}>{c.name}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>

                <div className="md:col-span-2">
                  <Label>Description</Label>
                  <Input value={form.description} maxLength={500} onChange={(e) => setForm((f) => ({ ...f, description: e.target.value }))} placeholder="e.g. November rent, fuel for delivery, etc." />
                </div>

                <div>
                  <Label>Amount *</Label>
                  <Input type="number" step="0.01" min="0" value={form.amount} onChange={(e) => setForm((f) => ({ ...f, amount: e.target.value }))} />
                </div>
                <div>
                  <Label>Paid to</Label>
                  <Input value={form.paidTo} maxLength={200} onChange={(e) => setForm((f) => ({ ...f, paidTo: e.target.value }))} placeholder="Optional payee name" />
                </div>

                <div>
                  <Label>Payment method *</Label>
                  <Select value={form.paymentMethod} onValueChange={(v) => setForm((f) => ({ ...f, paymentMethod: v }))}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>{PAY_METHODS.map((p) => <SelectItem key={p.value} value={p.value}>{p.label}</SelectItem>)}</SelectContent>
                  </Select>
                </div>
                {!isCredit ? (
                  <div>
                    <Label>Cash account *</Label>
                    <Select value={form.genericCashAccountId} onValueChange={(v) => setForm((f) => ({ ...f, genericCashAccountId: v }))}>
                      <SelectTrigger><SelectValue placeholder="Pick account…" /></SelectTrigger>
                      <SelectContent>
                        {cashAccounts.filter((a) => a.isActive).map((a) => <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>{a.accountName} ({a.accountType})</SelectItem>)}
                      </SelectContent>
                    </Select>
                  </div>
                ) : (
                  <div>
                    <Label>Supplier (credit) *</Label>
                    <Select value={form.genericSupplierId} onValueChange={(v) => setForm((f) => ({ ...f, genericSupplierId: v }))}>
                      <SelectTrigger><SelectValue placeholder="Pick supplier…" /></SelectTrigger>
                      <SelectContent>
                        {suppliers.map((s) => <SelectItem key={s.genericSupplierId} value={String(s.genericSupplierId)}>{s.supplierName}</SelectItem>)}
                      </SelectContent>
                    </Select>
                  </div>
                )}

                <div className="md:col-span-2">
                  <Label>Notes</Label>
                  <Textarea rows={2} value={form.notes} maxLength={1000} onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} />
                </div>

                <div className="md:col-span-2 flex justify-end gap-2 pt-2">
                  <Button variant="outline" onClick={() => router.push("/generic-expenses")}>Cancel</Button>
                  <Button onClick={onSave} disabled={saving || !isValid}>
                    {saving && <Loader2 className="h-4 w-4 animate-spin mr-2" />}Create as Draft
                  </Button>
                </div>
              </CardContent>
            </Card>
          )}
        </main>
      </div>
    </div>
  )
}
