/** Map stored batch status to UI toggles (mirrors flock HasArrived + Active). */
export function batchTogglesFromStatus(status?: string): { hasArrived: boolean; active: boolean } {
  const s = (status || "active").toLowerCase()
  if (s === "pending") return { hasArrived: false, active: true }
  if (s === "inactive") return { hasArrived: true, active: false }
  return { hasArrived: true, active: true }
}

/** Map UI toggles to status stored on MainFlockBatch. */
export function batchStatusFromToggles(hasArrived: boolean, active: boolean): string {
  if (!hasArrived) return "pending"
  return active ? "active" : "inactive"
}
