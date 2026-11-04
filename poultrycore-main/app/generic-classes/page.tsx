"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Switch } from "@/components/ui/switch"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog"
import { Loader2, Plus, Pencil, Trash2, GraduationCap, Users } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { getClasses, upsertClass, deleteClass, type GenericClass } from "@/lib/api/generic"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"

const EMPTY = { className: "", classLevel: "", classTeacher: "", capacity: "", description: "", isActive: true }

export default function GenericClassesPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const [rows, setRows] = useState<GenericClass[]>([])
  const [loading, setLoading] = useState(true)
  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [editingId, setEditingId] = useState<number | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<GenericClass | null>(null)
  const [form, setForm] = useState(EMPTY)

  const load = async () => {
    setLoading(true)
    try { setRows(await getClasses()) }
    catch (e: any) { toast({ title: "Could not load classes", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    load()
  }, [activeFarmType, router])

  const openNew = () => { setEditingId(null); setForm(EMPTY); setOpen(true) }
  const openEdit = (c: GenericClass) => {
    setEditingId(c.genericClassId)
    setForm({
      className: c.className,
      classLevel: c.classLevel != null ? String(c.classLevel) : "",
      classTeacher: c.classTeacher ?? "",
      capacity: c.capacity != null ? String(c.capacity) : "",
      description: c.description ?? "",
      isActive: c.isActive,
    })
    setOpen(true)
  }

  const onSave = async () => {
    if (!form.className.trim()) { toast({ title: "Class name is required", variant: "destructive" }); return }
    setSaving(true)
    try {
      await upsertClass({
        genericClassId: editingId ?? 0,
        className: form.className.trim(),
        classLevel: form.classLevel ? Number(form.classLevel) : null,
        classTeacher: form.classTeacher || null,
        capacity: form.capacity ? Number(form.capacity) : null,
        description: form.description || null,
        isActive: form.isActive,
      })
      toast({ title: editingId ? "Class updated" : "Class created" })
      setOpen(false); setForm(EMPTY); load()
    } catch (e: any) { toast({ title: "Could not save", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  const onDelete = async () => {
    if (!deleteTarget) return
    try {
      await deleteClass(deleteTarget.genericClassId)
      toast({ title: "Class deleted" })
      setDeleteTarget(null); load()
    } catch (e: any) { toast({ title: "Could not delete", description: e?.message, variant: "destructive" }) }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="max-w-4xl mx-auto space-y-4">
            <div className="flex items-center justify-between">
              <h1 className="text-xl font-semibold text-slate-900 flex items-center gap-2">
                <GraduationCap className="h-5 w-5" /> Classes
              </h1>
              <Dialog open={open} onOpenChange={setOpen}>
                <DialogTrigger asChild>
                  <Button onClick={openNew}><Plus className="h-4 w-4 mr-1" /> Add class</Button>
                </DialogTrigger>
                <DialogContent>
                  <DialogHeader>
                    <DialogTitle>{editingId ? "Edit class" : "Add class"}</DialogTitle>
                    <DialogDescription>Define a class or grade level for your school.</DialogDescription>
                  </DialogHeader>
                  <div className="space-y-3">
                    <div>
                      <Label>Class name *</Label>
                      <Input value={form.className} maxLength={100} onChange={(e) => setForm((f) => ({ ...f, className: e.target.value }))} placeholder="e.g. Primary 1, JSS 2" />
                    </div>
                    <div className="grid grid-cols-2 gap-3">
                      <div>
                        <Label>Level (for sorting)</Label>
                        <NumberInput step="1" min="0" value={form.classLevel} onChange={(e) => setForm((f) => ({ ...f, classLevel: e.target.value }))} placeholder="e.g. 1, 2, 3" />
                      </div>
                      <div>
                        <Label>Capacity</Label>
                        <NumberInput step="1" min="0" value={form.capacity} onChange={(e) => setForm((f) => ({ ...f, capacity: e.target.value }))} placeholder="Max students" />
                      </div>
                    </div>
                    <div>
                      <Label>Class teacher</Label>
                      <Input value={form.classTeacher} maxLength={200} onChange={(e) => setForm((f) => ({ ...f, classTeacher: e.target.value }))} />
                    </div>
                    <div>
                      <Label>Description</Label>
                      <Textarea rows={2} value={form.description} onChange={(e) => setForm((f) => ({ ...f, description: e.target.value }))} />
                    </div>
                    <div className="flex items-center gap-2">
                      <Switch checked={form.isActive} onCheckedChange={(v) => setForm((f) => ({ ...f, isActive: v }))} id="cls-active" />
                      <Label htmlFor="cls-active" className="cursor-pointer text-sm">Active</Label>
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
                  <p className="text-center text-sm text-slate-500 py-12">No classes yet. Add your first class above.</p>
                ) : (
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Class</TableHead>
                        <TableHead>Level</TableHead>
                        <TableHead>Teacher</TableHead>
                        <TableHead className="text-center">Students</TableHead>
                        <TableHead className="text-center">Capacity</TableHead>
                        <TableHead>Status</TableHead>
                        <TableHead className="text-right">Actions</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {rows.map((c) => (
                        <TableRow key={c.genericClassId}>
                          <TableCell className="font-medium">{c.className}</TableCell>
                          <TableCell>{c.classLevel ?? "—"}</TableCell>
                          <TableCell>{c.classTeacher ?? "—"}</TableCell>
                          <TableCell className="text-center">
                            <Badge variant="secondary" className="text-xs">
                              <Users className="h-3 w-3 mr-1" /> {c.studentCount}
                            </Badge>
                          </TableCell>
                          <TableCell className="text-center">{c.capacity ?? "—"}</TableCell>
                          <TableCell>
                            <Badge className={c.isActive ? "bg-emerald-100 text-emerald-700" : "bg-slate-100 text-slate-600"}>
                              {c.isActive ? "Active" : "Inactive"}
                            </Badge>
                          </TableCell>
                          <TableCell className="text-right space-x-1">
                            <Button variant="ghost" size="sm" onClick={() => openEdit(c)}><Pencil className="h-3.5 w-3.5" /></Button>
                            <Button variant="ghost" size="sm" onClick={() => setDeleteTarget(c)}><Trash2 className="h-3.5 w-3.5 text-red-500" /></Button>
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
        title="Delete class"
        description={`Are you sure you want to delete "${deleteTarget?.className}"? Students in this class will not be deleted.`}
      />
    </div>
  )
}
