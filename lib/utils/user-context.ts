export function getUserContext() {
  if (typeof window === "undefined") {
    return { userId: "", farmId: "" }
  }

  const userId = localStorage.getItem("userId") || ""
  const farmId = localStorage.getItem("farmId") || ""

  console.log("[v0] getUserContext:", { userId, farmId })

  return { userId, farmId }
}

export function setUserContext(userId: string, farmId: string) {
  if (typeof window === "undefined") return

  localStorage.setItem("userId", userId)
  localStorage.setItem("farmId", farmId)

  console.log("[v0] setUserContext:", { userId, farmId })
}

export function clearUserContext() {
  if (typeof window === "undefined") return

  localStorage.removeItem("userId")
  localStorage.removeItem("farmId")
  localStorage.removeItem("username")
  localStorage.removeItem("farmName")
  localStorage.removeItem("auth_token")
  localStorage.removeItem("refresh_token")
  localStorage.removeItem("isStaff")
  localStorage.removeItem("isSubscriber")

  console.log("[v0] User context cleared")
}
