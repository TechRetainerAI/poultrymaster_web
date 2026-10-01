"use client"

// Subscription & Billing — its own Business Office page, sitting in the
// sidebar right below Administration (it used to be a tab of Administration;
// the old ?tab=billing link now redirects here). Checkout return
// URLs (billing=success&reference=…) land on this route and the panel runs
// verification from the query params.

import { Suspense } from "react"
import { BusinessOfficeShell } from "@/components/dashboard/business-office-shell"
import { BillingPanel } from "@/components/business-office/billing-panel"

export default function BusinessOfficeBillingPage() {
  return (
    <BusinessOfficeShell active="billing">
      <main className="flex-1 overflow-y-auto p-4 sm:p-6 space-y-4">
        <div>
          <h1 className="text-xl font-bold text-slate-900 sm:text-2xl">Subscription & Billing</h1>
          <p className="text-sm text-slate-600 sm:text-base">One consolidated VisibilityCore subscription across every company in your organization.</p>
        </div>
        {/* BillingPanel reads checkout-return query params, so it needs a
            Suspense boundary during prerender (house pattern). */}
        <Suspense fallback={null}>
          <BillingPanel />
        </Suspense>
      </main>
    </BusinessOfficeShell>
  )
}
