// The Staff Page Access editor's state, as plain functions so it can be tested
// without a browser (tests 11, 24, 25, 26).
//
// The draft is the complete set of keys the person will hold in ONE company
// after Save — page views, page actions, and any finer keys they already had
// (those ride along untouched). Saving sends exactly this set; the database
// works out the Allow/Deny exceptions against their roles.

import {
  NAV_SECTIONS, defaultKeysFor, viewKey, type NavSection, type PageAction, type PageDef,
} from "@/lib/iam/page-catalog"

export const actionKey = (p: PageDef, a: PageAction) => `${p.module}.${p.resource}.${a}`

/** Tick or untick a page. Unticking also removes everything that page lets you do. */
export function setPageView(draft: ReadonlySet<string>, page: PageDef, on: boolean): Set<string> {
  const next = new Set(draft)
  if (on) {
    next.add(viewKey(page))
  } else {
    next.delete(viewKey(page))
    for (const a of page.actions ?? []) next.delete(actionKey(page, a))
  }
  return next
}

/** Tick or untick one action. An action needs the page itself, so ticking one ticks View too. */
export function setPageAction(draft: ReadonlySet<string>, page: PageDef, action: PageAction, on: boolean): Set<string> {
  const next = new Set(draft)
  if (on) {
    next.add(actionKey(page, action))
    next.add(viewKey(page))
  } else {
    next.delete(actionKey(page, action))
  }
  return next
}

/**
 * Select all / clear a section's pages (views only — Select all never grants
 * approve/reverse/delete). Returns the sensitive pages a Select all would turn
 * on so the caller can ask first.
 */
export function setSection(
  draft: ReadonlySet<string>, pages: readonly PageDef[], on: boolean, includeSensitive: boolean,
): Set<string> {
  let next = new Set(draft)
  for (const p of pages) {
    if (on && p.sensitive && !includeSensitive) continue
    next = setPageView(next, p, on)
  }
  return next
}

export function sensitiveTurnedOnBy(draft: ReadonlySet<string>, pages: readonly PageDef[]): PageDef[] {
  return pages.filter((p) => p.sensitive && !draft.has(viewKey(p)))
}

/** The default profile for a new employee in this company (ordinary pages ticked, nothing sensitive). */
export function defaultProfile(pages: readonly PageDef[], keep: ReadonlySet<string> = new Set()): Set<string> {
  const pageKeys = new Set(pages.flatMap((p) => ["view", ...(p.actions ?? [])].map((a) => `${p.module}.${p.resource}.${a}`)))
  // Keys outside the page list (finer actions) are left as they were.
  const next = new Set([...keep].filter((k) => !pageKeys.has(k)))
  for (const k of defaultKeysFor(pages)) next.add(k)
  return next
}

export interface SectionSummary {
  section: NavSection
  pages: PageDef[]
  enabled: number
}

export type ShowFilter = "all" | "enabled" | "disabled"

/**
 * Group pages by menu section for display, applying search and the
 * enabled/disabled filter. Filtering only changes what is SHOWN: the draft is
 * never touched, so ticks on hidden rows survive (test 25).
 */
export function groupForDisplay(
  pages: readonly PageDef[], draft: ReadonlySet<string>, query: string, show: ShowFilter,
): SectionSummary[] {
  const q = query.trim().toLowerCase()
  const out: SectionSummary[] = []
  for (const section of NAV_SECTIONS) {
    const all = pages.filter((p) => p.section === section)
    if (all.length === 0) continue
    const shown = all.filter((p) => {
      const on = draft.has(viewKey(p))
      if (show === "enabled" && !on) return false
      if (show === "disabled" && on) return false
      if (!q) return true
      return `${p.label} ${p.group} ${p.section} ${p.routes.join(" ")}`.toLowerCase().includes(q)
    })
    if (shown.length === 0) continue
    out.push({ section, pages: shown, enabled: all.filter((p) => draft.has(viewKey(p))).length })
  }
  return out
}

/** Count of pages in a section, for "3 of 4 pages enabled". */
export const sectionTotal = (pages: readonly PageDef[], section: NavSection) =>
  pages.filter((p) => p.section === section).length

export interface DraftDiff {
  added: string[]
  removed: string[]
}

export function diffDrafts(initial: ReadonlySet<string>, draft: ReadonlySet<string>): DraftDiff {
  return {
    added: [...draft].filter((k) => !initial.has(k)).sort(),
    removed: [...initial].filter((k) => !draft.has(k)).sort(),
  }
}

/** Readable name for a key: "Profit & Loss" or "Sales — Approve". */
export function describeKey(key: string, pages: readonly PageDef[]): string {
  const [module, resource, action] = key.split(".")
  const page = pages.find((p) => p.module === module && p.resource === resource)
  const label = page?.label ?? `${resource}`
  return action === "view" ? label : `${label} — ${action[0].toUpperCase()}${action.slice(1)}`
}
