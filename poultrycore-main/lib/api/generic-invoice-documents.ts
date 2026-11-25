// Generic Company Invoice Documents API client.
//
// Invoice documents are formal billing records that reference authoritative
// posted Sales. They do NOT create revenue, inventory, or cash — the Sale
// already did that. Migration 494.

import { buildApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"

// =============================================================================
// Types
// =============================================================================

export interface InvoiceDocumentRow {
  genericInvoiceDocumentId: number
  genericSaleId: number
  invoiceNumber: string
  issueDate: string
  dueDate: string | null
  paymentTerms: string
  documentStatus: string
  customerBillingName: string | null
  genericProjectId: number | null
  projectName: string | null
  saleReceiptNumber: string | null
  totalAmount: number
  amountPaid: number
  balance: number
  paymentStatus: string | null
  isOverdue: boolean
  daysUntilDue: number | null
  createdAt: string | null
}

export interface InvoiceDocumentDetail {
  genericInvoiceDocumentId: number
  farmId: string
  genericSaleId: number
  invoiceNumber: string
  issueDate: string
  dueDate: string | null
  paymentTerms: string
  documentStatus: string
  // Customer snapshot
  customerBillingName: string | null
  customerBillingAddress: string | null
  customerBillingEmail: string | null
  customerBillingPhone: string | null
  // Document fields
  paymentInstructions: string | null
  footerNotes: string | null
  termsAndConditions: string | null
  purchaseOrderReference: string | null
  deliveryReference: string | null
  genericProjectId: number | null
  projectName: string | null
  version: number
  voidedBy: string | null
  voidedAt: string | null
  voidReason: string | null
  issuedBy: string | null
  issuedAt: string | null
  createdBy: string | null
  createdAt: string | null
  // Sale fields (live)
  saleReceiptNumber: string | null
  saleDate: string | null
  salesType: string | null
  subtotalAmount: number
  discountAmount: number
  taxAmount: number
  totalAmount: number
  amountPaid: number
  balance: number
  paymentStatus: string | null
  saleStatus: string | null
  // Derived
  isOverdue: boolean
  daysUntilDue: number | null
  // Populated
  lines: InvoiceSaleLineRow[] | null
  history: InvoiceHistoryRow[] | null
}

export interface InvoiceSaleLineRow {
  genericSaleItemId: number
  itemType: string | null
  genericProductId: number | null
  genericServiceId: number | null
  productName: string | null
  serviceName: string | null
  description: string | null
  quantity: number
  unitName: string | null
  unitPrice: number
  discountAmount: number
  taxAmount: number
  lineTotal: number
  genericProjectId: number | null
}

export interface InvoiceHistoryRow {
  genericInvoiceHistoryId: number
  action: string
  previousValue: string | null
  newValue: string | null
  userId: string | null
  createdAt: string | null
}

export interface InvoiceSettingsDto {
  farmId: string
  invoicePrefix: string
  nextNumber: number
  defaultPaymentTerms: string
  paymentInstructions: string | null
  footerNotes: string | null
  termsAndConditions: string | null
  autoGenerateInvoiceAfterSale: boolean
  autoSendInvoiceAfterIssuance: boolean
}

export interface InvoiceSaleLookup {
  genericInvoiceDocumentId: number
  invoiceNumber: string
  documentStatus: string
  issueDate: string
  dueDate: string | null
}

export interface GenerateInvoiceInput {
  saleId: number
  dueDate?: string | null
  paymentTerms?: string | null
  purchaseOrderReference?: string | null
  deliveryReference?: string | null
  paymentInstructions?: string | null
}

export interface UpdateDraftInvoiceInput {
  dueDate?: string | null
  paymentTerms?: string | null
  purchaseOrderReference?: string | null
  deliveryReference?: string | null
  paymentInstructions?: string | null
  footerNotes?: string | null
  termsAndConditions?: string | null
}

export const PAYMENT_TERMS_OPTIONS = [
  { value: "DueImmediately", label: "Due Immediately" },
  { value: "Net7",           label: "Net 7 days" },
  { value: "Net14",          label: "Net 14 days" },
  { value: "Net30",          label: "Net 30 days" },
  { value: "Net45",          label: "Net 45 days" },
  { value: "Net60",          label: "Net 60 days" },
  { value: "Custom",         label: "Custom date" },
] as const

export const DOCUMENT_STATUS_OPTIONS = [
  "All", "Draft", "Issued", "Voided",
] as const

export const PAYMENT_STATUS_OPTIONS = [
  "All", "Unpaid", "PartiallyPaid", "Paid",
] as const

// =============================================================================
// Helpers
// =============================================================================

function currentFarmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("Missing farmId in user context.")
  return farmId
}

