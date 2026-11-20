// Water sale reversal (migration 458) -- the Water port of poultry's 351.
//
// Same preview / record shapes as lib/api/sale.ts so the one ReverseSaleDialog
// serves both modules. The server decides everything that matters and
// re-checks it on confirm; these only carry it.

import { farmApiUrl, getAuthHeaders } from "./config"
import type { ApiResponse, ReverseSaleInput, SaleReversalPreview, SaleReversalRecord } from "./sale"

async function readJson(response: Response): Promise<any> {
  const text = await response.text()
  try { return text ? JSON.parse(text) : null } catch { return text }
}

const base = (saleId: number) => `Water/sales/${saleId}`

export async function getWaterSaleReversalPreview(saleId: number, farmId: string): Promise<ApiResponse<SaleReversalPreview>> {
  try {
    const response = await fetch(farmApiUrl(`${base(saleId)}/reversal-preview?farmId=${encodeURIComponent(farmId)}`), {
      headers: getAuthHeaders(),
    })
    const data = await readJson(response)
    if (!response.ok) return { success: false, message: data?.message || "Could not work out what reversing this sale would do." }
    return { success: true, data }
  } catch (error) {
    return { success: false, message: error instanceof Error ? error.message : "Network error" }
  }
}

export async function getWaterSaleReversal(saleId: number, farmId: string): Promise<ApiResponse<SaleReversalRecord>> {
  try {
    const response = await fetch(farmApiUrl(`${base(saleId)}/reversal?farmId=${encodeURIComponent(farmId)}`), {
      headers: getAuthHeaders(),
    })
    const data = await readJson(response)
    if (!response.ok) return { success: false, message: data?.message || "Reversal not found" }
    return { success: true, data }
  } catch (error) {
    return { success: false, message: error instanceof Error ? error.message : "Network error" }
  }
}

/** stale: the sale changed after the preview was shown -- reload it and confirm again. */
export async function reverseWaterSale(
  saleId: number,
  input: ReverseSaleInput,
): Promise<ApiResponse<{ salereversalid: number; reversal: SaleReversalRecord | null }> & { stale?: boolean }> {
  try {
    const response = await fetch(farmApiUrl(`${base(saleId)}/reverse?farmId=${encodeURIComponent(input.farmId)}`), {
      method: "POST",
      headers: getAuthHeaders(),
      body: JSON.stringify(input),
    })
    const data = await readJson(response)
    if (!response.ok) {
      return { success: false, stale: !!data?.stale, message: data?.message || (typeof data === "string" ? data : "The sale was not reversed.") }
    }
    return { success: true, data }
  } catch (error) {
    return { success: false, message: error instanceof Error ? error.message : "Network error" }
  }
}
