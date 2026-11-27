"use client"

// The "Project / contract" column on Generic list pages that filter by project.
// Pages render it only while the company has Projects & Contracts switched on
// (useProjectsEnabled / labels.enabled), so a company that turned the feature
// off sees its tables exactly as before.

import { useCallback, useMemo } from "react"
import { TableCell, TableHead } from "@/components/ui/table"
import { useProjectOptions } from "@/hooks/use-generic-projects"

export const PROJECT_COLUMN_TITLE = "Project / contract"

export function ProjectHead({ className }: { className?: string }) {
  return <TableHead className={className}>{PROJECT_COLUMN_TITLE}</TableHead>
}

/** Full labels ("PRJ-0003 — Supply of Computers"); none = General. */
export function ProjectLabels({ labels }: { labels: string[] }) {
  if (labels.length === 0) return <span className="text-xs text-slate-400">General</span>
  return (
    <div className="space-y-0.5">
      {labels.map((l) => (
        <div key={l} className="max-w-[14rem] truncate text-xs font-medium text-indigo-700" title={l}>{l}</div>
      ))}
    </div>
  )
}

/**
 * A split, readable at a glance: each project with its share and, when the
 * record's amount is given, its part of it ("PRJ-0001 — Name · 50% · 5,000").
 * Falls back to plain labels when no share is known (sales / purchases are
 * split per line). Whatever no project has is shown as General.
 */
export function ProjectSplitLabels({ parts, amount, fmt }: {
  parts: { label: string; share: number | null }[]
  amount?: number
  fmt?: (n: number) => string
}) {
  if (parts.length === 0) return <span className="text-xs text-slate-400">General</span>
  const known = parts.every((p) => p.share != null)
  if (!known) return <ProjectLabels labels={parts.map((p) => p.label)} />
  const total = parts.reduce((t, p) => t + (p.share ?? 0), 0)
  const pct = (s: number) => `${Math.round(s * 10000) / 100}%`
  const money = (s: number) => (amount != null && fmt ? ` · ${fmt(Math.round(amount * s * 100) / 100)}` : "")
  const rest = 1 - total
  return (
    <div className="space-y-0.5">
      {parts.map((p) => (
        <div key={p.label} className="max-w-[18rem] truncate text-xs font-medium text-indigo-700" title={p.label}>
          {p.label}{parts.length > 1 || (p.share ?? 1) < 0.999999
            ? <span className="font-normal text-slate-500"> · {pct(p.share ?? 0)}{money(p.share ?? 0)}</span> : null}
        </div>
      ))}
      {rest > 0.000001 && (
        <div className="text-[11px] text-slate-400">General · {pct(rest)}{money(rest)}</div>
      )}
    </div>
  )
}

export function ProjectCell({ labels, className }: { labels: string[]; className?: string }) {
  return <TableCell className={className}><ProjectLabels labels={labels} /></TableCell>
}

/**
 * id -> "PRJ-0003 — Name", for sources that return project ids only (activity
 * shares, open balances). Closed projects included so older rows still name theirs.
 */
export function useProjectNames() {
  const { options } = useProjectOptions(true)
  const byId = useMemo(() => new Map(options.map((o) => [o.projectId, o.label])), [options])
  return useCallback(
    (ids: number[]) => Array.from(new Set(ids)).map((id) => byId.get(id) ?? `Project #${id}`),
    [byId],
  )
}
