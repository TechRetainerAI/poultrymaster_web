// Allocation maths for Water Batch Production (migration 193 — the DB/API name
// is "WaterDailyProduction"; the UI calls it Batch Production).
//
// Reuses the largest-remainder distributors from the poultry batch module —
// they are pure and their exact-sum property is the whole point of the
// reconciliation — but the row shape, the weighting methods and the
// reconciliation rules are water's own.
import { distributeInteger, distributeDecimal } from "@/lib/utils/batch-allocation"
import type {
  WaterAllocationMethod,
  WaterDailyProduction,
  WaterDailyProductionAllocation,
  WaterDailyProductionMachine,
} from "@/lib/api/water"

export { distributeInteger, distributeDecimal }

export type AllocRow = {
  waterMachineId: number
  machineName: string
  capacityPerHour: number
  shift: string | null
  operatorStaffId: number | null
  bagsProduced: number
  looseSachetsProduced: number
  rejectedSachets: number
  damagedBags: number
  packagingRollsUsed: number
  estimatedWaterUsedLitres: number
  electricityCost: number
  fuelCost: number
  laborCost: number
  otherProductionCost: number
  /** waterRawMaterialItemId -> quantity allocated to this machine */
  materialQty: Record<number, number>
  notes: string
  generatedBatchNumber?: string | null
}

export type ReconLine = {
  key: string
  label: string
  dayTotal: number
  allocated: number
  diff: number
  balanced: boolean
  /** Informational only — shown but never blocks posting. */
  info?: boolean
  decimals?: number
  money?: boolean
}

// Mirrors the server tolerances in migration 193's _Post.
const INT_TOL = 0
const QTY_TOL = 0.001
const MONEY_TOL = 0.01

export const METHODS: { value: WaterAllocationMethod; label: string; description: string }[] = [
  { value: "Manual", label: "Manual", description: "Type every machine's numbers yourself." },
  { value: "ByMachineCapacity", label: "By machine capacity", description: "Split in proportion to each machine's bags-per-hour rating." },
  { value: "ByPreviousProduction", label: "By recent output", description: "Split by what each machine actually produced recently; falls back to capacity." },
  { value: "EqualSplit", label: "Equal split", description: "Divide the batch evenly across every machine." },
]

export function blankRow(m: WaterDailyProductionMachine): AllocRow {
  return {
    waterMachineId: m.waterMachineId,
    machineName: m.machineName ?? `Machine #${m.waterMachineId}`,
    capacityPerHour: Number(m.capacityPerHour) || 0,
    shift: null,
    operatorStaffId: m.operatorStaffId ?? null,
    bagsProduced: 0,
    looseSachetsProduced: 0,
    rejectedSachets: 0,
    damagedBags: 0,
    packagingRollsUsed: 0,
    estimatedWaterUsedLitres: 0,
    electricityCost: 0,
    fuelCost: 0,
    laborCost: 0,
    otherProductionCost: 0,
    materialQty: {},
    notes: "",
  }
}

export function buildBlankRows(machines: WaterDailyProductionMachine[]): AllocRow[] {
  return (machines || []).map(blankRow)
}

/** Hydrate the grid from allocation rows already saved on the day record. */
export function allocationsToRows(
  allocations: WaterDailyProductionAllocation[],
  machines: WaterDailyProductionMachine[],
): AllocRow[] {
  const capacityOf = new Map(machines.map((m) => [m.waterMachineId, Number(m.capacityPerHour) || 0]))
  return (allocations || []).map((a) => ({
    waterMachineId: a.waterMachineId,
    machineName: a.machineName ?? `Machine #${a.waterMachineId}`,
    capacityPerHour: capacityOf.get(a.waterMachineId) ?? 0,
    shift: a.shift ?? null,
    operatorStaffId: a.operatorStaffId ?? null,
    bagsProduced: a.bagsProduced || 0,
    looseSachetsProduced: a.looseSachetsProduced || 0,
    rejectedSachets: a.rejectedSachets || 0,
    damagedBags: a.damagedBags || 0,
    packagingRollsUsed: a.packagingRollsUsed || 0,
    estimatedWaterUsedLitres: a.estimatedWaterUsedLitres || 0,
    electricityCost: a.electricityCost || 0,
    fuelCost: a.fuelCost || 0,
    laborCost: a.laborCost || 0,
    otherProductionCost: a.otherProductionCost || 0,
    materialQty: Object.fromEntries((a.materials || []).map((m) => [m.waterRawMaterialItemId, m.quantityAllocated])),
    notes: a.notes ?? "",
    generatedBatchNumber: a.generatedBatchNumber ?? null,
  }))
}

