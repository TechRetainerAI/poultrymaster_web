"use client"

/**
 * A sidebar section's menu, opened BESIDE the sidebar.
 *
 * Same menus as the top nav -- same config (lib/nav/*-nav-config.ts), same
 * routes, same dark chassis and orange accent (NAV_SURFACE) -- but with the
 * interaction a tall vertical rail needs, which the top nav's NavMegaMenu does
 * not have:
 *
 *   HOVER INTENT   Opens ~180ms after the pointer settles on a row, so sweeping
 *                  the mouse across the sidebar on the way to the page does not
 *                  fire a large panel. Once a menu is open, resting on another
 *                  row switches after ~150ms; merely crossing rows on the way
 *                  into the open panel does not.
 *   GRACE PERIOD   Leaving the row or the panel closes after ~200ms, and
 *                  entering either cancels it, so the trip from row to panel
 *                  never flickers.
 *   CLICK          Opens and PINS. A pinned menu ignores the pointer leaving;
 *                  it closes on a click outside, Esc, choosing a row, or
 *                  opening another section. A second click keeps it open.
 *   ONE AT A TIME  Opening a menu closes whichever other sidebar menu is open.
 *   KEYBOARD       Enter/Space/ArrowRight on the row opens it and focuses the
 *                  first link; arrows, Home and End move inside; Esc and Tab
 *                  close it and hand focus back to the row.
 *
 * Positioning is measured, not guessed: the panel sits against the sidebar's
 * right edge (the element marked `data-flyout-anchor`), level with its row, and
 * is pushed up just enough to stay on screen when the row is low. It follows
 * the row while the page or the sidebar scrolls, and on a window too narrow for
 * its columns it drops to a single scrolling column.
 */

import Link from "next/link"
import { usePathname } from "next/navigation"
import {
  useCallback, useEffect, useId, useLayoutEffect, useMemo, useRef, useState,
  type KeyboardEvent as ReactKeyboardEvent, type ReactNode,
} from "react"
import { createPortal } from "react-dom"
import type { LucideIcon } from "lucide-react"
import { cn } from "@/lib/utils"
import { navPathActive, type MegaMenuGroup, type MegaMenuItem, type NavAccent } from "@/lib/nav/nav-model"
import { NAV_SURFACE } from "./nav-surface"

const OPEN_DELAY_MS = 180
/**
 * Moving to ANOTHER row while a menu is open. Deliberately not instant: the
 * way from a row into its panel runs diagonally across the rows below it, and
 * an instant switch swapped the panel out from under the pointer on its way
 * in. A row crossed in passing is under the pointer for a few milliseconds;
 * one the user stops on is under it for longer than this.
 */
const SWITCH_DELAY_MS = 150
const CLOSE_DELAY_MS = 200
/** Matches the panel's exit animation, so it unmounts as it finishes. */
const EXIT_MS = 150
const GAP_PX = 8
const EDGE_PX = 8

// ---------------------------------------------------------------------------
// One open at a time, across every sidebar menu.
// ---------------------------------------------------------------------------
let openMenu: { id: string; close: () => void } | null = null

export interface SidebarFlyoutMenuProps {
  label: string
  icon: LucideIcon
  groups: MegaMenuGroup[]
  /** Header title; defaults to the label. */
  title?: string
  blurb?: string
  viewAll?: { href: string; label: string }
  /** How many groups sit side by side. The panel sizes to its content. */
  columns?: 1 | 2 | 3
  /** Extra prefixes that count as "you are in this section". */
  activeHrefs?: string[]
  /** Fill the current page's row. Off for one-row panels, where it would fill everything. */
  highlightActiveRow?: boolean
  /** Icon-only sidebar: the row shows just the icon. */
  collapsed?: boolean
  accent?: NavAccent
  /** Called after a row is chosen (e.g. to close a drawer). */
  onNavigate?: () => void
}

