"use client"

import { useEffect } from "react"
import { usePathname, useRouter } from "next/navigation"

const PUBLIC_PATH_PREFIXES = ["/login", "/signup", "/forgot-password", "/reset-password"]
const ALLOWED_UNSUBSCRIBED_PREFIXES = ["/payments", "/help", "/terms", "/resources", "/profile"]
// Temporary business override: keep app open while subscription/trial rollout is finalized.
const TEMP_ALLOW_ALL_ACCESS = true

function matchesPrefix(pathname: string, prefixes: string[]): boolean {
  return prefixes.some((prefix) => pathname === prefix || pathname.startsWith(`${prefix}/`))
}

export function SubscriptionGuard() {
  const pathname = usePathname()
  const router = useRouter()

  useEffect(() => {
    if (typeof window === "undefined") return
    if (!pathname) return
    if (TEMP_ALLOW_ALL_ACCESS) return

    if (matchesPrefix(pathname, PUBLIC_PATH_PREFIXES)) return

    const token = localStorage.getItem("auth_token")
    if (!token) return

    const isSubscriber = localStorage.getItem("isSubscriber") === "true"
    if (isSubscriber) return

    if (matchesPrefix(pathname, ALLOWED_UNSUBSCRIBED_PREFIXES)) return

    router.replace("/payments?subscription=required")
  }, [pathname, router])

  return null
}

