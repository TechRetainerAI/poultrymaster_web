// Platform billing admin client (ADMIN APP spec). Every call carries the
// developer's JWT and the userId from its NameIdentifier claim; the farm API
// enforces the per-permission gate (BillingAdmin.*) server-side — this portal
// only displays what the shared billing backend computes.

import { farmApiBase } from "./api"

const NAMEID_LONG = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier"

/** The Identity userId inside the JWT — the billing admin endpoints key on it. */
export function userIdFromJwt(token: string): string | null {
  try {
    const seg = token.split(".")[1]?.replace(/-/g, "+").replace(/_/g, "/")
    if (!seg) return null
    const payload = JSON.parse(atob(seg)) as Record<string, unknown>
    const v = payload[NAMEID_LONG] ?? payload.nameid ?? payload.sub
    return typeof v === "string" && v.trim() ? v.trim() : null
  } catch {
    return null
  }
}

function base(): string {
  const b = farmApiBase()
  if (!b) throw new Error("VITE_FARM_API_URL is not set — the billing admin needs the Farm API.")
  return b
}

export async function billingGet<T>(token: string, userId: string, path: string): Promise<T> {
  const sep = path.includes("?") ? "&" : "?"
  const res = await fetch(`${base()}/api/PlatformBillingAdmin/${path}${sep}userId=${encodeURIComponent(userId)}`, {
    headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
  })
  if (res.status === 403) throw new Error((await res.text()) || "This account lacks the required BillingAdmin permission.")
  if (!res.ok) throw new Error((await res.text()) || `Request failed (${res.status})`)
  return (await res.json()) as T
}

export type SendResult = { ok: boolean; message?: string; problems?: string[]; id?: number }

export async function billingSend(
  token: string, userId: string, method: string, path: string, body?: Record<string, unknown>
): Promise<SendResult> {
  const sep = path.includes("?") ? "&" : "?"
  const url = body
    ? `${base()}/api/PlatformBillingAdmin/${path}`
    : `${base()}/api/PlatformBillingAdmin/${path}${sep}userId=${encodeURIComponent(userId)}`
  const res = await fetch(url, {
    method,
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", Accept: "application/json" },
    body: body ? JSON.stringify({ userId, ...body }) : undefined,
  })
  const data = (await res.json().catch(() => ({}))) as Record<string, unknown>
  if (!res.ok)
    return {
      ok: false,
      message:
        (typeof data.message === "string" && data.message) ||
        (Array.isArray(data.problems) && (data.problems as string[]).join("; ")) ||
        `Failed (${res.status})`,
      problems: Array.isArray(data.problems) ? (data.problems as string[]) : undefined,
    }
  return { ok: data.ok !== false, message: data.message as string | undefined, id: data.id as number | undefined }
}

/** The legacy config dump endpoint (markets, tiers, profiles, prices, settings). */
export async function billingConfig(token: string, userId: string): Promise<Record<string, Record<string, unknown>[]>> {
  const res = await fetch(`${base()}/api/PlatformBillingAdmin/config?userId=${encodeURIComponent(userId)}`, {
    headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
  })
  if (!res.ok) throw new Error((await res.text()) || `Config failed (${res.status})`)
  return (await res.json()) as Record<string, Record<string, unknown>[]>
}

export function moneyFmt(v: unknown, c: string): string {
  if (v === null || v === undefined || v === "") return "—"
  const n = Number(v)
  return Number.isFinite(n) ? `${c} ${n.toLocaleString(undefined, { minimumFractionDigits: 2 })}` : "—"
}
