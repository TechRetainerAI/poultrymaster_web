"use client"

// Which project(s) each document on a list page belongs to, so a list can show
// a Project column and filter by the Project / Contract filter. One request per
// list (all documents of that type), only when the module is on.

import { useCallback, useEffect, useMemo, useState } from "react"
import { getProjectLabels } from "@/lib/api/generic-projects"
import { useProjectsEnabled } from "@/hooks/use-generic-projects"
import type { ProjectFilterValue } from "@/lib/generic/project-math"

export type LabelSourceType =
  | "Sale" | "Purchase" | "Expense" | "OwnerEntry" | "CustomerPayment" | "SupplierPayment"
  // 493: tagged from Link older transactions; the payroll, loans and assets pages filter by them.
  | "PayrollRun" | "Loan" | "CapitalAsset"
  // 501: more record types, and deferred-cost lots (keyed by stock movement id).
  | "InternalUsage" | "EmployeeLoan" | "CustomerCredit" | "RecurringTemplate" | "DeferredLot"

export function useProjectLabels(sourceType: LabelSourceType, reloadKey?: unknown) {
  const { enabled } = useProjectsEnabled()
  // 502: share = how much of the record the project has (0..1); null for sales / purchases split per line.
  const [map, setMap] = useState<Map<number, { projectId: number; label: string; share?: number | null }[]>>(new Map())

  const load = useCallback(async () => {
    if (!enabled) { setMap(new Map()); return }
    try {
      const rows = await getProjectLabels(sourceType)
      setMap(new Map(rows.map((r) => [r.sourceId, r.projects])))
    } catch {
      setMap(new Map())
    }
  }, [enabled, sourceType])

  useEffect(() => { void load() }, [load, reloadKey])

  /** Does a document pass the filter? "general" = belongs to no project at all. */
  const matches = useCallback((id: number, f: ProjectFilterValue) => {
    if (f.kind === "all") return true
    const ps = map.get(id) ?? []
    if (f.kind === "general") return ps.length === 0
    return ps.some((p) => f.ids.includes(p.projectId))
  }, [map])

  const labelOf = useCallback((id: number) => (map.get(id) ?? []).map((p) => p.label.split(" — ")[0]).join(", "), [map])

  /** Full labels ("PRJ-0003 — Name") for the Project / contract column; [] = General. */
  const labelsOf = useCallback((id: number | null | undefined) =>
    id == null ? [] : (map.get(id) ?? []).map((p) => p.label), [map])

  /** Labels with each project's share (502), for showing a split. */
  const partsOf = useCallback((id: number | null | undefined) =>
    id == null ? [] : (map.get(id) ?? []).map((p) => ({ label: p.label, share: p.share ?? null })), [map])

  return useMemo(() => ({ enabled, map, matches, labelOf, labelsOf, partsOf, reload: load }), [enabled, map, matches, labelOf, labelsOf, partsOf, load])
}
