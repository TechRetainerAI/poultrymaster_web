import type { HealthRecord } from "@/lib/api/health"
import { extractReceiptPathFromDescription } from "@/lib/utils/expense-receipt"

/** Stored on health `notes`; excluded from medication stock ledger. */
export const MEDICATION_PHOTO_TYPE_PREFIX = "[Type: MedicationPhoto]"

export function isMedicationPhotoReferenceRecord(r: Pick<HealthRecord, "notes">): boolean {
  return /^\[Type:\s*MedicationPhoto\]/i.test((r.notes || "").trim())
}

export function normalizeProductKey(label: string): string {
  return label
    .trim()
    .toLowerCase()
    .replace(/\s+/g, " ")
}

export function primaryLabelFromText(text: string): string {
  return text
    .trim()
    .split(/[\n;]/)[0]
    .trim()
}

/** Notes body for a flock health row that only stores a medication pack photo (no stock IN). Image bytes live in HealthRecord.AttachmentImage. */
export function buildMedicationPhotoNotesDb(caption?: string): string {
  const cap = (caption || "").trim()
  return cap ? `${MEDICATION_PHOTO_TYPE_PREFIX} ${cap}` : MEDICATION_PHOTO_TYPE_PREFIX
}

export type MedicationPhotoInfo = {
  productKey: string
  productLabel: string
  /** Legacy file path in notes (`/receipt-uploads/...`); null when image is only in DB. */
  path: string | null
  healthRecordId: number
  recordDate: string
  flockId: number | null
  hasAttachmentImage?: boolean
}

export function listMedicationPhotoInfos(records: HealthRecord[]): MedicationPhotoInfo[] {
  const list: MedicationPhotoInfo[] = []
  for (const r of records) {
    if (!isMedicationPhotoReferenceRecord(r)) continue
    const hasDb = Boolean(r.hasAttachmentImage)
    const path = extractReceiptPathFromDescription(r.notes || "")
    // List row whenever this is a medication-photo note row; UI loads bytes via /api/health-image even if
    // list endpoint omitted HasAttachmentImage or legacy path was never embedded in notes.
    const med = (r.medication || "").trim()
    if (!med) continue
    const productLabel = primaryLabelFromText(med)
    const productKey = normalizeProductKey(productLabel)
    const id = r.id
    if (id == null || !Number.isFinite(Number(id))) continue
    list.push({
      productKey,
      productLabel,
      path: path || null,
      healthRecordId: Number(id),
      recordDate: r.recordDate || "",
      flockId: r.flockId ?? null,
      hasAttachmentImage: hasDb,
    })
  }
  return list.sort((a, b) => new Date(b.recordDate).getTime() - new Date(a.recordDate).getTime())
}

export function getLatestMedicationPhotoByProductKey(records: HealthRecord[]): Map<string, MedicationPhotoInfo> {
  const map = new Map<string, MedicationPhotoInfo>()
  for (const info of listMedicationPhotoInfos(records)) {
    if (!map.has(info.productKey)) map.set(info.productKey, info)
  }
  return map
}
