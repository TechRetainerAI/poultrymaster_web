/**
 * The page half of the header search: turning a nav config into a list of
 * searchable pages, and ranking that list against what was typed.
 *
 * THE INDEX IS BUILT FROM THE GATED NAV, ON PURPOSE
 * =================================================
 * Same rule as lib/nav/quick-links.ts. The configs have already had their
 * permission gates applied -- a row the user may not open carries
 * `visible: false` -- so flattening them yields exactly the pages this user
 * may open, for the company type they are in. A hand-kept route list (which is
 * what the header used to have) shows Flocks on a Water company and Cash Flow
 * to a staff member denied it. The synonyms below only ever ADD words to a page
 * already in the index; they cannot add a page.
 *
 * React-free, like the rest of lib/.
 */

import type { LucideIcon } from "lucide-react"
import type { MegaMenuGroup, NavGroup } from "@/lib/nav/nav-model"
import { normalize, scoreFields } from "./fuzzy"

export interface SearchPage {
  href: string
  title: string
  /** The menu it lives in, shown beside the result ("Sales", "Trackers"). */
  group: string
  icon?: LucideIcon
  /** Extra words that should find this page. */
  keywords: string[]
}

function isNavGroup(v: unknown): v is NavGroup {
  return !!v && typeof v === "object" && Array.isArray((v as NavGroup).items) && "label" in (v as object)
    && !("key" in (v as object))
}

function isMegaMenuGroup(v: unknown): v is MegaMenuGroup {
  return !!v && typeof v === "object" && Array.isArray((v as MegaMenuGroup).items) && "key" in (v as object)
}

/**
 * Every visible, linkable row in a nav config. Accepts any of the config
 * shapes (each key is a NavGroup or a MegaMenuGroup[]) without importing them.
 *
 * Action rows (no href) are dropped -- "Log out" is not a search result.
 * Quick Links is read LAST so a page keeps the name of its canonical group
 * rather than "Quick Links", which says nothing about where it lives.
 */
export function flattenNavConfig(config: object, extraGroups: MegaMenuGroup[] = []): SearchPage[] {
  const out = new Map<string, SearchPage>()
  const add = (href: string | undefined, title: string, group: string, icon?: LucideIcon) => {
    if (!href) return
    const key = href.split("#")[0]
    if (out.has(key)) return
    out.set(key, { href, title, group, icon, keywords: [] })
  }

  const entries = Object.entries(config)
  const ordered = [
    ...entries.filter(([k]) => k !== "quickLinks"),
    ...entries.filter(([k]) => k === "quickLinks"),
  ]
  const visit = (v: unknown) => {
    if (isMegaMenuGroup(v)) {
      for (const it of v.items) {
        if (it.visible === false || it.onClick) continue
        add(it.href, it.title, v.label, it.icon)
      }
    } else if (isNavGroup(v)) {
      for (const it of v.items) add(it.href, it.label, v.label, it.icon)
    } else if (Array.isArray(v)) {
      v.forEach(visit)
    }
  }
  for (const [, v] of ordered) visit(v)
  extraGroups.forEach(visit)
  return withSynonyms([...out.values()])
}

/** NavGroup[] (the Generic sidebar lists) -> SearchPage[]. */
export function flattenNavGroups(groups: NavGroup[]): SearchPage[] {
  return flattenNavConfig({ groups })
}

/**
 * Words people use for a page that are not in its title. Matched on the
 * page's TITLE (normalised substring) rather than its href, so one entry covers
 * Poultry's /expenses and Water's /water-expenses alike. A leading `=` means
 * the whole title, not a substring: "=account" must not reach "Cash Account".
 */
