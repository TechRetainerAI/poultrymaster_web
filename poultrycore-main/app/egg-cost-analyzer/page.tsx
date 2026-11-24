"use client"

// Egg Cost & Profit Analyzer (migration 481) -- Tools > Egg Cost & Profit Analyzer.
//
// A new analytical workspace. It does not replace or change Cost Per Egg, Feed
// Cost Per Egg or Profit & Loss, and it never writes to business records: the
// server returns facts (sppoultryeggcost_facts) and lib/egg-cost/engine works
// out every figure, so each one can be traced to its rows.

import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import {
  AlertTriangle, Calculator, ClipboardCheck, Download, FileText, FlaskConical, FolderOpen, Loader2, Printer, Save, Scale, Settings2,
} from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Tabs, TabsContent, TabsList, TabsTrigger, PROMINENT_TABS_LIST, PROMINENT_TABS_TRIGGER } from "@/components/ui/tabs"
import { useToast } from "@/hooks/use-toast"
import { useLogout } from "@/hooks/use-logout"
import { usePermissions } from "@/hooks/use-permissions"
import { useBusinessDate } from "@/hooks/use-business-date"
import { useBatchFlockSelect } from "@/hooks/use-batch-flock-select"
import { useAuthStore } from "@/lib/store/auth-store"
import { getSelectedCurrency } from "@/lib/utils/currency"
import { getEggCostFacts, getSnapshot, saveSnapshot, type SnapshotSummary } from "@/lib/api/egg-cost"
import {
  analyze, CALC_VERSION, NEUTRAL_SCENARIO, runScenario, sources,
  type EggCostFacts, type ScenarioInputs, type Scope, type SourceRow,
} from "@/lib/egg-cost/engine"
import { CompletenessBadge, Kpi, Section, WarningList, num, pct, useMoney } from "@/components/egg-cost/bits"
import { CostBreakdown, DrilldownDialog } from "@/components/egg-cost/cost-breakdown"
import { FlockComparison } from "@/components/egg-cost/flock-comparison"
import { PriceAnalyzer, ReverseCalculators } from "@/components/egg-cost/price-analyzer"
import { WhatIfPanel } from "@/components/egg-cost/what-if"
import { Trends } from "@/components/egg-cost/trends"
import { PreLayingPanel } from "@/components/egg-cost/pre-laying"
import { CostSettingsDialog } from "@/components/egg-cost/settings-dialog"
import { OpenSnapshotDialog, SaveSnapshotDialog } from "@/components/egg-cost/snapshots"
import { exportCsv, exportPdf } from "@/components/egg-cost/export"

type Period = "day" | "week" | "month" | "year" | "custom" | "lifetime"
const DAY = 86_400_000
const shift = (iso: string, days: number) => new Date(Date.parse(`${iso}T00:00:00Z`) + days * DAY).toISOString().slice(0, 10)

