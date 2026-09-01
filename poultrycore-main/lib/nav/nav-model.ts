/**
 * Shared navigation model for the desktop top-nav mega-menus.
 *
 * Deliberately React-free so nav configs (lib/nav/*-nav-config.ts) never have
 * to import from components/ — the dependency only ever points lib -> lib.
 */

import type { LucideIcon } from "lucide-react"

/**
 * Is `href` the current page? Prefix-matching so a detail route
 * (/water-drivers/12) still lights up its list entry. /dashboard is exempt
 * because every route would otherwise match it.
 *
 * Moved here verbatim from top-nav.tsx so the sidebar's inline copy and the
 * top-nav's can eventually converge on one implementation.
 */
export function navPathActive(pathname: string, href: string): boolean {
  return pathname === href || (href !== "/dashboard" && pathname.startsWith(`${href}/`))
}

/** A row in the narrow single-column NavDropdown (and the nav rail's NavLink). */
export interface NavItem {
  href: string
  label: string
  icon: LucideIcon
}

export interface NavGroup {
  label: string
  items: NavItem[]
}

/**
 * Which company colour a nav panel is tinted with. One entry per nav bar:
 * sky = Water (bg-sky-600), orange = Poultry (bg-orange-500),
 * emerald = Generic (bg-emerald-600).
 *
 * Used by both the wide NavMegaMenu and the narrow NavDropdown — the classes
 * themselves live in components/dashboard/nav/nav-surface.ts.
 */
export type NavAccent = "sky" | "orange" | "emerald" | "violet"

export interface MegaMenuItem {
  /**
   * Unique within its group. REQUIRED rather than derived from href: hrefs are
   * not unique across menus (Deliveries and Sales each appear in Quick Links
   * *and* their canonical group) and action rows have no href at all.
   */
  id: string
  title: string
  icon: LucideIcon
  /** Link target. Omit for action rows. */
  href?: string
  /**
   * Action row — renders a <button> instead of a <Link>. Takes precedence over
   * `href` if both are set. Never model an action as href="#": <Link href="#">
   * pushes a history entry and scroll-jumps to the top of the page.
   */
  onClick?: () => void
  /** Extra prefixes that also light this row up. */
  activeHrefs?: string[]
  /** Red count pill on the right of the row. Hidden when 0 or undefined. */
  badge?: number
  /** false -> the row is dropped (permission gate). Defaults to visible. */
  visible?: boolean
}

export interface MegaMenuGroup {
  key: string
  label: string
  items: MegaMenuItem[]
}
// NOTE: groups used to carry a `color` for a 2x2 dot beside the heading. The
// dot is gone (arbitrary hues that encoded nothing, and some vanished against
// the tinted panel) — headings now use a rule in the panel's own border colour.
// The report CONFIGS still have a `color`; the /water-reports and
// /poultry/reports index pages render it as a solid icon tile, which is a real
// use. It just no longer travels into the nav model.
