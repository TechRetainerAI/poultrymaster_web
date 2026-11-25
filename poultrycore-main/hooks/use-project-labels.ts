"use client"

// Which project(s) each document on a list page belongs to, so a list can show
// a Project column and filter by the Project / Contract filter. One request per
// list (all documents of that type), only when the module is on.

import { useCallback, useEffect, useMemo, useState } from "react"
import { getProjectLabels } from "@/lib/api/generic-projects"
import { useProjectsEnabled } from "@/hooks/use-generic-projects"
import type { ProjectFilterValue } from "@/lib/generic/project-math"

export type LabelSourceType = "Sale" | "Purchase" | "Expense" | "OwnerEntry" | "CustomerPayment" | "SupplierPayment"

export function useProjectLabels(sourceType: LabelSourceType, reloadKey?: unknown) {
  const { enabled } = useProjectsEnabled()
  const [map, setMap] = useState<Map<number, { projectId: number; label: string }[]>>(new Map())

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

  return useMemo(() => ({ enabled, map, matches, labelOf, reload: load }), [enabled, map, matches, labelOf, load])
}
