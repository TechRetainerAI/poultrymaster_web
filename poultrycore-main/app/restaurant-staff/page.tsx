"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Plus, Trash2, Edit2, UserCog, Users, Shield, Phone, Mail, CheckCircle2, XCircle, Search } from "lucide-react"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import { Badge } from "@/components/ui/badge"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"

import { farmApiUrl, getAuthHeaders, getUserContext, readApiError } from "@/lib/api/config"

function activeFarmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company.")
  return farmId
}

interface StaffMember {
  restaurantStaffId: number; farmId: string; firstName: string; lastName: string
  phone: string; email?: string | null; role: string
  salaryType: string; basePay: number; isActive: boolean
  notes?: string | null; createdAt: string; updatedAt?: string | null
}

interface StaffInput {
  firstName: string; lastName: string; phone: string; email?: string | null
  role: string; salaryType?: string; basePay?: number; notes?: string | null
}

const RESTAURANT_ROLES = [
  { value: "Owner", label: "Owner", description: "Full access to everything", color: "bg-purple-100 text-purple-700", icon: "👑" },
  { value: "Manager", label: "Manager", description: "Manage staff, reports, settings, and daily operations", color: "bg-blue-100 text-blue-700", icon: "🏢" },
  { value: "HeadChef", label: "Head Chef", description: "Kitchen management, menu items, KDS", color: "bg-amber-100 text-amber-700", icon: "👨‍🍳" },
  { value: "Chef", label: "Chef / Cook", description: "Kitchen display, order prep", color: "bg-orange-100 text-orange-700", icon: "🍳" },
  { value: "Waiter", label: "Waiter / Server", description: "POS, take orders, manage tables", color: "bg-green-100 text-green-700", icon: "🍽️" },
  { value: "Cashier", label: "Cashier", description: "POS, process payments", color: "bg-emerald-100 text-emerald-700", icon: "💰" },
  { value: "Host", label: "Host / Hostess", description: "Reservations, waitlist, seating", color: "bg-pink-100 text-pink-700", icon: "🙋" },
  { value: "Bartender", label: "Bartender", description: "Bar orders, KDS bar station", color: "bg-indigo-100 text-indigo-700", icon: "🍸" },
  { value: "Driver", label: "Delivery Driver", description: "Delivery dispatch and tracking", color: "bg-sky-100 text-sky-700", icon: "🛵" },
  { value: "Other", label: "Other", description: "Custom role", color: "bg-gray-100 text-gray-700", icon: "👤" },
]

const ROLE_PERMISSIONS: Record<string, string[]> = {
  Owner: ["POS & Orders", "Kitchen Display", "Menu Management", "Floor Plan", "Reservations", "Online Ordering", "Delivery", "Staff & Roles", "Setup", "Reports"],
  Manager: ["POS & Orders", "Kitchen Display", "Menu Management", "Floor Plan", "Reservations", "Online Ordering", "Delivery", "Staff & Roles", "Setup", "Reports"],
  HeadChef: ["Kitchen Display", "Menu Management", "POS & Orders"],
  Chef: ["Kitchen Display"],
  Waiter: ["POS & Orders", "Floor Plan", "Reservations"],
  Cashier: ["POS & Orders"],
  Host: ["Reservations", "Floor Plan"],
  Bartender: ["Kitchen Display", "POS & Orders"],
  Driver: ["Delivery"],
  Other: [],
}

const SALARY_TYPES = ["Monthly", "Weekly", "Daily", "Hourly", "Commission"]

async function listStaff(role?: string): Promise<StaffMember[]> {
  const farmId = activeFarmId()
  const extra = role ? `&role=${encodeURIComponent(role)}` : ""
  const url = farmApiUrl(`/Restaurant/staff?farmId=${encodeURIComponent(farmId)}${extra}`)
  const res = await fetch(url, { headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}

async function createStaff(input: StaffInput): Promise<{ staffId: number }> {
  const farmId = activeFarmId()
  const url = farmApiUrl("/Restaurant/staff")
  const res = await fetch(url, { method: "POST", headers: getAuthHeaders(), body: JSON.stringify({ ...input, farmId }) })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}

async function updateStaff(id: number, input: StaffInput): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/staff/${id}?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "PUT", headers: getAuthHeaders(), body: JSON.stringify(input) })
  if (!res.ok) throw new Error(await readApiError(res))
}

