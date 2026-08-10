"use client"

/**
 * Wide, grouped nav panel — the pattern the Water/Poultry Reports menus already
 * used, generalised so any top-nav group can adopt it.
 *
 * Renders a portalled white card: a header strip (title + blurb + optional
 * "View all" link) above N labelled, colour-dotted columns of icon+title rows.
 */

import Link from "next/link"
import { usePathname } from "next/navigation"
import { useMemo } from "react"
import { createPortal } from "react-dom"
import { ChevronDown, type LucideIcon } from "lucide-react"
import { cn } from "@/lib/utils"
import { navPathActive, type NavAccent, type MegaMenuGroup, type MegaMenuItem } from "@/lib/nav/nav-model"
import { NAV_SURFACE } from "./nav-surface"
import { useNavPopover, NAV_TRIGGER_CLASS, NAV_TRIGGER_ACTIVE } from "./use-nav-popover"

export interface NavMegaMenuProps {
  /** Trigger text + icon in the nav rail. */
  label: string
  icon: LucideIcon
  groups: MegaMenuGroup[]
  /** Header strip title (often the same as `label`). */
  title: string
  blurb?: string
  viewAll?: { href: string; label: string }
  columns?: 1 | 2 | 3 | 4
  /** Panel width in rem. Also drives the right-edge clamp, so the two can't drift. */
  widthRem?: number
  accent?: NavAccent
  /**
   * "columns" = CSS multi-column, which balances by HEIGHT — a group is never
   * split (break-inside-avoid) but group N is not pinned to column N. Fine for
   * Reports, whose many small groups are meant to flow; wrong for a 3-group
   * menu where the columns ARE the taxonomy. Use "grid" for those.
   */
  layout?: "columns" | "grid"
  /** Prefixes that make the TRIGGER active even when no row matches — e.g. the
   *  /water-reports index page itself, which isn't one of the rows. */
  triggerActiveHrefs?: string[]
  closeDelayMs?: number
}

const COLUMNS_CLASS: Record<1 | 2 | 3 | 4, string> = {
  1: "columns-1",
  2: "columns-1 lg:columns-2",
  3: "columns-2 lg:columns-3",
  4: "columns-2 lg:columns-4",
}

// items-start, or a short column stretches to the tallest one and its hover
// targets grow into the empty space below the last row.
const GRID_CLASS: Record<1 | 2 | 3 | 4, string> = {
  1: "grid grid-cols-1 items-start",
  2: "grid grid-cols-1 lg:grid-cols-2 items-start",
  3: "grid grid-cols-2 lg:grid-cols-3 items-start",
  4: "grid grid-cols-2 lg:grid-cols-4 items-start",
}


