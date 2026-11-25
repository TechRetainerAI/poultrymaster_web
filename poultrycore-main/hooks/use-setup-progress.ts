"use client"

/**
 * What the active poultry company already has, for the Setup Guide's
 * "Set up a new farm" path (lib/help/setup-path.ts).
 *
 * Plain GETs on purpose: some list helpers (getCustomers) hand back MOCK data
 * when the call fails, which would tick a step the farm never did. Here a
 * failed call is `undefined` -- "could not check" -- never a number.
 *
 * Manual ticks are a per-person convenience, kept in this browser per company;
 * losing them (private window, cleared storage) only un-ticks the list.
 */

import { useCallback, useEffect, useState } from "react"
import { farmApiUrl, getAuthHeaders, getUserContext } from "@/lib/api/config"
import type { SetupCheck } from "@/lib/help/setup-path"

const ENDPOINTS: Record<SetupCheck, (farmId: string, userId: string) => string> = {
  houses: (f, u) => `/House?userId=${u}&farmId=${f}`,
  batches: (f, u) => `/MainFlockBatch?userId=${u}&farmId=${f}`,
  flocks: (f, u) => `/Flock?userId=${u}&farmId=${f}`,
  cashAccounts: (f) => `/Poultry/cash-accounts?farmId=${f}`,
  supplyItems: (f) => `/Poultry/raw-material-items?farmId=${f}`,
  customers: (f, u) => `/Customer?userId=${u}&farmId=${f}`,
  suppliers: (f, u) => `/Supplier?userId=${u}&farmId=${f}`,
  production: (f, u) => `/ProductionRecord?userId=${u}&farmId=${f}`,
  sales: (f, u) => `/Sale?userId=${u}&farmId=${f}`,
}

/** The number of rows in a list response, whether bare or wrapped in { data }. */
function rows(body: unknown): number | undefined {
  if (Array.isArray(body)) return body.length
  const data = (body as { data?: unknown; Data?: unknown } | null)?.data ?? (body as { Data?: unknown } | null)?.Data
  return Array.isArray(data) ? data.length : undefined
}

async function countOf(path: string): Promise<number | undefined> {
  try {
    const res = await fetch(farmApiUrl(path), { headers: getAuthHeaders() })
    if (!res.ok) return undefined
    return rows(await res.json())
  } catch {
    return undefined
  }
}

const tickKey = (farmId: string) => `setup-path-ticks:${farmId}`

function readTicks(farmId: string): Set<string> {
  try {
    const raw = localStorage.getItem(tickKey(farmId))
    const list = raw ? JSON.parse(raw) : []
    return new Set(Array.isArray(list) ? list.filter((x): x is string => typeof x === "string") : [])
  } catch {
    return new Set()
  }
}

export function useSetupProgress(enabled: boolean) {
  const [counts, setCounts] = useState<Partial<Record<SetupCheck, number | undefined>>>({})
  const [loading, setLoading] = useState(enabled)
  const [ticked, setTicked] = useState<Set<string>>(new Set())
  const [farmId, setFarmId] = useState("")

  const load = useCallback(async () => {
    const { farmId: f, userId } = getUserContext()
    setFarmId(f || "")
    setTicked(f ? readTicks(f) : new Set())
    if (!f) { setLoading(false); return }
    setLoading(true)
    const fid = encodeURIComponent(f)
    const uid = encodeURIComponent(userId || "")
    const keys = Object.keys(ENDPOINTS) as SetupCheck[]
    const values = await Promise.all(keys.map((k) => countOf(ENDPOINTS[k](fid, uid))))
    setCounts(Object.fromEntries(keys.map((k, i) => [k, values[i]])))
    setLoading(false)
  }, [])

  useEffect(() => {
    if (enabled) void load()
  }, [enabled, load])

  const toggleTick = useCallback((stepId: string) => {
    setTicked((prev) => {
      const next = new Set(prev)
      if (!next.delete(stepId)) next.add(stepId)
      try { if (farmId) localStorage.setItem(tickKey(farmId), JSON.stringify([...next])) } catch { /* only this browser's convenience */ }
      return next
    })
  }, [farmId])

  return { counts, ticked, toggleTick, loading, reload: load }
}
