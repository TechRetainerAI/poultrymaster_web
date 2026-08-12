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
import { Plus, Pencil, Trash2, Loader2, Cog } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterMachines, createWaterMachine, updateWaterMachine, deleteWaterMachine,
  type WaterMachine,
} from "@/lib/api/water"

const STATUSES = ["Active", "Down", "UnderMaintenance"]
const STATUS_COLOR: Record<string, string> = {
  Active: "bg-green-100 text-green-700",
  Down: "bg-rose-100 text-rose-700",
  UnderMaintenance: "bg-amber-100 text-amber-700",
}

type FormState = Omit<WaterMachine, "waterMachineId" | "farmId">
const EMPTY: FormState = {
  machineName: "", machineNumber: null, machineType: null, manufacturer: null,
  purchaseDate: null, capacityPerHour: null, assignedOperatorStaffId: null,
  maintenanceFrequencyDays: null, lastMaintenanceDate: null, nextMaintenanceDate: null,
  status: "Active", notes: null,
}

// Used as `max` on past-only date inputs (Last maintenance, Purchase date) and
// `min` on future-only inputs (Next maintenance). Mirrors water-boreholes which
// already does the right thing — bringing machines in line so users can't pick
// a last-maintenance date in the future.
const today = new Date().toISOString().slice(0, 10)

