"use client"

// One egg quantity, written the way the farm wants (migration 393).
//
//   compact   "25 boxes + 5 crates + 25 pcs"
//   expanded  "10,675 eggs" with "≈ 25 boxes + 5 crates + 25 pcs" underneath
//
// Always a CONVERSION of the egg count, never a claim that eggs were packed:
// the "≈" (and the title) say "equivalent to". Use this instead of hand-rolled
// `eggs / 30` maths so every screen follows the farm's crate and box size.

import { useEggPackaging } from "@/hooks/use-egg-packaging"
import { cn } from "@/lib/utils"
import {
  eggQuantityHint, formatEggQuantity, formatEggs, type EggDisplay, type EggPackaging,
} from "@/lib/poultry/egg-packaging"

export function EggQuantity({
  eggs, mode = "compact", preference, packaging, className, hintClassName,
}: {
  eggs: number | null | undefined
  /** compact = one line in the farm's display; expanded = eggs, then the equivalent. */
  mode?: "compact" | "expanded"
  /** Override the farm's display preference (e.g. a report toggle). */
  preference?: EggDisplay
  /** A historical snapshot (a posted sale's own conversion) instead of today's. */
  packaging?: EggPackaging
  className?: string
  hintClassName?: string
}) {
  const live = useEggPackaging()
  const p = packaging ?? live
  if (eggs == null || !Number.isFinite(Number(eggs))) return <span className={className}>—</span>
  const n = Number(eggs)
  const title = `${formatEggs(n)} — equivalent to ${formatEggQuantity(n, p, "BoxesCratesPieces")}`

  if (mode === "compact") {
    return <span className={cn("tabular-nums", className)} title={title}>{formatEggQuantity(n, p, preference)}</span>
  }
  const main = (preference ?? p.display) === "Pieces" ? formatEggs(n) : formatEggQuantity(n, p, preference)
  const hint = eggQuantityHint(n, p, preference)
  return (
    <span className={cn("inline-flex flex-col tabular-nums", className)} title={title}>
      <span>{main}</span>
      {hint && <span className={cn("text-xs font-normal text-slate-500", hintClassName)}>≈ {hint}</span>}
    </span>
  )
}

/** Hook form for places that need the text (table cells, exports, tooltips). */
export function useEggQuantityText() {
  const p = useEggPackaging()
  return {
    packaging: p,
    text: (eggs: number, preference?: EggDisplay) => formatEggQuantity(eggs, p, preference),
    hint: (eggs: number, preference?: EggDisplay) => eggQuantityHint(eggs, p, preference),
  }
}

/**
 * "≈ 20 boxes" under an egg figure -- only on a farm that shows boxes (393);
 * renders nothing anywhere else, so it can sit under any egg count without
 * changing crate-only farms. Display only: no stock, no money.
 */
export function EggBoxesHint({ eggs, className }: { eggs: number | null | undefined; className?: string }) {
  const p = useEggPackaging()
  if (eggs == null || !Number.isFinite(Number(eggs)) || p.cratesPerBox == null || p.display === "CratesPieces") return null
  return (
    <div className={cn("text-xs font-normal text-slate-500 tabular-nums", className)} title="Equivalent of the egg count; not packed stock">
      ≈ {formatEggQuantity(Math.trunc(Number(eggs)), p, "BoxesCratesPieces")}
    </div>
  )
}

/** Text form of EggBoxesHint for string-only places: " (≈ 20 boxes)", or "" off box farms. */
export function useEggBoxesSuffix(): (eggs: number | null | undefined) => string {
  const p = useEggPackaging()
  return (eggs) =>
    eggs == null || !Number.isFinite(Number(eggs)) || p.cratesPerBox == null || p.display === "CratesPieces"
      ? ""
      : ` (≈ ${formatEggQuantity(Math.trunc(Number(eggs)), p, "BoxesCratesPieces")})`
}
