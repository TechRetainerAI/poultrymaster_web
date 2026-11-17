"use client"

// =============================================================================
// Batch Bird Reconciliation (/poultry/reports/batch-bird-reconciliation) — 413
//
// For every batch: the birds bought, where they went and what is left.
//   Original = Originally allocated to flocks + removed before placing
//              (sold / died / culled / transferred / other) + unallocated live
//              + unexplained
// Flock-level history (deaths after placing, opening positions) is shown on the
// flock drilldown and is never subtracted again at batch level. All figures are
// sppoultrybatchreconcile_summary / _detail -- the same functions the Reconcile
// dialog and Initial Farm Setup post through.
//
// Admins also get "Data checks": the read-only diagnostic of bird movements
// written before 413, a dry run, and the metadata-only repair.
// =============================================================================

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { ArrowLeft, ClipboardCheck, Loader2, RefreshCw, ShieldCheck } from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { useLogout } from "@/hooks/use-logout"
import { usePermissions } from "@/hooks/use-permissions"
import { useToast } from "@/hooks/use-toast"
import { BatchReconcileDialog } from "@/components/poultry/batch-reconcile-dialog"
import {
  applyBirdMovementRepair, diagnoseBirdMovements, getBatchBirdReconciliation, getBatchBirdReconciliationDetail,
  type BatchBirdReconciliationRow, type BatchReconciliationDetail, type BirdRepairDiagnosticRow,
} from "@/lib/api/bird-reconciliation"

const n = (v: number | null | undefined) => (v ?? 0).toLocaleString()
const money = (v: number | null | undefined) =>
  v == null ? "—" : Number(v).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })

const STATUS: Record<BatchBirdReconciliationRow["status"], { label: string; cls: string }> = {
  FullyAccountedFor: { label: "Fully accounted for", cls: "bg-emerald-100 text-emerald-800" },
  NeedsReconciliation: { label: "Needs reconciliation", cls: "bg-amber-100 text-amber-800" },
  OverAllocated: { label: "More placed than bought", cls: "bg-red-100 text-red-800" },
}

