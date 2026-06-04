"use client"

// Issue 1 (test-report, 2026-06-03): the standalone Drivers page was
// redundant with People > Staff (a staff member with role=Driver). Staff is
// now the single source of truth for drivers — the form exposes License
// number + Assigned vehicle when Role = Driver, and on save it auto-syncs a
// matching WaterDrivers row so the delivery flows (Vehicle Loading, Driver
// Returns, etc.) that key off the WaterDrivers table keep working without
// any backend change.
//
// We leave this route file behind so bookmarks / old links resolve cleanly,
// and redirect to /water-staff with a Driver-role filter.

import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Users2, ArrowRight } from "lucide-react"
import { useLogout } from "@/hooks/use-logout"

export default function WaterDriversRedirect() {
  const router = useRouter()
  const logout = useLogout()

  useEffect(() => {
    // Auto-redirect after a short pause so anyone landing here understands why.
    const t = setTimeout(() => router.replace("/water-staff"), 1800)
    return () => clearTimeout(t)
  }, [router])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <Card className="max-w-2xl">
            <CardContent className="p-6 space-y-3">
              <div className="flex items-center gap-2 text-sky-700">
                <Users2 className="h-6 w-6" />
                <h1 className="text-xl font-semibold">Drivers moved into Staff</h1>
              </div>
              <p className="text-sm text-slate-600">
                Drivers are now managed under <strong>People &rsaquo; Staff</strong>.
                Add a staff member with the role <em>Driver</em> — the License
                number and Assigned vehicle fields appear automatically.
              </p>
              <Button onClick={() => router.replace("/water-staff")}>
                Go to Staff <ArrowRight className="h-4 w-4 ml-1" />
              </Button>
            </CardContent>
          </Card>
        </main>
      </div>
    </div>
  )
}
