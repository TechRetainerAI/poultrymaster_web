"use client"

// One flock's lifetime performance on a page of its own -- linkable, with a
// headline summary and the detail as cards below it. The body is the same
// FlockLifetimeView the quick-look dialog renders; this page only adds the
// shell, the back link and (for an open flock) the Close action.

import { useEffect, useState } from "react"
import Link from "next/link"
import { useParams, useRouter } from "next/navigation"
import { ArrowLeft, BarChart3, Flag, Lock } from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { usePermissions } from "@/hooks/use-permissions"
import { useLogout } from "@/hooks/use-logout"
import { useAuthStore } from "@/lib/store/auth-store"
import { clearFlocksCache } from "@/lib/utils/flock-utils"
import type { FlockLifetimeSummary } from "@/lib/api/flock-closeout"
import { FlockLifetimeView } from "@/components/poultry/flock-lifetime-view"
import { FlockCloseoutWizard } from "@/components/poultry/flock-closeout-wizard"

export default function FlockLifetimePage() {
  const params = useParams<{ flockId: string }>()
  const router = useRouter()
  const logout = useLogout()
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const flockId = Number(params?.flockId)
  const validId = Number.isInteger(flockId) && flockId > 0
  const canView = permissions.can("poultry.flock-closeout.view")
  const canClose = permissions.can("poultry.flock-closeout.create")
  const canReopen = permissions.can("poultry.flock-closeout.approve")

  const [summary, setSummary] = useState<FlockLifetimeSummary | null>(null)
  const [reloadKey, setReloadKey] = useState(0)
  const [closing, setClosing] = useState(false)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") router.replace("/dashboard")
  }, [activeFarmType, router])

  const refresh = () => { clearFlocksCache(); setReloadKey((k) => k + 1) }
  const isOpenFlock = summary?.status === "Active" || summary?.status === "Inactive"

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6 lg:p-8">
          <div className="mx-auto max-w-[1600px] space-y-6">
            <Button asChild variant="ghost" size="sm" className="-ml-2 h-8 px-2 text-slate-600 hover:text-slate-900">
              <Link href="/flock-closeout"><ArrowLeft className="h-4 w-4 mr-1" /> Back to Flock Closeout</Link>
            </Button>

            <div className="flex flex-wrap items-start justify-between gap-4">
              <div className="flex min-w-0 items-start gap-3">
                <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-orange-100 text-orange-600">
                  <BarChart3 className="h-5 w-5" />
                </span>
                <div className="min-w-0">
                  <h1 className="truncate text-2xl font-semibold text-slate-900">{summary?.flockName ?? "Flock"}</h1>
                  <p className="mt-0.5 text-sm text-slate-500">
                    Lifetime performance — everything this flock produced, earned and cost.
                  </p>
                </div>
              </div>
              {isOpenFlock && canClose && (
                <Button onClick={() => setClosing(true)} className="h-10">
                  <Flag className="h-4 w-4 mr-1" /> Close flock
                </Button>
              )}
            </div>

            {!permissions.isLoading && !canView ? (
              <Card><CardContent className="p-8 text-center text-slate-600">
                <Lock className="mx-auto mb-2 h-6 w-6 text-slate-400" />
                You do not have access to Flock Closeout.
              </CardContent></Card>
            ) : !validId ? (
              <Card><CardContent className="p-8 text-center text-slate-600">That is not a valid flock.</CardContent></Card>
            ) : (
              <FlockLifetimeView
                flockId={flockId}
                layout="page"
                canReopen={canReopen}
                onReopened={refresh}
                onLoaded={setSummary}
                reloadKey={reloadKey}
              />
            )}
          </div>
        </main>
      </div>

      <FlockCloseoutWizard
        flockId={closing ? flockId : null}
        open={closing}
        onOpenChange={(o) => { if (!o) setClosing(false) }}
        onClosed={refresh}
      />
    </div>
  )
}