export default function BatchBirdReconciliationReport() {
  const logout = useLogout()
  const { toast } = useToast()
  const permissions = usePermissions()
  const [rows, setRows] = useState<BatchBirdReconciliationRow[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [drill, setDrill] = useState<BatchBirdReconciliationRow | null>(null)
  const [detail, setDetail] = useState<BatchReconciliationDetail | null>(null)
  const [reconcile, setReconcile] = useState<BatchBirdReconciliationRow | null>(null)
  const [checks, setChecks] = useState<BirdRepairDiagnosticRow[] | null>(null)
  const [checking, setChecking] = useState(false)

  const load = useCallback(async () => {
    setError(null)
    try { setRows(await getBatchBirdReconciliation()) } catch (e: any) { setError(e?.message ?? "Could not load"); setRows([]) }
  }, [])
  useEffect(() => { load() }, [load])

  // ?batchId=N opens that batch's drilldown -- the "view source" link the
  // Initial Farm Setup wizard shows next to an already-recorded disposition.
  const [deepLinked, setDeepLinked] = useState(false)
  useEffect(() => {
    if (deepLinked || !rows || typeof window === "undefined") return
    setDeepLinked(true)
    const id = Number(new URLSearchParams(window.location.search).get("batchId"))
    const row = id ? rows.find((r) => r.batchId === id) : undefined
    if (row) setDrill(row)
  }, [rows, deepLinked])

  useEffect(() => {
    if (!drill) { setDetail(null); return }
    getBatchBirdReconciliationDetail(drill.batchId).then(setDetail).catch((e) =>
      toast({ title: "Could not load the batch", description: e?.message, variant: "destructive" }))
  }, [drill, toast])

  const totals = useMemo(() => (rows ?? []).reduce((t, r) => ({
    original: t.original + r.originalBirds, allocated: t.allocated + r.originallyAllocated,
    sold: t.sold + r.batchSold, mort: t.mort + r.batchMortality,
    other: t.other + r.batchCulled + r.batchTransferred + r.batchOtherRemovals - r.batchAdditions,
    unalloc: t.unalloc + r.unallocatedLive, flockLive: t.flockLive + r.flockLiveBirds,
    live: t.live + r.totalLiveBirds, unexplained: t.unexplained + r.unexplained,
    flockGone: t.flockGone + flockHistory(r) + flockSince(r) + (r.flockOtherChanges ?? 0),
  }), { original: 0, allocated: 0, sold: 0, mort: 0, other: 0, unalloc: 0, flockLive: 0, live: 0, unexplained: 0, flockGone: 0 }), [rows])

  async function runChecks() {
    setChecking(true)
    try { setChecks(await diagnoseBirdMovements()) }
    catch (e: any) { toast({ title: "Data check failed", description: e?.message, variant: "destructive" }) }
    finally { setChecking(false) }
  }

  async function repair(dryRun: boolean) {
    setChecking(true)
    try {
      const res = await applyBirdMovementRepair(dryRun)
      toast({
        title: dryRun ? `Dry run: ${res.length} movement(s) would be linked` : `${res.filter((r) => r.applied).length} movement(s) linked`,
        description: dryRun ? "Nothing was changed." : "Only batch / flock links were set; no bird quantity changed. Each change is logged.",
      })
      if (!dryRun) await runChecks()
    } catch (e: any) {
      toast({ title: "Repair failed", description: e?.message, variant: "destructive" })
    } finally {
      setChecking(false)
    }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex min-w-0 flex-1 flex-col">
        <DashboardHeader />
        <main className="min-w-0 flex-1 overflow-y-auto overflow-x-hidden p-4 pb-16 sm:p-6 lg:pb-4">
          <div className="mx-auto w-full max-w-7xl space-y-5">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div className="flex items-start gap-3">
                <Link href="/poultry/reports"><Button variant="ghost" size="icon"><ArrowLeft className="h-5 w-5" /></Button></Link>
                <div>
                  <h1 className="text-2xl font-semibold text-slate-900">Batch Bird Reconciliation</h1>
                  <p className="text-sm text-slate-500">Every bird each batch bought: in a flock, waiting to be placed, or gone — and why.</p>
                </div>
              </div>
              <Button variant="outline" onClick={load}><RefreshCw className="mr-2 h-4 w-4" />Refresh</Button>
            </div>

            {error && <p className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</p>}

            <div className="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-6">
              <Card label="Birds bought" value={n(totals.original)} />
              <Card label="Gone from flocks" value={n(totals.flockGone)} />
              <Card label="Live in flocks" value={n(totals.flockLive)} />
              <Card label="Live, not yet in a flock" value={n(totals.unalloc)} />
              <Card label="Total live birds" value={n(totals.live)} tone="text-emerald-700" />
              <Card label="Unexplained" value={n(totals.unexplained)} tone={totals.unexplained === 0 ? "text-emerald-700" : "text-amber-700"} />
            </div>

            <div className="overflow-x-auto rounded-xl border border-slate-200 bg-white">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Batch</TableHead>
                    <TableHead className="text-right">Original birds</TableHead>
                    <TableHead className="text-right">Originally allocated</TableHead>
                    <TableHead className="text-right">Batch-level sales</TableHead>
                    <TableHead className="text-right">Batch-level mortality</TableHead>
                    <TableHead className="text-right">Other dispositions</TableHead>
                    <TableHead className="text-right" title="From each flock's opening position in Initial Farm Setup: died, sold, culled, transferred or otherwise lost before tracking began">Lost from flocks before setup</TableHead>
                    <TableHead className="text-right">Flock deaths since setup</TableHead>
                    <TableHead className="text-right">Sold / culled / moved from flocks since</TableHead>
                    <TableHead className="text-right" title="Count corrections on production records, flock quantity adjustments, flock-to-flock transfers, and birds left in closed or deleted flocks">Other flock changes</TableHead>
                    <TableHead className="text-right">Unallocated live</TableHead>
                    <TableHead className="text-right">Current flock live birds</TableHead>
                    <TableHead className="text-right">Total live</TableHead>
                    <TableHead className="text-right">Unexplained difference</TableHead>
                    <TableHead>Status</TableHead>
                    <TableHead />
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {rows === null ? (
                    <TableRow><TableCell colSpan={16} className="py-10 text-center"><Loader2 className="mx-auto h-5 w-5 animate-spin text-slate-400" /></TableCell></TableRow>
                  ) : rows.length === 0 ? (
                    <TableRow><TableCell colSpan={16} className="py-10 text-center text-slate-500">No batches yet.</TableCell></TableRow>
                  ) : rows.map((r) => (
                    <TableRow key={r.batchId} className="cursor-pointer hover:bg-slate-50" onClick={() => setDrill(r)}>
                      <TableCell>
                        <div className="font-medium text-slate-900">{r.batchCode}</div>
                        <div className="text-xs text-slate-500">{r.batchName}{r.isHistorical ? " · existing batch" : ""}</div>
                      </TableCell>
                      <TableCell className="text-right tabular-nums">{n(r.originalBirds)}</TableCell>
                      <TableCell className="text-right tabular-nums">{n(r.originallyAllocated)}</TableCell>
                      <TableCell className="text-right tabular-nums">{n(r.batchSold)}</TableCell>
                      <TableCell className="text-right tabular-nums">{n(r.batchMortality)}</TableCell>
                      <TableCell className="text-right tabular-nums">{n(r.batchCulled + r.batchTransferred + r.batchOtherRemovals - r.batchAdditions)}</TableCell>
                      <TableCell className="text-right tabular-nums" title={historyBreakdown(r)}>{n(flockHistory(r))}</TableCell>
                      <TableCell className="text-right tabular-nums">{n(r.flockRecordedMortality ?? 0)}</TableCell>
                      <TableCell className="text-right tabular-nums" title={`Sold ${n(r.flockPostedSold ?? 0)} · culled ${n(r.flockCulled ?? 0)} · transferred ${n(r.flockTransferred ?? 0)}`}>{n(flockOutSince(r))}</TableCell>
                      <TableCell className={`text-right tabular-nums ${(r.flockOtherChanges ?? 0) === 0 ? "text-slate-400" : "text-slate-700"}`}>{n(r.flockOtherChanges ?? 0)}</TableCell>
                      <TableCell className="text-right tabular-nums">{n(r.unallocatedLive)}</TableCell>
                      <TableCell className="text-right tabular-nums">{n(r.flockLiveBirds)}</TableCell>
                      <TableCell className="text-right font-medium tabular-nums">{n(r.totalLiveBirds)}</TableCell>
                      <TableCell className={`text-right tabular-nums ${r.unexplained === 0 ? "" : r.unexplained < 0 ? "text-red-600" : "text-amber-700"}`}>{n(r.unexplained)}</TableCell>
                      <TableCell><span className={`rounded-full px-2 py-0.5 text-xs font-medium ${STATUS[r.status].cls}`}>{STATUS[r.status].label}</span></TableCell>
                      <TableCell>
                        {(r.unallocatedPool > 0 || r.status !== "FullyAccountedFor") && (
                          <Button size="sm" variant="outline" onClick={(e) => { e.stopPropagation(); setReconcile(r) }}>
                            <ClipboardCheck className="mr-1 h-4 w-4" />Reconcile
                          </Button>
                        )}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
            <p className="text-xs text-slate-500">
              Every row adds up: originally allocated = lost from flocks before setup + flock deaths since + sold / culled / moved since
              + other flock changes + current flock live birds. Click a batch for each flock. Historical sales are history only: they put no cash in today
              and are not this period&apos;s revenue; only money still owed appears, as an opening customer debt.
            </p>

            {permissions.isAdmin && (
              <div className="rounded-xl border border-slate-200 bg-white">
                <div className="flex flex-wrap items-center justify-between gap-2 border-b px-4 py-3">
                  <div className="flex items-center gap-2">
                    <ShieldCheck className="h-5 w-5 text-slate-500" />
                    <span className="font-semibold text-slate-800">Data checks</span>
                    <span className="text-xs text-slate-500">Bird movements recorded before this check existed</span>
                  </div>
                  <div className="flex flex-wrap gap-2">
                    <Button size="sm" variant="outline" onClick={runChecks} disabled={checking}>{checking ? <Loader2 className="h-4 w-4 animate-spin" /> : "Run check"}</Button>
                    {checks && checks.some((c) => c.autoRepairable) && (
                      <>
                        <Button size="sm" variant="outline" onClick={() => repair(true)} disabled={checking}>Dry run</Button>
                        <Button size="sm" onClick={() => { if (window.confirm("Link the verified movements to their batch and flock? No bird count changes.")) repair(false) }} disabled={checking}>Repair verified links</Button>
                      </>
                    )}
                  </div>
                </div>
                {checks && (
                  <div className="overflow-x-auto">
                    <Table>
                      <TableHeader><TableRow>
                        <TableHead>Check</TableHead><TableHead>Severity</TableHead><TableHead>Flock / batch</TableHead>
                        <TableHead>Now</TableHead><TableHead>Expected</TableHead><TableHead>Proposed</TableHead>
                        <TableHead>Double-count risk</TableHead><TableHead>Confidence</TableHead><TableHead>Evidence</TableHead>
                      </TableRow></TableHeader>
                      <TableBody>
                        {checks.length === 0 ? (
                          <TableRow><TableCell colSpan={9} className="py-6 text-center text-emerald-700">Nothing to repair.</TableCell></TableRow>
                        ) : checks.map((c, i) => (
                          <TableRow key={`${c.checkCode}-${c.ledgerRowId ?? c.openingPositionId ?? c.batchId}-${i}`}>
                            <TableCell className="text-xs font-medium">{c.checkCode.replaceAll("_", " ").toLowerCase()}</TableCell>
                            <TableCell className="text-xs">{c.severity}</TableCell>
                            <TableCell className="text-xs">{c.flockName ?? (c.batchId ? `batch #${c.batchId}` : "—")}</TableCell>
                            <TableCell className="text-xs">{c.currentValue}</TableCell>
                            <TableCell className="text-xs">{c.expectedValue}</TableCell>
                            <TableCell className="text-xs">{c.proposedCorrection}</TableCell>
                            <TableCell className="text-xs">{c.doubleApplicationRisk}</TableCell>
                            <TableCell className="text-xs">{c.confidence}</TableCell>
                            <TableCell className="max-w-xs text-xs text-slate-500">{c.evidence}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </div>
                )}
              </div>
            )}
          </div>
        </main>
      </div>

      <Dialog open={drill !== null} onOpenChange={(o) => { if (!o) setDrill(null) }}>
        <DialogContent className="w-[96vw] max-h-[90vh] overflow-y-auto sm:max-w-[min(96vw,1440px)]">
          <DialogHeader><DialogTitle>{drill?.batchCode} — where the birds went</DialogTitle></DialogHeader>
          {!detail ? <Loader2 className="mx-auto h-6 w-6 animate-spin text-slate-400" /> : (
            <div className="space-y-5 text-sm">
              <section>
                <h3 className="mb-1 font-semibold text-slate-800">Flocks (flock-level history)</h3>
                <div className="overflow-x-auto rounded-lg border">
                  <Table className="[&_th]:whitespace-normal [&_th]:align-bottom [&_th]:leading-tight">
                    <TableHeader><TableRow>
                      <TableHead>Flock</TableHead><TableHead className="text-right">Originally placed</TableHead>
                      <TableHead className="text-right">Hist. mortality</TableHead><TableHead className="text-right">Hist. sold</TableHead>
                      <TableHead className="text-right">Hist. culled</TableHead><TableHead className="text-right">Hist. transferred</TableHead>
                      <TableHead className="text-right">Hist. other</TableHead><TableHead className="text-right">Recorded mortality</TableHead>
                      <TableHead className="text-right">Sold / culled / moved since</TableHead><TableHead className="text-right">Live now</TableHead>
                    </TableRow></TableHeader>
                    <TableBody>
                      {detail.flocks.map((f) => (
                        <TableRow key={f.flockId}>
                          <TableCell>{f.flockName}{f.isClosed ? " (closed)" : ""}{f.isDeleted ? " (deleted)" : ""}{f.productionRecordCount === 0 ? <span className="ml-1 text-xs text-slate-400">no production record</span> : null}</TableCell>
                          <TableCell className="text-right tabular-nums">{n(f.originallyPlaced)}</TableCell>
                          <TableCell className="text-right tabular-nums">{n(f.historicalMortality)}</TableCell>
                          <TableCell className="text-right tabular-nums">{n(f.historicalSold)}</TableCell>
                          <TableCell className="text-right tabular-nums">{n(f.historicalCulled)}</TableCell>
                          <TableCell className="text-right tabular-nums">{n(f.historicalTransferred)}</TableCell>
                          <TableCell className="text-right tabular-nums">{n(f.historicalOther)}</TableCell>
                          <TableCell className="text-right tabular-nums">{n(f.recordedMortality)}</TableCell>
                          <TableCell className="text-right tabular-nums">{n(f.birdsSold + f.birdsCulled + f.birdsTransferred)}</TableCell>
                          <TableCell className="text-right font-medium tabular-nums">{n(f.currentLiveBirds)}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              </section>

              <section>
                <h3 className="mb-1 font-semibold text-slate-800">Bird movements</h3>
                <div className="overflow-x-auto rounded-lg border">
                  <Table className="[&_th]:whitespace-normal [&_th]:align-bottom [&_th]:leading-tight">
                    <TableHeader><TableRow>
                      <TableHead>Date</TableHead><TableHead>Pool</TableHead><TableHead>Reason</TableHead>
                      <TableHead className="text-right">Birds</TableHead><TableHead className="text-right">Before → after</TableHead>
                      <TableHead>Source</TableHead><TableHead>Note</TableHead>
                    </TableRow></TableHeader>
                    <TableBody>
                      {detail.movements.length === 0 ? (
                        <TableRow><TableCell colSpan={7} className="text-center text-slate-500">None.</TableCell></TableRow>
                      ) : detail.movements.map((m) => (
                        <TableRow key={m.birdAdjustmentId} className={m.reversedById || m.reversesId ? "text-slate-400" : ""}>
                          <TableCell>{String(m.date).slice(0, 10)}</TableCell>
                          <TableCell>{m.scope === "BatchUnallocated" ? "Not placed in a flock" : m.flockName}</TableCell>
                          <TableCell>{m.reason ?? m.movementType}{m.reversedById ? " (reversed)" : ""}</TableCell>
                          <TableCell className={`text-right tabular-nums ${m.quantity < 0 ? "text-red-600" : "text-emerald-700"}`}>{m.quantity > 0 ? "+" : ""}{n(m.quantity)}</TableCell>
                          <TableCell className="text-right tabular-nums">{n(m.birdsBefore)} → {n(m.birdsAfter)}</TableCell>
                          <TableCell className="text-xs">{m.sourceType ?? "—"}</TableCell>
                          <TableCell className="max-w-xs truncate text-xs">{m.note}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              </section>

              <section>
                <h3 className="mb-1 font-semibold text-slate-800">Historical sales</h3>
                <div className="overflow-x-auto rounded-lg border">
                  <Table className="[&_th]:whitespace-normal [&_th]:align-bottom [&_th]:leading-tight">
                    <TableHeader><TableRow>
                      <TableHead>Date</TableHead><TableHead>From</TableHead><TableHead className="text-right">Birds</TableHead>
                      <TableHead className="text-right">Price</TableHead><TableHead className="text-right">Value</TableHead>
                      <TableHead className="text-right">Received</TableHead><TableHead className="text-right">Owed</TableHead>
                      <TableHead>Customer / debt</TableHead><TableHead>Status</TableHead>
                    </TableRow></TableHeader>
                    <TableBody>
                      {detail.historicalSales.length === 0 ? (
                        <TableRow><TableCell colSpan={9} className="text-center text-slate-500">None.</TableCell></TableRow>
                      ) : detail.historicalSales.map((h) => (
                        <TableRow key={h.historicalSaleId} className={h.status === "Reversed" ? "text-slate-400 line-through" : ""}>
                          <TableCell>{String(h.saleDate).slice(0, 10)}</TableCell>
                          <TableCell>{h.flockName ?? "Not placed in a flock"}</TableCell>
                          <TableCell className="text-right tabular-nums">{n(h.birds)}</TableCell>
                          <TableCell className="text-right tabular-nums">{h.valueUnknown ? "unknown" : money(h.pricePerBird)}</TableCell>
                          <TableCell className="text-right tabular-nums">{money(h.totalValue)}</TableCell>
                          <TableCell className="text-right tabular-nums">{money(h.amountReceived)}</TableCell>
                          <TableCell className="text-right tabular-nums">{money(h.amountOwed)}</TableCell>
                          <TableCell className="text-xs">{h.customerName ?? "—"}{h.debtNumber ? ` · ${h.debtNumber}` : ""}</TableCell>
                          <TableCell className="text-xs">{h.status}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              </section>
            </div>
          )}
        </DialogContent>
      </Dialog>

      <BatchReconcileDialog
        open={reconcile !== null}
        onOpenChange={(o) => { if (!o) setReconcile(null) }}
        batchId={reconcile?.batchId ?? null}
        batchLabel={reconcile ? `${reconcile.batchCode} ${reconcile.batchName}` : undefined}
        source="Batch Bird Reconciliation report"
        onPosted={load}
      />
    </div>
  )
}

// Birds placed in a flock and lost before tracking began (the opening position).
function flockHistory(r: BatchBirdReconciliationRow): number {
  return (r.flockHistMortality ?? 0) + (r.flockHistSold ?? 0) + (r.flockHistCulled ?? 0)
    + (r.flockHistTransferred ?? 0) + (r.flockHistOther ?? 0)
}

function historyBreakdown(r: BatchBirdReconciliationRow): string {
  return `Died ${n(r.flockHistMortality ?? 0)} · sold ${n(r.flockHistSold ?? 0)} · culled ${n(r.flockHistCulled ?? 0)}`
    + ` · transferred ${n(r.flockHistTransferred ?? 0)} · other ${n(r.flockHistOther ?? 0)}`
}

function flockOutSince(r: BatchBirdReconciliationRow): number {
  return (r.flockPostedSold ?? 0) + (r.flockCulled ?? 0) + (r.flockTransferred ?? 0)
}

function flockSince(r: BatchBirdReconciliationRow): number {
  return (r.flockRecordedMortality ?? 0) + flockOutSince(r)
}

function Card({ label, value, tone = "text-slate-900" }: { label: string; value: string; tone?: string }) {
  return (
    <div className="rounded-xl border border-slate-200 bg-white px-4 py-3">
      <div className="text-xs font-medium uppercase tracking-wide text-slate-500">{label}</div>
      <div className={`mt-1 text-2xl font-semibold tabular-nums ${tone}`}>{value}</div>
    </div>
  )
}
