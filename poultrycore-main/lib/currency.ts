/**
 * Currency helper — Prompt 2 §15.
 *
 * The Water Company setup page stores three fields on the Farms row:
 *   currencyCode   — ISO-ish code (GHS, USD, ...)
 *   currencySymbol — display prefix (GHC, ₵, $, ...)
 *   showCurrencySymbol — when false the helper renders the number only
 *
 * Pages call `fmtMoney(n)` instead of hardcoding `GHC ${n.toFixed(2)}`. The
 * settings live in a Zustand store so a single fetch on app boot lights up
 * every page — no prop drilling, no per-page fetches.
 */

"use client"

import { create } from "zustand"
import { persist } from "zustand/middleware"
import { farmApiUrl, getAuthHeaders, getUserContext } from "@/lib/api/config"

export interface FarmSettings {
  farmId: string
  currencyCode: string
  currencySymbol: string
  showCurrencySymbol: boolean
}

interface FarmSettingsState {
  settings: FarmSettings | null
  loading: boolean
  load: (force?: boolean) => Promise<void>
  set: (s: Partial<FarmSettings>) => void
  // For pages that change currency settings, call this after a successful PUT.
  apply: (s: FarmSettings) => void
}

const DEFAULTS: FarmSettings = {
  farmId: "",
  currencyCode: "GHS",
  currencySymbol: "GHC",
  showCurrencySymbol: true,
}

export const useFarmSettingsStore = create<FarmSettingsState>()(
  persist(
    (set, get) => ({
      settings: null,
      loading: false,
      async load(force = false) {
        const ctx = getUserContext()
        if (!ctx?.farmId) return
        const cur = get().settings
        // Only reload if the active farm changed, or caller forced it.
        if (!force && cur && cur.farmId === ctx.farmId) return
        set({ loading: true })
        try {
          const url = farmApiUrl(`/Water/farm-settings?farmId=${encodeURIComponent(ctx.farmId)}`)
          const r = await fetch(url, { headers: getAuthHeaders(), credentials: "include" })
          if (!r.ok) return
          const j = await r.json()
          set({
            settings: {
              farmId: j.farmId ?? ctx.farmId,
              currencyCode: j.currencyCode ?? DEFAULTS.currencyCode,
              currencySymbol: j.currencySymbol ?? DEFAULTS.currencySymbol,
              showCurrencySymbol: !!j.showCurrencySymbol,
            },
          })
        } catch {
          // Silent: pages fall back to defaults via fmtMoney() below.
        } finally {
          set({ loading: false })
        }
      },
      set(patch) {
        const cur = get().settings ?? DEFAULTS
        set({ settings: { ...cur, ...patch } })
      },
      apply(s) {
        set({ settings: s })
      },
    }),
    { name: "farm-settings-storage" },
  ),
)

// ---------------------------------------------------------------------------
// Vanilla helpers — usable outside React (e.g. PDF generation later).
// ---------------------------------------------------------------------------

function currentSettings(): FarmSettings {
  if (typeof window === "undefined") return DEFAULTS
  return useFarmSettingsStore.getState().settings ?? DEFAULTS
}

/**
 * fmtMoney(amount) → "GHC 1,234.50" or "1,234.50" depending on showCurrencySymbol.
 * Safe to call from anywhere (server components fall back to defaults).
 */
export function fmtMoney(n: number | null | undefined, opts?: { showSymbol?: boolean }) {
  const v = n ?? 0
  const s = currentSettings()
  const formatted = v.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  const wantSymbol = opts?.showSymbol ?? s.showCurrencySymbol
  return wantSymbol ? `${s.currencySymbol} ${formatted}` : formatted
}

/**
 * fmtMoneyShort — no decimals (whole-number summary cards).
 */
export function fmtMoneyShort(n: number | null | undefined, opts?: { showSymbol?: boolean }) {
  const v = n ?? 0
  const s = currentSettings()
  const formatted = v.toLocaleString(undefined, { maximumFractionDigits: 0 })
  const wantSymbol = opts?.showSymbol ?? s.showCurrencySymbol
  return wantSymbol ? `${s.currencySymbol} ${formatted}` : formatted
}

// React hook — pages that want to react to setting changes should subscribe.
export function useCurrency() {
  const s = useFarmSettingsStore((x) => x.settings)
  return {
    code: s?.currencyCode ?? DEFAULTS.currencyCode,
    symbol: s?.currencySymbol ?? DEFAULTS.currencySymbol,
    showSymbol: s?.showCurrencySymbol ?? true,
    fmt: (n: number | null | undefined) => fmtMoney(n),
    fmtShort: (n: number | null | undefined) => fmtMoneyShort(n),
  }
}

/**
 * useFmt() — subscribes a component to the currency settings store AND
 * returns a settings-bound formatter. When the user flips the
 * "Show currency symbol" toggle, this hook fires, the component re-renders,
 * and every `fmt(n)` call below it returns the new shape.
 *
 * Usage:
 *
 *   const fmt = useFmt()
 *   return <div>{fmt(123.45)}</div>   // → "GHC 123.45" or "123.45"
 *
 * Pages that previously had a local `gh()` or `fmtMoney()` should switch to
 * this — it's the only way React knows to re-render when the toggle flips.
 */
export function useFmt() {
  // Subscribe to the settings — the subscription is the WHOLE point.
  useFarmSettingsStore((x) => x.settings)
  return fmtMoney
}

/**
 * useFmtShort() — same as useFmt() but with no decimals, for headline KPIs.
 */
export function useFmtShort() {
  useFarmSettingsStore((x) => x.settings)
  return fmtMoneyShort
}

// API helpers — small wrappers so pages don't need to know about the URL shape.
export async function fetchFarmSettings(): Promise<FarmSettings | null> {
  const ctx = getUserContext()
  if (!ctx?.farmId) return null
  const url = farmApiUrl(`/Water/farm-settings?farmId=${encodeURIComponent(ctx.farmId)}`)
  const r = await fetch(url, { headers: getAuthHeaders(), credentials: "include" })
  if (!r.ok) return null
  const j = await r.json()
  return {
    farmId: j.farmId ?? ctx.farmId,
    currencyCode: j.currencyCode ?? DEFAULTS.currencyCode,
    currencySymbol: j.currencySymbol ?? DEFAULTS.currencySymbol,
    showCurrencySymbol: !!j.showCurrencySymbol,
  }
}

export async function updateFarmCurrency(input: {
  currencyCode: string
  currencySymbol: string
  showCurrencySymbol: boolean
}): Promise<FarmSettings | null> {
  const ctx = getUserContext()
  if (!ctx?.farmId) return null
  const url = farmApiUrl(`/Water/farm-settings/currency?farmId=${encodeURIComponent(ctx.farmId)}`)
  const r = await fetch(url, {
    method: "PUT",
    headers: { ...getAuthHeaders(), "Content-Type": "application/json" },
    credentials: "include",
    body: JSON.stringify(input),
  })
  if (!r.ok) {
    const txt = await r.text().catch(() => "")
    throw new Error(`Could not update currency settings: ${r.status} ${txt}`.trim())
  }
  const j = await r.json()
  const next: FarmSettings = {
    farmId: j.farmId ?? ctx.farmId,
    currencyCode: j.currencyCode ?? DEFAULTS.currencyCode,
    currencySymbol: j.currencySymbol ?? DEFAULTS.currencySymbol,
    showCurrencySymbol: !!j.showCurrencySymbol,
  }
  // Push into the global store so every page picks it up without a refresh.
  useFarmSettingsStore.getState().apply(next)
  return next
}
