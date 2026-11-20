// Water Alerts (migration 465): GET api/Water/alerts -- derived on every read,
// never stored. One row per kind of problem, with the page that fixes it.

import { farmApiUrl, getAuthHeaders } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"

export type WaterAlertSeverity = "Critical" | "Warning" | "Info"

export interface WaterAlert {
  section: string
  code: string
  severity: WaterAlertSeverity
  title: string
  detail?: string | null
  itemCount: number
  amount?: number | null
  href: string
  sortOrder: number
}

export const WATER_ALERT_SECTIONS = ["Daily closing", "Production", "Deliveries", "Stock", "Equipment", "Money"] as const

export async function getWaterAlerts(farmId: string): Promise<WaterAlert[]> {
  const path = `/Water/alerts?farmId=${encodeURIComponent(farmId)}`
  const res = await fetch(farmApiUrl(path), { headers: getAuthHeaders() })
  if (!res.ok) {
    if (res.status === 401) forceReauth()
    const t = await res.text().catch(() => "")
    throw new Error(explainHttpError("GET", path, res.status, t))
  }
  return (await res.json()) as WaterAlert[]
}

/** What the bell counts: things that need doing (Critical + Warning), not Info. */
export const waterAlertBellCount = (rows: WaterAlert[]): number =>
  rows.filter((r) => r.severity !== "Info").reduce((s, r) => s + (Number(r.itemCount) || 0), 0)
