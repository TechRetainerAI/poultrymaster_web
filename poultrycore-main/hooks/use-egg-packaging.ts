"use client"

// The active farm's egg packaging (migration 393): Boxes of N crates.
// Loaded once per farm by EggPackagingLoader (mounted next to
// EggsPerCrateLoader in the dashboard header) and cached per farm in
// localStorage so a reload starts with the right boxes. Eggs per crate is NOT
// stored here: it always comes from the 344 setting (useEggsPerCrate), so the
// two can never disagree.
//
// Switching company resets to "boxes off" before the new farm's answer
// arrives, so one company's box size is never shown for another.

import { useEffect, useMemo, useSyncExternalStore } from "react"
import { useAuthStore } from "@/lib/store/auth-store"
import { getEggPackaging, type EggPackagingSettings } from "@/lib/api/egg-sorting"
import { useEggsPerCrate } from "@/hooks/use-eggs-per-crate"
import { getEggsPerCrate } from "@/lib/production/production-record-calc"
import { DEFAULT_EGG_PACKAGING, type EggPackaging } from "@/lib/poultry/egg-packaging"

type BoxConfig = Omit<EggPackaging, "eggsPerCrate" | "eggsPerBox"> & { farmId: string | null }

const OFF: BoxConfig = {
  farmId: null,
  enableBoxes: false,
  cratesPerBox: null,
  display: "CratesPieces",
  saleEntryUnit: "Crates",
  version: 1,
}

let current: BoxConfig = OFF
const listeners = new Set<() => void>()
const subscribe = (l: () => void) => { listeners.add(l); return () => { listeners.delete(l) } }
const getSnapshot = () => current
const setConfig = (next: BoxConfig) => { current = next; for (const l of listeners) l() }

const cacheKey = (farmId: string) => `eggPackaging:${farmId}`

const fromApi = (farmId: string, s: EggPackagingSettings): BoxConfig => ({
  farmId,
  enableBoxes: !!s.enableBoxes && (s.cratesPerBox ?? 0) >= 1,
  cratesPerBox: s.cratesPerBox ?? null,
  display: s.eggDisplay ?? "CratesPieces",
  saleEntryUnit: s.saleEntryUnit ?? "Crates",
  version: s.packagingVersion ?? 1,
})

/** Applies a freshly saved configuration right away (settings screen). */
export function applyEggPackaging(farmId: string | null | undefined, s: EggPackagingSettings) {
  if (!farmId) return
  const next = fromApi(farmId, s)
  setConfig(next)
  try { localStorage.setItem(cacheKey(farmId), JSON.stringify(next)) } catch { /* storage unavailable */ }
}

/** Builds the packaging a farm uses from the stored box config and the live crate size. */
function compose(cfg: BoxConfig, farmId: string | null | undefined, eggsPerCrate: number): EggPackaging {
  // A config for another company (the switch has not reloaded yet) is not used.
  const c = cfg.farmId && cfg.farmId === farmId ? cfg : OFF
  const on = c.enableBoxes && (c.cratesPerBox ?? 0) >= 1
  return {
    ...DEFAULT_EGG_PACKAGING,
    eggsPerCrate,
    enableBoxes: on,
    cratesPerBox: on ? c.cratesPerBox : null,
    eggsPerBox: on ? (c.cratesPerBox as number) * eggsPerCrate : null,
    display: c.display === "BoxesCratesPieces" && !on ? "CratesPieces" : c.display,
    saleEntryUnit: on ? c.saleEntryUnit : "Crates",
    version: c.version,
  }
}

/**
 * The active farm's packaging right now, for code outside React (sale-line
 * helpers) -- the same live-binding idea as EGGS_PER_CRATE. Components should
 * call useEggPackaging() so they re-render when it changes.
 */
export function getEggPackagingNow(): EggPackaging {
  return compose(current, useAuthStore.getState().activeFarmId, getEggsPerCrate())
}

/** The active farm's packaging, re-rendering when it (or the crate size) changes. */
export function useEggPackaging(): EggPackaging {
  const cfg = useSyncExternalStore(subscribe, getSnapshot, () => OFF)
  const farmId = useAuthStore((s) => s.activeFarmId)
  const eggsPerCrate = useEggsPerCrate()
  return useMemo(() => compose(cfg, farmId, eggsPerCrate), [cfg, farmId, eggsPerCrate])
}

export function EggPackagingLoader() {
  const farmId = useAuthStore((s) => s.activeFarmId)
  const farmType = useAuthStore((s) => s.activeFarmType)
  useEffect(() => {
    if (!farmId || (farmType && farmType !== "Poultry")) { setConfig(OFF); return }
    let cached: BoxConfig = { ...OFF, farmId }
    try {
      const raw = localStorage.getItem(cacheKey(farmId))
      if (raw) {
        const parsed = JSON.parse(raw) as BoxConfig
        if (parsed && parsed.farmId === farmId) cached = parsed
      }
    } catch { /* storage unavailable or corrupt: boxes off until the API answers */ }
    setConfig(cached)
    let cancelled = false
    getEggPackaging()
      .then((s) => { if (!cancelled) applyEggPackaging(farmId, s) })
      .catch(() => { /* before 393 or offline: keep the cached / off value */ })
    return () => { cancelled = true }
  }, [farmId, farmType])
  return null
}
