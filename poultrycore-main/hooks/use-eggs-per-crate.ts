"use client"

// The active farm's eggs per crate (migration 344). Loaded once per farm by
// EggsPerCrateLoader (mounted in the dashboard header) and cached per farm in
// localStorage so a reload starts with the right number; every screen that
// converts crates <-> eggs reads it through useEggsPerCrate() so it re-renders
// when the setting arrives or changes.

import { useEffect, useSyncExternalStore } from "react"
import { useAuthStore } from "@/lib/store/auth-store"
import { getEggSortingSettings } from "@/lib/api/egg-sorting"
import { getEggsPerCrate, setEggsPerCrate, subscribeEggsPerCrate } from "@/lib/production/production-record-calc"

const cacheKey = (farmId: string) => `eggsPerCrate:${farmId}`

export function useEggsPerCrate(): number {
  return useSyncExternalStore(subscribeEggsPerCrate, getEggsPerCrate, () => 30)
}

/** Applies a freshly saved value right away (Sizes & settings). */
export function applyEggsPerCrate(farmId: string | null | undefined, n: number) {
  setEggsPerCrate(n)
  try { if (farmId) localStorage.setItem(cacheKey(farmId), String(n)) } catch { /* storage unavailable */ }
}

export function EggsPerCrateLoader() {
  const farmId = useAuthStore((s) => s.activeFarmId)
  const farmType = useAuthStore((s) => s.activeFarmType)
  useEffect(() => {
    if (!farmId || (farmType && farmType !== "Poultry")) return
    try {
      const cached = Number(localStorage.getItem(cacheKey(farmId)))
      setEggsPerCrate(Number.isInteger(cached) && cached > 0 ? cached : 30)
    } catch { setEggsPerCrate(30) }
    let cancelled = false
    getEggSortingSettings()
      .then((s) => { if (!cancelled) applyEggsPerCrate(farmId, s.eggsPerCrate || 30) })
      .catch(() => { /* before 344 or offline: keep the cached / default value */ })
    return () => { cancelled = true }
  }, [farmId, farmType])
  return null
}
