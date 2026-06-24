"use client"

// Business Office — the organization headquarters (Prompt 2 + Prompt 4).
//
// STRICT MODE SEPARATION: this page has its OWN neutral shell (sidebar + header)
// — it deliberately does NOT use the company DashboardSidebar/Header, so it never
// shows Poultry/Water/Generic modules (Farm, Production, Egg Tracker, etc.). It's
// the org-level landing: pick a company to enter "Company Mode".
//
// Permission-aware throughout: admins get management actions + access controls;
// staff get a clean "open my company / my tasks" view. Built on getMyCompanies
// (already org-scoped via migration 117) — no company data leaks in here.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import {
  Briefcase, Building2, Bird, Droplets, ShoppingBag, Plus, Loader2, Users, ArrowRight, Check,
  Search, Bell, ListTodo, HelpCircle, LogOut, Menu, X, Megaphone, ShieldCheck, Activity, ChevronRight,
  Trash2, AlertTriangle, Info, ShieldAlert, Wrench, CreditCard, Sparkles,
} from "lucide-react"
import { Textarea } from "@/components/ui/textarea"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import {
  getMyCompanies, createCompany, sendCompanyWelcomeEmail, switchCompany,
  dashboardHomeForType, type Company, type CompanyType,
} from "@/lib/api/companies"
import {
  listAnnouncements, setAnnouncementReceipt, createAnnouncement, deleteAnnouncement,
  type Announcement,
} from "@/lib/api/announcements"