export default function WaterMachinesPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [items, setItems] = useState<WaterMachine[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [loading, setLoading] = useState(true)
  const [open, setOpen] = useState(false)

  const visibleItems = useMemo(
    () => filterByDateAndSearch(items, {
      search, dateFrom, dateTo,
      searchKeys: ["machineName", "machineType", "manufacturer"],
    }),
    [items, search, dateFrom, dateTo],
  )

  // Client-side paging: the whole list is already in memory, so this is a
  // slice. Feed the SAME slice to the cards and the desktop table.
  const pg = usePagination(visibleItems)
  const [editId, setEditId] = useState<number | null>(null)
  const [form, setForm] = useState<FormState>(EMPTY)
  const [saving, setSaving] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState<WaterMachine | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try { setItems(await listWaterMachines()) }
    catch (e: any) { toast({ title: "Could not load machines", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openNew() { setEditId(null); setForm(EMPTY); setOpen(true) }
  function openEdit(m: WaterMachine) {
    setEditId(m.waterMachineId)
    setForm({
      machineName: m.machineName, machineNumber: m.machineNumber, machineType: m.machineType, manufacturer: m.manufacturer,
      purchaseDate: m.purchaseDate?.split("T")[0] ?? null,
      capacityPerHour: m.capacityPerHour, assignedOperatorStaffId: m.assignedOperatorStaffId,
      maintenanceFrequencyDays: m.maintenanceFrequencyDays,
      lastMaintenanceDate: m.lastMaintenanceDate?.split("T")[0] ?? null,
      nextMaintenanceDate: m.nextMaintenanceDate?.split("T")[0] ?? null,
      status: m.status, notes: m.notes,
    })
    setOpen(true)
  }

  async function save() {
    if (!form.machineName.trim()) return toast({ title: "Machine name required", variant: "destructive" })
    // Belt-and-braces: the date inputs above are gated with `max={today}`, but
    // a user can still paste/type a future value. Reject explicitly so the
    // browser-level constraint isn't the only line of defence.
    if (form.lastMaintenanceDate && form.lastMaintenanceDate > today) {
      return toast({ title: "Last maintenance can't be in the future", variant: "destructive" })
    }
    if (form.purchaseDate && form.purchaseDate > today) {
      return toast({ title: "Purchase date can't be in the future", variant: "destructive" })
    }
    setSaving(true)
    try {
      if (editId) { await updateWaterMachine(editId, form); toast({ title: "Machine updated" }) }
      else        { await createWaterMachine(form);         toast({ title: "Machine added" }) }
      setOpen(false); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function performDelete(m: WaterMachine) {
    await deleteWaterMachine(m.waterMachineId)
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
              <Cog className="h-6 w-6 text-sky-600" /> Machines
            </h1>
            <Button onClick={openNew} className="w-full sm:w-auto h-11 sm:h-10"><Plus className="h-4 w-4 mr-1" /> New machine</Button>
          </div>

          <ListFilters
            search={search} setSearch={setSearch}
            searchOnly
            searchPlaceholder="Search name, type or manufacturer"
          />

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : items.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No machines yet.</div>
              ) : (
                <MobileCardList
                  items={pg.pageItems}
                  pagination={pg.paginationProps}
                  getKey={(m) => m.waterMachineId}
                  primary={(m) => m.machineName}
                  secondary={(m) => (
                    <>
                      <span>{m.machineType ?? "—"}</span>
                      <Badge className={STATUS_COLOR[m.status] ?? ""}>{m.status}</Badge>
                    </>
                  )}
                  details={(m) => [
                    { label: "Number", value: m.machineNumber ?? "—" },
                    { label: "Type", value: m.machineType ?? "—" },
                    { label: "Capacity/hr", value: m.capacityPerHour ?? "—" },
                    { label: "Next maint.", value: m.nextMaintenanceDate ? m.nextMaintenanceDate.split("T")[0] : "—" },
                    { label: "Status", value: m.status },
                  ]}
                  actions={(m) => (
                    <>
                      <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openEdit(m)}>
                        <Pencil className="h-4 w-4 mr-1" /> Edit
                      </Button>
                      <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => setDeleteTarget(m)}>
                        <Trash2 className="h-4 w-4 mr-1" /> Delete
                      </Button>
                    </>
                  )}
                  desktopTable={
                    <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow><TableHead>Name</TableHead><TableHead>Number</TableHead><TableHead>Type</TableHead><TableHead className="text-right">Capacity/hr</TableHead><TableHead>Next maint.</TableHead><TableHead>Status</TableHead><TableHead className="text-right">Actions</TableHead></TableRow>
                      </TableHeader>
                      <TableBody>
                        {pg.pageItems.map((m) => (
                          <TableRow key={m.waterMachineId}>
                            <TableCell className="font-medium">{m.machineName}</TableCell>
                            <TableCell>{m.machineNumber ?? "—"}</TableCell>
                            <TableCell>{m.machineType ?? "—"}</TableCell>
                            <TableCell className="text-right tabular-nums">{m.capacityPerHour ?? "—"}</TableCell>
                            <TableCell>{m.nextMaintenanceDate ? m.nextMaintenanceDate.split("T")[0] : "—"}</TableCell>
                            <TableCell><Badge className={STATUS_COLOR[m.status] ?? ""}>{m.status}</Badge></TableCell>
                            <TableCell className="text-right">
                              <Button size="sm" variant="ghost" onClick={() => openEdit(m)}><Pencil className="h-4 w-4" /></Button>
                              <Button size="sm" variant="ghost" onClick={() => setDeleteTarget(m)}><Trash2 className="h-4 w-4 text-red-500" /></Button>
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
              {editId ? <Pencil className="w-5 h-5 text-blue-600" /> : <Cog className="w-5 h-5 text-blue-600" />}
              {editId ? "Edit machine" : "New machine"}
            </DialogTitle>
            <DialogDescription>Register a production machine and its maintenance schedule</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormSection title="Identity" color="indigo">
              <FormField label="Machine name *" full>
                <Input value={form.machineName} onChange={(e) => setForm({ ...form, machineName: e.target.value })} />
              </FormField>
              <FormField label="Machine number">
                <Input value={form.machineNumber ?? ""} onChange={(e) => setForm({ ...form, machineNumber: e.target.value || null })} />
              </FormField>
              <FormField label="Type">
                <Input value={form.machineType ?? ""} onChange={(e) => setForm({ ...form, machineType: e.target.value || null })} placeholder="e.g. Sachet filling, Bottling" />
              </FormField>
              <FormField label="Manufacturer">
                <Input value={form.manufacturer ?? ""} onChange={(e) => setForm({ ...form, manufacturer: e.target.value || null })} />
              </FormField>
            </FormSection>

            <FormSection title="Details" color="blue">
              <FormField label="Capacity / hour (bags)">
                <NumberInput min={0} value={form.capacityPerHour ?? ""} onChange={(e) => setForm({ ...form, capacityPerHour: e.target.value ? Number(e.target.value) : null })} />
              </FormField>
              <FormField label="Purchase date">
                <Input type="date" max={today} value={form.purchaseDate ?? ""} onChange={(e) => setForm({ ...form, purchaseDate: e.target.value || null })} />
              </FormField>
              <FormField label="Status" full>
                <Select value={form.status} onValueChange={(v) => setForm({ ...form, status: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{STATUSES.map(s => <SelectItem key={s} value={s}>{s}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
            </FormSection>

            <FormSection title="Maintenance" color="amber">
              <FormField label="Maintenance frequency (days)" full>
                <NumberInput min={0} value={form.maintenanceFrequencyDays ?? ""} onChange={(e) => setForm({ ...form, maintenanceFrequencyDays: e.target.value ? Number(e.target.value) : null })} />
              </FormField>
              <FormField label="Last maintenance">
                <Input type="date" max={today} value={form.lastMaintenanceDate ?? ""} onChange={(e) => setForm({ ...form, lastMaintenanceDate: e.target.value || null })} />
              </FormField>
              <FormField label="Next maintenance">
                <Input type="date" min={today} value={form.nextMaintenanceDate ?? ""} onChange={(e) => setForm({ ...form, nextMaintenanceDate: e.target.value || null })} />
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
        title="Remove machine?"
        itemLabel={deleteTarget?.machineName}
        confirmLabel="Remove"
        successTitle="Machine removed"
        errorTitle="Remove failed"
        onConfirm={async () => { if (deleteTarget) await performDelete(deleteTarget) }}
      />
    </div>
  )
}
