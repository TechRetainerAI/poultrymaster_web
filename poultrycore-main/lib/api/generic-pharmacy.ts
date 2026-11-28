// Generic Pharmacy API client (migration 515): /api/generic-company/{farmId}/pharmacy/...
// Shown only to Generic companies whose industry template is "Pharmacy".

import { buildApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"

export type MedicineClass = "A" | "B" | "C"
export type PharmacyShopType = "Pharmacy" | "ChemicalShop"

export interface PharmacySettings {
  shopType: PharmacyShopType
  requirePrescriptionClassA: boolean
  expiryWarningDays: number
  saved: boolean
}

export interface ProductPack {
  genericProductPackId?: number
  packName: string
  /** How many base units (tablets, capsules, bottles) are in one pack. */
  unitsPerPack: number
  sellingPrice: number
}

export interface Medicine {
  genericProductId: number
  productName: string
  sku?: string | null
  barcode?: string | null
  categoryName?: string | null
  baseUnit: string
  sellingPrice: number
  costPrice: number
  currentStock: number
  minimumStockAlert: number
  trackInventory: boolean
  isActive: boolean
  /** False until medicine details were saved for this product. */
  isMedicine: boolean
  genericName?: string | null
  strength?: string | null
  dosageForm?: string | null
  medicineClass: MedicineClass
  fdaRegNo?: string | null
  manufacturer?: string | null
  storageNote?: string | null
  isControlled: boolean
  packs: ProductPack[]
  /** Base units in batches that have expired (cannot be sold). */
  expiredQty: number
  /** Base units in stock with no batch recorded. */
  unbatchedQty: number
  nearestExpiry?: string | null
  batchCount: number
}

export interface MedicineInput {
  genericName?: string | null
  strength?: string | null
  dosageForm?: string | null
  medicineClass: MedicineClass
  fdaRegNo?: string | null
  manufacturer?: string | null
  storageNote?: string | null
  isControlled: boolean
  packs: ProductPack[]
}

export interface ProductBatch {
  genericProductBatchId: number
  genericProductId: number
  productName: string
  genericName?: string | null
  medicineClass?: MedicineClass | null
  baseUnit: string
  batchNumber?: string | null
  expiryDate?: string | null
  daysToExpiry?: number | null
  receivedDate: string
  quantityReceived: number
  quantityRemaining: number
  unitCost?: number | null
  sourceType: "Purchase" | "Manual"
  genericPurchaseId?: number | null
  invoiceNumber?: string | null
  notes?: string | null
}

export interface PurchaseLineBatch {
  genericPurchaseItemId?: number
  genericProductId: number
  batchNumber?: string | null
  expiryDate?: string | null
}

export interface PrescriptionItem {
  genericProductId?: number | null
  medicineName: string
  quantity: number
  unit?: string | null
  directions?: string | null
}

export interface Prescription {
  genericPrescriptionId: number
  prescriptionDate: string
  patientName: string
  patientPhone?: string | null
  prescriberName: string
  prescriberFacility?: string | null
  prescriptionRef?: string | null
  notes?: string | null
  genericSaleId?: number | null
  receiptNumber?: string | null
  saleStatus?: string | null
  createdBy?: string | null
  items: PrescriptionItem[]
}

export interface PrescriptionInput {
  genericSaleId?: number | null
  prescriptionDate?: string | null
  patientName: string
  patientPhone?: string | null
  prescriberName: string
  prescriberFacility?: string | null
  prescriptionRef?: string | null
  notes?: string | null
  items: PrescriptionItem[]
}

export interface PharmacyReportRow {
  genericProductId: number
  productName: string
  genericName?: string | null
  medicineClass: MedicineClass
  isMedicine: boolean
  isControlled: boolean
  baseUnit: string
  qtySold: number
  revenue: number
  cost: number
  profit: number
  lastSoldAt?: string | null
  currentStock: number
  stockValue: number
  expiredQty: number
  expiringQty: number
  nearestExpiry?: string | null
}

// ---------------------------------------------------------------------------

function base(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("Missing farmId in user context.")
  return `/generic-company/${encodeURIComponent(farmId)}/pharmacy`
}

async function send<T>(method: string, path: string, body?: unknown): Promise<T> {
  const endpoint = `${base()}${path}`
  const { farmId } = getUserContext()
  const r = await fetch(buildApiUrl(endpoint), {
    method,
    headers: getAuthHeaders(),
    body: body === undefined ? undefined : JSON.stringify({ farmId, ...(body as object) }),
  })
  if (!r.ok) {
    const text = await r.text().catch(() => "")
    throw new Error(explainHttpError(method, endpoint, r.status, text))
  }
  const txt = r.status === 204 ? "" : await r.text()
  return (txt ? JSON.parse(txt) : null) as T
}

const qs = (o: Record<string, string | number | null | undefined>) => {
  const p = new URLSearchParams()
  for (const [k, v] of Object.entries(o)) if (v !== null && v !== undefined && v !== "") p.set(k, String(v))
  const s = p.toString()
  return s ? `?${s}` : ""
}

export const getPharmacySettings = () => send<PharmacySettings>("GET", "/settings")
export const savePharmacySettings = (s: Omit<PharmacySettings, "saved">) => send<void>("PUT", "/settings", s)

export const getMedicines = () => send<Medicine[]>("GET", "/medicines")
export const saveMedicine = (productId: number, input: MedicineInput) => send<void>("PUT", `/medicines/${productId}`, input)

export const getBatches = (productId?: number | null) => send<ProductBatch[]>("GET", `/batches${qs({ productId })}`)
export const addBatch = (input: {
  genericProductId: number; batchNumber?: string | null; expiryDate?: string | null; quantity: number
  unitCost?: number | null; receivedDate?: string | null; notes?: string | null
}) => send<{ genericProductBatchId: number }>("POST", "/batches", input)
export const updateBatch = (id: number, input: { batchNumber?: string | null; expiryDate?: string | null; notes?: string | null }) =>
  send<void>("PUT", `/batches/${id}`, input)
export const deleteBatch = (id: number) => send<void>("DELETE", `/batches/${id}`)
export const writeOffBatch = (id: number, quantity: number, reason?: string | null) =>
  send<{ genericStockAdjustmentId: number }>("POST", `/batches/${id}/write-off`, { quantity, reason })

export const getPurchaseBatches = (purchaseId: number) => send<PurchaseLineBatch[]>("GET", `/purchases/${purchaseId}/batches`)
/** Lines in the same order as the purchase's lines. Draft purchases only. */
export const setPurchaseBatches = (purchaseId: number, lines: PurchaseLineBatch[]) =>
  send<void>("PUT", `/purchases/${purchaseId}/batches`, { lines })

export const getPrescriptions = (from?: string | null, to?: string | null) =>
  send<Prescription[]>("GET", `/prescriptions${qs({ from, to })}`)
export const createPrescription = (input: PrescriptionInput) =>
  send<{ genericPrescriptionId: number }>("POST", "/prescriptions", input)

export const getPharmacyReport = (from: string, to: string, expiryDays = 90) =>
  send<PharmacyReportRow[]>("GET", `/report${qs({ from, to, expiryDays })}`)
