"use client"

// Days of Supply (migration 337): every raw material, how much is in stock,
// how much is actually being used per day, how many days that lasts, and an
// ESTIMATED stock-out date on the company's calendar. Restock opens the normal
// purchase dialog with the item chosen; nothing is bought automatically.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { Loader2, Package, Settings2 } from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { cn } from "@/lib/utils"
import { useToast } from "@/hooks/use-toast"
import { useLogout } from "@/hooks/use-logout"
import { useAuthStore } from "@/lib/store/auth-store"
import {
  getStockSupply,
  getStockSupplySettings,
  saveStockSupplySettings,
  type StockSupplySettings,
} from "@/lib/api/stock-supply"
import {
  daysText,
  explainAverage,
  isActionable,
  purchaseUnitEquivalent,
  qtyWithUnit,
  restockHref,
  sortBySeverity,
  stockoutText,
  supplyStatusStyle,
  type StockSupplyRow,
} from "@/lib/inventory/days-of-supply"
import { formatLongDate } from "@/lib/closing/daily-closing"

const LOOKBACKS = [7, 14, 30] as const

export default function DaysOfSupplyPage() {
  const router = useRouter()
  const logout = useLogout()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)

  const [lookback, setLookback] = useState<number | null>(null) // null = the farm's saved default
  const [rows, setRows] = useState<StockSupplyRow[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [showAll, setShowAll] = useState(false)
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [settings, setSettings] = useState<StockSupplySettings | null>(null)
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") router.replace("/dashboard")
  }, [activeFarmType, router])

  const load = useCallback(async () => {
    setError(null)
    try { setRows(sortBySeverity(await getStockSupply(lookback ?? undefined))) }
    catch (e) { setError(e instanceof Error ? e.message : "Could not load stock levels.") }
  }, [lookback])
  useEffect(() => { if (activeFarmId) void load() }, [activeFarmId, load])

  const openSettings = async () => {
    try { setSettings(await getStockSupplySettings()); setSettingsOpen(true) }
    catch (e) { toast({ title: "Could not load settings", description: e instanceof Error ? e.message : "", variant: "destructive" }) }
  }
  const saveSettings = async () => {
    if (!settings) return
    setSaving(true)
    try {
      await saveStockSupplySettings(settings)
      toast({ title: "Stock warning levels saved" })
      setSettingsOpen(false)
      setLookback(null)
      await load()
    } catch (e) {
      toast({ title: "Not saved", description: e instanceof Error ? e.message : "", variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  const first = rows?.[0]
  const shown = (rows ?? []).filter((r) => showAll || r.status !== "NoRecentUsage")
  const hiddenIdle = (rows ?? []).length - shown.length
  const anyExpected = (rows ?? []).some((r) => r.expectedDailyUsage != null)
  const urgentCount = (rows ?? []).filter((r) => isActionable(r.status)).length

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex min-w-0 flex-1 flex-col">
        <DashboardHeader />
        <main className="min-w-0 flex-1 overflow-x-hidden p-4 pb-16 sm:p-6 lg:pb-6">
          <div className="space-y-4">
            <div className="flex flex-wrap items-end justify-between gap-3">
              <div className="flex items-start gap-3">
                <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-sky-100">
                  <Package className="h-5 w-5 text-sky-700" />
                </div>
                <div>
                  <h1 className="text-2xl font-bold text-slate-900">Days of Supply</h1>
                  <p className="text-sm text-slate-600">How long each item lasts at the rate it is actually being used.</p>
                </div>
              </div>
              <div className="flex flex-wrap items-end gap-2">
                <div className="space-y-1">
                  <Label className="text-xs text-slate-500">Average over</Label>
                  <div className="inline-flex rounded-md border border-slate-200 bg-slate-50 p-0.5 text-sm">
                    {LOOKBACKS.map((d) => (
                      <button key={d} type="button" onClick={() => setLookback(d)}
                        className={cn("rounded px-3 py-1", (lookback ?? first?.lookbackDays) === d
                          ? "bg-white font-medium text-slate-900 shadow-sm" : "text-slate-600")}>
                        {d} days
                      </button>
                    ))}
                  </div>
                </div>
                <Button variant="outline" size="sm" className="gap-1.5" onClick={() => void openSettings()}>
                  <Settings2 className="h-4 w-4" /> Warning levels
                </Button>
              </div>
            </div>

            {first && (
              <p className="text-xs text-slate-500">
                Usage from {formatLongDate(first.windowFrom)} to {formatLongDate(first.windowTo)} (complete days; today is not
                counted yet). Critical under {first.criticalDays} days, warning under {first.warningDays} days.
                Feed and medication given to flocks and ingredients used in feed production count as usage;
                purchases, reversals and stock corrections do not. Stock-out dates are estimates.
              </p>
            )}

            {error && <Card className="border-rose-200 bg-rose-50"><CardContent className="p-4 text-sm text-rose-800">{error}</CardContent></Card>}
            {!rows && !error && <p className="flex items-center gap-2 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</p>}

            {rows && (
              <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
                <CardContent className="p-0">
                  <div className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-100 px-4 py-2 text-sm">
                    <span className="text-slate-600">{urgentCount} need{urgentCount === 1 ? "s" : ""} attention · {rows.length} items</span>
                    {hiddenIdle > 0 && (
                      <button type="button" className="text-sky-700 underline" onClick={() => setShowAll((v) => !v)}>
                        {showAll ? "Hide items with no recent usage" : `Show ${hiddenIdle} item${hiddenIdle === 1 ? "" : "s"} with no recent usage`}
                      </button>
                    )}
                  </div>
                  <div className="overflow-x-auto">
                    <table className="w-full min-w-[56rem] text-sm">
                      <thead className="bg-slate-50 text-left text-xs uppercase tracking-wider text-slate-500">
                        <tr>
                          <th className="px-3 py-2 font-medium">Item</th>
                          <th className="px-3 py-2 text-right font-medium">Current stock</th>
                          <th className="px-3 py-2 text-right font-medium">Avg daily use</th>
                          {anyExpected && <th className="px-3 py-2 text-right font-medium">Expected (feed rate)</th>}
                          <th className="px-3 py-2 font-medium">Days remaining</th>
                          <th className="px-3 py-2 font-medium">Status</th>
                          <th className="px-3 py-2 text-right font-medium">Action</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-100">
                        {shown.length === 0 && (
                          <tr><td colSpan={7} className="px-3 py-4 text-slate-500">Nothing has been used recently.</td></tr>
                        )}
                        {shown.map((r) => {
                          const st = supplyStatusStyle(r.status)
                          const out = stockoutText(r)
                          const bags = purchaseUnitEquivalent(r.currentQuantity, r)
                          return (
                            <tr key={r.poultryRawMaterialItemId} className="align-top">
                              <td className="px-3 py-2">
                                <div className="font-medium text-slate-900">{r.itemName}</div>
                                <div className="text-xs text-slate-500">{r.category}</div>
                                <div className="mt-0.5 max-w-md text-xs text-slate-500">{explainAverage(r)}</div>
                              </td>
                              <td className="px-3 py-2 text-right tabular-nums">
                                <span className={cn(r.currentQuantity < 0 && "text-rose-700")}>{qtyWithUnit(r.currentQuantity, r.unitOfMeasure)}</span>
                                {bags && <div className="text-xs text-slate-500">{bags}</div>}
                                {r.belowReorder && <div className="text-xs text-amber-700">At or below reorder level</div>}
                              </td>
                              <td className="px-3 py-2 text-right tabular-nums">{qtyWithUnit(r.avgDailyUsage, r.unitOfMeasure, 2)}</td>
                              {anyExpected && (
                                <td className="px-3 py-2 text-right tabular-nums">{qtyWithUnit(r.expectedDailyUsage, r.unitOfMeasure, 2)}</td>
                              )}
                              <td className="px-3 py-2">
                                <div className="font-medium text-slate-900">{daysText(r)}</div>
                                {out && <div className="text-xs text-slate-500">{out}</div>}
                              </td>
                              <td className="px-3 py-2">
                                <span className={cn("rounded-full border px-2 py-0.5 text-xs font-medium", st.badge)}>{st.label}</span>
                              </td>
                              <td className="px-3 py-2 text-right">
                                <Button asChild size="sm" variant={isActionable(r.status) ? "default" : "outline"} className="h-7 px-2.5 text-xs">
                                  <Link href={restockHref(r.poultryRawMaterialItemId)}>Restock</Link>
                                </Button>
                              </td>
                            </tr>
                          )
                        })}
                      </tbody>
                    </table>
                  </div>
                </CardContent>
              </Card>
            )}
          </div>
        </main>
      </div>

      <Dialog open={settingsOpen} onOpenChange={setSettingsOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Stock warning levels</DialogTitle>
            <DialogDescription>When an item counts as critical or needs a warning, and how many days of usage to average.</DialogDescription>
          </DialogHeader>
          {settings && (
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1">
                <Label className="text-xs">Critical under (days)</Label>
                <Input type="number" min={0} step="0.5" value={settings.criticalDays}
                  onChange={(e) => setSettings({ ...settings, criticalDays: Number(e.target.value) || 0 })} />
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Warning under (days)</Label>
                <Input type="number" min={0} step="0.5" value={settings.warningDays}
                  onChange={(e) => setSettings({ ...settings, warningDays: Number(e.target.value) || 0 })} />
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Default average over (days)</Label>
                <Input type="number" min={1} max={90} value={settings.lookbackDays}
                  onChange={(e) => setSettings({ ...settings, lookbackDays: Number(e.target.value) || 7 })} />
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Minimum history (days)</Label>
                <Input type="number" min={1} max={90} value={settings.minHistoryDays}
                  onChange={(e) => setSettings({ ...settings, minHistoryDays: Number(e.target.value) || 3 })} />
              </div>
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => setSettingsOpen(false)} disabled={saving}>Cancel</Button>
            <Button onClick={() => void saveSettings()} disabled={saving}>
              {saving && <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />} Save
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
