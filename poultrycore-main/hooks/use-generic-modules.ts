"use client"

// Which Generic modules to show, and what to call them.
//
// The sidebar, the top nav and the mobile bar all need the same two answers, so
// they share one hook and one in-memory cache keyed by farm. Without the cache
// switching pages would refetch the settings three times per render pass.
//
// Two deliberate defaults:
//   - While loading, and if the request fails, `settings` is null and
//     `showNew` is FALSE. A menu item that flickers in and out is worse than
//     one that appears a moment late.
//   - `labels` falls back to the neutral vocabulary, so a Generic company that
//     predates templates reads exactly as it does today.

import { useEffect, useState } from "react"
import { useAuthStore } from "@/lib/store/auth-store"
import {
  getModuleSettings, getBusinessTemplate, type GenericModuleSettings,
} from "@/lib/api/generic-subscriptions"
import { templateLabels, type TemplateLabels } from "@/lib/generic/template-labels"

interface Cached {
  settings: GenericModuleSettings | null
  industry: string | null
}

// Module-level, not React state: three components mount at once and must not
// each fire their own pair of requests.
const cache = new Map<string, Cached>()
const inflight = new Map<string, Promise<Cached>>()

async function load(farmId: string): Promise<Cached> {
  const hit = cache.get(farmId)
  if (hit) return hit

  const running = inflight.get(farmId)
  if (running) return running

  const p = (async () => {
    const [settings, template] = await Promise.all([
      getModuleSettings().catch(() => null),
      getBusinessTemplate().catch(() => null),
    ])
    const value: Cached = {
      settings,
      industry: template?.genericIndustryTemplate ?? null,
    }
    cache.set(farmId, value)
    inflight.delete(farmId)
    return value
  })()

  inflight.set(farmId, p)
  return p
}

/** Drop the cache for a farm — call after the setup wizard changes settings. */
export function invalidateGenericModules(farmId?: string) {
  if (farmId) {
    cache.delete(farmId)
    inflight.delete(farmId)
  } else {
    cache.clear()
    inflight.clear()
  }
}

export interface GenericModulesResult {
  settings: GenericModuleSettings | null
  industry: string | null
  labels: TemplateLabels
  isLoading: boolean
  /**
   * Whether to show a NEW nav item gated on a module setting. False while
   * loading and on failure — the existing Generic items are never gated on
   * this, because retro-fitting gates would take away access people have today.
   */
  showNew: (key: keyof GenericModuleSettings) => boolean
}

export function useGenericModules(): GenericModulesResult {
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const isGeneric = activeFarmType === "Generic"

  const [state, setState] = useState<Cached>(() =>
    activeFarmId ? cache.get(activeFarmId) ?? { settings: null, industry: null } : { settings: null, industry: null },
  )
  const [isLoading, setIsLoading] = useState(isGeneric && !cache.get(activeFarmId ?? ""))

  useEffect(() => {
    if (!isGeneric || !activeFarmId) {
      setState({ settings: null, industry: null })
      setIsLoading(false)
      return
    }
    let alive = true
    setIsLoading(true)
    load(activeFarmId)
      .then((v) => {
        if (alive) setState(v)
      })
      .finally(() => {
        if (alive) setIsLoading(false)
      })
    return () => {
      alive = false
    }
  }, [isGeneric, activeFarmId])

  return {
    settings: state.settings,
    industry: state.industry,
    labels: templateLabels(state.industry),
    isLoading,
    showNew: (key) => Boolean(state.settings?.[key]),
  }
}
