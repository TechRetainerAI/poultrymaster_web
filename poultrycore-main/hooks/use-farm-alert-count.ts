"use client"

// What the Farm Alerts page cards show, as numbers -- for the bell's badge and
// the page's summary tiles:
//   production still missing today (flocks) + earlier days missing (flock-days)
//   + earlier days with eggs still unsorted
//   + active flock alerts
//   + stock items that need action soon.
// Each source fails on its own: a missing permission or an unapplied migration
// marks that part unknown (null) and contributes 0 to the total. Cached per farm
// for a minute so moving between pages does not fire three requests each time;
// refreshed when the tab regains focus or when asked.

import { useCallback, useEffect, useState } from "react"
import { useAuthStore } from "@/lib/store/auth-store"
import { getActivityChecks } from "@/lib/api/activity-checks"
import { getFlockAlerts } from "@/lib/api/flock-alerts"
import { getStockSupply } from "@/lib/api/stock-supply"
import { isActionable } from "@/lib/inventory/days-of-supply"
import { PRODUCTION_CHECK_KEY, findCheck } from "@/lib/activity/completeness"

export interface FarmAlertBreakdown {
  /** Flocks missing production today; null = not available. */
  productionToday: number | null
  /** Missing flock-days on earlier dates. */
  productionEarlier: number | null
  /** Flocks expected to report today / recorded. */
  productionExpected: number | null
  productionRecorded: number | null
  /** Earlier production days with eggs still unsorted; null = sorting off / not available. */
  unsortedDays: number | null
  unsortedEggs: number | null
  flockAlerts: number | null
  stockActionable: number | null
  total: number
  loadedAt: number
}

const TTL_MS = 60_000
const cache = new Map<string, FarmAlertBreakdown>()
const inflight = new Map<string, Promise<FarmAlertBreakdown>>()
const listeners = new Set<() => void>()

async function fetchBreakdown(farmId: string): Promise<FarmAlertBreakdown> {
  const [checks, alerts, supply] = await Promise.allSettled([
    getActivityChecks(),
    getFlockAlerts({ status: "active" }),
    getStockSupply(),
  ])
  const b: FarmAlertBreakdown = {
    productionToday: null, productionEarlier: null, productionExpected: null, productionRecorded: null,
    unsortedDays: null, unsortedEggs: null, flockAlerts: null, stockActionable: null, total: 0, loadedAt: Date.now(),
  }
  if (checks.status === "fulfilled") {
    const production = findCheck(checks.value, PRODUCTION_CHECK_KEY)
    if (production && production.status !== "NotApplicable") {
      b.productionToday = production.outstandingCount ?? 0
      b.productionEarlier = production.counters?.backlogFlockDays ?? 0
      b.productionExpected = production.expectedCount ?? null
      b.productionRecorded = production.completedCount ?? null
    }
    const unsorted = findCheck(checks.value, "poultry.eggs.unsorted")
    if (unsorted && unsorted.status !== "NotApplicable") {
      b.unsortedDays = unsorted.outstandingCount ?? 0
      b.unsortedEggs = unsorted.counters?.eggs ?? 0
    }
  }
  if (alerts.status === "fulfilled" && Array.isArray(alerts.value)) b.flockAlerts = alerts.value.length
  if (supply.status === "fulfilled" && Array.isArray(supply.value)) b.stockActionable = supply.value.filter((r) => isActionable(r.status)).length
  b.total = (b.productionToday ?? 0) + (b.productionEarlier ?? 0) + (b.unsortedDays ?? 0) + (b.flockAlerts ?? 0) + (b.stockActionable ?? 0)
  cache.set(farmId, b)
  for (const l of listeners) l()
  return b
}

function load(farmId: string, force: boolean): Promise<FarmAlertBreakdown> {
  const hit = cache.get(farmId)
  if (!force && hit && Date.now() - hit.loadedAt < TTL_MS) return Promise.resolve(hit)
  const running = inflight.get(farmId)
  if (running) return running
  const p = fetchBreakdown(farmId).finally(() => inflight.delete(farmId))
  inflight.set(farmId, p)
  return p
}

/** Breakdown + a refresh that forces a re-read. null while loading / not poultry. */
export function useFarmAlertBreakdown(): { data: FarmAlertBreakdown | null; refresh: () => Promise<void> } {
  const farmId = useAuthStore((s) => s.activeFarmId)
  const farmType = useAuthStore((s) => s.activeFarmType)
  const [data, setData] = useState<FarmAlertBreakdown | null>(() => (farmId ? cache.get(farmId) ?? null : null))

  useEffect(() => {
    if (!farmId || farmType !== "Poultry") { setData(null); return }
    let cancelled = false
    const sync = () => { if (!cancelled) setData(cache.get(farmId) ?? null) }
    listeners.add(sync)
    void load(farmId, false).then(sync).catch(() => { /* keep what is shown */ })
    const onVisible = () => { if (document.visibilityState === "visible") void load(farmId, true).catch(() => {}) }
    document.addEventListener("visibilitychange", onVisible)
    return () => { cancelled = true; listeners.delete(sync); document.removeEventListener("visibilitychange", onVisible) }
  }, [farmId, farmType])

  const refresh = useCallback(async () => {
    if (!farmId || farmType !== "Poultry") return
    try { await load(farmId, true) } catch { /* keep what is shown */ }
  }, [farmId, farmType])

  return { data, refresh }
}

/** The bell's number. null while unknown (or not a poultry company). */
export function useFarmAlertCount(): number | null {
  return useFarmAlertBreakdown().data?.total ?? null
}
