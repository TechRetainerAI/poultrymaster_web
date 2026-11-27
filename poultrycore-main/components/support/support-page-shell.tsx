"use client"

import type { ReactNode } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"

/** The app chrome (sidebar, header, scrolling main) around a support page. */
export function SupportPageShell({ children }: { children: ReactNode }) {
  const router = useRouter()
  const handleLogout = () => {
    for (const k of ["auth_token", "refresh_token", "username", "userId", "farmId", "farmName", "isStaff", "isSubscriber"]) {
      localStorage.removeItem(k)
    }
    router.push("/login")
  }
  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          {children}
        </main>
      </div>
    </div>
  )
}
