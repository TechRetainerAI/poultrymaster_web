"use client"
import { useEffect, useState, useMemo } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Loader2, Plus, Eye, Pencil, Trash2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import {
  listHotelSuppliers, createHotelSupplier, updateHotelSupplier, deleteHotelSupplier,
  getHotelSupplierBalanceSummary,
  type HotelSupplier, type HotelSupplierBalanceSummary,
} from "@/lib/api/hotel-suppliers"

const SUPPLIER_TYPES = ["ProductSupplier", "ServiceProvider", "Landlord", "UtilityProvider", "Contractor", "Other"]

export default function HotelSuppliersPage() {
  const router = useRouter(); const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [suppliers, setSuppliers] = useState<HotelSupplier[]>([])
  const [summary, setSummary] = useState<HotelSupplierBalanceSummary | null>(null)
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState("")
  const [open, setOpen] = useState(false); const [saving, setSaving] = useState(false)
  const [editing, setEditing] = useState<HotelSupplier | null>(null)
  const [form, setForm] = useState({ supplierName: "", supplierType: "ProductSupplier", phone: "", email: "", location: "", address: "", paymentTermDays: 0, openingBalance: 0, notes: "", isActive: true })
  const [delTarget, setDelTarget] = useState<HotelSupplier | null>(null)

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try { const [ss, sm] = await Promise.all([listHotelSuppliers(), getHotelSupplierBalanceSummary()]); setSuppliers(ss); setSummary(sm) }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openNew() { setEditing(null); setForm({ supplierName: "", supplierType: "ProductSupplier", phone: "", email: "", location: "", address: "", paymentTermDays: 0, openingBalance: 0, notes: "", isActive: true }); setOpen(true) }
  function openEdit(s: HotelSupplier) { setEditing(s); setForm({ supplierName: s.supplierName, supplierType: s.supplierType || "ProductSupplier", phone: s.phone || "", email: s.email || "", location: s.location || "", address: s.address || "", paymentTermDays: s.paymentTermDays, openingBalance: s.openingBalance, notes: s.notes || "", isActive: s.isActive }); setOpen(true) }

  async function save() {
    if (!form.supplierName.trim()) { toast({ title: "Name required", variant: "destructive" }); return }
    setSaving(true)
    try {
      if (editing) { await updateHotelSupplier(editing.hotelSupplierId, { ...form, farmId: "" }); toast({ title: "Supplier updated" }) }
      else { await createHotelSupplier({ ...form, farmId: "" }); toast({ title: "Supplier created" }) }
      setOpen(false); await load()
    } catch (e: any) { toast({ title: "Error", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function doDelete() { if (!delTarget) return; try { await deleteHotelSupplier(delTarget.hotelSupplierId); toast({ title: "Deleted" }); setDelTarget(null); await load() } catch (e: any) { toast({ title: "Error", description: e?.message, variant: "destructive" }) } }

  const filtered = useMemo(() => { if (!search) return suppliers; const s = search.toLowerCase(); return suppliers.filter(sp => sp.supplierName.toLowerCase().includes(s) || (sp.phone || "").includes(s)) }, [suppliers, search])
  const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })

  if (loading) return (<div className="flex h-screen"><DashboardSidebar /><div className="flex-1 flex flex-col"><DashboardHeader /><div className="flex-1 flex items-center justify-center"><Loader2 className="h-8 w-8 animate-spin text-muted-foreground" /></div></div></div>)

  return (
    <div className="flex h-screen"><DashboardSidebar /><div className="flex-1 flex flex-col overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-y-auto p-4 md:p-6 space-y-6">
        <div className="flex items-center justify-between"><h1 className="text-2xl font-bold">Suppliers</h1><Button onClick={openNew}><Plus className="h-4 w-4 mr-2" />New Supplier</Button></div>

        {summary && (<div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <Card><CardContent className="pt-6"><p className="text-sm text-muted-foreground">Total Suppliers</p><p className="text-2xl font-bold">{summary.totalSuppliers}</p></CardContent></Card>
          <Card><CardContent className="pt-6"><p className="text-sm text-muted-foreground">We Owe</p><p className="text-2xl font-bold text-amber-600">{summary.suppliersOwed} suppliers</p></CardContent></Card>
          <Card><CardContent className="pt-6"><p className="text-sm text-muted-foreground">Total Payable</p><p className="text-2xl font-bold text-red-600">{fmt(summary.totalBalance)}</p></CardContent></Card>
        </div>)}

        <Input placeholder="Search..." value={search} onChange={(e) => setSearch(e.target.value)} className="max-w-sm" />

        <Card><CardContent className="p-0"><div className="overflow-x-auto"><table className="w-full text-sm">
          <thead><tr className="border-b bg-muted/50">
            <th className="text-left p-3">Name</th><th className="text-left p-3">Type</th><th className="text-left p-3">Phone</th>
            <th className="text-right p-3">We Owe</th><th className="text-center p-3">Status</th><th className="text-right p-3">Actions</th>
          </tr></thead>
          <tbody>
            {filtered.length === 0 && <tr><td colSpan={6} className="text-center p-8 text-muted-foreground">No suppliers found</td></tr>}
            {filtered.map(s => (
              <tr key={s.hotelSupplierId} className="border-b hover:bg-muted/30">
                <td className="p-3 font-medium">{s.supplierName}</td>
                <td className="p-3"><Badge variant="outline">{s.supplierType}</Badge></td>
                <td className="p-3">{s.phone || "—"}</td>
                <td className="p-3 text-right font-mono"><span className={s.currentBalance > 0 ? "text-red-600 font-semibold" : ""}>{fmt(s.currentBalance)}</span></td>
                <td className="p-3 text-center">{s.currentBalance > 0 ? <Badge className="bg-amber-100 text-amber-700">Owed</Badge> : <Badge className="bg-emerald-100 text-emerald-700">OK</Badge>}</td>
                <td className="p-3 text-right space-x-1">
                  <Button size="sm" variant="ghost" onClick={() => router.push(`/hotel-suppliers/${s.hotelSupplierId}/ledger`)}><Eye className="h-4 w-4" /></Button>
                  <Button size="sm" variant="ghost" onClick={() => openEdit(s)}><Pencil className="h-4 w-4" /></Button>
                  <Button size="sm" variant="ghost" onClick={() => setDelTarget(s)}><Trash2 className="h-4 w-4 text-red-500" /></Button>
                </td>
              </tr>
            ))}
          </tbody>
        </table></div></CardContent></Card>

        <Dialog open={open} onOpenChange={setOpen}><DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader><DialogTitle>{editing ? "Edit Supplier" : "New Supplier"}</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <FormField label="Supplier Name *"><Input value={form.supplierName} onChange={(e) => setForm({ ...form, supplierName: e.target.value })} /></FormField>
            <FormField label="Type"><Select value={form.supplierType} onValueChange={(v) => setForm({ ...form, supplierType: v })}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent>{SUPPLIER_TYPES.map(t => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent></Select></FormField>
            <FormField label="Phone"><Input value={form.phone} onChange={(e) => setForm({ ...form, phone: e.target.value })} /></FormField>
            <FormField label="Email"><Input type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} /></FormField>
            <FormField label="Location"><Input value={form.location} onChange={(e) => setForm({ ...form, location: e.target.value })} /></FormField>
            <FormField label="Payment Terms (Days)"><Input type="number" value={form.paymentTermDays} onChange={(e) => setForm({ ...form, paymentTermDays: Number(e.target.value) })} /></FormField>
            {!editing && <FormField label="Opening Balance"><Input type="number" step="0.01" value={form.openingBalance} onChange={(e) => setForm({ ...form, openingBalance: Number(e.target.value) })} /></FormField>}
            <FormField label="Notes"><Textarea value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></FormField>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button><Button onClick={save} disabled={saving}>{saving && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}{editing ? "Update" : "Create"}</Button></DialogFooter>
        </DialogContent></Dialog>

        <Dialog open={!!delTarget} onOpenChange={() => setDelTarget(null)}><DialogContent>
          <DialogHeader><DialogTitle>Delete Supplier</DialogTitle><DialogDescription>Delete &quot;{delTarget?.supplierName}&quot;?</DialogDescription></DialogHeader>
          <DialogFooter><Button variant="outline" onClick={() => setDelTarget(null)}>Cancel</Button><Button variant="destructive" onClick={doDelete}>Delete</Button></DialogFooter>
        </DialogContent></Dialog>
      </main>
    </div></div>
  )
}
