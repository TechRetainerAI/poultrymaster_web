"use client"

import { useEffect, useMemo, useState } from "react"
import { useParams, useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { NumberInput } from "@/components/ui/number-input"
import { Input } from "@/components/ui/input"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog"
import { useToast } from "@/hooks/use-toast"
import { ArrowLeft, Scale, Send, Save, ClipboardCheck, CheckCircle2, AlertTriangle } from "lucide-react"
import { cn } from "@/lib/utils"
import { getUserContext } from "@/lib/utils/user-context"
import { getFlocks, type Flock } from "@/lib/api/flock"
import { getProductionRecords, type ProductionRecord } from "@/lib/api/production-record"
import {
  getBatchProductionRecord,
  saveBatchAllocation,
  postBatchAllocation,
  batchNameLabel,
  type ProductionBatchRecord,
  type ProductionBatchAllocation,
} from "@/lib/api/production-batch"
import {
  type AllocRow,
  type AllocMethod,
  type ReconLine,
  applyMethod,
  buildBlankRows,
  buildReconciliation,
  rowTotalEggs,
  rowBirdsAfter,
  rowEggPct,
  rowFeedCost,
  rowMedCost,
} from "@/lib/utils/batch-allocation"

const METHODS: { key: AllocMethod; title: string; desc: string }[] = [
  { key: "Manual", title: "Manual Allocation", desc: "Enter exact numbers per flock. The grid opens blank for you to fill in." },
  { key: "ByBirdCount", title: "By Bird Count", desc: "Distribute totals in proportion to each flock's birds left." },
  { key: "ByPreviousProduction", title: "By Previous Production %", desc: "Distribute by recent laying performance (last 7 records). Falls back to bird count." },
  { key: "EqualSplit", title: "Equal Split", desc: "Split every total evenly across the included flocks." },
]

function allocationsToRows(batch: ProductionBatchRecord): AllocRow[] {
  const feedIds = (batch.feeds || []).map((f) => f.itemId)
  const medIds = (batch.medications || []).map((m) => m.itemId)
  return (batch.allocations || []).map((a) => ({
    flockId: a.flockId,
    flockName: a.flockName || `Flock ${a.flockId}`,
    ageInWeeks: a.ageInWeeks ?? null,
    ageInDays: a.ageInDays ?? null,
    birdsBefore: a.birdsBefore ?? 0,
    deaths: a.deaths ?? 0,
    p1: a.firstPickEggs ?? 0,
    p2: a.secondPickEggs ?? 0,
    p3: a.thirdPickEggs ?? 0,
    p4: a.fourthPickEggs ?? 0,
    broken: a.brokenEggs ?? 0,
    meaty: a.meatyEggs ?? 0,
    soft: a.softEggs ?? 0,
    lost: a.lostEggs ?? 0,
    feedQty: Object.fromEntries(feedIds.map((id) => [id, (a.feeds || []).find((f) => f.itemId === id)?.qty ?? 0])),
    medQty: Object.fromEntries(medIds.map((id) => [id, (a.medications || []).find((m) => m.itemId === id)?.qty ?? 0])),
    notes: a.notes || "",
  }))
}

export default function AllocateBatchPage() {
  const router = useRouter()
  const params = useParams()
  const batchId = Number(params?.id)
  const { toast } = useToast()

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [batch, setBatch] = useState<ProductionBatchRecord | null>(null)
  const [flocksById, setFlocksById] = useState<Map<number, Flock>>(new Map())
  const [records, setRecords] = useState<ProductionRecord[]>([])
  const [rows, setRows] = useState<AllocRow[]>([])
  const [method, setMethod] = useState<AllocMethod | null>(null)
  const [methodOpen, setMethodOpen] = useState(false)
  const [reconOpen, setReconOpen] = useState(false)

  const readOnly = !!batch && !["PendingAllocation", "Allocated", "Reversed"].includes(batch.status)

  useEffect(() => {
    if (!Number.isFinite(batchId)) return
    const { userId, farmId } = getUserContext()
    ;(async () => {
      setLoading(true)
      const [batchRes, flockRes, recRes] = await Promise.all([
        getBatchProductionRecord(batchId, farmId),
        getFlocks(userId, farmId),
        getProductionRecords(userId, farmId),
      ])
      if (!batchRes.success || !batchRes.data) {
        toast({ title: "Could not load batch", description: batchRes.message, variant: "destructive" })
        setLoading(false)
        return
      }
      const b = batchRes.data
      const fmap = new Map<number, Flock>()
      ;(flockRes.data || []).forEach((f) => fmap.set(f.flockId, f))
      const recs = (recRes.data || []) as ProductionRecord[]
      setBatch(b)
      setFlocksById(fmap)
      setRecords(recs)

      if ((b.allocations || []).length > 0) {
        setRows(allocationsToRows(b))
        setMethod("Manual")
      } else if (["PendingAllocation", "Allocated"].includes(b.status)) {
        setRows(buildBlankRows(b, fmap, recs))
        setMethodOpen(true)
      } else {
        setRows(buildBlankRows(b, fmap, recs))
      }
      setLoading(false)
    })()
  }, [batchId])

  const recon = useMemo(() => (batch ? buildReconciliation(rows, batch) : { lines: [], balanced: false }), [rows, batch])
  // Index recon lines by field key so the grid summary rows and the modal both
  // read from the SAME calculation — they can never disagree.
  const reconByKey = useMemo(() => {
    const m: Record<string, ReconLine> = {}
    recon.lines.forEach((l) => (m[l.key] = l))
    return m
  }, [recon])
  const allocBirds = useMemo(() => rows.reduce((s, r) => s + (r.birdsBefore || 0), 0), [rows])
  // Blocking mismatches only (egg/qty fields — money lines are informational).
  const mismatches = useMemo(() => recon.lines.filter((l) => !l.money && !l.balanced), [recon])
  const fmtRecon = (l: ReconLine, v: number) =>
    l.money ? v.toFixed(2) : l.decimals ? v.toFixed(l.decimals) : String(Math.round(v))

  function chooseMethod(m: AllocMethod) {
    if (!batch) return
    setMethod(m)
    setRows((prev) => applyMethod(m, prev.length ? prev : buildBlankRows(batch, flocksById, records), batch, records))
    setMethodOpen(false)
  }

  function patchRow(i: number, patch: Partial<AllocRow>) {
    setRows((prev) => prev.map((r, idx) => (idx === i ? { ...r, ...patch } : r)))
  }
  function patchFeed(i: number, itemId: number, v: number) {
    setRows((prev) => prev.map((r, idx) => (idx === i ? { ...r, feedQty: { ...r.feedQty, [itemId]: v } } : r)))
  }
  function patchMed(i: number, itemId: number, v: number) {
    setRows((prev) => prev.map((r, idx) => (idx === i ? { ...r, medQty: { ...r.medQty, [itemId]: v } } : r)))
  }

  function buildPayload(): ProductionBatchAllocation[] {
    if (!batch) return []
    return rows.map((r) => ({
      flockId: r.flockId,
      flockName: r.flockName,
      allocationMethod: method || "Manual",
      ageInWeeks: r.ageInWeeks,
      ageInDays: r.ageInDays,
      birdsBefore: r.birdsBefore,
      deaths: r.deaths,
      birdsAfter: rowBirdsAfter(r),
      firstPickEggs: r.p1,
      secondPickEggs: r.p2,
      thirdPickEggs: r.p3,
      fourthPickEggs: r.p4,
      brokenEggs: r.broken,
      meatyEggs: r.meaty,
      softEggs: r.soft,
      lostEggs: r.lost,
      totalEggs: rowTotalEggs(r),
      eggPercentage: Number(rowEggPct(r).toFixed(2)),
      feedKg: (batch.feeds || []).reduce((s, f) => s + (r.feedQty[f.itemId] || 0), 0),
      totalFeedCost: Number(rowFeedCost(r, batch).toFixed(2)),
      totalMedicationCost: Number(rowMedCost(r, batch).toFixed(2)),
      totalCostOfProduction: Number((rowFeedCost(r, batch) + rowMedCost(r, batch)).toFixed(2)),
      notes: r.notes || null,
      feeds: (batch.feeds || []).map((f) => ({
        batchUsageId: f.id ?? null,
        itemId: f.itemId,
        itemName: f.itemName,
        qty: r.feedQty[f.itemId] || 0,
        unitCost: f.unitCost ?? null,
        totalCost: Number(((r.feedQty[f.itemId] || 0) * (f.unitCost || 0)).toFixed(2)),
      })),
      medications: (batch.medications || []).map((m) => ({
        batchUsageId: m.id ?? null,
        itemId: m.itemId,
        itemName: m.itemName,
        qty: r.medQty[m.itemId] || 0,
        unitCost: m.unitCost ?? null,
        totalCost: Number(((r.medQty[m.itemId] || 0) * (m.unitCost || 0)).toFixed(2)),
      })),
    }))
  }

  async function handleSave() {
    if (!batch) return
    const { userId, farmId } = getUserContext()
    setSaving(true)
    const res = await saveBatchAllocation(batch.id, farmId, { updatedBy: userId, status: "Allocated", allocations: buildPayload() })
    setSaving(false)
    if (res.success) {
      toast({ title: "Allocation saved", description: "Marked as Allocated. Post it to apply to flock records." })
      if (res.data) setBatch(res.data)
    } else {
      toast({ title: "Save failed", description: res.message, variant: "destructive" })
    }
  }

  async function handlePost() {
    if (!batch) return
    if (!recon.balanced) {
      toast({ title: "Allocation is not balanced", description: "Resolve the highlighted differences before posting.", variant: "destructive" })
      return
    }
    const { userId, farmId } = getUserContext()
    setSaving(true)
    const saveRes = await saveBatchAllocation(batch.id, farmId, { updatedBy: userId, status: "Allocated", allocations: buildPayload() })
    if (!saveRes.success) {
      setSaving(false)
      toast({ title: "Save failed", description: saveRes.message, variant: "destructive" })
      return
    }
    const postRes = await postBatchAllocation(batch.id, farmId, userId)
    setSaving(false)
    if (postRes.success) {
      toast({ title: "Allocation posted", description: "Flock records, inventory and bird counts have been updated." })
      router.push("/batch-production-records")
    } else {
      toast({ title: "Posting failed", description: postRes.message, variant: "destructive" })
    }
  }

  const handleLogout = () => {
    localStorage.clear()
    router.push("/login")
  }

  const feedCols = batch?.feeds || []
  const medCols = batch?.medications || []

  // Ordered descriptors for the grid summary rows — MUST match the body column
  // order after the Flock + Age cells (Birds, 1st..Lost, Total, Egg%, Deaths,
  // Left, feeds…, meds…, Cost, Notes). `recon` lines drive the reconcilable ones.
  type FooterCol =
    | { kind: "birds" }
    | { kind: "blank" }
    | { kind: "recon"; line?: ReconLine }
  const footerCols: FooterCol[] = [
    { kind: "birds" },
    { kind: "recon", line: reconByKey["p1"] },
    { kind: "recon", line: reconByKey["p2"] },
    { kind: "recon", line: reconByKey["p3"] },
    { kind: "recon", line: reconByKey["p4"] },
    { kind: "recon", line: reconByKey["broken"] },
    { kind: "recon", line: reconByKey["meaty"] },
    { kind: "recon", line: reconByKey["soft"] },
    { kind: "recon", line: reconByKey["lost"] },
    { kind: "recon", line: reconByKey["total"] },
    { kind: "blank" }, // Egg %
    { kind: "recon", line: reconByKey["deaths"] },
    { kind: "blank" }, // Left
    ...feedCols.map((f): FooterCol => ({ kind: "recon", line: reconByKey[`feed-${f.itemId}`] })),
    ...medCols.map((m): FooterCol => ({ kind: "recon", line: reconByKey[`med-${m.itemId}`] })),
    { kind: "recon", line: reconByKey["prodCost"] }, // Cost
    { kind: "blank" }, // Notes
  ]

  // Renders the numeric cells for one summary row (Allocated / Total Batch / Difference).
  const footerCells = (metric: "allocated" | "batch" | "diff") =>
    footerCols.map((c, idx) => {
      if (c.kind === "birds")
        return (
          <TableCell key={`f-${metric}-${idx}`} className="text-right tabular-nums">
            {metric === "allocated" ? allocBirds.toLocaleString() : ""}
          </TableCell>
        )
      if (c.kind === "blank" || !c.line) return <TableCell key={`f-${metric}-${idx}`} />
      const l = c.line
      const value = metric === "allocated" ? l.allocated : metric === "batch" ? l.batchTotal : l.diff
      const isDiff = metric === "diff"
      const bad = isDiff && !l.money && !l.balanced
      return (
        <TableCell
          key={`f-${metric}-${idx}`}
          className={cn(
            "text-right tabular-nums",
            bad && "text-red-700 font-semibold",
            isDiff && !bad && !l.money && "text-emerald-700",
          )}
        >
          {isDiff && value > 0 ? "+" : ""}
          {fmtRecon(l, value)}
        </TableCell>
      )
    })

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="max-w-[1400px] mx-auto">
            <div className="flex items-center justify-between mb-4 gap-3 flex-wrap">
              <div className="flex items-center gap-3">
                <Button variant="ghost" size="sm" onClick={() => router.push("/batch-production-records")}>
                  <ArrowLeft className="h-4 w-4 mr-1" /> Back
                </Button>
                <div>
                  <h1 className="text-xl font-semibold">Allocate Batch Production</h1>
                  <p className="text-sm text-muted-foreground">
                    Distribute the batch-level totals across the flocks included in this batch. The allocated totals must match the
                    batch totals before posting.
                  </p>
                </div>
              </div>
              {batch && (
                <div className="text-right">
                  <div className="font-medium">{batchNameLabel(batch)}</div>
                  <Badge variant="outline">{batch.status}</Badge>
                </div>
              )}
            </div>

            {loading && <div className="text-sm text-muted-foreground py-16 text-center">Loading batch…</div>}

            {!loading && batch && readOnly && (
              <Card>
                <CardContent className="py-8 text-center text-sm text-muted-foreground">
                  This batch is <strong>{batch.status}</strong> and can no longer be allocated.
                </CardContent>
              </Card>
            )}

            {!loading && batch && !readOnly && (
              <>
                <div className="flex items-center gap-2 mb-3 flex-wrap">
                  <Button variant="outline" size="sm" onClick={() => setMethodOpen(true)}>
                    <Scale className="h-4 w-4 mr-1" /> {method ? `Method: ${method}` : "Choose method"}
                  </Button>
                  {recon.balanced ? (
                    <Badge className="bg-emerald-100 text-emerald-800 gap-1">
                      <CheckCircle2 className="h-3.5 w-3.5" /> Reconciled
                    </Badge>
                  ) : (
                    <Badge variant="destructive" className="gap-1">
                      <AlertTriangle className="h-3.5 w-3.5" />
                      {mismatches.length} field{mismatches.length === 1 ? "" : "s"} need attention
                    </Badge>
                  )}
                  <Button variant="ghost" size="sm" onClick={() => setReconOpen(true)}>
                    <ClipboardCheck className="h-4 w-4 mr-1" /> View reconciliation details
                  </Button>
                  <div className="flex-1" />
                  <Button variant="outline" onClick={handleSave} disabled={saving}>
                    <Save className="h-4 w-4 mr-1" /> Save Allocation
                  </Button>
                  <Button onClick={handlePost} disabled={saving || !recon.balanced} title={recon.balanced ? undefined : "Resolve the highlighted differences before posting"}>
                    <Send className="h-4 w-4 mr-1" /> Post Allocation
                  </Button>
                </div>

                <Card className="mb-4">
                  <CardContent className="p-0 overflow-x-auto">
                    <Table className="min-w-[1100px]">
                      <TableHeader>
                        <TableRow>
                          <TableHead className="sticky left-0 bg-background z-10">Flock</TableHead>
                          <TableHead>Age</TableHead>
                          <TableHead className="text-right">Birds</TableHead>
                          <TableHead className="text-right">1st</TableHead>
                          <TableHead className="text-right">2nd</TableHead>
                          <TableHead className="text-right">3rd</TableHead>
                          <TableHead className="text-right">4th</TableHead>
                          <TableHead className="text-right">Broken</TableHead>
                          <TableHead className="text-right">Meaty</TableHead>
                          <TableHead className="text-right">Soft</TableHead>
                          <TableHead className="text-right">Lost</TableHead>
                          <TableHead className="text-right">Total</TableHead>
                          <TableHead className="text-right">Egg %</TableHead>
                          <TableHead className="text-right">Deaths</TableHead>
                          <TableHead className="text-right">Left</TableHead>
                          {feedCols.map((f) => (
                            <TableHead key={`fh-${f.itemId}`} className="text-right whitespace-nowrap">{f.itemName || "Feed"} (kg)</TableHead>
                          ))}
                          {medCols.map((m) => (
                            <TableHead key={`mh-${m.itemId}`} className="text-right whitespace-nowrap">{m.itemName || "Med"}</TableHead>
                          ))}
                          <TableHead className="text-right">Cost</TableHead>
                          <TableHead>Notes</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {rows.map((r, i) => (
                          <TableRow key={r.flockId}>
                            <TableCell className="sticky left-0 bg-background z-10 font-medium whitespace-nowrap">{r.flockName}</TableCell>
                            <TableCell className="whitespace-nowrap text-muted-foreground">
                              {r.ageInWeeks != null ? `${r.ageInWeeks}w` : "—"}
                            </TableCell>
                            <TableCell className="text-right text-muted-foreground">{r.birdsBefore}</TableCell>
                            <TableCell className="p-1"><NumberInput min="0" value={r.p1} onChange={(e) => patchRow(i, { p1: parseInt(e.target.value) || 0 })} className="w-16 text-right" /></TableCell>
                            <TableCell className="p-1"><NumberInput min="0" value={r.p2} onChange={(e) => patchRow(i, { p2: parseInt(e.target.value) || 0 })} className="w-16 text-right" /></TableCell>
                            <TableCell className="p-1"><NumberInput min="0" value={r.p3} onChange={(e) => patchRow(i, { p3: parseInt(e.target.value) || 0 })} className="w-16 text-right" /></TableCell>
                            <TableCell className="p-1"><NumberInput min="0" value={r.p4} onChange={(e) => patchRow(i, { p4: parseInt(e.target.value) || 0 })} className="w-16 text-right" /></TableCell>
                            <TableCell className="p-1"><NumberInput min="0" value={r.broken} onChange={(e) => patchRow(i, { broken: parseInt(e.target.value) || 0 })} className="w-16 text-right" /></TableCell>
                            <TableCell className="p-1"><NumberInput min="0" value={r.meaty} onChange={(e) => patchRow(i, { meaty: parseInt(e.target.value) || 0 })} className="w-16 text-right" /></TableCell>
                            <TableCell className="p-1"><NumberInput min="0" value={r.soft} onChange={(e) => patchRow(i, { soft: parseInt(e.target.value) || 0 })} className="w-16 text-right" /></TableCell>
                            <TableCell className="p-1"><NumberInput min="0" value={r.lost} onChange={(e) => patchRow(i, { lost: parseInt(e.target.value) || 0 })} className="w-16 text-right" /></TableCell>
                            <TableCell className="text-right font-medium">{rowTotalEggs(r)}</TableCell>
                            <TableCell className="text-right text-muted-foreground">{rowEggPct(r).toFixed(1)}%</TableCell>
                            <TableCell className="p-1"><NumberInput min="0" value={r.deaths} onChange={(e) => patchRow(i, { deaths: parseInt(e.target.value) || 0 })} className="w-16 text-right" /></TableCell>
                            <TableCell className="text-right text-muted-foreground">{rowBirdsAfter(r)}</TableCell>
                            {feedCols.map((f) => (
                              <TableCell key={`fc-${r.flockId}-${f.itemId}`} className="p-1">
                                <NumberInput min="0" step="0.001" value={r.feedQty[f.itemId] ?? 0} onChange={(e) => patchFeed(i, f.itemId, parseFloat(e.target.value) || 0)} className="w-20 text-right" />
                              </TableCell>
                            ))}
                            {medCols.map((m) => (
                              <TableCell key={`mc-${r.flockId}-${m.itemId}`} className="p-1">
                                <NumberInput min="0" step="0.001" value={r.medQty[m.itemId] ?? 0} onChange={(e) => patchMed(i, m.itemId, parseFloat(e.target.value) || 0)} className="w-20 text-right" />
                              </TableCell>
                            ))}
                            <TableCell className="text-right text-muted-foreground whitespace-nowrap">
                              {(rowFeedCost(r, batch) + rowMedCost(r, batch)).toFixed(2)}
                            </TableCell>
                            <TableCell className="p-1">
                              <Input value={r.notes} onChange={(e) => patchRow(i, { notes: e.target.value })} className="w-32" />
                            </TableCell>
                          </TableRow>
                        ))}

                        {/* ---- Summary rows: Allocated Total / Total Batch / Difference ---- */}
                        <TableRow className="border-t-2 bg-slate-50 font-medium">
                          <TableCell className="sticky left-0 bg-slate-50 z-10 whitespace-nowrap">Allocated Total</TableCell>
                          <TableCell />
                          {footerCells("allocated")}
                        </TableRow>
                        <TableRow className="bg-slate-50/60 text-muted-foreground">
                          <TableCell className="sticky left-0 bg-slate-50/60 z-10 whitespace-nowrap">Total Batch</TableCell>
                          <TableCell />
                          {footerCells("batch")}
                        </TableRow>
                        <TableRow className="bg-slate-50 font-medium border-b">
                          <TableCell className="sticky left-0 bg-slate-50 z-10 whitespace-nowrap">
                            <span className="inline-flex items-center gap-1">
                              Difference
                              {recon.balanced ? (
                                <CheckCircle2 className="h-3.5 w-3.5 text-emerald-600" />
                              ) : (
                                <AlertTriangle className="h-3.5 w-3.5 text-red-600" />
                              )}
                            </span>
                          </TableCell>
                          <TableCell />
                          {footerCells("diff")}
                        </TableRow>
                      </TableBody>
                    </Table>
                  </CardContent>
                </Card>

              </>
            )}
          </div>
        </main>
      </div>

      <Dialog open={methodOpen} onOpenChange={setMethodOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Choose an allocation method</DialogTitle>
            <DialogDescription>Pick how the batch totals are pre-filled across the included flocks. You can edit any value afterwards.</DialogDescription>
          </DialogHeader>
          <div className="grid gap-2">
            {METHODS.map((m) => (
              <button
                key={m.key}
                onClick={() => chooseMethod(m.key)}
                className="text-left rounded-lg border p-3 hover:border-primary hover:bg-slate-50 transition"
              >
                <div className="font-medium">{m.title}</div>
                <div className="text-sm text-muted-foreground">{m.desc}</div>
              </button>
            ))}
          </div>
        </DialogContent>
      </Dialog>

      <Dialog open={reconOpen} onOpenChange={setReconOpen}>
        <DialogContent className="max-w-2xl">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              Reconciliation details
              {recon.balanced ? (
                <Badge className="bg-emerald-100 text-emerald-800 gap-1">
                  <CheckCircle2 className="h-3.5 w-3.5" /> Reconciled
                </Badge>
              ) : (
                <Badge variant="destructive" className="gap-1">
                  <AlertTriangle className="h-3.5 w-3.5" /> Needs attention
                </Badge>
              )}
            </DialogTitle>
            <DialogDescription>
              {recon.balanced
                ? "Every allocatable field matches the batch totals. You can post this allocation."
                : `${mismatches.length} field${mismatches.length === 1 ? "" : "s"} do not match the batch totals. Resolve the differences below before posting.`}
            </DialogDescription>
          </DialogHeader>
          <div className="overflow-x-auto max-h-[55vh]">
            <Table className="min-w-[520px]">
              <TableHeader>
                <TableRow>
                  <TableHead>Field</TableHead>
                  <TableHead className="text-right">Allocated Total</TableHead>
                  <TableHead className="text-right">Total Batch</TableHead>
                  <TableHead className="text-right">Difference</TableHead>
                  <TableHead className="text-right">Status</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {recon.lines.map((l) => (
                  <TableRow key={l.key} className={l.balanced ? "" : "bg-red-50"}>
                    <TableCell>{l.label}</TableCell>
                    <TableCell className="text-right tabular-nums">{fmtRecon(l, l.allocated)}</TableCell>
                    <TableCell className="text-right tabular-nums">{fmtRecon(l, l.batchTotal)}</TableCell>
                    <TableCell className={cn("text-right font-medium tabular-nums", l.balanced ? "text-emerald-700" : "text-red-700")}>
                      {l.diff > 0 ? "+" : ""}
                      {fmtRecon(l, l.diff)}
                    </TableCell>
                    <TableCell className="text-right">
                      {l.balanced ? (
                        <span className="inline-flex items-center justify-end gap-1 text-emerald-700 text-xs">
                          <CheckCircle2 className="h-3.5 w-3.5" /> Reconciled
                        </span>
                      ) : l.money ? (
                        <span className="text-amber-600 text-xs">Info only</span>
                      ) : (
                        <span className="inline-flex items-center justify-end gap-1 text-red-700 text-xs">
                          <AlertTriangle className="h-3.5 w-3.5" /> Needs attention
                        </span>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
          <p className="text-xs text-muted-foreground">
            Egg and quantity fields must match exactly to post. Cost lines are informational — final costs are recomputed
            server-side when the flock records are created.
          </p>
        </DialogContent>
      </Dialog>
    </div>
  )
}
