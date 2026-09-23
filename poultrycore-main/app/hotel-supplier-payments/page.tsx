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
import { FormField } from "@/components/ui/form-section"
import { Textarea } from "@/components/ui/textarea"
import { Loader2, Plus, CheckCircle2, XCircle } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { listHotelSuppliers, listHotelSupplierPayments, createHotelSupplierPayment, approveHotelSupplierPayment, cancelHotelSupplierPayment, type HotelSupplier, type HotelSupplierPayment } from "@/lib/api/hotel-suppliers"
import { listHotelCashAccounts, type HotelCashAccount } from "@/lib/api/hotel"

const STATUS_COLORS: Record<string, string> = { Draft: "bg-slate-100 text-slate-700", Approved: "bg-emerald-100 text-emerald-700", Cancelled: "bg-red-100 text-red-700" }
const METHODS = ["Cash", "MoMo", "Bank", "Card"]
function todayLocal(): string { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}` }

export default function HotelSupplierPaymentsPage() {
  const router = useRouter(); const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [payments, setPayments] = useState<HotelSupplierPayment[]>([])
  const [suppliers, setSuppliers] = useState<HotelSupplier[]>([])
  const [accounts, setAccounts] = useState<HotelCashAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [statusFilter, setStatusFilter] = useState("ALL")
  const [open, setOpen] = useState(false); const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({ hotelSupplierId: 0, amount: 0, paymentMethod: "Cash", hotelCashAccountId: null as number | null, reference: "", paymentDate: todayLocal(), notes: "" })

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])

  async function load() { setLoading(true); try { const [ps, ss, accs] = await Promise.all([listHotelSupplierPayments(), listHotelSuppliers(), listHotelCashAccounts()]); setPayments(ps); setSuppliers(ss); setAccounts(accs) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setLoading(false) } }

  async function save() {
    if (!form.hotelSupplierId) { toast({ title: "Select a supplier", variant: "destructive" }); return }
    if (form.amount <= 0) { toast({ title: "Amount must be positive", variant: "destructive" }); return }
    setSaving(true)
    try { await createHotelSupplierPayment({ ...form, farmId: "" }); toast({ title: "Payment created as Draft. Approve to debit supplier balance and cash." }); setOpen(false); await load() }
    catch (e: any) { toast({ title: "Error", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function doApprove(id: number) { try { await approveHotelSupplierPayment(id); toast({ title: "Payment approved" }); await load() } catch (e: any) { toast({ title: "Error", description: e?.message, variant: "destructive" }) } }
  async function doCancel(id: number) { try { await cancelHotelSupplierPayment(id); toast({ title: "Payment cancelled" }); await load() } catch (e: any) { toast({ title: "Error", description: e?.message, variant: "destructive" }) } }

  const filtered = useMemo(() => statusFilter === "ALL" ? payments : payments.filter(p => p.status === statusFilter), [payments, statusFilter])
  const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  const fmtDate = (s: string) => new Date(s).toLocaleDateString()
  const selectedSupplier = suppliers.find(s => s.hotelSupplierId === form.hotelSupplierId)

  if (loading) return (<div className="flex h-screen"><DashboardSidebar /><div className="flex-1 flex flex-col"><DashboardHeader /><div className="flex-1 flex items-center justify-center"><Loader2 className="h-8 w-8 animate-spin text-muted-foreground" /></div></div></div>)

  return (
    <div className="flex h-screen"><DashboardSidebar /><div className="flex-1 flex flex-col overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-y-auto p-4 md:p-6 space-y-6">
        <div className="flex items-center justify-between"><h1 className="text-2xl font-bold">Supplier Payments</h1><Button onClick={() => { setForm({ hotelSupplierId: 0, amount: 0, paymentMethod: "Cash", hotelCashAccountId: null, reference: "", paymentDate: todayLocal(), notes: "" }); setOpen(true) }}><Plus className="h-4 w-4 mr-2" />Record Payment</Button></div>

        <Select value={statusFilter} onValueChange={setStatusFilter}><SelectTrigger className="w-40"><SelectValue /></SelectTrigger><SelectContent><SelectItem value="ALL">All</SelectItem><SelectItem value="Draft">Draft</SelectItem><SelectItem value="Approved">Approved</SelectItem><SelectItem value="Cancelled">Cancelled</SelectItem></SelectContent></Select>

        <Card><CardContent className="p-0"><div className="overflow-x-auto"><table className="w-full text-sm">
          <thead><tr className="border-b bg-muted/50"><th className="text-left p-3">#</th><th className="text-left p-3">Supplier</th><th className="text-left p-3">Date</th><th className="text-right p-3">Amount</th><th className="text-left p-3">Method</th><th className="text-center p-3">Status</th><th className="text-right p-3">Actions</th></tr></thead>
          <tbody>
            {filtered.length === 0 && <tr><td colSpan={7} className="text-center p-8 text-muted-foreground">No payments found</td></tr>}
            {filtered.map(p => (
              <tr key={p.hotelSupplierPaymentId} className="border-b hover:bg-muted/30">
                <td className="p-3">{p.hotelSupplierPaymentId}</td><td className="p-3 font-medium">{p.supplierName || "—"}</td>
                <td className="p-3">{fmtDate(p.paymentDate)}</td><td className="p-3 text-right font-mono">{fmt(p.amount)}</td>
                <td className="p-3">{p.paymentMethod}</td><td className="p-3 text-center"><Badge className={STATUS_COLORS[p.status] || ""}>{p.status}</Badge></td>
                <td className="p-3 text-right space-x-1">{p.status === "Draft" && (<><Button size="sm" variant="outline" onClick={() => doApprove(p.hotelSupplierPaymentId)}><CheckCircle2 className="h-4 w-4 mr-1" />Approve</Button><Button size="sm" variant="ghost" onClick={() => doCancel(p.hotelSupplierPaymentId)}><XCircle className="h-4 w-4 text-red-500" /></Button></>)}</td>
              </tr>
            ))}
          </tbody>
        </table></div></CardContent></Card>

        <Dialog open={open} onOpenChange={setOpen}><DialogContent className="max-w-lg">
          <DialogHeader><DialogTitle>Record Supplier Payment</DialogTitle><DialogDescription>Create a Draft payment. Approve to post to ledger and cash.</DialogDescription></DialogHeader>
          <div className="space-y-4">
            <FormField label="Supplier *"><Select value={form.hotelSupplierId ? String(form.hotelSupplierId) : ""} onValueChange={(v) => setForm({ ...form, hotelSupplierId: Number(v) })}><SelectTrigger><SelectValue placeholder="Select supplier" /></SelectTrigger><SelectContent>{suppliers.filter(s => s.isActive).map(s => <SelectItem key={s.hotelSupplierId} value={String(s.hotelSupplierId)}>{s.supplierName} {s.currentBalance > 0 ? `(owed ${fmt(s.currentBalance)})` : ""}</SelectItem>)}</SelectContent></Select></FormField>
            {selectedSupplier && selectedSupplier.currentBalance > 0 && <p className="text-sm text-amber-600">We owe them: {fmt(selectedSupplier.currentBalance)}</p>}
            <FormField label="Amount *"><Input type="number" step="0.01" value={form.amount || ""} onChange={(e) => setForm({ ...form, amount: Number(e.target.value) })} /></FormField>
            <FormField label="Payment Date"><Input type="date" value={form.paymentDate} onChange={(e) => setForm({ ...form, paymentDate: e.target.value })} /></FormField>
            <FormField label="Method"><Select value={form.paymentMethod} onValueChange={(v) => setForm({ ...form, paymentMethod: v })}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent>{METHODS.map(m => <SelectItem key={m} value={m}>{m}</SelectItem>)}</SelectContent></Select></FormField>
            <FormField label="Cash Account"><Select value={form.hotelCashAccountId ? String(form.hotelCashAccountId) : "none"} onValueChange={(v) => setForm({ ...form, hotelCashAccountId: v === "none" ? null : Number(v) })}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent><SelectItem value="none">No account</SelectItem>{accounts.map(a => <SelectItem key={a.hotelCashAccountId} value={String(a.hotelCashAccountId)}>{a.accountName}</SelectItem>)}</SelectContent></Select></FormField>
            <FormField label="Reference"><Input value={form.reference} onChange={(e) => setForm({ ...form, reference: e.target.value })} /></FormField>
            <FormField label="Notes"><Textarea value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></FormField>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button><Button onClick={save} disabled={saving}>{saving && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}Create Payment</Button></DialogFooter>
        </DialogContent></Dialog>
      </main>
    </div></div>
  )
}