/**
 * Weights for an auto-distribution method.
 * `history` is machineId -> recent average bags, used only by ByPreviousProduction.
 */
export function weightsForMethod(
  method: WaterAllocationMethod,
  rows: AllocRow[],
  history?: Record<number, number>,
): number[] {
  if (method === "EqualSplit") return rows.map(() => 1)
  if (method === "ByMachineCapacity") {
    const w = rows.map((r) => r.capacityPerHour)
    return w.some((x) => x > 0) ? w : rows.map(() => 1)
  }
  if (method === "ByPreviousProduction") {
    const w = rows.map((r) => (history?.[r.waterMachineId] ?? 0))
    if (w.some((x) => x > 0)) return w
    // No history yet — fall back to capacity rather than silently going equal.
    return weightsForMethod("ByMachineCapacity", rows)
  }
  return rows.map(() => 1)
}

/**
 * Distribute the day's totals across the rows.
 *
 * Unlike the poultry equivalent, Manual does NOT blank the grid — re-selecting
 * Manual after hand-editing would otherwise silently destroy the work.
 */
export function applyMethod(
  method: WaterAllocationMethod,
  rows: AllocRow[],
  day: WaterDailyProduction,
  history?: Record<number, number>,
): AllocRow[] {
  if (method === "Manual" || rows.length === 0) return rows

  const w = weightsForMethod(method, rows, history)
  const bags = distributeInteger(day.bagsProduced || 0, w)
  const loose = distributeInteger(day.looseSachetsProduced || 0, w)
  const rejected = distributeInteger(day.rejectedSachets || 0, w)
  const damaged = distributeInteger(day.damagedBags || 0, w)
  const rolls = distributeInteger(day.packagingRollsUsed || 0, w)
  const litres = distributeInteger(day.estimatedWaterUsedLitres || 0, w)
  // dp 2, not the default 3: the server gates these buckets at 0.01 (52712).
  const elec = distributeDecimal(day.electricityCost || 0, w, 2)
  const fuel = distributeDecimal(day.fuelCost || 0, w, 2)
  const labor = distributeDecimal(day.laborCost || 0, w, 2)
  const other = distributeDecimal(day.otherProductionCost || 0, w, 2)

  const perMaterial = new Map<number, number[]>()
  for (const mat of day.materials || []) {
    perMaterial.set(mat.waterRawMaterialItemId, distributeDecimal(mat.quantityUsed || 0, w, 3))
  }

  return rows.map((r, i) => {
    const materialQty: Record<number, number> = {}
    for (const [itemId, parts] of perMaterial) materialQty[itemId] = parts[i] ?? 0
    return {
      ...r,
      bagsProduced: bags[i] ?? 0,
      looseSachetsProduced: loose[i] ?? 0,
      rejectedSachets: rejected[i] ?? 0,
      damagedBags: damaged[i] ?? 0,
      packagingRollsUsed: rolls[i] ?? 0,
      estimatedWaterUsedLitres: litres[i] ?? 0,
      electricityCost: elec[i] ?? 0,
      fuelCost: fuel[i] ?? 0,
      laborCost: labor[i] ?? 0,
      otherProductionCost: other[i] ?? 0,
      materialQty,
    }
  })
}

