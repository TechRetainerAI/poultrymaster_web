import { getAuthHeaders } from './config'

// Doc §4a-4c: attach feed/medication consumption + costing to a create/update
// payload. All optional — omitted/null when the user didn't pick feed/medication.
/**
 * The sentence to show when the API refuses a save -- never the raw response.
 *
 * A refusal arrives either as a 400 with { message } (e.g. 372's byproduct
 * guard) or as a 500 from GlobalExceptionMiddleware wrapping a database RAISE
 * ({ errorType: "SqlException", sqlState: "P0001" / "P0010", message }). Both
 * carry a message written for the user ("… already has a production record for
 * 15 Oct 2026. Edit that record instead …"). Any other failure -- a crash, an
 * HTML error page, a non-JSON body -- gets the plain fallback.
 */
function refusalMessage(status: number, errorText: string, fallback: string): string {
  let body: any = null
  try { body = JSON.parse(errorText) } catch {}
  const message = typeof body?.message === "string" ? body.message.trim() : ""
  if (message) {
    // A RAISE from our own functions (SQLSTATE class P0) is written for the user.
    const raised = typeof body?.sqlState === "string" && body.sqlState.startsWith("P0")
    if (status === 400 || raised) return message
  }
  // A plain-text 400 is the API's own wording; anything else is not for the user.
  if (status === 400 && errorText && !body && !errorText.trim().startsWith("<")) return errorText.trim()
  return fallback
}

function attachCosting(payload: any, record: ProductionRecordInput) {
  payload.specificFeedUsedId = record.specificFeedUsedId ?? null
  payload.specificFeedUsedName = record.specificFeedUsedName ?? null
  payload.feedUnitCost = record.feedUnitCost ?? null
  payload.totalFeedConsumed = record.totalFeedConsumed ?? null
  payload.totalFeedCost = record.totalFeedCost ?? null
  payload.specificMedicationUsedId = record.specificMedicationUsedId ?? null
  payload.specificMedicationUsedName = record.specificMedicationUsedName ?? null
  payload.medicationUnitCost = record.medicationUnitCost ?? null
  payload.totalMedicationConsumed = record.totalMedicationConsumed ?? null
  payload.totalMedicationCost = record.totalMedicationCost ?? null
  payload.totalCostOfProduction = record.totalCostOfProduction ?? null
  // Migration 147: multiple medication lines. Send the array (even empty) so the
  // backend derives the aggregate medication columns from it; omit (null) only
  // when the caller doesn't manage lines, in which case the single-medication
  // fields above are used as the sole line.
  payload.medications = record.medications ?? null
  // Migration 148: multiple feed lines — same contract as medications.
  payload.feeds = record.feeds ?? null
}

/** One medication line drawn from raw-material inventory (migration 147). */
export interface ProductionMedicationLine {
  specificMedicationUsedId: number | null
  specificMedicationUsedName?: string | null
  totalMedicationConsumed: number | null
  medicationUnitCost?: number | null
  totalMedicationCost?: number | null
}

/** One feed line drawn from raw-material inventory (migration 148). */
export interface ProductionFeedLine {
  specificFeedUsedId: number | null
  specificFeedUsedName?: string | null
  totalFeedConsumed: number | null
  feedUnitCost?: number | null
  totalFeedCost?: number | null
}

/** 372: what happens to a record's dead birds / broken eggs. */
export type ByproductDisposition = "Keep" | "Disposed"

