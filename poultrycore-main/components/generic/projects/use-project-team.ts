"use client"

// 500: which projects each staff member is on (the project TEAM), for the
// pages about people -- Employee Credit, Employee Loans & Advances. A staff
// member on several projects matches each of them. Loads only while the
// company has Projects & Contracts on.

import { useCallback, useEffect, useMemo, useState } from "react"
import { useProjectsEnabled } from "@/hooks/use-generic-projects"
import { getTeamByStaff } from "@/lib/api/generic-projects"
import type { ProjectFilterValue } from "@/lib/generic/project-math"

export function useProjectTeam() {
  const { enabled } = useProjectsEnabled()
  const [byStaff, setByStaff] = useState<Map<number, { projectId: number; label: string }[]>>(new Map())

  useEffect(() => {
    if (!enabled) { setByStaff(new Map()); return }
    let cancelled = false
    getTeamByStaff()
      .then((rows) => { if (!cancelled) setByStaff(new Map(rows.map((r) => [r.staffId, r.projects]))) })
      .catch(() => { if (!cancelled) setByStaff(new Map()) })
    return () => { cancelled = true }
  }, [enabled])

  /** Is this staff member on a project the filter picked? "general" = on no team at all. */
  const staffMatches = useCallback((staffId: number | null | undefined, f: ProjectFilterValue) => {
    if (f.kind === "all") return true
    const ps = staffId == null ? [] : (byStaff.get(staffId) ?? [])
    if (f.kind === "general") return ps.length === 0
    return ps.some((p) => f.ids.includes(p.projectId))
  }, [byStaff])

  /** The projects a staff member works on, for a column. */
  const teamLabels = useCallback((staffId: number | null | undefined) =>
    staffId == null ? [] : (byStaff.get(staffId) ?? []).map((p) => p.label), [byStaff])

  return useMemo(() => ({ enabled, staffMatches, teamLabels }), [enabled, staffMatches, teamLabels])
}
