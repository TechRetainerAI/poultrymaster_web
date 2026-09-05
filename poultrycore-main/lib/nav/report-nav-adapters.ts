/**
 * Report catalogs -> the shared mega-menu shape.
 *
 * Mapped once at module load rather than per render: both sources are static
 * module data, so a stable array identity gives NavMegaMenu's useMemo a free
 * cache hit and avoids re-mapping ~50 items on every nav render.
 */

import { WATER_REPORT_GROUPS, waterReportHref } from "@/lib/reports/water-reports-config"
import { POULTRY_REPORT_MENU_GROUPS } from "@/lib/reports/poultry-reports-config"
import { HOTEL_REPORT_GROUPS } from "@/lib/reports/hotel-reports-config"
import { RESTAURANT_REPORT_GROUPS } from "@/lib/reports/restaurant-reports-config"
import type { MegaMenuGroup } from "./nav-model"

/**
 * Water reports use `reports` / `slug` plus an href *function*.
 *
 * `status: "stub"` is deliberately NOT filtered — the menu has always rendered
 * every report regardless of status (and all 24 are currently "ready").
 */
export const WATER_REPORT_NAV_GROUPS: MegaMenuGroup[] = WATER_REPORT_GROUPS.map((g) => ({
  key: g.key,
  label: g.label,
  items: g.reports.map((r) => ({
    // Slugs are unique per group, not globally — prefix to be safe.
    id: `${g.key}:${r.slug}`,
    title: r.title,
    icon: r.icon,
    href: waterReportHref(r.slug),
  })),
}))

/**
 * Poultry menu groups are already `items` / `id` / `href`.
 *
 * Safe to map at module scope even though poultry-reports-config.ts push-mutates
 * its groups (Batch Production Summary, Feed Production): that mutation happens
 * during *its own* module evaluation, which completes before this import
 * resolves. If it ever grows a runtime mutation, make this a function.
 */
export const POULTRY_REPORT_NAV_GROUPS: MegaMenuGroup[] = POULTRY_REPORT_MENU_GROUPS.map((g) => ({
  key: g.key,
  label: g.label,
  items: g.items.map((it) => ({
    id: `${g.key}:${it.id}`,
    title: it.title,
    icon: it.icon,
    href: it.href,
  })),
}))

/**
 * Hotel reports: same slug-based pattern as water.
 */
export const HOTEL_REPORT_NAV_GROUPS: MegaMenuGroup[] = HOTEL_REPORT_GROUPS.map((g) => ({
  key: g.key,
  label: g.label,
  items: g.reports.map((r) => ({
    id: `${g.key}:${r.slug}`,
    title: r.title,
    icon: r.icon,
    href: `/hotel-reports/${r.slug}`,
  })),
}))

/**
 * Restaurant reports: same pattern. Links to /restaurant-reports with tab hash.
 */
export const RESTAURANT_REPORT_NAV_GROUPS: MegaMenuGroup[] = RESTAURANT_REPORT_GROUPS.map((g) => ({
  key: g.key,
  label: g.label,
  items: g.reports.map((r) => ({
    id: `${g.key}:${r.slug}`,
    title: r.title,
    icon: r.icon,
    href: `/restaurant-reports?tab=${r.slug}`,
  })),
}))