// Visual style per announcement type.
function annStyle(type: string): { tone: string; icon: any } {
  switch (type) {
    case "Critical":
    case "Security":     return { tone: "border-rose-200 bg-rose-50 text-rose-700", icon: ShieldAlert }
    case "Warning":      return { tone: "border-amber-200 bg-amber-50 text-amber-700", icon: AlertTriangle }
    case "Payment":      return { tone: "border-orange-200 bg-orange-50 text-orange-700", icon: CreditCard }
    case "Maintenance":  return { tone: "border-slate-200 bg-slate-50 text-slate-700", icon: Wrench }
    case "FeatureUpdate":return { tone: "border-violet-200 bg-violet-50 text-violet-700", icon: Sparkles }
    case "Success":      return { tone: "border-emerald-200 bg-emerald-50 text-emerald-700", icon: Check }
    default:             return { tone: "border-blue-200 bg-blue-50 text-blue-700", icon: Info }
  }
}
const ANN_TYPES = ["Info", "Success", "Warning", "Critical", "Maintenance", "FeatureUpdate", "Payment", "Security"]

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
// Per-company-type metric labels (graceful placeholders — a cross-company
// summary API is a future enhancement, so values show "—" for now).
function typeMetrics(type: string): string[] {
  if (type === "Water") return ["Production today", "Bags in stock", "Driver returns", "Today's sales"]
  if (type === "Poultry") return ["Eggs today", "Feed stock", "Mortality", "Today's sales"]
  if (type === "Generic") return ["Sales today", "Expenses today", "Low stock", "Customer debt"]
  return ["Today's sales", "Today's expenses", "Cash at hand", "Alerts"]
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
  const isAdmin = permissions.isAdmin

  const [companies, setLocal] = useState<Company[]>([])
  const [loading, setLoading] = useState(true)
  const [openingId, setOpeningId] = useState<string | null>(null)
  const [drawer, setDrawer] = useState(false)

  // Announcements (real, from the backend)
  const [announcements, setAnnouncements] = useState<Announcement[]>([])
  const orgOwnerUserId = useMemo(() => companies.find((c) => c.ownerUserId)?.ownerUserId ?? null, [companies])
  const [postOpen, setPostOpen] = useState(false)
  const [posting, setPosting] = useState(false)
  const [annForm, setAnnForm] = useState({ title: "", message: "", type: "Info", audienceRole: "All", isDismissible: true, requiresAck: false, actionLabel: "", actionUrl: "" })

  // Filters / search
  const [q, setQ] = useState("")
  const [typeFilter, setTypeFilter] = useState<string>("all")

  // Create company
  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState<{ name: string; type: CompanyType; email: string; phoneNumber: string }>({
    name: "", type: "Water", email: "", phoneNumber: "",
  })

  const [officeName, setOfficeName] = useState("Business Office")
  const [orgCode, setOrgCode] = useState("")
  const [userName, setUserName] = useState("")
  useEffect(() => {
    let bo = "", code = "", un = ""
    try {
      bo = localStorage.getItem("businessOfficeName") || ""
      code = localStorage.getItem("myOrgCode") || ""
      un = localStorage.getItem("username") || localStorage.getItem("userName") || ""
    } catch {}
    setOfficeName(((user as any)?.businessOfficeName) || bo || "Business Office")
    setOrgCode(((user as any)?.organizationCode || code || "").toUpperCase())
    setUserName((user as any)?.username || un || "")
  }, [user])

  const roleLabel = isAdmin ? "Organization Admin" : "Staff"

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

  // Load announcements (platform-wide on mount; org-scoped once companies load).
  async function loadAnnouncements() {
    try { setAnnouncements(await listAnnouncements({ orgOwnerUserId, isAdmin, farmId: activeFarmId })) } catch {}
  }
  useEffect(() => { void loadAnnouncements() }, [orgOwnerUserId, isAdmin, activeFarmId]) // eslint-disable-line react-hooks/exhaustive-deps

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
      await createAnnouncement({
        orgOwnerUserId, title: annForm.title, message: annForm.message, type: annForm.type,
        audienceRole: annForm.audienceRole, isDismissible: annForm.isDismissible, requiresAck: annForm.requiresAck,
        actionLabel: annForm.actionLabel || null, actionUrl: annForm.actionUrl || null,
      })
      toast({ title: "Announcement posted" })
      setPostOpen(false)
      setAnnForm({ title: "", message: "", type: "Info", audienceRole: "All", isDismissible: true, requiresAck: false, actionLabel: "", actionUrl: "" })
      await loadAnnouncements()
    } catch (e: any) { toast({ title: "Post failed", description: e?.message, variant: "destructive" }) }
    finally { setPosting(false) }
  }

  async function openCompany(c: Company) {
    setOpeningId(c.farmId)
    try {
      const res = await switchCompany(c.farmId)
      setActiveCompany(res.farmId, res.farmName, c.type, res.accessToken.token)
      router.push(dashboardHomeForType(c.type)) // enter Company Mode
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

  const visible = useMemo(() => {
    return companies.filter((c) => {
      if (typeFilter !== "all" && c.type !== typeFilter) return false
      if (q && !(`${c.name} ${c.type} ${c.role}`.toLowerCase().includes(q.toLowerCase()))) return false
      return true
    })
  }, [companies, q, typeFilter])

  // ---- Sidebar items (permission-aware; only real destinations) ----
  const navMain = [
    { href: "/business-office", label: "Business Office", icon: Briefcase, active: true },
    { href: "/companies", label: "Companies", icon: Building2 },
    { href: "#tasks", label: "My Tasks", icon: ListTodo },
    { href: "#notices", label: "Notifications", icon: Bell },
  ]
  const navAdmin = isAdmin ? [
    { href: "/employees", label: "Users & Permissions", icon: ShieldCheck },
  ] : []
  const navFooter = [
    { href: "/help", label: "Help Center", icon: HelpCircle },
  ]

  const SidebarBody = () => (
    <div className="flex h-full flex-col">
      <div className="flex items-center gap-2 px-4 h-16 border-b border-slate-800">
        <span className="inline-flex h-8 w-8 items-center justify-center rounded-lg bg-orange-500 text-white shrink-0">
          <Briefcase className="h-5 w-5" />
        </span>
        <div className="min-w-0">
          <div className="text-white font-bold leading-tight truncate">VisibilityCore</div>
          <div className="text-[11px] text-slate-400 leading-tight">Business Office</div>
        </div>
      </div>
      <nav className="flex-1 overflow-y-auto py-3 px-2 space-y-5 text-sm">
        <NavGroup title="Main" items={navMain} />
        {navAdmin.length > 0 && <NavGroup title="People & Access" items={navAdmin} />}
        <NavGroup title="Help" items={navFooter} />
      </nav>
      <div className="border-t border-slate-800 p-2">
        <button onClick={logout} className="flex w-full items-center gap-3 px-3 py-2.5 rounded-md text-slate-300 hover:bg-slate-800 hover:text-white">
          <LogOut className="h-5 w-5 text-slate-400" /> Logout
        </button>
      </div>
    </div>
  )

  function NavGroup({ title, items }: { title: string; items: { href: string; label: string; icon: any; active?: boolean }[] }) {
    return (
      <div>
        <div className="px-3 pb-1 text-[10px] font-semibold uppercase tracking-wider text-slate-500">{title}</div>
        <div className="space-y-0.5">
          {items.map((it) => {
            const Icon = it.icon
            const cls = `flex items-center gap-3 px-3 py-2.5 rounded-md transition-colors ${it.active ? "bg-slate-700 text-white" : "text-slate-300 hover:bg-slate-800 hover:text-white"}`
            const inner = <><Icon className={`h-5 w-5 shrink-0 ${it.active ? "text-orange-300" : "text-slate-400"}`} /> <span className="truncate">{it.label}</span></>
            return it.href.startsWith("#")
              ? <a key={it.label} href={it.href} onClick={() => setDrawer(false)} className={cls}>{inner}</a>
              : <Link key={it.label} href={it.href} onClick={() => setDrawer(false)} className={cls}>{inner}</Link>
          })}
        </div>
      </div>
    )
  }

  return (
    <div className="flex h-screen bg-slate-50">
      {/* Sidebar — desktop */}
      <aside className="hidden lg:block w-64 bg-slate-900 shrink-0"><SidebarBody /></aside>

      {/* Sidebar — mobile drawer */}
      {drawer && (
        <div className="lg:hidden fixed inset-0 z-50">
          <div className="absolute inset-0 bg-black/50" onClick={() => setDrawer(false)} />
          <div className="absolute left-0 top-0 bottom-0 w-64 bg-slate-900 shadow-xl"><SidebarBody /></div>
        </div>
      )}

      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        {/* Neutral Business Office header (NOT the company header) */}
        <header className="h-16 bg-white border-b border-slate-200 flex items-center gap-3 px-4 sm:px-6 shrink-0">
          <button className="lg:hidden h-9 w-9 grid place-items-center rounded-lg border border-slate-200" onClick={() => setDrawer(true)} aria-label="Menu"><Menu className="h-5 w-5" /></button>
          <div className="min-w-0">
            <div className="text-[11px] uppercase tracking-wide text-slate-400 leading-tight">Business Office</div>
            <div className="font-semibold text-slate-900 truncate leading-tight">{officeName}{isAdmin && orgCode && <span className="ml-2 text-xs font-mono font-normal text-slate-400">{orgCode}</span>}</div>
          </div>
          <div className="ml-auto flex items-center gap-2">
            <a href="#notices" className="h-9 w-9 grid place-items-center rounded-lg hover:bg-slate-100 text-slate-500" aria-label="Notifications"><Bell className="h-5 w-5" /></a>
            <div className="flex items-center gap-2 pl-2">
              <span className="hidden sm:block text-sm text-slate-600">{userName || "Account"}</span>
              <span className="h-8 w-8 grid place-items-center rounded-full bg-orange-100 text-orange-700 text-sm font-semibold">{(userName || "U").charAt(0).toUpperCase()}</span>
            </div>
          </div>
        </header>

        <main className="flex-1 overflow-auto p-4 sm:p-6 space-y-6">
          {/* A. Context header */}
          <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900">Welcome{userName ? `, ${userName}` : ""}</h1>
              <p className="text-sm text-slate-500">Your headquarters for <span className="font-medium text-slate-700">{officeName}</span> · Role: {roleLabel}</p>
            </div>
            <div className="flex flex-wrap gap-2">
              {isAdmin ? (
                <>
                  <Button variant="outline" onClick={() => router.push("/employees")}><Users className="h-4 w-4 mr-1" /> Users &amp; Permissions</Button>
                  <Button onClick={() => setOpen(true)}><Plus className="h-4 w-4 mr-1" /> New company</Button>
                </>
              ) : (
                <Button variant="outline" asChild><a href="#tasks"><ListTodo className="h-4 w-4 mr-1" /> View my tasks</a></Button>
              )}
            </div>
          </div>

          {/* B. Announcements / Notifications */}
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
                  const st = annStyle(a.type)
                  const Icon = st.icon
                  const acked = !!a.acknowledgedAt
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
                          {isAdmin && a.orgOwnerUserId && (
                            <button onClick={() => annDelete(a)} className="text-sm text-slate-500 hover:text-rose-600 inline-flex items-center gap-1"><Trash2 className="h-3.5 w-3.5" /> Delete</button>
                          )}
                        </div>
                      </div>
                      {a.isDismissible && <button onClick={() => annAction(a, "Dismiss")} className="text-slate-400 hover:text-slate-700 shrink-0" aria-label="Dismiss"><X className="h-4 w-4" /></button>}
                    </div>
                  )
                })}
              </div>
            )}
          </section>

          {/* C. Summary cards */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <SummaryTile label="Companies" value={loading ? "…" : counts.total} icon={Building2} />
            <SummaryTile label="Water" value={loading ? "…" : counts.water} icon={Droplets} tone="text-sky-600" />
            <SummaryTile label="Poultry" value={loading ? "…" : counts.poultry} icon={Bird} tone="text-orange-600" />
            <SummaryTile label="Generic" value={loading ? "…" : counts.generic} icon={ShoppingBag} tone="text-violet-600" />
          </div>

          {/* D. Companies */}
          <section>
            <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 mb-3">
              <h2 className="text-lg font-semibold text-slate-900">Your companies</h2>
              <div className="flex gap-2">
                <div className="relative">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                  <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search companies…" className="pl-9 w-full sm:w-56" />
                </div>
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
                {isAdmin ? (
                  <><p className="text-slate-600 mb-4">Create your first company to get started.</p>
                    <Button onClick={() => setOpen(true)}><Plus className="h-4 w-4 mr-1" /> Create company</Button></>
                ) : (
                  <p className="text-slate-600">You don&apos;t currently have access to any company. Contact your Business Office administrator.</p>
                )}
              </CardContent></Card>
            ) : visible.length === 0 ? (
              <Card><CardContent className="p-10 text-center text-slate-500">No companies match your search.</CardContent></Card>
            ) : (
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                {visible.map((c) => {
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
                              <div className="text-xs text-slate-500">Role: {c.role}{isActive ? " · current" : ""}</div>
                            </div>
                          </div>
                          <Badge className={typeTone(c.type)}>{c.type}</Badge>
                        </div>

                        {/* Permission-aware metrics. Values are placeholders until a
                            cross-company summary API exists; financial labels are
                            hidden for non-admins. */}
                        <div className="grid grid-cols-2 gap-2">
                          {typeMetrics(c.type).filter((m) => isAdmin || !/sales|debt|expenses|cash/i.test(m)).slice(0, 4).map((m) => (
                            <div key={m} className="rounded-lg bg-slate-50 px-2.5 py-1.5">
                              <div className="text-[11px] text-slate-500 truncate">{m}</div>
                              <div className="text-sm font-semibold text-slate-700">—</div>
                            </div>
                          ))}
                        </div>

                        <div className="flex items-center gap-2 pt-1">
                          <Button size="sm" className="flex-1" onClick={() => openCompany(c)} disabled={opening}>
                            {opening ? <><Loader2 className="h-4 w-4 mr-1 animate-spin" /> Opening…</>
                              : isActive ? <><Check className="h-4 w-4 mr-1" /> Open</>
                              : <>Open <ArrowRight className="h-4 w-4 ml-1" /></>}
                          </Button>
                          {isAdmin && <Button size="sm" variant="outline" onClick={() => router.push("/employees")}>Access</Button>}
                        </div>
                      </CardContent>
                    </Card>
                  )
                })}
              </div>
            )}
          </section>

          {/* E. My Tasks + F. Recent activity */}
          <div className="grid lg:grid-cols-2 gap-4">
            <section id="tasks">
              <Card><CardContent className="p-5">
                <div className="flex items-center gap-2 mb-3"><ListTodo className="h-5 w-5 text-slate-500" /> <h3 className="font-semibold">My Tasks</h3></div>
                <div className="text-center py-8 text-slate-400">
                  <Check className="h-8 w-8 mx-auto mb-2 text-emerald-400" />
                  You&apos;re all caught up.
                </div>
              </CardContent></Card>
            </section>
            <section>
              <Card><CardContent className="p-5">
                <div className="flex items-center gap-2 mb-3"><Activity className="h-5 w-5 text-slate-500" /> <h3 className="font-semibold">Recent activity</h3></div>
                <div className="text-center py-8 text-slate-400">Activity from your companies will appear here.</div>
              </CardContent></Card>
            </section>
          </div>

          {/* G. Quick links */}
          <section>
            <h3 className="text-sm font-semibold text-slate-500 uppercase tracking-wide mb-2">Quick actions</h3>
            <div className="flex flex-wrap gap-2">
              {isAdmin && <QuickLink onClick={() => setOpen(true)} icon={Plus} label="Create company" />}
              {isAdmin && <QuickLink onClick={() => router.push("/employees")} icon={Users} label="Manage users" />}
              <QuickLink onClick={() => router.push("/companies")} icon={Building2} label="All companies" />
              <QuickLink onClick={() => router.push("/help")} icon={HelpCircle} label="Help center" />
            </div>
          </section>
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
            <p className="text-xs text-slate-500">Created under <span className="font-medium">{officeName}</span>; appears here and in your switcher.</p>
            <div className="flex justify-end gap-2 pt-1">
              <Button variant="ghost" onClick={() => setOpen(false)}>Cancel</Button>
              <Button onClick={create} disabled={saving}>{saving ? "Creating…" : "Create"}</Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Post announcement dialog (admin) */}
      <Dialog open={postOpen} onOpenChange={setPostOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle>Post an announcement</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <div><Label>Title *</Label>
              <Input value={annForm.title} onChange={(e) => setAnnForm({ ...annForm, title: e.target.value })} placeholder="e.g. Subscription renewal due" /></div>
            <div><Label>Message</Label>
              <Textarea value={annForm.message} onChange={(e) => setAnnForm({ ...annForm, message: e.target.value })} rows={3} /></div>
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
                  <SelectContent>
                    <SelectItem value="All">Everyone</SelectItem>
                    <SelectItem value="Admin">Admins only</SelectItem>
                    <SelectItem value="Staff">Staff only</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div><Label>Action label (optional)</Label>
                <Input value={annForm.actionLabel} onChange={(e) => setAnnForm({ ...annForm, actionLabel: e.target.value })} placeholder="e.g. Renew now" /></div>
              <div><Label>Action URL (optional)</Label>
                <Input value={annForm.actionUrl} onChange={(e) => setAnnForm({ ...annForm, actionUrl: e.target.value })} placeholder="https://…" /></div>
            </div>
            <div className="flex items-center gap-6">
              <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={annForm.isDismissible} onChange={(e) => setAnnForm({ ...annForm, isDismissible: e.target.checked })} /> Dismissible</label>
              <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={annForm.requiresAck} onChange={(e) => setAnnForm({ ...annForm, requiresAck: e.target.checked })} /> Requires acknowledgement</label>
            </div>
            <div className="flex justify-end gap-2 pt-1">
              <Button variant="ghost" onClick={() => setPostOpen(false)}>Cancel</Button>
              <Button onClick={postAnnouncement} disabled={posting}>{posting ? "Posting…" : "Post announcement"}</Button>
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

function QuickLink({ onClick, icon: Icon, label }: { onClick: () => void; icon: any; label: string }) {
  return (
    <button onClick={onClick} className="inline-flex items-center gap-2 rounded-lg border border-slate-200 bg-white px-3.5 py-2 text-sm font-medium text-slate-700 hover:border-slate-300 hover:bg-slate-50 transition">
      <Icon className="h-4 w-4 text-slate-500" /> {label} <ChevronRight className="h-4 w-4 text-slate-300" />
    </button>
  )
}
