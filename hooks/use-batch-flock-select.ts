"use client"

// Loads flock batches + valid flocks, filters flocks by the selected batch.
// James asked (2026-05-27) that every page with a Flock dropdown also have a Batch
// dropdown above it, defaulting to "ALL". When ALL is selected, every flock shows;
// otherwise the Flock dropdown narrows to flocks tagged with the chosen batchId.
//
// Each /new page already has its own Flock state and validation, so this hook only
// owns the *list-source* state: batches, filtered flocks, loading/error. The page
// renders the two <Select> primitives itself using the data this hook returns —
// keeping the existing onChange/save logic untouched.

import { useEffect, useMemo, useState } from "react"
import { getUserContext } from "@/lib/utils/user-context"
import { getValidFlocks } from "@/lib/utils/flock-utils"
import { getFlockBatches, type FlockBatch } from "@/lib/api/flock-batch"
import type { Flock } from "@/lib/api/flock"

export const BATCH_ALL = "ALL"

export interface FlockSelectOption {
  value: string
  label: string
}

export function useBatchFlockSelect() {
  const [allFlocks, setAllFlocks] = useState<Flock[]>([])
  const [batches, setBatches] = useState<FlockBatch[]>([])
  const [selectedBatchId, setSelectedBatchId] = useState<string>(BATCH_ALL)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string>("")

  useEffect(() => {
    let cancelled = false
    const load = async () => {
      try {
        setLoading(true)
        setError("")
        const { userId, farmId } = getUserContext()
        if (!userId || !farmId) {
          if (!cancelled) {
            setAllFlocks([])
            setBatches([])
            setLoading(false)
          }
          return
        }
        // Run both in parallel — independent endpoints.
        const [flocks, batchesRes] = await Promise.all([
          getValidFlocks().catch(() => [] as Flock[]),
          getFlockBatches(userId, farmId).catch(() => ({ success: false, data: [] as FlockBatch[] })),
        ])
        if (cancelled) return
        setAllFlocks(flocks)
        setBatches(batchesRes.success && Array.isArray(batchesRes.data) ? batchesRes.data : [])
      } catch (e: any) {
        if (!cancelled) setError(e?.message ?? "Failed to load batches and flocks")
      } finally {
        if (!cancelled) setLoading(false)
      }
    }
    void load()
    return () => { cancelled = true }
  }, [])

  // Flocks narrowed to the selected batch. When ALL, return everything.
  const filteredFlocks = useMemo<Flock[]>(() => {
    if (selectedBatchId === BATCH_ALL) return allFlocks
    const batchIdNum = Number(selectedBatchId)
    if (!Number.isFinite(batchIdNum)) return allFlocks
    return allFlocks.filter((f) => f.batchId === batchIdNum)
  }, [allFlocks, selectedBatchId])

  // Pre-built {value,label} options the page can drop straight into <SelectItem>.
  const flockOptions = useMemo<FlockSelectOption[]>(
    () => filteredFlocks
      .filter((f) => f.flockId != null && f.name)
      .map((f) => ({ value: String(f.flockId), label: f.name })),
    [filteredFlocks],
  )

  // Batch options including the leading "All" entry. Pages render these directly.
  const batchOptions = useMemo<FlockSelectOption[]>(
    () => [
      { value: BATCH_ALL, label: "All batches" },
      ...batches
        .filter((b) => b.batchId != null)
        .map((b) => ({ value: String(b.batchId), label: b.batchName || b.batchCode || `Batch #${b.batchId}` })),
    ],
    [batches],
  )

  return {
    batches,
    batchOptions,
    selectedBatchId,
    setSelectedBatchId,
    allFlocks,
    filteredFlocks,
    flockOptions,
    loading,
    error,
  }
}
