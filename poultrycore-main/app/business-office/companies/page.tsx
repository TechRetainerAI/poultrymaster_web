"use client"

// Business Office → Companies (Prompt 4). Full company list inside the Business
// Office shell — opening a company switches into Company Mode.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Building2, Bird, Droplets, ShoppingBag, Plus, Loader2, ArrowRight, Check } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { BusinessOfficeShell } from "@/components/dashboard/business-office-shell"
import {
  getMyCompanies, createCompany, sendCompanyWelcomeEmail, switchCompany,
  dashboardHomeForType, type Company, type CompanyType,
} from "@/lib/api/companies"

function typeIcon(t: string) { return t === "Water" ? Droplets : t === "Poultry" ? Bird : t === "Generic" ? ShoppingBag : Building2 }
function typeTone(t: string) { return t === "Water" ? "bg-sky-100 text-sky-700" : t === "Poultry" ? "bg-orange-100 text-orange-700" : t === "Generic" ? "bg-violet-100 text-violet-700" : "bg-slate-100 text-slate-700" }
function typeStrip(t: string) { return t === "Water" ? "bg-sky-400" : t === "Poultry" ? "bg-orange-400" : t === "Generic" ? "bg-violet-400" : "bg-slate-300" }

export default function BusinessOfficeCompaniesPage() {
  const router = useRouter()
  const { toast } = useToast()
  const permissions = usePermissions()
  const isAdmin = permissions.isAdmin
  const setCompanies = useAuthStore((s) => s.setCompanies)
  const setActiveCompany = useAuthStore((s) => s.setActiveCompany)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const userEmail = useAuthStore((s) => s.user?.email)

  const [companies, setLocal] = useState<Company[]>([])
  const [loading, setLoading] = useState(true)
  const [openingId, setOpeningId] = useState<string | null>(null)
  const [q, setQ] = useState("")
  const [typeFilter, setTypeFilter] = useState("all")
  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState<{ name: string; type: CompanyType; email: string; phoneNumber: string }>({ name: "", type: "Water", email: "", phoneNumber: "" })

  async function load() {
    setLoading(true)
    try { const list = await getMyCompanies(); setLocal(list); setCompanies(list) }
    catch (e: any) { toast({ title: "Could not load companies", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }
  useEffect(() => { void load() }, []) // eslint-disable-line react-hooks/exhaustive-deps
  // Seed the search box from the Business Office header search (?q=).
  useEffect(() => { try { const v = new URLSearchParams(window.location.search).get("q"); if (v) setQ(v) } catch {} }, [])

  async function openCompany(c: Company) {
    setOpeningId(c.farmId)
    try { const res = await switchCompany(c.farmId); setActiveCompany(res.farmId, res.farmName, c.type, res.accessToken.token); router.push(dashboardHomeForType(c.type)) }
    catch (e: any) { toast({ title: "Couldn't open company", description: e?.message, variant: "destructive" }); setOpeningId(null) }
  }
  async function create() {
    if (!form.name.trim()) return toast({ title: "Company name is required", variant: "destructive" })
    setSaving(true)
    try {
      await createCompany({ name: form.name, type: form.type, email: form.email || undefined, phoneNumber: form.phoneNumber || undefined })
      toast({ title: `Created ${form.name}` })
      const to = (form.email.trim() || userEmail || "").trim()
      if (to) { try { await sendCompanyWelcomeEmail({ email: to, companyName: form.name, companyType: form.type }) } catch {} }
      setOpen(false); setForm({ name: "", type: "Water", email: "", phoneNumber: "" }); await load()
    } catch (e: any) { toast({ title: "Create failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  const visible = useMemo(() => companies.filter((c) => {
    if (typeFilter !== "all" && c.type !== typeFilter) return false
    if (q && !(`${c.name} ${c.type} ${c.role}`.toLowerCase().includes(q.toLowerCase()))) return false
    return true
  }), [companies, q, typeFilter])

  return (
    <BusinessOfficeShell active="companies">
      <main className="flex-1 overflow-auto p-4 sm:p-6 space-y-5">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div>
            <h1 className="text-2xl font-semibold text-slate-900">Companies</h1>
            <p className="text-sm text-slate-500">All companies in your Business Office. Open one to work inside it.</p>
          </div>
          {isAdmin && <Button onClick={() => setOpen(true)}><Plus className="h-4 w-4 mr-1" /> New company</Button>}
        </div>

        <div className="flex gap-2">
          <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search companies…" className="w-full sm:w-64" />
          <Select value={typeFilter} onValueChange={setTypeFilter}>
            <SelectTrigger className="w-36"><SelectValue /></SelectTrigger>
            <SelectContent><SelectItem value="all">All types</SelectItem><SelectItem value="Water">Water</SelectItem><SelectItem value="Poultry">Poultry</SelectItem><SelectItem value="Generic">Generic</SelectItem></SelectContent>
          </Select>
        </div>

        {loading ? (
          <div className="p-8 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
        ) : companies.length === 0 ? (
          <Card><CardContent className="p-10 text-center">
            <Building2 className="h-10 w-10 text-slate-300 mx-auto mb-3" />
            {isAdmin ? (<><p className="text-slate-600 mb-4">Create your first company to get started.</p><Button onClick={() => setOpen(true)}><Plus className="h-4 w-4 mr-1" /> Create company</Button></>)
              : (<p className="text-slate-600">You don&apos;t currently have access to any company. Contact your Business Office administrator.</p>)}
          </CardContent></Card>
        ) : visible.length === 0 ? (
          <Card><CardContent className="p-10 text-center text-slate-500">No companies match your search.</CardContent></Card>
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {visible.map((c) => {
              const Icon = typeIcon(c.type); const isActive = c.farmId === activeFarmId; const opening = openingId === c.farmId
              return (
                <Card key={c.farmId} className="overflow-hidden hover:shadow-lg hover:-translate-y-0.5 transition-all">
                  <div className={`h-1 ${typeStrip(c.type)}`} />
                  <CardContent className="p-4 flex flex-col gap-3">
                    <div className="flex items-start justify-between gap-2">
                      <div className="flex items-center gap-2.5 min-w-0">
                        <div className={`rounded-lg p-2 ${typeTone(c.type)}`}><Icon className="h-5 w-5" /></div>
                        <div className="min-w-0"><div className="font-semibold text-slate-900 truncate">{c.name}</div><div className="text-xs text-slate-500">Role: {c.role}{isActive ? " · current" : ""}</div></div>
                      </div>
                      <Badge className={typeTone(c.type)}>{c.type}</Badge>
                    </div>
                    <div className="flex items-center gap-2 pt-1">
                      <Button size="sm" className="flex-1" onClick={() => openCompany(c)} disabled={opening}>
                        {opening ? <><Loader2 className="h-4 w-4 mr-1 animate-spin" /> Opening…</> : isActive ? <><Check className="h-4 w-4 mr-1" /> Open</> : <>Open <ArrowRight className="h-4 w-4 ml-1" /></>}
                      </Button>
                      {isAdmin && <Button size="sm" variant="outline" onClick={() => router.push("/employees?bo=1")}>Access</Button>}
                    </div>
                  </CardContent>
                </Card>
              )
            })}
          </div>
        )}
      </main>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle>Create new company</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <div><Label>Company type *</Label>
              <Select value={form.type} onValueChange={(v) => setForm({ ...form, type: v as CompanyType })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent><SelectItem value="Water">Water (sachet / bottled water)</SelectItem><SelectItem value="Poultry">Poultry farm</SelectItem><SelectItem value="Generic">Generic (shop / restaurant / hotel / pharmacy)</SelectItem></SelectContent>
              </Select>
            </div>
            <div><Label>Company name *</Label><Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="e.g. Great Favour Water Co." /></div>
            <div><Label>Contact email</Label><Input type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} /></div>
            <div><Label>Phone</Label><Input value={form.phoneNumber} onChange={(e) => setForm({ ...form, phoneNumber: e.target.value })} /></div>
            <div className="flex justify-end gap-2 pt-1"><Button variant="ghost" onClick={() => setOpen(false)}>Cancel</Button><Button onClick={create} disabled={saving}>{saving ? "Creating…" : "Create"}</Button></div>
          </div>
        </DialogContent>
      </Dialog>
    </BusinessOfficeShell>
  )
}
