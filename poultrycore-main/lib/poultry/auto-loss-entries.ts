// Automatic rows on the Poultry Loss & Damage page.
//
// Eggs are marked damaged in three places, and before this none of them showed
// up on the Loss & Damage page, which only listed rows typed in by hand:
//   1. a production record's broken eggs,
//   2. damaged / missing crates on a driver return (and delivery or production
//      batch losses), which the API already writes to poultryproductionloss,
//   3. a 'Egg Loss' adjustment (breakage / loss) on an egg class in the Egg
//      Sorting workspace, which is a stock-ledger row.
//
// These rows are DERIVED, never stored: each one is read from its source every
// time, so editing or deleting the source changes the row and the two cannot
// disagree. They carry no approval step and add no value to the closing
// report's loss figure (that reads approved manual records only). To change one,
// change its source — the row links there.

import type { ProductionRecord } from "@/lib/api/production-record"
import type { PoultryProductionLoss, PoultryStockTransaction } from "@/lib/api/poultry-inventory"

export type AutoLossSource = "ProductionRecord" | "DriverReturn" | "Delivery" | "ProductionBatch" | "EggSorting"

export interface AutoLossEntry {
  /** Unique across all sources, for React keys. */
  key: string
  source: AutoLossSource
  /** Shown as "Damage — from <sourceLabel>". */
  sourceLabel: string
  lossDate: string
  lossType: string
  productName: string
  quantity: number
  estimatedValue: number | null
  reason: string | null
  /** Where the entry is changed. Null when the source has no page. */
  href: string | null
}

const RETURN_TO = encodeURIComponent("/poultry-loss-records")

function dayOf(d: string | null | undefined): string {
  return (d || "").split("T")[0]
}

function inRange(d: string, from?: string, to?: string): boolean {
  const day = dayOf(d)
  if (!day) return false
  if (from && day < from) return false
  if (to && day > to) return false
  return true
}

/** One row per production record with broken eggs. */
export function fromProductionRecords(records: ProductionRecord[]): AutoLossEntry[] {
  return records
    .filter((r) => Number(r.brokenEggs ?? 0) > 0)
    .map((r) => {
      const broken = Number(r.brokenEggs)
      const disposed = r.brokenEggsDisposed
      const bits = [r.flockName ? `Flock ${r.flockName}` : null]
      if (disposed != null) bits.push(disposed >= broken ? "all disposed" : `${disposed} disposed, ${broken - disposed} kept`)
      else if (r.brokenEggDisposition === "Disposed") bits.push("all disposed")
      return {
        key: `pr-${r.id}`,
        source: "ProductionRecord" as const,
        sourceLabel: "production record",
        lossDate: r.date,
        lossType: "Damage",
        productName: "Broken eggs",
        quantity: broken,
        estimatedValue: null,
        reason: bits.filter(Boolean).join(" · ") || null,
        href: `/production-records/${r.id}?returnTo=${RETURN_TO}`,
      }
    })
}

/** Driver-return, delivery and production-batch losses (already one row each). */
export function fromProductionLosses(losses: PoultryProductionLoss[]): AutoLossEntry[] {
  return losses
    .filter((l) => Number(l.quantityLost ?? 0) > 0)
    .map((l) => {
      const src: AutoLossSource =
        l.sourceType === "PoultryDriverReturn" ? "DriverReturn"
        : l.sourceType === "PoultryDelivery" ? "Delivery"
        : "ProductionBatch"
      const label = src === "DriverReturn" ? "driver return" : src === "Delivery" ? "delivery" : "production batch"
      const href = src === "DriverReturn" ? "/poultry-driver-returns" : src === "Delivery" ? "/poultry-deliveries" : null
      return {
        key: `pl-${l.poultryProductionLossId}`,
        source: src,
        sourceLabel: label,
        lossDate: l.lossDate,
        lossType: "Damage",
        productName: l.productName || "Eggs",
        quantity: Number(l.quantityLost),
        estimatedValue: l.estimatedValue ?? null,
        reason: l.reason ?? null,
        href,
      }
    })
}

