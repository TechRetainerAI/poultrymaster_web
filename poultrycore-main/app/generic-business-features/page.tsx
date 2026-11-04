"use client"

// Setup → Business Features
//
// The page where an authorized user manages which features their Generic
// company has active. Replaces the module-toggle section that was previously
// buried in /generic-settings — this page is purpose-built for the task and
// includes recommended indicators, grouped features, dependency checks,
// and a "Restore Recommended Features" action.
//
// Turning a feature off hides its menus and blocks new writes. It never
// deletes data — re-enabling restores access to all historical records.

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Switch } from "@/components/ui/switch"
import { Badge } from "@/components/ui/badge"
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription,
} from "@/components/ui/dialog"
import {
  Loader2, Save, Settings2, RotateCcw, Check, Info, ShieldCheck,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  getModuleSettings, saveModuleSettings, getBusinessTemplate,
  type GenericModuleSettings,
} from "@/lib/api/generic-subscriptions"
import { invalidateGenericModules } from "@/hooks/use-generic-modules"
import { businessTypeForIndustry } from "@/lib/companies/business-types"
import {
  getRecommendedModules, groupedFeatures,
  type ModuleKey, type RecommendedModules,
} from "@/lib/generic/recommended-modules"

// ---------------------------------------------------------------------------
// Feature dependency rules
// ---------------------------------------------------------------------------
// If feature A depends on feature B, disabling B while A is on should warn.
const DEPENDENCIES: { feature: ModuleKey; requires: ModuleKey; reason: string }[] = [
  { feature: "enableInventory",        requires: "enableProducts",   reason: "Inventory tracks stock for your products." },
  { feature: "enableStockAdjustments", requires: "enableInventory",  reason: "Stock adjustments correct inventory counts." },
  { feature: "enableInternalUse",      requires: "enableInventory",  reason: "Internal use consumes inventory stock." },
  { feature: "enableInvoices",         requires: "enableSubscriptions", reason: "Invoices are raised by billing runs from subscriptions." },
  { feature: "enableCustomerBalances", requires: "enableInvoices",   reason: "Customer balances are built from invoices." },
]

function getDependencyWarning(
  key: ModuleKey,
  disabling: boolean,
  modules: GenericModuleSettings,
): string | null {
  if (!disabling) return null
  // Check if any enabled feature depends on the one being disabled
  for (const dep of DEPENDENCIES) {
    if (dep.requires === key && modules[dep.feature]) {
      return `${dep.reason} Disabling this will also hide dependent features.`
    }
  }
  return null
}

