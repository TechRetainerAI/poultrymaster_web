"use client"

// The frame every Pharmacy page shares (migration 511): sidebar, header, the page title,
// and one tab row that links the five pharmacy pages together, so a user can move
// Medicines -> Batches -> Till -> Prescriptions -> Reports without the menu.

import { useEffect, type ReactNode } from "react"
import Link from "next/link"
import { usePathname, useRouter } from "next/navigation"
import { ArrowLeft, BarChart3, Boxes, ClipboardList, Pill, ShoppingCart } from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useGenericModules } from "@/hooks/use-generic-modules"
import { cn } from "@/lib/utils"

export const PHARMACY_PAGES = [
  { href: "/generic-medicines",        label: "Medicines",        icon: Pill },
  { href: "/generic-batches",          label: "Batches & expiry", icon: Boxes },
  { href: "/generic-pharmacy-pos",     label: "Pharmacy till",    icon: ShoppingCart },
  { href: "/generic-prescriptions",    label: "Prescriptions",    icon: ClipboardList },
  { href: "/generic-pharmacy-reports", label: "Pharmacy reports", icon: BarChart3 },
] as const

export function PharmacyShell({ title, subtitle, actions, children, wide }: {
  title: string
  subtitle?: string
  actions?: ReactNode
  children: ReactNode
  wide?: boolean
}) {
  const router = useRouter()
  const pathname = usePathname()
  const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const { industry } = useGenericModules()

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") router.replace("/dashboard")
  }, [activeFarmType, router])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className={cn("mx-auto space-y-4", wide ? "max-w-7xl" : "max-w-6xl")}>
            <div className="flex flex-wrap items-center gap-3">
              <button onClick={() => router.back()} className="rounded-full p-1 hover:bg-slate-200 transition" title="Go back">
                <ArrowLeft className="w-5 h-5 text-slate-600" />
              </button>
              <div className="flex-1 min-w-0">
                <h1 className="text-xl font-semibold text-slate-900">{title}</h1>
                {subtitle && <p className="text-sm text-slate-500">{subtitle}</p>}
              </div>
              {actions && <div className="flex flex-wrap items-center gap-2">{actions}</div>}
            </div>

            <nav className="flex gap-1 overflow-x-auto rounded-lg border bg-white p-1" aria-label="Pharmacy pages">
              {PHARMACY_PAGES.map((p) => {
                const Icon = p.icon
                const active = pathname === p.href
                return (
                  <Link key={p.href} href={p.href}
                    className={cn(
                      "flex items-center gap-1.5 whitespace-nowrap rounded-md px-3 py-1.5 text-sm transition",
                      active ? "bg-emerald-600 text-white" : "text-slate-600 hover:bg-slate-100",
                    )}>
                    <Icon className="h-4 w-4" /> {p.label}
                  </Link>
                )
              })}
            </nav>

            {industry && industry !== "Pharmacy" && (
              <div className="rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-800">
                These pages are made for pharmacies and chemical shops. This business is set up as
                “{industry}”, so they are not in its menu. You can still use them.
              </div>
            )}

            {children}
          </div>
        </main>
      </div>
    </div>
  )
}
