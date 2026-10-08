"use client"

// Farm Alerts: everything that needs the farmer's attention, on one page.
//   - A status line ("All clear" / "N things need attention") and four tiles --
//     Production, Egg sorting, Flock health, Stock -- each green or amber with
//     its count, jumping to its section.
//   - The sections: Farm Completeness (332, with unsorted eggs from 344),
//     Flock Alerts (338) and Stock Days of Supply (337), each card loading and
//     gating itself exactly as it did on the dashboard.
// The numbers come from the same breakdown as the bell in the header, so the
// badge and this page always agree.

import { useEffect, useState, type ReactNode } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { Activity, ArrowRight, Bell, CheckCircle2, ClipboardCheck, Egg, Loader2, Package, RefreshCw } from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { FarmCompletenessCard } from "@/components/dashboard/farm-completeness-card"
import { FlockAlertsCard } from "@/components/dashboard/flock-alerts-card"
import { StockSupplyCard } from "@/components/dashboard/stock-supply-card"
import { cn } from "@/lib/utils"
import { useLogout } from "@/hooks/use-logout"
import { useCompanyDateTime } from "@/hooks/use-company-datetime"
import { useFarmAlertBreakdown, type FarmAlertBreakdown } from "@/hooks/use-farm-alert-count"
import { useAuthStore } from "@/lib/store/auth-store"

type Tone = "ok" | "warn" | "off"

interface Tile {
  id: string
  title: string
  icon: typeof Bell
  value: string
  detail: string
  tone: Tone
}

const fmt = (n: number) => n.toLocaleString()

function tilesFor(d: FarmAlertBreakdown | null): Tile[] {
  const productionOpen = (d?.productionToday ?? 0) + (d?.productionEarlier ?? 0)
  const production: Tile = d?.productionToday == null
    ? { id: "production", title: "Production", icon: ClipboardCheck, value: "—", detail: "Not available", tone: "off" }
    : {
        id: "production", title: "Production", icon: ClipboardCheck,
        value: productionOpen === 0 ? "Up to date" : `${fmt(productionOpen)} missing`,
        detail: [
          d.productionExpected ? `Today ${fmt(d.productionRecorded ?? 0)} / ${fmt(d.productionExpected)} recorded` : "No flocks due today",
          d.productionEarlier ? `${fmt(d.productionEarlier)} earlier` : null,
        ].filter(Boolean).join(" · "),
        tone: productionOpen === 0 ? "ok" : "warn",
      }
  const sorting: Tile = d?.unsortedDays == null
    ? { id: "production", title: "Egg sorting", icon: Egg, value: "Off", detail: "Sorting is not switched on", tone: "off" }
    : {
        id: "production", title: "Egg sorting", icon: Egg,
        value: d.unsortedDays === 0 ? "Up to date" : `${fmt(d.unsortedEggs ?? 0)} eggs`,
        detail: d.unsortedDays === 0 ? "Earlier days are all sorted" : `from ${fmt(d.unsortedDays)} earlier day${d.unsortedDays === 1 ? "" : "s"}, unsorted`,
        tone: d.unsortedDays === 0 ? "ok" : "warn",
      }
  const flocks: Tile = d?.flockAlerts == null
    ? { id: "flocks", title: "Flock health", icon: Activity, value: "—", detail: "Not available", tone: "off" }
    : {
        id: "flocks", title: "Flock health", icon: Activity,
        value: d.flockAlerts === 0 ? "All normal" : `${fmt(d.flockAlerts)} alert${d.flockAlerts === 1 ? "" : "s"}`,
        detail: d.flockAlerts === 0 ? "No flock out of line with its figures" : "Flocks out of line with their recent figures",
        tone: d.flockAlerts === 0 ? "ok" : "warn",
      }
  const stock: Tile = d?.stockActionable == null
    ? { id: "stock", title: "Stock", icon: Package, value: "—", detail: "Not available", tone: "off" }
    : {
        id: "stock", title: "Stock", icon: Package,
        value: d.stockActionable === 0 ? "Well stocked" : `${fmt(d.stockActionable)} running low`,
        detail: d.stockActionable === 0 ? "Nothing runs out soon" : "Items to reorder or top up",
        tone: d.stockActionable === 0 ? "ok" : "warn",
      }
  return [production, sorting, flocks, stock]
}

const TONE: Record<Tone, { card: string; icon: string; value: string }> = {
  ok:   { card: "border-emerald-200 bg-emerald-50/60 hover:bg-emerald-50", icon: "bg-emerald-500 text-white", value: "text-emerald-800" },
  warn: { card: "border-amber-300 bg-amber-50 hover:bg-amber-100/70", icon: "bg-amber-500 text-white", value: "text-amber-900" },
  off:  { card: "border-slate-200 bg-white hover:bg-slate-50", icon: "bg-slate-200 text-slate-600", value: "text-slate-600" },
}

function Section({ id, title, description, href, linkLabel, children }: {
  id: string; title: string; description: string; href: string; linkLabel: string; children: ReactNode
}) {
  return (
    <section id={id} className="scroll-mt-24 space-y-2">
      <div className="flex flex-wrap items-end justify-between gap-2">
        <div>
          <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-500">{title}</h2>
          <p className="text-xs text-slate-500">{description}</p>
        </div>
        <Link href={href} className="inline-flex items-center gap-1 text-xs font-medium text-amber-700 hover:underline">
          {linkLabel} <ArrowRight className="h-3.5 w-3.5" />
        </Link>
      </div>
      {children}
    </section>
  )
}

