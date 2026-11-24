// Generic sale reversal (migration 483_Enock_GenericSaleReversal) -- the
// Poultry 351 / Water 458 model on Generic sales.
//
// Same preview / record shapes as lib/api/sale.ts so the one ReverseSaleDialog
// serves all three modules. The server decides everything that matters and
// re-checks it on confirm; these only carry it.

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import type { ApiResponse, ReverseSaleInput, SaleReversalPreview, SaleReversalRecord } from "./sale"

async function readJson(response: Response): Promise<any> {
  const text = await response.text()
  try { return text ? JSON.parse(text) : null } catch { return text }
}

const base = (saleId: number, farmId?: string) =>
  `/generic-company/${encodeURIComponent(farmId || getUserContext().farmId || "")}/sales/${saleId}`

export async function getGenericSaleReversalPreview(saleId: number, farmId: string): Promise<ApiResponse<SaleReversalPreview>> {
  try {
    const response = await fetch(farmApiUrl(`${base(saleId, farmId)}/reversal-preview`), { headers: getAuthHeaders() })
    const data = await readJson(response)
    if (!response.ok) return { success: false, message: data?.message || "Could not work out what reversing this sale would do." }
    return { success: true, data }
  } catch (error) {
    return { success: false, message: error instanceof Error ? error.message : "Network error" }
  }
}

/** The reversal of a reversed sale; success false (404) when the sale was not reversed. */
export async function getGenericSaleReversal(saleId: number, farmId?: string): Promise<ApiResponse<SaleReversalRecord>> {
  try {
    const response = await fetch(farmApiUrl(`${base(saleId, farmId)}/reversal`), { headers: getAuthHeaders() })
    const data = await readJson(response)
    if (!response.ok) return { success: false, message: data?.message || "Reversal not found" }
    return { success: true, data }
  } catch (error) {
    return { success: false, message: error instanceof Error ? error.message : "Network error" }
  }
}

/** stale: the sale changed after the preview was shown -- reload it and confirm again. */
export async function reverseGenericSale(
  saleId: number,
  input: ReverseSaleInput,
): Promise<ApiResponse<{ salereversalid: number; reversal: SaleReversalRecord | null }> & { stale?: boolean }> {
  try {
    const response = await fetch(farmApiUrl(`${base(saleId, input.farmId)}/reverse`), {
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