const TITLE_SYNONYMS: [string, string[]][] = [
  ["flock group", ["birds", "chickens", "layers", "broilers", "flock", "flocks"]],
  ["flock purchases", ["batch", "batches", "chicks", "day old", "bird purchase"]],
  ["production records", ["eggs collected", "mortality", "deaths", "daily production", "egg collection"]],
  ["egg sorting", ["grading", "egg sizes", "crates", "trays"]],
  ["egg tracker", ["eggs at hand", "egg stock", "egg inventory"]],
  ["birds tracker", ["birds left", "bird count", "how many birds"]],
  ["dead birds", ["mortality", "deaths", "carcass"]],
  ["broken eggs", ["cracked eggs", "damaged eggs"]],
  ["feed usage", ["feeding", "feed consumed", "feed given"]],
  ["feed tracker", ["feed at hand", "feed stock", "feed consumption"]],
  ["feed formulas", ["ration", "recipe", "mix"]],
  ["health records", ["vaccination", "vaccine", "medication", "treatment", "disease", "vet"]],
  ["medication tracker", ["drugs", "medicine", "treatment log"]],
  ["treatment campaigns", ["vaccination programme", "deworming"]],
  ["sales", ["sell", "sold", "revenue", "invoice", "receipt", "orders"]],
  ["customer payments", ["collections", "money received", "paid", "receive payment"]],
  ["payments", ["collections", "money received"]],
  ["customer balances", ["debtors", "receivables", "who owes", "owing", "debt", "outstanding"]],
  ["customer credits", ["deposit", "advance", "overpayment", "prepaid"]],
  ["supplier balances", ["creditors", "payables", "we owe", "bills"]],
  ["supplier payments", ["pay supplier", "bills paid"]],
  ["supplier credits", ["supplier advance", "prepayment"]],
  ["suppliers", ["vendor", "vendors"]],
  ["customers", ["clients", "buyers"]],
  ["expenses", ["costs", "spending", "spent", "bills"]],
  ["recurring expenses", ["rent", "subscription", "monthly bills", "standing order"]],
  ["cash flow", ["money in", "money out", "cash movement"]],
  ["cash account", ["bank", "mobile money", "momo", "till"]],
  ["cash transfers", ["move money", "bank deposit", "withdrawal"]],
  ["reconciliation", ["cash count", "balance check", "shortage"]],
  ["profit and loss", ["pnl", "p and l", "income statement", "profit", "loss", "margin"]],
  ["financial activity", ["cash vs profit", "why is profit different", "profit impact"]],
  ["daily closing", ["end of day", "close day", "eod", "close the day"]],
  ["owner money", ["drawings", "capital", "owner withdrawal", "investment"]],
  ["loans", ["borrowing", "financing", "repayment"]],
  ["employee loans", ["salary advance", "staff loan"]],
  ["payroll", ["salaries", "wages", "pay staff"]],
  ["staff", ["workers", "employees", "team"]],
  ["users and permissions", ["access", "roles", "employees", "login", "accounts"]],
  ["inventory", ["stock", "items", "store"]],
  ["supply purchases", ["buy", "purchase", "restock", "procurement"]],
  ["receive purchase", ["goods received", "grn", "delivery from supplier"]],
  ["stock movement", ["stock ledger", "stock history", "adjustment"]],
  ["internal use", ["consumed", "used on farm", "own use"]],
  ["loss and damage", ["theft", "spoilage", "write off", "breakage"]],
  ["damages and loss", ["theft", "spoilage", "write off", "breakage"]],
  ["deliveries", ["driver returns", "load vehicle", "dispatch"]],
  ["drivers", ["riders"]],
  ["vehicles", ["trucks", "vans", "tricycle"]],
  ["capital investments", ["assets", "equipment", "depreciation"]],
  ["houses", ["pen", "pens", "barn", "coop"]],
  ["activity log", ["audit", "history", "who changed"]],
  ["=account", ["profile", "password", "my details", "settings"]],
  ["farm alerts", ["warnings", "notifications", "attention"]],
  ["restock forecast", ["running out", "reorder", "low stock"]],
  ["lifecycle", ["schedule", "milestones", "tasks"]],
  ["closeout", ["end flock", "depopulate", "close flock"]],
  ["water production", ["bags", "sachets", "bottles produced"]],
  ["boreholes", ["water source", "well"]],
  ["maintenance", ["repairs", "service", "breakdown"]],
  ["billing", ["subscription", "plan", "paystack"]],
  ["help", ["support", "how to", "guide"]],
  ["reports", ["analytics", "summary"]],
]

function withSynonyms(pages: SearchPage[]): SearchPage[] {
  return pages.map((p) => {
    const t = normalize(p.title)
    const extra = TITLE_SYNONYMS
      .filter(([needle]) => (needle.startsWith("=") ? t === needle.slice(1) : t.includes(needle))).flatMap(([, words]) => words)
    return extra.length ? { ...p, keywords: [...p.keywords, ...extra] } : p
  })
}

/**
 * Leading words that say what the user wants to DO rather than what they are
 * looking for. "new sale" should find Sales; "go to cash flow" should find Cash
 * Flow. They are stripped before matching; `create` remembers the verb was
 * there so the UI can label the result honestly.
 */
const NAV_VERBS = ["go to", "goto", "open", "show", "view", "find", "search", "see"]
const CREATE_VERBS = ["new", "add", "record", "create", "log", "enter", "make"]

export interface ParsedQuery {
  /** What is left to match once the verb is gone. */
  text: string
  /** The query asked to record something ("new sale", "record expense"). */
  create: boolean
}

export function parseQuery(raw: string): ParsedQuery {
  let text = normalize(raw)
  let create = false
  for (const v of NAV_VERBS) {
    if (text.startsWith(`${v} `)) { text = text.slice(v.length + 1); break }
  }
  for (const v of CREATE_VERBS) {
    if (text.startsWith(`${v} `)) { text = text.slice(v.length + 1); create = true; break }
  }
  // "new sale" -> "sale" should still find "Sales"; a trailing "a" / "an"
  // ("record a sale") is noise.
  text = text.replace(/^(a|an|the)\s+/, "")
  return { text, create }
}

export interface RankedPage extends SearchPage {
  score: number
}

/**
 * Pages matching `raw`, best first. Recent pages get a small nudge so the one
 * you opened yesterday wins a tie, but never enough to beat a better match.
 */
export function rankPages(raw: string, pages: SearchPage[], recentHrefs: string[] = [], limit = 8): RankedPage[] {
  const { text } = parseQuery(raw)
  if (!text) return []
  const ranked: RankedPage[] = []
  for (const p of pages) {
    let score = scoreFields(text, [
      { text: p.title, weight: 1 },
      ...p.keywords.map((k) => ({ text: k, weight: 0.85 })),
      { text: p.group, weight: 0.45 },
    ])
    if (score <= 0) continue
    const r = recentHrefs.indexOf(p.href)
    if (r !== -1) score += Math.max(0, 6 - r)
    // Shorter titles win ties: "Sales" over "Sales by customer report".
    score -= Math.min(4, p.title.length / 12)
    ranked.push({ ...p, score })
  }
  return ranked.sort((a, b) => b.score - a.score).slice(0, limit)
}
