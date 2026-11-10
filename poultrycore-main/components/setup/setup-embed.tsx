"use client"

// Lets one setup view render in two places: its own standalone route, and a
// tab inside the consolidated Farm Setup page (/poultry-setup).
//
// The views under components/setup-views/ are the full standalone pages moved
// out of app/. Each reads useSetupEmbedded() and, when embedded:
//   * drops its page shell (sidebar, header, the scrolling <main> padding),
//   * hides its own title block (Farm Setup shows one line instead),
//   * hands its buttons to Farm Setup's task bar via <SetupTaskBar>,
//   * moves its search / view switches beside the tab's description line via
//     <SetupTabTools>.
// Everything else (lists, dialogs, filters, validation, API calls) is the same
// code in both places, so the two can never drift apart.

import { createContext, useContext, useEffect, useLayoutEffect, useRef, type ReactNode } from "react"
import { createPortal } from "react-dom"
import { TaskBarRow, type SetupTask } from "@/components/setup/setup-task-bar"

export type { SetupTask } from "@/components/setup/setup-task-bar"

type SetupEmbedValue = {
  /** Registers (or, with null, removes) one view's tasks on the task bar. */
  setTasks: (owner: string, tasks: SetupTask[] | null) => void
  /** Reports unsaved edits so tab / section changes can ask first. */
  setDirty: (key: string, dirty: boolean) => void
  /** The slot beside the description line; null until it mounts. */
  toolsEl: HTMLElement | null
}

const SetupEmbedContext = createContext<SetupEmbedValue | null>(null)

/** Hands each mounted <SetupTaskBar> its own owner key. */
let taskOwnerSeq = 0

export function SetupEmbedProvider({ value, children }: { value: SetupEmbedValue; children: React.ReactNode }) {
  return <SetupEmbedContext.Provider value={value}>{children}</SetupEmbedContext.Provider>
}

/** True when the view is rendered inside the Farm Setup page. */
export function useSetupEmbedded(): boolean {
  return useContext(SetupEmbedContext) !== null
}

/**
 * The view's buttons, as data. Standalone: drawn in place. Embedded: shown on
 * Farm Setup's task bar, which updates whenever the list changes (a task is
 * added, hidden, disabled or relabelled).
 */
export function SetupTaskBar({ tasks, className }: { tasks: SetupTask[]; className?: string }) {
  const ctx = useContext(SetupEmbedContext)
  // One owner per mounted instance. Not useId: that follows the tree position,
  // so a remounted view (Reload, company switch) got the old one's id and the
  // old one's late cleanup wiped the new buttons off the bar.
  const ownerRef = useRef<string | null>(null)
  if (ownerRef.current === null) ownerRef.current = `tasks-${++taskOwnerSeq}`
  const owner = ownerRef.current
  const setTasks = ctx?.setTasks

  // Handlers change every render; the bar calls the latest one through this
  // ref, so only a visible change (the signature) re-publishes the list.
  const latest = useRef(tasks)
  latest.current = tasks
  const signature = JSON.stringify(tasks.map(({ onClick, icon, ...rest }) => [rest, !!onClick, icon?.displayName ?? icon?.name ?? ""]))

  // Register and unregister in one (layout) effect: every cleanup is paired with
  // the registration it undoes, and the buttons land on the bar in the same
  // paint as the view instead of after its deferred effects.
  useLayoutEffect(() => {
    if (!setTasks) return
    setTasks(owner, latest.current.map((t) => ({
      ...t,
      onClick: t.onClick ? () => latest.current.find((x) => x.id === t.id)?.onClick?.() : undefined,
    })))
    return () => setTasks(owner, null)
  }, [setTasks, owner, signature])

  if (ctx) return null
  return <TaskBarRow tasks={tasks} align="end" className={className ?? "w-full min-w-0 sm:w-auto sm:min-w-[12rem] sm:flex-1"} />
}

/**
 * The view's list tools (search, counts, view switch). Standalone: rendered in
 * place, inside `standaloneClassName`. Embedded: moved beside the tab's
 * description line, so they take no row of their own.
 */
export function SetupTabTools({ children, standaloneClassName }: { children: ReactNode; standaloneClassName?: string }) {
  const ctx = useContext(SetupEmbedContext)
  if (!ctx) return <div className={standaloneClassName}>{children}</div>
  if (!ctx.toolsEl) return null
  return createPortal(children, ctx.toolsEl)
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
  // Per instance, like SetupTaskBar's owner: a remounted view must not share
  // the old one's key.
  const keyRef = useRef<string | null>(null)
  if (keyRef.current === null) keyRef.current = `dirty-${++taskOwnerSeq}`
  const key = keyRef.current
  const setDirty = ctx?.setDirty
  useEffect(() => {
    if (!setDirty) return
    setDirty(key, dirty)
    return () => setDirty(key, false)
  }, [setDirty, key, dirty])
}
