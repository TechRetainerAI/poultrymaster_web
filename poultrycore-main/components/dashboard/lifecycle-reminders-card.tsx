"use client"

// Lifecycle reminders on Farm Alerts (347, vaccinations 387): the flock
// milestones due now or overdue -- the national vaccinations and the farm's own
// reminders. Read-only: completing or skipping one happens on Flock Lifecycle.

import { useEffect, useState } from "react"
import Link from "next/link"
import { CheckCircle2, Loader2, Syringe } from "lucide-react"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { cn } from "@/lib/utils"
import { useAuthStore } from "@/lib/store/auth-store"
import { listLifecycleTasks, type LifecycleTask } from "@/lib/api/poultry-lifecycle"
import { STATUS_TONE, dueLabel, sortTasks, taskKey, taskSentence } from "@/lib/poultry/lifecycle"

const SHOW = 5

export function LifecycleRemindersCard() {
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const [tasks, setTasks] = useState<LifecycleTask[] | null>(null)
  const [failed, setFailed] = useState(false)

  useEffect(() => {
    if (!activeFarmId) return
    let cancelled = false
    setTasks(null)
    setFailed(false)
    listLifecycleTasks({ view: "Open" })
      .then((r) => { if (!cancelled) setTasks(sortTasks(r.filter((t) => t.status === "Due" || t.status === "Overdue"))) })
      .catch(() => { if (!cancelled) setFailed(true) })
    return () => { cancelled = true }
  }, [activeFarmId])

  // Advisory: quietly absent on failure (no poultry.lifecycle.view, or 347 not applied).
  if (!activeFarmId || failed) return null
  if (tasks == null) {
    return (
      <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
        <CardContent className="flex items-center gap-2 p-4 text-sm text-slate-500">
          <Loader2 className="h-4 w-4 animate-spin" /> Checking vaccinations and reminders…
        </CardContent>
      </Card>
    )
  }

  const overdue = tasks.filter((t) => t.status === "Overdue").length

  return (
    <Card className={cn("rounded-xl border border-l-4 border-slate-200 bg-white shadow-sm",
      overdue ? "border-l-rose-500" : tasks.length ? "border-l-amber-500" : "border-l-emerald-500")}>
      <CardContent className="space-y-3 p-4">
        <div className="flex items-start gap-3">
          <div className={cn("flex h-10 w-10 shrink-0 items-center justify-center rounded-lg",
            overdue ? "bg-rose-500" : tasks.length ? "bg-amber-500" : "bg-emerald-500")}>
            <Syringe className="h-5 w-5 text-white" />
          </div>
          <div>
            <p className="text-xs font-medium uppercase tracking-wider text-slate-500">Vaccinations &amp; reminders</p>
            {tasks.length === 0 ? (
              <p className="mt-1 flex items-center gap-1.5 text-sm text-emerald-700">
                <CheckCircle2 className="h-4 w-4" /> Nothing due. Flocks without a plan get no reminders.
              </p>
            ) : (
              <p className="mt-1 text-sm text-slate-700">
                <b>{tasks.length}</b> due{overdue > 0 && <span className="text-rose-700"> · {overdue} overdue</span>}
              </p>
            )}
          </div>
        </div>

        {tasks.length > 0 && (
          <ul className="divide-y divide-slate-100 rounded-lg border border-slate-100">
            {tasks.slice(0, SHOW).map((t) => (
              <li key={taskKey(t)} className="flex flex-wrap items-center justify-between gap-2 px-3 py-2">
                <div className="min-w-0">
                  <div className="truncate text-sm font-medium text-slate-900">{t.title}</div>
                  <div className="truncate text-xs text-slate-500">{taskSentence(t)} · {dueLabel(t)}</div>
                </div>
                <Badge variant="outline" className={STATUS_TONE[t.status]}>{t.status}</Badge>
              </li>
            ))}
          </ul>
        )}

        <Button asChild size="sm" variant="outline">
          <Link href="/poultry-lifecycle">
            {tasks.length > SHOW ? `See all ${tasks.length}` : "Open Flock Lifecycle"}
          </Link>
        </Button>
      </CardContent>
    </Card>
  )
}
