// Carry a saved day's feed / medication lines into the next day's form: the
// step-through catch-up uses this so a farm that feeds the same thing every
// day types it once. The drafts are ordinary editable lines; the next save
// runs its own stock check on them.

import type { ProductionFeedLine, ProductionMedicationLine } from "@/lib/api/production-record"

export interface FeedDraftLike { specificFeedUsedId: string; totalFeedConsumed: string }
export interface MedDraftLike { specificMedicationUsedId: string; totalMedicationConsumed: string }

export function feedDraftsFrom(lines: ProductionFeedLine[] | null | undefined): FeedDraftLike[] {
  return (lines ?? [])
    .filter((l) => l.specificFeedUsedId != null && (l.totalFeedConsumed ?? 0) > 0)
    .map((l) => ({ specificFeedUsedId: String(l.specificFeedUsedId), totalFeedConsumed: String(l.totalFeedConsumed) }))
}

export function medDraftsFrom(lines: ProductionMedicationLine[] | null | undefined): MedDraftLike[] {
  return (lines ?? [])
    .filter((l) => l.specificMedicationUsedId != null && (l.totalMedicationConsumed ?? 0) > 0)
    .map((l) => ({
      specificMedicationUsedId: String(l.specificMedicationUsedId),
      totalMedicationConsumed: String(l.totalMedicationConsumed),
    }))
}