// ------------------------------------------------------------- row derivations
export const rowGoodBags = (r: AllocRow) => Math.max(0, r.bagsProduced - r.damagedBags)
export const rowTotalSachets = (r: AllocRow, sachetsPerBag: number) =>
  r.bagsProduced * (sachetsPerBag || 0) + r.looseSachetsProduced
export const rowProductionCost = (r: AllocRow) =>
  r.electricityCost + r.fuelCost + r.laborCost + r.otherProductionCost

/** Preview material cost. Re-priced from the lots at posting. */
export function rowMaterialCost(r: AllocRow, day: WaterDailyProduction): number {
  let total = 0
  for (const mat of day.materials || []) {
    const qty = r.materialQty[mat.waterRawMaterialItemId] || 0
    total += qty * (Number(mat.unitCost) || 0)
  }
  return total
}

export const rowAllInCost = (r: AllocRow, day: WaterDailyProduction) =>
  rowProductionCost(r) + rowMaterialCost(r, day)

export function rowCostPerBag(r: AllocRow, day: WaterDailyProduction): number {
  const good = rowGoodBags(r)
  return good > 0 ? rowAllInCost(r, day) / good : 0
}

/** Day cost per bag is SUM(allIn) / SUM(goodBags) — never the mean of the rows. */
export function dayCostPerBag(rows: AllocRow[], day: WaterDailyProduction): number {
  const good = rows.reduce((s, r) => s + rowGoodBags(r), 0)
  if (good <= 0) return 0
  return rows.reduce((s, r) => s + rowAllInCost(r, day), 0) / good
}

/** Per-row problems the server would reject (52705/52706), surfaced inline. */
export function rowErrors(r: AllocRow, sachetsPerBag: number): string[] {
  const errs: string[] = []
  if (r.bagsProduced < 0 || r.damagedBags < 0 || r.rejectedSachets < 0 || r.looseSachetsProduced < 0) {
    errs.push("Quantities cannot be negative")
  }
  if (r.damagedBags > r.bagsProduced) errs.push("Damaged bags exceed bags produced")
  if (r.rejectedSachets > rowTotalSachets(r, sachetsPerBag)) errs.push("Rejected sachets exceed sachets produced")
  return errs
}

/**
 * Reconciliation footer.
 *
 * Output AND cost-bucket lines block posting — unlike poultry, where money is
 * informational. On water each bucket becomes a real WaterExpenses row per
 * child batch, so an under-allocated bucket under-books the day's expenses.
 * Material COST lines stay informational: the lot draw re-prices them at
 * approve, so the preview figure on both sides is provisional.
 */
