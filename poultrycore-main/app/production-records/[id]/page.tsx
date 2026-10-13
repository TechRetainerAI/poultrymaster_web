"use client"

// Full-page EDIT production record.
//
// Same deal as the add route: the modal is the default, this stays for room,
// direct links and bookmarks, and renders the SAME <ProductionRecordForm>.
//
// This file used to hold its own ~780-line copy of the form, which had already
// drifted from the add page's copy.

import { Suspense } from "react"
import { useParams, useRouter, useSearchParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { ArrowLeft, FileText, X } from "lucide-react"
import { ProductionRecordForm } from "@/components/production/production-record-form"

export default function EditProductionRecordPage() {
  // useSearchParams needs a Suspense boundary during prerender.
  return (
    <Suspense fallback={null}>
      <EditProductionRecordInner />
    </Suspense>
  )
}

function EditProductionRecordInner() {
  const router = useRouter()
  const params = useParams()
  const recordId = Number(Array.isArray(params?.id) ? params.id[0] : params?.id)
  // ?returnTo=/poultry-egg-sorting (from the Egg Sorting Workspace): Close,
  // Cancel and Save go back there instead of to Production Records. Same-site
  // paths only, so the link cannot send anyone off the app.
  const returnParam = useSearchParams().get("returnTo")
  const returnTo = returnParam && returnParam.startsWith("/") && !returnParam.startsWith("//") ? returnParam : null
  const back = () => router.push(returnTo ?? "/production-records")

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
                <h1 className="text-2xl font-bold text-slate-900">Edit Egg Production Record</h1>
                <p className="text-sm text-slate-600">Update production record details</p>
              </div>
            </div>
            {returnTo?.startsWith("/poultry-egg-sorting") ? (
              <Button type="button" size="sm" className="gap-1.5 bg-amber-500 text-white hover:bg-amber-600" onClick={back}>
                <ArrowLeft className="h-4 w-4" /> Back to Egg Sorting
              </Button>
            ) : (
              <Button
                type="button"
                size="sm"
                className="gap-1.5 bg-red-600 text-white hover:bg-red-700"
                onClick={back}
              >
                <X className="h-4 w-4" /> Close
              </Button>
            )}
          </div>

          {Number.isFinite(recordId) && recordId > 0 ? (
            <ProductionRecordForm
              mode="edit"
              displayMode="page"
              recordId={recordId}
              onSaved={back}
              onCancel={back}
            />
          ) : (
            <p className="text-sm text-slate-500">That production record could not be found.</p>
          )}
        </main>
      </div>
    </div>
  )
}
