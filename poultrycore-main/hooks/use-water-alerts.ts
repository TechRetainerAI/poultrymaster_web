"use client"

// Water Alerts (465) for the header bell and the /water-alerts page. Cached per
// company for a minute so moving between pages does not refetch; refreshed when
// the tab regains focus or when asked. Returns null for a non-Water company,
// so the header can call it unconditionally (rules of hooks).

import { useCallback, useEffect, useState } from "react"
import { useAuthStore } from "@/lib/store/auth-store"
import { getWaterAlerts, waterAlertBellCount, type WaterAlert } from "@/lib/api/water-alerts"

const TTL_MS = 60_000
const cache = new Map<string, { rows: WaterAlert[]; at: number }>()
const inflight = new Map<string, Promise<WaterAlert[]>>()
const listeners = new Set<() => void>()

function load(farmId: string, force: boolean): Promise<WaterAlert[]> {
  const hit = cache.get(farmId)
  if (!force && hit && Date.now() - hit.at < TTL_MS) return Promise.resolve(hit.rows)
  const running = inflight.get(farmId)
  if (running) return running
  const p = getWaterAlerts(farmId)
    .then((rows) => { cache.set(farmId, { rows, at: Date.now() }); for (const l of listeners) l(); return rows })
    .finally(() => inflight.delete(farmId))
  inflight.set(farmId, p)
  return p
}

export function useWaterAlerts(): { rows: WaterAlert[] | null; error: string | null; refresh: () => Promise<void> } {
  const farmId = useAuthStore((s) => s.activeFarmId)
  const farmType = useAuthStore((s) => s.activeFarmType)
  const isWater = farmType === "Water"
  const [rows, setRows] = useState<WaterAlert[] | null>(() => (farmId && isWater ? cache.get(farmId)?.rows ?? null : null))
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!farmId || !isWater) { setRows(null); return }
    let cancelled = false
    const sync = () => { if (!cancelled) setRows(cache.get(farmId)?.rows ?? null) }
    listeners.add(sync)
    load(farmId, false).then(() => { sync(); setError(null) }).catch((e) => { if (!cancelled) setError(e?.message ?? String(e)) })
    const onVisible = () => { if (document.visibilityState === "visible") void load(farmId, true).catch(() => {}) }
    document.addEventListener("visibilitychange", onVisible)
    return () => { cancelled = true; listeners.delete(sync); document.removeEventListener("visibilitychange", onVisible) }
  }, [farmId, isWater])

  const refresh = useCallback(async () => {
    if (!farmId || !isWater) return
    try { await load(farmId, true); setError(null) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [farmId, isWater])

  return { rows, error, refresh }
}

/** The bell's number for a Water company; null when unknown or not Water. */
export function useWaterAlertCount(): number | null {
  const { rows } = useWaterAlerts()
  return rows ? waterAlertBellCount(rows) : null
}
