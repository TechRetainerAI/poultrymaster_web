"use client"

/**
 * Open/close + positioning behaviour shared by every top-nav panel.
 *
 * This block used to be copy-pasted three times in top-nav.tsx (NavDropdown and
 * the two Reports mega-menus), differing only in the close delay and whether a
 * left-clamp was applied. Extracted so the mega-menu can parameterise the clamp
 * by its own width — a fixed 896px clamp is wrong for anything narrower.
 *
 * Panels are portalled into <body> because the nav rail sets `overflow-x: auto`
 * (globals.css .nav-rail-scroll), which would otherwise clip them.
 */

import { useCallback, useEffect, useRef, useState } from "react"

/** Shared trigger-button classes. Layout and the active state are the same on
 *  every bar; the idle state is per-company and lives in NAV_SURFACE
 *  (`triggerIdle` / `triggerIcon`), since it has to sit on a sky, orange or
 *  emerald bar. bg-white/25 works on all three. */
export const NAV_TRIGGER_CLASS =
  "flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-md transition-colors whitespace-nowrap"
export const NAV_TRIGGER_ACTIVE = "bg-white/25 text-white font-semibold"

export interface UseNavPopoverOptions {
  /** Grace period after the pointer leaves, so the user can travel diagonally
   *  from the trigger into the panel. */
  closeDelayMs?: number
  /** Panel width in px. When set, the panel is clamped so it can't run off the
   *  right edge. Omit to pin it flush to the trigger's left edge. */
  menuWidthPx?: number
}

export function useNavPopover({ closeDelayMs = 150, menuWidthPx }: UseNavPopoverOptions = {}) {
  const [open, setOpen] = useState(false)
  const [mounted, setMounted] = useState(false)
  const [position, setPosition] = useState({ top: 0, left: 0 })
  const triggerRef = useRef<HTMLDivElement>(null)
  const menuRef = useRef<HTMLDivElement>(null)
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  // createPortal needs a client-side document; `mounted` keeps the server render
  // and the first client render identical (trigger only, no panel).
  useEffect(() => { setMounted(true) }, [])

  // All three original copies leaked this timer on unmount.
  useEffect(() => () => { if (timeoutRef.current) clearTimeout(timeoutRef.current) }, [])

  const updatePosition = useCallback(() => {
    const el = triggerRef.current
    if (!el) return
    const rect = el.getBoundingClientRect()
    let left = rect.left
    if (menuWidthPx) {
      // clientWidth, not innerWidth — innerWidth counts the scrollbar gutter.
      const viewport = document.documentElement.clientWidth
      left = Math.min(left, Math.max(8, viewport - menuWidthPx - 16))
    }
    setPosition({ top: rect.bottom + 4, left })
  }, [menuWidthPx])

  const handleMouseEnter = useCallback(() => {
    if (timeoutRef.current) clearTimeout(timeoutRef.current)
    updatePosition()
    setOpen(true)
  }, [updatePosition])

  const handleMouseLeave = useCallback(() => {
    timeoutRef.current = setTimeout(() => setOpen(false), closeDelayMs)
  }, [closeDelayMs])

  const close = useCallback(() => {
    if (timeoutRef.current) clearTimeout(timeoutRef.current)
    setOpen(false)
  }, [])

  const toggle = useCallback(() => {
    updatePosition()
    setOpen((o) => !o)
  }, [updatePosition])

  useEffect(() => {
    if (!open) return
    const handleClickOutside = (e: MouseEvent) => {
      const t = e.target as Node
      if (
        triggerRef.current && !triggerRef.current.contains(t) &&
        (!menuRef.current || !menuRef.current.contains(t))
      ) setOpen(false)
    }
    document.addEventListener("mousedown", handleClickOutside)
    return () => document.removeEventListener("mousedown", handleClickOutside)
  }, [open])

  return {
    open, mounted, position,
    triggerRef, menuRef,
    handleMouseEnter, handleMouseLeave,
    toggle, close, updatePosition,
  }
}
