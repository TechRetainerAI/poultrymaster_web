"use client"

// Billing lives as a tab of Administration (/business-office/setup?tab=billing).
// This route survives only so links minted while it was a standalone page —
// and the provider's checkout return URLs — keep working; query params
// (billing=success&reference=…) are carried across so verification still runs.

import { useEffect } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { Suspense } from "react"
import { Loader2 } from "lucide-react"

export default function BillingRedirect() {
  return (
    <Suspense fallback={null}>
      <RedirectInner />
    </Suspense>
  )
}

function RedirectInner() {
  const router = useRouter()
  const searchParams = useSearchParams()
  useEffect(() => {
    const qs = searchParams.toString()
    router.replace(`/business-office/setup?tab=billing${qs ? `&${qs}` : ""}`)
  }, [router, searchParams])
  return (
    <div className="flex items-center gap-2 text-slate-600 py-12 justify-center">
      <Loader2 className="h-5 w-5 animate-spin" /> Opening billing…
    </div>
  )
}
