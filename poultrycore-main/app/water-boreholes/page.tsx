"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Badge } from "@/components/ui/badge"
import { Switch } from "@/components/ui/switch"
import { Plus, Pencil, Trash2, Loader2, Droplets } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterBoreholes, createWaterBorehole, updateWaterBorehole, deleteWaterBorehole,
  type WaterBorehole,
} from "@/lib/api/water"

const STATUSES = ["Active", "Inactive", "UnderMaintenance"]
const STATUS_COLOR: Record<string, string> = {
  Active: "bg-green-100 text-green-700",
  Inactive: "bg-slate-100 text-slate-700",
  UnderMaintenance: "bg-amber-100 text-amber-700",
}

type FormState = Omit<WaterBorehole, "waterBoreholeId" | "farmId">
const EMPTY: FormState = {
  boreholeName: "", location: null, pumpType: null, pumpCapacity: null, tankCapacity: null,
  waterTreatmentMethod: null, filtrationSystem: null, uvSterilizationAvailable: false,
  maintenanceFrequencyDays: null, lastMaintenanceDate: null, nextMaintenanceDate: null,
  waterQualityTestDueDate: null, status: "Active", notes: null,
}

const today = new Date().toISOString().slice(0, 10)

export default function WaterBoreholesPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [items, setItems] = useState<WaterBorehole[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [loading, setLoading] = useState(true)
  const [open, setOpen] = useState(false)

  const visibleItems = useMemo(
    () => filterByDateAndSearch(items, {
      search, dateFrom, dateTo,
      searchKeys: ["boreholeName", "location"],
    }),
    [items, search, dateFrom, dateTo],
  )

  // Client-side paging: the whole list is already in memory, so this is a
  // slice. Feed the SAME slice to the cards and the desktop table.
  const pg = usePagination(visibleItems)
  const [editId, setEditId] = useState<number | null>(null)
  const [form, setForm] = useState<FormState>(EMPTY)
  const [saving, setSaving] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState<WaterBorehole | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try { setItems(await listWaterBoreholes()) }
    catch (e: any) { toast({ title: "Could not load boreholes", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openNew() { setEditId(null); setForm(EMPTY); setOpen(true) }
  function openEdit(b: WaterBorehole) {
    setEditId(b.waterBoreholeId)
    setForm({
      boreholeName: b.boreholeName, location: b.location, pumpType: b.pumpType,
      pumpCapacity: b.pumpCapacity, tankCapacity: b.tankCapacity,
      waterTreatmentMethod: b.waterTreatmentMethod, filtrationSystem: b.filtrationSystem,
      uvSterilizationAvailable: b.uvSterilizationAvailable ?? false,
      maintenanceFrequencyDays: b.maintenanceFrequencyDays,
      lastMaintenanceDate: b.lastMaintenanceDate?.split("T")[0] ?? null,
      nextMaintenanceDate: b.nextMaintenanceDate?.split("T")[0] ?? null,
      waterQualityTestDueDate: b.waterQualityTestDueDate?.split("T")[0] ?? null,
      status: b.status, notes: b.notes,
    })
    setOpen(true)
  }

  async function save() {
    if (!form.boreholeName.trim()) return toast({ title: "Borehole name required", variant: "destructive" })
    setSaving(true)
    try {
      if (editId) { await updateWaterBorehole(editId, form); toast({ title: "Borehole updated" }) }
      else        { await createWaterBorehole(form);          toast({ title: "Borehole added" }) }
      setOpen(false); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function performDelete(b: WaterBorehole) {
    await deleteWaterBorehole(b.waterBoreholeId)
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
              <Droplets className="h-6 w-6 text-sky-600" /> Boreholes
            </h1>
            <Button onClick={openNew} className="w-full sm:w-auto h-11 sm:h-10"><Plus className="h-4 w-4 mr-1" /> New borehole</Button>
          </div>

          <ListFilters
            search={search} setSearch={setSearch}
            searchOnly
            searchPlaceholder="Search borehole or location"
          />

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : items.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No boreholes yet.</div>
              ) : (
                <MobileCardList
                  striped
                  defaultOpen
                  items={pg.pageItems}
                  pagination={pg.paginationProps}
                  getKey={(b) => b.waterBoreholeId}
                  primary={(b) => b.boreholeName}
                  secondary={(b) => (
                    <>
                      <span>{b.location ?? "—"}</span>
                      <Badge className={STATUS_COLOR[b.status] ?? ""}>{b.status}</Badge>
                    </>
                  )}
                  highlights={(b) => [
                    { label: "Next maintenance", value: b.nextMaintenanceDate ? b.nextMaintenanceDate.split("T")[0] : "—", accent: "blue" },
                    { label: "Quality test due", value: b.waterQualityTestDueDate ? b.waterQualityTestDueDate.split("T")[0] : "—", accent: "violet" },
                  ]}
                  details={(b) => [
                    { label: "Location", value: b.location ?? "—" },
                    { label: "Treatment", value: b.waterTreatmentMethod ?? "—" },
                    { label: "Status", value: b.status },
                  ]}
                  actions={(b) => (
                    <>
                      <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openEdit(b)}>
                        <Pencil className="h-4 w-4 mr-1" /> Edit
                      </Button>
                      <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => setDeleteTarget(b)}>
                        <Trash2 className="h-4 w-4 mr-1" /> Delete
                      </Button>
                    </>
                  )}
                  desktopTable={
                    <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow><TableHead>Name</TableHead><TableHead>Location</TableHead><TableHead>Treatment</TableHead><TableHead>Next maint.</TableHead><TableHead>Quality test due</TableHead><TableHead>Status</TableHead><TableHead className="text-right">Actions</TableHead></TableRow>
                      </TableHeader>
                      <TableBody>
                        {pg.pageItems.map((b) => (
                          <TableRow key={b.waterBoreholeId}>
                            <TableCell className="font-medium">{b.boreholeName}</TableCell>
                            <TableCell>{b.location ?? "—"}</TableCell>
                            <TableCell>{b.waterTreatmentMethod ?? "—"}</TableCell>
                            <TableCell>{b.nextMaintenanceDate ? b.nextMaintenanceDate.split("T")[0] : "—"}</TableCell>
                            <TableCell>{b.waterQualityTestDueDate ? b.waterQualityTestDueDate.split("T")[0] : "—"}</TableCell>
                            <TableCell><Badge className={STATUS_COLOR[b.status] ?? ""}>{b.status}</Badge></TableCell>
                            <TableCell className="text-right">
                              <Button size="sm" variant="ghost" onClick={() => openEdit(b)}><Pencil className="h-4 w-4" /></Button>
                              <Button size="sm" variant="ghost" onClick={() => setDeleteTarget(b)}><Trash2 className="h-4 w-4 text-red-500" /></Button>
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
              {editId ? <Pencil className="w-5 h-5 text-blue-600" /> : <Droplets className="w-5 h-5 text-blue-600" />}
              {editId ? "Edit borehole" : "New borehole"}
            </DialogTitle>
            <DialogDescription>Register a borehole and its treatment configuration</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormSection title="Identity" color="indigo">
              <FormField label="Borehole name *" full>
                <Input value={form.boreholeName} onChange={(e) => setForm({ ...form, boreholeName: e.target.value })} />
              </FormField>
              <FormField label="Location" full>
                <Input value={form.location ?? ""} onChange={(e) => setForm({ ...form, location: e.target.value || null })} />
              </FormField>
            </FormSection>

            <FormSection title="Pump & Tank" color="blue">
              <FormField label="Pump type">
                <Input value={form.pumpType ?? ""} onChange={(e) => setForm({ ...form, pumpType: e.target.value || null })} />
              </FormField>
              <FormField label="Pump capacity">
                <Input placeholder="e.g. 5000 L/hr" value={form.pumpCapacity ?? ""} onChange={(e) => setForm({ ...form, pumpCapacity: e.target.value || null })} />
              </FormField>
              <FormField label="Tank capacity" full>
                <Input placeholder="e.g. 10000 L" value={form.tankCapacity ?? ""} onChange={(e) => setForm({ ...form, tankCapacity: e.target.value || null })} />
              </FormField>
            </FormSection>

            <FormSection title="Treatment" color="sky">
              <FormField label="Treatment method">
                <Input value={form.waterTreatmentMethod ?? ""} onChange={(e) => setForm({ ...form, waterTreatmentMethod: e.target.value || null })} />
              </FormField>
              <FormField label="Filtration">
                <Input value={form.filtrationSystem ?? ""} onChange={(e) => setForm({ ...form, filtrationSystem: e.target.value || null })} />
              </FormField>
              <FormField label="UV sterilization" full>
                <div className="flex items-center justify-between rounded border p-2">
                  <span className="text-sm text-slate-700">UV sterilization available</span>
                  <Switch checked={form.uvSterilizationAvailable ?? false} onCheckedChange={(v) => setForm({ ...form, uvSterilizationAvailable: v })} />
                </div>
              </FormField>
              <FormField label="Status" full>
                <Select value={form.status} onValueChange={(v) => setForm({ ...form, status: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{STATUSES.map(s => <SelectItem key={s} value={s}>{s}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
            </FormSection>

            <FormSection title="Maintenance" color="amber">
              <FormField label="Maint. frequency (days)" full>
                <NumberInput min={0} value={form.maintenanceFrequencyDays ?? ""} onChange={(e) => setForm({ ...form, maintenanceFrequencyDays: e.target.value ? Number(e.target.value) : null })} />
              </FormField>
              <FormField label="Last maintenance">
                <Input type="date" max={today} value={form.lastMaintenanceDate ?? ""} onChange={(e) => setForm({ ...form, lastMaintenanceDate: e.target.value || null })} />
              </FormField>
              <FormField label="Next maintenance">
                <Input type="date" min={today} value={form.nextMaintenanceDate ?? ""} onChange={(e) => setForm({ ...form, nextMaintenanceDate: e.target.value || null })} />
              </FormField>
              <FormField label="Water quality test due date" full>
                <Input type="date" min={today} value={form.waterQualityTestDueDate ?? ""} onChange={(e) => setForm({ ...form, waterQualityTestDueDate: e.target.value || null })} />
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
        title="Remove borehole?"
        itemLabel={deleteTarget?.boreholeName}
        confirmLabel="Remove"
        successTitle="Borehole removed"
        errorTitle="Remove failed"
        onConfirm={async () => { if (deleteTarget) await performDelete(deleteTarget) }}
      />
    </div>
  )
}