/** 'Egg Loss' ledger rows: breakage or loss taken out of an egg class. */
export function fromEggLossTransactions(txns: PoultryStockTransaction[]): AutoLossEntry[] {
  return txns
    .filter((t) => t.txnType === "Egg Loss" && Number(t.quantity) < 0)
    .map((t) => ({
      key: `st-${t.poultryStockTransactionId}`,
      source: "EggSorting" as const,
      sourceLabel: "egg sorting",
      lossDate: t.effectiveDate || t.createdDate,
      lossType: "Damage",
      productName: t.productName ? `${t.productName} eggs` : "Eggs",
      quantity: Math.abs(Number(t.quantity)),
      estimatedValue: null,
      reason: t.note ?? t.reason ?? null,
      href: "/poultry-egg-sorting",
    }))
}

/** A row from GET /Poultry/loss-records/auto-damage (migration 405). */
export interface AutoDamageApiRow {
  sourceType: string; sourceId?: number | null; lossDate: string; lossType: string
  productName?: string | null; quantity: number; estimatedValue?: number | null
  details?: string | null; flockName?: string | null; brokenEggs?: number | null; disposed?: number | null
}

/** Maps the server's rows to the same shape the browser fallback builds. */
export function fromAutoDamageApi(rows: AutoDamageApiRow[]): AutoLossEntry[] {
  return rows.map((r, i) => {
    const id = r.sourceId ?? `x${i}`
    switch (r.sourceType) {
      case "ProductionRecord": {
        const broken = Number(r.brokenEggs ?? r.quantity)
        const d = r.disposed
        const bits = [r.flockName ? `Flock ${r.flockName}` : null]
        if (d != null && d > 0) bits.push(d >= broken ? "all disposed" : `${d} disposed, ${broken - d} kept`)
        return {
          key: `pr-${id}`, source: "ProductionRecord" as const, sourceLabel: "production record",
          lossDate: r.lossDate, lossType: r.lossType, productName: r.productName || "Broken eggs",
          quantity: Number(r.quantity), estimatedValue: null, reason: bits.filter(Boolean).join(" · ") || null,
          href: r.sourceId != null ? `/production-records/${r.sourceId}?returnTo=${RETURN_TO}` : null,
        }
      }
      case "EggSorting":
        return {
          key: `st-${id}`, source: "EggSorting" as const, sourceLabel: "egg sorting",
          lossDate: r.lossDate, lossType: r.lossType, productName: r.productName || "Eggs",
          quantity: Number(r.quantity), estimatedValue: null, reason: r.details ?? null, href: "/poultry-egg-sorting",
        }
      default: {
        const src: AutoLossSource = r.sourceType === "DriverReturn" ? "DriverReturn" : r.sourceType === "Delivery" ? "Delivery" : "ProductionBatch"
        return {
          key: `pl-${src}-${id}-${i}`, source: src,
          sourceLabel: src === "DriverReturn" ? "driver return" : src === "Delivery" ? "delivery" : "production batch",
          lossDate: r.lossDate, lossType: r.lossType, productName: r.productName || "Eggs",
          quantity: Number(r.quantity), estimatedValue: r.estimatedValue ?? null, reason: r.details ?? null,
          href: src === "DriverReturn" ? "/poultry-driver-returns" : src === "Delivery" ? "/poultry-deliveries" : null,
        }
      }
    }
  })
}

/** All three, newest first, optionally limited to a date range (YYYY-MM-DD). */
export function buildAutoLossEntries(input: {
  records?: ProductionRecord[]
  losses?: PoultryProductionLoss[]
  txns?: PoultryStockTransaction[]
  fromDate?: string
  toDate?: string
}): AutoLossEntry[] {
  const all = [
    ...fromProductionRecords(input.records ?? []),
    ...fromProductionLosses(input.losses ?? []),
    ...fromEggLossTransactions(input.txns ?? []),
  ].filter((e) => inRange(e.lossDate, input.fromDate, input.toDate))
  return all.sort((a, b) => (dayOf(b.lossDate) < dayOf(a.lossDate) ? -1 : dayOf(b.lossDate) > dayOf(a.lossDate) ? 1 : 0))
}