function basePath(): string {
  return `api/generic-company/${currentFarmId()}/invoice-documents`
}

async function getJson<T>(endpoint: string): Promise<T> {
  const r = await fetch(buildApiUrl(endpoint), { method: "GET", headers: getAuthHeaders() })
  if (!r.ok) {
    const text = await r.text().catch(() => "")
    throw new Error(explainHttpError("GET", endpoint, r.status, text))
  }
  return (await r.json()) as T
}

async function sendJson<T>(
  method: "POST" | "PUT",
  endpoint: string,
  body: unknown,
): Promise<T | null> {
  const r = await fetch(buildApiUrl(endpoint), {
    method,
    headers: getAuthHeaders(),
    body: JSON.stringify({ ...(body as object), farmId: currentFarmId() }),
  })
  if (r.status === 204) return null
  if (!r.ok) {
    const text = await r.text().catch(() => "")
    throw new Error(explainHttpError(method, endpoint, r.status, text))
  }
  const txt = await r.text()
  return txt ? (JSON.parse(txt) as T) : null
}

// =============================================================================
// Settings
// =============================================================================

export async function getInvoiceSettings(): Promise<InvoiceSettingsDto> {
  return getJson<InvoiceSettingsDto>(`${basePath()}/settings`)
}

export async function saveInvoiceSettings(
  input: Omit<InvoiceSettingsDto, "farmId" | "nextNumber">,
): Promise<InvoiceSettingsDto | null> {
  return sendJson<InvoiceSettingsDto>("PUT", `${basePath()}/settings`, input)
}

// =============================================================================
// Invoice CRUD
// =============================================================================

export async function generateInvoice(
  input: GenerateInvoiceInput,
): Promise<InvoiceDocumentDetail | null> {
  return sendJson<InvoiceDocumentDetail>("POST", `${basePath()}/generate`, input)
}

export async function getInvoiceDocument(
  docId: number,
): Promise<InvoiceDocumentDetail> {
  return getJson<InvoiceDocumentDetail>(`${basePath()}/${docId}`)
}

export async function getInvoiceForSale(
  saleId: number,
): Promise<InvoiceSaleLookup | null> {
  try {
    return await getJson<InvoiceSaleLookup>(`${basePath()}/by-sale/${saleId}`)
  } catch {
    return null // 404 = no invoice for this sale
  }
}

export async function getInvoiceDocuments(opts?: {
  documentStatus?: string
  paymentStatus?: string
  customerId?: number
  projectId?: number
  from?: string
  to?: string
  overdueOnly?: boolean
}): Promise<InvoiceDocumentRow[]> {
  const params = new URLSearchParams()
  if (opts?.documentStatus && opts.documentStatus !== "All")
    params.set("documentStatus", opts.documentStatus)
  if (opts?.paymentStatus && opts.paymentStatus !== "All")
    params.set("paymentStatus", opts.paymentStatus)
  if (opts?.customerId) params.set("customerId", String(opts.customerId))
  if (opts?.projectId) params.set("projectId", String(opts.projectId))
  if (opts?.from) params.set("from", opts.from)
  if (opts?.to) params.set("to", opts.to)
  if (opts?.overdueOnly) params.set("overdueOnly", "true")
  const qs = params.toString()
  return getJson<InvoiceDocumentRow[]>(`${basePath()}${qs ? `?${qs}` : ""}`)
}

// =============================================================================
// Lifecycle
// =============================================================================

export async function issueInvoice(docId: number): Promise<void> {
  await sendJson("POST", `${basePath()}/${docId}/issue`, {})
}

export async function voidInvoice(
  docId: number,
  reason: string,
): Promise<void> {
  await sendJson("POST", `${basePath()}/${docId}/void`, { reason })
}

export async function updateDraftInvoice(
  docId: number,
  input: UpdateDraftInvoiceInput,
): Promise<InvoiceDocumentDetail | null> {
  return sendJson<InvoiceDocumentDetail>("PUT", `${basePath()}/${docId}/draft`, input)
}

// =============================================================================
// Supporting data
// =============================================================================

export async function getInvoiceHistory(
  docId: number,
): Promise<InvoiceHistoryRow[]> {
  return getJson<InvoiceHistoryRow[]>(`${basePath()}/${docId}/history`)
}

export async function getInvoiceSaleLines(
  saleId: number,
): Promise<InvoiceSaleLineRow[]> {
  return getJson<InvoiceSaleLineRow[]>(`${basePath()}/sale-lines/${saleId}`)
}
