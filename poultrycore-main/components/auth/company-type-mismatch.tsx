"use client"

import { useRouter } from "next/navigation"
import { ShieldAlert } from "lucide-react"
import { dashboardHomeForType, type CompanyType } from "@/lib/api/companies"

interface Props {
  activeFarmType: CompanyType | null
}

export function CompanyTypeMismatch({ activeFarmType }: Props) {
  const router = useRouter()

  return (
    <div className="fixed inset-0 z-[9998] flex items-center justify-center bg-white dark:bg-slate-950">
      <div className="mx-4 max-w-md text-center">
        <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-amber-100 dark:bg-amber-900/30">
          <ShieldAlert className="h-8 w-8 text-amber-600 dark:text-amber-400" />
        </div>
        <h1 className="mb-2 text-xl font-semibold text-slate-900 dark:text-slate-100">
          Page Not Available
        </h1>
        <p className="mb-6 text-sm text-slate-600 dark:text-slate-400">
          This page is not available for your selected business type.
          Please navigate back to your dashboard.
        </p>
        <button
          type="button"
          onClick={() => router.replace(dashboardHomeForType(activeFarmType))}
          className="inline-flex items-center gap-2 rounded-lg bg-slate-900 px-5 py-2.5 text-sm font-medium text-white hover:bg-slate-800 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-slate-200"
        >
          Back to Dashboard
        </button>
      </div>
    </div>
  )
}