export interface ProductionRecord {
  id: number
  farmId: string
  userId: string
  createdBy: string
  updatedBy: string
  ageInWeeks: number
  ageInDays: number
  date: string
  noOfBirds: number
  mortality: number
  noOfBirdsLeft: number
  feedKg: number
  medication: string
  production9AM: number
  production12PM: number
  production4PM: number
  /** 4th egg pick (migration 152). 1st/2nd/3rd picks reuse the 9AM/12PM/4PM fields. */
  production4thPick?: number
  /** 5th and 6th picks (migration 249), for farms collecting more than four
   *  times a day. Offered on the form only when the farm enables them. */
  production5thPick?: number
  production6thPick?: number
  brokenEggs: number
  /** 372: Keep (into Dead Birds / Broken Eggs stock) or Disposed immediately. */
  mortalityDisposition?: ByproductDisposition
  brokenEggDisposition?: ByproductDisposition
  /** 386: how many broken eggs were disposed at once; the rest go to Broken Eggs
   *  stock. Wins over brokenEggDisposition. Absent from an older API. */
  brokenEggsDisposed?: number | null
  /** 387: the same for the dead birds. Wins over mortalityDisposition. */
  mortalityDisposed?: number | null
  totalProduction: number
  /** Free-text notes for the production entry. */
  notes?: string | null
  createdAt: string
  updatedAt: string
  flockId?: number | null
  flockName?: string
  /** Egg size grade (e.g. Small, Medium). */
  eggGrade?: string | null
  /** Eggs lost as "meaty" (yolk/blood spot). Added by migration 018. */
  meatyEggs?: number | null
  /** Eggs lost as "soft" (thin/no shell). Added by migration 018. */
  softEggs?: number | null
  /** Eggs lost (missing/dropped). Added by migration 018. */
  lostEggs?: number | null
  // Doc §4a-4c: feed/medication consumed from raw-material inventory + costing.
  specificFeedUsedId?: number | null
  specificFeedUsedName?: string | null
  feedUnitCost?: number | null
  totalFeedConsumed?: number | null
  totalFeedCost?: number | null
  specificMedicationUsedId?: number | null
  specificMedicationUsedName?: string | null
  medicationUnitCost?: number | null
  totalMedicationConsumed?: number | null
  totalMedicationCost?: number | null
  totalCostOfProduction?: number | null
  /** Migration 147: individual medication lines (each drawn from inventory). */
  medications?: ProductionMedicationLine[] | null
  /** Migration 148: individual feed lines (each drawn from inventory). */
  feeds?: ProductionFeedLine[] | null
  /** 389: ManualSingleFlock | BatchAllocation | FeedUsage (feed recorded, production not filled in yet). */
  sourceType?: string | null
}

export interface ProductionRecordInput {
  farmId: string
  userId: string
  createdBy: string
  updatedBy: string
  ageInWeeks: number
  ageInDays: number
  date: string
  noOfBirds: number
  mortality: number
  noOfBirdsLeft: number
  feedKg: number
  medication: string
  production9AM: number
  production12PM: number
  production4PM: number
  /** 4th egg pick (migration 152). 1st/2nd/3rd picks reuse the 9AM/12PM/4PM fields. */
  production4thPick?: number
  /** 5th and 6th picks (migration 249), for farms collecting more than four
   *  times a day. Offered on the form only when the farm enables them. */
  production5thPick?: number
  production6thPick?: number
  brokenEggs: number
  /** 372: Keep (into Dead Birds / Broken Eggs stock) or Disposed immediately. */
  mortalityDisposition?: ByproductDisposition
  brokenEggDisposition?: ByproductDisposition
  /** 386: how many broken eggs were disposed at once; the rest go to Broken Eggs
   *  stock. Wins over brokenEggDisposition. Absent from an older API. */
  brokenEggsDisposed?: number | null
  /** 387: the same for the dead birds. Wins over mortalityDisposition. */
  mortalityDisposed?: number | null
  totalProduction: number
  /** Free-text notes for the production entry. */
  notes?: string | null
  flockId?: number | null
  eggGrade?: string | null
  meatyEggs?: number | null
  softEggs?: number | null
  lostEggs?: number | null
  // Doc §4a-4c: feed/medication consumed from raw-material inventory + costing.
  specificFeedUsedId?: number | null
  specificFeedUsedName?: string | null
  feedUnitCost?: number | null
  totalFeedConsumed?: number | null
  totalFeedCost?: number | null
  specificMedicationUsedId?: number | null
  specificMedicationUsedName?: string | null
  medicationUnitCost?: number | null
  totalMedicationConsumed?: number | null
  totalMedicationCost?: number | null
  totalCostOfProduction?: number | null
  /** Migration 147: individual medication lines (each drawn from inventory). */
  medications?: ProductionMedicationLine[] | null
  /** Migration 148: individual feed lines (each drawn from inventory). */
  feeds?: ProductionFeedLine[] | null
  /** 389: send on save from the production form, so a feed-only record becomes production. */
  markRecorded?: boolean
}

/**
 * An existing record as a complete update payload.
 *
 * The update is a full PUT, so a caller that only means to change a few fields
 * (the egg picks, say) must still send everything else, or the API receives the
 * rest as blanks. Start from this and override just the fields being changed.
 */
