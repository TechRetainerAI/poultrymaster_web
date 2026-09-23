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
import { Loader2, Users, Plus, Eye, Pencil, Trash2, Receipt } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listHotelCustomers, createHotelCustomer, updateHotelCustomer, deleteHotelCustomer,
  getHotelCustomerBalanceSummary,
  type HotelCustomer, type HotelCustomerBalanceSummary,
} from "@/lib/api/hotel-customers"

const CUSTOMER_TYPES = ["Corporate", "TravelAgent", "Government", "Individual", "Other"]

export default function HotelCustomersPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [customers, setCustomers] = useState<HotelCustomer[]>([])
  const [summary, setSummary] = useState<HotelCustomerBalanceSummary | null>(null)
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState("")

  const [open, setOpen] = useState(false); const [saving, setSaving] = useState(false)
  const [editing, setEditing] = useState<HotelCustomer | null>(null)
  const [form, setForm] = useState({
    customerName: "", customerType: "Corporate", phone: "", email: "",
    address: "", city: "", paymentTermDays: 0, creditLimit: 0,
    openingBalance: 0, notes: "", isActive: true,
  })

  const [delTarget, setDelTarget] = useState<HotelCustomer | null>(null)

  useEffect(() => {
    if (!activeFarmType) return
    if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    load()
  }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try {
      const [cs, s] = await Promise.all([listHotelCustomers(), getHotelCustomerBalanceSummary()])
      setCustomers(cs); setSummary(s)
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openNew() {
    setEditing(null)
    setForm({ customerName: "", customerType: "Corporate", phone: "", email: "", address: "", city: "", paymentTermDays: 0, creditLimit: 0, openingBalance: 0, notes: "", isActive: true })
    setOpen(true)
  }

  function openEdit(c: HotelCustomer) {
    setEditing(c)
    setForm({
      customerName: c.customerName, customerType: c.customerType || "Corporate",
      phone: c.phone || "", email: c.email || "", address: c.address || "", city: c.city || "",
      paymentTermDays: c.paymentTermDays, creditLimit: c.creditLimit,
      openingBalance: c.openingBalance, notes: c.notes || "", isActive: c.isActive,
    })
    setOpen(true)
  }

  async function save() {
    if (!form.customerName.trim()) { toast({ title: "Name required", variant: "destructive" }); return }
    setSaving(true)
    try {
      if (editing) {
        await updateHotelCustomer(editing.hotelCustomerId, { ...form, farmId: "" })
        toast({ title: "Customer updated" })
      } else {
        await createHotelCustomer({ ...form, farmId: "" })
        toast({ title: "Customer created" })
      }
      setOpen(false); await load()
    } catch (e: any) { toast({ title: "Error", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function doDelete() {
    if (!delTarget) return
    try {
      await deleteHotelCustomer(delTarget.hotelCustomerId)
      toast({ title: "Customer deleted" })
      setDelTarget(null); await load()
    } catch (e: any) { toast({ title: "Error", description: e?.message, variant: "destructive" }) }
  }

  const filtered = useMemo(() => {
    if (!search) return customers
    const s = search.toLowerCase()
    return customers.filter(c =>
      c.customerName.toLowerCase().includes(s) ||
      (c.phone || "").toLowerCase().includes(s) ||
      (c.email || "").toLowerCase().includes(s) ||
      (c.customerType || "").toLowerCase().includes(s)
    )
  }, [customers, search])

  const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })

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
            <h1 className="text-2xl font-bold">Customers</h1>
            <Button onClick={openNew}><Plus className="h-4 w-4 mr-2" />New Customer</Button>
          </div>

          {/* Summary Cards */}
          {summary && (
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
              <Card><CardContent className="pt-6"><p className="text-sm text-muted-foreground">Total Customers</p><p className="text-2xl font-bold">{summary.totalCustomers}</p></CardContent></Card>
              <Card><CardContent className="pt-6"><p className="text-sm text-muted-foreground">Customers Owing</p><p className="text-2xl font-bold text-amber-600">{summary.customersOwing}</p></CardContent></Card>
              <Card><CardContent className="pt-6"><p className="text-sm text-muted-foreground">Total Balance Owed</p><p className="text-2xl font-bold text-red-600">{fmt(summary.totalBalance)}</p></CardContent></Card>
            </div>
          )}

          {/* Search */}
          <div className="flex gap-4">
            <Input placeholder="Search by name, phone, email..." value={search} onChange={(e) => setSearch(e.target.value)} className="max-w-sm" />
          </div>

          {/* Table */}
          <Card>
            <CardContent className="p-0">
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead><tr className="border-b bg-muted/50">
                    <th className="text-left p-3">Name</th>
                    <th className="text-left p-3">Type</th>
                    <th className="text-left p-3">Phone</th>
                    <th className="text-left p-3">Email</th>
                    <th className="text-right p-3">Balance</th>
                    <th className="text-center p-3">Status</th>
                    <th className="text-right p-3">Actions</th>
                  </tr></thead>
                  <tbody>
                    {filtered.length === 0 && (
                      <tr><td colSpan={7} className="text-center p-8 text-muted-foreground">No customers found</td></tr>
                    )}
                    {filtered.map(c => (
                      <tr key={c.hotelCustomerId} className="border-b hover:bg-muted/30">
                        <td className="p-3 font-medium">{c.customerName}</td>
                        <td className="p-3"><Badge variant="outline">{c.customerType}</Badge></td>
                        <td className="p-3">{c.phone || "—"}</td>
                        <td className="p-3">{c.email || "—"}</td>
                        <td className="p-3 text-right font-mono">
                          <span className={c.currentBalance > 0 ? "text-red-600 font-semibold" : ""}>
                            {fmt(c.currentBalance)}
                          </span>
                        </td>
                        <td className="p-3 text-center">
                          {c.currentBalance > 0
                            ? <Badge className="bg-amber-100 text-amber-700">Owed</Badge>
                            : c.isActive
                              ? <Badge className="bg-emerald-100 text-emerald-700">OK</Badge>
                              : <Badge className="bg-slate-100 text-slate-700">Inactive</Badge>
                          }
                        </td>
                        <td className="p-3 text-right space-x-1">
                          <Button size="sm" variant="ghost" onClick={() => router.push(`/hotel-customers/${c.hotelCustomerId}/ledger`)}><Eye className="h-4 w-4" /></Button>
                          <Button size="sm" variant="ghost" onClick={() => openEdit(c)}><Pencil className="h-4 w-4" /></Button>
                          <Button size="sm" variant="ghost" onClick={() => setDelTarget(c)}><Trash2 className="h-4 w-4 text-red-500" /></Button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </CardContent>
          </Card>

          {/* Create/Edit Dialog */}
          <Dialog open={open} onOpenChange={setOpen}>
            <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
              <DialogHeader>
                <DialogTitle>{editing ? "Edit Customer" : "New Customer"}</DialogTitle>
                <DialogDescription>{editing ? "Update customer details" : "Add a new credit customer"}</DialogDescription>
              </DialogHeader>
              <div className="space-y-4">
                <FormSection title="Basic Info">
                  <FormField label="Customer Name *">
                    <Input value={form.customerName} onChange={(e) => setForm({ ...form, customerName: e.target.value })} />
                  </FormField>
                  <FormField label="Customer Type">
                    <Select value={form.customerType} onValueChange={(v) => setForm({ ...form, customerType: v })}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>
                        {CUSTOMER_TYPES.map(t => <SelectItem key={t} value={t}>{t}</SelectItem>)}
                      </SelectContent>
                    </Select>
                  </FormField>
                  <FormField label="Phone">
                    <Input value={form.phone} onChange={(e) => setForm({ ...form, phone: e.target.value })} />
                  </FormField>
                  <FormField label="Email">
                    <Input type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} />
                  </FormField>
                </FormSection>

                <FormSection title="Address">
                  <FormField label="Address">
                    <Input value={form.address} onChange={(e) => setForm({ ...form, address: e.target.value })} />
                  </FormField>
                  <FormField label="City">
                    <Input value={form.city} onChange={(e) => setForm({ ...form, city: e.target.value })} />
                  </FormField>
                </FormSection>

                <FormSection title="Terms">
                  <FormField label="Payment Terms (Days)">
                    <Input type="number" value={form.paymentTermDays} onChange={(e) => setForm({ ...form, paymentTermDays: Number(e.target.value) })} />
                  </FormField>
                  <FormField label="Credit Limit">
                    <Input type="number" step="0.01" value={form.creditLimit} onChange={(e) => setForm({ ...form, creditLimit: Number(e.target.value) })} />
                  </FormField>
                  {!editing && (
                    <FormField label="Opening Balance">
                      <Input type="number" step="0.01" value={form.openingBalance} onChange={(e) => setForm({ ...form, openingBalance: Number(e.target.value) })} />
                    </FormField>
                  )}
                </FormSection>

                <FormField label="Notes">
                  <Textarea value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} />
                </FormField>
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
                <Button onClick={save} disabled={saving}>{saving && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}{editing ? "Update" : "Create"}</Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>

          {/* Delete Dialog */}
          <Dialog open={!!delTarget} onOpenChange={() => setDelTarget(null)}>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Delete Customer</DialogTitle>
                <DialogDescription>Are you sure you want to delete &quot;{delTarget?.customerName}&quot;? This action cannot be undone.</DialogDescription>
              </DialogHeader>
              <DialogFooter>
                <Button variant="outline" onClick={() => setDelTarget(null)}>Cancel</Button>
                <Button variant="destructive" onClick={doDelete}>Delete</Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </main>
      </div>
    </div>
  )
}
