"use client"

// Egg Sorting Settings (Setup > Production). Only the settings: turn egg
// sorting on or off, the Daily Closing policy, eggs per crate, and the sizes
// with their prices. The same panel as the Egg Sorting Workspace's
// "Sizes & settings" tab, without the workspace around it.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { Settings } from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { useLogout } from "@/hooks/use-logout"
import { usePermissions } from "@/hooks/use-permissions"
import { useEggsPerCrate } from "@/hooks/use-eggs-per-crate"
import { useAuthStore } from "@/lib/store/auth-store"
import { getEggClasses, getEggSortingSettings, type EggClass, type EggSortingSettings } from "@/lib/api/egg-sorting"
import { cratesText, fmtCount } from "@/lib/production/egg-sorting"
import { SizesSettingsPanel } from "@/components/egg-sorting/sizes-settings-panel"

export default function EggSortingSettingsPage() {
  const router = useRouter()
  const logout = useLogout()
  const permissions = usePermissions()
  useEggsPerCrate()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const canEdit = permissions.can("poultry.egg-sorting.edit") || permissions.canEdit

  const [settings, setSettings] = useState<EggSortingSettings | null>(null)
  const [classes, setClasses] = useState<EggClass[]>([])
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") router.replace("/dashboard")
  }, [activeFarmType, router])

  const load = useCallback(async () => {
    try {
      setError(null)
      const s = await getEggSortingSettings()
      setSettings(s)
      setClasses(await getEggClasses({ includeInactive: true, ensure: s.enableEggSorting }))
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not load egg sorting settings.")
    }
  }, [])
  useEffect(() => { if (activeFarmId) void load() }, [activeFarmId, load])

  const unsortedClass = classes.find((c) => c.classKind === "Unsorted")

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex min-w-0 flex-1 flex-col">
        <DashboardHeader />
        <main className="min-w-0 flex-1 overflow-x-hidden p-4 pb-6 sm:p-6">
          <div className="space-y-4">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div className="flex items-start gap-3">
                <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-amber-100">
                  <Settings className="h-5 w-5 text-amber-700" />
                </div>
                <div>
                  <h1 className="text-2xl font-bold text-slate-900">Egg Sorting Settings</h1>
                  <p className="text-sm text-slate-600">
                    Turn egg sorting on or off, and set the egg sizes and their prices.
                  </p>
                </div>
              </div>
              <Button variant="outline" size="sm" asChild><Link href="/poultry-egg-sorting">Open Egg Sorting Workspace</Link></Button>
            </div>

            {error && <Card className="border-rose-200 bg-rose-50"><CardContent className="p-4 text-sm text-rose-800">{error}</CardContent></Card>}

            <SizesSettingsPanel settings={settings} classes={classes} canEdit={canEdit} onChanged={() => void load()} />
            {unsortedClass && (
              <p className="text-xs text-slate-500">
                Unsorted / General eggs on hand: {fmtCount(unsortedClass.onHand)} ({cratesText(unsortedClass.onHand)}). Production always adds to Unsorted.
              </p>
            )}
          </div>
        </main>
      </div>
    </div>
  )
}
