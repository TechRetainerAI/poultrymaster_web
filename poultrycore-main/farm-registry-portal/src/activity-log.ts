export type DeveloperActivity = {
  id: string
  at: string
  actor: string
  action: string
  details?: string
}

const KEY = "frp_activity_log"
const MAX_ITEMS = 250

export function readActivityLog(): DeveloperActivity[] {
  if (typeof window === "undefined") return []
  try {
    const raw = localStorage.getItem(KEY)
    if (!raw) return []
    const parsed = JSON.parse(raw) as DeveloperActivity[]
    return Array.isArray(parsed) ? parsed : []
  } catch {
    return []
  }
}

export function appendActivity(entry: Omit<DeveloperActivity, "id" | "at">) {
  if (typeof window === "undefined") return
  const next: DeveloperActivity = {
    id: `${Date.now()}-${Math.random().toString(16).slice(2)}`,
    at: new Date().toISOString(),
    actor: entry.actor || "unknown",
    action: entry.action,
    details: entry.details,
  }
  const current = readActivityLog()
  const merged = [next, ...current].slice(0, MAX_ITEMS)
  localStorage.setItem(KEY, JSON.stringify(merged))
}

export function clearActivityLog() {
  if (typeof window === "undefined") return
  localStorage.removeItem(KEY)
}
