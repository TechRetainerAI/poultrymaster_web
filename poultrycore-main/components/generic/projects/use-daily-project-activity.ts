"use client"

// 501: Daily Closing with a Project / Contract filter -- for each day, the
// project's part of that day's sales, customer collections, expenses and net
// cash. Built from Financial Activity events and their project shares (the same
// split the Financial Activity page and the project P&L use). Read only: a
// closing's own stored totals, approval and submit are untouched.

import { useEffect, useState } from "react"
import { useProjectsEnabled } from "@/hooks/use-generic-projects"
import { getActivityShares } from "@/lib/api/generic-projects"
import { getGenericFinancialActivity } from "@/lib/api/generic-financial-activity"
import { projectPart, round, type ProjectFilterValue } from "@/lib/generic/project-math"

export interface DayProjectActivity { sales: number; collections: number; expenses: number; netCash: number }

const COLLECTION_TYPES = new Set(["Receipt", "ReceiptReversal"])

export function useDailyProjectActivity(fromDate: string | null, toDate: string | null, filter: ProjectFilterValue) {
  const { enabled } = useProjectsEnabled()
  const [byDay, setByDay] = useState<Map<string, DayProjectActivity> | null>(null)
  const [loading, setLoading] = useState(false)
  const active = enabled && filter.kind !== "all" && !!fromDate && !!toDate

  useEffect(() => {
    if (!active) { setByDay(null); return }
    let cancelled = false
    setLoading(true)
    Promise.all([
      getGenericFinancialActivity({ fromDate: fromDate!, toDate: toDate! }),
      getActivityShares(fromDate!, toDate!),
    ]).then(([fa, shares]) => {
      if (cancelled) return
      const sh = new Map(shares.map((s) => [s.eventKey, s.projects]))
      const m = new Map<string, DayProjectActivity>()
      for (const r of fa.rows ?? []) {
        const day = (r.businessDate ?? r.occurredAt ?? "").slice(0, 10)
        const ps = sh.get(r.eventKey)
        const part = (n: number) => projectPart(Number(n) || 0, ps, filter)
        const d = m.get(day) ?? { sales: 0, collections: 0, expenses: 0, netCash: 0 }
        d.sales = round(d.sales + part(r.revenue))
        d.expenses = round(d.expenses + part(r.expense))
        d.netCash = round(d.netCash + part(r.moneyIn) - part(r.moneyOut))
        if (COLLECTION_TYPES.has(r.sourceType ?? "")) d.collections = round(d.collections + part(r.moneyIn) - part(r.moneyOut))
        m.set(day, d)
      }
      setByDay(m)
    }).catch(() => { if (!cancelled) setByDay(new Map()) })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
    // filter is compared by value
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [active, fromDate, toDate, JSON.stringify(filter)])

  return { enabled, active, loading, byDay }
}
