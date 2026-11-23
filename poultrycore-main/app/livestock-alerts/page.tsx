"use client"

// Farm Alerts -- the poultry Flock Alerts page for livestock. Worked out fresh
// each time from the records; nothing to dismiss -- an alert goes away when
// what it is about is dealt with.

import { useCallback, useEffect, useState } from "react"
import { Bell } from "lucide-react"
import { listAlerts, type LivestockAlert } from "@/lib/api/livestock"
import { AlertsList } from "@/components/livestock/alerts-list"
import { EmptyState, LivestockPage, LoadError, Loading } from "@/components/livestock/livestock-page"

export default function LivestockAlertsPage() {
  const [alerts, setAlerts] = useState<LivestockAlert[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const load = useCallback(async () => {
    setError(null)
    try { setAlerts(await listAlerts()) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [])
  useEffect(() => { load() }, [load])

  return (
    <LivestockPage title="Farm alerts" description="What needs attention today. Each one clears once it is dealt with." icon={Bell}>
      {error ? <LoadError message={error} onRetry={load} /> : !alerts ? <Loading /> : alerts.length === 0 ? (
        <EmptyState title="Nothing needs attention">Deaths are normal, records are up to date, and nothing is running out.</EmptyState>
      ) : <AlertsList alerts={alerts} />}
    </LivestockPage>
  )
}
