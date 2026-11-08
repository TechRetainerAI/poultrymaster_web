"use client"

// Lets one setup view render in two places: its own standalone route, and a
// tab inside the consolidated Farm Setup page (/poultry-setup).
//
// The views under components/setup-views/ are the full standalone pages moved
// out of app/. Each reads useSetupEmbedded() and, when embedded:
//   * drops its page shell (sidebar, header, the scrolling <main> padding),
//   * hides its own title block (Farm Setup shows one line instead),
//   * sends its primary actions to the tab's action slot via <SetupTabActions>.
// Everything else (lists, dialogs, filters, validation, API calls) is the same
// code in both places, so the two can never drift apart.

import { createContext, useContext, useEffect, useId, type ReactNode } from "react"
import { createPortal } from "react-dom"

type SetupEmbedValue = {
  /** Where <SetupTabActions> renders its buttons; null until the slot mounts. */
  actionsEl: HTMLElement | null
  /** Reports unsaved edits so tab / section changes can ask first. */
  setDirty: (key: string, dirty: boolean) => void
}

const SetupEmbedContext = createContext<SetupEmbedValue | null>(null)

export function SetupEmbedProvider({ value, children }: { value: SetupEmbedValue; children: ReactNode }) {
  return <SetupEmbedContext.Provider value={value}>{children}</SetupEmbedContext.Provider>
}

/** True when the view is rendered inside the Farm Setup page. */
export function useSetupEmbedded(): boolean {
  return useContext(SetupEmbedContext) !== null
}

/**
 * The view's primary actions. Standalone: rendered in place. Embedded: moved
 * beside the tab's description line, so the buttons keep working exactly as
 * they do on the standalone page.
 */
export function SetupTabActions({ children }: { children: ReactNode }) {
  const ctx = useContext(SetupEmbedContext)
  if (!ctx) return <>{children}</>
  if (!ctx.actionsEl) return null
  return createPortal(children, ctx.actionsEl)
}

/** Page-shell class: the standalone value, or a plain block when embedded. */
export function shellClass(embedded: boolean, standalone: string): string {
  return embedded ? "min-w-0" : standalone
}

/**
 * Tells Farm Setup that this view holds unsaved edits, so switching tab or
 * section asks first. A no-op on the standalone page.
 */
export function useSetupDirty(dirty: boolean) {
  const ctx = useContext(SetupEmbedContext)
  const key = useId()
  const setDirty = ctx?.setDirty
  useEffect(() => {
    if (!setDirty) return
    setDirty(key, dirty)
    return () => setDirty(key, false)
  }, [setDirty, key, dirty])
}
