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
import { Plus, Pencil, Trash2, Loader2, Route as RouteIcon } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listPoultryRoutes, createPoultryRoute, updatePoultryRoute, deletePoultryRoute,
  listPoultryVehicles, type PoultryRoute, type PoultryVehicle, type PoultryRouteInput,
} from "@/lib/api/poultry-distribution"

type FormState = PoultryRouteInput
const EMPTY: FormState = { routeName: "", areaCovered: null, defaultDriverId: null, defaultVehicleId: null, expectedCustomers: null, expectedCratesSold: null, notes: null }

export default function PoultryRoutesPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [items, setItems] = useState<PoultryRoute[]>([])
  const [vehicles, setVehicles] = useState<PoultryVehicle[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [loading, setLoading] = useState(true)

  const visibleItems = useMemo(
    () => filterByDateAndSearch(items, {
      search, dateFrom, dateTo,
      searchKeys: ["routeName", "areaCovered"],
    }),
    [items, search, dateFrom, dateTo],
  )

  // Client-side paging: the whole list is already in memory, so this is a
  // slice. Feed the SAME slice to the cards and the desktop table.
  const pg = usePagination(visibleItems)
  const [open, setOpen] = useState(false)
  const [editId, setEditId] = useState<number | null>(null)
  const [form, setForm] = useState<FormState>(EMPTY)
  const [saving, setSaving] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState<PoultryRoute | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try { const [rs, vs] = await Promise.all([listPoultryRoutes(), listPoultryVehicles()]); setItems(rs); setVehicles(vs) }
    catch (e: any) { toast({ title: "Could not load routes", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openNew() { setEditId(null); setForm(EMPTY); setOpen(true) }
  function openEdit(r: PoultryRoute) {
    setEditId(r.poultryRouteId)
    setForm({
      routeName: r.routeName, areaCovered: r.areaCovered, defaultDriverId: r.defaultDriverId,
      defaultVehicleId: r.defaultVehicleId, expectedCustomers: r.expectedCustomers,
      expectedCratesSold: r.expectedCratesSold, notes: r.notes,
    })
    setOpen(true)
  }

  async function save() {
    if (!form.routeName.trim()) return toast({ title: "Route name required", variant: "destructive" })
    setSaving(true)
    try {
      if (editId) { await updatePoultryRoute(editId, form); toast({ title: "Route updated" }) }
      else        { await createPoultryRoute(form);          toast({ title: "Route added" }) }
      setOpen(false); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function performDelete(r: PoultryRoute) {
    await deletePoultryRoute(r.poultryRouteId)
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
              <RouteIcon className="h-6 w-6 text-sky-600" /> Routes
            </h1>
            <Button onClick={openNew} className="w-full sm:w-auto h-11 sm:h-10"><Plus className="h-4 w-4 mr-1" /> New route</Button>
          </div>

          <ListFilters
            search={search} setSearch={setSearch}
            searchOnly
            searchPlaceholder="Search route or area"
          />

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : items.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No routes yet.</div>
              ) : (
                <MobileCardList
                  items={pg.pageItems}
                  pagination={pg.paginationProps}
                  getKey={(r) => r.poultryRouteId}
                  primary={(r) => r.routeName}
                  secondary={(r) => (
                    <>
                      <span>{r.areaCovered ?? "—"}</span>
                    </>
                  )}
                  details={(r) => [
                    { label: "Area", value: r.areaCovered ?? "—" },
                    { label: "Default vehicle", value: vehicles.find(v => v.poultryVehicleId === r.defaultVehicleId)?.vehicleName ?? "—" },
                    { label: "Expected customers", value: r.expectedCustomers ?? "—" },
                    { label: "Expected crates", value: r.expectedCratesSold ?? "—" },
                  ]}
                  actions={(r) => (
                    <>
                      <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openEdit(r)}>
                        <Pencil className="h-4 w-4 mr-1" /> Edit
                      </Button>
                      <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => setDeleteTarget(r)}>
                        <Trash2 className="h-4 w-4 mr-1" /> Delete
                      </Button>
                    </>
                  )}
                  desktopTable={
                    <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow><TableHead>Name</TableHead><TableHead>Area</TableHead><TableHead>Default vehicle</TableHead><TableHead className="text-right">Expected customers</TableHead><TableHead className="text-right">Expected crates</TableHead><TableHead className="text-right">Actions</TableHead></TableRow>
                      </TableHeader>
                      <TableBody>
                        {pg.pageItems.map((r) => (
                          <TableRow key={r.poultryRouteId}>
                            <TableCell className="font-medium">{r.routeName}</TableCell>
                            <TableCell>{r.areaCovered ?? "—"}</TableCell>
                            <TableCell>{vehicles.find(v => v.poultryVehicleId === r.defaultVehicleId)?.vehicleName ?? "—"}</TableCell>
                            <TableCell className="text-right tabular-nums">{r.expectedCustomers ?? "—"}</TableCell>
                            <TableCell className="text-right tabular-nums">{r.expectedCratesSold ?? "—"}</TableCell>
                            <TableCell className="text-right">
                              <Button size="sm" variant="ghost" onClick={() => openEdit(r)}><Pencil className="h-4 w-4" /></Button>
                              <Button size="sm" variant="ghost" onClick={() => setDeleteTarget(r)}><Trash2 className="h-4 w-4 text-red-500" /></Button>
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
              {editId ? <Pencil className="w-5 h-5 text-blue-600" /> : <RouteIcon className="w-5 h-5 text-blue-600" />}
              {editId ? "Edit route" : "New route"}
            </DialogTitle>
            <DialogDescription>Define a delivery route and its expectations</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormSection title="Basics" color="indigo">
              <FormField label="Route name *" full>
                <Input value={form.routeName} onChange={(e) => setForm({ ...form, routeName: e.target.value })} placeholder="e.g. Kumasi East" />
              </FormField>
              <FormField label="Area covered" full>
                <Input value={form.areaCovered ?? ""} onChange={(e) => setForm({ ...form, areaCovered: e.target.value || null })} />
              </FormField>
            </FormSection>

            <FormSection title="Assignment" color="blue">
              <FormField label="Default vehicle" full>
                <Select value={String(form.defaultVehicleId ?? "")} onValueChange={(v) => setForm({ ...form, defaultVehicleId: v ? Number(v) : null })}>
                  <SelectTrigger><SelectValue placeholder="(none)" /></SelectTrigger>
                  <SelectContent>
                    {vehicles.length === 0 && (
                      <div className="px-2 py-1.5 text-sm text-slate-500">No vehicles. Add one on the Vehicles page first.</div>
                    )}
                    {vehicles.map(v => (
                      <SelectItem key={v.poultryVehicleId} value={String(v.poultryVehicleId)}>
                        {v.vehicleName} ({v.vehicleType}){v.status !== "Active" ? ` — ${v.status}` : ""}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </FormField>
              <FormField label="Expected customers">
                <NumberInput min={0} value={form.expectedCustomers ?? ""} onChange={(e) => setForm({ ...form, expectedCustomers: e.target.value ? Number(e.target.value) : null })} />
              </FormField>
              <FormField label="Expected crates/day">
                <NumberInput min={0} value={form.expectedCratesSold ?? ""} onChange={(e) => setForm({ ...form, expectedCratesSold: e.target.value ? Number(e.target.value) : null })} />
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
        title="Remove route?"
        itemLabel={deleteTarget?.routeName}
        confirmLabel="Remove"
        successTitle="Route removed"
        errorTitle="Remove failed"
        onConfirm={async () => { if (deleteTarget) await performDelete(deleteTarget) }}
      />
    </div>
  )
}
