"use client"

// Poultry Financial Settings -> Cost Recognition.
//
// Two choices: when feed costs reach Profit & Loss, and when medication costs
// do. They are independent, and either can be left exactly as it is today.
//
// WHAT THIS PAGE IS CAREFUL ABOUT
// ------------------------------
// Three things users get wrong about this feature, each answered on screen
// rather than in a manual:
//
//   1. "Deferring the cost stops tracking the stock." It does not. Physical
//      inventory and financial recognition are separate, and the subtitle says
//      so before either radio is read.
//   2. "Changing this will restate my reports." It will not. Every purchase
//      carries the method it was created with, and the warning says so at the
//      moment of changing rather than after.
//   3. "Expense when consumed means I will see the cost as I use stock."
//      Not yet -- Phase 2 builds that. Until then a deferred purchase holds its
//      cost and shows in Profit & Loss not at all. Choosing it without knowing
//      that would be a nasty surprise at month end, so the page says it in the
//      one place it cannot be missed: attached to the option itself.
//
// The save button stays disabled until something actually differs, so the
// warning only ever appears in front of a real change.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { AlertTriangle, Coins, Info, Loader2, Save, Wheat, Pill } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import {
  getPoultryFinancialSettings, updatePoultryFinancialSettings,
  type PoultryFinancialSettings,
} from "@/lib/api/poultry-inventory"
import {
  EXPENSE_WHEN_PURCHASED, EXPENSE_WHEN_CONSUMED,
  methodLabel, METHOD_HELP, FEED_OPTION_HINT, MEDICATION_OPTION_HINT,
  CHANGE_WARNING, DEFERRED_ACTIVE_NOTE,
  type CostRecognitionMethod,
} from "@/lib/poultry/cost-recognition"

const METHODS: CostRecognitionMethod[] = [EXPENSE_WHEN_PURCHASED, EXPENSE_WHEN_CONSUMED]

export default function PoultryFinancialSettingsPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const { can, isLoading: permsLoading } = usePermissions()

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState<PoultryFinancialSettings | null>(null)

  const [feed, setFeed] = useState<CostRecognitionMethod>(EXPENSE_WHEN_PURCHASED)
  const [medication, setMedication] = useState<CostRecognitionMethod>(EXPENSE_WHEN_PURCHASED)
  const [effectiveFrom, setEffectiveFrom] = useState("")

  const canView = can("poultry.financial-settings.view")
  const canEdit = can("poultry.financial-settings.edit")

  const load = async () => {
    setLoading(true)
    try {
      const s = await getPoultryFinancialSettings()
      setSaved(s)
      setFeed(s.feedCostRecognitionMethod)
      setMedication(s.medicationCostRecognitionMethod)
      setEffectiveFrom(s.effectiveFromDate ? s.effectiveFromDate.slice(0, 10) : "")
    } catch (e: any) {
      toast({ title: "Could not load financial settings", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router])

  const dirty = useMemo(() => {
    if (!saved) return false
    const savedFrom = saved.effectiveFromDate ? saved.effectiveFromDate.slice(0, 10) : ""
    return feed !== saved.feedCostRecognitionMethod
      || medication !== saved.medicationCostRecognitionMethod
      || effectiveFrom !== savedFrom
  }, [saved, feed, medication, effectiveFrom])

  // Only a change TOWARDS deferral needs the "not built yet" note. Turning it
  // back off is always safe and does not need a caveat.
  const turningOnDeferral =
    (feed === EXPENSE_WHEN_CONSUMED && saved?.feedCostRecognitionMethod !== EXPENSE_WHEN_CONSUMED)
    || (medication === EXPENSE_WHEN_CONSUMED && saved?.medicationCostRecognitionMethod !== EXPENSE_WHEN_CONSUMED)

  const save = async () => {
    setSaving(true)
    try {
      const s = await updatePoultryFinancialSettings({
        feedCostRecognitionMethod: feed,
        medicationCostRecognitionMethod: medication,
        effectiveFromDate: effectiveFrom || null,
      })
      setSaved(s)
      toast({
        title: "Cost recognition saved",
        description: "New purchases from now on use these settings. Existing purchases are unchanged.",
      })
    } catch (e: any) {
      toast({ title: "Could not save", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
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
              <Coins className="h-6 w-6 text-emerald-600" /> Cost Recognition
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
                icon={<Wheat className="h-5 w-5 text-amber-600" />}
                title="Feed & Feed Raw Materials"
                blurb="Feed ingredients, finished feed and grain."
                value={feed}
                onChange={setFeed}
                hints={FEED_OPTION_HINT}
                disabled={!canEdit}
              />

              <MethodSection
                icon={<Pill className="h-5 w-5 text-rose-600" />}
                title="Medication"
                blurb="Drugs and vaccines. Independent of the feed setting above — one can defer while the other does not."
                value={medication}
                onChange={setMedication}
                hints={MEDICATION_OPTION_HINT}
                disabled={!canEdit}
              />

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

              {/* The warnings appear only in front of a real change. */}
              {dirty && (
                <Card className="border-amber-200 bg-amber-50">
                  <CardContent className="p-4 space-y-2 text-sm text-amber-900">
                    <div className="flex gap-3">
                      <AlertTriangle className="h-4 w-4 mt-0.5 shrink-0" />
                      <div>{CHANGE_WARNING}</div>
                    </div>
                    {turningOnDeferral && (
                      <div className="flex gap-3 border-t border-amber-200 pt-2">
                        <AlertTriangle className="h-4 w-4 mt-0.5 shrink-0" />
                        <div>{DEFERRED_ACTIVE_NOTE}</div>
                      </div>
                    )}
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
            </div>
          )}
        </main>
      </div>
    </div>
  )
}

function MethodSection({
  icon, title, blurb, value, onChange, hints, disabled,
}: {
  icon: React.ReactNode
  title: string
  blurb: string
  value: CostRecognitionMethod
  onChange: (m: CostRecognitionMethod) => void
  hints: Record<CostRecognitionMethod, string>
  disabled: boolean
}) {
  return (
    <Card>
      <CardContent className="p-4">
        <div className="flex items-center gap-2 mb-1">
          {icon}
          <h2 className="font-semibold text-slate-900">{title}</h2>
        </div>
        <p className="text-sm text-slate-500 mb-3">{blurb}</p>

        <div className="space-y-2">
          {METHODS.map((m) => {
            const selected = value === m
            return (
              <button
                key={m}
                type="button"
                disabled={disabled}
                onClick={() => onChange(m)}
                className={`w-full text-left rounded-lg border p-3 transition ${
                  selected ? "border-emerald-500 bg-emerald-50" : "border-slate-200 hover:border-slate-300"
                } ${disabled ? "opacity-60 cursor-not-allowed" : ""}`}
              >
                <div className="flex items-start gap-3">
                  <span
                    className={`mt-0.5 h-4 w-4 shrink-0 rounded-full border-2 ${
                      selected ? "border-emerald-600 bg-emerald-600" : "border-slate-300"
                    }`}
                  />
                  <div className="min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="font-medium text-slate-900">{methodLabel(m)}</span>
                      {m === EXPENSE_WHEN_PURCHASED && (
                        <Badge variant="secondary" className="text-xs">Current standard</Badge>
                      )}
                    </div>
                    <p className="text-xs text-slate-600 mt-0.5">{hints[m]}</p>
                    <p className="text-xs text-slate-500 mt-1">{METHOD_HELP[m]}</p>
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
