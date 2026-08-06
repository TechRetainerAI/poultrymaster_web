"use client"

import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { WaterDailyProductionForm } from "@/components/water/daily-production-form"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"

export default function NewWaterDailyProductionPage() {
  const router = useRouter()
  const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") router.replace("/dashboard")
  }, [activeFarmType, router])

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <WaterDailyProductionForm />
        </main>
      </div>
    </div>
  )
}
