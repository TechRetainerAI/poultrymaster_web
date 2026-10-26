"use client"

import { useRouter } from "next/navigation"
import { ShieldAlert } from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { type CompanyType } from "@/lib/api/companies"

interface Props {
  activeFarmType: CompanyType | null
}

export function CompanyTypeMismatch({ activeFarmType }: Props) {
  const router = useRouter()

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
    <div className="fixed inset-0 z-[9998] flex min-h-screen bg-slate-50 dark:bg-slate-950">
      <DashboardSidebar onLogout={handleLogout} />

      <div className="flex-1 flex flex-col w-full lg:w-auto min-w-0">
        <DashboardHeader />

        <main className="flex-1 flex items-center justify-center p-4 sm:p-6">
          <div className="mx-4 max-w-md text-center">
            <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-amber-100 dark:bg-amber-900/30">
              <ShieldAlert className="h-8 w-8 text-amber-600 dark:text-amber-400" />
            </div>
            <h1 className="mb-2 text-xl font-semibold text-slate-900 dark:text-slate-100">
              Page Not Available
            </h1>
            <p className="text-sm text-slate-600 dark:text-slate-400">
              This page is not available for your selected business type.
              Use the sidebar to navigate to the correct page.
            </p>
          </div>
        </main>
      </div>
    </div>
  )
}