export function SidebarFlyoutMenu({
  label, icon: Icon, groups, title = label, blurb, viewAll, columns = 1,
  activeHrefs, highlightActiveRow = true, collapsed = false, accent = "orange", onNavigate,
}: SidebarFlyoutMenuProps) {
  const pathname = usePathname()
  const a = NAV_SURFACE[accent]
  const id = useId()
  const panelId = `${id}-panel`

  const [open, setOpen] = useState(false)
  const [rendered, setRendered] = useState(false)
  const [mounted, setMounted] = useState(false)
  const [pos, setPos] = useState({ top: 0, left: 0, maxHeight: 600, maxWidth: 560, caret: 20, compact: false })

  const triggerRef = useRef<HTMLButtonElement>(null)
  const panelRef = useRef<HTMLDivElement>(null)
  const headerRef = useRef<HTMLDivElement>(null)
  const bodyRef = useRef<HTMLDivElement>(null)
  const openTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const closeTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const exitTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const pinned = useRef(false)
  const focusFirstOnOpen = useRef(false)

  useEffect(() => { setMounted(true) }, [])

  const visibleGroups = useMemo(
    () => groups
      .map((g) => ({ ...g, items: g.items.filter((i) => i.visible !== false) }))
      .filter((g) => g.items.length > 0),
    [groups],
  )

  const isRowActive = (it: MegaMenuItem) =>
    (it.href ? navPathActive(pathname, it.href) : false) ||
    (it.activeHrefs ?? []).some((h) => navPathActive(pathname, h))
  const sectionActive =
    visibleGroups.some((g) => g.items.some(isRowActive)) ||
    (activeHrefs ?? []).some((h) => navPathActive(pathname, h))

  const clearTimers = () => {
    if (openTimer.current) clearTimeout(openTimer.current)
    if (closeTimer.current) clearTimeout(closeTimer.current)
    openTimer.current = null
    closeTimer.current = null
  }

  const hide = useCallback((returnFocus = false) => {
    if (openTimer.current) clearTimeout(openTimer.current)
    if (closeTimer.current) clearTimeout(closeTimer.current)
    pinned.current = false
    setOpen(false)
    if (openMenu?.id === id) openMenu = null
    if (exitTimer.current) clearTimeout(exitTimer.current)
    exitTimer.current = setTimeout(() => setRendered(false), EXIT_MS)
    if (returnFocus) triggerRef.current?.focus()
  }, [id])

  const show = useCallback(() => {
    if (openMenu && openMenu.id !== id) openMenu.close()
    openMenu = { id, close: () => hide(false) }
    if (exitTimer.current) clearTimeout(exitTimer.current)
    setRendered(true)
    setOpen(true)
  }, [id, hide])

  // Timers and the registry entry must not outlive the component.
  useEffect(() => () => {
    if (openTimer.current) clearTimeout(openTimer.current)
    if (closeTimer.current) clearTimeout(closeTimer.current)
    if (exitTimer.current) clearTimeout(exitTimer.current)
    if (openMenu?.id === id) openMenu = null
  }, [id])

  // A new page means the menu did its job.
  useEffect(() => { if (open) hide(false) }, [pathname]) // eslint-disable-line react-hooks/exhaustive-deps

  // ---- Pointer ------------------------------------------------------------
  const onTriggerEnter = () => {
    if (closeTimer.current) { clearTimeout(closeTimer.current); closeTimer.current = null }
    if (open) return
    const delay = openMenu && openMenu.id !== id ? SWITCH_DELAY_MS : OPEN_DELAY_MS
    if (openTimer.current) clearTimeout(openTimer.current)
    openTimer.current = setTimeout(show, delay)
  }
  const scheduleClose = () => {
    if (openTimer.current) { clearTimeout(openTimer.current); openTimer.current = null }
    if (pinned.current || !open) return
    if (closeTimer.current) clearTimeout(closeTimer.current)
    closeTimer.current = setTimeout(() => hide(false), CLOSE_DELAY_MS)
  }
  const onPanelEnter = () => {
    if (closeTimer.current) { clearTimeout(closeTimer.current); closeTimer.current = null }
  }

  // ---- Click / keyboard on the row ---------------------------------------
  const onTriggerClick = (e: React.MouseEvent) => {
    clearTimers()
    pinned.current = true
    // detail === 0: activated from the keyboard, so take focus into the panel.
    if (e.detail === 0) focusFirstOnOpen.current = true
    if (!open) show()
    else if (focusFirstOnOpen.current) focusItem(0)
  }
  const onTriggerKeyDown = (e: ReactKeyboardEvent) => {
    if (e.key === "ArrowRight") {
      e.preventDefault()
      clearTimers()
      pinned.current = true
      focusFirstOnOpen.current = true
      if (!open) show()
      else focusItem(0)
    }
  }

  // ---- Close on outside click and on Esc ---------------------------------
  useEffect(() => {
    if (!open) return
    const onDown = (e: MouseEvent) => {
      const t = e.target as Node
      if (triggerRef.current?.contains(t) || panelRef.current?.contains(t)) return
      hide(false)
    }
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== "Escape") return
      const focusWasInside = panelRef.current?.contains(document.activeElement) ||
        triggerRef.current === document.activeElement
      hide(!!focusWasInside)
    }
    document.addEventListener("mousedown", onDown)
    document.addEventListener("keydown", onKey)
    return () => {
      document.removeEventListener("mousedown", onDown)
      document.removeEventListener("keydown", onKey)
    }
  }, [open, hide])

  // ---- Positioning --------------------------------------------------------
  // The panel's width with all its columns side by side, measured once per
  // opening while it is laid out that way. Narrower space than this and the
  // groups stack into one scrolling column instead of being clipped.
  const fullWidth = useRef(0)

  const place = useCallback(() => {
    const trigger = triggerRef.current
    const panel = panelRef.current
    if (!trigger || !panel) return
    const r = trigger.getBoundingClientRect()
    const anchor = trigger.closest("[data-flyout-anchor]") as HTMLElement | null
    const left = (anchor ? anchor.getBoundingClientRect().right : r.right) + GAP_PX
    const vw = document.documentElement.clientWidth
    const vh = window.innerHeight
    const maxWidth = Math.max(220, vw - left - EDGE_PX)
    const maxHeight = vh - EDGE_PX * 2

    const body = bodyRef.current
    if (!pos.compact && body) fullWidth.current = body.scrollWidth + 2
    const compact = columns > 1 && fullWidth.current > maxWidth

    // Level with the row, then nudged up only as far as it must be to stay on
    // screen when the row is low -- never above the top edge.
    const height = Math.min(panel.offsetHeight, maxHeight)
    const top = Math.max(EDGE_PX, Math.min(r.top - 6, vh - height - EDGE_PX))
    const caret = Math.min(Math.max(r.top + r.height / 2 - top, 14), Math.max(14, height - 14))

    setPos((p) => (
      p.top === top && p.left === left && p.maxHeight === maxHeight &&
      p.maxWidth === maxWidth && p.caret === caret && p.compact === compact
        ? p
        : { top, left, maxHeight, maxWidth, caret, compact }
    ))
  }, [columns, pos.compact])

  // Every opening starts from the full layout, so it is measured afresh.
  useLayoutEffect(() => {
    if (open) { fullWidth.current = 0; setPos((p) => (p.compact ? { ...p, compact: false } : p)) }
  }, [open])
  // Measured before paint; settles in a pass or two, then setPos is a no-op.
  useLayoutEffect(() => { if (open && rendered) place() })

  // Follow the row while anything scrolls or the window resizes.
  useEffect(() => {
    if (!open) return
    const onMove = () => place()
    window.addEventListener("resize", onMove)
    window.addEventListener("scroll", onMove, true)
    return () => {
      window.removeEventListener("resize", onMove)
      window.removeEventListener("scroll", onMove, true)
    }
  }, [open, place])

  // ---- Focus inside the panel ----------------------------------------------
  const items = () =>
    Array.from(panelRef.current?.querySelectorAll<HTMLElement>("[data-flyout-item]") ?? [])
  const focusItem = (index: number) => {
    const list = items()
    if (list.length === 0) return
    list[(index + list.length) % list.length].focus()
  }
  useEffect(() => {
    if (open && focusFirstOnOpen.current) {
      focusFirstOnOpen.current = false
      // After the portal has painted.
      requestAnimationFrame(() => focusItem(0))
    }
  }, [open])

  const onPanelKeyDown = (e: ReactKeyboardEvent) => {
    const list = items()
    const i = list.indexOf(document.activeElement as HTMLElement)
    if (e.key === "ArrowDown") { e.preventDefault(); focusItem(i + 1) }
    else if (e.key === "ArrowUp") { e.preventDefault(); focusItem(i - 1) }
    else if (e.key === "Home") { e.preventDefault(); focusItem(0) }
    else if (e.key === "End") { e.preventDefault(); focusItem(list.length - 1) }
    else if (e.key === "ArrowLeft" || e.key === "Tab") { e.preventDefault(); hide(true) }
  }

  if (visibleGroups.length === 0) return null

  const showGroupLabels = visibleGroups.length > 1
  const cols = pos.compact ? 1 : Math.min(columns, visibleGroups.length)
  const choose = (after?: () => void) => {
    hide(false)
    after?.()
    onNavigate?.()
  }
  const caretInHeader = headerRef.current ? pos.caret < headerRef.current.offsetHeight : true

  return (
    <div onMouseEnter={onTriggerEnter} onMouseLeave={scheduleClose}>
      <button
        ref={triggerRef}
        type="button"
        onClick={onTriggerClick}
        onKeyDown={onTriggerKeyDown}
        aria-haspopup="true"
        aria-expanded={open}
        aria-controls={open ? panelId : undefined}
        aria-label={collapsed ? label : undefined}
        title={collapsed ? label : undefined}
        className={cn(
          // 12px with tighter padding, not text-sm: in Geist Medium "Sales,
          // Expenses & Money" is 168px at 14px but 144px at 12px, and the 240px
          // rail -- less Windows' ~11px scrollbar -- leaves it about 150px.
          "relative w-full flex items-center gap-2 rounded-md border-l-[3px] py-2.5 text-xs leading-5 font-medium transition-colors",
          "outline-none focus-visible:ring-2 focus-visible:ring-orange-400 focus-visible:ring-offset-2 focus-visible:ring-offset-slate-900",
          collapsed ? "justify-center px-2" : "pl-[10px] pr-1",
          // Open: the orange edge says "this is the section on screen beside you".
          open
            ? "bg-slate-800 text-white border-orange-400"
            : sectionActive
              ? "bg-slate-800/60 text-white border-transparent hover:bg-slate-800"
              : "text-slate-300 border-transparent hover:bg-slate-800 hover:text-white",
        )}
      >
        <Icon className={cn("shrink-0", collapsed ? "h-5 w-5" : "h-[18px] w-[18px]", open || sectionActive ? "text-orange-400" : "text-slate-400")} />
        {!collapsed && (
          <>
            {/* title=: a safety net if a longer label is ever added. */}
            <span className="truncate text-left" title={label}>{label}</span>
            <svg aria-hidden="true" viewBox="0 0 16 16"
              className={cn("ml-auto h-3 w-3 shrink-0 transition-transform duration-150",
                open ? "translate-x-0.5 text-orange-400" : "text-slate-500")}>
              <path d="M6 3l5 5-5 5" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </>
        )}
      </button>

      {rendered && mounted && createPortal(
        <div
          ref={panelRef}
          id={panelId}
          role="group"
          aria-label={title}
          data-state={open ? "open" : "closed"}
          onMouseEnter={onPanelEnter}
          onMouseLeave={scheduleClose}
          onKeyDown={onPanelKeyDown}
          style={{
            position: "fixed",
            top: pos.top,
            left: pos.left,
            maxWidth: pos.maxWidth,
            maxHeight: pos.maxHeight,
            width: pos.compact ? Math.min(pos.maxWidth, 320) : "max-content",
          }}
          className={cn(
            "z-[9999] flex min-w-[15rem] flex-col rounded-lg border shadow-xl shadow-black/40",
            a.panel,
            // transition-none: `duration-150` times the enter/exit animation, but
            // it also sets transition-duration, and with the default
            // transition-property of `all` the panel then SLID from wherever it
            // was first laid out to its measured spot -- straight across its
            // own row, which the browser reported as the pointer leaving.
            "transition-none duration-150 [animation-fill-mode:forwards] motion-reduce:animate-none",
            "data-[state=open]:animate-in data-[state=open]:fade-in-0 data-[state=open]:slide-in-from-left-1",
            "data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=closed]:slide-out-to-left-1",
          )}
        >
          {/* The notch that ties the panel to its row. */}
          <span aria-hidden="true"
            style={{ top: pos.caret - 5 }}
            className={cn("absolute -left-[6px] h-2.5 w-2.5 rotate-45 border-b border-l",
              caretInHeader ? "bg-slate-900 border-slate-700" : "bg-slate-800 border-slate-700")} />

          <div ref={headerRef}
            className={cn("flex shrink-0 items-start justify-between gap-4 rounded-t-lg border-b px-4 py-2.5", a.header)}>
            {/* min-w-full + w-0: the blurb wraps to the panel's width instead of
                setting it, so a long sentence cannot stretch a narrow menu. */}
            <div className="min-w-full w-0">
              <div className="flex items-baseline justify-between gap-4">
                <div className={cn("text-sm font-semibold", a.headerTitle)}>{title}</div>
                {viewAll && (
                  <Link href={viewAll.href} prefetch data-flyout-item
                    onClick={() => choose()}
                    className={cn("shrink-0 rounded text-xs font-medium hover:underline outline-none focus-visible:ring-2 focus-visible:ring-orange-400", a.link)}>
                    {viewAll.label}
                  </Link>
                )}
              </div>
              {blurb && <div className={cn("mt-0.5 text-xs leading-snug", a.headerBlurb)}>{blurb}</div>}
            </div>
          </div>

          <div
            ref={bodyRef}
            className="min-h-0 overflow-y-auto overflow-x-hidden overscroll-contain p-2.5"
            style={{
              display: "grid",
              gridTemplateColumns: cols === 1 ? "minmax(0, 1fr)" : `repeat(${cols}, max-content)`,
              columnGap: "0.75rem",
              rowGap: "0.75rem",
              alignItems: "start",
            }}
          >
            {visibleGroups.map((g) => (
              <div key={g.key} className={cn("min-w-0", cols > 1 && "max-w-[12.5rem]")}>
                {showGroupLabels && (
                  <div className={cn("px-2 pb-1 pt-0.5 text-[11px] font-semibold uppercase tracking-wider", a.groupLabel)}>
                    {g.label}
                  </div>
                )}
                <ul className="space-y-px">
                  {g.items.map((it) => {
                    const active = isRowActive(it) && highlightActiveRow
                    const RowIcon = it.icon
                    const rowClass = cn(
                      "flex w-full items-center gap-2.5 rounded-md px-2 py-1.5 text-left text-[13px] leading-5 transition-colors",
                      "outline-none focus-visible:ring-2 focus-visible:ring-orange-400",
                      active ? cn(a.rowActive, "font-medium") : a.rowIdle,
                    )
                    const inner: ReactNode = (
                      <>
                        <RowIcon className={cn("h-4 w-4 shrink-0", active ? a.iconActive : a.iconIdle)} />
                        <span className="min-w-0 break-words">{it.title}</span>
                        {typeof it.badge === "number" && it.badge > 0 && (
                          <span className="ml-auto inline-flex h-5 min-w-[20px] items-center justify-center rounded-full bg-red-500 px-1.5 text-[10px] font-bold text-white">
                            {it.badge > 99 ? "99+" : it.badge}
                          </span>
                        )}
                      </>
                    )
                    return (
                      <li key={it.id}>
                        {it.onClick ? (
                          <button type="button" data-flyout-item className={rowClass}
                            onClick={() => choose(it.onClick)}>
                            {inner}
                          </button>
                        ) : (
                          <Link href={it.href!} prefetch data-flyout-item className={rowClass}
                            aria-current={isRowActive(it) ? "page" : undefined}
                            onClick={() => choose()}>
                            {inner}
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
