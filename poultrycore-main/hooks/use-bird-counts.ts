"use client"

// Live birds per flock and per batch, for showing next to the Batch / Flock
// pickers. Read from the bird ledger (sppoultrybirdadjustment_options ->
// fnflock_birdposition), never flock.quantity -- the same figure the bird
// adjustment page shows. A batch's birds = its flocks' live birds + birds of
// the batch not yet placed in any flock.

import { useEffect, useMemo, useState } from "react"
import { listPoultryBirdAdjustmentOptions, type PoultryBirdAdjustmentOption } from "@/lib/api/poultry-inventory"

export interface BatchBirdCount {
  total: number
  inFlocks: number
  unplaced: number
}

export function useBirdCounts() {
  const [rows, setRows] = useState<PoultryBirdAdjustmentOption[]>([])
  const [loaded, setLoaded] = useState(false)

  useEffect(() => {
    let cancelled = false
    listPoultryBirdAdjustmentOptions()
      .then((r) => { if (!cancelled) setRows(Array.isArray(r) ? r : []) })
      .catch(() => { /* counts are a hint; the pickers work without them */ })
      .finally(() => { if (!cancelled) setLoaded(true) })
    return () => { cancelled = true }
  }, [])

  return useMemo(() => {
    const byFlock = new Map<number, number>()
    const byBatch = new Map<number, BatchBirdCount>()
    for (const r of rows) {
      const b = byBatch.get(r.batchId) ?? { total: 0, inFlocks: 0, unplaced: Math.max(r.unplacedBirds ?? 0, 0) }
      if (r.flockId != null) {
        const live = Math.max(r.liveBirds ?? 0, 0)
        byFlock.set(r.flockId, live)
        b.inFlocks += live
      }
      b.total = b.inFlocks + b.unplaced
      byBatch.set(r.batchId, b)
    }
    return { byFlock, byBatch, loaded }
  }, [rows, loaded])
}

export const birdsText = (n: number) => `${n.toLocaleString()} bird${n === 1 ? "" : "s"}`
