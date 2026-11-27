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
    <span className="flex flex-col gap-0.5">
      {labels.map((l) => (
        <span key={l} className="block max-w-[14rem] truncate text-xs font-medium text-indigo-700" title={l}>{l}</span>
      ))}
    </span>
  )
}

const projectNo = (label: string) => label.split(" — ")[0]
const projectName = (label: string) => label.split(" — ").slice(1).join(" — ")
const pctText = (s: number) => `${Math.round(s * 10000) / 100}%`

/**
 * A split in a table cell: one compact line per project -- number, share and
 * amount ("PRJ-0001 · 50% · GHC 1,000.00"). Nothing is cut off; the full
 * project name is on hover. Plain labels when no share is known (sales /
 * purchases are split per line). Whatever no project has is General.
 */
export function ProjectSplitLabels({ parts, amount, fmt }: {
  parts: { label: string; share: number | null }[]
  amount?: number
  fmt?: (n: number) => string
}) {
  if (parts.length === 0) return <span className="text-xs text-slate-400">General</span>
  const known = parts.every((p) => p.share != null)
  if (!known) return <ProjectLabels labels={parts.map((p) => p.label)} />
  const whole = parts.length === 1 && (parts[0].share ?? 0) >= 0.999999
  if (whole) return <ProjectLabels labels={[parts[0].label]} />
  const money = (s: number) => (amount != null && fmt ? fmt(Math.round(amount * s * 100) / 100) : null)
  const rest = 1 - parts.reduce((t, p) => t + (p.share ?? 0), 0)
  return (
    <span className="flex flex-col gap-0.5">
      {parts.map((p) => (
        <span key={p.label} className="block whitespace-nowrap text-xs" title={p.label}>
          <span className="font-medium text-indigo-700">{projectNo(p.label)}</span>
          <span className="text-slate-500"> · {pctText(p.share ?? 0)}</span>
          {money(p.share ?? 0) && <span className="tabular-nums text-slate-700"> · {money(p.share ?? 0)}</span>}
        </span>
      ))}
      {rest > 0.000001 && (
        <span className="block whitespace-nowrap text-[11px] text-slate-400">
          General · {pctText(rest)}{money(rest) ? ` · ${money(rest)}` : ""}
        </span>
      )}
    </span>
  )
}

/**
 * The full split, for an opened row: a small table with each project's name,
 * a share bar, its share and its amount, then General (if any) and the total.
 */
export function ProjectSplitTable({ parts, amount, fmt, title }: {
  parts: { label: string; share: number | null }[]
  amount: number
  fmt: (n: number) => string
  title?: string
}) {
  const rows = parts.filter((p) => p.share != null) as { label: string; share: number }[]
  if (rows.length === 0) return null
  const rest = Math.max(0, 1 - rows.reduce((t, p) => t + p.share, 0))
  const part = (s: number) => Math.round(amount * s * 100) / 100
  const line = (key: string, no: string, name: string, share: number, muted = false) => (
    <tr key={key} className={muted ? "text-slate-500" : undefined}>
      <td className="py-1.5 pr-4">
        <span className={muted ? "" : "font-medium text-indigo-700"}>{no}</span>
        {name && <span className="ml-1.5 text-slate-600">{name}</span>}
      </td>
      <td className="w-40 py-1.5 pr-4">
        <span className="block h-1.5 w-full rounded-full bg-slate-200">
          <span className={`block h-1.5 rounded-full ${muted ? "bg-slate-400" : "bg-indigo-500"}`} style={{ width: `${Math.min(100, share * 100)}%` }} />
        </span>
      </td>
      <td className="py-1.5 pr-4 text-right tabular-nums">{pctText(share)}</td>
      <td className="py-1.5 text-right tabular-nums">{fmt(part(share))}</td>
    </tr>
  )
  return (
    <div className="max-w-2xl">
      {title && <div className="mb-1 text-xs font-semibold uppercase tracking-wide text-slate-500">{title}</div>}
      <table className="w-full text-sm">
        <thead>
          <tr className="text-left text-xs text-slate-500">
            <th className="pb-1 pr-4 font-medium">Project / contract</th>
            <th className="pb-1 pr-4 font-medium" />
            <th className="pb-1 pr-4 text-right font-medium">Share</th>
            <th className="pb-1 text-right font-medium">Amount</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-slate-100">
          {rows.map((p) => line(p.label, projectNo(p.label), projectName(p.label), p.share))}
          {rest > 0.000001 && line("general", "General", "company, no project", rest, true)}
        </tbody>
        <tfoot>
          <tr className="border-t border-slate-300 font-semibold">
            <td className="pt-1.5 pr-4">Total</td><td />
            <td className="pt-1.5 pr-4 text-right tabular-nums">100%</td>
            <td className="pt-1.5 text-right tabular-nums">{fmt(amount)}</td>
          </tr>
        </tfoot>
      </table>
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
