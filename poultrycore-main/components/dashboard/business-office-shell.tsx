"use client"

// Business Office shell (Prompt 4) — the neutral org-level chrome (sidebar +
// header) shared by every Business Office page, so Companies, Users &
// Permissions, etc. stay INSIDE the Business Office instead of jumping to the
// company (Poultry/Water) sidebar.

import { ReactNode, useEffect, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { Input } from "@/components/ui/input"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { usePermissions } from "@/hooks/use-permissions"
import { Briefcase, Building2, Bell, ListTodo, HelpCircle, LogOut, Menu, ShieldCheck, Settings, Search } from "lucide-react"

type ActiveKey = "home" | "companies" | "users" | "settings" | "help"

export function BusinessOfficeShell({ active, children }: { active: ActiveKey; children: ReactNode }) {
  const logout = useLogout()
  const router = useRouter()
  const permissions = usePermissions()
  const isAdmin = permissions.isAdmin
  const user = useAuthStore((s) => s.user)
  const [drawer, setDrawer] = useState(false)
  const [search, setSearch] = useState("")

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
    { key: "companies", href: "/business-office/companies", label: "Companies", icon: Building2 },
    { key: "tasks", href: "/business-office#tasks", label: "My Tasks", icon: ListTodo },
    { key: "notices", href: "/business-office#notices", label: "Notifications", icon: Bell },
  ]
  // Users & Permissions and Business Setup open the SAME pages used inside a
  // company (/employees, /settings) with ?bo=1 so they render in this shell —
  // same data, same features, just kept in the Business Office.
  const admin = isAdmin ? [{ key: "users", href: "/employees?bo=1", label: "Users & Permissions", icon: ShieldCheck }] : []
  const settings = isAdmin ? [{ key: "settings", href: "/settings?bo=1", label: "Business Setup", icon: Settings }] : []
  const footer = [{ key: "help", href: "/business-office/help", label: "Help Center", icon: HelpCircle }]

  function Group({ title, items }: { title: string; items: { key: string; href: string; label: string; icon: any }[] }) {
    return (
      <div>
        <div className="px-3 pb-1 text-[10px] font-semibold uppercase tracking-wider text-slate-500">{title}</div>
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
        <Group title="Main" items={main} />
        {admin.length > 0 && <Group title="People & Access" items={admin} />}
        {settings.length > 0 && <Group title="Settings" items={settings} />}
        <Group title="Help" items={footer} />
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
        <header className="h-16 bg-white/90 backdrop-blur border-b border-slate-200 flex items-center gap-3 px-4 sm:px-6 shrink-0 shadow-[0_1px_2px_rgba(15,23,42,0.04)]">
          <button className="lg:hidden h-9 w-9 grid place-items-center rounded-lg border border-slate-200" onClick={() => setDrawer(true)} aria-label="Menu"><Menu className="h-5 w-5" /></button>
          <div className="min-w-0">
            <div className="text-[11px] uppercase tracking-wide text-slate-400 leading-tight">Business Office</div>
            <div className="font-semibold text-slate-900 truncate leading-tight">{officeName}{isAdmin && orgCode && <span className="ml-2 text-xs font-mono font-normal text-slate-400">{orgCode}</span>}</div>
          </div>

          {/* Search — finds companies across the Business Office. */}
          <form
            onSubmit={(e) => { e.preventDefault(); router.push(`/business-office/companies${search.trim() ? `?q=${encodeURIComponent(search.trim())}` : ""}`) }}
            className="hidden md:block relative ml-4 flex-1 max-w-sm"
          >
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
            <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search companies…" className="pl-9 h-9 bg-slate-50" />
          </form>

          <div className="ml-auto flex items-center gap-2">
            <Link href="/business-office#notices" className="h-9 w-9 grid place-items-center rounded-lg hover:bg-slate-100 text-slate-500" aria-label="Notifications"><Bell className="h-5 w-5" /></Link>
            <div className="flex items-center gap-2 pl-2">
              <span className="hidden sm:block text-sm text-slate-600">{userName || "Account"}</span>
              <span className="h-8 w-8 grid place-items-center rounded-full bg-orange-100 text-orange-700 text-sm font-semibold">{(userName || "U").charAt(0).toUpperCase()}</span>
            </div>
          </div>
        </header>
        {children}
      </div>
    </div>
  )
}
