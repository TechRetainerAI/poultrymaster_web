"use client"

// 440: Tools > Batch Bird Count. A farm counts its pens and sets every flock of
// a batch to its counted birds in one save; each flock's difference is posted
// as its own Stock Count Correction (see components/poultry/batch-bird-count-dialog).

import { useState } from "react"
import Link from "next/link"
import { ClipboardList } from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { useLogout } from "@/hooks/use-logout"
import { usePermissions } from "@/hooks/use-permissions"
import { BatchBirdCountForm } from "@/components/poultry/batch-bird-count-dialog"

export default function PoultryBatchBirdCountPage() {
  const logout = useLogout()
  // 441: its own permission; saving needs .create (checked in the form).
  const canView = usePermissions().can("poultry.bird-count.view")
  // Bumped after a save: a fresh form with the new bird figures.
  const [resetKey, setResetKey] = useState(0)

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex min-w-0 flex-1 flex-col">
        <DashboardHeader />
        <main className="min-w-0 flex-1 overflow-y-auto overflow-x-hidden p-4 pb-6 sm:p-6">
          <div className="space-y-4">
            <div className="flex items-start gap-3">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-blue-100">
                <ClipboardList className="h-5 w-5 text-blue-700" />
              </div>
              <div>
                <h1 className="text-2xl font-bold text-slate-900">Batch Bird Count</h1>
                <p className="text-sm text-slate-600">
                  Counted your pens? Pick the batch and enter the birds you counted in each flock. Each flock&apos;s
                  difference is saved as its own Stock Count Correction, exactly as if entered one by one on{" "}
                  <Link href="/poultry-stock" className="text-blue-600 hover:underline">Stock Movements</Link>,
                  where each one can be reversed.
                </p>
              </div>
            </div>
            {canView ? (
              <BatchBirdCountForm layout="page" resetKey={resetKey} onSaved={() => setResetKey((k) => k + 1)} />
            ) : (
              <div className="rounded-lg border border-slate-200 bg-white px-4 py-12 text-center text-sm text-slate-500">
                You do not have access to Batch Bird Count. Ask an admin for the Batch Bird Count permission.
              </div>
            )}
          </div>
        </main>
      </div>
    </div>
  )
}
