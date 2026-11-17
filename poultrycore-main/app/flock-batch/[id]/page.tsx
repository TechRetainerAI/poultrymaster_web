"use client"

import { useRouter, useParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Bird, ArrowLeft } from "lucide-react"
import { FlockBatchEditForm } from "@/components/poultry/flock-batch-edit-form"

export default function EditFlockBatchPage() {
  const router = useRouter()
  const params = useParams()
  const batchId = params.id as string

  const handleLogout = () => {
    localStorage.removeItem("auth_token")
    localStorage.removeItem("refresh_token")
    localStorage.removeItem("username")
    localStorage.removeItem("userId")
    localStorage.removeItem("farmId")
    localStorage.removeItem("farmName")
    localStorage.removeItem("isStaff")
    localStorage.removeItem("isSubscriber")
    router.push("/login")
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6 max-w-3xl">
            {/* Page Header */}
            <div className="flex items-center gap-3">
              <Button variant="ghost" size="icon" onClick={() => router.push("/flock-batch")} className="shrink-0">
                <ArrowLeft className="w-5 h-5" />
              </Button>
              <div className="w-10 h-10 bg-green-100 rounded-lg flex items-center justify-center">
                <Bird className="w-5 h-5 text-green-600" />
              </div>
              <div>
                <h1 className="text-2xl font-bold text-slate-900">Edit Flock Batch</h1>
                <p className="text-slate-600 text-sm">Update the flock batch information below</p>
              </div>
            </div>

            <FlockBatchEditForm batchId={batchId}
              onSaved={() => router.push("/flock-batch")}
              onCancel={() => router.push("/flock-batch")} />
          </div>
        </main>
      </div>
    </div>
  )
}
