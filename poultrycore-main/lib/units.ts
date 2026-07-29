// Units of measure offered for raw-material items, purchases and feed formulas.
// Kept in one place so a formula's unit list matches the inventory it draws on.
export const RAW_MATERIAL_UNITS = [
  "Bag", "Sack", "Tonne", "Kilogram", "Gram", "Litre", "Millilitre", "Bottle",
  "Sachet", "Piece", "Pack", "Carton", "Box", "Bundle", "Dozen", "Crate", "Unit", "Other",
]

// The standard list, with whatever the record already holds pinned to the front
// so editing an older row never silently drops its unit.
export function unitOptions(current?: string | null): string[] {
  const set = [...RAW_MATERIAL_UNITS]
  const c = (current ?? "").trim()
  if (c && !set.includes(c)) set.unshift(c)
  return set
}
