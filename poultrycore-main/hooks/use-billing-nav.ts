"use client"

import { useEffect, useState } from "react"
import { farmApiUrl, getAuthHeaders, getUserContext } from "@/lib/api/config"

/**
 * Whether the customer-app Billing button should be shown.
 *
 * Controlled from the admin portal (Operations → Feature Flags) by the
 * "billing_nav" flag: a global master toggle plus optional per-company rules.
 * On = Billing visible; Off = hidden. Resolution is per the current company.
 *
 * Fail-open: if the flag can't be read, errors, or does not exist
 * (FlagNotFound), Billing stays visible — so a flag/API hiccup never hides a
 * button that should be there.
 */
export function useBillingNavVisible(): boolean {
  const [visible, setVisible] = useState(true)

  useEffect(() => {
    let cancelled = false
    try {
      const { farmId } = getUserContext()
      const qs = farmId ? `?companyId=${encodeURIComponent(farmId)}` : ""
      fetch(farmApiUrl(`/PlatformOps/flags/billing_nav/evaluate${qs}`), { headers: getAuthHeaders() })
        .then((r) => (r.ok ? r.json() : null))
        .then((d) => {
          if (cancelled || !d) return
          if (d.enabled === false && d.matchedScope !== "FlagNotFound") setVisible(false)
        })
        .catch(() => {
          /* fail-open: keep Billing visible */
        })
    } catch {
      /* fail-open */
    }
    return () => {
      cancelled = true
    }
  }, [])

  return visible
}
