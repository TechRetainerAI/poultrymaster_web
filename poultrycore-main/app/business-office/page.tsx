"use client"

// Business Office dashboard (Prompt 2 + 4). Renders inside the shared
// BusinessOfficeShell so it stays in "Business Office mode" — no company
// (Poultry/Water) sidebar. Pick a company to enter Company Mode.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Textarea } from "@/components/ui/textarea"
import {
  Building2, Bird, Droplets, ShoppingBag, Plus, Loader2, Users, ArrowRight, Check,
  ListTodo, HelpCircle, X, Megaphone, Activity, ChevronRight, Trash2, AlertTriangle, Info,
  ShieldAlert, Wrench, CreditCard, Sparkles, Briefcase,
} from "lucide-react"

function typeStrip(t: string) {
  if (t === "Water") return "bg-sky-400"
  if (t === "Poultry") return "bg-orange-400"
  if (t === "Generic") return "bg-violet-400"
  return "bg-slate-300"
}
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { BusinessOfficeShell } from "@/components/dashboard/business-office-shell"
import {
  getMyCompanies, createCompany, sendCompanyWelcomeEmail, switchCompany,
  dashboardHomeForType, type Company, type CompanyType,
} from "@/lib/api/companies"
import {
  listAnnouncements, setAnnouncementReceipt, createAnnouncement, deleteAnnouncement, type Announcement,
} from "@/lib/api/announcements"

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
function typeMetrics(type: string): string[] {
  if (type === "Water") return ["Production today", "Bags in stock", "Driver returns", "Today's sales"]
  if (type === "Poultry") return ["Eggs today", "Feed stock", "Mortality", "Today's sales"]
  if (type === "Generic") return ["Sales today", "Expenses today", "Low stock", "Customer debt"]
  return ["Today's sales", "Today's expenses", "Cash at hand", "Alerts"]
}
function annStyle(type: string): { tone: string; icon: any } {
  switch (type) {
    case "Critical": case "Security": return { tone: "border-rose-200 bg-rose-50 text-rose-700", icon: ShieldAlert }
    case "Warning": return { tone: "border-amber-200 bg-amber-50 text-amber-700", icon: AlertTriangle }
    case "Payment": return { tone: "border-orange-200 bg-orange-50 text-orange-700", icon: CreditCard }
    case "Maintenance": return { tone: "border-slate-200 bg-slate-50 text-slate-700", icon: Wrench }
    case "FeatureUpdate": return { tone: "border-violet-200 bg-violet-50 text-violet-700", icon: Sparkles }
    case "Success": return { tone: "border-emerald-200 bg-emerald-50 text-emerald-700", icon: Check }
    default: return { tone: "border-blue-200 bg-blue-50 text-blue-700", icon: Info }
  }
}
const ANN_TYPES = ["Info", "Success", "Warning", "Critical", "Maintenance", "FeatureUpdate", "Payment", "Security"]

