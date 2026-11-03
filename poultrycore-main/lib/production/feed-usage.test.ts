import { describe, expect, it } from "vitest"
import { batchesFrom, splitBlocker, splitFeed, sumKg } from "./feed-usage"
import type { FeedUsageCandidate } from "@/lib/api/feed-usage-entries"

describe("splitFeed", () => {
  it("splits by birds and sums exactly", () => {
    const r = splitFeed(100, [{ flockId: 1, birds: 1000 }, { flockId: 2, birds: 2000 }], "Birds")
    expect(r[1]).toBeCloseTo(33.333, 3)
    expect(r[2]).toBeCloseTo(66.667, 3)
    expect(sumKg(Object.values(r))).toBe(100)
  })

  it("splits equally, leftover grams to the biggest remainder then most birds", () => {
    const r = splitFeed(10, [{ flockId: 1, birds: 10 }, { flockId: 2, birds: 50 }, { flockId: 3, birds: 20 }], "Equal")
    expect(sumKg(Object.values(r))).toBe(10)
    expect(r[2]).toBe(3.334)
    expect(r[1]).toBe(3.333)
  })

  it("falls back to equal when no birds are known", () => {
    const r = splitFeed(9, [{ flockId: 1, birds: null }, { flockId: 2, birds: 0 }, { flockId: 3, birds: null }], "Birds")
    expect(r).toEqual({ 1: 3, 2: 3, 3: 3 })
  })

  it("gives zero to everyone for a zero total", () => {
    expect(splitFeed(0, [{ flockId: 1, birds: 5 }], "Birds")).toEqual({ 1: 0 })
  })

  it("handles the Btesting batch shape (one tiny flock)", () => {
    const flocks = [1000, 1000, 1000, 1000, 1000, 100, 900].map((b, i) => ({ flockId: i + 1, birds: b }))
    const r = splitFeed(600, flocks, "Birds")
    expect(sumKg(Object.values(r))).toBe(600)
    expect(r[6]).toBe(10)
  })
})

describe("splitBlocker", () => {
  it("passes when the shares add up", () => {
    expect(splitBlocker("Layer Mash", 50, [20, 30])).toBeNull()
    expect(splitBlocker("Layer Mash", 0.3, [0.1, 0.2])).toBeNull()
  })
  it("blocks a short split", () => {
    expect(splitBlocker("Layer Mash", 50, [20, 20])).toMatch(/40 kg, not 50 kg/)
  })
  it("blocks a negative share", () => {
    expect(splitBlocker("Layer Mash", 50, [60, -10])).toMatch(/negative/)
  })
})

describe("batchesFrom", () => {
  it("groups flocks by batch and skips flocks with no batch", () => {
    const c = (flockId: number, batchId: number | null): FeedUsageCandidate => ({
      flockId, flockName: `F${flockId}`, batchId, batchName: batchId ? `B${batchId}` : null, houseName: null,
      recordStatus: "None", productionRecordId: null, birds: 100, stockFeedKg: 0, feedLines: null,
    })
    const b = batchesFrom([c(1, 9), c(2, 9), c(3, null), c(4, 7)])
    expect(b.map((x) => [x.batchId, x.flocks.length])).toEqual([[9, 2], [7, 1]])
  })
})