export function productionRecordToInput(record: ProductionRecord, updatedBy: string): ProductionRecordInput {
  return {
    farmId: record.farmId,
    userId: record.userId,
    createdBy: record.createdBy,
    updatedBy,
    ageInWeeks: record.ageInWeeks,
    ageInDays: record.ageInDays,
    date: record.date,
    noOfBirds: record.noOfBirds,
    mortality: record.mortality,
    noOfBirdsLeft: record.noOfBirdsLeft,
    feedKg: record.feedKg,
    medication: record.medication,
    production9AM: record.production9AM,
    production12PM: record.production12PM,
    production4PM: record.production4PM,
    production4thPick: record.production4thPick,
    production5thPick: record.production5thPick,
    production6thPick: record.production6thPick,
    brokenEggs: record.brokenEggs,
    mortalityDisposition: record.mortalityDisposition,
    brokenEggDisposition: record.brokenEggDisposition,
    brokenEggsDisposed: record.brokenEggsDisposed,
    mortalityDisposed: record.mortalityDisposed,
    totalProduction: record.totalProduction,
    notes: record.notes ?? null,
    flockId: record.flockId ?? null,
    eggGrade: record.eggGrade ?? null,
    meatyEggs: record.meatyEggs ?? null,
    softEggs: record.softEggs ?? null,
    lostEggs: record.lostEggs ?? null,
    specificFeedUsedId: record.specificFeedUsedId ?? null,
    specificFeedUsedName: record.specificFeedUsedName ?? null,
    feedUnitCost: record.feedUnitCost ?? null,
    totalFeedConsumed: record.totalFeedConsumed ?? null,
    totalFeedCost: record.totalFeedCost ?? null,
    specificMedicationUsedId: record.specificMedicationUsedId ?? null,
    specificMedicationUsedName: record.specificMedicationUsedName ?? null,
    medicationUnitCost: record.medicationUnitCost ?? null,
    totalMedicationConsumed: record.totalMedicationConsumed ?? null,
    totalMedicationCost: record.totalMedicationCost ?? null,
    totalCostOfProduction: record.totalCostOfProduction ?? null,
    medications: record.medications ?? null,
    feeds: record.feeds ?? null,
  }
}

/**
 * Change a few fields on an existing record without blanking the rest.
 *
 * Re-reads the record singly (the list rows may not carry the feed and
 * medication lines), copies it whole, applies `changes` and saves. If the
 * single read fails, `existing` is used as the base instead.
 */
export async function patchProductionRecord(
  existing: ProductionRecord,
  userId: string,
  farmId: string,
  changes: Partial<ProductionRecordInput>,
) {
  const full = await getProductionRecord(existing.id, userId, farmId)
  const base = productionRecordToInput(full.success && full.data ? full.data : existing, userId)
  return updateProductionRecord(existing.id, { ...base, ...changes, updatedBy: userId })
}

// Mock data for development
const mockProductionRecords: ProductionRecord[] = [
  {
    id: 1,
    farmId: "farm-1",
    userId: "user-1",
    createdBy: "user-1",
    updatedBy: "user-1",
    ageInWeeks: 20,
    ageInDays: 140,
    date: new Date().toISOString(),
    noOfBirds: 100,
    mortality: 2,
    noOfBirdsLeft: 98,
    feedKg: 25.5,
    medication: "None",
    production9AM: 45,
    production12PM: 52,
    production4PM: 48,
    brokenEggs: 0,
    totalProduction: 145,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    flockId: null,
  },
  {
    id: 2,
    farmId: "farm-1",
    userId: "user-1",
    createdBy: "user-1",
    updatedBy: "user-1",
    ageInWeeks: 21,
    ageInDays: 147,
    date: new Date(Date.now() - 86400000).toISOString(), // Yesterday
    noOfBirds: 98,
    mortality: 1,
    noOfBirdsLeft: 97,
    feedKg: 24.0,
    medication: "Vitamin supplement",
    production9AM: 42,
    production12PM: 49,
    production4PM: 46,
    brokenEggs: 0,
    totalProduction: 137,
    createdAt: new Date(Date.now() - 86400000).toISOString(),
    updatedAt: new Date(Date.now() - 86400000).toISOString(),
    flockId: null,
  },
]

let nextRecordId = 3

export async function getProductionRecords(userId: string, farmId: string) {
  try {
    // Use proxy to avoid CORS issues
    const url = `/api/proxy/ProductionRecord?userId=${encodeURIComponent(userId)}&farmId=${encodeURIComponent(farmId)}`
    console.log("[v0] Fetching production records:", url)

    const response = await fetch(url, {
      method: "GET",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
    })

    console.log("[v0] Production records response status:", response.status)

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] Production records fetch error:", errorText)
      
      // Return error instead of mock data
      return {
        success: false,
        message: `Failed to fetch production records: ${response.status} - ${errorText || 'Server error'}`,
        data: [],
      }
    }

    const contentType = response.headers.get("content-type")
    if (!contentType || !contentType.includes("application/json")) {
      console.error("[v0] Non-JSON response received")
      
      return {
        success: false,
        message: "Invalid response from server (non-JSON)",
        data: [],
      }
    }

    const data = await response.json()
    console.log("[v0] Production records data received:", data)

    return {
      success: true,
      message: "Production records fetched successfully",
      data: data as ProductionRecord[],
    }
  } catch (error) {
    console.error("[v0] Production records fetch error:", error)
    
    // Return error instead of mock data
    const errorMessage = error instanceof Error ? error.message : 'Network error'
    return {
      success: false,
      message: `Failed to connect to server: ${errorMessage}. Please check if the API is running and CORS is configured.`,
      data: [],
    }
  }
}

