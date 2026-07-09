"use client"

// Reusable page view-mode preference (James 2026-07-08).
// A page can render its data as a TABLE (default) or as SCORECARDS, and when in
// scorecards it can group them under TABS. "Always show as scorecards" and
// "Show as tabs" are ONE global preference for this device (localStorage); the
// per-visit "View as scorecards" toggle starts from that global default.
import { useCallback, useEffect, useState } from "react"

const ALWAYS_KEY = "vc.view.alwaysScorecards"
const TABS_KEY = "vc.view.asTabs"

function readBool(key: string): boolean {
  if (typeof window === "undefined") return false
  try { return window.localStorage.getItem(key) === "1" } catch { return false }
}
function writeBool(key: string, val: boolean) {
  if (typeof window === "undefined") return
  try { window.localStorage.setItem(key, val ? "1" : "0") } catch { /* ignore */ }
}

export type ViewMode = "table" | "scorecards"

export function useViewMode() {
  // Global (persisted) prefs.
  const [alwaysScorecards, setAlwaysState] = useState(false)
  const [asTabs, setAsTabsState] = useState(false)
  // Session view for this page visit; seeded from the global default on mount.
  const [scorecards, setScorecards] = useState(false)
  const [ready, setReady] = useState(false)

  useEffect(() => {
    const a = readBool(ALWAYS_KEY)
    setAlwaysState(a); setAsTabsState(readBool(TABS_KEY)); setScorecards(a); setReady(true)
  }, [])

  const setAlwaysScorecards = useCallback((val: boolean) => {
    setAlwaysState(val); writeBool(ALWAYS_KEY, val); setScorecards(val)
  }, [])
  const setAsTabs = useCallback((val: boolean) => {
    setAsTabsState(val); writeBool(TABS_KEY, val)
  }, [])

  const mode: ViewMode = scorecards ? "scorecards" : "table"
  return { ready, mode, scorecards, setScorecards, alwaysScorecards, setAlwaysScorecards, asTabs, setAsTabs }
}
