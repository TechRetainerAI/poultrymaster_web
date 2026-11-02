// Egg packaging: Boxes, Crates and Pieces (migration 393).
//
// Egg stock is ALWAYS individual eggs. A crate is the farm's eggs-per-crate
// (344) and a box is the farm's crates-per-box (393); both are only ways of
// writing the same egg count. Nothing here creates, removes or stores stock.
//
// This file is the one conversion rule on the web side. It must agree with
// the database functions fnpoultry_eggpieces / fnpoultry_eggbreakdown /
// fnpoultry_eggqtytext -- the database is the authority when posting; these
// are for entry, previews and display.
//
// A box is a quantity unit, not a poultry Batch (a group of birds).

/** How a farm wants egg quantities written. */
export type EggDisplay = "BoxesCratesPieces" | "CratesPieces" | "Pieces"

/** Which packaging field Add Sale puts first. Presentation only. */
export type SaleEntryUnit = "Boxes" | "Crates"

export interface EggPackaging {
  eggsPerCrate: number
  /** Boxes switched on for this farm. */
  enableBoxes: boolean
  /** Null when boxes are off. */
  cratesPerBox: number | null
  /** cratesPerBox x eggsPerCrate; null when boxes are off. */
  eggsPerBox: number | null
  display: EggDisplay
  saleEntryUnit: SaleEntryUnit
  /** Bumps whenever the conversion changes (393). */
  version: number
}

export const DEFAULT_EGG_PACKAGING: EggPackaging = {
  eggsPerCrate: 30,
  enableBoxes: false,
  cratesPerBox: null,
  eggsPerBox: null,
  display: "CratesPieces",
  saleEntryUnit: "Crates",
  version: 1,
}

export const MAX_CRATES_PER_BOX = 200

export interface PackagedQuantity {
  boxes: number
  crates: number
  pieces: number
}

const whole = (n: unknown) => {
  const v = Number(n)
  return Number.isFinite(v) ? Math.trunc(v) : 0
}

/** Crates per box when boxes are usable, else null. Never 0 (no division by zero). */
export function boxSize(p: Pick<EggPackaging, "enableBoxes" | "cratesPerBox">): number | null {
  const c = whole(p.cratesPerBox)
  return p.enableBoxes && c >= 1 ? c : null
}

/** Eggs in one box, or null when boxes are off. */
export function eggsPerBox(p: Pick<EggPackaging, "enableBoxes" | "cratesPerBox" | "eggsPerCrate">): number | null {
  const c = boxSize(p)
  return c == null ? null : c * Math.max(1, whole(p.eggsPerCrate) || 30)
}

/**
 * A packaging configuration problem, or null when it is fine. The same rules
 * as sppoultryeggpackaging_save, so the form can say so before saving.
 */
export function packagingConfigError(p: {
  enableBoxes: boolean
  cratesPerBox: number | null | undefined
  display: EggDisplay
  saleEntryUnit: SaleEntryUnit
}): string | null {
  const c = p.cratesPerBox
  if (p.enableBoxes && (c == null || String(c) === "")) return "Enter how many crates are in one box."
  if (c != null && String(c) !== "" && (!Number.isInteger(Number(c)) || Number(c) < 1 || Number(c) > MAX_CRATES_PER_BOX)) {
    return `Crates per box must be a whole number from 1 to ${MAX_CRATES_PER_BOX}.`
  }
  if (p.display === "BoxesCratesPieces" && !p.enableBoxes) return "Turn on Boxes to show quantities in boxes."
  if (p.saleEntryUnit === "Boxes" && !p.enableBoxes) return "Turn on Boxes to enter sales in boxes first."
  return null
}

/**
 * A packaging entry problem, or null. Whole, non-negative numbers; boxes only
 * when the farm has a box size.
 */
export function packagedQuantityError(q: Partial<PackagedQuantity>, p: EggPackaging): string | null {
  for (const [k, v] of Object.entries(q)) {
    if (v == null || (v as unknown) === "") continue
    const n = Number(v)
    if (!Number.isFinite(n) || !Number.isInteger(n)) return `Enter whole ${k}.`
    if (n < 0) return `${k[0].toUpperCase()}${k.slice(1)} cannot be negative.`
  }
  if (whole(q.boxes) > 0 && boxSize(p) == null) return "Boxes are not set up for this farm."
  return null
}

/** Boxes + Crates + Pieces -> eggs. Bad parts count as 0; check packagedQuantityError first. */
export function toEggPieces(q: Partial<PackagedQuantity>, p: EggPackaging): number {
  const epc = Math.max(1, whole(p.eggsPerCrate) || 30)
  const b = Math.max(0, whole(q.boxes))
  const c = Math.max(0, whole(q.crates))
  const pc = Math.max(0, whole(q.pieces))
  const ebx = eggsPerBox(p) ?? 0
  return b * ebx + c * epc + pc
}

