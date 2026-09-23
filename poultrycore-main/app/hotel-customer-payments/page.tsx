"use client"
import { useEffect, useState, useMemo } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Textarea } from "@/components/ui/textarea"
import { Loader2, Plus, CheckCircle2, XCircle } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import {
  listHotelCustomers, listHotelCustomerPayments, createHotelCustomerPayment,
  approveHotelCustomerPayment, cancelHotelCustomerPayment,
  type HotelCustomer, type HotelCustomerPayment,
} from "@/lib/api/hotel-customers"
import { listHotelCashAccounts, type HotelCashAccount } from "@/lib/api/hotel"

const STATUS_COLORS: Record<string, string> = {
  Draft: "bg-slate-100 text-slate-700",
  Approved: "bg-emerald-100 text-emerald-700",
  Cancelled: "bg-red-100 text-red-700",
}

const METHODS = ["Cash", "MoMo", "Bank", "Card"]

function todayLocal(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
}

export default function HotelCustomerPaymentsPage() {
  const router = useRouter(); const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [payments, setPayments] = useState<HotelCustomerPayment[]>([])
  const [customers, setCustomers] = useState<HotelCustomer[]>([])
  const [accounts, setAccounts] = useState<HotelCashAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [statusFilter, setStatusFilter] = useState("ALL")

  const [open, setOpen] = useState(false); const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({
    hotelCustomerId: 0, amount: 0, paymentMethod: "Cash",
    hotelCashAccountId: null as number | null, reference: "", paymentDate: todayLocal(), notes: "",
  })

  useEffect(() => {
    if (!activeFarmType) return
    if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    load()
  }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try {
      const [ps, cs, accs] = await Promise.all([listHotelCustomerPayments(), listHotelCustomers(), listHotelCashAccounts()])
      setPayments(ps); setCustomers(cs); setAccounts(accs)
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openNew() {
    setForm({ hotelCustomerId: 0, amount: 0, paymentMethod: "Cash", hotelCashAccountId: null, reference: "", paymentDate: todayLocal(), notes: "" })
    setOpen(true)
  }

  async function save() {
    if (!form.hotelCustomerId) { toast({ title: "Select a customer", variant: "destructive" }); return }
    if (form.amount <= 0) { toast({ title: "Amount must be positive", variant: "destructive" }); return }
    setSaving(true)
    try {
      await createHotelCustomerPayment({ ...form, farmId: "" })
      toast({ title: "Payment created as Draft. Approve to debit customer balance." })
      setOpen(false); await load()
    } catch (e: any) { toast({ title: "Error", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function doApprove(id: number) {
    try { await approveHotelCustomerPayment(id); toast({ title: "Payment approved" }); await load() }
    catch (e: any) { toast({ title: "Error", description: e?.message, variant: "destructive" }) }
  }

  async function doCancel(id: number) {
    try { await cancelHotelCustomerPayment(id); toast({ title: "Payment cancelled" }); await load() }
    catch (e: any) { toast({ title: "Error", description: e?.message, variant: "destructive" }) }
  }

  const filtered = useMemo(() => {
    if (statusFilter === "ALL") return payments
    return payments.filter(p => p.status === statusFilter)
  }, [payments, statusFilter])

  const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  const fmtDate = (s: string) => new Date(s).toLocaleDateString()

  const selectedCustomer = customers.find(c => c.hotelCustomerId === form.hotelCustomerId)

  if (loading) return (
    <div className="flex h-screen"><DashboardSidebar /><div className="flex-1 flex flex-col"><DashboardHeader />
      <div className="flex-1 flex items-center justify-center"><Loader2 className="h-8 w-8 animate-spin text-muted-foreground" /></div>
    </div></div>
  )

  return (
    <div className="flex h-screen">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 md:p-6 space-y-6">
          <div className="flex items-center justify-between">
            <h1 className="text-2xl font-bold">Customer Payments</h1>
            <Button onClick={openNew}><Plus className="h-4 w-4 mr-2" />Record Payment</Button>
          </div>

          {/* Filters */}
          <div className="flex gap-4">
            <Select value={statusFilter} onValueChange={setStatusFilter}>
              <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="ALL">All</SelectItem>
                <SelectItem value="Draft">Draft</SelectItem>
                <SelectItem value="Approved">Approved</SelectItem>
                <SelectItem value="Cancelled">Cancelled</SelectItem>
              </SelectContent>
            </Select>
          </div>

          {/* Table */}
          <Card>
            <CardContent className="p-0">
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead><tr className="border-b bg-muted/50">
                    <th className="text-left p-3">#</th>
                    <th className="text-left p-3">Customer</th>
                    <th className="text-left p-3">Date</th>
                    <th className="text-right p-3">Amount</th>
                    <th className="text-left p-3">Method</th>
                    <th className="text-center p-3">Status</th>
                    <th className="text-right p-3">Actions</th>
                  </tr></thead>
                  <tbody>
                    {filtered.length === 0 && (
                      <tr><td colSpan={7} className="text-center p-8 text-muted-foreground">No payments found</td></tr>
                    )}
                    {filtered.map((p, idx) => (
                      <tr key={p.hotelCustomerPaymentId ?? idx} className="border-b hover:bg-muted/30">
                        <td className="p-3">{p.hotelCustomerPaymentId}</td>
                        <td className="p-3 font-medium">{p.customerName || "—"}</td>
                        <td className="p-3">{fmtDate(p.paymentDate)}</td>
                        <td className="p-3 text-right font-mono">{fmt(p.amount)}</td>
                        <td className="p-3">{p.paymentMethod}</td>
                        <td className="p-3 text-center"><Badge className={STATUS_COLORS[p.status] || ""}>{p.status}</Badge></td>
                        <td className="p-3 text-right space-x-1">
                          {p.status === "Draft" && (
                            <span className="inline-flex gap-1">
                              <Button size="sm" variant="outline" onClick={() => doApprove(p.hotelCustomerPaymentId)}><CheckCircle2 className="h-4 w-4 mr-1" />Approve</Button>
                              <Button size="sm" variant="ghost" onClick={() => doCancel(p.hotelCustomerPaymentId)}><XCircle className="h-4 w-4 text-red-500" /></Button>
                            </span>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </CardContent>
          </Card>

          {/* Create Payment Dialog */}
          <Dialog open={open} onOpenChange={setOpen}>
            <DialogContent className="max-w-lg">
              <DialogHeader>
                <DialogTitle>Record Customer Payment</DialogTitle>
                <DialogDescription>Create a Draft payment. Approve to post to the ledger and cash account.</DialogDescription>
              </DialogHeader>
              <div className="space-y-4">
                <FormField label="Customer *">
                  <Select value={form.hotelCustomerId ? String(form.hotelCustomerId) : ""} onValueChange={(v) => setForm({ ...form, hotelCustomerId: Number(v) })}>
                    <SelectTrigger><SelectValue placeholder="Select customer" /></SelectTrigger>
                    <SelectContent>
                      {customers.filter(c => c.isActive).map(c => (
                        <SelectItem key={c.hotelCustomerId} value={String(c.hotelCustomerId)}>
                          {c.customerName} {c.currentBalance > 0 ? `(owes ${fmt(c.currentBalance)})` : ""}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </FormField>
                {selectedCustomer && selectedCustomer.currentBalance > 0 && (
                  <p className="text-sm text-amber-600">Current balance owed: {fmt(selectedCustomer.currentBalance)}</p>
                )}
                <FormField label="Amount *">
                  <Input type="number" step="0.01" value={form.amount || ""} onChange={(e) => setForm({ ...form, amount: Number(e.target.value) })} />
                </FormField>
                <FormField label="Payment Date">
                  <Input type="date" value={form.paymentDate} onChange={(e) => setForm({ ...form, paymentDate: e.target.value })} />
                </FormField>
                <FormField label="Payment Method">
                  <Select value={form.paymentMethod} onValueChange={(v) => setForm({ ...form, paymentMethod: v })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {METHODS.map(m => <SelectItem key={m} value={m}>{m}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </FormField>
                <FormField label="Cash Account">
                  <Select value={form.hotelCashAccountId ? String(form.hotelCashAccountId) : "none"} onValueChange={(v) => setForm({ ...form, hotelCashAccountId: v === "none" ? null : Number(v) })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="none">No account</SelectItem>
                      {accounts.map(a => <SelectItem key={a.hotelCashAccountId} value={String(a.hotelCashAccountId)}>{a.accountName}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </FormField>
                <FormField label="Reference">
                  <Input value={form.reference} onChange={(e) => setForm({ ...form, reference: e.target.value })} />
                </FormField>
                <FormField label="Notes">
                  <Textarea value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} />
                </FormField>
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
                <Button onClick={save} disabled={saving}>{saving && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}Create Payment</Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </main>
      </div>
    </div>
  )
}
