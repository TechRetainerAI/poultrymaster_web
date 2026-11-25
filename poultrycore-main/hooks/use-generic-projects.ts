"use client"

// Projects & Contracts: is the module on for this company, and which projects
// can a transaction be assigned to. One cached list per farm, shared by every
// picker on a page (a purchase form with ten lines must not fetch ten times).

import { useCallback, useEffect, useState } from "react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useGenericModules } from "@/hooks/use-generic-modules"
import { getProjectOptions, type ProjectOption } from "@/lib/api/generic-projects"

const cache = new Map<string, ProjectOption[]>()
const inflight = new Map<string, Promise<ProjectOption[]>>()

function key(farmId: string, includeClosed: boolean) {
  return `${farmId}|${includeClosed ? 1 : 0}`
}

/** Drop the cached project lists (after creating, archiving or renaming one). */
export function invalidateProjectOptions() {
  cache.clear()
  inflight.clear()
}

export function useProjectsEnabled(): { enabled: boolean; isLoading: boolean } {
  const { settings, isLoading } = useGenericModules()
  return { enabled: Boolean(settings?.enableProjects), isLoading }
}

/**
 * Projects for pickers. includeClosed adds Completed/Cancelled projects (report
 * filters, linking older transactions). Archived projects never appear.
 */
export function useProjectOptions(includeClosed = false) {
  const farmId = useAuthStore((s) => s.activeFarmId) ?? ""
  const k = key(farmId, includeClosed)
  const [options, setOptions] = useState<ProjectOption[]>(() => cache.get(k) ?? [])
  const [loading, setLoading] = useState(!cache.has(k))
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async (force = false) => {
    if (!farmId) return
    if (force) { cache.delete(k); inflight.delete(k) }
    const hit = cache.get(k)
    if (hit) { setOptions(hit); setLoading(false); return }
    setLoading(true)
    let p = inflight.get(k)
    if (!p) {
      p = getProjectOptions(includeClosed).then((v) => { cache.set(k, v ?? []); inflight.delete(k); return v ?? [] })
      inflight.set(k, p)
    }
    try {
      setOptions(await p)
      setError(null)
    } catch (e: any) {
      inflight.delete(k)
      setError(e?.message ?? String(e))
    } finally {
      setLoading(false)
    }
  }, [farmId, k, includeClosed])

  useEffect(() => { void load() }, [load])

  return { options, loading, error, reload: () => load(true) }
}
