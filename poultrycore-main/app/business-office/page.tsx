"use client"

// Business Office — the owner's headquarters (Prompt 2). Sits ABOVE the company
// dashboards: one place to see every company in the owner's business group,
// open any of them, create new ones, and jump to org-wide people/permissions.
//
// Built on the existing model: getMyCompanies() already returns every company
// the user owns or is a member of (spCompany_GetByUserId, migration 117), and
// createCompany() now files the company under the owner (migration 117). So this
// is primarily a landing/navigation experience — no new backend required.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Building2, Bird, Droplets, ShoppingBag, Plus, Loader2, Users, ArrowRight, Check, Briefcase } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import {
  getMyCompanies, createCompany, sendCompanyWelcomeEmail, switchCompany,
  dashboardHomeForType, type Company, type CompanyType,
} from "@/lib/api/companies"

function typeIcon(type: string) {
  if (type === "Water") return Droplets
  if (type === "Poultry") return Bird
  if (type === "Generic") return ShoppingBag
  return Building2
}
function typeTone(type: string) {
  if (type === "Water") return "bg-sky-100 text-sky-700"
  if (type === "Poultry") return "bg-orange-100 text-orange-700"
  if (type === "Generic") return "bg-violet-100 text-violet-700"
  return "bg-slate-100 text-slate-700"
}

