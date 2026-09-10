"use client"

// Water Financial Settings -> Cost Recognition.
//
// Two choices: when packaging costs reach Profit & Loss, and when treatment
// chemical costs do. They are independent, and either can be left exactly as it
// is today. Underneath them, a per-item override for the exceptions.
//
// WHAT THIS PAGE IS CAREFUL ABOUT
// ------------------------------
// Four things users get wrong about this feature, each answered on screen rather
// than in a manual:
//
//   1. "Deferring the cost stops tracking the stock." It does not. Physical
//      inventory and financial recognition are separate, and the subtitle says
//      so before either radio is read.
//   2. "Changing this will restate my reports." It will not. Every purchase
//      carries the method it was created with, and the warning says so at the
//      moment of changing rather than after.
//   3. "This covers all my raw materials." It does not. Only three packaging
//      categories and Chemical follow a company setting; Filter, UVLamp,
//      SparePart, Fuel and CleaningSupply never do. The categories each setting
//      governs are listed under it, because that is the commonest question.
//   4. "Expense when consumed is just another option." Not on Water, not yet.
//      See below.
//
// WHY THE DEFERRED OPTION IS LOCKED
// ---------------------------------
// The server refuses EXPENSE_WHEN_CONSUMED until the water phase-2 migrations
// land, because until then a deferred purchase would still be expensed at
// purchase AND expensed again once consumption recognition arrives -- the same
// cost in Profit & Loss twice.
//
// This page reads that state from the API (`deferralAvailable`) rather than
// hardcoding it, so the day phase 2 is applied the option unlocks with no
// frontend deploy. It renders the option DISABLED WITH THE REASON rather than
// hiding it: somebody evaluating this feature needs to know it is coming and
// why it is not here, and an option that silently vanished would just get asked
// about.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from "@/components/ui/table"
import { AlertTriangle, Coins, Info, Loader2, Lock, Package, Save, FlaskConical } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import {
  getWaterFinancialSettings, updateWaterFinancialSettings,
  listWaterItemCostRecognition, setWaterItemCostRecognition,
  type WaterFinancialSettings, type WaterItemCostRecognition,
} from "@/lib/api/water-assets"
import {
  EXPENSE_WHEN_PURCHASED, EXPENSE_WHEN_CONSUMED,
  methodLabel, methodShortLabel, METHOD_HELP,
  PACKAGING_OPTION_HINT, TREATMENT_OPTION_HINT,
  CHANGE_WARNING, DEFERRAL_UNAVAILABLE_NOTE, DEFERRAL_FUTURE_NOTE,
  GROUP_CATEGORIES,
  type CostRecognitionMethod,
} from "@/lib/water/cost-recognition"

const METHODS: CostRecognitionMethod[] = [EXPENSE_WHEN_PURCHASED, EXPENSE_WHEN_CONSUMED]

