"use client"

/**
 * The Livestock company's species: the catalogue, which ones the farm keeps,
 * and what that switches on (egg, milk and breeding pages).
 *
 * Fails OPEN like usePoultryEggFeatures: while loading, on error, and on
 * other company types every feature is "on" -- hiding a page a farm needs is
 * the worse mistake.
 *
 * HOOK ORDER: safe to call for every company type; the query is only enabled
 * on a Livestock company.
 */

import { useQuery, useQueryClient } from "@tanstack/react-query"
import { useCallback, useMemo } from "react"
import { useAuthStore } from "@/lib/store/auth-store"
import { listSpecies, type LivestockSpecies } from "@/lib/api/livestock"

export const LIVESTOCK_SPECIES_KEY = "livestock-species"

export function useLivestockSpecies() {
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const isLivestock = activeFarmType === "Livestock"
  const qc = useQueryClient()
  const { data, isLoading, error } = useQuery({
    queryKey: [LIVESTOCK_SPECIES_KEY, activeFarmId],
    queryFn: listSpecies,
    enabled: isLivestock && !!activeFarmId,
    staleTime: 5 * 60 * 1000,
    retry: false,
  })
  const refresh = useCallback(
    () => qc.invalidateQueries({ queryKey: [LIVESTOCK_SPECIES_KEY] }),
    [qc],
  )
  return useMemo(() => {
    const all: LivestockSpecies[] = data ?? []
    const kept = all.filter((s) => s.enabled)
    const byCode = new Map(all.map((s) => [s.speciesCode, s]))
    return { all, kept, byCode, isLoading, error: error as Error | null, refresh, loaded: !!data }
  }, [data, isLoading, error, refresh])
}

export interface LivestockFeatures { eggs: boolean; milk: boolean; breeding: boolean }

/** What the kept species switch on. All true until known, or when nothing is kept yet. */
export function useLivestockFeatures(): LivestockFeatures {
  const { kept, loaded } = useLivestockSpecies()
  return useMemo(() => {
    if (!loaded || kept.length === 0) return { eggs: true, milk: true, breeding: true }
    return {
      eggs: kept.some((s) => s.producesEggs),
      milk: kept.some((s) => s.producesMilk),
      breeding: kept.some((s) => s.breedsOnFarm),
    }
  }, [kept, loaded])
}