export function buildReconciliation(
  rows: AllocRow[],
  day: WaterDailyProduction,
): { lines: ReconLine[]; balanced: boolean } {
  const sum = (fn: (r: AllocRow) => number) => rows.reduce((s, r) => s + fn(r), 0)
  const lines: ReconLine[] = []

  const push = (
    key: string, label: string, dayTotal: number, allocated: number,
    tol: number, extra: Partial<ReconLine> = {},
  ) => {
    const diff = allocated - dayTotal
    lines.push({ key, label, dayTotal, allocated, diff, balanced: Math.abs(diff) <= tol, ...extra })
  }

  push("bags", "Bags Produced", day.bagsProduced || 0, sum((r) => r.bagsProduced), INT_TOL)
  push("loose", "Loose Sachets", day.looseSachetsProduced || 0, sum((r) => r.looseSachetsProduced), INT_TOL)
  push("rejected", "Rejected Sachets", day.rejectedSachets || 0, sum((r) => r.rejectedSachets), INT_TOL)
  push("damaged", "Damaged Bags", day.damagedBags || 0, sum((r) => r.damagedBags), INT_TOL)
  push("rolls", "Packaging Rolls", day.packagingRollsUsed || 0, sum((r) => r.packagingRollsUsed), INT_TOL)
  // The server skips this line when the day header leaves litres blank.
  if (day.estimatedWaterUsedLitres != null) {
    push("litres", "Water Used (L)", day.estimatedWaterUsedLitres, sum((r) => r.estimatedWaterUsedLitres), INT_TOL)
  }

  push("elec", "Electricity", day.electricityCost || 0, sum((r) => r.electricityCost), MONEY_TOL, { money: true })
  push("fuel", "Fuel", day.fuelCost || 0, sum((r) => r.fuelCost), MONEY_TOL, { money: true })
  push("labor", "Labor", day.laborCost || 0, sum((r) => r.laborCost), MONEY_TOL, { money: true })
  push("other", "Other Production Cost", day.otherProductionCost || 0, sum((r) => r.otherProductionCost), MONEY_TOL, { money: true })

  for (const mat of day.materials || []) {
    push(
      `mat-${mat.waterRawMaterialItemId}`,
      `${mat.itemName || "Material"}${mat.unitOfMeasure ? ` (${mat.unitOfMeasure})` : ""}`,
      mat.quantityUsed || 0,
      sum((r) => r.materialQty[mat.waterRawMaterialItemId] || 0),
      QTY_TOL,
      { decimals: 3 },
    )
  }

  push("matCost", "Raw Material Cost", day.rawMaterialCost || 0, sum((r) => rowMaterialCost(r, day)),
       MONEY_TOL, { money: true, info: true })

  const balanced = lines.filter((l) => !l.info).every((l) => l.balanced)
  return { lines, balanced }
}

/** Shape the grid into the payload the save/post endpoints expect. */
export function rowsToAllocations(
  rows: AllocRow[],
  day: WaterDailyProduction,
  method: WaterAllocationMethod,
): WaterDailyProductionAllocation[] {
  const matMeta = new Map((day.materials || []).map((m) => [m.waterRawMaterialItemId, m]))
  const perBag = (itemId: number) =>
    (day.bagsProduced || 0) > 0 ? (matMeta.get(itemId)?.expectedQuantityUsed ?? 0) / day.bagsProduced : 0

  return rows.map((r) => ({
    waterMachineId: r.waterMachineId,
    machineName: r.machineName,
    allocationMethod: method,
    shift: r.shift,
    operatorStaffId: r.operatorStaffId,
    bagsProduced: r.bagsProduced,
    looseSachetsProduced: r.looseSachetsProduced,
    rejectedSachets: r.rejectedSachets,
    damagedBags: r.damagedBags,
    packagingRollsUsed: r.packagingRollsUsed,
    estimatedWaterUsedLitres: r.estimatedWaterUsedLitres,
    electricityCost: r.electricityCost,
    fuelCost: r.fuelCost,
    laborCost: r.laborCost,
    otherProductionCost: r.otherProductionCost,
    rawMaterialCost: rowMaterialCost(r, day),
    notes: r.notes || null,
    materials: Object.entries(r.materialQty)
      .map(([id, qty]) => ({ id: Number(id), qty: Number(qty) || 0 }))
      .filter((x) => x.qty > 0)
      .map((x) => ({
        waterDailyProductionMaterialId: matMeta.get(x.id)?.waterDailyProductionMaterialId ?? null,
        waterRawMaterialItemId: x.id,
        itemName: matMeta.get(x.id)?.itemName ?? null,
        quantityAllocated: x.qty,
        // Expected is recomputed per row from the recipe rate, NOT distributed
        // by weight: the recipe is linear in bags, and that is what the operator
        // compares actual usage against. WaterRawMaterialUsage.Variance depends
        // on this being the per-row expectation.
        expectedQuantityAllocated: Number((perBag(x.id) * r.bagsProduced).toFixed(3)),
        unitCost: matMeta.get(x.id)?.unitCost ?? null,
      })),
  }))
}
