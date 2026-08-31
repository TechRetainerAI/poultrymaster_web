"use client"

// Full-page ADD production record.
//
// The modal on /production-records is the default way in; this route stays for
// people who want the room, for direct links and bookmarks, and as the mobile
// fallback. It renders the SAME <ProductionRecordForm> the modal does — the
// only difference is the container — so the two can no longer drift apart.
//
// This file used to hold its own ~970-line copy of the form.

import { Suspense } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { FileText, X } from "lucide-react"
import { ProductionRecordForm } from "@/components/production/production-record-form"

function NewProductionRecordPageInner() {
  const router = useRouter()
  const searchParams = useSearchParams()
  // The modal's "Open Full Page" passes the flock it had selected, so the
  // switch doesn't lose it.
  const flockIdParam = Number(searchParams.get("flockId"))
  const flockId = Number.isFinite(flockIdParam) && flockIdParam > 0 ? flockIdParam : null

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
              <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-emerald-100">
                <FileText className="h-5 w-5 text-emerald-600" />
              </div>
              <div>
                <h1 className="text-2xl font-bold text-slate-900">Add Production Record</h1>
                <p className="text-sm text-slate-600">Record daily egg production data for a flock</p>
              </div>
            </div>
            <Button
              type="button"
              size="sm"
              className="gap-1.5 bg-red-600 text-white hover:bg-red-700"
              onClick={() => router.push("/production-records")}
            >
              <X className="h-4 w-4" /> Close
            </Button>
          </div>

          <ProductionRecordForm
            mode="create"
            displayMode="page"
            flockId={flockId}
            onSaved={() => router.push("/production-records")}
            onCancel={() => router.push("/production-records")}
          />
        </main>
      </div>
    </div>
  )
}

export default function NewProductionRecordPage() {
  // useSearchParams needs a Suspense boundary during prerender.
  return (
    <Suspense fallback={null}>
      <NewProductionRecordPageInner />
    </Suspense>
  )
}
