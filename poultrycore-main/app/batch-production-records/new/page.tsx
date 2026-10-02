"use client"

// Full-page ADD batch production record.
//
// The modal on /batch-production-records is the default way in; this route
// stays for people who want the room, for direct links and bookmarks, and as
// the mobile fallback. It renders the SAME <BatchProductionRecordForm> the
// modal does, so the two cannot drift apart.
//
// This file used to hold its own ~860-line copy of the form.
//
// ?date=yyyy-MM-dd&flockIds=1,2,3 pre-selects flocks — written by the
// dashboard's "Complete Missing Production" (migration 332). See
// lib/activity/completeness.ts for both ends of that link.

import { Suspense } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Boxes, X } from "lucide-react"
import { BatchProductionRecordForm } from "@/components/production/batch-production-record-form"
import { farmCompletenessHref, parseMissingProductionPrefill } from "@/lib/activity/completeness"

function NewBatchProductionRecordPageInner() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const prefill = parseMissingProductionPrefill(searchParams)

  const handleLogout = () => {
    localStorage.clear()
    router.push("/login")
  }

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex min-w-0 flex-1 flex-col">
        <DashboardHeader />
        <main className="min-w-0 overflow-x-hidden p-4 pb-16 sm:p-6 lg:pb-4">
          <div className="mb-4 flex items-center justify-between gap-3">
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-sky-100">
                <Boxes className="h-5 w-5 text-sky-600" />
              </div>
              <div>
                <h1 className="text-2xl font-bold text-slate-900">Add New Batch Production Record</h1>
                <p className="text-sm text-slate-600">Log total production for a batch or group of flocks</p>
              </div>
            </div>
            <Button
              type="button"
              size="sm"
              className="gap-1.5 bg-red-600 text-white hover:bg-red-700"
              onClick={() => router.push("/batch-production-records")}
            >
              <X className="h-4 w-4" /> Close
            </Button>
          </div>

          <BatchProductionRecordForm
            mode="create"
            displayMode="page"
            prefill={prefill}
            onSaved={(status, id) => {
              // Opened from Farm Completeness: the job is not done until the
              // batch is POSTED, so go straight to allocation (where posting
              // happens). A draft goes back to where the user came from.
              if (prefill) {
                const back = farmCompletenessHref(prefill.date)
                if (status === "PendingAllocation" && id != null) {
                  router.push(`/batch-production-records/${id}/allocate?returnTo=${encodeURIComponent(back)}`)
                } else {
                  router.push(back)
                }
                return
              }
              router.push("/batch-production-records")
            }}
            onCancel={() => router.push("/batch-production-records")}
          />
        </main>
      </div>
    </div>
  )
}

export default function NewBatchProductionRecordPage() {
  // useSearchParams needs a Suspense boundary during prerender.
  return (
    <Suspense fallback={null}>
      <NewBatchProductionRecordPageInner />
    </Suspense>
  )
}
