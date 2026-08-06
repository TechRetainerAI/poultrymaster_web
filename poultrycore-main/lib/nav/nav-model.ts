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

/** Active-row tint. One entry per nav bar colour that hosts a mega-menu. */
export type MegaMenuAccent = "sky" | "amber"

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
  /**
   * Tailwind bg-* class for the 2x2 group dot, e.g. "bg-emerald-600". Must be a
   * literal — Tailwind cannot see interpolated class names.
   */
  color: string
  items: MegaMenuItem[]
}