export default function FarmAlertsPage() {
  const router = useRouter()
  const logout = useLogout()
  const { fmtInstant } = useCompanyDateTime()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const { data, refresh } = useFarmAlertBreakdown()
  const [refreshing, setRefreshing] = useState(false)
  // Bumped by Refresh: remounts the cards so they re-read too.
  const [cardsKey, setCardsKey] = useState(0)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") router.replace("/dashboard")
  }, [activeFarmType, router])

  const doRefresh = async () => {
    setRefreshing(true)
    setCardsKey((k) => k + 1)
    await refresh()
    setRefreshing(false)
  }

  const tiles = tilesFor(data)
  const total = data?.total ?? 0
  const jump = (id: string) => document.getElementById(id)?.scrollIntoView({ behavior: "smooth", block: "start" })

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex min-w-0 flex-1 flex-col">
        <DashboardHeader />
        <main className="min-w-0 flex-1 overflow-x-hidden p-4 pb-16 sm:p-6 lg:pb-6">
          <div className="mx-auto max-w-6xl space-y-6">
            {/* ---------------------------------------------------- status */}
            <div className={cn(
              "overflow-hidden rounded-2xl border shadow-sm",
              !data ? "border-slate-200 bg-white" : total === 0 ? "border-emerald-200 bg-white" : "border-amber-200 bg-white",
            )}>
              <div className={cn(
                "flex flex-wrap items-center justify-between gap-4 px-5 py-4",
                !data ? "bg-slate-50" : total === 0 ? "bg-gradient-to-r from-emerald-50 to-white" : "bg-gradient-to-r from-amber-50 to-white",
              )}>
                <div className="flex items-center gap-4">
                  <div className={cn(
                    "relative flex h-12 w-12 shrink-0 items-center justify-center rounded-xl",
                    !data ? "bg-slate-200" : total === 0 ? "bg-emerald-500" : "bg-amber-500",
                  )}>
                    {!data ? <Loader2 className="h-6 w-6 animate-spin text-slate-500" />
                      : total === 0 ? <CheckCircle2 className="h-6 w-6 text-white" />
                      : <Bell className="h-6 w-6 text-white" />}
                    {data && total > 0 && (
                      <span className="absolute -right-1.5 -top-1.5 flex h-5 min-w-[20px] items-center justify-center rounded-full bg-red-600 px-1 text-[11px] font-semibold text-white">
                        {total > 99 ? "99+" : total}
                      </span>
                    )}
                  </div>
                  <div>
                    <h1 className="text-2xl font-bold text-slate-900">Farm Alerts</h1>
                    <p className="text-sm text-slate-600">
                      {!data ? "Checking the farm…"
                        : total === 0 ? "All clear — nothing needs your attention right now."
                        : `${fmt(total)} thing${total === 1 ? "" : "s"} need${total === 1 ? "s" : ""} your attention.`}
                    </p>
                  </div>
                </div>
                <div className="flex items-center gap-3">
                  {data && <span className="text-xs text-slate-500">Updated {fmtInstant(new Date(data.loadedAt).toISOString())}</span>}
                  <Button variant="outline" size="sm" onClick={() => void doRefresh()} disabled={refreshing}>
                    <RefreshCw className={cn("mr-1.5 h-4 w-4", refreshing && "animate-spin")} /> Refresh
                  </Button>
                </div>
              </div>

              {/* ------------------------------------------------- tiles */}
              <div className="grid grid-cols-1 gap-3 border-t border-slate-100 p-4 sm:grid-cols-2 lg:grid-cols-4">
                {tiles.map((t) => {
                  const tone = TONE[t.tone]
                  const Icon = t.icon
                  return (
                    <button key={t.title} type="button" onClick={() => jump(t.id)}
                      className={cn("flex items-start gap-3 rounded-xl border p-3 text-left transition-colors", tone.card)}>
                      <span className={cn("flex h-9 w-9 shrink-0 items-center justify-center rounded-lg", tone.icon)}>
                        <Icon className="h-5 w-5" />
                      </span>
                      <span className="min-w-0">
                        <span className="block text-[11px] font-medium uppercase tracking-wider text-slate-500">{t.title}</span>
                        <span className={cn("block text-lg font-bold leading-tight", tone.value)}>{data ? t.value : "…"}</span>
                        <span className="block truncate text-xs text-slate-600">{data ? t.detail : " "}</span>
                      </span>
                    </button>
                  )
                })}
              </div>
            </div>

            {/* ------------------------------------------------- sections */}
            <Section id="production" title="Production & egg sorting"
              description="Production still to record for today or earlier days, and eggs from earlier days still to sort."
              href="/poultry-farm-completeness" linkLabel="Farm Completeness">
              <FarmCompletenessCard key={`fc-${cardsKey}`} compact />
            </Section>

            <div className="grid grid-cols-1 gap-6 xl:grid-cols-2">
              <Section id="flocks" title="Flock health"
                description="Flocks whose mortality, eggs or feed are out of line with their own recent figures."
                href="/poultry-flock-alerts" linkLabel="All flock alerts">
                <FlockAlertsCard key={`fa-${cardsKey}`} />
              </Section>

              <Section id="stock" title="Stock"
                description="Feed, medication and supplies that will run out soonest at their actual usage."
                href="/poultry-restock-forecast" linkLabel="Inventory Restock Forecast">
                <StockSupplyCard key={`ss-${cardsKey}`} />
              </Section>
            </div>
          </div>
        </main>
      </div>
    </div>
  )
}
