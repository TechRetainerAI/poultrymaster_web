"use client"

// 493: the Project / Contract filter for a Generic list page, as one piece:
// the labelled control for the page's filter strip and the test for each row.
// Undefined while the module is off, so a company that never used projects
// sees its pages exactly as before.

import { useMemo, useState } from "react"
import { Label } from "@/components/ui/label"
import { ProjectFilter } from "@/components/generic/projects/project-filter"
import { useProjectLabels, type LabelSourceType } from "@/hooks/use-project-labels"
import { PROJECT_COLUMN_TITLE, ProjectSplitLabels } from "@/components/generic/projects/project-column"
import { ALL_PROJECTS, type ProjectFilterValue } from "@/lib/generic/project-math"

export function useProjectListFilter<T>(
  sourceType: LabelSourceType,
  /** The record's id as the projects module knows it; null = never belongs to a project. */
  idOf: (row: T) => number | null,
  reloadKey?: unknown,
) {
  const [filter, setFilter] = useState<ProjectFilterValue>(ALL_PROJECTS)
  const labels = useProjectLabels(sourceType, reloadKey)

  const extraFilter = useMemo(() => {
    if (!labels.enabled) return undefined
    return {
      control: (
        <div className="w-full space-y-1 sm:w-auto">
          <Label className="text-xs text-slate-500">Project / contract</Label>
          <ProjectFilter value={filter} onChange={setFilter} className="h-9 w-full sm:w-64" />
        </div>
      ),
      /** The Project / contract column, for shared tables that accept one. */
      column: {
        title: PROJECT_COLUMN_TITLE,
        // 502: with each project's share when it is known.
        cell: (row: T) => <ProjectSplitLabels parts={labels.partsOf(idOf(row))} />,
      },
      matches: (row: T) => {
        if (filter.kind === "all") return true
        const id = idOf(row)
        if (id == null) return filter.kind === "general"
        return labels.matches(id, filter)
      },
    }
    // idOf is a plain accessor; callers pass a new arrow each render.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [labels, filter])

  return { extraFilter, filter, setFilter, labels }
}
