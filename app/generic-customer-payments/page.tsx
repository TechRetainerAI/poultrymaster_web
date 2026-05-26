"use client"

export const dynamic = "force-dynamic"

import { Suspense, useEffect, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog"
import { Check, CreditCard, Loader2, Plus, X } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  approveCustomerPayment, cancelCustomerPayment, createCustomerPayment, getCashAccounts, getCustomerPayments, getCustomers,
  type GenericCashAccount, type GenericCustomer, type GenericCustomerPayment,
} from "@/lib/api/generic"

const STATUS_FILTERS = ["All", "Draft", "Approved", "Cancelled"] as const
const PAY_METHODS = ["Cash", "MoMo", "Bank", "Card"]

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}

function badgeClass(s: string) {
  switch (s) {
    case "Approved":  return "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"
    case "Cancelled": return "bg-rose-100 text-rose-800 hover:bg-rose-100"
    default:          return "bg-slate-100 text-slate-800 hover:bg-slate-100"
  }
}

function GenericCustomerPaymentsPageInner() {
  const router = useRouter()
  const search = useSearchParams()
  const status = search.get("status") || "All"
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()

  const [rows, setRows] = useState<GenericCustomerPayment[]>([])
  const [customers, setCustomers] = useState<GenericCustomer[]>([])
  const [cashAccounts, setCashAccounts] = useState<GenericCashAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)

  const [form, setForm] = useState({
    genericCustomerId: "",
    amount: "0",
    paymentMethod: "Cash",
    genericCashAccountId: "",
    paymentDate: new Date().toISOString().slice(0, 10),
    notes: "",
  })

  const load = async () => {
    setLoading(true)
    try {
      const [ps, cs, as] = await Promise.all([
        getCustomerPayments(status === "All" ? null : status),
        getCustomers(),
        getCashAccounts(),
      ])
      setRows(ps); setCustomers(cs); setCashAccounts(as)
      const firstCash = as.find((a) => a.isActive)
      if (firstCash && !form.genericCashAccountId) setForm((f) => ({ ...f, genericCashAccountId: String(firstCash.genericCashAccountId) }))
    } catch (e: any) {
      toast({ title: "Could not load", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router, status])

  const onSave = async () => {
    if (!form.genericCustomerId) { toast({ title: "Pick a customer", variant: "destructive" }); return }
    const amount = Number(form.amount)
    if (!(amount > 0)) { toast({ title: "Amount must be greater than zero", variant: "destructive" }); return }
    setSaving(true)
    try {
      const created = await createCustomerPayment({
        genericCustomerId: Number(form.genericCustomerId),
        amount,
        paymentMethod: form.paymentMethod,
        genericCashAccountId: form.genericCashAccountId ? Number(form.genericCashAccountId) : null,
        paymentDate: form.paymentDate,
        notes: form.notes || null,
      })
      if (created) {
        toast({ title: "Customer payment created as Draft. Approve to update ledger + cash." })
        setOpen(false)
        setForm({ genericCustomerId: "", amount: "0", paymentMethod: "Cash", genericCashAccountId: form.genericCashAccountId, paymentDate: new Date().toISOString().slice(0, 10), notes: "" })
        await load()
      }
    } catch (e: any) {
      toast({ title: "Could not create payment", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  const onApprove = async (id: number) => {
    try { await approveCustomerPayment(id); toast({ title: `Payment #${id} approved.` }); await load() }
    catch (e: any) { toast({ title: "Approve failed", description: e?.message ?? String(e), variant: "destructive" }) }
  }

  const onCancel = async (id: number) => {
    try { await cancelCustomerPayment(id); toast({ title: `Payment #${id} cancelled.` }); await load() }
    catch (e: any) { toast({ title: "Cancel failed", description: e?.message ?? String(e), variant: "destructive" }) }
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
                <CreditCard className="h-6 w-6 text-emerald-600" /> Customer payments
              </h1>
              <p className="text-sm text-slate-500">{rows.length} payment(s) – money coming in from customers.</p>
            </div>
            <Dialog open={open} onOpenChange={setOpen}>
              <DialogTrigger asChild><Button><Plus className="h-4 w-4 mr-1" />Record payment</Button></DialogTrigger>
              <DialogContent>
                <DialogHeader>
                  <DialogTitle>New customer payment</DialogTitle>
                  <DialogDescription>Creates a Draft payment. Approval credits the customer&apos;s ledger and adds cash.</DialogDescription>
                </DialogHeader>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                  <div className="md:col-span-2">
                    <Label>Customer *</Label>
                    <Select value={form.genericCustomerId} onValueChange={(v) => setForm((f) => ({ ...f, genericCustomerId: v }))}>
                      <SelectTrigger><SelectValue placeholder="Pick customer..." /></SelectTrigger>
                      <SelectContent>{customers.map((c) => <SelectItem key={c.genericCustomerId} value={String(c.genericCustomerId)}>{c.customerName}{c.currentBalance > 0 ? ` – owes ${fmt(c.currentBalance)}` : ""}</SelectItem>)}</SelectContent>
                    </Select>
                  </div>
                  <div>
                    <Label>Date</Label>
                    <Input type="date" value={form.paymentDate} onChange={(e) => setForm((f) => ({ ...f, paymentDate: e.target.value }))} />
                  </div>
                  <div>
                    <Label>Amount *</Label>
                    <Input type="number" step="0.01" min="0" value={form.amount} onChange={(e) => setForm((f) => ({ ...f, amount: e.target.value }))} />
                  </div>
                  <div>
                    <Label>Method</Label>
                    <Select value={form.paymentMethod} onValueChange={(v) => setForm((f) => ({ ...f, paymentMethod: v }))}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>{PAY_METHODS.map((p) => <SelectItem key={p} value={p}>{p}</SelectItem>)}</SelectContent>
                    </Select>
                  </div>
                  <div>
                    <Label>Cash account (receives)</Label>
                    <Select value={form.genericCashAccountId || "__none__"} onValueChange={(v) => setForm((f) => ({ ...f, genericCashAccountId: v === "__none__" ? "" : v }))}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="__none__">– none –</SelectItem>
                        {cashAccounts.filter((a) => a.isActive).map((a) => <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>{a.accountName} ({a.accountType})</SelectItem>)}
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="md:col-span-2">
                    <Label>Notes</Label>
                    <Textarea rows={2} value={form.notes} onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} maxLength={1000} />
                  </div>
                </div>
                <DialogFooter>
                  <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
                  <Button onClick={onSave} disabled={saving}>{saving && <Loader2 className="h-4 w-4 animate-spin mr-2" />}Create</Button>
                </DialogFooter>
              </DialogContent>
            </Dialog>
          </div>

          <div className="flex gap-1 mb-3 flex-wrap">
            {STATUS_FILTERS.map((s) => (
              <Button key={s} size="sm" variant={s === status ? "default" : "outline"}
                onClick={() => router.replace(s === "All" ? "/generic-customer-payments" : `/generic-customer-payments?status=${s}`)}>{s}</Button>
            ))}
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading...</div>
          ) : rows.length === 0 ? (
            <Card><CardContent className="py-8 text-center text-slate-500">No customer payments yet.</CardContent></Card>
          ) : (
            <Card>
              <CardContent className="p-0">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>#</TableHead>
                      <TableHead>Date</TableHead>
                      <TableHead>Customer</TableHead>
                      <TableHead>Method</TableHead>
                      <TableHead className="text-right">Amount</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead></TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {rows.map((p) => (
                      <TableRow key={p.genericCustomerPaymentId}>
                        <TableCell>#{p.genericCustomerPaymentId}</TableCell>
                        <TableCell>{new Date(p.paymentDate).toLocaleDateString()}</TableCell>
                        <TableCell>{p.customerName ?? "–"}</TableCell>
                        <TableCell className="text-xs text-slate-500">{p.paymentMethod}</TableCell>
                        <TableCell className="text-right font-semibold text-emerald-700">{fmt(p.amount)}</TableCell>
                        <TableCell><Badge className={badgeClass(p.status)}>{p.status}</Badge></TableCell>
                        <TableCell className="flex gap-1">
                          {p.status === "Draft" && (
                            <>
                              <Button size="sm" className="bg-emerald-600 hover:bg-emerald-700" onClick={() => onApprove(p.genericCustomerPaymentId)}><Check className="h-3 w-3 mr-1" />Approve</Button>
                              <Button size="sm" variant="outline" onClick={() => onCancel(p.genericCustomerPaymentId)}><X className="h-3 w-3" /></Button>
                            </>
                          )}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </CardContent>
            </Card>
          )}
        </main>
      </div>
    </div>
  )
}

export default function GenericCustomerPaymentsPage() {
  return (
    <Suspense fallback={<div className="p-6 text-slate-500">Loading...</div>}>
      <GenericCustomerPaymentsPageInner />
    </Suspense>
  )
}
