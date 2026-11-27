"use client"

// 501: which projects each cash-ledger entry belongs to, for Cash & Accounts and
// Reconciliation. Same rows and shares as the project cash flow. Account
// balances are never split -- only the entries are filtered.

import { useCallback, useEffect, useMemo, useState } from "react"
import { useProjectsEnabled } from "@/hooks/use-generic-projects"
import { getCashShares } from "@/lib/api/generic-projects"
import { projectPart, type ProjectFilterValue } from "@/lib/generic/project-math"

type Share = { projectId: number; share: number; label: string }

/** skip = read nothing (e.g. a dialog that is closed). */
export function useCashShares(accountId?: number, reloadKey?: unknown, skip = false) {
  const { enabled } = useProjectsEnabled()
  const [map, setMap] = useState<Map<number, Share[]>>(new Map())

  useEffect(() => {
    if (!enabled || skip) { setMap(new Map()); return }
    let cancelled = false
    getCashShares(accountId ? { accountId } : {})
      .then((rows) => { if (!cancelled) setMap(new Map(rows.map((r) => [r.cashTransactionId, r.projects]))) })
      .catch(() => { if (!cancelled) setMap(new Map()) })
    return () => { cancelled = true }
  }, [enabled, accountId, reloadKey, skip])

  /** Does an entry belong (partly) to the picked projects? "general" = the part no project has. */
  const matches = useCallback((id: number, f: ProjectFilterValue) => {
    if (f.kind === "all") return true
    const ps = map.get(id) ?? []
    if (f.kind === "general") return ps.reduce((t, p) => t + p.share, 0) < 0.999999
    return ps.some((p) => f.ids.includes(p.projectId))
  }, [map])

  /** The entry's amount that belongs to the picked projects (split the way the engine splits). */
  const part = useCallback((id: number, amount: number, f: ProjectFilterValue) =>
    projectPart(amount, map.get(id), f), [map])

  const labelsOf = useCallback((id: number) => (map.get(id) ?? []).map((p) => p.label), [map])

  return useMemo(() => ({ enabled, matches, part, labelsOf }), [enabled, matches, part, labelsOf])
}
