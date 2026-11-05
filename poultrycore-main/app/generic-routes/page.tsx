"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { usePagination } from "@/hooks/use-pagination"
import { MapPin, Plus, Loader2, Pencil, Trash2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { getRoutes, createRoute, updateRoute, deleteRoute, type GenericRoute } from "@/lib/api/generic"

const empty = () => ({ routeName: "", description: "", startPoint: "", endPoint: "", estimatedTime: "", notes: "" })

export default function GenericRoutesPage() {
  const router = useRouter()
  const logout = useLogout()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [rows, setRows] = useState<GenericRoute[]>([])
  const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState<GenericRoute | null>(null)
  const [deleting, setDeleting] = useState<GenericRoute | null>(null)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState(empty())

  const pg = usePagination(rows)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load()
  }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try { setRows(await getRoutes()) }
    catch (e: any) { toast({ title: "Could not load routes", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openCreate() { setEditing(null); setForm(empty()); setDialogOpen(true) }
  function openEdit(r: GenericRoute) {
    setEditing(r)
    setForm({ routeName: r.routeName, description: r.description ?? "", startPoint: r.startPoint ?? "", endPoint: r.endPoint ?? "", estimatedTime: r.estimatedTime ?? "", notes: r.notes ?? "" })
    setDialogOpen(true)
  }

  async function doSave() {
    if (!form.routeName.trim()) { toast({ title: "Route name is required", variant: "destructive" }); return }
    setSaving(true)
    try {
      if (editing) {
        await updateRoute(editing.genericRouteId, { ...form, isActive: editing.isActive })
        toast({ title: "Route updated" })
      } else {
        await createRoute(form)
        toast({ title: "Route added" })
      }
      setDialogOpen(false); await load()
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-3 md:p-4 space-y-3">
          <div className="flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-xl font-semibold text-slate-900 flex items-center gap-2">
                <MapPin className="h-5 w-5 text-emerald-600" /> Delivery Routes
              </h1>
              <p className="text-xs text-slate-500">Manage delivery routes and destinations.</p>
            </div>
            <Button onClick={openCreate}><Plus className="h-4 w-4 mr-1" /> Add Route</Button>
          </div>

          {loading ? (
            <Card><CardContent className="py-12 text-center text-slate-600"><Loader2 className="h-4 w-4 animate-spin inline mr-2" />Loading…</CardContent></Card>
          ) : (
            <Card><CardContent className="p-0 md:p-2">
              <MobileCardList defaultOpen striped stripeAccent="blue"
                items={pg.pageItems} pagination={pg.paginationProps}
                getKey={(r: any) => r.genericRouteId}
                primary={(r: any) => r.routeName}
                secondary={(r: any) => r.description ?? "No description"}
                trailing={(r: any) => <Badge className={r.isActive ? "bg-emerald-100 text-emerald-700" : "bg-slate-100 text-slate-600"}>{r.isActive ? "Active" : "Inactive"}</Badge>}
                highlights={(r: any) => [
                  ...(r.startPoint ? [{ label: "From", value: r.startPoint, accent: "blue" as const }] : []),
                  ...(r.endPoint ? [{ label: "To", value: r.endPoint, accent: "emerald" as const }] : []),
                ]}
                details={(r: any) => [
                  { label: "Start", value: r.startPoint ?? "—" },
                  { label: "End", value: r.endPoint ?? "—" },
                  { label: "Est. time", value: r.estimatedTime ?? "—" },
                  { label: "Notes", value: r.notes ?? "—" },
                ]}
                actions={(r: any) => (
                  <>
                    <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openEdit(r)}>
                      <Pencil className="h-4 w-4 mr-1" /> Edit
                    </Button>
                    <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => setDeleting(r)}>
                      <Trash2 className="h-4 w-4 mr-1" /> Delete
                    </Button>
                  </>
                )}
                desktopTable={
                  <div className="overflow-x-auto"><Table>
                    <TableHeader><TableRow>
                      <TableHead>Route</TableHead><TableHead>Description</TableHead>
                      <TableHead>From</TableHead><TableHead>To</TableHead>
                      <TableHead>Est. Time</TableHead><TableHead>Status</TableHead>
                      <TableHead className="text-right">Actions</TableHead>
                    </TableRow></TableHeader>
                    <TableBody>
                      {rows.length === 0 ? <TableRow><TableCell colSpan={7} className="text-center text-slate-500 py-6">No routes. Add one to get started.</TableCell></TableRow>
                      : pg.pageItems.map((r: any) => (
                        <TableRow key={r.genericRouteId}>
                          <TableCell className="font-medium">{r.routeName}</TableCell>
                          <TableCell className="text-sm text-slate-600 max-w-xs truncate">{r.description ?? "—"}</TableCell>
                          <TableCell>{r.startPoint ?? "—"}</TableCell>
                          <TableCell>{r.endPoint ?? "—"}</TableCell>
                          <TableCell>{r.estimatedTime ?? "—"}</TableCell>
                          <TableCell><Badge className={r.isActive ? "bg-emerald-100 text-emerald-700" : "bg-slate-100 text-slate-600"}>{r.isActive ? "Active" : "Inactive"}</Badge></TableCell>
                          <TableCell className="text-right whitespace-nowrap">
                            <Button variant="ghost" size="sm" onClick={() => openEdit(r)}><Pencil className="h-4 w-4 text-slate-600" /></Button>
                            <Button variant="ghost" size="sm" onClick={() => setDeleting(r)}><Trash2 className="h-4 w-4 text-red-600" /></Button>
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table></div>
                }
              />
            </CardContent></Card>
          )}
        </main>
      </div>

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="max-w-lg"><DialogHeader><DialogTitle>{editing ? "Edit Route" : "Add Route"}</DialogTitle></DialogHeader>
          <FormSection title="Route details" color="indigo">
            <FormField label="Route name *"><Input value={form.routeName} onChange={(e) => setForm({ ...form, routeName: e.target.value })} /></FormField>
            <FormField label="Description"><Input value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} /></FormField>
            <FormField label="Start point"><Input value={form.startPoint} onChange={(e) => setForm({ ...form, startPoint: e.target.value })} placeholder="Where the route starts" /></FormField>
            <FormField label="End point"><Input value={form.endPoint} onChange={(e) => setForm({ ...form, endPoint: e.target.value })} placeholder="Where the route ends" /></FormField>
            <FormField label="Estimated time"><Input value={form.estimatedTime} onChange={(e) => setForm({ ...form, estimatedTime: e.target.value })} placeholder="e.g. 2 hours" /></FormField>
            <FormField label="Notes"><Input value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></FormField>
          </FormSection>
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setDialogOpen(false)}>Cancel</Button>
            <Button onClick={doSave} disabled={saving}>{saving ? <Loader2 className="h-4 w-4 animate-spin" /> : editing ? "Save" : "Add Route"}</Button>
          </div>
        </DialogContent>
      </Dialog>

      <ConfirmDeleteDialog
        open={!!deleting} onOpenChange={(o) => { if (!o) setDeleting(null) }}
        title={`Delete ${deleting?.routeName}?`}
        description="This route will be permanently removed."
        onConfirm={async () => { if (deleting) { await deleteRoute(deleting.genericRouteId); setDeleting(null); await load() } }}
      />
    </div>
  )
}
