import { farmApiUrl, getAuthHeaders } from "./config"

// Prompt 4 — Business Office announcements / notifications.
export interface Announcement {
  announcementId: number
  orgOwnerUserId?: string | null
  title: string
  message: string
  type: string            // Info|Success|Warning|Critical|Maintenance|FeatureUpdate|Payment|Security
  priority: number
  audienceRole?: string | null  // All|Admin|Staff
  targetFarmId?: string | null
  startDate?: string | null
  endDate?: string | null
  isDismissible: boolean
  requiresAck: boolean
  actionLabel?: string | null
  actionUrl?: string | null
  createdBy?: string | null
  createdAt: string
  readAt?: string | null
  dismissedAt?: string | null
  acknowledgedAt?: string | null
}

function currentUserId(): string {
  if (typeof window === "undefined") return ""
  try { return localStorage.getItem("userId") || "" } catch { return "" }
}

async function jget<T>(path: string): Promise<T> {
  const res = await fetch(farmApiUrl(path), { headers: getAuthHeaders() })
  if (!res.ok) throw new Error(`Announcements ${res.status}`)
  return res.json()
}
async function jsend<T>(path: string, method: string, body?: any): Promise<T> {
  const init: RequestInit = { method, headers: getAuthHeaders() }
  if (body !== undefined) init.body = JSON.stringify(body)
  const res = await fetch(farmApiUrl(path), init)
  if (!res.ok) throw new Error(`Announcements ${res.status} ${await res.text().catch(() => "")}`)
  return res.json().catch(() => ({} as T))
}

export const listAnnouncements = (opts: { orgOwnerUserId?: string | null; isAdmin?: boolean; farmId?: string | null }) => {
  const qs = new URLSearchParams({ userId: currentUserId() })
  if (opts.orgOwnerUserId) qs.append("orgOwnerUserId", opts.orgOwnerUserId)
  if (opts.isAdmin) qs.append("isAdmin", "true")
  if (opts.farmId) qs.append("farmId", opts.farmId)
  return jget<Announcement[]>(`/Announcements?${qs.toString()}`)
}

export const setAnnouncementReceipt = (id: number, action: "Read" | "Dismiss" | "Ack") =>
  jsend<{ success: boolean }>(`/Announcements/${id}/receipt?userId=${encodeURIComponent(currentUserId())}&action=${action}`, "POST")

export const listManageAnnouncements = (orgOwnerUserId: string) =>
  jget<Announcement[]>(`/Announcements/manage?orgOwnerUserId=${encodeURIComponent(orgOwnerUserId)}`)

export const createAnnouncement = (input: {
  orgOwnerUserId?: string | null
  title: string
  message?: string
  type?: string
  priority?: number
  audienceRole?: string | null
  targetFarmId?: string | null
  isDismissible?: boolean
  requiresAck?: boolean
  actionLabel?: string | null
  actionUrl?: string | null
}) => jsend<{ announcementId: number }>(`/Announcements`, "POST", { ...input, createdBy: currentUserId() })

export const deleteAnnouncement = (id: number, orgOwnerUserId: string) =>
  jsend<{ success: boolean }>(`/Announcements/${id}?orgOwnerUserId=${encodeURIComponent(orgOwnerUserId)}`, "DELETE")