/** Features that depend on the one being disabled. */
function getDependents(key: ModuleKey, modules: GenericModuleSettings): ModuleKey[] {
  const result: ModuleKey[] = []
  const queue = [key]
  while (queue.length > 0) {
    const current = queue.shift()!
    for (const dep of DEPENDENCIES) {
      if (dep.requires === current && modules[dep.feature] && !result.includes(dep.feature)) {
        result.push(dep.feature)
        queue.push(dep.feature)
      }
    }
  }
  return result
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function GenericBusinessFeaturesPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const logout = useLogout()
  const { toast } = useToast()

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [modules, setModules] = useState<GenericModuleSettings | null>(null)
  const [recommended, setRecommended] = useState<RecommendedModules | null>(null)
  const [industryLabel, setIndustryLabel] = useState<string | null>(null)
  const [dirty, setDirty] = useState(false)

  // Restore dialog
  const [showRestore, setShowRestore] = useState(false)
  const [restoring, setRestoring] = useState(false)

  useEffect(() => {
    if (!activeFarmType) return
    if (activeFarmType !== "Generic") {
      router.replace("/dashboard")
      return
    }
    let cancelled = false
    ;(async () => {
      const [m, t] = await Promise.allSettled([
        getModuleSettings(),
        getBusinessTemplate(),
      ])
      if (cancelled) return
      if (m.status === "fulfilled") setModules(m.value)
      else toast({ title: "Could not load feature settings", description: String(m.reason?.message ?? m.reason), variant: "destructive" })

      if (t.status === "fulfilled") {
        const rec = getRecommendedModules(t.value?.genericBusinessTemplate)
        setRecommended(rec)
        const bt = businessTypeForIndustry(t.value?.genericIndustryTemplate)
        setIndustryLabel(bt?.label ?? t.value?.genericIndustryTemplate ?? null)
      }
      setLoading(false)
    })()
    return () => { cancelled = true }
  }, [activeFarmType, router, toast])

  const toggle = (key: ModuleKey) => {
    if (!modules) return
    const newValue = !modules[key]
    let updated = { ...modules, [key]: newValue }

    // If disabling, also disable dependents
    if (!newValue) {
      const deps = getDependents(key, modules)
      for (const dep of deps) {
        updated = { ...updated, [dep]: false }
      }
    }

    setModules(updated)
    setDirty(true)
  }

  const save = async () => {
    if (!modules) return
    setSaving(true)
    try {
      const { farmId, ...rest } = modules
      const saved = await saveModuleSettings(rest)
      if (saved) setModules(saved)
      invalidateGenericModules(activeFarmId ?? undefined)
      setDirty(false)
      toast({ title: "Business features saved" })
    } catch (e: any) {
      toast({ title: "Could not save", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  // Restore recommended
  const restoreChanges = (): { toEnable: ModuleKey[]; toDisable: ModuleKey[] } => {
    if (!modules || !recommended) return { toEnable: [], toDisable: [] }
    const toEnable: ModuleKey[] = []
    const toDisable: ModuleKey[] = []
    for (const key of Object.keys(recommended) as ModuleKey[]) {
      if (recommended[key] && !modules[key]) toEnable.push(key)
      if (!recommended[key] && modules[key]) toDisable.push(key)
    }
    return { toEnable, toDisable }
  }

  const doRestore = async () => {
    if (!modules || !recommended) return
    setRestoring(true)
    try {
      const restored: GenericModuleSettings = { ...modules }
      for (const key of Object.keys(recommended) as ModuleKey[]) {
        ;(restored as any)[key] = recommended[key]
      }
      const { farmId, ...rest } = restored
      const saved = await saveModuleSettings(rest)
      if (saved) setModules(saved)
      invalidateGenericModules(activeFarmId ?? undefined)
      setDirty(false)
      setShowRestore(false)
      toast({ title: "Recommended features restored", description: "Your menus now match the recommended configuration." })
    } catch (e: any) {
      toast({ title: "Could not restore", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setRestoring(false)
    }
  }

  const groups = groupedFeatures()
  const { toEnable, toDisable } = restoreChanges()
  const hasChangesToRestore = toEnable.length > 0 || toDisable.length > 0

  // Feature label from the catalog
  const featureLabel = (key: ModuleKey) => {
    for (const g of groups) {
      for (const f of g.features) {
        if (f.key === key) return f.label
      }
    }
    return key
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="max-w-4xl mx-auto space-y-4">
            {/* Page header */}
            <div className="flex items-end justify-between flex-wrap gap-2">
              <div>
                <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                  <Settings2 className="h-6 w-6 text-indigo-600" />
                  Business Features
                </h1>
                <p className="text-sm text-slate-500 mt-1">
                  Your business is already set up with the recommended features. You can
                  customise which features appear in your workspace anytime.
                </p>
              </div>
              <div className="flex gap-2">
                {recommended && (
                  <Button
                    variant="outline"
                    onClick={() => setShowRestore(true)}
                    disabled={loading || !hasChangesToRestore}
                  >
                    <RotateCcw className="h-4 w-4 mr-1" /> Restore Recommended
                  </Button>
                )}
                <Button onClick={save} disabled={saving || loading || !modules || !dirty}>
                  {saving ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <Save className="h-4 w-4 mr-1" />}
                  Save Changes
                </Button>
              </div>
            </div>

            {loading ? (
              <div className="flex items-center gap-2 text-slate-500">
                <Loader2 className="h-4 w-4 animate-spin" /> Loading…
              </div>
            ) : (
              <>
                {/* Template info card */}
                {industryLabel && (
                  <Card>
                    <CardContent className="p-4 flex items-center gap-3">
                      <div className="flex h-10 w-10 items-center justify-center rounded-full bg-indigo-100 shrink-0">
                        <ShieldCheck className="h-5 w-5 text-indigo-600" />
                      </div>
                      <div className="min-w-0">
                        <div className="text-sm font-medium text-slate-900">
                          Business Type: {industryLabel}
                        </div>
                        <div className="text-xs text-slate-500">
                          Recommended Configuration: {recommended ? "Applied" : "Not available"}
                        </div>
                      </div>
                    </CardContent>
                  </Card>
                )}

                {/* Feature groups */}
                {!modules ? (
                  <Card>
                    <CardContent className="p-6 text-center text-slate-500">
                      Feature settings could not be loaded.
                    </CardContent>
                  </Card>
                ) : (
                  <div className="space-y-4">
                    {groups.map(({ group, features }) => (
                      <Card key={group}>
                        <CardHeader className="pb-2">
                          <CardTitle className="text-base">{group}</CardTitle>
                        </CardHeader>
                        <CardContent>
                          <div className="divide-y">
                            {features.map((f) => {
                              const isEnabled = Boolean(modules[f.key])
                              const isRecommended = recommended?.[f.key] ?? null

                              return (
                                <div
                                  key={f.key}
                                  className="flex items-center justify-between gap-4 py-3"
                                >
                                  <div className="min-w-0 flex-1">
                                    <div className="flex items-center gap-2 flex-wrap">
                                      <span className="text-sm font-medium text-slate-900">
                                        {f.label}
                                      </span>
                                      {isRecommended === true && (
                                        <Badge variant="secondary" className="text-xs bg-indigo-50 text-indigo-700 border-indigo-200">
                                          Recommended
                                        </Badge>
                                      )}
                                    </div>
                                    <p className="text-xs text-slate-500 mt-0.5">
                                      {f.description}
                                    </p>
                                  </div>
                                  <div className="flex items-center gap-3 shrink-0">
                                    <span className={`text-xs font-medium ${isEnabled ? "text-emerald-600" : "text-slate-400"}`}>
                                      {isEnabled ? "Enabled" : "Disabled"}
                                    </span>
                                    <Switch
                                      checked={isEnabled}
                                      onCheckedChange={() => toggle(f.key)}
                                    />
                                  </div>
                                </div>
                              )
                            })}
                          </div>
                        </CardContent>
                      </Card>
                    ))}

                    {/* Info note */}
                    <div className="rounded-lg border border-slate-200 bg-slate-50 p-4 flex gap-3">
                      <Info className="h-5 w-5 text-slate-400 shrink-0 mt-0.5" />
                      <div className="text-sm text-slate-600">
                        <p className="font-medium">Disabling a feature hides it from menus</p>
                        <p className="mt-1">
                          All your data is preserved. If you re-enable a feature later,
                          everything — transactions, reports, history — will still be there.
                        </p>
                      </div>
                    </div>
                  </div>
                )}
              </>
            )}
          </div>
        </main>
      </div>

      {/* Restore Recommended Features dialog */}
      <Dialog open={showRestore} onOpenChange={setShowRestore}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Restore Recommended Features</DialogTitle>
            <DialogDescription>
              This will reset your features to the recommended configuration for{" "}
              <strong>{industryLabel}</strong>. Your data is never deleted.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-3">
            {toEnable.length > 0 && (
              <div>
                <p className="text-sm font-medium text-emerald-700 mb-1">Features to enable:</p>
                <ul className="space-y-1">
                  {toEnable.map((key) => (
                    <li key={key} className="text-sm text-slate-600 flex items-center gap-2">
                      <Check className="h-3.5 w-3.5 text-emerald-500" />
                      {featureLabel(key)}
                    </li>
                  ))}
                </ul>
              </div>
            )}

            {toDisable.length > 0 && (
              <div>
                <p className="text-sm font-medium text-amber-700 mb-1">Features to disable:</p>
                <ul className="space-y-1">
                  {toDisable.map((key) => (
                    <li key={key} className="text-sm text-slate-600 flex items-center gap-2">
                      <span className="h-3.5 w-3.5 flex items-center justify-center text-amber-500">—</span>
                      {featureLabel(key)}
                    </li>
                  ))}
                </ul>
              </div>
            )}

            <div className="rounded-lg bg-slate-50 p-3">
              <p className="text-xs text-slate-500">
                All existing data, transactions, reports and history will be preserved.
                No records are deleted when features are enabled or disabled.
              </p>
            </div>

            <div className="flex justify-end gap-2 pt-1">
              <Button variant="ghost" onClick={() => setShowRestore(false)} disabled={restoring}>
                Cancel
              </Button>
              <Button onClick={doRestore} disabled={restoring}>
                {restoring ? (
                  <><Loader2 className="h-4 w-4 animate-spin mr-1" /> Restoring…</>
                ) : (
                  <><RotateCcw className="h-4 w-4 mr-1" /> Restore Recommended Features</>
                )}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}