export default function BusinessOfficePage() {
  const router = useRouter()
  const { toast } = useToast()
  const permissions = usePermissions()
  const setCompanies = useAuthStore((s) => s.setCompanies)
  const setActiveCompany = useAuthStore((s) => s.setActiveCompany)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const user = useAuthStore((s) => s.user)
  const userEmail = user?.email
  const isAdmin = permissions.isAdmin

  const [companies, setLocal] = useState<Company[]>([])
  const [loading, setLoading] = useState(true)
  const [openingId, setOpeningId] = useState<string | null>(null)
  const [q, setQ] = useState("")
  const [typeFilter, setTypeFilter] = useState<string>("all")

  const [announcements, setAnnouncements] = useState<Announcement[]>([])
  const orgOwnerUserId = useMemo(() => companies.find((c) => c.ownerUserId)?.ownerUserId ?? null, [companies])
  const [postOpen, setPostOpen] = useState(false)
  const [posting, setPosting] = useState(false)
  const [annForm, setAnnForm] = useState({ title: "", message: "", type: "Info", audienceRole: "All", isDismissible: true, requiresAck: false, actionLabel: "", actionUrl: "" })

  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState<{ name: string; type: CompanyType; email: string; phoneNumber: string }>({ name: "", type: "Water", email: "", phoneNumber: "" })

  const [officeName, setOfficeName] = useState("Business Office")
  const [userName, setUserName] = useState("")
  useEffect(() => {
    let bo = "", un = ""
    try { bo = localStorage.getItem("businessOfficeName") || ""; un = localStorage.getItem("username") || localStorage.getItem("userName") || "" } catch {}
    setOfficeName(((user as any)?.businessOfficeName) || bo || "Business Office")
    setUserName((user as any)?.username || un || "")
  }, [user])

  const roleLabel = isAdmin ? "Organization Admin" : "Staff"

  async function load() {
    setLoading(true)
    try { const list = await getMyCompanies(); setLocal(list); setCompanies(list) }
    catch (e: any) { toast({ title: "Could not load your Business Office", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }
  useEffect(() => { void load() }, []) // eslint-disable-line react-hooks/exhaustive-deps

  async function loadAnnouncements() {
    try { setAnnouncements(await listAnnouncements({ orgOwnerUserId, isAdmin, farmId: activeFarmId })) } catch {}
  }
  useEffect(() => { void loadAnnouncements() }, [orgOwnerUserId, isAdmin, activeFarmId]) // eslint-disable-line react-hooks/exhaustive-deps

  // The "New company" button moved to the top bar (shell). It opens this page's
  // create dialog via a custom event (when already here) or ?new=1 (on navigation).
  useEffect(() => {
    const openNew = () => setOpen(true)
    window.addEventListener("bo:new-company", openNew)
    try { if (new URLSearchParams(window.location.search).get("new") === "1") setOpen(true) } catch {}
    return () => window.removeEventListener("bo:new-company", openNew)
  }, [])

  async function annAction(a: Announcement, action: "Dismiss" | "Ack") {
    try {
      await setAnnouncementReceipt(a.announcementId, action)
      if (action === "Dismiss") setAnnouncements((p) => p.filter((x) => x.announcementId !== a.announcementId))
      else setAnnouncements((p) => p.map((x) => x.announcementId === a.announcementId ? { ...x, acknowledgedAt: new Date().toISOString() } : x))
    } catch (e: any) { toast({ title: "Action failed", description: e?.message, variant: "destructive" }) }
  }
  async function annDelete(a: Announcement) {
    if (!orgOwnerUserId) return
    try { await deleteAnnouncement(a.announcementId, orgOwnerUserId); setAnnouncements((p) => p.filter((x) => x.announcementId !== a.announcementId)) }
    catch (e: any) { toast({ title: "Delete failed", description: e?.message, variant: "destructive" }) }
  }
  async function postAnnouncement() {
    if (!annForm.title.trim()) return toast({ title: "Title is required", variant: "destructive" })
    setPosting(true)
    try {
      await createAnnouncement({ orgOwnerUserId, title: annForm.title, message: annForm.message, type: annForm.type, audienceRole: annForm.audienceRole, isDismissible: annForm.isDismissible, requiresAck: annForm.requiresAck, actionLabel: annForm.actionLabel || null, actionUrl: annForm.actionUrl || null })
      toast({ title: "Announcement posted" })
      setPostOpen(false); setAnnForm({ title: "", message: "", type: "Info", audienceRole: "All", isDismissible: true, requiresAck: false, actionLabel: "", actionUrl: "" })
      await loadAnnouncements()
    } catch (e: any) { toast({ title: "Post failed", description: e?.message, variant: "destructive" }) }
    finally { setPosting(false) }
  }

  async function openCompany(c: Company) {
    setOpeningId(c.farmId)
    try {
      const res = await switchCompany(c.farmId)
      setActiveCompany(res.farmId, res.farmName, c.type, res.accessToken.token)
      router.push(dashboardHomeForType(c.type))
    } catch (e: any) { toast({ title: "Couldn't open company", description: e?.message ?? String(e), variant: "destructive" }); setOpeningId(null) }
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

  const counts = useMemo(() => {
    const by = (t: string) => companies.filter((c) => c.type === t).length
    return { total: companies.length, water: by("Water"), poultry: by("Poultry"), generic: by("Generic") }
  }, [companies])
  const visible = useMemo(() => companies.filter((c) => {
    if (typeFilter !== "all" && c.type !== typeFilter) return false
    if (q && !(`${c.name} ${c.type} ${c.role}`.toLowerCase().includes(q.toLowerCase()))) return false
    return true
  }), [companies, q, typeFilter])

  return (
    <BusinessOfficeShell active="home">
      <main className="flex-1 overflow-auto p-4 sm:p-6 space-y-6">
        {/* Welcome + org actions now live in the coloured top bar (shell). The
            "New company" button there opens this page's create dialog via event. */}

        {/* Announcements */}
        <section id="notices">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-semibold text-slate-500 uppercase tracking-wide flex items-center gap-1.5"><Megaphone className="h-4 w-4" /> VisibilityCore Announcements</h3>
            {isAdmin && <Button size="sm" variant="outline" onClick={() => setPostOpen(true)}><Plus className="h-4 w-4 mr-1" /> Post</Button>}
          </div>
          {announcements.length === 0 ? (
            <div className="rounded-lg border border-dashed border-slate-200 p-4 text-sm text-slate-400">No new notifications.</div>
          ) : (
            <div className="space-y-2">
              {announcements.map((a) => {
                const st = annStyle(a.type); const Icon = st.icon; const acked = !!a.acknowledgedAt
                return (
                  <div key={a.announcementId} className={`rounded-xl border p-4 flex items-start gap-3 ${st.tone}`}>
                    <span className="h-9 w-9 grid place-items-center rounded-lg bg-white/70 shrink-0"><Icon className="h-5 w-5" /></span>
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="font-semibold text-slate-900">{a.title}</span>
                        <Badge className="bg-white/70 text-slate-700">{a.type}</Badge>
                        {a.requiresAck && <Badge className={acked ? "bg-emerald-100 text-emerald-700" : "bg-slate-200 text-slate-700"}>{acked ? "Acknowledged" : "Action needed"}</Badge>}
                      </div>
                      {a.message && <p className="text-sm text-slate-700 mt-0.5">{a.message}</p>}
                      <div className="mt-2 flex items-center gap-3">
                        {a.actionUrl && <a href={a.actionUrl} className="text-sm font-semibold underline underline-offset-2">{a.actionLabel || "Open"}</a>}
                        {a.requiresAck && !acked && <button onClick={() => annAction(a, "Ack")} className="text-sm font-semibold text-emerald-700 hover:underline">Acknowledge</button>}
                        {isAdmin && a.orgOwnerUserId && <button onClick={() => annDelete(a)} className="text-sm text-slate-500 hover:text-rose-600 inline-flex items-center gap-1"><Trash2 className="h-3.5 w-3.5" /> Delete</button>}
                      </div>
                    </div>
                    {a.isDismissible && <button onClick={() => annAction(a, "Dismiss")} className="text-slate-400 hover:text-slate-700 shrink-0" aria-label="Dismiss"><X className="h-4 w-4" /></button>}
                  </div>
                )
              })}
            </div>
          )}
        </section>

        {/* Summary tiles */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          <SummaryTile label="Companies" value={loading ? "…" : counts.total} icon={Building2} tone="text-slate-600" bg="bg-slate-100" />
          <SummaryTile label="Water" value={loading ? "…" : counts.water} icon={Droplets} tone="text-sky-600" bg="bg-sky-100" />
          <SummaryTile label="Poultry" value={loading ? "…" : counts.poultry} icon={Bird} tone="text-orange-600" bg="bg-orange-100" />
          <SummaryTile label="Generic" value={loading ? "…" : counts.generic} icon={ShoppingBag} tone="text-violet-600" bg="bg-violet-100" />
        </div>

        {/* Companies */}
        <section>
          <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 mb-3">
            <h2 className="text-lg font-semibold text-slate-900">Your companies</h2>
            <div className="flex gap-2">
              <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search companies…" className="w-full sm:w-56" />
              <Select value={typeFilter} onValueChange={setTypeFilter}>
                <SelectTrigger className="w-36"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All types</SelectItem>
                  <SelectItem value="Water">Water</SelectItem>
                  <SelectItem value="Poultry">Poultry</SelectItem>
                  <SelectItem value="Generic">Generic</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
          {loading ? (
            <div className="p-8 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading your companies…</div>
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
                const Icon = typeIcon(c.type); const opening = openingId === c.farmId
                return (
                  <Card key={c.farmId} className="overflow-hidden hover:shadow-lg hover:-translate-y-0.5 transition-all">
                    <div className={`h-1 ${typeStrip(c.type)}`} />
                    <CardContent className="p-4 flex flex-col gap-3">
                      <div className="flex items-start justify-between gap-2">
                        <div className="flex items-center gap-2.5 min-w-0">
                          <div className={`rounded-lg p-2 ${typeTone(c.type)}`}><Icon className="h-5 w-5" /></div>
                          <div className="min-w-0"><div className="font-semibold text-slate-900 truncate">{c.name}</div><div className="text-xs text-slate-500">Role: {c.role}</div></div>
                        </div>
                        <Badge className={typeTone(c.type)}>{c.type}</Badge>
                      </div>
                      <div className="grid grid-cols-2 gap-2">
                        {typeMetrics(c.type).filter((m) => isAdmin || !/sales|debt|expenses|cash/i.test(m)).slice(0, 4).map((m) => (
                          <div key={m} className="rounded-lg bg-slate-50 px-2.5 py-1.5"><div className="text-[11px] text-slate-500 truncate">{m}</div><div className="text-sm font-semibold text-slate-700">—</div></div>
                        ))}
                      </div>
                      <div className="flex items-center gap-2 pt-1">
                        <Button size="sm" className="flex-1" onClick={() => openCompany(c)} disabled={opening}>
                          {opening ? <><Loader2 className="h-4 w-4 mr-1 animate-spin" /> Opening…</> : <>Open <ArrowRight className="h-4 w-4 ml-1" /></>}
                        </Button>
                        {isAdmin && <Button size="sm" variant="outline" onClick={() => router.push("/business-office/users")}>Access</Button>}
                      </div>
                    </CardContent>
                  </Card>
                )
              })}
            </div>
          )}
        </section>

        {/* My Tasks + Recent activity */}
        <div className="grid lg:grid-cols-2 gap-4">
          <section id="tasks">
            <Card><CardContent className="p-5">
              <div className="flex items-center gap-2 mb-3"><ListTodo className="h-5 w-5 text-slate-500" /> <h3 className="font-semibold">My Tasks</h3></div>
              <div className="text-center py-8 text-slate-400"><Check className="h-8 w-8 mx-auto mb-2 text-emerald-400" /> You&apos;re all caught up.</div>
            </CardContent></Card>
          </section>
          <section>
            <Card><CardContent className="p-5">
              <div className="flex items-center gap-2 mb-3"><Activity className="h-5 w-5 text-slate-500" /> <h3 className="font-semibold">Recent activity</h3></div>
              <div className="text-center py-8 text-slate-400">Activity from your companies will appear here.</div>
            </CardContent></Card>
          </section>
        </div>

        {/* Quick actions */}
        <section>
          <h3 className="text-sm font-semibold text-slate-500 uppercase tracking-wide mb-2">Quick actions</h3>
          <div className="flex flex-wrap gap-2">
            {isAdmin && <QuickLink onClick={() => setOpen(true)} icon={Plus} label="Create company" />}
            {isAdmin && <QuickLink onClick={() => router.push("/business-office/users")} icon={Users} label="Manage users" />}
            <QuickLink onClick={() => router.push("/business-office/companies")} icon={Building2} label="All companies" />
            <QuickLink onClick={() => router.push("/business-office/help")} icon={HelpCircle} label="Help center" />
          </div>
        </section>
      </main>

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
            <div><Label>Company name *</Label><Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="e.g. Great Favour Water Co." /></div>
            <div><Label>Contact email</Label><Input type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} /></div>
            <div><Label>Phone</Label><Input value={form.phoneNumber} onChange={(e) => setForm({ ...form, phoneNumber: e.target.value })} /></div>
            <p className="text-xs text-slate-500">Created under <span className="font-medium">{officeName}</span>; appears here and in your switcher.</p>
            <div className="flex justify-end gap-2 pt-1"><Button variant="ghost" onClick={() => setOpen(false)}>Cancel</Button><Button onClick={create} disabled={saving}>{saving ? "Creating…" : "Create"}</Button></div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Post announcement dialog */}
      <Dialog open={postOpen} onOpenChange={setPostOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle>Post an announcement</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <div><Label>Title *</Label><Input value={annForm.title} onChange={(e) => setAnnForm({ ...annForm, title: e.target.value })} placeholder="e.g. Subscription renewal due" /></div>
            <div><Label>Message</Label><Textarea value={annForm.message} onChange={(e) => setAnnForm({ ...annForm, message: e.target.value })} rows={3} /></div>
            <div className="grid grid-cols-2 gap-3">
              <div><Label>Type</Label>
                <Select value={annForm.type} onValueChange={(v) => setAnnForm({ ...annForm, type: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{ANN_TYPES.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent>
                </Select>
              </div>
              <div><Label>Audience</Label>
                <Select value={annForm.audienceRole} onValueChange={(v) => setAnnForm({ ...annForm, audienceRole: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent><SelectItem value="All">Everyone</SelectItem><SelectItem value="Admin">Admins only</SelectItem><SelectItem value="Staff">Staff only</SelectItem></SelectContent>
                </Select>
              </div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div><Label>Action label (optional)</Label><Input value={annForm.actionLabel} onChange={(e) => setAnnForm({ ...annForm, actionLabel: e.target.value })} placeholder="e.g. Renew now" /></div>
              <div><Label>Action URL (optional)</Label><Input value={annForm.actionUrl} onChange={(e) => setAnnForm({ ...annForm, actionUrl: e.target.value })} placeholder="https://…" /></div>
            </div>
            <div className="flex items-center gap-6">
              <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={annForm.isDismissible} onChange={(e) => setAnnForm({ ...annForm, isDismissible: e.target.checked })} /> Dismissible</label>
              <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={annForm.requiresAck} onChange={(e) => setAnnForm({ ...annForm, requiresAck: e.target.checked })} /> Requires acknowledgement</label>
            </div>
            <div className="flex justify-end gap-2 pt-1"><Button variant="ghost" onClick={() => setPostOpen(false)}>Cancel</Button><Button onClick={postAnnouncement} disabled={posting}>{posting ? "Posting…" : "Post announcement"}</Button></div>
          </div>
        </DialogContent>
      </Dialog>
    </BusinessOfficeShell>
  )
}

function SummaryTile({ label, value, icon: Icon, tone, bg }: { label: string; value: string | number; icon: any; tone?: string; bg?: string }) {
  return (
    <Card className="border-slate-200 hover:shadow-sm transition-shadow"><CardContent className="p-4 flex items-center gap-3">
      <span className={`h-11 w-11 grid place-items-center rounded-xl ${bg ?? "bg-slate-100"}`}><Icon className={`h-5 w-5 ${tone ?? "text-slate-600"}`} /></span>
      <div><div className="text-xs font-medium text-slate-500">{label}</div><div className="text-2xl font-bold text-slate-900 tabular-nums">{value}</div></div>
    </CardContent></Card>
  )
}
function QuickLink({ onClick, icon: Icon, label }: { onClick: () => void; icon: any; label: string }) {
  return (
    <button onClick={onClick} className="inline-flex items-center gap-2 rounded-lg border border-slate-200 bg-white px-3.5 py-2 text-sm font-medium text-slate-700 hover:border-slate-300 hover:bg-slate-50 transition">
      <Icon className="h-4 w-4 text-slate-500" /> {label} <ChevronRight className="h-4 w-4 text-slate-300" />
    </button>
  )
}