/**
 * Eggs -> whole boxes, whole crates, loose pieces. Boxes off gives 0 boxes.
 * A negative count keeps its sign on every part (a decrease or a correction).
 */
export function toBoxesCratesPieces(totalEggs: number, p: EggPackaging): PackagedQuantity {
  const raw = whole(totalEggs)
  const sign = raw < 0 ? -1 : 1
  const n = Math.abs(raw)
  const epc = Math.max(1, whole(p.eggsPerCrate) || 30)
  const ebx = eggsPerBox(p)
  const boxes = ebx ? Math.floor(n / ebx) : 0
  const rest = ebx ? n % ebx : n
  // `|| 0` turns a -0 into 0 so a zero part never prints as "-0".
  return { boxes: sign * boxes || 0, crates: sign * Math.floor(rest / epc) || 0, pieces: sign * (rest % epc) || 0 }
}

/** Eggs -> whole crates + loose pieces, ignoring boxes. */
export function toCratesPieces(totalEggs: number, p: Pick<EggPackaging, "eggsPerCrate">): { crates: number; pieces: number } {
  const q = toBoxesCratesPieces(totalEggs, { ...DEFAULT_EGG_PACKAGING, eggsPerCrate: p.eggsPerCrate })
  return { crates: q.crates, pieces: q.pieces }
}

/**
 * The same eggs written in their fewest packages: 1 box + 16 crates + 35 pcs
 * at 14 crates/box becomes 2 boxes + 3 crates + 5 pcs. Same egg count.
 */
export function normalizePackaged(q: Partial<PackagedQuantity>, p: EggPackaging): PackagedQuantity {
  return toBoxesCratesPieces(toEggPieces(q, p), p)
}

const fmtInt = (n: number) => n.toLocaleString("en-US")
const plural = (n: number, one: string, many: string) => (Math.abs(n) === 1 ? one : many)

/** The display mode actually usable: a box display without boxes falls back to crates. */
export function effectiveDisplay(p: EggPackaging, preference: EggDisplay = p.display): EggDisplay {
  return preference === "BoxesCratesPieces" && boxSize(p) == null ? "CratesPieces" : preference
}

/** "10,675 eggs" */
export function formatEggs(totalEggs: number): string {
  const n = whole(totalEggs)
  return `${fmtInt(n)} ${plural(n, "egg", "eggs")}`
}

/**
 * One packaged quantity as text. Zero parts are left out; a quantity smaller
 * than one crate (or 0) is written in eggs. Same words as fnpoultry_eggqtytext.
 *   BoxesCratesPieces  "25 boxes + 5 crates + 25 pcs"
 *   CratesPieces       "355 crates + 25 pcs"
 *   Pieces             "10,675 eggs"
 */
export function formatEggQuantity(totalEggs: number, p: EggPackaging, preference: EggDisplay = p.display): string {
  const mode = effectiveDisplay(p, preference)
  const n = whole(totalEggs)
  if (mode === "Pieces") return formatEggs(n)
  const q = mode === "BoxesCratesPieces" ? toBoxesCratesPieces(n, p) : { boxes: 0, ...toCratesPieces(n, p) }
  if (q.boxes === 0 && q.crates === 0) return formatEggs(n)
  return formatPackaged(q)
}

/** A packaged quantity exactly as entered: "2 boxes + 3 crates + 10 pcs". Empty -> "0 eggs". */
export function formatPackaged(q: Partial<PackagedQuantity>): string {
  const b = whole(q.boxes), c = whole(q.crates), pc = whole(q.pieces)
  const parts = [
    b ? `${fmtInt(b)} ${plural(b, "box", "boxes")}` : "",
    c ? `${fmtInt(c)} ${plural(c, "crate", "crates")}` : "",
    pc ? `${fmtInt(pc)} pcs` : "",
  ].filter(Boolean)
  return parts.length ? parts.join(" + ") : "0 eggs"
}

/**
 * The secondary line under a total: the packaging equivalent when it says
 * something the egg count does not, else null. "Pieces" farms get the box (or
 * crate) equivalent as the hint; packaging farms get the egg count.
 */
