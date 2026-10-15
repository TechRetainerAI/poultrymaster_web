// 372-374: Broken Eggs and Dead Birds are system products with their own stock.
//
// Sales still name their product in text, and much of the app sorts sales by
// that text ("...egg..." = eggs, "...bird..." = live birds). These two names
// must never fall into either: a Broken Eggs sale is not an egg sale and a
// Dead Birds sale does not take live birds. The server applies the same test
// (fnpoultrysale_byproductrole), so the two cannot disagree.

export type ByproductRole = "BrokenEggs" | "DeadBirds"

export const BYPRODUCT_NAME: Record<ByproductRole, string> = {
  BrokenEggs: "Broken Eggs",
  DeadBirds: "Dead Birds",
}

/** "Broken Eggs" / "Dead Birds" (or their "(system)" names) -> the role; anything else null. */
export function byproductRole(product: string | null | undefined): ByproductRole | null {
  switch ((product ?? "").trim().toLowerCase()) {
    case "broken eggs":
    case "broken eggs (system)":
      return "BrokenEggs"
    case "dead birds":
    case "dead birds (system)":
      return "DeadBirds"
    default:
      return null
  }
}

export const isByproduct = (product: string | null | undefined) => byproductRole(product) != null
