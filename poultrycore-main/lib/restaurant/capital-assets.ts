// =============================================================================
// Restaurant Capital Investments/Assets — the wording (migration 328).
//
// Copied word for word from lib/poultry/financial-classification.ts, the source
// of truth for this register's vocabulary. Each module keeps its own copy (the
// shared components/capital-assets/* panels take their wording as props and say
// so), which keeps the Restaurant pages free of Poultry imports while reading
// exactly as the Poultry register does.
// =============================================================================

export function assetStatusLabel(s: string | null | undefined): string {
  switch (s) {
    case "Draft": return "Not in service"
    case "Active": return "In service"
    case "FullyDepreciated": return "Fully depreciated"
    case "Disposed": return "Disposed"
    case "Reversed": return "Reversed"
    default: return s ?? "—"
  }
}

export const ASSET_STATUS_CLASS: Record<string, string> = {
  Draft: "border-slate-300 bg-slate-50 text-slate-700",
  Active: "border-emerald-300 bg-emerald-50 text-emerald-700",
  FullyDepreciated: "border-sky-300 bg-sky-50 text-sky-700",
  Disposed: "border-amber-300 bg-amber-50 text-amber-800",
  Reversed: "border-red-300 bg-red-50 text-red-700",
}

export const DEPRECIATION_CONVENTION_NOTE =
  "Depreciation is charged for the whole month an asset goes into service and for every whole month after it. Amounts are not split part-way through a month."

export const DEPRECIATION_NONCASH_NOTE =
  "Depreciation reduces profit and the asset's book value. It moves no money: no cash account, no supplier and no payment are affected."

export const BOOK_VALUE_TOOLTIP =
  "What the capital investment is still worth on the books: what it cost, less the depreciation charged so far. It never falls below the residual value."

export const ACQUISITION_COST_LABEL = "Original acquisition cost"
export const ADDITIONAL_COST_LABEL = "Additional capitalised costs"
export const TOTAL_CAPITALIZED_COST_LABEL = "Total capitalised cost"

export const ACQUISITION_COST_TOOLTIP =
  "What this capital investment was originally acquired for, including any correction made to that figure. It does not move when costs are added later."

export const ADDITIONAL_COST_TOOLTIP =
  "Everything capitalised into this capital investment after it was acquired — installation, improvements, upgrades. Reversed entries are excluded."

export const TOTAL_CAPITALIZED_COST_TOOLTIP =
  "Original acquisition cost plus any additional costs capitalised into this capital investment."

export const CORRECT_ORIGINAL_COST_NOTE =
  "Use this to fix a mistake in what the capital investment was recorded as costing. It is not the same as Add cost, which records real extra money spent on it. The correction is kept on the record with its reason, and the money already recorded is adjusted — no second payment and no second expense are created."

export const CORRECTION_DEPRECIATION_NOTE =
  "Depreciation already posted is not changed — months that have been charged stay charged, and past profit stays as it was reported. Future months follow the corrected cost."

export const COST_TREATMENT_NOTE =
  "Capitalising adds the money to what the capital investment is worth and charges it to profit gradually through depreciation. Recording it as an operating expense charges the whole amount to this period's profit instead. Routine repairs, cleaning and servicing are usually operating expenses; installation, improvements and upgrades are usually capitalised."

export const COST_LOCKED_BY_DEPRECIATION_NOTE =
  "Depreciation has already been posted for this capital investment, so its costs cannot be changed — every month already charged was worked out from them. Reverse the depreciation first."
