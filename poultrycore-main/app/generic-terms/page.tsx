"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog"
import { Loader2, Plus, Pencil, Trash2, Calendar } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { getAcademicTerms, upsertAcademicTerm, deleteAcademicTerm, type GenericAcademicTerm } from "@/lib/api/generic"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"

const EMPTY = { termName: "", startDate: "", endDate: "", isCurrent: false, isActive: true }

function fmtDate(d: string) {
  return new Date(d).toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" })
}

export default function GenericTermsPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const [rows, setRows] = useState<GenericAcademicTerm[]>([])
  const [loading, setLoading] = useState(true)
  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [editingId, setEditingId] = useState<number | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<GenericAcademicTerm | null>(null)
  const [form, setForm] = useState(EMPTY)

  const load = async () => {
    setLoading(true)
    try { setRows(await getAcademicTerms()) }
    catch (e: any) { toast({ title: "Could not load terms", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    load()
  }, [activeFarmType, router])

  const openNew = () => { setEditingId(null); setForm(EMPTY); setOpen(true) }
  const openEdit = (t: GenericAcademicTerm) => {
    setEditingId(t.genericAcademicTermId)
    setForm({
      termName: t.termName,
      startDate: t.startDate.slice(0, 10),
      endDate: t.endDate.slice(0, 10),
      isCurrent: t.isCurrent,
      isActive: t.isActive,
    })
    setOpen(true)
  }

  const onSave = async () => {
    if (!form.termName.trim()) { toast({ title: "Term name is required", variant: "destructive" }); return }
    if (!form.startDate || !form.endDate) { toast({ title: "Start and end dates are required", variant: "destructive" }); return }
    if (form.endDate <= form.startDate) { toast({ title: "End date must be after start date", variant: "destructive" }); return }
    setSaving(true)
    try {
      await upsertAcademicTerm({
        genericAcademicTermId: editingId ?? 0,
        termName: form.termName.trim(),
        startDate: form.startDate,
        endDate: form.endDate,
        isCurrent: form.isCurrent,
        isActive: form.isActive,
      })
      toast({ title: editingId ? "Term updated" : "Term created" })
      setOpen(false); setForm(EMPTY); load()
    } catch (e: any) { toast({ title: "Could not save", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  const onDelete = async () => {
    if (!deleteTarget) return
    try {
      await deleteAcademicTerm(deleteTarget.genericAcademicTermId)
      toast({ title: "Term deleted" })
      setDeleteTarget(null); load()
    } catch (e: any) { toast({ title: "Could not delete", description: e?.message, variant: "destructive" }) }
  }

  const currentTerm = rows.find((t) => t.isCurrent)

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="max-w-4xl mx-auto space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <h1 className="text-xl font-semibold text-slate-900 flex items-center gap-2">
                  <Calendar className="h-5 w-5" /> Academic Terms
                </h1>
                {currentTerm && (
                  <p className="text-sm text-slate-500 mt-0.5">
                    Current term: <strong>{currentTerm.termName}</strong> ({fmtDate(currentTerm.startDate)} — {fmtDate(currentTerm.endDate)})
                  </p>
                )}
              </div>
              <Dialog open={open} onOpenChange={setOpen}>
                <DialogTrigger asChild>
                  <Button onClick={openNew}><Plus className="h-4 w-4 mr-1" /> Add term</Button>
                </DialogTrigger>
                <DialogContent>
                  <DialogHeader>
                    <DialogTitle>{editingId ? "Edit term" : "Add term"}</DialogTitle>
                    <DialogDescription>Define an academic term or semester.</DialogDescription>
                  </DialogHeader>
                  <div className="space-y-3">
                    <div>
                      <Label>Term name *</Label>
                      <Input value={form.termName} maxLength={100} onChange={(e) => setForm((f) => ({ ...f, termName: e.target.value }))} placeholder="e.g. Term 1 2026, Semester 2" />
                    </div>
                    <div className="grid grid-cols-2 gap-3">
                      <div>
                        <Label>Start date *</Label>
                        <Input type="date" value={form.startDate} onChange={(e) => setForm((f) => ({ ...f, startDate: e.target.value }))} />
                      </div>
                      <div>
                        <Label>End date *</Label>
                        <Input type="date" value={form.endDate} onChange={(e) => setForm((f) => ({ ...f, endDate: e.target.value }))} />
                      </div>
                    </div>
                    <div className="flex items-center gap-2">
                      <Switch checked={form.isCurrent} onCheckedChange={(v) => setForm((f) => ({ ...f, isCurrent: v }))} id="term-current" />
                      <Label htmlFor="term-current" className="cursor-pointer text-sm">This is the current term</Label>
                    </div>
                    <div className="flex items-center gap-2">
                      <Switch checked={form.isActive} onCheckedChange={(v) => setForm((f) => ({ ...f, isActive: v }))} id="term-active" />
                      <Label htmlFor="term-active" className="cursor-pointer text-sm">Active</Label>
                    </div>
                  </div>
                  <DialogFooter>
                    <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
                    <Button onClick={onSave} disabled={saving}>
                      {saving ? <><Loader2 className="h-4 w-4 mr-1 animate-spin" /> Saving…</> : editingId ? "Save" : "Create"}
                    </Button>
                  </DialogFooter>
                </DialogContent>
              </Dialog>
            </div>

            <Card>
              <CardContent className="p-0">
                {loading ? (
                  <div className="flex items-center justify-center py-12"><Loader2 className="h-5 w-5 animate-spin text-slate-400" /></div>
                ) : rows.length === 0 ? (
                  <p className="text-center text-sm text-slate-500 py-12">No terms yet. Add your first academic term above.</p>
                ) : (
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Term</TableHead>
                        <TableHead>Start</TableHead>
                        <TableHead>End</TableHead>
                        <TableHead>Status</TableHead>
                        <TableHead className="text-right">Actions</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {rows.map((t) => (
                        <TableRow key={t.genericAcademicTermId}>
                          <TableCell className="font-medium">
                            {t.termName}
                            {t.isCurrent && <Badge className="ml-2 bg-indigo-100 text-indigo-700">Current</Badge>}
                          </TableCell>
                          <TableCell>{fmtDate(t.startDate)}</TableCell>
                          <TableCell>{fmtDate(t.endDate)}</TableCell>
                          <TableCell>
                            <Badge className={t.isActive ? "bg-emerald-100 text-emerald-700" : "bg-slate-100 text-slate-600"}>
                              {t.isActive ? "Active" : "Inactive"}
                            </Badge>
                          </TableCell>
                          <TableCell className="text-right space-x-1">
                            <Button variant="ghost" size="sm" onClick={() => openEdit(t)}><Pencil className="h-3.5 w-3.5" /></Button>
                            <Button variant="ghost" size="sm" onClick={() => setDeleteTarget(t)}><Trash2 className="h-3.5 w-3.5 text-red-500" /></Button>
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                )}
              </CardContent>
            </Card>
          </div>
        </main>
      </div>
      <ConfirmDeleteDialog
        open={!!deleteTarget}
        onOpenChange={() => setDeleteTarget(null)}
        onConfirm={onDelete}
        title="Delete term"
        description={`Are you sure you want to delete "${deleteTarget?.termName}"?`}
      />
    </div>
  )
}
