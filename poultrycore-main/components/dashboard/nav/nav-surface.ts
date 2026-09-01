/**
 * The single place a nav-panel colour is defined.
 *
 * Dropdowns used to be two different surfaces: mega-menus were plain white with
 * a slate header, while the narrow NavDropdown was bg-blue-600 — a leftover
 * that matched none of the three nav bars. Both now read from this map, so a
 * panel is always a pale tint of the active company's colour.
 *
 * Three steps per colour — panel (50) / hover (100) / active (200) — because
 * once the panel stops being white, a selected row needs two levels of headroom
 * to still read as selected.
 *
 * Text stays dark rather than white-on-brand: white on orange-500 is 2.8:1 and
 * on sky-600 is 4.1:1, both under the 4.5:1 WCAG AA floor for body text.
 *
 * Every value is a literal class string. Tailwind cannot see `bg-${accent}-50`,
 * so never build these by interpolation.
 */

import type { NavAccent } from "@/lib/nav/nav-model"

export interface NavSurface {
  /** Panel background + border. */
  panel: string
  /** Header strip background + border. */
  header: string
  /** Header strip title. A token, not a fixed slate, because a dark strip
   *  needs light text. */
  headerTitle: string
  /** Header strip sub-line. */
  headerBlurb: string
  /** Uppercase group heading. Carries no rule — the tracked caps are enough. */
  groupLabel: string
  /** Row text + hover background. */
  rowIdle: string
  /** Row background + text when it is the current page. */
  rowActive: string
  iconIdle: string
  iconActive: string
  /** "View all →" link in the header strip. */
  link: string
  /** Trigger button ON the nav bar, when it isn't the current section. The
   *  active state is bar-agnostic (bg-white/25) and lives in use-nav-popover. */
  triggerIdle: string
  /** Icon inside an idle trigger. One step darker than triggerIdle. */
  triggerIcon: string
}

/**
 * One dark chassis, three accents.
 *
 * Every panel is the same slate-800 card; only the accent changes per company —
 * sky (Water), orange (Poultry), emerald (Generic). So the panels read as one
 * component while each rail still says which company you're in.
 *
 * Dark was chosen over both a pale tint of the bar (too faint to register as a
 * background colour) and a saturated fill of it (a bright ground fights its own
 * text: white is 2.7:1 on sky-500 and 2.8:1 on orange-500, both under the 4.5:1
 * AA floor). Dark inverts the problem — pure white on slate-800 is 14.5:1 with
 * no compromises, and the bar above reads brighter because the panel beneath is
 * not competing for hue.
 *
 * The accent carries the group headings and the active row. Active rows use
 * near-black ON the accent rather than white, because the 400/500-level accents
 * are too light to hold white text.
 *
 * triggerIdle / triggerIcon are the exception to all of this: they sit on the
 * COLOURED BAR, not on the panel, so they stay tinted to their own bar.
 */
export const NAV_SURFACE: Record<NavAccent, NavSurface> = {
  sky: {
    panel:      "bg-slate-800 border-slate-700",
    header:     "bg-slate-900 border-slate-700",
    headerTitle: "text-white",
    headerBlurb: "text-slate-400",
    groupLabel: "text-sky-400",
    rowIdle:    "text-white hover:bg-slate-700",
    rowActive:  "bg-sky-500 text-slate-950",
    iconIdle:   "text-slate-400",
    iconActive: "text-slate-950",
    link:       "text-sky-400 hover:text-sky-300",
    triggerIdle: "text-sky-100 hover:bg-white/15 hover:text-white",
    triggerIcon: "text-sky-200",
  },
  orange: {
    panel:      "bg-slate-800 border-slate-700",
    header:     "bg-slate-900 border-slate-700",
    headerTitle: "text-white",
    headerBlurb: "text-slate-400",
    groupLabel: "text-orange-400",
    rowIdle:    "text-white hover:bg-slate-700",
    rowActive:  "bg-orange-500 text-slate-950",
    iconIdle:   "text-slate-400",
    iconActive: "text-slate-950",
    link:       "text-orange-400 hover:text-orange-300",
    triggerIdle: "text-orange-100 hover:bg-white/15 hover:text-white",
    triggerIcon: "text-orange-200",
  },
  emerald: {
    panel:      "bg-slate-800 border-slate-700",
    header:     "bg-slate-900 border-slate-700",
    headerTitle: "text-white",
    headerBlurb: "text-slate-400",
    groupLabel: "text-emerald-400",
    rowIdle:    "text-white hover:bg-slate-700",
    rowActive:  "bg-emerald-500 text-slate-950",
    iconIdle:   "text-slate-400",
    iconActive: "text-slate-950",
    link:       "text-emerald-400 hover:text-emerald-300",
    triggerIdle: "text-emerald-100 hover:bg-white/15 hover:text-white",
    triggerIcon: "text-emerald-200",
  },
  violet: {
    panel:      "bg-slate-800 border-slate-700",
    header:     "bg-slate-900 border-slate-700",
    headerTitle: "text-white",
    headerBlurb: "text-slate-400",
    groupLabel: "text-violet-400",
    rowIdle:    "text-white hover:bg-slate-700",
    rowActive:  "bg-violet-500 text-slate-950",
    iconIdle:   "text-slate-400",
    iconActive: "text-slate-950",
    link:       "text-violet-400 hover:text-violet-300",
    triggerIdle: "text-violet-100 hover:bg-white/15 hover:text-white",
    triggerIcon: "text-violet-200",
  },
}
