"use client"

// Livestock dashboard -- the landing page for a Livestock company (see
// dashboardHomeForType). Animals on the farm by kind, with what needs doing.
// Cards for production, feed, health and money are added as those modules land.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { ArrowRight, PawPrint } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { useAuthStore } from "@/lib/store/auth-store"
import { dashboardHomeForType } from "@/lib/api/companies"
import { getOverview, listAlerts, type LivestockAlert, type LivestockOverview } from "@/lib/api/livestock"
import { AlertsList } from "@/components/livestock/alerts-list"
import { RecentActivity } from "@/components/livestock/recent-activity"
import { useLivestockFeatures } from "@/hooks/use-livestock-species"
import {
  AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, StatCard, fmtNum,
} from "@/components/livestock/livestock-page"

export default function LivestockDashboardPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmName = useAuthStore((s) => s.activeFarmName)
  const [data, setData] = useState<LivestockOverview | null>(null)
  const features = useLivestockFeatures()
  const [alerts, setAlerts] = useState<LivestockAlert[]>([])
  const [error, setError] = useState<string | null>(null)

  const isLivestock = activeFarmType === "Livestock"
  // Wait for the persisted store; then send any other company type home.
  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (!isLivestock) router.replace(dashboardHomeForType(activeFarmType))
  }, [activeFarmType, isLivestock, router])

  const load = useCallback(async () => {
    setError(null)
    try {
      const [o, a] = await Promise.all([getOverview(), listAlerts().catch(() => [])])
      setData(o); setAlerts(a)
    } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [])
  useEffect(() => { if (isLivestock) load() }, [isLivestock, load])

  return (
    <LivestockPage
      title={`${activeFarmName ?? "Livestock farm"} dashboard`}
      description="Your animals at a glance."
      icon={PawPrint}
    >
      {error ? <LoadError message={error} onRetry={load} /> : !data ? <Loading /> : data.speciesKept === 0 ? (
        <EmptyState title="Welcome to your livestock farm"
          action={<Button asChild className={AMBER_BUTTON}><Link href="/livestock-animals-kept">Choose your animals</Link></Button>}>
          Start by ticking the animals you keep. Then add your pens and the animals already on the farm.
        </EmptyState>
      ) : (
        <>
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
            <StatCard label="Animals on the farm" value={fmtNum(data.head)} tone="amber" hint={`${fmtNum(data.tagged)} tagged`} />
            <StatCard label="Active groups" value={fmtNum(data.activeGroups)} hint={`${fmtNum(data.pens)} pen(s) in use`} />
            <StatCard label="Deaths, last 30 days" value={fmtNum(data.deathsLast30)} tone={data.deathsLast30 > 0 ? "rose" : "stone"} />
            <StatCard label="Kinds of animal" value={fmtNum(data.speciesKept)} />
          </div>

          {alerts.length > 0 && (
            <Card>
              <CardHeader className="pb-2 flex-row items-center justify-between space-y-0">
                <CardTitle className="text-base text-stone-900">Needs attention</CardTitle>
                <Link className="text-sm text-amber-800 hover:underline" href="/livestock-alerts">All {alerts.length} →</Link>
              </CardHeader>
              <CardContent><AlertsList alerts={alerts} limit={5} /></CardContent>
            </Card>
          )}

          {data.unallocatedBatches > 0 && (
            <Link href="/livestock-batches" className="flex items-center justify-between rounded-md border border-amber-300 bg-amber-50 px-4 py-3 text-sm text-amber-900 hover:bg-amber-100">
              <span>{data.unallocatedBatches} intake batch(es) still have animals that are not in a group.</span>
              <span className="inline-flex items-center gap-1 font-medium">Divide them <ArrowRight className="h-4 w-4" /></span>
            </Link>
          )}

          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            {data.species.map((s) => (
              <Card key={s.speciesCode}>
                <CardHeader className="pb-1"><CardTitle className="text-base text-stone-900">{s.name}</CardTitle></CardHeader>
                <CardContent className="text-sm text-stone-600 space-y-1">
                  <div className="text-2xl font-semibold text-stone-900">{fmtNum(s.head)}</div>
                  <div>{s.groups} active {s.groupTerm.toLowerCase()}{s.groups === 1 ? "" : "s"} · {fmtNum(s.tagged)} tagged</div>
                </CardContent>
              </Card>
            ))}
          </div>

          <RecentActivity showBreeding={features.breeding} />
        </>
      )}
    </LivestockPage>
  )
}