export async function getProductionRecord(id: number, userId: string, farmId: string) {
  try {
    // Use proxy to avoid CORS issues
    const url = `/api/proxy/ProductionRecord/${id}?userId=${encodeURIComponent(userId)}&farmId=${encodeURIComponent(farmId)}`
    console.log("[v0] Fetching production record:", url)

    const response = await fetch(url, {
      method: "GET",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
    })

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] Production record fetch error:", errorText)
      
      return {
        success: false,
        message: `Failed to fetch production record: ${response.status} - ${errorText || 'Server error'}`,
        data: null,
      }
    }

    const data = await response.json()
    return {
      success: true,
      message: "Production record fetched successfully",
      data: data as ProductionRecord,
    }
  } catch (error) {
    console.error("[v0] Production record fetch error:", error)
    
    const errorMessage = error instanceof Error ? error.message : 'Network error'
    return {
      success: false,
      message: `Failed to connect to server: ${errorMessage}`,
      data: null,
    }
  }
}

export async function createProductionRecord(record: ProductionRecordInput) {
  try {
    // Use proxy to avoid CORS issues
    const url = `/api/proxy/ProductionRecord`
    console.log("[v0] Creating production record:", url)

    // Only send fields expected by the SP (omit id/createdAt/updatedAt)
    const payload: any = {
      farmId: record.farmId,
      userId: record.userId,
      createdBy: record.createdBy,
      updatedBy: record.updatedBy,
      ageInWeeks: record.ageInWeeks,
      ageInDays: record.ageInDays,
      date: record.date,
      noOfBirds: record.noOfBirds,
      mortality: record.mortality,
      noOfBirdsLeft: record.noOfBirdsLeft,
      feedKg: record.feedKg,
      medication: record.medication,
      production9AM: record.production9AM,
      production12PM: record.production12PM,
      production4PM: record.production4PM,
      production4thPick: record.production4thPick ?? 0,
      production5thPick: record.production5thPick ?? 0,
      production6thPick: record.production6thPick ?? 0,
      brokenEggs: record.brokenEggs ?? 0,
      totalProduction: record.totalProduction,
    }
    if (record.flockId !== undefined) payload.FlockId = record.flockId
    payload.eggGrade = record.eggGrade?.trim() ? record.eggGrade.trim() : null
    payload.meatyEggs = record.meatyEggs ?? null
    payload.softEggs = record.softEggs ?? null
    payload.lostEggs = record.lostEggs ?? null
    payload.notes = record.notes ?? null
    if (record.mortalityDisposition) payload.mortalityDisposition = record.mortalityDisposition
    if (record.brokenEggDisposition) payload.brokenEggDisposition = record.brokenEggDisposition
    if (record.brokenEggsDisposed != null) payload.brokenEggsDisposed = record.brokenEggsDisposed
    if (record.mortalityDisposed != null) payload.mortalityDisposed = record.mortalityDisposed
    attachCosting(payload, record)

    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify(payload),
    })

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] Production record create error:", errorText)
      // SECURITY: Removed mock data modification - no client-side data creation
      // All data operations must go through backend for proper validation and security
      return {
        success: false,
        message: refusalMessage(response.status, errorText, "Could not save the production record. Please check the details and try again."),
      }
    }

    // Accept 204/No Content as success
    if (response.status === 204) {
      return { success: true, message: "Production record created successfully" }
    }

    // Some APIs return created entity; tolerate non-JSON
    const ct = response.headers.get("content-type") || ""
    if (!ct.includes("application/json")) {
      return { success: true, message: "Production record created successfully" }
    }

    await response.json().catch(() => null)
    return {
      success: true,
      message: "Production record created successfully",
    }
  } catch (error) {
    console.error("[v0] Production record create error:", error)
    // SECURITY: Removed mock data modification - no client-side data creation
    return {
      success: false,
      message: "Network error. Please try again.",
    }
  }
}

