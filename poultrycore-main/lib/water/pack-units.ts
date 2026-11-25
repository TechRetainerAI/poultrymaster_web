// The words a water product uses for its package and its single unit, so
// production and stock screens say "Packs" / "Bottles per pack" for a bottle
// product instead of the sachet-era "Bags" / "Sachets per bag".
//
// packagingUnit = the package (Bag, Pack, Carton…), baseUnit/unit = the single
// item (Sachet, Bottle…), sachetsPerBag = how many singles in one package.

type PackSource = {
  packagingUnit?: string | null
  baseUnit?: string | null
  unit?: string | null
  sachetsPerBag?: number | null
} | null | undefined

export type PackWords = {
  /** "Pack" */ pack: string
  /** "Packs" */ packs: string
  /** "Bottle" */ single: string
  /** "Bottles" */ singles: string
}

const cap = (s: string) => (s ? s.charAt(0).toUpperCase() + s.slice(1) : s)
const plural = (s: string) => (/s$/i.test(s) ? s : /(x|ch|sh)$/i.test(s) ? `${s}es` : `${s}s`)

export function packWords(p: PackSource): PackWords {
  const pack = cap((p?.packagingUnit ?? "").trim()) || "Bag"
  const single = cap((p?.baseUnit ?? p?.unit ?? "").trim()) || "Sachet"
  return { pack, packs: plural(pack), single, singles: plural(single) }
}

/** The product's own units-per-package, or null when it has none set. */
export function productPackSize(p: PackSource): number | null {
  const n = Number(p?.sachetsPerBag ?? 0)
  return n > 0 ? n : null
}
