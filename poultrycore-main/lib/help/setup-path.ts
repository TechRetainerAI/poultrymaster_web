/**
 * "Set up a new farm" -- the numbered path at the top of the Setup Guide.
 *
 * The order is the order a new poultry farm can actually work in: money
 * accounts before anything is bought, houses before birds go into them, a
 * batch before it is split into flocks, flocks before production, customers
 * before a sale.
 *
 * A step whose result is a RECORD (a house, a flock, a sale) is ticked by
 * itself from the company's data (`count`). A step that is a SETTINGS screen
 * has nothing to count -- the screen always holds something -- so the person
 * ticks it (`manual`); that tick only remembers their own progress in this
 * browser, it changes nothing on the farm.
 */

import { setupHref } from "@/lib/nav/poultry-setup-tabs"

export type SetupCheck =
  | "houses" | "batches" | "flocks" | "cashAccounts" | "supplyItems"
  | "customers" | "suppliers" | "production" | "sales"

export interface SetupStep {
  id: string
  title: string
  /** One sentence: what and why. */
  detail: string
  /** Where the work is done. */
  href: string
  action: string
  /** The Setup Guide walkthrough with pictures for it, if any. */
  guide?: string
  /** Ticked from the data when the company has at least one of these. */
  count?: SetupCheck
  /** Nothing to count: the person ticks it. */
  manual?: true
  /** Not every farm needs it. */
  optional?: true
  /** A second way to do the step. */
  alt?: { label: string; href: string }
}

export const SETUP_STEPS: SetupStep[] = [
  {
    id: "company", title: "Company settings",
    detail: "Your business name and contacts, farm type, currency and business time zone. Every amount and date in the app uses them.",
    href: setupHref("production", "company-settings"), action: "Open Company settings",
    guide: "set-up-farm", manual: true,
  },
  {
    id: "cash-accounts", title: "Cash accounts",
    detail: "Your cash box, bank and mobile money accounts. Every payment in or out goes into one of them.",
    href: setupHref("business", "cash-accounts"), action: "Add a cash account",
    guide: "set-up-farm", count: "cashAccounts",
  },
  {
    id: "financial", title: "Financial settings",
    detail: "Choose whether feed and medicine count as a cost when you buy them or when you use them. Decide this before your first purchase.",
    href: setupHref("business", "financial-settings"), action: "Open Financial settings",
    guide: "set-up-farm", manual: true,
  },
  {
    id: "houses", title: "Houses & pens",
    detail: "Every house or pen your birds live in, with its capacity.",
    href: setupHref("production", "houses"), action: "Add a house",
    guide: "set-up-farm", count: "houses",
  },
  {
    id: "suppliers", title: "Suppliers",
    detail: "Everyone you buy birds, feed and supplies from. Add them before you record what you bought.",
    href: setupHref("business", "suppliers"), action: "Add a supplier",
    guide: "set-up-farm", count: "suppliers",
  },
  {
    id: "batches", title: "Bird purchase (batch)",
    detail: "Each batch of birds you bought: supplier, number of birds and cost per bird.",
    href: "/flock-batch", action: "Add a flock batch",
    guide: "add-flock", count: "batches",
    alt: { label: "Birds already on the farm? Use Initial Farm Setup", href: "/poultry-farm-setup" },
  },
  {
    id: "flocks", title: "Flock groups",
    detail: "Split each batch into the groups you manage, each in its house. Production is recorded per flock.",
    href: "/flocks", action: "Add a flock",
    guide: "add-flock", count: "flocks",
  },
  {
    id: "egg-settings", title: "Egg settings",
    detail: "Pick times, eggs per crate, packaging and egg sizes. They shape how production is recorded.",
    href: "/business-office/egg-pick-settings", action: "Open Egg Settings",
    guide: "eggs-per-crate", manual: true,
  },
  {
    id: "supply-items", title: "Supply items",
    detail: "Feed, medicine, packaging and other supplies you keep in stock.",
    href: setupHref("production", "inventory"), action: "Add a supply item",
    guide: "which-purchase", count: "supplyItems",
  },
  {
    id: "customers", title: "Customers",
    detail: "Everyone you sell to. You pick them when you record a sale.",
    href: setupHref("business", "customers"), action: "Add a customer",
    guide: "set-up-farm", count: "customers",
  },
  {
    id: "users", title: "Staff logins",
    detail: "Give each worker their own login and switch on only the pages they need.",
    href: "/employees", action: "Open Users & Permissions",
    guide: "add-user", manual: true, optional: true,
  },
  {
    id: "production", title: "First production record",
    detail: "Log the eggs, deaths and feed of each flock after a pick. From here on, this is daily work.",
    href: "/production-records", action: "Log production",
    guide: "log-production", count: "production",
  },
  {
    id: "sales", title: "First sale",
    detail: "Record a sale as it happens, paid now, part paid or on credit.",
    href: "/sales", action: "Add a sale",
    guide: "record-sale", count: "sales",
  },
  {
    id: "daily-closing", title: "Close your first day",
    detail: "At the end of the day, check everything was recorded and close the day.",
    href: "/poultry-daily-closing", action: "Open Daily Closing",
    guide: "daily-closing", manual: true,
  },
]

export type StepState = "done" | "todo" | "unknown"

/**
 * The state of each step. `counts` holds what the company has (undefined =
 * could not be read, e.g. no permission or offline); `ticked` the manual steps
 * the person has ticked.
 */
export function stepStates(
  steps: SetupStep[],
  counts: Partial<Record<SetupCheck, number | undefined>>,
  ticked: ReadonlySet<string>,
): Record<string, StepState> {
  const out: Record<string, StepState> = {}
  for (const s of steps) {
    if (s.count) {
      const n = counts[s.count]
      out[s.id] = n == null ? "unknown" : n > 0 ? "done" : "todo"
    } else {
      out[s.id] = ticked.has(s.id) ? "done" : "todo"
    }
  }
  return out
}

/** Progress over the required steps; an optional step never holds it back. */
export function setupProgress(steps: SetupStep[], states: Record<string, StepState>) {
  const required = steps.filter((s) => !s.optional)
  const done = required.filter((s) => states[s.id] === "done").length
  // The step to do next: the first required one not done (unknown counts as not done).
  const next = required.find((s) => states[s.id] !== "done")?.id ?? null
  return { done, total: required.length, next, complete: done === required.length }
}
