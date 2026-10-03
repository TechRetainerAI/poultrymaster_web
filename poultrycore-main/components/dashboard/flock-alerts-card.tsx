"use client"

// Flock alerts on the poultry dashboard (migration 338): the flocks whose own
// figures today are out of line with their recent history — one row per flock,
// however many signals fired. Loading the card runs the server's idempotent
// scan, so a new alert appears once and is never repeated.

import { useEffect, useState } from "react"
import Link from "next/link"
import { Activity, CheckCircle2, Loader2 } from "lucide-react"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { cn } from "@/lib/utils"
import { useAuthStore } from "@/lib/store/auth-store"
import { getFlockAlerts } from "@/lib/api/flock-alerts"
import {
  alertHeadline,
  dayOf,
  flockLabel,
  severityStyle,
  sortAlerts,
  statusStyle,
  summarizeAlerts,
  type FlockAlert,
} from "@/lib/production/flock-anomalies"
import { formatLongDate } from "@/lib/closing/daily-closing"

const SHOW = 4

export function FlockAlertsCard() {
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const [alerts, setAlerts] = useState<FlockAlert[] | null>(null)
  const [failed, setFailed] = useState(false)

  useEffect(() => {
    if (!activeFarmId) return
    let cancelled = false
    setAlerts(null)
    setFailed(false)
    getFlockAlerts({ status: "active" })
      .then((r) => { if (!cancelled) setAlerts(sortAlerts(r)) })
      .catch(() => { if (!cancelled) setFailed(true) })
    return () => { cancelled = true }
  }, [activeFarmId])

  // Advisory: quietly absent on failure (e.g. no poultry.health view right).
  if (!activeFarmId || failed) return null
  if (alerts == null) {
    return (
      <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
        <CardContent className="flex items-center gap-2 p-4 text-sm text-slate-500">
          <Loader2 className="h-4 w-4 animate-spin" /> Checking flocks for unusual figures…
        </CardContent>
      </Card>
    )
  }

  const s = summarizeAlerts(alerts)
  const worst = severityStyle(s.worst)

  return (
    <Card className={cn("rounded-xl border border-l-4 border-slate-200 bg-white shadow-sm",
      s.active ? worst.border : "border-l-emerald-500")}>
      <CardContent className="space-y-3 p-4">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div className="flex items-start gap-3">
            <div className={cn("flex h-10 w-10 shrink-0 items-center justify-center rounded-lg",
              s.critical ? "bg-rose-500" : s.active ? "bg-amber-500" : "bg-emerald-500")}>
              <Activity className="h-5 w-5 text-white" />
            </div>
            <div>
              <p className="text-xs font-medium uppercase tracking-wider text-slate-500">Flock Alerts</p>
              {s.active === 0 ? (
                <p className="mt-1 flex items-center gap-1.5 text-sm text-emerald-700">
                  <CheckCircle2 className="h-4 w-4" /> No flock is out of line with its recent figures.
                </p>
              ) : (
                <p className="mt-1 text-sm text-slate-700">
                  <b>{s.active}</b> flock alert{s.active === 1 ? "" : "s"}
                  {s.critical > 0 && <span className="text-rose-700"> · {s.critical} critical</span>}
                  {s.acknowledged > 0 && <span className="text-slate-500"> · {s.acknowledged} acknowledged</span>}
                </p>
              )}
            </div>
          </div>
          <Button asChild variant="outline" size="sm">
            <Link href="/poultry-flock-alerts">View all</Link>
          </Button>
        </div>

        {s.active > 0 && (
          <ul className="divide-y divide-slate-100">
            {alerts.slice(0, SHOW).map((a) => {
              const sev = severityStyle(a.severity)
              const lead = a.signals.find((x) => x.isActive) ?? a.signals[0]
              return (
                <li key={a.alertId} className="py-2">
                  <Link href={`/poultry-flock-alerts?alert=${a.alertId}`} className="block min-w-0 hover:opacity-80">
                    <p className="text-sm">
                      <span className={cn("mr-2 rounded-full border px-2 py-0.5 text-[11px] font-medium uppercase", sev.badge)}>{sev.label}</span>
                      <span className="font-medium text-slate-900">{flockLabel(a)}</span>
                      <span className="text-slate-600"> — {alertHeadline(a)}</span>
                    </p>
                    <p className="mt-0.5 text-xs text-slate-500">
                      {formatLongDate(dayOf(a.businessDate))}
                      {a.status !== "Open" && ` · ${statusStyle(a.status).label}`}
                      {a.consecutiveDays > 1 && ` · ${a.consecutiveDays} days in a row`}
                      {lead?.explanation?.[0] && ` · ${lead.explanation[0]}`}
                    </p>
                  </Link>
                </li>
              )
            })}
            {alerts.length > SHOW && (
              <li className="pt-2 text-xs text-slate-500">
                and {alerts.length - SHOW} more — <Link className="text-sky-700 underline" href="/poultry-flock-alerts">view all</Link>
              </li>
            )}
          </ul>
        )}
      </CardContent>
    </Card>
  )
}
