"use client"

// Business Office shell (Prompt 4) — the neutral org-level chrome (sidebar +
// header) shared by every Business Office page, so Companies, Users &
// Permissions, etc. stay INSIDE the Business Office instead of jumping to the
// company (Poultry/Water) sidebar.

import { ReactNode, useEffect, useState } from "react"
import Link from "next/link"
import { useRouter, usePathname } from "next/navigation"
import { Input } from "@/components/ui/input"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { usePermissions } from "@/hooks/use-permissions"
import { useToast } from "@/hooks/use-toast"
import { Briefcase, Building2, Bird, Droplets, ShoppingBag, Bell, HelpCircle, LogOut, Menu, Settings, Plus, Loader2 } from "lucide-react"
import { BoCompanySelector } from "@/components/dashboard/bo-company-selector"
import { getMyCompanies, switchCompany, dashboardHomeForType, type Company } from "@/lib/api/companies"
import { companyColorMap, companyInitial, FALLBACK_COMPANY_COLOR } from "@/lib/utils/company-color"
import { cn } from "@/lib/utils"

// Same type→icon mapping the header selector and company cards use.
function typeIcon(type?: string | null) {
  if (type === "Water") return Droplets
  if (type === "Poultry") return Bird
  if (type === "Generic") return ShoppingBag
  return Building2
}

type ActiveKey = "home" | "companies" | "employees" | "users" | "settings" | "org" | "help"

