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
import { Briefcase, Building2, Bell, ListTodo, HelpCircle, LogOut, Menu, ShieldCheck, Settings, UserCog, Plus } from "lucide-react"
import { BoCompanySelector } from "@/components/dashboard/bo-company-selector"

type ActiveKey = "home" | "companies" | "employees" | "users" | "settings" | "org" | "help"

export function BusinessOfficeShell({ active, children }: { active: ActiveKey; children: ReactNode }) {
  const logout = useLogout()
  const router = useRouter()
  const pathname = usePathname()
  const permissions = usePermissions()
  const isAdmin = permissions.isAdmin
  const roleLabel = isAdmin ? "Organization Admin" : "Staff"

  // "New company" now lives in the top bar (banner removed). The create dialog
  // stays on the home page (it owns the company list refresh), so trigger it via
  // an event when already there, or navigate home with ?new=1 to open it.
  function goNewCompany() {
    if (pathname === "/business-office") window.dispatchEvent(new CustomEvent("bo:new-company"))
    else router.push("/business-office?new=1")
  }
  const user = useAuthStore((s) => s.user)
  const clearActiveCompany = useAuthStore((s) => s.clearActiveCompany)
  const [drawer, setDrawer] = useState(false)
  const [search, setSearch] = useState("")

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
  // Business group — one entry. Organization Profile, Users & Permissions and
  // Companies are tabs inside the Business Setup hub, so they no longer need
  // their own sidebar rows. (Employees removed here too — James, 2026-07-05.)
  const business = isAdmin ? [
    { key: "settings", href: "/business-office/setup", label: "Business Setup", icon: Settings },
  ] : []
  const footer = [{ key: "help", href: "/business-office/help", label: "Help Center", icon: HelpCircle }]

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

  const SidebarBody = () => (
    <div className="flex h-full flex-col">
      <Link href="/business-office" className="flex items-center gap-2 px-4 h-16 border-b border-slate-800">
        <span className="inline-flex h-8 w-8 items-center justify-center rounded-lg bg-orange-500 text-white shrink-0"><Briefcase className="h-5 w-5" /></span>
        <div className="min-w-0">
          <div className="text-white font-bold leading-tight truncate">VisibilityCore</div>
          <div className="text-[11px] text-slate-400 leading-tight">Business Office</div>
        </div>
      </Link>
      <nav className="flex-1 overflow-y-auto py-3 px-2 space-y-5 text-sm">
        {/* Home needs no group header — it's the one item above the groups. */}
        <Group items={main} />
        {business.length > 0 && <Group title="Business" items={business} />}
        <Group title="Support" items={footer} />
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
        {/* Brand-coloured top bar. Carries the welcome message + the org-level
            actions (Users & Permissions, New company) that used to sit in the
            page's dark welcome banner (James 2026-07-08). */}
        <header className="relative z-30 h-16 bg-gradient-to-r from-orange-600 to-amber-500 text-white border-b border-orange-700/30 flex items-center gap-3 px-4 sm:px-6 shrink-0 shadow-sm">
          <button className="lg:hidden h-9 w-9 grid place-items-center rounded-lg border border-white/25 text-white hover:bg-white/10" onClick={() => setDrawer(true)} aria-label="Menu"><Menu className="h-5 w-5" /></button>
          <div className="min-w-0">
            <div className="font-bold text-white truncate leading-tight">Welcome{userName ? `, ${userName}` : ""}</div>
            <div className="text-[11px] text-white/85 truncate leading-tight">{officeName} · {roleLabel}{isAdmin && orgCode && <span className="ml-2 font-mono text-white/70">{orgCode}</span>}</div>
          </div>

          {/* Doc 3 §10: global company selector (replaces the old search box). */}
          <BoCompanySelector />

          <div className="ml-auto flex items-center gap-2">
            {isAdmin && (
              <>
                <Link href="/business-office/setup?tab=users" className="hidden sm:inline-flex items-center gap-1.5 h-9 px-3 rounded-lg border border-white/30 bg-white/10 text-sm font-medium text-white hover:bg-white/20 transition-colors">
                  <ShieldCheck className="h-4 w-4" /> <span className="hidden lg:inline">Users &amp; Permissions</span><span className="lg:hidden">Users</span>
                </Link>
                <button onClick={goNewCompany} className="inline-flex items-center gap-1.5 h-9 px-3 rounded-lg bg-white text-orange-700 text-sm font-semibold hover:bg-orange-50 transition-colors shadow-sm">
                  <Plus className="h-4 w-4" /> <span className="hidden sm:inline">New company</span>
                </button>
              </>
            )}
            <Link href="/business-office#notices" className="h-9 w-9 grid place-items-center rounded-lg hover:bg-white/15 text-white/90" aria-label="Notifications"><Bell className="h-5 w-5" /></Link>
            <div className="flex items-center gap-2 pl-1">
              <span className="hidden xl:block text-sm text-white/90">{userName || "Account"}</span>
              <span className="h-8 w-8 grid place-items-center rounded-full bg-white/20 text-white text-sm font-semibold ring-1 ring-inset ring-white/30">{(userName || "U").charAt(0).toUpperCase()}</span>
            </div>
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