async function deleteStaff(id: number): Promise<void> {
  const farmId = activeFarmId()
  const url = farmApiUrl(`/Restaurant/staff/${id}?farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { method: "DELETE", headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
}

export default function RestaurantStaffPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [loading, setLoading] = useState(true)
  const [staff, setStaff] = useState<StaffMember[]>([])
  const [search, setSearch] = useState("")
  const [filterRole, setFilterRole] = useState("all")
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState<StaffMember | null>(null)
  const [form, setForm] = useState<StaffInput>({ firstName: "", lastName: "", phone: "", role: "Waiter" })
  const [permDialogOpen, setPermDialogOpen] = useState(false)
  const [selectedRole, setSelectedRole] = useState<string>("")

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    loadStaff()
  }, [activeFarmType, router])

  async function loadStaff() {
    setLoading(true)
    try { setStaff(await listStaff()) }
    catch (e: any) { toast({ title: "Failed to load", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openDialog(s?: StaffMember) {
    if (s) { setEditing(s); setForm({ firstName: s.firstName, lastName: s.lastName, phone: s.phone, email: s.email, role: s.role, salaryType: s.salaryType, basePay: s.basePay, notes: s.notes }) }
    else { setEditing(null); setForm({ firstName: "", lastName: "", phone: "", role: "Waiter", salaryType: "Monthly", basePay: 0 }) }
    setDialogOpen(true)
  }

  async function save() {
    if (!form.firstName.trim() || !form.phone.trim()) { toast({ title: "Name and phone required", variant: "destructive" }); return }
    try {
      if (editing) await updateStaff(editing.restaurantStaffId, form)
      else await createStaff(form)
      toast({ title: editing ? "Staff updated" : "Staff member added" })
      setDialogOpen(false); loadStaff()
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  async function remove(id: number) {
    try { await deleteStaff(id); toast({ title: "Staff removed" }); loadStaff() }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  const filtered = staff.filter(s => {
    if (filterRole !== "all" && s.role !== filterRole) return false
    if (search && !`${s.firstName} ${s.lastName}`.toLowerCase().includes(search.toLowerCase())) return false
    return true
  })

  const roleCounts = RESTAURANT_ROLES.map(r => ({ ...r, count: staff.filter(s => s.role === r.value).length }))

  if (loading) return <PageSkeleton />

  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-6">
          <div className="max-w-6xl mx-auto space-y-6">
            {/* Header */}
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="h-10 w-10 rounded-lg bg-rose-100 flex items-center justify-center"><UserCog className="h-5 w-5 text-rose-600" /></div>
                <div>
                  <h1 className="text-2xl font-bold text-gray-900">Staff & Permissions</h1>
                  <p className="text-sm text-muted-foreground">{staff.length} team members across {new Set(staff.map(s => s.role)).size} roles</p>
                </div>
              </div>
              <Button className="bg-rose-600 hover:bg-rose-700" onClick={() => openDialog()}><Plus className="h-4 w-4 mr-2" /> Add Staff</Button>
            </div>

            {/* Role cards */}
            <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
              {roleCounts.filter(r => r.count > 0).map(r => (
                <Card key={r.value} className="cursor-pointer hover:border-rose-200 transition-all" onClick={() => setFilterRole(filterRole === r.value ? "all" : r.value)}>
                  <CardContent className="py-3 px-4">
                    <div className="flex items-center gap-2">
                      <span className="text-xl">{r.icon}</span>
                      <div>
                        <div className="font-bold text-lg">{r.count}</div>
                        <div className="text-xs text-muted-foreground">{r.label}</div>
                      </div>
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>

            {/* Roles & Permissions */}
            <Card>
              <CardHeader>
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <div className="h-9 w-9 rounded-lg bg-purple-100 flex items-center justify-center"><Shield className="h-5 w-5 text-purple-600" /></div>
                    <div>
                      <CardTitle className="text-lg">Roles & Permissions</CardTitle>
                      <CardDescription>Each role has predefined access to restaurant modules</CardDescription>
                    </div>
                  </div>
                </div>
              </CardHeader>
              <CardContent>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                  {RESTAURANT_ROLES.map(r => (
                    <div key={r.value} className={`p-4 rounded-xl border hover:shadow-sm transition-all cursor-pointer ${filterRole === r.value ? "border-rose-300 bg-rose-50/50" : ""}`}
                      onClick={() => { setSelectedRole(r.value); setPermDialogOpen(true) }}>
                      <div className="flex items-center gap-3">
                        <span className="text-2xl">{r.icon}</span>
                        <div className="flex-1">
                          <div className="flex items-center gap-2">
                            <h4 className="font-semibold text-gray-900">{r.label}</h4>
                            <Badge variant="secondary" className="text-[10px] h-4">{staff.filter(s => s.role === r.value).length}</Badge>
                          </div>
                          <p className="text-xs text-muted-foreground mt-0.5">{r.description}</p>
                        </div>
                        <div className="flex flex-wrap gap-1 max-w-[200px]">
                          {(ROLE_PERMISSIONS[r.value] || []).slice(0, 3).map(p => (
                            <Badge key={p} variant="outline" className="text-[9px] h-4 px-1">{p}</Badge>
                          ))}
                          {(ROLE_PERMISSIONS[r.value] || []).length > 3 && <Badge variant="outline" className="text-[9px] h-4 px-1">+{(ROLE_PERMISSIONS[r.value] || []).length - 3}</Badge>}
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>

            {/* Staff List */}
            <Card>
              <CardHeader>
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <div className="h-9 w-9 rounded-lg bg-green-100 flex items-center justify-center"><Users className="h-5 w-5 text-green-600" /></div>
                    <div>
                      <CardTitle className="text-lg">Team Members</CardTitle>
                      <CardDescription>{filtered.length} staff {filterRole !== "all" ? `(${filterRole})` : ""}</CardDescription>
                    </div>
                  </div>
                  <div className="flex gap-2">
                    <div className="relative">
                      <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                      <Input className="pl-9 h-9 w-[200px]" placeholder="Search staff..." value={search} onChange={e => setSearch(e.target.value)} />
                    </div>
                    <Select value={filterRole} onValueChange={setFilterRole}>
                      <SelectTrigger className="w-[150px] h-9"><SelectValue placeholder="All Roles" /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="all">All Roles</SelectItem>
                        {RESTAURANT_ROLES.map(r => <SelectItem key={r.value} value={r.value}>{r.icon} {r.label}</SelectItem>)}
                      </SelectContent>
                    </Select>
                  </div>
                </div>
              </CardHeader>
              <CardContent>
                {filtered.length === 0 ? (
                  <div className="text-center py-16 border-2 border-dashed rounded-xl">
                    <Users className="h-12 w-12 mx-auto text-gray-300 mb-3" />
                    <h3 className="font-medium text-gray-900 mb-1">{search || filterRole !== "all" ? "No staff match" : "No staff members yet"}</h3>
                    <p className="text-sm text-muted-foreground mb-4">Add your team members and assign their roles</p>
                    {!search && filterRole === "all" && <Button className="bg-rose-600 hover:bg-rose-700" onClick={() => openDialog()}><Plus className="h-4 w-4 mr-2" /> Add First Member</Button>}
                  </div>
                ) : (
                  <div className="space-y-2">
                    {filtered.map(s => {
                      const roleConfig = RESTAURANT_ROLES.find(r => r.value === s.role)
                      return (
                        <div key={s.restaurantStaffId} className="group flex items-center gap-4 p-4 border rounded-xl hover:border-rose-200 transition-all">
                          <div className={`h-11 w-11 rounded-xl flex items-center justify-center text-lg flex-shrink-0 ${roleConfig?.color || "bg-gray-100 text-gray-700"}`}>
                            {roleConfig?.icon || "👤"}
                          </div>
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center gap-2">
                              <h4 className="font-semibold text-gray-900">{s.firstName} {s.lastName}</h4>
                              <Badge className={`text-[10px] h-5 ${roleConfig?.color || "bg-gray-100 text-gray-700"} hover:${roleConfig?.color}`}>{roleConfig?.label || s.role}</Badge>
                              {!s.isActive && <Badge variant="secondary" className="text-[10px] h-4">Inactive</Badge>}
                            </div>
                            <div className="flex items-center gap-3 mt-1 text-xs text-muted-foreground">
                              <span className="flex items-center gap-1"><Phone className="h-3 w-3" />{s.phone}</span>
                              {s.email && <span className="flex items-center gap-1"><Mail className="h-3 w-3" />{s.email}</span>}
                              {s.basePay > 0 && <span>{s.basePay.toFixed(0)}/{s.salaryType}</span>}
                            </div>
                          </div>
                          <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                            <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => openDialog(s)}><Edit2 className="h-3.5 w-3.5" /></Button>
                            <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => remove(s.restaurantStaffId)}><Trash2 className="h-3.5 w-3.5 text-red-500" /></Button>
                          </div>
                        </div>
                      )
                    })}
                  </div>
                )}
              </CardContent>
            </Card>
          </div>
        </main>
      </div>

      {/* Staff Dialog */}
      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>{editing ? "Edit Staff Member" : "Add Staff Member"}</DialogTitle>
            <DialogDescription>Add team members and assign their restaurant role</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5"><Label>First Name <span className="text-rose-500">*</span></Label><Input value={form.firstName} onChange={e => setForm({ ...form, firstName: e.target.value })} className="h-10" /></div>
              <div className="space-y-1.5"><Label>Last Name</Label><Input value={form.lastName} onChange={e => setForm({ ...form, lastName: e.target.value })} className="h-10" /></div>
              <div className="space-y-1.5"><Label>Phone <span className="text-rose-500">*</span></Label><Input value={form.phone} onChange={e => setForm({ ...form, phone: e.target.value })} className="h-10" /></div>
              <div className="space-y-1.5"><Label>Email</Label><Input type="email" value={form.email || ""} onChange={e => setForm({ ...form, email: e.target.value })} className="h-10" /></div>
            </div>

            <div className="space-y-1.5">
              <Label>Role</Label>
              <div className="grid grid-cols-2 gap-2">
                {RESTAURANT_ROLES.map(r => (
                  <button key={r.value} type="button" onClick={() => setForm({ ...form, role: r.value })}
                    className={`flex items-center gap-2 p-2.5 rounded-lg border-2 text-left transition-all ${
                      form.role === r.value ? "border-rose-500 bg-rose-50 shadow-sm" : "border-gray-200 hover:border-gray-300"
                    }`}>
                    <span className="text-lg">{r.icon}</span>
                    <div>
                      <div className={`text-xs font-semibold ${form.role === r.value ? "text-rose-700" : "text-gray-700"}`}>{r.label}</div>
                      <div className="text-[10px] text-muted-foreground">{r.description.slice(0, 30)}</div>
                    </div>
                  </button>
                ))}
              </div>
            </div>

            <div className="grid grid-cols-2 gap-3 pt-2 border-t">
              <div className="space-y-1.5">
                <Label>Pay Type</Label>
                <Select value={form.salaryType || "Monthly"} onValueChange={v => setForm({ ...form, salaryType: v })}>
                  <SelectTrigger className="h-10"><SelectValue /></SelectTrigger>
                  <SelectContent>{SALARY_TYPES.map(s => <SelectItem key={s} value={s}>{s}</SelectItem>)}</SelectContent>
                </Select>
              </div>
              <div className="space-y-1.5">
                <Label>Base Pay</Label>
                <Input type="number" step="0.01" value={form.basePay || 0} onChange={e => setForm({ ...form, basePay: parseFloat(e.target.value) || 0 })} className="h-10" />
              </div>
            </div>

            <div className="space-y-1.5"><Label>Notes</Label><Input value={form.notes || ""} onChange={e => setForm({ ...form, notes: e.target.value })} placeholder="Optional notes" className="h-10" /></div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialogOpen(false)}>Cancel</Button>
            <Button onClick={save} className="bg-rose-600 hover:bg-rose-700">{editing ? "Update" : "Add Member"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Role Permissions Dialog */}
      <Dialog open={permDialogOpen} onOpenChange={setPermDialogOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <span className="text-xl">{RESTAURANT_ROLES.find(r => r.value === selectedRole)?.icon}</span>
              {RESTAURANT_ROLES.find(r => r.value === selectedRole)?.label} — Permissions
            </DialogTitle>
            <DialogDescription>{RESTAURANT_ROLES.find(r => r.value === selectedRole)?.description}</DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            {["POS & Orders", "Kitchen Display", "Menu Management", "Floor Plan", "Reservations", "Online Ordering", "Delivery", "Staff & Roles", "Setup", "Reports"].map(perm => {
              const has = (ROLE_PERMISSIONS[selectedRole] || []).includes(perm)
              return (
                <div key={perm} className={`flex items-center justify-between p-3 rounded-lg ${has ? "bg-green-50" : "bg-gray-50"}`}>
                  <span className="text-sm font-medium text-gray-700">{perm}</span>
                  {has ? (
                    <div className="flex items-center gap-1 text-green-600"><CheckCircle2 className="h-4 w-4" /><span className="text-xs font-medium">Allowed</span></div>
                  ) : (
                    <div className="flex items-center gap-1 text-gray-400"><XCircle className="h-4 w-4" /><span className="text-xs">No access</span></div>
                  )}
                </div>
              )
            })}
          </div>
          <div className="pt-2 border-t">
            <p className="text-xs text-muted-foreground">
              <strong>{staff.filter(s => s.role === selectedRole).length}</strong> team member{staff.filter(s => s.role === selectedRole).length !== 1 ? "s" : ""} with this role
            </p>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setPermDialogOpen(false)}>Close</Button></DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
