"use client"

// Renders the "Source" column on Expense lists / details for auto-generated
// expense rows. See Prompt 2 ("Populate Clickable Source Links") in
// Migrations/ompal/Three Prompts In one powerful please implement all.txt.
//
// Routing rules:
//   ProductionBatch       → /water-production-batches/[id]
//   RawMaterialPurchase   → /water-raw-materials?purchaseId=[id]
//                           (no detail page for purchases yet — we deep-link
//                            with a query param the list page can scroll to)
//   Payroll               → /water-payroll/[id]
//
// Add a new SourceType by adding a row here. The DB already carries the
// SourceType/SourceId on the row (migration 075/078 — see notes in those
// migrations); the label/URL mapping stays UI-side because labels are
// display concerns and routes evolve independently of the DB.

import Link from "next/link"
import { Factory, Package, Banknote } from "lucide-react"

type SourceKind = "ProductionBatch" | "RawMaterialPurchase" | "Payroll" | (string & {})

export interface ExpenseSourceLinkProps {
  sourceType?: SourceKind | null
  sourceId?: number | null
  // Legacy fallback — older RM purchase auto-expenses set
  // linkedWaterProductionBatchId rather than SourceType. The 078 backfill
  // populates SourceType for new reads, but if a row hasn't been re-read
  // since the migration we still want the Production link to render.
  linkedWaterProductionBatchId?: number | null
}

export function ExpenseSourceLink({
  sourceType, sourceId, linkedWaterProductionBatchId,
}: ExpenseSourceLinkProps) {
  // Resolve SourceType + SourceId, falling back to the legacy column.
  let resolvedType: SourceKind | null = sourceType ?? null
  let resolvedId:   number | null      = sourceId   ?? null
  if (!resolvedType && linkedWaterProductionBatchId) {
    resolvedType = "ProductionBatch"
    resolvedId   = linkedWaterProductionBatchId
  }
  if (!resolvedType || !resolvedId) {
    return <span className="text-slate-400">—</span>
  }

  switch (resolvedType) {
    case "ProductionBatch":
      return (
        <Link
          href={`/water-production-batches/${resolvedId}`}
          className="inline-flex items-center gap-1 text-indigo-700 hover:underline text-xs"
        >
          <Factory className="h-3.5 w-3.5" /> Production Batch
        </Link>
      )
    case "RawMaterialPurchase":
      return (
        <Link
          href={`/water-raw-materials?purchaseId=${resolvedId}`}
          className="inline-flex items-center gap-1 text-emerald-700 hover:underline text-xs"
        >
          <Package className="h-3.5 w-3.5" /> Raw Materials &amp; Supplies Purchase
        </Link>
      )
    case "Payroll":
      return (
        <Link
          href={`/water-payroll/${resolvedId}`}
          className="inline-flex items-center gap-1 text-sky-700 hover:underline text-xs"
        >
          <Banknote className="h-3.5 w-3.5" /> Payroll Run #{resolvedId}
        </Link>
      )
    default:
      // Unknown source — show the raw type so it's debuggable instead of
      // silently rendering "—" and pretending nothing's there.
      return (
        <span className="inline-flex items-center gap-1 text-slate-500 text-xs">
          {resolvedType} #{resolvedId}
        </span>
      )
  }
}