export function BusinessOfficeShell({ active, children }: { active: ActiveKey; children: ReactNode }) {
  const logout = useLogout()
  const router = useRouter()
  const pathname = usePathname()
  const permissions = usePermissions()
  const isAdmin = permissions.isAdmin
  const roleLabel = isAdmin ? "Organization Admin" : "Staff"

  // "New company" lives as the last row of the sidebar companies list (it was
  // also duplicated in the top bar; that copy is gone). The create dialog stays
  // on the home page (it owns the company list refresh), so trigger it via an
  // event when already there, or navigate home with ?new=1 to open it.
  function goNewCompany() {
    if (pathname === "/business-office") window.dispatchEvent(new CustomEvent("bo:new-company"))
    else router.push("/business-office?new=1")
  }
  const user = useAuthStore((s) => s.user)
  const clearActiveCompany = useAuthStore((s) => s.clearActiveCompany)
  const setActiveCompany = useAuthStore((s) => s.setActiveCompany)
  const { toast } = useToast()
  const [drawer, setDrawer] = useState(false)
  const [search, setSearch] = useState("")

  // Companies listed directly in the sidebar, under Business Office. Refreshed
  // when the home page creates one (it fires bo:companies-changed after create).
  const [companies, setCompanies] = useState<Company[]>([])
  const [companiesLoading, setCompaniesLoading] = useState(true)
  const [openingId, setOpeningId] = useState<string | null>(null)
  useEffect(() => {
    let cancelled = false
    const load = () => {
      getMyCompanies()
        .then((list) => { if (!cancelled) setCompanies(list) })
        .catch(() => {})
        .finally(() => { if (!cancelled) setCompaniesLoading(false) })
    }
    load()
    window.addEventListener("bo:companies-changed", load)
    return () => { cancelled = true; window.removeEventListener("bo:companies-changed", load) }
  }, [])

  // Clicking a company leaves the Business Office and enters Company Mode —
  // same switch-then-route flow as the header selector and the company cards.
  async function openCompany(c: Company) {
    setOpeningId(c.farmId)
    try {
      const res = await switchCompany(c.farmId)
      setActiveCompany(res.farmId ?? c.farmId, res.farmName ?? c.name, c.type, res.accessToken?.token)
      setDrawer(false)
      router.push(dashboardHomeForType(c.type))
    } catch (e: any) {
      toast({ title: "Could not open company", description: e?.message ?? String(e), variant: "destructive" })
      setOpeningId(null)
    }
  }

  // Doc 3 §9: being inside the Business Office IS the company-neutral state, so
  // no company should read as "active/current" here (a stale activeFarmId from a
  // previous session would otherwise mark a card "· current"). Clear it whenever
  // any BO page mounts. Opening a company navigates away (unmounts this shell),
  // so this never fights the selector's setActiveCompany.
  useEffect(() => { try { clearActiveCompany() } catch {} }, [clearActiveCompany])

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

  const main = [
    { key: "home", href: "/business-office", label: "Business Office", icon: Briefcase },
    // My Tasks + Notifications hidden from the sidebar until the feature is
    // built out (James, 2026-08-06). Restore these two lines to bring them back.
    // { key: "tasks", href: "/business-office#tasks", label: "My Tasks", icon: ListTodo },
    // { key: "notices", href: "/business-office#notices", label: "Notifications", icon: Bell },
  ]
  // Administration group — one entry, and it sits at the BOTTOM of the nav
  // (below the companies list) since day-to-day work is picking a company, not
  // setup. Organization Profile, Users & Permissions and Companies are tabs
  // inside it.
  const business = isAdmin ? [
    { key: "settings", href: "/business-office/setup", label: "Administration", icon: Settings },
  ] : []

  function Group({ title, items }: { title?: string; items: { key: string; href: string; label: string; icon: any }[] }) {
    return (
      <div>
        {title && <div className="px-3 pb-1 text-[10px] font-semibold uppercase tracking-wider text-slate-500">{title}</div>}
        <div className="space-y-0.5">
          {items.map((it) => {
            const Icon = it.icon
            const isActive = it.key === active
            const base = "flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors"
            const cls = isActive
              ? `${base} bg-slate-800 text-white border-l-2 border-orange-400 pl-[10px]`
              : `${base} text-slate-300 hover:bg-slate-800/60 hover:text-white`
            const inner = <><Icon className={`h-[18px] w-[18px] shrink-0 ${isActive ? "text-orange-300" : "text-slate-400"}`} /> <span className="truncate">{it.label}</span></>
            return <Link key={it.key} href={it.href} onClick={() => setDrawer(false)} className={cls}>{inner}</Link>
          })}
        </div>
      </div>
    )
  }

  // Every company the user can reach, listed right under Business Office, with
  // "New company" as the last row. Clicking a name switches into that company.
  function CompaniesGroup() {
    // One colour each, assigned across the whole list so no two companies in
    // view collide. Recomputed only when the list itself changes.
    const colours = companyColorMap(companies)
    const rowBase = "w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors text-slate-300 hover:bg-slate-800/60 hover:text-white"
    // Company rows carry their own tint and hover, so they drop the shared
    // hover:bg — leaving it on would fight the colour on hover.
    const companyRowBase = "w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors text-slate-200 hover:text-white"
    return (
      <div>
        <div className="space-y-0.5">
          {companiesLoading ? (
            <div className="flex items-center gap-2 px-3 py-2.5 text-sm text-slate-500">
              <Loader2 className="h-4 w-4 animate-spin" /> Loading…
            </div>
          ) : companies.length === 0 ? (
            <div className="px-3 py-2 text-xs text-slate-500">No companies yet.</div>
          ) : companies.map((c) => {
            const Icon = typeIcon(c.type)
            const opening = openingId === c.farmId
            const colour = colours.get(c.farmId) ?? FALLBACK_COMPANY_COLOR
            return (
              <button
                key={c.farmId}
                onClick={() => openCompany(c)}
                disabled={!!openingId}
                title={`${c.name} · ${c.type}`}
                className={cn(companyRowBase, colour.row, "text-left disabled:opacity-60")}
              >
                <span
                  aria-hidden
                  className={cn(
                    "h-[22px] w-[22px] shrink-0 rounded-md grid place-items-center text-[11px] font-bold leading-none",
                    colour.chip,
                  )}
                >
                  {companyInitial(c.name)}
                </span>
                <span className="truncate">{c.name}</span>
                {/* Type moves to the right of the name now the chip has the left
                    slot — the colour identifies the company, the icon its kind. */}
                {opening
                  ? <Loader2 className="h-3.5 w-3.5 ml-auto shrink-0 animate-spin text-slate-300" />
                  : <Icon className="h-3.5 w-3.5 ml-auto shrink-0 text-slate-400" />}
              </button>
            )
          })}
          {isAdmin && (
            <button
              onClick={() => { setDrawer(false); goNewCompany() }}
              className={`${rowBase} text-left text-orange-300 hover:text-orange-200`}
            >
              <Plus className="h-[18px] w-[18px] shrink-0 text-orange-300" />
              <span className="truncate">New company</span>
            </button>
          )}
        </div>
      </div>
    )
  }

  const SidebarBody = () => (
    <div className="flex h-full flex-col">
      <Link href="/business-office" className="flex items-center gap-2 px-4 h-16 border-b border-slate-800">
        <span className="inline-flex h-8 w-8 items-center justify-center rounded-lg bg-orange-500 text-white shrink-0"><Briefcase className="h-5 w-5" /></span>
        <div className="min-w-0">
          <div className="text-white font-bold leading-tight truncate">VisibilityCore</div>
          <div className="text-[11px] text-slate-400 leading-tight">Business Office</div>
        </div>
      </Link>
      {/* flex-col + gap (not space-y) so the Setup group can mt-auto itself to
          the very bottom of the rail, right above Logout. */}
      <nav className="flex-1 overflow-y-auto py-3 px-2 flex flex-col gap-5 text-sm">
        {/* Home needs no group header — it's the one item above the groups. */}
        <Group items={main} />
        <CompaniesGroup />
        {/* Administration sits at the bottom of the rail, directly above
            Logout. No group header — it'd just repeat the row. Help moved to
            the top bar, beside the account name. */}
        <div className="mt-auto pt-2">
          <Group items={business} />
        </div>
      </nav>
      <div className="border-t border-slate-800 p-2">
        <button onClick={logout} className="flex w-full items-center gap-3 px-3 py-2.5 rounded-md text-slate-300 hover:bg-slate-800 hover:text-white">
          <LogOut className="h-5 w-5 text-slate-400" /> Logout
        </button>
      </div>
    </div>
  )

  return (
    <div className="flex h-screen bg-slate-50">
      <aside className="hidden lg:block w-64 bg-slate-900 shrink-0"><SidebarBody /></aside>
      {drawer && (
        <div className="lg:hidden fixed inset-0 z-50">
          <div className="absolute inset-0 bg-black/50" onClick={() => setDrawer(false)} />
          <div className="absolute left-0 top-0 bottom-0 w-64 bg-slate-900 shadow-xl"><SidebarBody /></div>
        </div>
      )}
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        {/* Brand-coloured top bar. Carries the welcome message, the company
            selector, and Help beside the account name. (Users & Permissions
            lives in Administration → its tab; "New company" is a row in the
            sidebar companies list.) */}
        <header className="relative z-30 h-16 bg-gradient-to-r from-orange-600 to-amber-500 text-white border-b border-orange-700/30 flex items-center gap-3 px-4 sm:px-6 shrink-0 shadow-sm">
          <button className="lg:hidden h-9 w-9 grid place-items-center rounded-lg border border-white/25 text-white hover:bg-white/10" onClick={() => setDrawer(true)} aria-label="Menu"><Menu className="h-5 w-5" /></button>
          <div className="min-w-0">
            <div className="font-bold text-white truncate leading-tight">Welcome{userName ? `, ${userName}` : ""}</div>
            <div className="text-[11px] text-white/85 truncate leading-tight">{officeName} · {roleLabel}{isAdmin && orgCode && <span className="ml-2 font-mono text-white/70">{orgCode}</span>}</div>
          </div>

          {/* Doc 3 §10: global company selector (replaces the old search box). */}
          <BoCompanySelector />

          <div className="ml-auto flex items-center gap-2">
            <Link href="/business-office#notices" className="h-9 w-9 grid place-items-center rounded-lg hover:bg-white/15 text-white/90" aria-label="Notifications"><Bell className="h-5 w-5" /></Link>
            <div className="flex items-center gap-2 pl-1">
              <span className="hidden xl:block text-sm text-white/90">{userName || "Account"}</span>
              <span className="h-8 w-8 grid place-items-center rounded-full bg-white/20 text-white text-sm font-semibold ring-1 ring-inset ring-white/30">{(userName || "U").charAt(0).toUpperCase()}</span>
            </div>
            {/* Help moved out of the sidebar footer to the far top-right — last
                item in the bar, after the account. Icon-only below sm. */}
            <Link
              href="/business-office/help"
              aria-label="Help"
              aria-current={active === "help" ? "page" : undefined}
              className={`inline-flex items-center gap-1.5 h-9 px-2.5 rounded-lg text-sm font-medium transition-colors ${
                active === "help" ? "bg-white/20 text-white" : "text-white/90 hover:bg-white/15"
              }`}
            >
              <HelpCircle className="h-5 w-5" /> <span className="hidden sm:inline">Help</span>
            </Link>
          </div>
        </header>

        {/* Mobile: the company selector doesn't fit in the top bar, so show it as
            a full-width row underneath (desktop keeps it inline in the header). */}
        <div className="md:hidden relative z-20 bg-white border-b border-slate-200 px-4 py-2">
          <BoCompanySelector className="relative w-full" />
        </div>

        {children}
      </div>
    </div>
  )
}
