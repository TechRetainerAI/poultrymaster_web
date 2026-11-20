"use client"

// Water Alerts (migration 465): everything that needs attention, on one page --
// daily closing, production, deliveries, stock, equipment and money. Derived on
// every read; an alert disappears as soon as its cause is fixed. The header
// bell counts the same rows (Critical + Warning).

import { useEffect } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { AlertTriangle, ArrowRight, Bell, CheckCircle2, Info, Loader2, RefreshCw } from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { cn } from "@/lib/utils"
import { useFmt } from "@/lib/currency"
import { useLogout } from "@/hooks/use-logout"
import { useAuthStore } from "@/lib/store/auth-store"
import { useWaterAlerts } from "@/hooks/use-water-alerts"
import { WATER_ALERT_SECTIONS, waterAlertBellCount, type WaterAlert } from "@/lib/api/water-alerts"

const TONE: Record<WaterAlert["severity"], { box: string; icon: typeof Bell; label: string }> = {
  Critical: { box: "border-rose-300 bg-rose-50 text-rose-900", icon: AlertTriangle, label: "Critical" },
  Warning:  { box: "border-amber-300 bg-amber-50 text-amber-900", icon: AlertTriangle, label: "Needs attention" },
  Info:     { box: "border-sky-200 bg-sky-50 text-sky-900", icon: Info, label: "For information" },
}

export default function WaterAlertsPage() {
  const router = useRouter()
  const logout = useLogout()
  const gh = useFmt()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const { rows, error, refresh } = useWaterAlerts()

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") router.replace("/dashboard")
  }, [activeFarmType, router])

  const open = rows ? waterAlertBellCount(rows) : 0
  const bySection = (s: string) => (rows ?? []).filter((r) => r.section === s)

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6 space-y-4">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2"><Bell className="h-6 w-6 text-sky-600" /> Alerts</h1>
              <p className="text-sm text-slate-500">Everything that needs attention, worked out fresh each time. Fix the cause and the alert goes away.</p>
            </div>
            <Button variant="outline" onClick={() => void refresh()}><RefreshCw className="h-4 w-4 mr-1" /> Refresh</Button>
          </div>

          {error && <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</div>}

          {rows == null && !error ? (
            <div className="flex items-center gap-2 p-8 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Checking…</div>
          ) : rows && (
            <>
              <div className={cn("flex items-center gap-2 rounded-lg border p-4 text-base font-medium",
                open === 0 ? "border-emerald-300 bg-emerald-50 text-emerald-900" : "border-amber-300 bg-amber-50 text-amber-900")}>
                {open === 0
                  ? <><CheckCircle2 className="h-5 w-5" /> All clear{rows.length > 0 ? " — only notes for information below." : "."}</>
                  : <><AlertTriangle className="h-5 w-5" /> {open} {open === 1 ? "thing needs" : "things need"} attention</>}
              </div>

              <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-2">
                {WATER_ALERT_SECTIONS.map((s) => {
                  const list = bySection(s)
                  const n = waterAlertBellCount(list)
                  return (
                    <a key={s} href={`#${s.replace(/\s+/g, "-").toLowerCase()}`}
                       className={cn("rounded-lg border p-3", n > 0 ? "border-amber-300 bg-amber-50" : "border-emerald-200 bg-white")}>
                      <div className="text-xs text-slate-500">{s}</div>
                      <div className={cn("text-lg font-semibold", n > 0 ? "text-amber-800" : "text-emerald-700")}>
                        {n > 0 ? n : "OK"}
                      </div>
                    </a>
                  )
                })}
              </div>

              {WATER_ALERT_SECTIONS.map((s) => {
                const list = bySection(s)
                if (list.length === 0) return null
                return (
                  <section key={s} id={s.replace(/\s+/g, "-").toLowerCase()} className="space-y-2">
                    <h2 className="text-sm font-semibold uppercase tracking-wide text-slate-500">{s}</h2>
                    {list.map((a) => {
                      const tone = TONE[a.severity] ?? TONE.Info
                      const Icon = tone.icon
                      return (
                        <div key={a.code} className={cn("flex flex-wrap items-start justify-between gap-3 rounded-lg border p-3", tone.box)}>
                          <div className="flex min-w-0 gap-2">
                            <Icon className="mt-0.5 h-4 w-4 shrink-0" />
                            <div className="min-w-0">
                              <div className="font-medium">{a.title}{a.amount ? <span className="ml-2 tabular-nums">· {gh(Number(a.amount))}</span> : null}</div>
                              {a.detail && <div className="text-sm opacity-80 break-words">{a.detail}</div>}
                              <div className="text-[11px] uppercase tracking-wide opacity-60">{tone.label}</div>
                            </div>
                          </div>
                          <Button asChild size="sm" variant="outline" className="bg-white">
                            <Link href={a.href}>Open <ArrowRight className="ml-1 h-3.5 w-3.5" /></Link>
                          </Button>
                        </div>
                      )
                    })}
                  </section>
                )
              })}
            </>
          )}
        </main>
      </div>
    </div>
  )
}