export function eggQuantityHint(totalEggs: number, p: EggPackaging, preference: EggDisplay = p.display): string | null {
  const mode = effectiveDisplay(p, preference)
  const n = whole(totalEggs)
  if (mode === "Pieces") {
    const alt = formatEggQuantity(n, p, boxSize(p) != null ? "BoxesCratesPieces" : "CratesPieces")
    return alt === formatEggs(n) ? null : alt
  }
  const main = formatEggQuantity(n, p, mode)
  return main === formatEggs(n) ? null : formatEggs(n)
}

/** Cache key part for anything derived from the packaging (company + version). */
export const packagingKey = (farmId: string | null | undefined, p: EggPackaging) =>
  `${farmId ?? "-"}:${p.version}:${p.eggsPerCrate}:${boxSize(p) ?? 0}`

// -----------------------------------------------------------------------------
// Pricing (migration 394)
// -----------------------------------------------------------------------------

export interface PackagedPrices {
  /** Per crate: the price sales have always used. */
  pricePerCrate: number
  /** Null = crates per box x the crate price. */
  pricePerBox?: number | null
  /** Null = the crate price shared over the crate (the pro-rata rule). */
  pricePerPiece?: number | null
}

/** The box price a line uses: its own, else crates per box x the crate price. */
export function effectiveBoxPrice(prices: PackagedPrices, p: EggPackaging): number {
  if (prices.pricePerBox != null && Number.isFinite(Number(prices.pricePerBox))) return Number(prices.pricePerBox)
  return (Number(prices.pricePerCrate) || 0) * (boxSize(p) ?? 0)
}

/** The piece price a line uses: its own, else the crate price over the crate. */
export function effectivePiecePrice(prices: PackagedPrices, p: EggPackaging): number {
  if (prices.pricePerPiece != null && Number.isFinite(Number(prices.pricePerPiece))) return Number(prices.pricePerPiece)
  return (Number(prices.pricePerCrate) || 0) / Math.max(1, whole(p.eggsPerCrate) || 30)
}

/**
 * What a packaged egg line comes to -- the same rule as the database
 * (fnpoultry_eggpackagedamount): boxes x box price + crates x crate price +
 * pieces x piece price, rounded ONCE to the cent. Each part is a different
 * portion of the eggs, so a box is never charged again as crates.
 *
 * With no box or piece price it equals the old rule (eggs / eggs-per-crate x
 * crate price), so a farm that sets neither sees the same totals as before.
 */
export function packagedLineAmount(q: Partial<PackagedQuantity>, prices: PackagedPrices, p: EggPackaging): number {
  const b = Math.max(0, whole(q.boxes)), c = Math.max(0, whole(q.crates)), pc = Math.max(0, whole(q.pieces))
  const crate = Number(prices.pricePerCrate) || 0
  // Each part in cents-precision before the one rounding, so 7 crates at
  // 137.50 does not pick up float noise.
  const amount = b * effectiveBoxPrice(prices, p) + c * crate + pc * effectivePiecePrice(prices, p)
  return Math.round((amount + Number.EPSILON) * 100) / 100
}

// -----------------------------------------------------------------------------
// Posted sale lines (migration 394)
// -----------------------------------------------------------------------------

/** The packaging snapshot a posted sale line carries (all null before 394). */
export interface PostedEggLine {
  quantity: number
  boxes?: number | null
  crates?: number | null
  pieces?: number | null
  eggsPerCrate?: number | null
  cratesPerBox?: number | null
  pricePerBox?: number | null
  pricePerCrate?: number | null
  pricePerPiece?: number | null
}

/**
 * A posted line's egg quantity. A line saved with its packaging (394) is shown
 * exactly as it was entered, with ITS conversion -- never re-read with today's
 * box size. An older line has no packaging: it gets a derived equivalent in
 * today's packaging, and `asEntered` is false so a caller can label it
 * "equivalent" rather than claim boxes were sold.
 */
export function postedLineQuantity(l: PostedEggLine, today: EggPackaging): { text: string; eggs: number; asEntered: boolean } {
  const eggs = whole(l.quantity)
  if (l.crates != null) {
    return { text: formatPackaged({ boxes: l.boxes ?? 0, crates: l.crates, pieces: l.pieces ?? 0 }), eggs, asEntered: true }
  }
  return { text: formatEggQuantity(eggs, today, today.display === "Pieces" ? "CratesPieces" : today.display), eggs, asEntered: false }
}

/** "1 box = 14 crates" -- the conversion a posted line used, or null when it had no boxes. */
export function postedLineConversion(l: PostedEggLine): string | null {
  if (!l.boxes || !l.cratesPerBox) return null
  return `1 box = ${l.cratesPerBox} crates × ${l.eggsPerCrate ?? 30} = ${(l.cratesPerBox * (l.eggsPerCrate ?? 30)).toLocaleString("en-US")} eggs`
}
