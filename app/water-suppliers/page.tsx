"use client"

// Suppliers master list page. Same shape as /water-customers.
// See migration 076 + lib/api/water.ts (listWaterSuppliers etc.) for the
// data model. The Setup tab on /water-company-setup will reuse the same
// CRUD endpoints, so any change here syncs both places automatically.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Plus, Pencil, Trash2, Loader2, Truck } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterSuppliers, createWaterSupplier, updateWaterSupplier, deleteWaterSupplier,
  type WaterSupplier, type WaterSupplierInput,
  WATER_SUPPLIER_TYPES,
} from "@/lib/api/water"

const EMPTY: WaterSupplierInput = {
  supplierName: "",
  supplierType: "Other",
  contactPerson: "",
  phone: "",
  email: "",
  address: "",
  notes: "",
  isActive: true,
}

export default function WaterSuppliersPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [suppliers, setSuppliers] = useState<WaterSupplier[]>([])
  const [search, setSearch] = useState("")
  const [loading, setLoading] = useState(true)

  const visible = useMemo(
    () => filterByDateAndSearch(suppliers, {
      search, dateFrom: "", dateTo: "",
      searchKeys: ["supplierName", "contactPerson", "phone", "email", "supplierType"],
    }),
    [suppliers, search],
  )

  const [open, setOpen] = useState(false)
  const [editId, setEditId] = useState<number | null>(null)
  const [form, setForm] = useState<WaterSupplierInput>(EMPTY)
  const [saving, setSaving] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState<WaterSupplier | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") {
      router.replace("/dashboard"); return
    }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try { setSuppliers(await listWaterSuppliers({ includeInactive: true })) }
    catch (e: any) { toast({ title: "Could not load suppliers", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openNew() { setEditId(null); setForm(EMPTY); setOpen(true) }
  function openEdit(s: WaterSupplier) {
    setEditId(s.waterSupplierId)
    setForm({
      supplierName:  s.supplierName,
      supplierType:  s.supplierType  ?? "Other",
      contactPerson: s.contactPerson ?? "",
      phone:         s.phone         ?? "",
      email:         s.email         ?? "",
      address:       s.address       ?? "",
      notes:         s.notes         ?? "",
      isActive:      s.isActive,
    })
    setOpen(true)
  }

  async function save() {
    if (!form.supplierName.trim()) return toast({ title: "Supplier name required", variant: "destructive" })
    setSaving(true)
    try {
      if (editId) { await updateWaterSupplier(editId, form); toast({ title: "Supplier updated" }) }
      else        { await createWaterSupplier(form);          toast({ title: "Supplier created" }) }
      setOpen(false); setForm(EMPTY); setEditId(null); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function performDelete(s: WaterSupplier) {
    await deleteWaterSupplier(s.waterSupplierId)
    await load()
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <Truck className="h-6 w-6 text-sky-600" /> Suppliers
            </h1>
            <Button onClick={openNew} className="w-full sm:w-auto h-11 sm:h-10"><Plus className="h-4 w-4 mr-1" /> New supplier</Button>
          </div>

          <p className="text-sm text-slate-500 mb-3">
            Master list of vendors, service providers and anyone you pay.
            Used as the "Paid To" picker on Expenses and as the Supplier dropdown on
            Raw Materials &amp; Supplies purchases.
          </p>

          <ListFilters
            search={search} setSearch={setSearch}
            searchOnly
            searchPlaceholder="Search name, contact, phone, email or type"
          />

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : suppliers.length === 0 ? (
                <div className="p-8 text-center text-slate-500">
                  No suppliers yet. Click <span className="font-medium">New supplier</span> to add the first one.
                </div>
              ) : (
                <MobileCardList
                  items={visible}
                  getKey={(s) => s.waterSupplierId}
                  primary={(s) => s.supplierName}
                  secondary={(s) => (
                    <>
                      <span>{s.supplierType ?? "—"}</span>
                      <span>·</span>
                      <span>{s.phone ?? "—"}</span>
                    </>
                  )}
                  details={(s) => [
                    { label: "Type",    value: s.supplierType  ?? "—" },
                    { label: "Contact", value: s.contactPerson ?? "—" },
                    { label: "Phone",   value: s.phone ?? "—" },
                    { label: "Email",   value: s.email ?? "—" },
                    { label: "Status",  value: s.isActive ? "Active" : "Inactive" },
                  ]}
                  actions={(s) => (
                    <>
                      <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openEdit(s)}>
                        <Pencil className="h-4 w-4 mr-1" /> Edit
                      </Button>
                      <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => setDeleteTarget(s)}>
                        <Trash2 className="h-4 w-4 mr-1" /> Delete
                      </Button>
                    </>
                  )}
                  desktopTable={
                    <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Name</TableHead>
                          <TableHead>Type</TableHead>
                          <TableHead>Contact</TableHead>
                          <TableHead>Phone</TableHead>
                          <TableHead>Email</TableHead>
                          <TableHead>Status</TableHead>
                          <TableHead className="text-right">Actions</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {visible.map((s) => (
                          <TableRow key={s.waterSupplierId}>
                            <TableCell className="font-medium">{s.supplierName}</TableCell>
                            <TableCell>{s.supplierType ?? "—"}</TableCell>
                            <TableCell>{s.contactPerson ?? "—"}</TableCell>
                            <TableCell>{s.phone ?? "—"}</TableCell>
                            <TableCell>{s.email ?? "—"}</TableCell>
                            <TableCell>
                              <span className={s.isActive ? "text-emerald-600" : "text-slate-400"}>
                                {s.isActive ? "Active" : "Inactive"}
                              </span>
                            </TableCell>
                            <TableCell className="text-right">
                              <Button size="sm" variant="ghost" onClick={() => openEdit(s)}><Pencil className="h-4 w-4" /></Button>
                              <Button size="sm" variant="ghost" onClick={() => setDeleteTarget(s)}><Trash2 className="h-4 w-4 text-red-500" /></Button>
                            </TableCell>
                          </TableRow>
                        ))}
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

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="w-[95vw] max-w-[1600px] max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              {editId ? <Pencil className="w-5 h-5 text-blue-600" /> : <Truck className="w-5 h-5 text-blue-600" />}
              {editId ? "Edit supplier" : "New supplier"}
            </DialogTitle>
            <DialogDescription>
              Enter the supplier information. Required: name.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormSection title="Identity" color="indigo">
              <FormField label="Supplier name *" full>
                <Input value={form.supplierName} onChange={(e) => setForm({ ...form, supplierName: e.target.value })} />
              </FormField>
              <FormField label="Supplier type">
                <Select value={form.supplierType ?? "Other"} onValueChange={(v) => setForm({ ...form, supplierType: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {WATER_SUPPLIER_TYPES.map((t) => (<SelectItem key={t} value={t}>{t}</SelectItem>))}
                  </SelectContent>
                </Select>
              </FormField>
              <FormField label="Active">
                <Select value={form.isActive ? "yes" : "no"} onValueChange={(v) => setForm({ ...form, isActive: v === "yes" })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="yes">Active</SelectItem>
                    <SelectItem value="no">Inactive</SelectItem>
                  </SelectContent>
                </Select>
              </FormField>
            </FormSection>

            <FormSection title="Contact" color="green">
              <FormField label="Contact person">
                <Input value={form.contactPerson ?? ""} onChange={(e) => setForm({ ...form, contactPerson: e.target.value })} />
              </FormField>
              <FormField label="Phone">
                <Input value={form.phone ?? ""} onChange={(e) => setForm({ ...form, phone: e.target.value })} />
              </FormField>
              <FormField label="Email">
                <Input type="email" value={form.email ?? ""} onChange={(e) => setForm({ ...form, email: e.target.value })} />
              </FormField>
              <FormField label="Address" full>
                <Input value={form.address ?? ""} onChange={(e) => setForm({ ...form, address: e.target.value })} />
              </FormField>
            </FormSection>

            <FormSection title="Notes" color="slate" columns={1}>
              <FormField label="Notes">
                <Input value={form.notes ?? ""} onChange={(e) => setForm({ ...form, notes: e.target.value })} />
              </FormField>
            </FormSection>

            <div className="flex gap-3 justify-end pt-2">
              <Button type="button" onClick={() => setOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
              <Button onClick={save} disabled={saving}>
                {saving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : "Save"}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      <ConfirmDeleteDialog
        open={!!deleteTarget}
        onOpenChange={(o) => { if (!o) setDeleteTarget(null) }}
        title="Delete supplier?"
        itemLabel={deleteTarget?.supplierName}
        successTitle="Supplier removed"
        errorTitle="Delete failed"
        onConfirm={async () => { if (deleteTarget) await performDelete(deleteTarget) }}
      />
    </div>
  )
}
