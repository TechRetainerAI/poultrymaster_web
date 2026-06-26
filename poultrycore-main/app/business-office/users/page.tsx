"use client"

// Business Office → Users & Permissions (Prompt 4). Organization-wide user list
// inside the Business Office shell. Admin-only management (add / make-admin /
// remove). Note: users are created against the active company (farm) — the org
// owner already sees every company, and assignment refinement is a follow-up.

import { useEffect, useMemo, useState } from "react"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { Loader2, Plus, Search, ShieldCheck, ShieldOff, Trash2, UserPlus } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { BusinessOfficeShell } from "@/components/dashboard/business-office-shell"
import { getEmployees, createEmployee, updateEmployee, deleteEmployee, sendCredentialsEmail, type Employee } from "@/lib/api/admin"

export default function BusinessOfficeUsersPage() {
  const { toast } = useToast()
  const permissions = usePermissions()
  const isAdmin = permissions.isAdmin

  const [users, setUsers] = useState<Employee[]>([])
  const [loading, setLoading] = useState(true)
  const [q, setQ] = useState("")
  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [busyId, setBusyId] = useState<string | null>(null)
  const [delTarget, setDelTarget] = useState<Employee | null>(null)
  const [form, setForm] = useState({ firstName: "", lastName: "", userName: "", email: "", phoneNumber: "", password: "", isAdmin: false })

  function farmCtx() {
    try { return { farmId: localStorage.getItem("farmId") || "", farmName: localStorage.getItem("farmName") || "" } } catch { return { farmId: "", farmName: "" } }
  }

  async function load() {
    setLoading(true)
    try { const r = await getEmployees(); setUsers(r.success && r.data ? r.data : []) }
    catch (e: any) { toast({ title: "Could not load users", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }
  useEffect(() => { void load() }, [])

  async function create() {
    if (!form.firstName.trim() || !form.lastName.trim()) return toast({ title: "First and last name are required", variant: "destructive" })
    if (!form.userName.trim()) return toast({ title: "Username is required", variant: "destructive" })
    if (form.password.length < 6) return toast({ title: "Password must be at least 6 characters", variant: "destructive" })
    const { farmId, farmName } = farmCtx()
    if (!farmId) return toast({ title: "Open a company first", description: "Users are assigned to a company. Open one, then add users.", variant: "destructive" })
    setSaving(true)
    try {
      const r = await createEmployee({
        firstName: form.firstName.trim(), lastName: form.lastName.trim(), userName: form.userName.trim(),
        email: form.email.trim() || `${form.userName.trim()}@noemail.local`, phoneNumber: form.phoneNumber.trim(),
        password: form.password, farmId, farmName, isAdmin: form.isAdmin,
      })
      if (!r.success) { toast({ title: "Create failed", description: r.message, variant: "destructive" }); return }
      toast({ title: `Added ${form.firstName}` })
      if (form.email.trim()) { try { await sendCredentialsEmail({ email: form.email.trim(), userName: form.userName.trim(), password: form.password, farmName }) } catch {} }
      setOpen(false); setForm({ firstName: "", lastName: "", userName: "", email: "", phoneNumber: "", password: "", isAdmin: false }); await load()
    } catch (e: any) { toast({ title: "Create failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function toggleAdmin(u: Employee) {
    setBusyId(u.id)
    try {
      const r = await updateEmployee(u.id, { id: u.id, firstName: u.firstName, lastName: u.lastName, phoneNumber: u.phoneNumber, email: u.email, isAdmin: !u.isAdmin })
      if (r.success) { setUsers((p) => p.map((x) => x.id === u.id ? { ...x, isAdmin: !u.isAdmin } : x)); toast({ title: !u.isAdmin ? "Granted admin" : "Removed admin" }) }
      else toast({ title: "Update failed", description: r.message, variant: "destructive" })
    } catch (e: any) { toast({ title: "Update failed", description: e?.message, variant: "destructive" }) }
    finally { setBusyId(null) }
  }

  const visible = useMemo(() => users.filter((u) => !q || `${u.firstName} ${u.lastName} ${u.userName} ${u.email}`.toLowerCase().includes(q.toLowerCase())), [users, q])

  return (
    <BusinessOfficeShell active="users">
      <main className="flex-1 overflow-auto p-4 sm:p-6 space-y-5">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div>
            <h1 className="text-2xl font-semibold text-slate-900">Users &amp; Permissions</h1>
            <p className="text-sm text-slate-500">People with login access across your Business Office.</p>
          </div>
          {isAdmin && <Button onClick={() => setOpen(true)}><UserPlus className="h-4 w-4 mr-1" /> Add user</Button>}
        </div>

        {!isAdmin ? (
          <Card><CardContent className="p-10 text-center text-slate-600">You don&apos;t have permission to manage users.</CardContent></Card>
        ) : (
          <>
            <div className="relative w-full sm:w-72">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
              <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search users…" className="pl-9" />
            </div>

            {loading ? (
              <div className="p-8 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading users…</div>
            ) : users.length === 0 ? (
              <Card><CardContent className="p-10 text-center">
                <ShieldCheck className="h-10 w-10 text-slate-300 mx-auto mb-3" />
                <p className="text-slate-600 mb-4">Add your first employee or invite a user.</p>
                <Button onClick={() => setOpen(true)}><Plus className="h-4 w-4 mr-1" /> Add user</Button>
              </CardContent></Card>
            ) : (
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
                {visible.map((u) => (
                  <Card key={u.id}>
                    <CardContent className="p-4 flex flex-col gap-2">
                      <div className="flex items-center gap-2.5 min-w-0">
                        <span className="h-9 w-9 grid place-items-center rounded-full bg-slate-100 text-slate-600 font-semibold shrink-0">{(u.firstName || u.userName || "U").charAt(0).toUpperCase()}</span>
                        <div className="min-w-0">
                          <div className="font-semibold text-slate-900 truncate">{u.firstName} {u.lastName}</div>
                          <div className="text-xs text-slate-500 truncate">{u.email?.endsWith("@noemail.local") ? u.userName : u.email}</div>
                        </div>
                        <Badge className={(u.isAdmin ? "bg-orange-100 text-orange-700" : "bg-slate-100 text-slate-600") + " ml-auto"}>{u.isAdmin ? "Admin" : "Staff"}</Badge>
                      </div>
                      <div className="flex items-center gap-2 pt-1">
                        <Button size="sm" variant="outline" className="flex-1" disabled={busyId === u.id} onClick={() => toggleAdmin(u)}>
                          {busyId === u.id ? <Loader2 className="h-4 w-4 animate-spin" /> : u.isAdmin ? <><ShieldOff className="h-4 w-4 mr-1" /> Remove admin</> : <><ShieldCheck className="h-4 w-4 mr-1" /> Make admin</>}
                        </Button>
                        <Button size="sm" variant="outline" className="text-rose-600 border-rose-200" onClick={() => setDelTarget(u)}><Trash2 className="h-4 w-4" /></Button>
                      </div>
                    </CardContent>
                  </Card>
                ))}
              </div>
            )}
          </>
        )}
      </main>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle>Add user</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <div><Label>First name *</Label><Input value={form.firstName} onChange={(e) => setForm({ ...form, firstName: e.target.value })} /></div>
              <div><Label>Last name *</Label><Input value={form.lastName} onChange={(e) => setForm({ ...form, lastName: e.target.value })} /></div>
            </div>
            <div><Label>Username *</Label><Input value={form.userName} onChange={(e) => setForm({ ...form, userName: e.target.value })} /></div>
            <div className="grid grid-cols-2 gap-3">
              <div><Label>Email</Label><Input type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} /></div>
              <div><Label>Phone</Label><Input value={form.phoneNumber} onChange={(e) => setForm({ ...form, phoneNumber: e.target.value })} /></div>
            </div>
            <div><Label>Temporary password *</Label><Input value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} placeholder="At least 6 characters" /></div>
            <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={form.isAdmin} onChange={(e) => setForm({ ...form, isAdmin: e.target.checked })} /> Make this user an admin</label>
            <p className="text-xs text-slate-500">The user is added to your current company; if an email is given, their login details are emailed to them.</p>
            <div className="flex justify-end gap-2 pt-1"><Button variant="ghost" onClick={() => setOpen(false)}>Cancel</Button><Button onClick={create} disabled={saving}>{saving ? "Adding…" : "Add user"}</Button></div>
          </div>
        </DialogContent>
      </Dialog>

      <ConfirmDeleteDialog
        open={!!delTarget}
        onOpenChange={(o) => { if (!o) setDelTarget(null) }}
        title="Remove user?"
        description={delTarget ? `${delTarget.firstName} ${delTarget.lastName} will lose login access.` : undefined}
        successTitle="User removed"
        errorTitle="Remove failed"
        onConfirm={async () => { if (delTarget) { await deleteEmployee(delTarget.id); await load() } }}
      />
    </BusinessOfficeShell>
  )
}