export default function BusinessOfficePage() {
  const router = useRouter()
  const { toast } = useToast()
  const logout = useLogout()
  const permissions = usePermissions()
  const setCompanies = useAuthStore((s) => s.setCompanies)
  const setActiveCompany = useAuthStore((s) => s.setActiveCompany)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const user = useAuthStore((s) => s.user)
  const userEmail = user?.email

  const [companies, setLocal] = useState<Company[]>([])
  const [loading, setLoading] = useState(true)
  const [openingId, setOpeningId] = useState<string | null>(null)

  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState<{ name: string; type: CompanyType; email: string; phoneNumber: string }>({
    name: "", type: "Water", email: "", phoneNumber: "",
  })

  const isAdmin = permissions.isAdmin

  async function load() {
    setLoading(true)
    try {
      const list = await getMyCompanies()
      setLocal(list); setCompanies(list)
    } catch (e: any) {
      toast({ title: "Could not load your Business Office", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }
  useEffect(() => { void load() }, []) // eslint-disable-line react-hooks/exhaustive-deps

  async function openCompany(c: Company) {
    setOpeningId(c.farmId)
    try {
      const res = await switchCompany(c.farmId)
      setActiveCompany(res.farmId, res.farmName, c.type, res.accessToken.token)
      router.push(dashboardHomeForType(c.type))
    } catch (e: any) {
      toast({ title: "Couldn't open company", description: e?.message ?? String(e), variant: "destructive" })
      setOpeningId(null)
    }
  }

  async function create() {
    if (!form.name.trim()) return toast({ title: "Company name is required", variant: "destructive" })
    setSaving(true)
    try {
      await createCompany({ name: form.name, type: form.type, email: form.email || undefined, phoneNumber: form.phoneNumber || undefined })
      toast({ title: `Created ${form.name}` })
      const to = (form.email.trim() || userEmail || "").trim()
      if (to) { try { await sendCompanyWelcomeEmail({ email: to, companyName: form.name, companyType: form.type }) } catch {} }
      setOpen(false); setForm({ name: "", type: "Water", email: "", phoneNumber: "" })
      await load()
    } catch (e: any) { toast({ title: "Create failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  const counts = useMemo(() => {
    const by = (t: string) => companies.filter((c) => c.type === t).length
    return { total: companies.length, water: by("Water"), poultry: by("Poultry"), generic: by("Generic") }
  }, [companies])

  const officeName = (user as any)?.businessOfficeName || "Business Office"

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6 space-y-5">
          {/* Header */}
          <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div className="flex items-center gap-3 min-w-0">
              <div className="rounded-xl bg-orange-100 p-2.5 shrink-0"><Briefcase className="h-7 w-7 text-orange-600" /></div>
              <div className="min-w-0">
                <h1 className="text-2xl font-semibold text-slate-900 truncate">{officeName}</h1>
                <p className="text-sm text-slate-500">Your headquarters — all your companies in one place.</p>
              </div>
            </div>
            {isAdmin && (
              <div className="flex flex-wrap gap-2">
                <Button variant="outline" onClick={() => router.push("/employees")}><Users className="h-4 w-4 mr-1" /> Users &amp; Permissions</Button>
                <Button onClick={() => setOpen(true)}><Plus className="h-4 w-4 mr-1" /> New company</Button>
              </div>
            )}
          </div>

          {/* Summary tiles */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <SummaryTile label="Companies" value={loading ? "…" : counts.total} icon={Building2} />
            <SummaryTile label="Water" value={loading ? "…" : counts.water} icon={Droplets} tone="text-sky-600" />
            <SummaryTile label="Poultry" value={loading ? "…" : counts.poultry} icon={Bird} tone="text-orange-600" />
            <SummaryTile label="Generic" value={loading ? "…" : counts.generic} icon={ShoppingBag} tone="text-violet-600" />
          </div>

          {/* Company cards */}
          {loading ? (
            <div className="p-8 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading your companies…</div>
          ) : companies.length === 0 ? (
            <Card><CardContent className="p-10 text-center">
              <Building2 className="h-10 w-10 text-slate-300 mx-auto mb-3" />
              {isAdmin ? (
                <>
                  <p className="text-slate-600 mb-4">Create your first company to get started.</p>
                  <Button onClick={() => setOpen(true)}><Plus className="h-4 w-4 mr-1" /> Create company</Button>
                </>
              ) : (
                <p className="text-slate-600">You don&apos;t currently have access to any company. Contact your business owner or administrator.</p>
              )}
            </CardContent></Card>
          ) : (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              {companies.map((c) => {
                const Icon = typeIcon(c.type)
                const isActive = c.farmId === activeFarmId
                const opening = openingId === c.farmId
                return (
                  <Card key={c.farmId} className="overflow-hidden hover:shadow-md transition-shadow">
                    <CardContent className="p-4 flex flex-col gap-3">
                      <div className="flex items-start justify-between gap-2">
                        <div className="flex items-center gap-2.5 min-w-0">
                          <div className={`rounded-lg p-2 ${typeTone(c.type)}`}><Icon className="h-5 w-5" /></div>
                          <div className="min-w-0">
                            <div className="font-semibold text-slate-900 truncate">{c.name}</div>
                            <div className="text-xs text-slate-500">{c.role}{isActive ? " · current" : ""}</div>
                          </div>
                        </div>
                        <Badge className={typeTone(c.type)}>{c.type}</Badge>
                      </div>

                      {/* Type-specific metrics are loaded inside the company; keep
                          a neutral placeholder here so the card never breaks. */}
                      <div className="text-xs text-slate-400">Open to view today&apos;s figures &amp; alerts.</div>

                      <div className="flex items-center gap-2 pt-1">
                        <Button size="sm" className="flex-1" onClick={() => openCompany(c)} disabled={opening}>
                          {opening ? <><Loader2 className="h-4 w-4 mr-1 animate-spin" /> Opening…</>
                            : isActive ? <><Check className="h-4 w-4 mr-1" /> Open</>
                            : <>Open <ArrowRight className="h-4 w-4 ml-1" /></>}
                        </Button>
                        {isAdmin && (
                          <Button size="sm" variant="outline" onClick={() => router.push("/employees")}>Access</Button>
                        )}
                      </div>
                    </CardContent>
                  </Card>
                )
              })}
            </div>
          )}
        </main>
      </div>

      {/* Create company dialog */}
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle>Create new company</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <div><Label>Company type *</Label>
              <Select value={form.type} onValueChange={(v) => setForm({ ...form, type: v as CompanyType })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="Water">Water (sachet / bottled water)</SelectItem>
                  <SelectItem value="Poultry">Poultry farm</SelectItem>
                  <SelectItem value="Generic">Generic (shop / restaurant / hotel / pharmacy / any business)</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div><Label>Company name *</Label>
              <Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="e.g. Great Favour Water Co." /></div>
            <div><Label>Contact email</Label>
              <Input type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} /></div>
            <div><Label>Phone</Label>
              <Input value={form.phoneNumber} onChange={(e) => setForm({ ...form, phoneNumber: e.target.value })} /></div>
            <p className="text-xs text-slate-500">This company will be created under <span className="font-medium">{officeName}</span> and appear here and in your company switcher.</p>
            <div className="flex justify-end gap-2 pt-1">
              <Button variant="ghost" onClick={() => setOpen(false)}>Cancel</Button>
              <Button onClick={create} disabled={saving}>{saving ? "Creating…" : "Create"}</Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}

function SummaryTile({ label, value, icon: Icon, tone }: { label: string; value: string | number; icon: any; tone?: string }) {
  return (
    <Card><CardContent className="p-4 flex items-center gap-3">
      <Icon className={`h-6 w-6 ${tone ?? "text-slate-500"}`} />
      <div>
        <div className="text-xs text-slate-500">{label}</div>
        <div className="text-2xl font-semibold text-slate-900 tabular-nums">{value}</div>
      </div>
    </CardContent></Card>
  )
}