export default function WaterFinancialSettingsPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const { can, isLoading: permsLoading } = usePermissions()

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState<WaterFinancialSettings | null>(null)
  const [items, setItems] = useState<WaterItemCostRecognition[]>([])
  const [savingItem, setSavingItem] = useState<number | null>(null)

  const [packaging, setPackaging] = useState<CostRecognitionMethod>(EXPENSE_WHEN_PURCHASED)
  const [treatment, setTreatment] = useState<CostRecognitionMethod>(EXPENSE_WHEN_PURCHASED)
  const [effectiveFrom, setEffectiveFrom] = useState("")

  const canView = can("water.financial-settings.view")
  const canEdit = can("water.financial-settings.edit")

  // The server owns this. Defaulting to false while loading means the option is
  // never briefly offered and then withdrawn.
  const deferralAvailable = saved?.deferralAvailable ?? false

  const load = async () => {
    setLoading(true)
    try {
      const [s, i] = await Promise.all([
        getWaterFinancialSettings(),
        // The item resolution is a separate read on the water side: migration
        // 274 does not add the resolved columns to the raw-material item list.
        listWaterItemCostRecognition().catch(() => [] as WaterItemCostRecognition[]),
      ])
      setSaved(s)
      setItems(i)
      setPackaging(s.packagingCostRecognitionMethod as CostRecognitionMethod)
      setTreatment(s.treatmentCostRecognitionMethod as CostRecognitionMethod)
      setEffectiveFrom(s.effectiveFromDate ? s.effectiveFromDate.slice(0, 10) : "")
    } catch (e: any) {
      toast({ title: "Could not load financial settings", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router])

  const dirty = useMemo(() => {
    if (!saved) return false
    const savedFrom = saved.effectiveFromDate ? saved.effectiveFromDate.slice(0, 10) : ""
    return packaging !== saved.packagingCostRecognitionMethod
      || treatment !== saved.treatmentCostRecognitionMethod
      || effectiveFrom !== savedFrom
  }, [saved, packaging, treatment, effectiveFrom])

  const save = async () => {
    setSaving(true)
    try {
      const s = await updateWaterFinancialSettings({
        packagingCostRecognitionMethod: packaging,
        treatmentCostRecognitionMethod: treatment,
        effectiveFromDate: effectiveFrom || null,
      })
      setSaved(s)
      toast({
        title: "Cost recognition saved",
        description: "New purchases from now on use these settings. Existing purchases are unchanged.",
      })
      // The resolved item view moves with the company default, so it has to be
      // re-read rather than left showing the previous answer.
      listWaterItemCostRecognition().then(setItems).catch(() => {})
    } catch (e: any) {
      toast({ title: "Could not save", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  const setOverride = async (itemId: number, value: string | null) => {
    setSavingItem(itemId)
    try {
      const row = await setWaterItemCostRecognition(itemId, value)
      setItems((prev) => prev.map((i) => (i.waterRawMaterialItemId === itemId ? { ...i, ...row } : i)))
    } catch (e: any) {
      toast({ title: "Could not change this item", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSavingItem(null)
    }
  }

  if (!permsLoading && !canView) {
    return (
      <div className="flex h-screen bg-slate-50">
        <DashboardSidebar onLogout={logout} />
        <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
          <DashboardHeader />
          <main className="flex-1 overflow-auto p-6">
            <Card><CardContent className="p-8 text-center text-slate-500">
              You do not have access to financial settings.
            </CardContent></Card>
          </main>
        </div>
      </div>
    )
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <Coins className="h-6 w-6 text-sky-600" /> Cost Recognition
            </h1>
            <p className="text-sm text-slate-500 max-w-3xl mt-1">
              Choose when inventory costs affect Profit &amp; Loss. Physical stock is tracked
              either way — this only decides <em>when</em> a cost counts as a cost.
            </p>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500">
              <Loader2 className="h-4 w-4 animate-spin" /> Loading…
            </div>
          ) : (
            <div className="max-w-3xl space-y-4">
              {/* The reason the option below is locked, said once and up front. */}
              {!deferralAvailable && (
                <Card className="border-slate-300 bg-slate-100">
                  <CardContent className="p-4 flex gap-3 text-sm text-slate-700">
                    <Lock className="h-4 w-4 mt-0.5 shrink-0" />
                    <div>
                      <div className="font-medium text-slate-900 mb-0.5">
                        Expense-when-consumed is not available yet
                      </div>
                      {DEFERRAL_UNAVAILABLE_NOTE}
                    </div>
                  </CardContent>
                </Card>
              )}

              {/* Never present a default as though somebody chose it. */}
              {!saved?.isConfigured && (
                <Card className="border-sky-200 bg-sky-50">
                  <CardContent className="p-4 flex gap-3 text-sm text-sky-900">
                    <Info className="h-4 w-4 mt-0.5 shrink-0" />
                    <div>
                      Nobody has set this up yet, so both are on the standard treatment:
                      costs reach Profit &amp; Loss as you pay for them. Nothing changes until
                      you save something different here.
                    </div>
                  </CardContent>
                </Card>
              )}

              <MethodSection
                icon={<Package className="h-5 w-5 text-sky-600" />}
                title="Packaging Materials"
                blurb="The film, rolls and bags a sachet or bottle physically consumes."
                categories={GROUP_CATEGORIES.Packaging}
                value={packaging}
                onChange={setPackaging}
                hints={PACKAGING_OPTION_HINT}
                disabled={!canEdit}
                deferralAvailable={deferralAvailable}
              />

              <MethodSection
                icon={<FlaskConical className="h-5 w-5 text-emerald-600" />}
                title="Treatment Chemicals"
                blurb="Independent of the packaging setting above — one can defer while the other does not."
                categories={GROUP_CATEGORIES.Treatment}
                value={treatment}
                onChange={setTreatment}
                hints={TREATMENT_OPTION_HINT}
                disabled={!canEdit}
                deferralAvailable={deferralAvailable}
              />

              {/* Say plainly what these settings do NOT reach. */}
              <Card className="border-slate-200">
                <CardContent className="p-4 text-sm text-slate-600">
                  <div className="font-medium text-slate-900 mb-1">
                    Not covered by either setting
                  </div>
                  <div className="flex flex-wrap gap-1.5 mb-2">
                    {GROUP_CATEGORIES.Unconfigured.map((c) => (
                      <Badge key={c} variant="outline" className="text-xs">{c}</Badge>
                    ))}
                  </div>
                  These always reach Profit &amp; Loss when you buy them, whatever the
                  settings above say. Filter and UVLamp are excluded on purpose — they are
                  periodic replacements, and many companies record them as maintenance or on
                  the Asset Register instead. Any single item can still be changed on its own
                  in the table below.
                </CardContent>
              </Card>

              <Card>
                <CardContent className="p-4 space-y-3">
                  <div className="space-y-1.5 max-w-xs">
                    <Label htmlFor="cr-from">Start from (optional)</Label>
                    <Input
                      id="cr-from" type="date" value={effectiveFrom} disabled={!canEdit}
                      min={new Date().toISOString().slice(0, 10)}
                      onChange={(e) => setEffectiveFrom(e.target.value)}
                    />
                    <p className="text-xs text-slate-500">
                      Leave blank to apply immediately. A future date holds the change until
                      then. A past date is refused — purchases already recorded keep the
                      treatment they were created with, so backdating could not change them
                      anyway.
                    </p>
                  </div>

                  {saved?.isConfigured && (
                    <div className="text-xs text-slate-500 border-t pt-3">
                      Last changed
                      {saved.updatedAt ? ` on ${new Date(saved.updatedAt).toLocaleString()}` : ""}
                      {saved.updatedBy ? ` by ${saved.updatedBy}` : ""}.
                    </div>
                  )}
                </CardContent>
              </Card>

              {/* The warning appears only in front of a real change. */}
              {dirty && (
                <Card className="border-amber-200 bg-amber-50">
                  <CardContent className="p-4 flex gap-3 text-sm text-amber-900">
                    <AlertTriangle className="h-4 w-4 mt-0.5 shrink-0" />
                    <div>{CHANGE_WARNING}</div>
                  </CardContent>
                </Card>
              )}

              <div className="flex items-center gap-3">
                <Button onClick={save} disabled={!canEdit || !dirty || saving}>
                  {saving
                    ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>
                    : <><Save className="w-4 h-4 mr-2" />Save changes</>}
                </Button>
                {dirty && (
                  <Button type="button" variant="ghost" onClick={load} disabled={saving}>
                    Discard
                  </Button>
                )}
                {!canEdit && (
                  <span className="text-xs text-slate-500">
                    You can see this setting but not change it.
                  </span>
                )}
              </div>

              <ItemOverrideTable
                items={items}
                disabled={!canEdit}
                savingItem={savingItem}
                deferralAvailable={deferralAvailable}
                onSet={setOverride}
              />
            </div>
          )}
        </main>
      </div>
    </div>
  )
}

function MethodSection({
  icon, title, blurb, categories, value, onChange, hints, disabled, deferralAvailable,
}: {
  icon: React.ReactNode
  title: string
  blurb: string
  categories: string[]
  value: CostRecognitionMethod
  onChange: (m: CostRecognitionMethod) => void
  hints: Record<CostRecognitionMethod, string>
  disabled: boolean
  deferralAvailable: boolean
}) {
  return (
    <Card>
      <CardContent className="p-4">
        <div className="flex items-center gap-2 mb-1">
          {icon}
          <h2 className="font-semibold text-slate-900">{title}</h2>
        </div>
        <p className="text-sm text-slate-500 mb-2">{blurb}</p>
        {/* Which categories this actually governs. The commonest question. */}
        <div className="flex flex-wrap gap-1.5 mb-3">
          {categories.map((c) => (
            <Badge key={c} variant="secondary" className="text-xs font-normal">{c}</Badge>
          ))}
        </div>

        <div className="space-y-2">
          {METHODS.map((m) => {
            const selected = value === m
            const locked = m === EXPENSE_WHEN_CONSUMED && !deferralAvailable
            const isDisabled = disabled || locked
            return (
              <button
                key={m}
                type="button"
                disabled={isDisabled}
                aria-disabled={isDisabled}
                onClick={() => onChange(m)}
                className={`w-full text-left rounded-lg border p-3 transition ${
                  selected ? "border-sky-500 bg-sky-50" : "border-slate-200 hover:border-slate-300"
                } ${isDisabled ? "opacity-60 cursor-not-allowed" : ""}`}
              >
                <div className="flex items-start gap-3">
                  <span
                    className={`mt-0.5 h-4 w-4 shrink-0 rounded-full border-2 ${
                      selected ? "border-sky-600 bg-sky-600" : "border-slate-300"
                    }`}
                  />
                  <div className="min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="font-medium text-slate-900">{methodLabel(m)}</span>
                      {m === EXPENSE_WHEN_PURCHASED && (
                        <Badge variant="secondary" className="text-xs">Current standard</Badge>
                      )}
                      {locked && (
                        <Badge variant="outline" className="text-xs gap-1">
                          <Lock className="h-3 w-3" /> Not available yet
                        </Badge>
                      )}
                    </div>
                    <p className="text-xs text-slate-600 mt-0.5">{hints[m]}</p>
                    <p className="text-xs text-slate-500 mt-1">
                      {locked ? DEFERRAL_FUTURE_NOTE : METHOD_HELP[m]}
                    </p>
                  </div>
                </div>
              </button>
            )
          })}
        </div>
      </CardContent>
    </Card>
  )
}

/**
 * The per-item exceptions.
 *
 * A separate table rather than a column on the Raw Materials page, because on
 * the water side the resolution is its own read -- migration 274 does not add it
 * to the item list. Rows that are simply following the company default are shown
 * too, so the table answers "how is this item treated?" and not only "which
 * items are unusual?".
 */
function ItemOverrideTable({
  items, disabled, savingItem, deferralAvailable, onSet,
}: {
  items: WaterItemCostRecognition[]
  disabled: boolean
  savingItem: number | null
  deferralAvailable: boolean
  onSet: (itemId: number, value: string | null) => void
}) {
  const [showAll, setShowAll] = useState(false)
  const active = items.filter((i) => i.isActive)
  const overridden = active.filter((i) => i.costRecognitionOverride)
  const rows = showAll ? active : overridden

  if (active.length === 0) return null

  return (
    <Card>
      <CardContent className="p-4">
        <div className="flex items-start justify-between gap-3 mb-1">
          <div>
            <h2 className="font-semibold text-slate-900">Per-item exceptions</h2>
            <p className="text-sm text-slate-500">
              An item can be treated differently from its category. This is the only way to
              defer something in an uncovered category — or to keep one item on purchase
              while the rest of its category defers.
            </p>
          </div>
          <Button type="button" variant="ghost" size="sm" onClick={() => setShowAll((v) => !v)}>
            {showAll ? "Show exceptions only" : `Show all ${active.length}`}
          </Button>
        </div>

        {rows.length === 0 ? (
          <p className="text-sm text-slate-500 py-4">
            No item overrides. Every item follows its category.
          </p>
        ) : (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Item</TableHead>
                  <TableHead>Category</TableHead>
                  <TableHead>Treated as</TableHead>
                  <TableHead className="text-right">Override</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((i) => {
                  const isOverride = i.costRecognitionSource === "ItemOverride"
                  const busy = savingItem === i.waterRawMaterialItemId
                  return (
                    <TableRow key={i.waterRawMaterialItemId}>
                      <TableCell className="font-medium">{i.itemName}</TableCell>
                      <TableCell>
                        <Badge variant="outline" className="text-xs">{i.category}</Badge>
                        <div className="text-xs text-slate-500 mt-0.5">
                          {i.costRecognitionCategoryGroup === "Unconfigured"
                            ? "No company setting"
                            : `Follows ${i.costRecognitionCategoryGroup}`}
                        </div>
                      </TableCell>
                      <TableCell>
                        <Badge
                          variant={isOverride ? "default" : "secondary"}
                          className="text-xs"
                        >
                          {methodShortLabel(i.effectiveCostRecognitionMethod)}
                        </Badge>
                        <div className="text-xs text-slate-500 mt-0.5">
                          {isOverride ? "Set on this item" : "Company default"}
                        </div>
                      </TableCell>
                      <TableCell className="text-right">
                        {busy ? (
                          <Loader2 className="h-4 w-4 animate-spin inline" />
                        ) : isOverride ? (
                          <Button
                            type="button" variant="ghost" size="sm" disabled={disabled}
                            onClick={() => onSet(i.waterRawMaterialItemId, null)}
                          >
                            Clear
                          </Button>
                        ) : (
                          <div className="inline-flex gap-1">
                            <Button
                              type="button" variant="outline" size="sm" disabled={disabled}
                              onClick={() => onSet(i.waterRawMaterialItemId, EXPENSE_WHEN_PURCHASED)}
                            >
                              On purchase
                            </Button>
                            {/* Locked for the same reason the settings are. */}
                            <Button
                              type="button" variant="outline" size="sm"
                              disabled={disabled || !deferralAvailable}
                              title={deferralAvailable ? undefined : DEFERRAL_UNAVAILABLE_NOTE}
                              onClick={() => onSet(i.waterRawMaterialItemId, EXPENSE_WHEN_CONSUMED)}
                            >
                              On use
                            </Button>
                          </div>
                        )}
                      </TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
