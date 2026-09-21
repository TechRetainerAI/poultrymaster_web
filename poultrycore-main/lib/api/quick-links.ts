/**
 * User Quick Links — what one user wants in their shortcut bar, for one
 * company (migration 318, api/UserQuickLinks).
 *
 * `customised` is the field to read, not `hrefs.length`. An empty list means
 * two different things depending on it: never chosen, so show the page's
 * defaults; or deliberately cleared, so show nothing.
 */

import { farmApiUrl, getAuthHeaders, getUserContext } from "@/lib/api/config"

export interface UserQuickLinks {
  userId: string
  farmId: string
  customised: boolean
  hrefs: string[]
  updatedAt?: string | null
}

/** Backend JSON is PascalCase; the house helper lowercases the first char. */
function lower<T>(v: any): T {
  if (Array.isArray(v)) return v.map((x) => lower(x)) as unknown as T
  if (v && typeof v === "object") {
    return Object.fromEntries(
      Object.entries(v).map(([k, val]) => [k.charAt(0).toLowerCase() + k.slice(1), lower(val)]),
    ) as T
  }
  return v as T
}

export async function getUserQuickLinks(): Promise<UserQuickLinks | null> {
  const { farmId, userId } = getUserContext()
  if (!farmId || !userId) return null

  const url = farmApiUrl(
    `/UserQuickLinks?userId=${encodeURIComponent(userId)}&farmId=${encodeURIComponent(farmId)}`,
  )
  const r = await fetch(url, { headers: getAuthHeaders(), credentials: "include" })
  if (!r.ok) throw new Error(`Quick Links could not be loaded (${r.status})`)
  return lower<UserQuickLinks>(await r.json())
}

/**
 * Replace the whole bar. Returns what was STORED, which is not always what was
 * sent -- 318 drops duplicates and anything that is not a path.
 */
export async function saveUserQuickLinks(hrefs: string[]): Promise<UserQuickLinks> {
  const { farmId, userId } = getUserContext()
  if (!farmId || !userId) throw new Error("No company is open.")

  const r = await fetch(farmApiUrl("/UserQuickLinks"), {
    method: "PUT",
    headers: getAuthHeaders(),
    credentials: "include",
    body: JSON.stringify({ userId, farmId, hrefs }),
  })
  if (!r.ok) throw new Error((await r.text()) || `Quick Links could not be saved (${r.status})`)
  return lower<UserQuickLinks>(await r.json())
}

/** Back to the page's defaults. Deletes the choice rather than storing one. */
export async function resetUserQuickLinks(): Promise<void> {
  const { farmId, userId } = getUserContext()
  if (!farmId || !userId) throw new Error("No company is open.")

  const r = await fetch(
    farmApiUrl(
      `/UserQuickLinks?userId=${encodeURIComponent(userId)}&farmId=${encodeURIComponent(farmId)}`,
    ),
    { method: "DELETE", headers: getAuthHeaders(), credentials: "include" },
  )
  if (!r.ok) throw new Error(`Quick Links could not be reset (${r.status})`)
}
