"use client"

// Full-page EDIT batch production record.
//
// Same deal as the add route: the modal is the default, this stays for room,
// direct links and bookmarks, and renders the SAME
// <BatchProductionRecordForm>.
//
// This file used to hold its own ~820-line copy of the form.

import { useParams, useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Boxes, X } from "lucide-react"
import { BatchProductionRecordForm } from "@/components/production/batch-production-record-form"

export default function EditBatchProductionRecordPage() {
  const router = useRouter()
  const params = useParams()
  const recordId = Number(Array.isArray(params?.id) ? params.id[0] : params?.id)

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
                <h1 className="text-2xl font-bold text-slate-900">Edit Batch Production Record</h1>
                <p className="text-sm text-slate-600">Update total production for a batch or group of flocks</p>
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

          {Number.isFinite(recordId) && recordId > 0 ? (
            <BatchProductionRecordForm
              mode="edit"
              displayMode="page"
              recordId={recordId}
              onSaved={() => router.push("/batch-production-records")}
              onCancel={() => router.push("/batch-production-records")}
            />
          ) : (
            <p className="text-sm text-slate-500">That batch production record could not be found.</p>
          )}
        </main>
      </div>
    </div>
  )
}