export function NavMegaMenu({
  label, icon: TriggerIcon, groups, title, blurb, viewAll,
  columns = 4, widthRem = 56, accent = "sky", layout = "columns",
  triggerActiveHrefs, closeDelayMs = 180,
}: NavMegaMenuProps) {
  const pathname = usePathname()
  const pop = useNavPopover({ closeDelayMs, menuWidthPx: widthRem * 16 })
  const a = NAV_SURFACE[accent]

  // Drop permission-hidden rows, then drop any group left empty.
  const visibleGroups = useMemo(
    () => groups
      .map((g) => ({ ...g, items: g.items.filter((i) => i.visible !== false) }))
      .filter((g) => g.items.length > 0),
    [groups],
  )

  const isRowActive = (it: MegaMenuItem) =>
    (it.href ? navPathActive(pathname, it.href) : false) ||
    (it.activeHrefs ?? []).some((h) => navPathActive(pathname, h))

  const triggerActive =
    visibleGroups.some((g) => g.items.some(isRowActive)) ||
    (triggerActiveHrefs ?? []).some((h) => navPathActive(pathname, h))

  // With a single group the dot + uppercase label just repeats the header
  // strip's title, so drop it and let the rows sit directly under the header.
  const showGroupLabels = visibleGroups.length > 1

  // After the hooks — bailing earlier would break the hook order.
  if (visibleGroups.length === 0) return null

  return (
    <div ref={pop.triggerRef} onMouseEnter={pop.handleMouseEnter} onMouseLeave={pop.handleMouseLeave}>
      <button
        onClick={pop.toggle}
        className={cn(NAV_TRIGGER_CLASS, triggerActive ? NAV_TRIGGER_ACTIVE : a.triggerIdle)}
      >
        <TriggerIcon className="h-4 w-4" />
        {label}
        <ChevronDown className={cn("h-3.5 w-3.5 transition-transform", pop.open ? "rotate-180" : "")} />
      </button>

      {pop.open && pop.mounted && createPortal(
        <div
          ref={pop.menuRef}
          style={{
            position: "fixed",
            top: pop.position.top,
            left: pop.position.left,
            width: `${widthRem}rem`,
            maxWidth: "calc(100vw - 16px)",
          }}
          className={cn("rounded-lg shadow-2xl border z-[9999] overflow-hidden", a.panel)}
          onMouseEnter={pop.handleMouseEnter}
          onMouseLeave={pop.handleMouseLeave}
        >
          {/* Header strip — gives the menu a clear identity. */}
          <div className={cn("px-5 py-3 border-b flex items-center justify-between", a.header)}>
            <div>
              <div className={cn("font-semibold text-sm", a.headerTitle)}>{title}</div>
              {blurb && <div className={cn("text-xs", a.headerBlurb)}>{blurb}</div>}
            </div>
            {viewAll && (
              <Link
                href={viewAll.href}
                prefetch
                onClick={pop.close}
                className={cn("text-xs font-medium hover:underline whitespace-nowrap", a.link)}
              >
                {viewAll.label}
              </Link>
            )}
          </div>

          <div
            className={cn(
              layout === "grid" ? GRID_CLASS[columns] : COLUMNS_CLASS[columns],
              "gap-x-4 p-4 max-h-[70vh] overflow-y-auto",
            )}
          >
            {visibleGroups.map((g) => (
              <div key={g.key} className={cn("min-w-0 break-inside-avoid", showGroupLabels && "mb-4")}>
                {showGroupLabels && (
                  // A rule rather than a coloured dot: the dots were seven
                  // arbitrary hues that encoded nothing, and on a tinted panel
                  // some of them (amber on orange-50) all but vanished.
                  <div className={cn("mb-2 pb-1.5 border-b", a.groupRule)}>
                    <h3 className={cn("text-[11px] font-semibold uppercase tracking-wider", a.groupLabel)}>{g.label}</h3>
                  </div>
                )}
                <ul className="space-y-0.5">
                  {g.items.map((it) => {
                    const active = isRowActive(it)
                    const Icon = it.icon
                    // w-full text-left so the <button> variant matches the
                    // <Link> — buttons shrink to fit and centre by default.
                    const rowClass = cn(
                      "w-full text-left flex items-start gap-2 px-2 py-1.5 rounded-md text-sm transition-colors",
                      active ? cn(a.rowActive, "font-medium") : a.rowIdle,
                    )
                    const rowInner = (
                      <>
                        <Icon className={cn("h-4 w-4 mt-0.5 shrink-0", active ? a.iconActive : a.iconIdle)} />
                        <span className="truncate">{it.title}</span>
                        {typeof it.badge === "number" && it.badge > 0 && (
                          <span className="ml-auto inline-flex items-center justify-center min-w-[20px] h-5 rounded-full bg-red-500 text-white text-[10px] font-bold px-1.5">
                            {it.badge > 99 ? "99+" : it.badge}
                          </span>
                        )}
                      </>
                    )
                    return (
                      <li key={it.id}>
                        {it.onClick ? (
                          <button
                            type="button"
                            className={rowClass}
                            onClick={() => { pop.close(); it.onClick!() }}
                          >
                            {rowInner}
                          </button>
                        ) : (
                          <Link href={it.href!} prefetch className={rowClass} onClick={pop.close}>
                            {rowInner}
                          </Link>
                        )}
                      </li>
                    )
                  })}
                </ul>
              </div>
            ))}
          </div>
        </div>,
        document.body,
      )}
    </div>
  )
}
