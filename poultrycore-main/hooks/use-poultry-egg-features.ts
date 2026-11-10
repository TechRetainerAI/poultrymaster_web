"use client"

/**
 * Does the active poultry company need its egg screens? (migration 399)
 *
 * The answer comes from its flocks: yes while any open flock is a Layer flock,
 * no once only broilers are running. The company's business type (Layers |
 * Broilers | Both) settles an empty farm -- but that endpoint is admin-only, so
 * for staff a 403 simply means "not known", never "hide".
 *
 * Fails OPEN: while loading, on any error, and on non-poultry companies the
 * answer is true. Hiding a screen a layer farm needs is the worse mistake.
 *
 * HOOK ORDER: safe to call for every company type -- the query is merely
 * disabled off poultry. See the TopNavigation note on the Water crash.
 */

import { useQuery, useQueryClient } from "@tanstack/react-query"
import { useCallback } from "react"
import { useAuthStore } from "@/lib/store/auth-store"
import { getUserContext } from "@/lib/api/config"
import { getFlocks } from "@/lib/api/flock"
import { getPoultryCompanyProfile } from "@/lib/api/poultry-company"
import { showBroilerFeatures, showEggFeatures } from "@/lib/poultry/flock-type"

export const POULTRY_EGG_FEATURES_KEY = "poultry-egg-features"

interface PoultryFeatures { eggs: boolean; broilers: boolean }

async function loadPoultryFeatures(): Promise<PoultryFeatures> {
  const { userId, farmId } = getUserContext()
  const [flocksRes, profile] = await Promise.all([
    getFlocks(userId ?? undefined, farmId ?? undefined).catch(() => null),
    getPoultryCompanyProfile().catch(() => null),
  ])
  if (!flocksRes?.success) return { eggs: true, broilers: true }
  const flocks = flocksRes.data ?? []
  const type = profile?.businessType ?? null
  return { eggs: showEggFeatures(flocks, type), broilers: showBroilerFeatures(flocks, type) }
}

function usePoultryFeatures(): PoultryFeatures | undefined {
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const isPoultry = !activeFarmType || String(activeFarmType).toLowerCase() === "poultry"
  const { data } = useQuery({
    queryKey: [POULTRY_EGG_FEATURES_KEY, activeFarmId],
    queryFn: loadPoultryFeatures,
    enabled: isPoultry && !!activeFarmId,
    staleTime: 5 * 60 * 1000,
    gcTime: 15 * 60 * 1000,
    retry: false,
  })
  return data
}

export function usePoultryEggFeatures(): boolean {
  return usePoultryFeatures()?.eggs ?? true
}

/** 402: offer Broiler performance? Same query and the same fail-open rule as eggs. */
export function usePoultryBroilerFeatures(): boolean {
  return usePoultryFeatures()?.broilers ?? true
}

/**
 * The company's business type (Layers | Broilers | Both), or null when it is
 * not known -- no profile yet, or a staff member (the endpoint is admin-only).
 * Only used to SHOW the default a new flock will get; the server applies the
 * same rule itself, so null never changes what is saved.
 */
export function usePoultryBusinessType(): string | null {
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const { data } = useQuery({
    queryKey: ["poultry-business-type", activeFarmId],
    queryFn: async () => (await getPoultryCompanyProfile().catch(() => null))?.businessType ?? null,
    enabled: !!activeFarmId,
    staleTime: 10 * 60 * 1000,
    retry: false,
  })
  return data ?? null
}

/** Call after a flock is created, retyped or closed, so the menus follow at once. */
export function useRefreshPoultryEggFeatures(): () => void {
  const qc = useQueryClient()
  return useCallback(() => {
    void qc.invalidateQueries({ queryKey: [POULTRY_EGG_FEATURES_KEY] })
  }, [qc])
}