export default function EggCostAnalyzerPage() {
  const router = useRouter()
  const logout = useLogout()
  const { toast } = useToast()
  const { isAdmin } = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const { businessDate: today } = useBusinessDate()
  const { money } = useMoney()
  const { batches, allFlocks } = useBatchFlockSelect()

  useEffect(() => { if (activeFarmType && activeFarmType !== "Poultry") router.replace("/dashboard") }, [activeFarmType, router])

  const [mode, setMode] = useState<"recorded" | "scenario">("recorded")
  const [view, setView] = useState<"full" | "direct">("full")
  const [period, setPeriod] = useState<Period>("month")
  const [customStart, setCustomStart] = useState("")
  const [customEnd, setCustomEnd] = useState("")
  const [level, setLevel] = useState<"farm" | "batch" | "flock">("farm")
  const [batchId, setBatchId] = useState<string>("")
  const [flockId, setFlockId] = useState<string>("")
  const [scenario, setScenario] = useState<ScenarioInputs>(NEUTRAL_SCENARIO)
  const [facts, setFacts] = useState<EggCostFacts | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [drill, setDrill] = useState<{ key: string; label: string } | null>(null)
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [saveOpen, setSaveOpen] = useState(false)
  const [openOpen, setOpenOpen] = useState(false)
  const [opened, setOpened] = useState<{ name: string; fingerprint: string | null; headline: Record<string, unknown> | null; createdAt: string } | null>(null)

  // ---- period -> dates (company business date)
  const [startDate, endDate] = useMemo((): [string, string] => {
    if (!today) return ["", ""]
    switch (period) {
      case "day": return [today, today]
      case "week": return [shift(today, -6), today]
      case "month": return [`${today.slice(0, 8)}01`, today]
      case "year": return [`${today.slice(0, 4)}-01-01`, today]
      case "custom": return [customStart || shift(today, -29), customEnd || today]
      case "lifetime": {
        const pool = level === "flock" ? allFlocks.filter((f) => String(f.flockId) === flockId)
          : level === "batch" ? allFlocks.filter((f) => String(f.batchId) === batchId) : allFlocks
        const starts = pool.map((f) => (f.startDate ?? "").slice(0, 10)).filter(Boolean).sort()
        const s = starts[0] ?? shift(today, -364)
        return [s < shift(today, -3650) ? shift(today, -3650) : s, today]
      }
    }
  }, [period, today, customStart, customEnd, level, flockId, batchId, allFlocks])

  const scope: Scope = useMemo(() => (
    level === "batch" && batchId ? { level: "batch", batchId: Number(batchId) }
      : level === "flock" && flockId ? { level: "flock", flockIds: [Number(flockId)] }
        : { level: "farm" }
  ), [level, batchId, flockId])

  const load = useCallback(async () => {
    if (!startDate || !endDate || !activeFarmId) return
    if (endDate < startDate) { setError("The period must end on or after it starts."); return }
    setLoading(true); setError(null)
    const r = await getEggCostFacts(startDate, endDate)
    setLoading(false)
    if (!r.success || !r.data) { setError(r.message ?? "Could not load the analysis."); setFacts(null); return }
    setFacts(r.data)
  }, [startDate, endDate, activeFarmId])
  useEffect(() => { void load() }, [load])

  const a = useMemo(() => (facts ? analyze(facts, scope) : null), [facts, scope])
  const scen = useMemo(() => (a && mode === "scenario" ? runScenario(a, scenario) : null), [a, scenario, mode])
  const drillRows: SourceRow[] = useMemo(() => (facts && a && drill ? sources(facts, a, drill.key) : []), [facts, a, drill])

  const scopeLabel = level === "farm" ? "Entire farm"
    : level === "batch" ? `Batch ${batches.find((b) => String(b.batchId) === batchId)?.batchCode ?? batchId}`
      : `Flock ${allFlocks.find((f) => String(f.flockId) === flockId)?.name ?? flockId}`
  const layingFlocks = useMemo(() => allFlocks.filter((f) => (f as { flockType?: string }).flockType !== "Broiler"), [allFlocks])

  // ---- snapshots
  async function doSave(name: string) {
    if (!a || !facts) return false
    const r = await saveSnapshot({
      name, mode: mode === "scenario" ? "Scenario" : "Recorded",
      params: { startDate, endDate, period, scope, costView: view, scenario: mode === "scenario" ? { ...scenario } : null },
      result: {
        headline: {
          fullPerCrate: a.fullPerCrate, directPerCrate: a.directPerCrate, feedPerCrate: a.feedPerCrate,
          saleable: a.saleable, saleableCrates: a.saleableCrates, pricePerCrate: a.price.pricePerCrate,
          marginPerCrate: a.marginPerCrate, completeness: a.completeness,
          ...(scen ? { scenarioFullPerCrate: scen.fullPerCrate, scenarioMarginPerCrate: scen.marginPerCrate } : {}),
        },
        components: a.components, warnings: a.warnings, settings: a.settings, excluded: a.excluded,
        ...(scen ? { scenario: scen } : {}),
      },
      calcVersion: CALC_VERSION, settingsVersion: a.settings.version, sourceFingerprint: facts.fingerprint,
    })
    if (!r.success) { toast({ title: "Not saved", description: r.message, variant: "destructive" }); return false }
    toast({ title: "Analysis saved", description: "Nothing was posted -- this is a saved calculation only." })
    return true
  }

  async function doOpen(s: SnapshotSummary) {
    const r = await getSnapshot(s.snapshotId)
    if (!r.success || !r.data) { toast({ title: "Could not open", description: r.message, variant: "destructive" }); return }
    const p = r.data.params
    setPeriod("custom"); setCustomStart(p.startDate); setCustomEnd(p.endDate)
    setLevel(p.scope?.level ?? "farm")
    setBatchId(p.scope?.batchId != null ? String(p.scope.batchId) : "")
    setFlockId(p.scope?.flockIds?.[0] != null ? String(p.scope.flockIds[0]) : "")
    setView(p.costView ?? "full")
    if (r.data.mode === "Scenario" && p.scenario) { setScenario({ ...NEUTRAL_SCENARIO, ...(p.scenario as Partial<ScenarioInputs>) }); setMode("scenario") } else setMode("recorded")
    setOpened({ name: r.data.name, fingerprint: r.data.sourceFingerprint, headline: (r.data.result?.headline as Record<string, unknown>) ?? null, createdAt: r.data.createdAt })
  }

  const exportCtx = a ? { a, scenario: scen, mode: (mode === "scenario" ? "Scenario" : "Recorded") as "Recorded" | "Scenario", scopeLabel, money, currencyLabel: getSelectedCurrency() } : null
  const changedSinceSave = opened && facts && opened.fingerprint && facts.fingerprint !== opened.fingerprint

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex min-w-0 flex-1 flex-col">
        <DashboardHeader />
        <main className="min-w-0 flex-1 overflow-y-auto overflow-x-hidden p-4 pb-16 sm:p-6 lg:pb-6">
          <div className="mx-auto max-w-7xl space-y-4">
            {/* ------------------------------------------------ header */}
            <div className="flex flex-wrap items-end justify-between gap-3">
              <div className="flex items-start gap-3">
                <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-sky-100"><Calculator className="h-5 w-5 text-sky-700" /></div>
                <div>
                  <h1 className="text-2xl font-bold text-slate-900">Egg Cost &amp; Profit Analyzer</h1>
                  <p className="text-sm text-slate-500">Understand the true cost of producing eggs and discover opportunities to improve profitability.</p>
                </div>
              </div>
              <div className="flex flex-wrap gap-2 print:hidden">
                <Button variant="outline" size="sm" onClick={() => setOpenOpen(true)}><FolderOpen className="mr-1 h-4 w-4" />Saved</Button>
                <Button variant="outline" size="sm" disabled={!a} onClick={() => setSaveOpen(true)}><Save className="mr-1 h-4 w-4" />Save</Button>
                <Button variant="outline" size="sm" onClick={() => setSettingsOpen(true)}><Settings2 className="mr-1 h-4 w-4" />Cost settings</Button>
                <Button variant="outline" size="sm" disabled={!exportCtx} onClick={() => exportCtx && exportCsv(exportCtx)}><Download className="mr-1 h-4 w-4" />CSV</Button>
                <Button variant="outline" size="sm" disabled={!exportCtx} onClick={() => exportCtx && void exportPdf(exportCtx)}><FileText className="mr-1 h-4 w-4" />PDF</Button>
                <Button variant="outline" size="sm" disabled={!a} onClick={() => window.print()}><Printer className="mr-1 h-4 w-4" />Print</Button>
              </div>
            </div>

            {/* ------------------------------------------------ controls */}
            <Card className="border-slate-200 print:hidden">
              <CardContent className="grid gap-3 p-4 sm:grid-cols-2 lg:grid-cols-6">
                <div className="space-y-1">
                  <Label className="text-xs">Period</Label>
                  <Select value={period} onValueChange={(v) => setPeriod(v as Period)}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="day">Today</SelectItem>
                      <SelectItem value="week">Last 7 days</SelectItem>
                      <SelectItem value="month">This month</SelectItem>
                      <SelectItem value="year">This year</SelectItem>
                      <SelectItem value="lifetime">Flock lifetime</SelectItem>
                      <SelectItem value="custom">Custom range</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                {period === "custom" ? (
                  <div className="grid grid-cols-2 gap-2 lg:col-span-2">
                    <div className="space-y-1"><Label htmlFor="ec-from" className="text-xs">From</Label><Input id="ec-from" type="date" value={customStart || startDate} onChange={(e) => setCustomStart(e.target.value)} /></div>
                    <div className="space-y-1"><Label htmlFor="ec-to" className="text-xs">To</Label><Input id="ec-to" type="date" value={customEnd || endDate} onChange={(e) => setCustomEnd(e.target.value)} /></div>
                  </div>
                ) : (
                  <div className="space-y-1 lg:col-span-2">
                    <Label className="text-xs">Dates</Label>
                    <p className="flex h-9 items-center text-sm text-slate-700">{startDate} → {endDate}</p>
                  </div>
                )}
                <div className="space-y-1">
                  <Label className="text-xs">Analyse</Label>
                  <Select value={level} onValueChange={(v) => setLevel(v as typeof level)}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="farm">Entire farm</SelectItem>
                      <SelectItem value="batch">A batch</SelectItem>
                      <SelectItem value="flock">A flock</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                {level === "batch" && (
                  <div className="space-y-1">
                    <Label className="text-xs">Batch</Label>
                    <Select value={batchId} onValueChange={setBatchId}>
                      <SelectTrigger><SelectValue placeholder="Choose a batch" /></SelectTrigger>
                      <SelectContent>{batches.map((b) => <SelectItem key={b.batchId} value={String(b.batchId)}>{b.batchCode || b.batchName || `Batch ${b.batchId}`}</SelectItem>)}</SelectContent>
                    </Select>
                  </div>
                )}
                {level === "flock" && (
                  <div className="space-y-1">
                    <Label className="text-xs">Flock</Label>
                    <Select value={flockId} onValueChange={setFlockId}>
                      <SelectTrigger><SelectValue placeholder="Choose a flock" /></SelectTrigger>
                      <SelectContent>{layingFlocks.map((f) => <SelectItem key={f.flockId} value={String(f.flockId)}>{f.name}</SelectItem>)}</SelectContent>
                    </Select>
                  </div>
                )}
                <div className="space-y-1">
                  <Label className="text-xs">Cost definition</Label>
                  <Select value={view} onValueChange={(v) => setView(v as typeof view)}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="full">Full cost</SelectItem>
                      <SelectItem value="direct">Direct cost</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
              </CardContent>
            </Card>

            {opened && (
              <div className={`rounded-md border px-3 py-2 text-sm ${changedSinceSave ? "border-amber-200 bg-amber-50 text-amber-900" : "border-sky-200 bg-sky-50 text-sky-900"}`}>
                <strong>{opened.name}</strong> (saved {opened.createdAt.slice(0, 10)}).{" "}
                {changedSinceSave
                  ? "Records have changed since it was saved: the figures below are recalculated from today's records. "
                  : "The records behind it are unchanged. "}
                Saved figures: full cost {money(opened.headline?.fullPerCrate as number | null)} a crate, direct {money(opened.headline?.directPerCrate as number | null)}, margin {money(opened.headline?.marginPerCrate as number | null)}.
                <button type="button" className="ml-2 underline" onClick={() => setOpened(null)}>Dismiss</button>
              </div>
            )}

            {error && <p className="flex items-center gap-2 rounded-md border border-rose-200 bg-rose-50 px-3 py-2 text-sm text-rose-800"><AlertTriangle className="h-4 w-4" />{error}</p>}
            {loading && !a && <p className="flex items-center gap-2 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Gathering production and cost records…</p>}
            {(level === "batch" && !batchId) || (level === "flock" && !flockId) ? (
              <p className="text-sm text-slate-500">Choose a {level} to analyse.</p>
            ) : a && facts && (
              <Tabs value={mode} onValueChange={(v) => setMode(v as typeof mode)}>
                <TabsList className={`${PROMINENT_TABS_LIST} print:hidden`}>
                  <TabsTrigger value="recorded" className={PROMINENT_TABS_TRIGGER}><ClipboardCheck className="mr-1.5 h-4 w-4" />Recorded analysis</TabsTrigger>
                  <TabsTrigger value="scenario" className={PROMINENT_TABS_TRIGGER}><FlaskConical className="mr-1.5 h-4 w-4" />What-If scenario</TabsTrigger>
                </TabsList>

                <TabsContent value="recorded" className="mt-4 space-y-4">
                  <div className="flex flex-wrap items-center gap-2 text-sm text-slate-600">
                    <CompletenessBadge status={a.completeness} />
                    <span>{scopeLabel} · {startDate} → {endDate} · {a.eggsPerCrate} eggs a crate{loading ? " · refreshing…" : ""}</span>
                  </div>

                  <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
                    <Kpi label={a.fullLabel} value={money(a.fullPerCrate)} tone="sky" emphasis hint="Direct cost plus allocated overhead, depreciation and pre-laying cost, per crate of saleable eggs." />
                    <Kpi label={a.directLabel} value={money(a.directPerCrate)} tone="emerald" hint="Feed, medication, labour and flock-assigned costs, per crate of saleable eggs." />
                    <Kpi label="Cost per saleable egg" value={money(view === "full" ? a.fullPerEgg : a.directPerEgg, 4)} tone="slate" sub={view === "full" ? "Full cost" : "Direct cost"} />
                    <Kpi label="Avg selling price / crate" value={money(a.price.pricePerCrate)} tone="violet" sub={a.price.eggsSold > 0 ? `${num(a.price.eggsSold)} eggs sold` : "No egg sales"} />
                    <Kpi label="Estimated margin / crate" value={money(a.marginPerCrate)} tone={a.marginPerCrate != null && a.marginPerCrate < 0 ? "rose" : "emerald"} sub={a.marginPct != null ? `${pct(a.marginPct)} of price` : undefined} />
                    <Kpi label="Saleable crates" value={num(a.saleableCrates, 1)} tone="amber" sub={`${num(a.saleable)} of ${num(a.gross)} eggs laid`} />
                  </div>

                  <div className="grid gap-3 sm:grid-cols-3">
                    <Kpi label="Feed cost / crate" value={money(a.feedPerCrate)} tone="slate" />
                    <Kpi label="Packaged cost / crate" value={money(a.packagedPerCrate)} tone="slate" sub="Full cost + packaging & supplies" />
                    <Kpi label="Broken / lost eggs" value={pct(a.gross > 0 ? (a.gross - a.saleable) / a.gross : null)} tone="slate"
                      sub={`${num(a.broken)} broken + ${num(a.otherLoss)} other loss`} />
                  </div>
                  {a.byproductAdjustedPerCrate != null && (
                    <p className="text-xs text-slate-600">Byproduct-adjusted full cost (less broken-egg sales, by policy): <strong>{money(a.byproductAdjustedPerCrate)}</strong> a crate.</p>
                  )}

                  <Section title="Data completeness" icon={ClipboardCheck} description="What this analysis could and could not find. A zero cost is not proof that nothing was spent.">
                    <WarningList warnings={a.warnings} />
                  </Section>

                  <CostBreakdown a={a} view={view} onDrill={(key, label) => setDrill({ key, label })} />

                  <div className="grid gap-4 xl:grid-cols-2">
                    <PriceAnalyzer a={a} view={view} />
                    <ReverseCalculators a={a} view={view} />
                  </div>

                  <FlockComparison a={a} />
                  <PreLayingPanel facts={facts} a={a} canManage={isAdmin} onChanged={() => void load()} />
                  <Trends facts={facts} scope={scope} />

                  <Section title="Reconciliation with the books" icon={Scale}
                    description="Production cost asks what went into the eggs; the P&L asks what was expensed in the period. These lines explain the difference.">
                    <div className="grid gap-4 md:grid-cols-2">
                      <div>
                        <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-slate-500">Expenses left out of this analysis</p>
                        {a.excluded.length === 0 ? <p className="text-sm text-slate-500">None.</p> : (
                          <ul className="space-y-1 text-sm">{a.excluded.map((x) => <li key={x.component} className="flex justify-between gap-3"><span>{x.label} <span className="text-slate-400">({x.count})</span></span><span className="tabular-nums">{money(x.amount)}</span></li>)}</ul>
                        )}
                      </div>
                      <div>
                        <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-slate-500">Shared cost that is not egg cost this period</p>
                        {a.notEggCost.length === 0 && a.unallocatedShared === 0 ? <p className="text-sm text-slate-500">None.</p> : (
                          <ul className="space-y-1 text-sm">
                            {a.notEggCost.map((x) => <li key={x.label} className="flex justify-between gap-3"><span>{x.label}</span><span className="tabular-nums">{money(x.amount)}</span></li>)}
                            {a.unallocatedShared > 0 && <li className="flex justify-between gap-3 text-amber-800"><span>Could not be allocated</span><span className="tabular-nums">{money(a.unallocatedShared)}</span></li>}
                          </ul>
                        )}
                        <p className="mt-2 text-xs text-slate-500">Pre-laying cost is a management allocation: on the P&amp;L the birds and rearing costs were expensed when bought or used.</p>
                      </div>
                    </div>
                  </Section>
                </TabsContent>

                <TabsContent value="scenario" className="mt-4">
                  <WhatIfPanel base={a} inputs={scenario} onChange={setScenario} view={view} />
                </TabsContent>
              </Tabs>
            )}
          </div>
        </main>
      </div>

      <DrilldownDialog open={drill != null} title={drill?.label ?? ""} rows={drillRows} onOpenChange={(o) => { if (!o) setDrill(null) }} />
      {facts && (
        <CostSettingsDialog open={settingsOpen} settings={facts.settings} eggsPerCrate={facts.packaging.eggsPerCrate} canManage={isAdmin}
          onOpenChange={setSettingsOpen} onSaved={() => { setSettingsOpen(false); void load() }} />
      )}
      <SaveSnapshotDialog open={saveOpen} mode={mode === "scenario" ? "Scenario" : "Recorded"}
        defaultName={`${scopeLabel} ${mode === "scenario" ? "scenario" : "analysis"} ${startDate} to ${endDate}`}
        onOpenChange={setSaveOpen} onSave={doSave} />
      <OpenSnapshotDialog open={openOpen} onOpenChange={setOpenOpen} onOpen={(s) => void doOpen(s)} />
    </div>
  )
}
