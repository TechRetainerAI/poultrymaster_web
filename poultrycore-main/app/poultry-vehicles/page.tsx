"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Badge } from "@/components/ui/badge"
import { Plus, Pencil, Trash2, Loader2, Truck } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listPoultryVehicles, createPoultryVehicle, updatePoultryVehicle, deletePoultryVehicle,
  type PoultryVehicle, type PoultryVehicleInput,
} from "@/lib/api/poultry-distribution"

const TYPES = ["Truck", "Van", "Tricycle", "Motorbike", "Pickup", "Other"]
const STATUSES = ["Active", "Inactive", "UnderMaintenance"]
const STATUS_COLOR: Record<string, string> = {
  Active: "bg-green-100 text-green-700",
  Inactive: "bg-slate-100 text-slate-700",
  UnderMaintenance: "bg-amber-100 text-amber-700",
}

type FormState = PoultryVehicleInput
const EMPTY: FormState = { vehicleName: "", vehicleType: "Truck", registrationNumber: null, defaultDriverId: null, capacityCrates: null, fuelType: null, status: "Active", notes: null }

export default function PoultryVehiclesPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [items, setItems] = useState<PoultryVehicle[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [loading, setLoading] = useState(true)
  const [open, setOpen] = useState(false)

  const visibleItems = useMemo(
    () => filterByDateAndSearch(items, {
      search, dateFrom, dateTo,
      searchKeys: ["vehicleName", "vehicleType", "registrationNumber"],
    }),
    [items, search, dateFrom, dateTo],
  )

  // Client-side paging: the whole list is already in memory, so this is a
  // slice. Feed the SAME slice to the cards and the desktop table.
  const pg = usePagination(visibleItems)
  const [editId, setEditId] = useState<number | null>(null)
  const [form, setForm] = useState<FormState>(EMPTY)
  const [saving, setSaving] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState<PoultryVehicle | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try { setItems(await listPoultryVehicles()) }
    catch (e: any) { toast({ title: "Could not load vehicles", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openNew() { setEditId(null); setForm(EMPTY); setOpen(true) }
  function openEdit(v: PoultryVehicle) {
    setEditId(v.poultryVehicleId)
    setForm({
      vehicleName: v.vehicleName, vehicleType: v.vehicleType, registrationNumber: v.registrationNumber,
      defaultDriverId: v.defaultDriverId, capacityCrates: v.capacityCrates, fuelType: v.fuelType,
      status: v.status, notes: v.notes,
    })
    setOpen(true)
  }

  async function save() {
    if (!form.vehicleName.trim()) return toast({ title: "Vehicle name required", variant: "destructive" })
    setSaving(true)
    try {
      if (editId) { await updatePoultryVehicle(editId, form); toast({ title: "Vehicle updated" }) }
      else        { await createPoultryVehicle(form);         toast({ title: "Vehicle added" }) }
      setOpen(false); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function performDelete(v: PoultryVehicle) {
    await deletePoultryVehicle(v.poultryVehicleId)
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
              <Truck className="h-6 w-6 text-sky-600" /> Vehicles
            </h1>
            <Button onClick={openNew} className="w-full sm:w-auto h-11 sm:h-10"><Plus className="h-4 w-4 mr-1" /> New vehicle</Button>
          </div>

          <ListFilters
            search={search} setSearch={setSearch}
            searchOnly
            searchPlaceholder="Search name, type or registration"
          />

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : items.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No vehicles yet.</div>
              ) : (
                <MobileCardList
                  items={pg.pageItems}
                  pagination={pg.paginationProps}
                  getKey={(v) => v.poultryVehicleId}
                  primary={(v) => v.vehicleName}
                  secondary={(v) => (
                    <>
                      <Badge variant="outline">{v.vehicleType}</Badge>
                      <Badge className={STATUS_COLOR[v.status] ?? ""}>{v.status}</Badge>
                    </>
                  )}
                  details={(v) => [
                    { label: "Type", value: v.vehicleType ?? "—" },
                    { label: "Reg #", value: v.registrationNumber ?? "—" },
                    { label: "Capacity (crates)", value: v.capacityCrates ?? "—" },
                    { label: "Fuel", value: v.fuelType ?? "—" },
                    { label: "Status", value: v.status },
                  ]}
                  actions={(v) => (
                    <>
                      <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openEdit(v)}>
                        <Pencil className="h-4 w-4 mr-1" /> Edit
                      </Button>
                      <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => setDeleteTarget(v)}>
                        <Trash2 className="h-4 w-4 mr-1" /> Delete
                      </Button>
                    </>
                  )}
                  desktopTable={
                    <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow><TableHead>Name</TableHead><TableHead>Type</TableHead><TableHead>Reg #</TableHead><TableHead className="text-right">Capacity (crates)</TableHead><TableHead>Fuel</TableHead><TableHead>Status</TableHead><TableHead className="text-right">Actions</TableHead></TableRow>
                      </TableHeader>
                      <TableBody>
                        {pg.pageItems.map((v) => (
                          <TableRow key={v.poultryVehicleId}>
                            <TableCell className="font-medium">{v.vehicleName}</TableCell>
                            <TableCell><Badge variant="outline">{v.vehicleType}</Badge></TableCell>
                            <TableCell>{v.registrationNumber ?? "—"}</TableCell>
                            <TableCell className="text-right tabular-nums">{v.capacityCrates ?? "—"}</TableCell>
                            <TableCell>{v.fuelType ?? "—"}</TableCell>
                            <TableCell><Badge className={STATUS_COLOR[v.status] ?? ""}>{v.status}</Badge></TableCell>
                            <TableCell className="text-right">
                              <Button size="sm" variant="ghost" onClick={() => openEdit(v)}><Pencil className="h-4 w-4" /></Button>
                              <Button size="sm" variant="ghost" onClick={() => setDeleteTarget(v)}><Trash2 className="h-4 w-4 text-red-500" /></Button>
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
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              {editId ? <Pencil className="w-5 h-5 text-blue-600" /> : <Truck className="w-5 h-5 text-blue-600" />}
              {editId ? "Edit vehicle" : "New vehicle"}
            </DialogTitle>
            <DialogDescription>Add or update a delivery vehicle</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormSection title="Identity" color="indigo">
              <FormField label="Vehicle name *" full>
                <Input value={form.vehicleName} onChange={(e) => setForm({ ...form, vehicleName: e.target.value })} placeholder="e.g. Truck 1" />
              </FormField>
              <FormField label="Type">
                <Select value={form.vehicleType ?? "Truck"} onValueChange={(v) => setForm({ ...form, vehicleType: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{TYPES.map(t => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
              <FormField label="Registration #">
                <Input value={form.registrationNumber ?? ""} onChange={(e) => setForm({ ...form, registrationNumber: e.target.value || null })} />
              </FormField>
            </FormSection>

            <FormSection title="Details" color="blue">
              <FormField label="Capacity (crates)">
                <NumberInput min={0} value={form.capacityCrates ?? ""} onChange={(e) => setForm({ ...form, capacityCrates: e.target.value ? Number(e.target.value) : null })} />
              </FormField>
              <FormField label="Fuel type">
                <Input value={form.fuelType ?? ""} onChange={(e) => setForm({ ...form, fuelType: e.target.value || null })} placeholder="Petrol / Diesel" />
              </FormField>
              <FormField label="Status" full>
                <Select value={form.status ?? "Active"} onValueChange={(v) => setForm({ ...form, status: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{STATUSES.map(s => <SelectItem key={s} value={s}>{s}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
            </FormSection>

            <FormSection title="Notes" color="slate" columns={1}>
              <FormField label="Notes">
                <Input value={form.notes ?? ""} onChange={(e) => setForm({ ...form, notes: e.target.value || null })} />
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
        title="Remove vehicle?"
        itemLabel={deleteTarget?.vehicleName}
        confirmLabel="Remove"
        successTitle="Vehicle removed"
        errorTitle="Remove failed"
        onConfirm={async () => { if (deleteTarget) await performDelete(deleteTarget) }}
      />
    </div>
  )
}
