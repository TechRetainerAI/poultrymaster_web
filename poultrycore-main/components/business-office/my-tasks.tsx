"use client"

// Business Office -> My Tasks.
//
// The flock lifecycle reminders (migration 347) of every POULTRY company the
// user can open, in one list. It follows the company-card pattern on the same
// page: one request per company, each landing on its own, so a slow or
// refused company never holds up the rest.
//
// WHO SEES WHAT is decided by the server, per company: each request carries
// that company's farmId, and the IAM filter answers poultry.lifecycle.view for
// THAT company. The browser cannot -- its can() only knows the active company,
// and the Business Office has none. A company that refuses (403) is simply not
// listed; one that fails for another reason is named, so a blank list never
// hides a fault.
//
// Opening a task switches into its company first (the caller's onOpen), then
// lands on the Flock Lifecycle page.

import { useEffect, useMemo, useState } from "react"
import { ArrowRight, CheckCircle2, ListTodo, Loader2 } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import type { Company } from "@/lib/api/companies"
import { LifecycleHttpError, listLifecycleTasks, type LifecycleTask } from "@/lib/api/poultry-lifecycle"
import { STATUS_TONE, dueLabel, sortTasks, taskSentence } from "@/lib/poultry/lifecycle"

interface CompanyTask extends LifecycleTask { companyFarmId: string; companyName: string }

type LoadState = "loading" | "ok" | "denied" | "failed"

const SHOW = 8

export function MyTasks({ companies, onOpen }: {
  companies: Company[]
  /** Switch into the company, then go to the path. */
  onOpen: (company: Company, path: string) => void | Promise<void>
}) {
  const poultry = useMemo(() => companies.filter((c) => c.type === "Poultry"), [companies])
  const [tasks, setTasks] = useState<CompanyTask[]>([])
  const [state, setState] = useState<Record<string, LoadState>>({})
  const [showAll, setShowAll] = useState(false)
  const [opening, setOpening] = useState<string | null>(null)

  useEffect(() => {
    if (poultry.length === 0) return
    let cancelled = false
    setTasks([])
    setState(Object.fromEntries(poultry.map((c) => [c.farmId, "loading" as LoadState])))
    for (const c of poultry) {
      listLifecycleTasks({ view: "Open", farmId: c.farmId })
        .then((rows) => {
          if (cancelled) return
          setTasks((prev) => [...prev, ...rows.map((r) => ({ ...r, companyFarmId: c.farmId, companyName: c.name }))])
          setState((s) => ({ ...s, [c.farmId]: "ok" }))
        })
        .catch((e) => {
          if (cancelled) return
          const denied = e instanceof LifecycleHttpError && (e.status === 403 || e.status === 401)
          setState((s) => ({ ...s, [c.farmId]: denied ? "denied" : "failed" }))
        })
    }
    return () => { cancelled = true }
  }, [poultry])

  if (poultry.length === 0) return null

  const sorted = sortTasks(tasks)
  const shown = showAll ? sorted : sorted.slice(0, SHOW)
  const loading = Object.values(state).some((s) => s === "loading")
  const failed = poultry.filter((c) => state[c.farmId] === "failed")
  const allowed = poultry.filter((c) => state[c.farmId] !== "denied")
  const overdue = tasks.filter((t) => t.status === "Overdue").length
  const due = tasks.filter((t) => t.status === "Due").length

  // Nobody here may see lifecycle tasks in any company: say nothing at all.
  if (!loading && allowed.length === 0) return null

  return (
    <section id="tasks" className="space-y-2">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 className="text-lg font-semibold text-slate-900 flex items-center gap-2">
          <ListTodo className="h-5 w-5 text-indigo-600" /> My Tasks
          {loading && <Loader2 className="h-4 w-4 animate-spin text-slate-400" />}
        </h2>
        {tasks.length > 0 && (
          <div className="flex gap-1.5 text-xs">
            {overdue > 0 && <Badge variant="outline" className={STATUS_TONE.Overdue}>{overdue} overdue</Badge>}
            {due > 0 && <Badge variant="outline" className={STATUS_TONE.Due}>{due} due</Badge>}
            <Badge variant="outline">{tasks.length} open</Badge>
          </div>
        )}
      </div>

      <Card>
        <CardContent className="p-0 divide-y">
          {!loading && tasks.length === 0 && (
            <div className="p-6 text-center text-slate-500 flex items-center justify-center gap-2">
              <CheckCircle2 className="h-4 w-4 text-emerald-600" /> No flock lifecycle reminders need attention.
            </div>
          )}
          {shown.map((t) => {
            const key = `${t.companyFarmId}-${t.flockId}-${t.milestoneId}`
            const company = poultry.find((c) => c.farmId === t.companyFarmId)!
            return (
              <div key={key} className="p-3 flex flex-wrap items-center justify-between gap-2">
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-1.5">
                    <Badge variant="outline" className={STATUS_TONE[t.status]}>{t.status}</Badge>
                    <span className="font-medium text-slate-900">{t.title}</span>
                    {t.isEstimated && <Badge variant="outline" className="border-amber-300 text-amber-800 bg-amber-50">Estimated</Badge>}
                  </div>
                  <div className="text-sm text-slate-600">{taskSentence(t)} · {dueLabel(t)}</div>
                  <div className="text-xs text-slate-500">{t.companyName}</div>
                </div>
                <Button size="sm" variant="outline" disabled={opening === key}
                  onClick={async () => {
                    setOpening(key)
                    try { await onOpen(company, `/poultry-lifecycle?flockId=${t.flockId}`) } finally { setOpening(null) }
                  }}>
                  {opening === key ? <Loader2 className="h-4 w-4 animate-spin" /> : <>Open <ArrowRight className="h-4 w-4 ml-1" /></>}
                </Button>
              </div>
            )
          })}
          {sorted.length > SHOW && (
            <div className="p-2 text-center">
              <Button size="sm" variant="ghost" onClick={() => setShowAll((v) => !v)}>
                {showAll ? "Show fewer" : `Show all ${sorted.length}`}
              </Button>
            </div>
          )}
        </CardContent>
      </Card>
      {failed.length > 0 && (
        <p className="text-xs text-amber-700">Couldn&apos;t load tasks for {failed.map((c) => c.name).join(", ")}.</p>
      )}
    </section>
  )
}
