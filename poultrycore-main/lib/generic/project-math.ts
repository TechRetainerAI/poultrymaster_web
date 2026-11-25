// Projects & Contracts — the small pure rules the screens share. The money is
// always worked out by the database (484); these only shape what the user types
// before it is sent, and read the report filter value.

import type { ProjectAssignment, ProjectSplit } from "@/lib/api/generic-projects"

// ---------------------------------------------------------------- report filter

/**
 * The value of a "Project / Contract" report filter, as sent to the API in
 * `?project=`. Mirrors GenericProjectScope.Parse in the Farm API.
 */
export type ProjectFilterValue =
  | { kind: "all" }
  | { kind: "general" }
  | { kind: "projects"; ids: number[] }

export const ALL_PROJECTS: ProjectFilterValue = { kind: "all" }

export function filterToParam(v: ProjectFilterValue): string {
  if (v.kind === "all") return "all"
  if (v.kind === "general") return "general"
  return [...new Set(v.ids)].filter((n) => Number.isInteger(n) && n > 0).join(",") || "all"
}

export function paramToFilter(p: string | null | undefined): ProjectFilterValue {
  const s = (p ?? "").trim().toLowerCase()
  if (!s || s === "all") return ALL_PROJECTS
  if (s === "general") return { kind: "general" }
  const ids = s.split(",").map((x) => Number(x.trim())).filter((n) => Number.isInteger(n) && n > 0)
  return ids.length ? { kind: "projects", ids: [...new Set(ids)] } : ALL_PROJECTS
}

export function isFiltered(v: ProjectFilterValue): boolean {
  return v.kind !== "all"
}

// ---------------------------------------------------------------- splits

export type SplitBasis = "quantity" | "amount" | "percent"

export interface SplitRow {
  projectId: number | null
  value: number
}

export interface SplitCheck {
  /** What the rows add up to, in the basis's unit. */
  allocated: number
  /** What is left for General company activity (never negative when ok). */
  unallocated: number
  ok: boolean
  message: string | null
}

const EPS = 1e-9

/**
 * Check a split the user typed. The whole is the line's quantity, its amount,
 * or 100 for a percentage. Parts may add up to LESS than the whole -- the rest
 * stays General company activity -- but never to more, and never twice the same
 * project.
 */
export function checkSplit(rows: SplitRow[], basis: SplitBasis, whole: number): SplitCheck {
  const used = rows.filter((r) => r.projectId != null)
  const total = basis === "percent" ? 100 : whole
  const allocated = round(used.reduce((s, r) => s + (Number.isFinite(r.value) ? r.value : 0), 0), 6)
  const unallocated = round(total - allocated, 6)
  const ids = used.map((r) => r.projectId)
  if (new Set(ids).size !== ids.length) return { allocated, unallocated, ok: false, message: "The same project is listed twice." }
  if (used.some((r) => !(r.value > 0))) return { allocated, unallocated, ok: false, message: "Each project's part must be more than zero." }
  if (allocated > total + EPS) {
    return { allocated, unallocated, ok: false, message: "The parts add up to more than the whole. Nothing may be counted twice." }
  }
  return { allocated, unallocated, ok: true, message: null }
}

/** Turn typed rows into what the API takes. */
export function toSplits(rows: SplitRow[], basis: SplitBasis): ProjectSplit[] {
  return rows
    .filter((r) => r.projectId != null && r.value > 0)
    .map((r) =>
      basis === "quantity" ? { projectId: r.projectId!, quantity: r.value }
        : basis === "amount" ? { projectId: r.projectId!, amount: r.value }
          : { projectId: r.projectId!, share: round(r.value / 100, 6) })
}

/**
 * Build the "projects" value of a save.
 *  - a header project with no per-line splits -> the whole document
 *  - any per-line split -> per line (lines without their own split follow the header)
 *  - nothing chosen and the module off -> undefined (send nothing; old behaviour)
 */
export function buildAssignment(
  headerProjectId: number | null | undefined,
  lineSplits?: (ProjectSplit[] | null | undefined)[],
): ProjectAssignment | undefined {
  const anyLine = lineSplits?.some((l) => l && l.length > 0)
  if (anyLine && lineSplits) {
    return {
      lines: lineSplits.map((l) =>
        l && l.length > 0 ? l : headerProjectId ? [{ projectId: headerProjectId, share: 1 }] : null),
    }
  }
  if (headerProjectId === undefined) return undefined
  return { projectId: headerProjectId }
}

/** Read ?projectId= from a URL query string (Work inside a project). */
export function projectIdFromQuery(search: string | URLSearchParams | null | undefined): number | null {
  const p = typeof search === "string" ? new URLSearchParams(search) : search
  const n = Number(p?.get("projectId"))
  return Number.isInteger(n) && n > 0 ? n : null
}

export function round(n: number, dp = 2): number {
  const f = 10 ** dp
  return Math.round((n + Number.EPSILON) * f) / f
}

/** One project's share of a record (0 < share <= 1), as the 493 endpoints return it. */
export type ProjectShare = { projectId: number; share: number }

/**
 * The part of `amount` the filter covers, split the way the database engine
 * splits it (484): each project's part rounded to the cent, General takes the
 * remainder, so projects + General always add back to the whole exactly.
 * "all" = the whole amount.
 */
export function projectPart(amount: number, shares: ProjectShare[] | undefined, f: ProjectFilterValue): number {
  if (f.kind === "all") return amount
  const parts = (shares ?? []).map((s) => ({ id: s.projectId, amount: round(amount * s.share) }))
  if (f.kind === "general") return round(amount - parts.reduce((t, p) => t + p.amount, 0))
  return round(parts.filter((p) => f.ids.includes(p.id)).reduce((t, p) => t + p.amount, 0))
}

// ---------------------------------------------------------------- reconciliation

/** True when every company figure equals projects + General (to the cent). */
export function reconciles(rows: { company: number; projects: number; general: number }[]): boolean {
  return rows.every((r) => Math.abs(round(r.company - r.projects - r.general)) < 0.005)
}
