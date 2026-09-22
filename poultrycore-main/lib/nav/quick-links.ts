/**
 * Customisable Quick Links — the catalogue, and how a stored choice becomes a
 * rendered bar (migration 318).
 *
 * The bar used to be a fixed list in each nav config. It still is: that list is
 * the DEFAULT, and what this file adds is the ability for one user to say
 * "not that, these" for one company.
 *
 * THE GATE IS NOT HERE, AND THAT IS THE POINT
 * ===========================================
 * A stored href is a preference about what is SHOWN. It grants nothing. Both
 * functions below read from a nav config that has ALREADY had its permission
 * gates applied -- the mega-menu rows carry `visible: false` when the user may
 * not have them, and the default quick links were filtered by money() when the
 * config was built. So a row the user may not see is not in the catalogue, and
 * a stored href for such a row resolves to nothing and is dropped.
 *
 * That means a user who is later denied Cash Flow simply stops seeing the row
 * they pinned; their stored preference sits there harmlessly until they are
 * allowed it again. If this file ever starts resolving hrefs against anything
 * other than a gated config, a shortcut bar becomes a way around permissions.
 *
 * React-free, like the rest of lib/nav: these run inside the config builders.
 */

import type { LucideIcon } from "lucide-react"
import type { MegaMenuGroup, NavGroup, NavItem } from "./nav-model"

/**
 * The shape both the poultry and the water config share. Typed structurally
 * rather than importing either one, so this file does not depend on the two
 * modules that depend on it.
 */
export interface CustomisableNav {
  quickLinks: NavGroup
  operations: MegaMenuGroup[]
  salesMoney: MegaMenuGroup[]
  analytics: MegaMenuGroup[]
  setup: MegaMenuGroup[]
}

/** One row the user may pin, with the menu it normally lives in. */
export interface QuickLinkChoice extends NavItem {
  /** The menu this row's home is, for grouping the picker. */
  group: string
}

/**
 * Everything this user could pin, in rail order.
 *
 * `system` is deliberately excluded. Help, Alerts and Log out are not pages you
 * shortcut to -- two of them are action rows with no href at all -- and a
 * picker that offered "Log out" as a Quick Link would be answering a question
 * nobody asked.
 *
 * First occurrence of an href wins, so a page that is both a default quick link
 * and a row in its own menu keeps the quick link's wording ("Egg sorting"
 * rather than "Egg Production"): that is the shorter name, chosen for exactly
 * this bar.
 */
export function quickLinkCatalogue(nav: CustomisableNav): QuickLinkChoice[] {
  const out: QuickLinkChoice[] = []
  const seen = new Set<string>()

  const push = (item: NavItem, group: string) => {
    if (!item.href || seen.has(item.href)) return
    seen.add(item.href)
    out.push({ ...item, group })
  }

  for (const i of nav.quickLinks.items) push(i, "Shortcuts")

  const menus: [string, MegaMenuGroup[]][] = [
    ["Operations", nav.operations],
    ["Sales, Expenses & Money", nav.salesMoney],
    ["Trackers", nav.analytics],
    ["Setup", nav.setup],
  ]
  for (const [menu, groups] of menus) {
    for (const g of groups) {
      for (const it of g.items) {
        // No href = an action row. visible === false = the permission gate
        // already said no. Neither belongs in a list of pages to pin.
        if (!it.href || it.visible === false) continue
        push({ href: it.href, label: it.title, icon: it.icon }, `${menu} · ${g.label}`)
      }
    }
  }
  return out
}

/**
 * The bar to render: the user's choice if they have made one, the config's own
 * defaults if they have not.
 *
 * `hrefs === null` means NEVER CUSTOMISED and is not the same as `[]`, which
 * means "I cleared it". Collapsing the two would hand the defaults back to the
 * one user who explicitly did not want them.
 *
 * Unknown hrefs are dropped rather than rendered as dead rows: a page can be
 * renamed or removed, and a stored preference outlives both.
 */
export function resolveQuickLinks(
  nav: CustomisableNav,
  hrefs: string[] | null | undefined,
): NavItem[] {
  if (!hrefs) return nav.quickLinks.items

  const byHref = new Map(quickLinkCatalogue(nav).map((c) => [c.href, c]))
  return hrefs
    .map((h) => byHref.get(h))
    .filter((c): c is QuickLinkChoice => !!c)
    .map(({ group, ...item }) => item)
}
