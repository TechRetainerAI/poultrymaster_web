"use client"

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Loader2, Plus, Truck, Pencil, Trash2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { createSupplier, updateSupplier, deleteSupplier, getSuppliers, type GenericSupplier } from "@/lib/api/generic"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"

const SUPPLIER_TYPES = ["ProductSupplier", "ServiceProvider", "Landlord", "UtilityProvider", "Contractor", "Other"]

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}

export default function GenericSuppliersPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const [rows, setRows] = useState<GenericSupplier[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [loading, setLoading] = useState(true)
  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [editingId, setEditingId] = useState<number | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<GenericSupplier | null>(null)

  const EMPTY_FORM = {
    supplierName: "",
    supplierType: "ProductSupplier",
    phoneNumber: "",
    email: "",
    location: "",
    address: "",
    paymentTermsDays: "0",
    openingBalance: "0",
    notes: "",
    isActive: true,
  }
  const [form, setForm] = useState(EMPTY_FORM)

  const openNew = () => { setEditingId(null); setForm(EMPTY_FORM); setOpen(true) }
  const openEdit = (s: GenericSupplier) => {
    setEditingId(s.genericSupplierId)
    setForm({
      supplierName: s.supplierName,
      supplierType: s.supplierType,
      phoneNumber: s.phoneNumber ?? "",
      email: s.email ?? "",
      location: s.location ?? "",
      address: s.address ?? "",
      paymentTermsDays: String(s.paymentTermsDays),
      openingBalance: String(s.openingBalance),
      notes: s.notes ?? "",
      isActive: s.isActive,
    })
    setOpen(true)
  }

  const load = async () => {
    setLoading(true)
    try {
      setRows(await getSuppliers())
    } catch (e: any) {
      toast({ title: "Could not load suppliers", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router])

  const visibleRows = useMemo(
    () => filterByDateAndSearch(rows, {
      search, dateFrom, dateTo,
      searchKeys: ["supplierName", "phoneNumber", "email", "location"],
    }),
    [rows, search, dateFrom, dateTo],
  )

  const onSave = async () => {
    if (!form.supplierName.trim()) {
      toast({ title: "Name is required", variant: "destructive" })
      return
    }
    setSaving(true)
    try {
      const payload = {
        supplierName: form.supplierName.trim(),
        supplierType: form.supplierType,
        phoneNumber: form.phoneNumber || null,
        email: form.email || null,
        location: form.location || null,
        address: form.address || null,
        paymentTermsDays: Number(form.paymentTermsDays) || 0,
        openingBalance: Number(form.openingBalance) || 0,
        isActive: form.isActive,
        notes: form.notes || null,
      }
      if (editingId != null) {
        await updateSupplier(editingId, payload)
        toast({ title: `Supplier updated.` })
      } else {
        const created = await createSupplier(payload)
        if (created) toast({ title: `Supplier "${created.supplierName}" created.` })
      }
      setOpen(false)
      setForm(EMPTY_FORM)
      setEditingId(null)
      await load()
    } catch (e: any) {
      toast({ title: editingId != null ? "Could not save changes" : "Could not create supplier", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
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
                <Truck className="h-6 w-6 text-orange-600" /> Suppliers
              </h1>
              <p className="text-sm text-slate-500">{rows.length} supplier(s)</p>
            </div>
            <Dialog open={open} onOpenChange={(o) => { setOpen(o); if (!o) setEditingId(null) }}>
              <DialogTrigger asChild>
                <Button onClick={openNew} className="w-full sm:w-auto h-11 sm:h-10"><Plus className="h-4 w-4 mr-1" />New supplier</Button>
              </DialogTrigger>
              <DialogContent className="w-[95vw] max-w-[1600px] max-h-[90vh] overflow-y-auto">
                <DialogHeader>
                  <DialogTitle className="flex items-center gap-2">
                    {editingId != null
                      ? <><Pencil className="w-5 h-5 text-blue-600" /> Edit supplier</>
                      : <><Truck className="w-5 h-5 text-blue-600" /> New supplier</>}
                  </DialogTitle>
                  <DialogDescription>Pre-existing balance is the amount you already owe them.</DialogDescription>
                </DialogHeader>
                <div className="space-y-4">
                  <FormSection title="Personal information" color="indigo">
                    <FormField label="Supplier name *" full>
                      <Input value={form.supplierName} onChange={(e) => setForm((f) => ({ ...f, supplierName: e.target.value }))} maxLength={200} />
                    </FormField>
                    <FormField label="Type">
                      <Select value={form.supplierType} onValueChange={(v) => setForm((f) => ({ ...f, supplierType: v }))}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>{SUPPLIER_TYPES.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent>
                      </Select>
                    </FormField>
                    <FormField label="Phone">
                      <Input value={form.phoneNumber} onChange={(e) => setForm((f) => ({ ...f, phoneNumber: e.target.value }))} maxLength={50} />
                    </FormField>
                    <FormField label="Email">
                      <Input type="email" value={form.email} onChange={(e) => setForm((f) => ({ ...f, email: e.target.value }))} maxLength={150} />
                    </FormField>
                  </FormSection>

                  <FormSection title="Address" color="green">
                    <FormField label="Location">
                      <Input value={form.location} onChange={(e) => setForm((f) => ({ ...f, location: e.target.value }))} maxLength={255} />
                    </FormField>
                    <FormField label="Address" full>
                      <Input value={form.address} onChange={(e) => setForm((f) => ({ ...f, address: e.target.value }))} maxLength={500} />
                    </FormField>
                  </FormSection>

                  <FormSection title="Payment terms" color="amber">
                    <FormField label="Payment terms (days)">
                      <NumberInput min="0" value={form.paymentTermsDays} onChange={(e) => setForm((f) => ({ ...f, paymentTermsDays: e.target.value }))} />
                    </FormField>
                    <FormField label="Opening balance (you owe)">
                      <NumberInput step="0.01" value={form.openingBalance} onChange={(e) => setForm((f) => ({ ...f, openingBalance: e.target.value }))} />
                    </FormField>
                  </FormSection>

                  <FormSection title="Notes" color="slate" columns={1}>
                    <FormField label="Notes">
                      <Textarea rows={2} value={form.notes} onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} />
                    </FormField>
                  </FormSection>

                  <div className="flex gap-3 justify-end pt-2">
                    <Button type="button" onClick={() => setOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
                    <Button onClick={onSave} disabled={saving}>
                      {saving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : (editingId != null ? "Save changes" : "Create")}
                    </Button>
                  </div>
                </div>
              </DialogContent>
            </Dialog>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : rows.length === 0 ? (
            <Card><CardContent className="py-8 text-center text-slate-500">No suppliers yet.</CardContent></Card>
          ) : (
            <>
            <ListFilters
              search={search} setSearch={setSearch}
              searchOnly
              searchPlaceholder="Search name, phone, email or location"
            />
            <Card>
              <CardContent className="p-0">
                <MobileCardList
                  items={visibleRows}
                  getKey={(s) => s.genericSupplierId}
                  primary={(s) => (
                    <Link href={`/generic-suppliers/${s.genericSupplierId}/ledger`} className="text-orange-700 hover:underline">
                      {s.supplierName}
                    </Link>
                  )}
                  secondary={(s) => (
                    <>
                      <Badge variant="outline">{s.supplierType}</Badge>
                      {s.phoneNumber && <span>· {s.phoneNumber}</span>}
                    </>
                  )}
                  trailing={(s) => (
                    !s.isActive ? <Badge variant="secondary">Inactive</Badge>
                      : s.currentBalance > 0 ? <Badge className="bg-amber-100 text-amber-800 hover:bg-amber-100">Owed</Badge>
                      : <Badge className="bg-emerald-100 text-emerald-800 hover:bg-emerald-100">OK</Badge>
                  )}
                  details={(s) => [
                    { label: "Phone", value: s.phoneNumber ?? "—" },
                    { label: "Location", value: s.location ?? "—" },
                    { label: "Terms", value: s.paymentTermsDays > 0 ? `${s.paymentTermsDays}d` : "—" },
                    { label: "We owe them", value: <span className={s.currentBalance > 0 ? "text-rose-700 font-semibold" : ""}>{fmt(s.currentBalance)}</span> },
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
                          <TableHead>Phone</TableHead>
                          <TableHead>Location</TableHead>
                          <TableHead className="text-right">Terms</TableHead>
                          <TableHead className="text-right">We owe them</TableHead>
                          <TableHead>Status</TableHead>
                          <TableHead></TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {visibleRows.map((s) => (
                          <TableRow key={s.genericSupplierId}>
                            <TableCell className="font-medium">
                              <Link href={`/generic-suppliers/${s.genericSupplierId}/ledger`} className="text-orange-700 hover:underline">
                                {s.supplierName}
                              </Link>
                            </TableCell>
                            <TableCell><Badge variant="outline">{s.supplierType}</Badge></TableCell>
                            <TableCell>{s.phoneNumber ?? "—"}</TableCell>
                            <TableCell>{s.location ?? "—"}</TableCell>
                            <TableCell className="text-right">{s.paymentTermsDays > 0 ? `${s.paymentTermsDays}d` : "—"}</TableCell>
                            <TableCell className={`text-right ${s.currentBalance > 0 ? "text-rose-700 font-semibold" : ""}`}>{fmt(s.currentBalance)}</TableCell>
                            <TableCell>
                              {!s.isActive ? <Badge variant="secondary">Inactive</Badge>
                                : s.currentBalance > 0 ? <Badge className="bg-amber-100 text-amber-800 hover:bg-amber-100">Owed</Badge>
                                : <Badge className="bg-emerald-100 text-emerald-800 hover:bg-emerald-100">OK</Badge>}
                            </TableCell>
                            <TableCell className="text-right">
                              <Button size="sm" variant="ghost" onClick={() => openEdit(s)} title="Edit"><Pencil className="h-4 w-4" /></Button>
                              <Button size="sm" variant="ghost" onClick={() => setDeleteTarget(s)} title="Delete"><Trash2 className="h-4 w-4 text-red-500" /></Button>
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

      <ConfirmDeleteDialog
        open={!!deleteTarget}
        onOpenChange={(o) => { if (!o) setDeleteTarget(null) }}
        title="Delete supplier?"
        itemLabel={deleteTarget?.supplierName}
        description={deleteTarget && deleteTarget.currentBalance > 0
          ? `Balance owed to "${deleteTarget.supplierName}": ${fmt(deleteTarget.currentBalance)}. Backend will refuse if purchases or open payments exist.`
          : undefined}
        successTitle="Supplier deleted"
        errorTitle="Delete failed"
        onConfirm={async () => {
          if (deleteTarget) {
            await deleteSupplier(deleteTarget.genericSupplierId)
            await load()
          }
        }}
      />
    </div>
  )
}