export async function updateProductionRecord(id: number, record: ProductionRecordInput) {
  try {
    // Use proxy to avoid CORS issues
    const url = `/api/proxy/ProductionRecord/${id}`
    console.log("[v0] Updating production record:", url)

    const payload: any = {
      id,
      farmId: record.farmId,
      userId: record.userId,
      createdBy: record.createdBy,
      updatedBy: record.updatedBy,
      ageInWeeks: record.ageInWeeks,
      ageInDays: record.ageInDays,
      date: record.date,
      noOfBirds: record.noOfBirds,
      mortality: record.mortality,
      noOfBirdsLeft: record.noOfBirdsLeft,
      feedKg: record.feedKg,
      medication: record.medication,
      production9AM: record.production9AM,
      production12PM: record.production12PM,
      production4PM: record.production4PM,
      production4thPick: record.production4thPick ?? 0,
      production5thPick: record.production5thPick ?? 0,
      production6thPick: record.production6thPick ?? 0,
      brokenEggs: record.brokenEggs ?? 0,
      totalProduction: record.totalProduction,
    }
    if (record.flockId !== undefined) payload.FlockId = record.flockId
    if (Object.prototype.hasOwnProperty.call(record, "eggGrade")) {
      payload.eggGrade = record.eggGrade?.trim() ? record.eggGrade.trim() : null
    }
    if (Object.prototype.hasOwnProperty.call(record, "meatyEggs")) payload.meatyEggs = record.meatyEggs ?? null
    if (Object.prototype.hasOwnProperty.call(record, "softEggs")) payload.softEggs = record.softEggs ?? null
    if (Object.prototype.hasOwnProperty.call(record, "lostEggs")) payload.lostEggs = record.lostEggs ?? null
    if (Object.prototype.hasOwnProperty.call(record, "notes")) payload.notes = record.notes ?? null
    if (record.mortalityDisposition) payload.mortalityDisposition = record.mortalityDisposition
    if (record.brokenEggDisposition) payload.brokenEggDisposition = record.brokenEggDisposition
    if (record.brokenEggsDisposed != null) payload.brokenEggsDisposed = record.brokenEggsDisposed
    if (record.mortalityDisposed != null) payload.mortalityDisposed = record.mortalityDisposed
    // 389: the production form completed a feed-only (Feed Usage) record.
    if (record.markRecorded) payload.markRecorded = true
    attachCosting(payload, record)

    const response = await fetch(url, {
      method: "PUT",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify(payload),
    })

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] Production record update error:", errorText)
      return {
        success: false,
        message: refusalMessage(response.status, errorText, "Could not save the changes to this production record. Please try again."),
      }
    }

    if (response.status === 204) {
      return { success: true, message: "Production record updated successfully" }
    }

    const ct = response.headers.get("content-type") || ""
    if (!ct.includes("application/json")) {
      return { success: true, message: "Production record updated successfully" }
    }

    await response.json().catch(() => null)
    return {
      success: true,
      message: "Production record updated successfully",
    }
  } catch (error) {
    console.error("[v0] Production record update error:", error)
    return {
      success: false,
      message: "Failed to update production record",
    }
  }
}

export async function deleteProductionRecord(id: number, userId: string, farmId: string) {
  try {
    // SECURITY: Validate required parameters before proceeding
    if (!userId || !farmId) {
      console.error("[v0] Security: Missing userId or farmId for production record deletion")
      return {
        success: false,
        message: "Authorization required. Please log in again.",
      }
    }
    
    if (!id || !Number.isFinite(id) || id <= 0) {
      console.error("[v0] Security: Invalid production record ID")
      return {
        success: false,
        message: "Invalid production record ID",
      }
    }
    
    // Use proxy to avoid CORS issues
    const url = `/api/proxy/ProductionRecord/${id}?userId=${encodeURIComponent(userId)}&farmId=${encodeURIComponent(farmId)}`
    console.log("[v0] Deleting production record:", url)

    const response = await fetch(url, {
      method: "DELETE",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        ...getAuthHeaders(),
      },
    })

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] Production record delete error:", errorText)
      // 372: a refusal (e.g. its broken eggs / dead birds were already used) comes back as { message }.
      return {
        success: false,
        message: refusalMessage(response.status, errorText, "Could not delete this production record. Please try again."),
      }
    }

    return {
      success: true,
      message: "Production record deleted successfully",
    }
  } catch (error) {
    console.error("[v0] Production record delete error:", error)
    return {
      success: false,
      message: "Failed to delete production record",
    }
  }
}