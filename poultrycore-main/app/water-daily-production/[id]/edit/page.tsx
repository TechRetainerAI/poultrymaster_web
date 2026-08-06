"use client"

import { useEffect, useState } from "react"
import { useParams, useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { WaterDailyProductionForm } from "@/components/water/daily-production-form"
import { Loader2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { getWaterDailyProduction, type WaterDailyProduction } from "@/lib/api/water"

export default function EditWaterDailyProductionPage() {
  const router = useRouter()
  const params = useParams<{ id: string }>()
  const id = Number(params?.id)
  const logout = useLogout()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [record, setRecord] = useState<WaterDailyProduction | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    ;(async () => {
      try {
        const r = await getWaterDailyProduction(id)
        // The server is the real gate (52611); this keeps the user out of a
        // form whose save would just bounce.
        if (r.status === "Posted" || r.status === "Cancelled") {
          toast({ title: `A ${r.status.toLowerCase()} record cannot be edited`, variant: "destructive" })
          router.replace(`/water-daily-production/${id}`)
          return
        }
        setRecord(r)
      } catch (e: any) {
        toast({ title: "Failed to load the record", description: e?.message ?? String(e), variant: "destructive" })
        router.replace("/water-daily-production")
      } finally {
        setLoading(false)
      }
    })()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, id])

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          {loading || !record
            ? <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div>
            : <WaterDailyProductionForm existing={record} />}
        </main>
      </div>
    </div>
  )
}
