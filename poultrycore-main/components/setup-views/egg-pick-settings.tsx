"use client"

// =============================================================================
// Egg Settings (/business-office/egg-pick-settings; was "Egg Pick Time Settings")
//
// One place for the farm's egg settings, as tabs:
//   - Pick times: the time each pick represents (display/reporting only) and
//     which of the later picks are enabled for entry. Production records are
//     labelled generically (1st..6th Pick). FarmProductionSettings (153, 248).
//   - Egg sorting, Packaging & units, Egg sizes: the same cards as the Egg
//     Sorting Workspace's "Sizes & settings" tab (341–344, 393, 394).
// ?tab=picks|sorting|packaging|sizes opens a tab directly.
// =============================================================================

import { useSetupEmbedded, shellClass, SetupTabActions, useSetupDirty } from "@/components/setup/setup-embed"
import { Suspense, useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { useRouter, useSearchParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { ArrowLeft, Clock, Egg, ExternalLink, Layers, Loader2, Package, Save, Settings } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { useLogout } from "@/hooks/use-logout"
import { usePermissions } from "@/hooks/use-permissions"
import { useEggsPerCrate } from "@/hooks/use-eggs-per-crate"
import { useEggPackaging } from "@/hooks/use-egg-packaging"
import { boxSize } from "@/lib/poultry/egg-packaging"
import { useAuthStore } from "@/lib/store/auth-store"
import { cn } from "@/lib/utils"
import {
  DEFAULT_PICK_SETTINGS,
  getFarmProductionSettings,
  saveFarmProductionSettings,
  formatPickTime,
  type FarmProductionSettings,
} from "@/lib/api/farm-production-settings"
import { getEggClasses, getEggSortingSettings, type EggClass, type EggSortingSettings } from "@/lib/api/egg-sorting"
import { cratesText, fmtCount } from "@/lib/production/egg-sorting"
import { EggSizesCard, EggSortingSettingsCard } from "@/components/egg-sorting/sizes-settings-panel"
import { EggPackagingCard } from "@/components/egg-sorting/egg-packaging-card"

type PickKey = "firstPickTime" | "secondPickTime" | "thirdPickTime" | "fourthPickTime" | "fifthPickTime" | "sixthPickTime"
type ToggleKey = "enableFourthPick" | "enableFifthPick" | "enableSixthPick"

// The three optional rounds each have their own switch rather than one switch
// for "extra picks": a farm that collects five times should not have to enable
// a sixth to get the fifth.
const PICKS: { key: PickKey; n: number; label: string; toggle?: ToggleKey; hint?: string }[] = [
  { key: "firstPickTime", n: 1, label: "1st Pick" },
  { key: "secondPickTime", n: 2, label: "2nd Pick" },
  { key: "thirdPickTime", n: 3, label: "3rd Pick" },
  {
    key: "fourthPickTime", n: 4, label: "4th Pick", toggle: "enableFourthPick",
    hint: "When off, the 4th Pick input is hidden on entry forms. Records and reports still support it, so you can turn it on any time without losing data.",
  },
  {
    key: "fifthPickTime", n: 5, label: "5th Pick", toggle: "enableFifthPick",
    hint: "Sets the time and the label. Production records cannot store a 5th pick yet, so entry forms will start using it once they can.",
  },
  {
    key: "sixthPickTime", n: 6, label: "6th Pick", toggle: "enableSixthPick",
    hint: "Sets the time and the label. Production records cannot store a 6th pick yet, so entry forms will start using it once they can.",
  },
]

const TABS = [
  { value: "picks", label: "Pick times", icon: Clock },
  { value: "sorting", label: "Egg sorting", icon: Settings },
  { value: "packaging", label: "Packaging & units", icon: Package },
  { value: "sizes", label: "Egg sizes", icon: Layers },
] as const
type TabValue = (typeof TABS)[number]["value"]

function EggPickSettingsInner() {
  const embedded = useSetupEmbedded()
  const router = useRouter()
  const searchParams = useSearchParams()
  const logout = useLogout()
  const { toast } = useToast()
  const permissions = usePermissions()
  useEggsPerCrate()
  const packaging = useEggPackaging()
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const canEditEggs = permissions.can("poultry.egg-sorting.edit") || permissions.canEdit

  const initialTab = embedded ? null : searchParams.get("tab")
  const [tab, setTab] = useState<TabValue>(TABS.some((t) => t.value === initialTab) ? (initialTab as TabValue) : "picks")

  // ---- Pick times --------------------------------------------------------
  const [form, setForm] = useState<FarmProductionSettings>(DEFAULT_PICK_SETTINGS)
  const [savedForm, setSavedForm] = useState<FarmProductionSettings>(DEFAULT_PICK_SETTINGS)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    let cancelled = false
    getFarmProductionSettings()
      .then((s) => { if (!cancelled) { setForm(s); setSavedForm(s) } })
      .catch(() => { /* keep defaults */ })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  }, [activeFarmId])

  const picksDirty = JSON.stringify(form) !== JSON.stringify(savedForm)
  useSetupDirty(picksDirty)

  const save = async () => {
    setSaving(true)
    const res = await saveFarmProductionSettings(form)
    if (res.success) {
      if (res.data) { setForm(res.data); setSavedForm(res.data) } else setSavedForm(form)
      toast({ title: "Egg pick settings saved" })
    } else {
      toast({ title: "Save failed", description: res.message || "Please try again.", variant: "destructive" })
    }
    setSaving(false)
  }

  const enabledPicks = PICKS.filter((p) => !p.toggle || form[p.toggle])

  // ---- Egg sorting, packaging, sizes --------------------------------------
  const [settings, setSettings] = useState<EggSortingSettings | null>(null)
  const [classes, setClasses] = useState<EggClass[]>([])
  const [eggError, setEggError] = useState<string | null>(null)

  const loadEggs = useCallback(async () => {
    try {
      setEggError(null)
      const s = await getEggSortingSettings()
      setSettings(s)
      setClasses(await getEggClasses({ includeInactive: true, ensure: s.enableEggSorting }))
    } catch (e) {
      setEggError(e instanceof Error ? e.message : "Could not load egg sorting settings.")
    }
  }, [])
  useEffect(() => { if (activeFarmId) void loadEggs() }, [activeFarmId, loadEggs])
  const eggsChanged = () => { void loadEggs() }

  const unsortedClass = classes.find((c) => c.classKind === "Unsorted")
  const activeSizes = classes.filter((c) => c.classKind === "Size" && c.isActive).length

  // Small status line under each tab label, so the farm's setup reads at a glance.
  const tabStatus: Record<TabValue, string> = {
    picks: loading ? "…" : `${enabledPicks.length} picks a day`,
    sorting: settings ? (settings.enableEggSorting ? "On" : "Off") : "…",
    packaging: boxSize(packaging) != null ? `Boxes of ${packaging.cratesPerBox} crates` : `Crates of ${packaging.eggsPerCrate}`,
    sizes: settings ? `${activeSizes} active` : "…",
  }

  return (
    <div className={shellClass(embedded, "flex h-screen bg-slate-50")}>
      {!embedded && <DashboardSidebar onLogout={logout} />}
      <div className={shellClass(embedded, "flex-1 flex flex-col min-w-0")}>
        {!embedded && <DashboardHeader />}
        <main className={embedded ? "min-w-0" : "flex-1 overflow-y-auto overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-6"}>
          <div className="mx-auto max-w-5xl space-y-6">
            {/* Header */}
            <div className={embedded ? "hidden" : "relative overflow-hidden rounded-2xl border border-amber-100 bg-gradient-to-br from-amber-50 via-white to-emerald-50 p-4 sm:p-6 shadow-sm"}>
              <div className="flex flex-wrap items-start justify-between gap-4">
                <div className="flex items-start gap-3 min-w-0">
                  <Button variant="ghost" size="icon" onClick={() => router.push("/business-office/setup")} className="shrink-0 -ml-2">
                    <ArrowLeft className="w-5 h-5" />
                  </Button>
                  <div className="w-12 h-12 shrink-0 rounded-xl bg-amber-500 text-white shadow-sm flex items-center justify-center">
                    <Egg className="w-6 h-6" />
                  </div>
                  <div className="min-w-0">
                    <h1 className="text-2xl font-bold text-slate-900">Egg Settings</h1>
                    <p className="text-sm text-slate-600 max-w-2xl">
                      Everything about how this farm collects, counts, sorts and prices its eggs — pick times, egg sorting,
                      packaging units and egg sizes.
                    </p>
                  </div>
                </div>
                <SetupTabActions><Button variant="outline" size="sm" asChild className="bg-white/70">
                  <Link href="/poultry-egg-sorting"><ExternalLink className="w-4 h-4 mr-1.5" />Open Egg Sorting</Link>
                </Button></SetupTabActions>
              </div>
            </div>

            <Tabs value={tab} onValueChange={(v) => setTab(v as TabValue)} className="gap-4">
              <TabsList className="grid h-auto w-full grid-cols-2 gap-1 rounded-xl bg-white p-1 shadow-sm border border-slate-200 sm:grid-cols-4">
                {TABS.map(({ value, label, icon: Icon }) => (
                  <TabsTrigger
                    key={value}
                    value={value}
                    className="h-auto flex-col items-start gap-0.5 rounded-lg px-3 py-2 text-left whitespace-normal data-[state=active]:bg-amber-50 data-[state=active]:text-amber-900 data-[state=active]:shadow-none data-[state=active]:border-amber-200"
                  >
                    <span className="flex items-center gap-1.5 text-sm font-semibold">
                      <Icon className="w-4 h-4" /> {label}
                    </span>
                    <span className="text-[11px] font-normal text-slate-500">{tabStatus[value]}</span>
                  </TabsTrigger>
                ))}
              </TabsList>

              {eggError && tab !== "picks" && (
                <Card className="border-rose-200 bg-rose-50"><CardContent className="p-4 text-sm text-rose-800">{eggError}</CardContent></Card>
              )}

              {/* ---- Pick times ---- */}
              <TabsContent value="picks" className="space-y-4">
                <Card className="rounded-xl border border-slate-200 shadow-sm">
                  <CardContent className="p-4 sm:p-6 space-y-5">
                    <div>
                      <div className="flex items-center gap-2 font-semibold text-slate-900">
                        <Clock className="h-4 w-4 text-emerald-600" /> Pick times
                      </div>
                      <p className="text-sm text-slate-600">
                        The time of day each egg pick represents. Used for display and reporting; production records are
                        labelled 1st Pick through 6th Pick.
                      </p>
                    </div>

                    {loading ? (
                      <div className="flex items-center gap-2 text-slate-500 py-8">
                        <Loader2 className="w-4 h-4 animate-spin" /> Loading…
                      </div>
                    ) : (
                      <>
                        {/* The day at a glance */}
                        <div className="flex flex-wrap items-center gap-2 rounded-lg bg-slate-50 border border-slate-100 px-3 py-2.5">
                          <span className="text-xs font-medium text-slate-500 mr-1">Your day:</span>
                          {enabledPicks.map((p, i) => (
                            <span key={p.key} className="flex items-center gap-2">
                              <span className="inline-flex items-center gap-1.5 rounded-full bg-white border border-emerald-200 px-2.5 py-0.5 text-xs font-medium text-emerald-800">
                                <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" />
                                {p.label} · {formatPickTime(form[p.key]) || "default"}
                              </span>
                              {i < enabledPicks.length - 1 && <span className="text-slate-300">→</span>}
                            </span>
                          ))}
                        </div>

                        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
                          {PICKS.map((p) => {
                            const enabled = !p.toggle || form[p.toggle]
                            return (
                              <div
                                key={p.key}
                                className={cn(
                                  "rounded-xl border p-4 space-y-3 transition-colors",
                                  enabled ? "border-slate-200 bg-white" : "border-dashed border-slate-200 bg-slate-50",
                                )}
                              >
                                <div className="flex items-center justify-between gap-2">
                                  <div className="flex items-center gap-2">
                                    <span className={cn(
                                      "flex h-7 w-7 items-center justify-center rounded-full text-xs font-bold",
                                      enabled ? "bg-emerald-100 text-emerald-700" : "bg-slate-200 text-slate-500",
                                    )}>
                                      {p.n}
                                    </span>
                                    <Label htmlFor={`pick-${p.key}`} className="text-sm font-semibold text-slate-800">{p.label}</Label>
                                  </div>
                                  {p.toggle ? (
                                    <Switch
                                      checked={form[p.toggle]}
                                      onCheckedChange={(checked) => setForm({ ...form, [p.toggle as ToggleKey]: checked })}
                                      disabled={saving}
                                      aria-label={`Enable ${p.label}`}
                                    />
                                  ) : (
                                    <span className="text-[11px] font-medium text-slate-400">Always on</span>
                                  )}
                                </div>
                                <Input
                                  id={`pick-${p.key}`}
                                  type="time"
                                  value={form[p.key] || ""}
                                  onChange={(e) => setForm({ ...form, [p.key]: e.target.value })}
                                  disabled={saving}
                                  className={cn(!enabled && "opacity-70")}
                                />
                                <p className="text-xs text-slate-500">
                                  {formatPickTime(form[p.key]) || "Not set — falls back to the default."}
                                </p>
                                {p.hint && <p className="text-[11px] leading-snug text-slate-400">{p.hint}</p>}
                              </div>
                            )
                          })}
                        </div>
                      </>
                    )}
                  </CardContent>
                </Card>

                {/* Save bar: sits in the flow after the pick times. It used to be
                    sticky and floated over the cards; it now only turns amber
                    when there are unsaved changes (leaving still asks first). */}
                <div className={cn(
                  "flex flex-wrap items-center justify-between gap-3 rounded-xl border px-4 py-3",
                  picksDirty ? "border-amber-200 bg-amber-50" : "border-slate-200 bg-white",
                )}>
                  <span className="text-sm text-slate-600">
                    {picksDirty ? "You have unsaved changes to the pick times." : "Pick times are saved."}
                  </span>
                  <div className="flex gap-2">
                    <Button variant="outline" onClick={() => setForm(savedForm)} disabled={saving || !picksDirty}>
                      Discard
                    </Button>
                    <Button onClick={save} disabled={saving || loading || !picksDirty} className="min-w-[140px]">
                      {saving ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</> : <><Save className="w-4 h-4 mr-2" />Save pick times</>}
                    </Button>
                  </div>
                </div>
              </TabsContent>

              {/* ---- Egg sorting ---- */}
              <TabsContent value="sorting" className="space-y-4">
                <EggSortingSettingsCard settings={settings} classes={classes} canEdit={canEditEggs} onChanged={eggsChanged} />
                {unsortedClass && (
                  <p className="text-xs text-slate-500 px-1">
                    Unsorted / General eggs on hand: {fmtCount(unsortedClass.onHand)} ({cratesText(unsortedClass.onHand)}). Production always adds to Unsorted.
                  </p>
                )}
              </TabsContent>

              {/* ---- Packaging & units ---- */}
              <TabsContent value="packaging" className="space-y-4">
                <EggPackagingCard canEdit={canEditEggs} />
              </TabsContent>

              {/* ---- Egg sizes ---- */}
              <TabsContent value="sizes" className="space-y-4">
                <EggSizesCard classes={classes} canEdit={canEditEggs} onChanged={eggsChanged} />
              </TabsContent>

            </Tabs>
          </div>
        </main>
      </div>
    </div>
  )
}

export function EggPickSettingsPage() {
  // useSearchParams needs a Suspense boundary during prerender.
  return (
    <Suspense fallback={null}>
      <EggPickSettingsInner />
    </Suspense>
  )
}
