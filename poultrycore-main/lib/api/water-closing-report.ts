// Water Closing by Category (migration 463): GET api/Water/closing-report.
// One object of named period figures (PascalCase keys, as the server builds them).

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"

export async function getWaterClosingByCategory(fromDate: string, toDate: string): Promise<Record<string, unknown>> {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  const qs = new URLSearchParams({ farmId, fromDate, toDate })
  const path = `/Water/closing-report?${qs.toString()}`
  const res = await fetch(farmApiUrl(path), { headers: getAuthHeaders() })
  if (!res.ok) {
    if (res.status === 401) forceReauth()
    const t = await res.text().catch(() => "")
    throw new Error(explainHttpError("GET", path, res.status, t))
  }
  return (await res.json()) as Record<string, unknown>
}
