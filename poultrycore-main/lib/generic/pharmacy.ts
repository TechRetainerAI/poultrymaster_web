// Pharmacy rules shared by the pharmacy pages (migration 515). Pure functions, unit-tested
// in pharmacy.test.ts.
//
// Ghana's classes of medicine:
//   A = Prescription only (POM)      - pharmacy only, with a prescription
//   B = Pharmacy medicine (P)        - pharmacy only, a pharmacist must supervise the sale
//   C = Over the counter (OTC)       - any licensed seller, including a chemical shop
// A chemical shop (licensed over-the-counter medicine seller) may sell Class C only.

import type { Medicine, MedicineClass, PharmacyShopType, ProductPack } from "@/lib/api/generic-pharmacy"

export const MEDICINE_CLASSES: { value: MedicineClass; label: string; short: string; hint: string }[] = [
  { value: "A", label: "Class A: prescription only", short: "Rx only", hint: "Sold only by a pharmacy, against a prescription." },
  { value: "B", label: "Class B: pharmacy medicine", short: "Pharmacy", hint: "Sold only by a pharmacy, with a pharmacist supervising." },
  { value: "C", label: "Class C: over the counter", short: "OTC", hint: "Any licensed seller, including a chemical shop." },
]

export const DOSAGE_FORMS = [
  "Tablet", "Capsule", "Caplet", "Syrup", "Suspension", "Injection", "Cream", "Ointment", "Gel",
  "Drops", "Inhaler", "Suppository", "Powder", "Sachet", "Lozenge", "Spray", "Device / supply", "Other",
]

export const SHOP_TYPES: { value: PharmacyShopType; label: string; hint: string }[] = [
  { value: "Pharmacy", label: "Pharmacy", hint: "Registered pharmacy: sells Class A, B and C medicines." },
  { value: "ChemicalShop", label: "Chemical shop (OTC medicine seller)", hint: "Sells Class C (over-the-counter) medicines only." },
]

/** Why this shop may not sell this medicine, or null when it may. */
export function sellBlockReason(shopType: PharmacyShopType, cls: MedicineClass | null | undefined): string | null {
  if (shopType === "ChemicalShop" && (cls === "A" || cls === "B")) {
    return `A chemical shop may sell over-the-counter (Class C) medicines only. This is a Class ${cls} medicine.`
  }
  return null
}

/** A sale unit at the till: the base unit (tablet) or one of the packs. */
export interface SellUnit {
  unit: string
  /** Base units in one of this unit. */
  factor: number
  price: number
}

/** The units a medicine can be sold in, smallest first: base unit, then packs. */
export function sellUnits(m: Pick<Medicine, "baseUnit" | "sellingPrice" | "packs">): SellUnit[] {
  const out: SellUnit[] = [{ unit: m.baseUnit || "unit", factor: 1, price: Number(m.sellingPrice) || 0 }]
  for (const p of [...(m.packs ?? [])].sort((a, b) => a.unitsPerPack - b.unitsPerPack)) {
    if (!p.packName || !(p.unitsPerPack > 0)) continue
    if (out.some((o) => o.unit.toLowerCase() === p.packName.toLowerCase())) continue
    out.push({ unit: p.packName, factor: Number(p.unitsPerPack), price: Number(p.sellingPrice) || 0 })
  }
  return out
}

/** Stock that may be sold: what is on hand minus what sits in expired batches. */
export function sellableStock(m: Pick<Medicine, "currentStock" | "expiredQty">): number {
  return Math.max(0, (Number(m.currentStock) || 0) - (Number(m.expiredQty) || 0))
}

/** Problems with a pack list before it is saved (empty list = fine). */
export function packProblems(baseUnit: string, packs: ProductPack[]): string[] {
  const out: string[] = []
  const seen = new Set<string>()
  for (const p of packs) {
    const name = (p.packName ?? "").trim()
    if (!name) continue
    const key = name.toLowerCase()
    if (key === (baseUnit || "").trim().toLowerCase()) out.push(`"${name}" is the base unit; a pack needs another name.`)
    if (seen.has(key)) out.push(`"${name}" is listed twice.`)
    seen.add(key)
    if (!(Number(p.unitsPerPack) > 0)) out.push(`Say how many ${baseUnit || "units"} are in one ${name}.`)
    if (Number(p.sellingPrice) < 0) out.push(`The price of a ${name} cannot be below zero.`)
  }
  return out
}

export type ExpiryState = "expired" | "soon" | "ok" | "none"

export function expiryState(expiryDate: string | null | undefined, warningDays: number, today = new Date()): ExpiryState {
  if (!expiryDate) return "none"
  const d = new Date(`${String(expiryDate).slice(0, 10)}T00:00:00`)
  const t = new Date(today.getFullYear(), today.getMonth(), today.getDate())
  const days = Math.round((d.getTime() - t.getTime()) / 86_400_000)
  if (days < 0) return "expired"
  if (days <= warningDays) return "soon"
  return "ok"
}

/** "2 Box + 3 Strip + 4 tablet" for a quantity in base units. */
export function describeQty(qty: number, units: SellUnit[]): string {
  let left = Math.round((Number(qty) || 0) * 1000) / 1000
  if (left <= 0) return `0 ${units[0]?.unit ?? ""}`.trim()
  const parts: string[] = []
  for (const u of [...units].sort((a, b) => b.factor - a.factor)) {
    if (u.factor <= 0) continue
    const n = u.factor === 1 ? left : Math.floor(left / u.factor + 1e-9)
    if (n > 0) {
      parts.push(`${Math.round(n * 1000) / 1000} ${u.unit}`)
      left = Math.round((left - n * u.factor) * 1000) / 1000
    }
    if (left <= 0) break
  }
  return parts.join(" + ")
}
