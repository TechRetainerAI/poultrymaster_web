// Doc3-D: when any API call reports an expired/invalid session (HTTP 401), the
// app must not let the user keep attempting tasks. This wipes auth and bounces
// to the login screen. Safe to call repeatedly (it no-ops once on /login).
let redirecting = false

export function forceReauth(): void {
  if (typeof window === "undefined") return
  if (redirecting) return
  if (window.location.pathname === "/login") return
  redirecting = true
  try {
    localStorage.removeItem("auth_token")
    localStorage.removeItem("auth-storage")
    localStorage.removeItem("farmId")
    localStorage.removeItem("farmName")
    localStorage.removeItem("farmType")
    localStorage.removeItem("roles")
    localStorage.removeItem("isStaff")
    localStorage.removeItem("isAdmin")
    localStorage.removeItem("isSubscriber")
  } catch {}
  window.location.href = "/login?expired=1"
}
