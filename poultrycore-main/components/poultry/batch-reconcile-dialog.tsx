"use client"

// 413 / Issues 2 & 6: "What happened to the birds that never went into a flock?"
// One dialog for the Flock Purchases page, the Farm Setup batch tab (the same
// view) and the Batch Bird Reconciliation report. Posts through
// sppoultrybatchreconcile_post, which re-checks everything; the figures here
// come from previewBatchReconciliation, which follows the same rules.
//
// It never creates a sale, cash or revenue. A historical sale keeps its price,
// value and what was received; only an amount still owed can become ONE opening
// customer debt (369), which the customer later pays the ordinary way.

import { useCallback, useEffect, useMemo, useState } from "react"
import { CheckCircle2, ClipboardCheck, History, Info, Loader2, Plus, Trash2, Undo2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Checkbox } from "@/components/ui/checkbox"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { NumberInput } from "@/components/ui/number-input"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import {
  getBatchBirdReconciliationDetail, listReconciliationCustomers, postBatchReconciliation, reverseBatchReconciliation,
  type BatchReconciliationDetail,
} from "@/lib/api/bird-reconciliation"
import {
  KIND_LABELS, newRequestKey, previewBatchReconciliation, saleValue,
  type ReconciliationKind, type ReconciliationLine,
} from "@/lib/flocks/bird-reconciliation"

const KINDS: ReconciliationKind[] = ["Mortality", "Cull", "TransferOut", "StockCorrection", "Other"]
const money = (n: number | null | undefined) =>
  n == null ? "—" : Number(n).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
const num = (v: unknown) => Number((v as any) ?? 0) || 0

interface Row extends ReconciliationLine { id: string }

const newRow = (kind: ReconciliationKind, date: string): Row => ({
  id: newRequestKey("row"), kind, quantity: 0, date,
  ...(kind === "Sale" ? { pricePerBird: null, amountReceived: null, valueUnknown: false, createReceivable: false } : {}),
})

export function BatchReconcileDialog({ open, onOpenChange, batchId, batchLabel, costPerBird, source = "Batch", onPosted }: {
  open: boolean
  onOpenChange: (open: boolean) => void
  batchId: number | null
  batchLabel?: string
  /** The batch's purchase cost per bird, for the cost-basis note. */
  costPerBird?: number | null
  source?: string
  onPosted?: () => void
}) {
  const { toast } = useToast()
  const permissions = usePermissions()
  const today = new Date().toISOString().split("T")[0]
  const [detail, setDetail] = useState<BatchReconciliationDetail | null>(null)
  const [loading, setLoading] = useState(false)
  const [saving, setSaving] = useState(false)
  const [rows, setRows] = useState<Row[]>([])
  const [stillAlive, setStillAlive] = useState<string>("0")
  const [asOf, setAsOf] = useState(today)
  const [notes, setNotes] = useState("")
  const [requestKey, setRequestKey] = useState(() => newRequestKey("br"))
  const [customers, setCustomers] = useState<{ customerId: number; name: string }[]>([])
  // A fully accounted batch opens on a summary; the form appears on request.
  const [showForm, setShowForm] = useState(false)

  const load = useCallback(async () => {
    if (!batchId) return
    setLoading(true)
    try {
      setDetail(await getBatchBirdReconciliationDetail(batchId))
    } catch (e: any) {
      toast({ title: "Could not load the batch", description: e?.message, variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }, [batchId, toast])

  useEffect(() => {
    if (!open) return
    setRows([]); setShowForm(false); setStillAlive("0"); setAsOf(today); setNotes(""); setRequestKey(newRequestKey("br"))
    load()
    listReconciliationCustomers().then(setCustomers).catch(() => setCustomers([]))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, batchId])

  const s = (detail?.summary ?? {}) as Record<string, any>
  const pool = num(s.unallocatedpool)
  const preview = useMemo(() => previewBatchReconciliation(pool, rows, Number(stillAlive) || 0), [pool, rows, stillAlive])
  const openingFlocks = (detail?.flocks ?? []).filter((f) => f.hasOpeningPosition && f.historicalSold > 0)
  const valuedByFlock = (flockId: number) =>
    (detail?.historicalSales ?? []).filter((h) => h.status === "Posted" && h.flockId === flockId).reduce((a, h) => a + h.birds, 0)

  const patch = (id: string, p: Partial<Row>) => setRows((rs) => rs.map((r) => (r.id === id ? { ...r, ...p } : r)))

  async function save() {
    if (!batchId) return
    if (preview.status === "Invalid") {
      toast({ title: "Check the lines", description: preview.problems[0], variant: "destructive" })
      return
    }
    setSaving(true)
    try {
      const res = await postBatchReconciliation({
        batchId, asOfDate: asOf, stillUnallocatedLive: Number(stillAlive) || 0, notes: notes || null, source, requestKey,
        lines: rows.filter((r) => num(r.quantity) > 0).map(({ id: _id, ...l }) => ({
          ...l, quantity: Math.trunc(num(l.quantity)),
          pricePerBird: l.kind === "Sale" && !l.valueUnknown ? num(l.pricePerBird) : null,
          amountReceived: l.kind === "Sale" && !l.valueUnknown ? (l.amountReceived == null || String(l.amountReceived) === "" ? saleValue(l).total : num(l.amountReceived)) : null,
        })),
      })
      toast({
        title: res.repeated ? "Already recorded" : res.status === "Reconciled" ? "Batch fully accounted for" : "Saved — some birds still unexplained",
        description: res.repeated ? `${res.reconciliationNo} was saved earlier; nothing was posted twice.`
          : `${res.reconciliationNo}: ${(res.removedBirds ?? 0).toLocaleString()} birds explained${(res.unexplainedBirds ?? 0) > 0 ? `, ${(res.unexplainedBirds ?? 0).toLocaleString()} still to explain` : ""}. No cash, sale or revenue was posted.`,
      })
      onPosted?.()
      setRequestKey(newRequestKey("br"))
      setRows([])
      await load()
    } catch (e: any) {
      toast({ title: "Not saved", description: e?.message, variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  async function reverse(id: number, no: string) {
    const reason = window.prompt(`Why is ${no} being reversed?`)
    if (!reason?.trim()) return
    try {
      await reverseBatchReconciliation(id, reason.trim())
      toast({ title: `${no} reversed`, description: "Its birds are back with the batch and any debt it created is reversed." })
      onPosted?.()
      await load()
    } catch (e: any) {
      toast({ title: "Not reversed", description: e?.message, variant: "destructive" })
    }
  }

  // What the batch's birds became, as one bar. Every bird of the batch is in
  // exactly one of these, so the segments add up to the purchase.
  const otherRemovals = Math.max(0, num(s.batchculled) + num(s.batchtransferred) + num(s.batchotherremovals) - num(s.batchadditions))
  const unexplainedNow = num(s.unexplained)
  const segments = [
    { key: "flocks", label: "In flocks", value: num(s.originallyallocated), color: "bg-emerald-500" },
    { key: "sold", label: "Sold before placing", value: num(s.batchsold), color: "bg-orange-400" },
    { key: "died", label: "Died before placing", value: num(s.batchmortality), color: "bg-rose-400" },
    { key: "other", label: "Culled / transferred / other", value: otherRemovals, color: "bg-slate-400" },
    { key: "waiting", label: "Waiting to be placed", value: num(s.unallocatedlive), color: "bg-indigo-400" },
    { key: "unexplained", label: unexplainedNow < 0 ? "Over-allocated" : "Unexplained", value: Math.abs(unexplainedNow), color: unexplainedNow < 0 ? "bg-red-500" : "bg-amber-400" },
  ].filter((g) => g.value > 0)
  const barTotal = Math.max(num(s.originalbirds), segments.reduce((a, g) => a + g.value, 0), 1)
  const statusKey: string = s.status ?? "FullyAccountedFor"
  const allAccounted = pool === 0 && statusKey === "FullyAccountedFor"
  const formVisible = !allAccounted || showForm || rows.length > 0
  const nothingToSave = pool === 0 && rows.filter((r) => num(r.quantity) > 0).length === 0

  const addLine = (kind: ReconciliationKind) => { setShowForm(true); setRows((r) => [...r, newRow(kind, asOf)]) }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="flex w-[95vw] flex-col gap-0 overflow-hidden p-0 sm:max-w-4xl">
        <DialogHeader className="border-b border-slate-200 px-6 pb-4 pt-5">
          <div className="flex items-center gap-3 pr-6">
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-amber-50 text-amber-600">
              <ClipboardCheck className="h-5 w-5" />
            </div>
            <div className="min-w-0 flex-1">
              <DialogTitle className="flex flex-wrap items-center gap-2 text-lg">
                Reconcile Birds
                {detail && <StatusBadge status={statusKey} />}
              </DialogTitle>
              <DialogDescription className="mt-1 truncate">
                {batchLabel ? <span className="font-medium text-slate-700">{batchLabel}</span> : null}
                {batchLabel ? " · " : ""}Account for the birds that never went into a flock.
              </DialogDescription>
            </div>
          </div>
        </DialogHeader>

        {loading || !detail ? (
          <div className="flex justify-center py-16"><Loader2 className="h-6 w-6 animate-spin text-slate-400" /></div>
        ) : (
          <>
            <div className="flex-1 space-y-5 overflow-y-auto px-6 py-5">
              {/* ---- Where the birds went ---- */}
              <section className="rounded-xl border border-slate-200 bg-white p-4">
                <div className="flex flex-wrap items-baseline justify-between gap-2">
                  <h3 className="text-sm font-semibold text-slate-800">Where the batch&apos;s birds went</h3>
                  <span className="text-sm text-slate-500">
                    <span className="font-semibold tabular-nums text-slate-900">{num(s.originalbirds).toLocaleString()}</span> birds bought
                  </span>
                </div>
                <div className="mt-3 flex h-3 w-full gap-0.5 overflow-hidden rounded-full bg-slate-100">
                  {segments.map((g) => (
                    <div key={g.key} className={g.color} style={{ width: `${(g.value / barTotal) * 100}%` }} title={`${g.label}: ${g.value.toLocaleString()}`} />
                  ))}
                </div>
                <div className="mt-3 flex flex-wrap gap-x-6 gap-y-2">
                  {segments.map((g) => (
                    <div key={g.key} className="flex items-center gap-2 text-sm">
                      <span className={`h-2.5 w-2.5 shrink-0 rounded-full ${g.color}`} />
                      <span className="text-slate-600">{g.label}</span>
                      <span className="font-semibold tabular-nums text-slate-900">{g.value.toLocaleString()}</span>
                    </div>
                  ))}
                </div>
              </section>

              {!formVisible && (
                <section className="flex flex-col items-center gap-3 rounded-xl border border-emerald-200 bg-emerald-50/60 px-4 py-6 text-center">
                  <CheckCircle2 className="h-8 w-8 text-emerald-600" />
                  <div>
                    <p className="font-semibold text-emerald-900">Every bird in this batch is accounted for</p>
                    <p className="mt-0.5 text-sm text-emerald-800/80">There are no birds outside a flock left to explain.</p>
                  </div>
                  <Button size="sm" variant="outline" className="bg-white" onClick={() => setShowForm(true)}>
                    <Plus className="mr-1 h-4 w-4" />Record a correction or value a historical sale
                  </Button>
                </section>
              )}

              {formVisible && (
                <>
                  {/* ---- Lines ---- */}
                  <section className="rounded-xl border border-slate-200">
                    <div className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-200 bg-slate-50 px-4 py-3">
                      <div>
                        <h3 className="text-sm font-semibold text-slate-800">What happened to them?</h3>
                        <p className="text-xs text-slate-500">
                          {pool > 0
                            ? <><span className="font-semibold text-indigo-700">{pool.toLocaleString()}</span> birds are not in a flock. Add a line for each historical sale or loss.</>
                            : "Add a line for each historical sale or correction."}
                        </p>
                      </div>
                      <div className="flex flex-wrap gap-2">
                        <Button size="sm" variant="outline" className="bg-white" onClick={() => addLine("Sale")}><Plus className="mr-1 h-4 w-4" />Historical sale</Button>
                        <Button size="sm" variant="outline" className="bg-white" onClick={() => addLine("Mortality")}><Plus className="mr-1 h-4 w-4" />Loss / other</Button>
                      </div>
                    </div>
                    <div className="space-y-3 p-4">
                      {rows.length === 0 && (
                        <div className="rounded-lg border border-dashed border-slate-300 px-4 py-6 text-center text-sm text-slate-500">
                          No lines yet. Use <b>+ Historical sale</b> for birds that were sold, or <b>+ Loss / other</b> for birds that died, were culled or moved.
                        </div>
                      )}
                      {rows.map((r, i) => {
                        const v = r.kind === "Sale" ? saleValue(r) : null
                        return (
                          <div key={r.id} className="rounded-lg border border-slate-200 bg-white">
                            <div className="flex items-center justify-between gap-2 border-b border-slate-100 px-3 py-2">
                              <span className="flex items-center gap-2 text-sm font-medium text-slate-800">
                                <span className="flex h-5 w-5 items-center justify-center rounded-full bg-slate-100 text-[11px] font-semibold text-slate-600">{i + 1}</span>
                                {r.kind === "Sale" ? "Historical sale" : "Loss / other"}
                              </span>
                              <Button size="icon" variant="ghost" className="h-7 w-7 text-slate-400 hover:bg-red-50 hover:text-red-600" title="Remove line"
                                onClick={() => setRows((rs) => rs.filter((x) => x.id !== r.id))}>
                                <Trash2 className="h-4 w-4" />
                              </Button>
                            </div>
                            <div className="grid grid-cols-1 gap-3 p-3 sm:grid-cols-2 lg:grid-cols-4">
                              {r.kind === "Sale" ? (
                                <Field label="Sold from">
                                  <select className={selectCls} value={r.flockId ?? ""}
                                    onChange={(e) => patch(r.id, { flockId: e.target.value ? Number(e.target.value) : null })}>
                                    <option value="">Not placed in a flock</option>
                                    {openingFlocks.map((f) => (
                                      <option key={f.flockId} value={f.flockId}>
                                        {f.flockName} ({f.historicalSold.toLocaleString()} sold, {valuedByFlock(f.flockId).toLocaleString()} valued)
                                      </option>
                                    ))}
                                  </select>
                                </Field>
                              ) : (
                                <Field label="What happened">
                                  <select className={selectCls} value={r.kind}
                                    onChange={(e) => patch(r.id, { kind: e.target.value as ReconciliationKind })}>
                                    {KINDS.map((k) => <option key={k} value={k}>{KIND_LABELS[k]}</option>)}
                                  </select>
                                </Field>
                              )}
                              <Field label="Birds">
                                <NumberInput min="0" value={r.quantity || ""} onChange={(e) => patch(r.id, { quantity: Number(e.target.value) || 0 })} />
                              </Field>
                              <Field label="Date">
                                <Input type="date" max={today} value={r.date ?? ""} onChange={(e) => patch(r.id, { date: e.target.value })} />
                              </Field>
                              {r.kind === "StockCorrection" && (
                                <Field label="Direction">
                                  <select className={selectCls} value={r.direction ?? "Decrease"}
                                    onChange={(e) => patch(r.id, { direction: e.target.value as "Decrease" | "Increase" })}>
                                    <option value="Decrease">Fewer birds than recorded</option>
                                    <option value="Increase">More birds than recorded</option>
                                  </select>
                                </Field>
                              )}
                              {r.kind === "Sale" && (
                                <Field label="Price per bird">
                                  <NumberInput min="0" step="0.01" disabled={r.valueUnknown} value={r.pricePerBird ?? ""}
                                    onChange={(e) => patch(r.id, { pricePerBird: e.target.value === "" ? null : Number(e.target.value) })} />
                                </Field>
                              )}
                              <Field label={r.kind === "Other" ? "Note *" : "Note"} className={r.kind === "Sale" || r.kind === "StockCorrection" ? "sm:col-span-2 lg:col-span-4" : ""}>
                                <Input value={r.note ?? ""} placeholder={r.kind === "Other" ? "Say what happened" : "Optional"} onChange={(e) => patch(r.id, { note: e.target.value })} />
                              </Field>
                            </div>

                            {r.kind === "Sale" && v && (
                              <div className="space-y-3 border-t border-slate-100 bg-slate-50/70 p-3">
                                <div className="flex flex-wrap items-center justify-between gap-3">
                                  <label className="flex items-center gap-2 text-sm text-slate-700">
                                    <Checkbox checked={!!r.valueUnknown} onCheckedChange={(c) => patch(r.id, { valueUnknown: c === true, pricePerBird: null, amountReceived: null, createReceivable: false })} />
                                    I don&apos;t know the value. Record the birds only
                                  </label>
                                  {!r.valueUnknown && (
                                    <div className="flex gap-5 text-sm">
                                      <div><span className="text-slate-500">Value </span><span className="font-semibold tabular-nums">{money(v.total)}</span></div>
                                      <div><span className="text-slate-500">Owed </span><span className={`font-semibold tabular-nums ${v.owed > 0 ? "text-amber-700" : ""}`}>{money(v.owed)}</span></div>
                                    </div>
                                  )}
                                </div>
                                {!r.valueUnknown && (
                                  <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
                                    <Field label="Already received">
                                      <NumberInput min="0" step="0.01" value={r.amountReceived ?? ""} placeholder={v.total != null ? String(v.total) : ""}
                                        onChange={(e) => patch(r.id, { amountReceived: e.target.value === "" ? null : Number(e.target.value) })} />
                                    </Field>
                                    <Field label={`Customer${r.createReceivable ? " *" : ""}`}>
                                      <select className={selectCls} value={r.customerId ?? ""}
                                        onChange={(e) => patch(r.id, { customerId: e.target.value ? Number(e.target.value) : null })}>
                                        <option value="">—</option>
                                        {customers.map((c) => <option key={c.customerId} value={c.customerId}>{c.name}</option>)}
                                      </select>
                                    </Field>
                                    <Field label="Reference">
                                      <Input value={r.reference ?? ""} placeholder="Optional" onChange={(e) => patch(r.id, { reference: e.target.value })} />
                                    </Field>
                                    {v.owed > 0 && (
                                      <label className="flex items-center gap-2 text-sm text-slate-700 sm:col-span-3">
                                        <Checkbox checked={!!r.createReceivable} onCheckedChange={(c) => patch(r.id, { createReceivable: c === true })} />
                                        Record the {money(v.owed)} still owed as an opening customer debt
                                      </label>
                                    )}
                                  </div>
                                )}
                                {v.problem && num(r.quantity) > 0 && <p className="text-xs text-red-600">{v.problem}</p>}
                              </div>
                            )}
                          </div>
                        )
                      })}
                    </div>
                  </section>

                  {/* ---- Remaining + result ---- */}
                  <section className="grid grid-cols-1 gap-4 md:grid-cols-5">
                    <div className="space-y-3 md:col-span-3">
                      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                        <Field label="Still alive, not in a flock *" hint="Birds waiting to be placed.">
                          <NumberInput min="0" value={stillAlive} onChange={(e) => setStillAlive(e.target.value)} />
                        </Field>
                        <Field label="As of date">
                          <Input type="date" max={today} value={asOf} onChange={(e) => setAsOf(e.target.value)} />
                        </Field>
                      </div>
                      <Field label="Notes">
                        <Input value={notes} placeholder="Optional" onChange={(e) => setNotes(e.target.value)} />
                      </Field>
                    </div>

                    <div className="rounded-xl border border-slate-200 bg-slate-50 p-4 text-sm md:col-span-2">
                      <div className="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-500">After saving</div>
                      <Line label="Not in a flock now" value={preview.poolBefore} />
                      <Line label="Explained by the lines" value={-preview.removed} />
                      <Line label="Still alive" value={-preview.stillAlive} />
                      <div className="my-2 border-t border-slate-200" />
                      <Line label="Unexplained" value={preview.unexplained} strong
                        tone={preview.unexplained === 0 ? "text-emerald-700" : "text-amber-700"} />
                      {preview.saleBirds > 0 && (
                        <>
                          <div className="my-2 border-t border-slate-200" />
                          <Line label="Historical sales (birds)" value={preview.saleBirds} />
                          <Line label="Historical sales value" text={money(preview.saleValue)} />
                          <Line label="Received" text={money(preview.received)} />
                          <Line label="Still owed" text={money(preview.owed)} tone={preview.owed > 0 ? "text-amber-700" : ""} />
                          {preview.receivablesToCreate > 0 && <Line label="Customer debts to create" value={preview.receivablesToCreate} />}
                        </>
                      )}
                      {preview.problems.map((p) => <p key={p} className="mt-2 text-xs text-red-600">{p}</p>)}
                    </div>
                  </section>

                  <p className="flex items-start gap-2 text-xs text-slate-500">
                    <Info className="mt-0.5 h-3.5 w-3.5 shrink-0" />
                    <span>
                      This records history only: no cash, sale or revenue is posted.
                      {costPerBird != null && costPerBird > 0 && <> Flocks carry the bird cost ({money(costPerBird)} × birds placed); birds sold or lost before placing are charged to no flock.</>}
                    </span>
                  </p>
                </>
              )}

              {/* ---- History ---- */}
              {(detail.reconciliations ?? []).length > 0 && (
                <section>
                  <h3 className="mb-2 flex items-center gap-2 text-sm font-semibold text-slate-800">
                    <History className="h-4 w-4 text-slate-400" />Earlier reconciliations
                  </h3>
                  <div className="divide-y divide-slate-100 rounded-xl border border-slate-200">
                    {detail.reconciliations.map((r) => {
                      const reversed = r.status === "Reversed"
                      return (
                        <div key={r.reconciliationid} className={`flex flex-wrap items-center gap-x-4 gap-y-2 px-4 py-3 text-sm ${reversed ? "opacity-60" : ""}`}>
                          <div className="min-w-0 flex-1">
                            <div className="flex flex-wrap items-center gap-2">
                              <span className={`font-semibold text-slate-900 ${reversed ? "line-through" : ""}`}>{r.reconciliationno}</span>
                              <span className={`rounded-full px-2 py-0.5 text-[11px] font-medium ${reversed ? "bg-slate-100 text-slate-600" : r.status === "Reconciled" ? "bg-emerald-50 text-emerald-700" : "bg-amber-50 text-amber-700"}`}>{r.status}</span>
                              <span className="text-slate-500">{formatDay(r.asofdate)}{r.source ? ` · ${r.source}` : ""}</span>
                            </div>
                            <div className="mt-1 flex flex-wrap gap-x-4 text-xs text-slate-600">
                              <span><b className="tabular-nums text-slate-800">{r.removedbirds.toLocaleString()}</b> explained</span>
                              <span><b className="tabular-nums text-slate-800">{r.stillunallocatedlive.toLocaleString()}</b> still alive</span>
                              <span><b className={`tabular-nums ${r.unexplainedbirds > 0 ? "text-amber-700" : "text-slate-800"}`}>{r.unexplainedbirds.toLocaleString()}</b> unexplained</span>
                            </div>
                          </div>
                          {!reversed && permissions.isAdmin && (
                            <Button size="sm" variant="outline" className="h-8" onClick={() => reverse(r.reconciliationid, r.reconciliationno)}>
                              <Undo2 className="mr-1 h-4 w-4" />Reverse
                            </Button>
                          )}
                        </div>
                      )
                    })}
                  </div>
                </section>
              )}
            </div>

            <div className="flex items-center justify-end gap-2 border-t border-slate-200 bg-white px-6 py-3">
              <Button variant="outline" onClick={() => onOpenChange(false)}>Close</Button>
              {formVisible && (
                <Button onClick={save} disabled={saving || nothingToSave || preview.status === "Invalid"}
                  className={preview.status === "Reconciled" ? "bg-emerald-600 hover:bg-emerald-700" : ""}>
                  {saving ? <Loader2 className="h-4 w-4 animate-spin" />
                    : preview.status === "Reconciled" ? <><CheckCircle2 className="mr-1 h-4 w-4" />Save — all accounted for</>
                    : "Save (some still unexplained)"}
                </Button>
              )}
            </div>
          </>
        )}
      </DialogContent>
    </Dialog>
  )
}

const selectCls = "h-10 w-full rounded-md border border-slate-200 bg-white px-2 text-sm focus:outline-none focus:ring-2 focus:ring-slate-300"

/** 0 instead of "-0", and a real minus sign otherwise. */
const fmtCount = (n: number) => (n === 0 ? "0" : n < 0 ? `−${Math.abs(n).toLocaleString()}` : n.toLocaleString())

function formatDay(d: unknown) {
  const t = new Date(String(d).slice(0, 10) + "T00:00:00")
  return isNaN(t.getTime()) ? String(d).slice(0, 10) : t.toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" })
}

function Field({ label, hint, className = "", children }: { label: string; hint?: string; className?: string; children: React.ReactNode }) {
  return (
    <div className={`space-y-1 ${className}`}>
      <Label className="text-xs font-medium text-slate-600">{label}</Label>
      {children}
      {hint && <p className="text-xs text-slate-500">{hint}</p>}
    </div>
  )
}

function StatusBadge({ status }: { status: string }) {
  const map: Record<string, [string, string]> = {
    FullyAccountedFor: ["All accounted for", "bg-emerald-50 text-emerald-700 border-emerald-200"],
    NeedsReconciliation: ["Needs reconciliation", "bg-amber-50 text-amber-700 border-amber-200"],
    OverAllocated: ["Over-allocated", "bg-red-50 text-red-700 border-red-200"],
  }
  const [text, cls] = map[status] ?? [status, "bg-slate-50 text-slate-700 border-slate-200"]
  return <span className={`rounded-full border px-2 py-0.5 text-xs font-medium ${cls}`}>{text}</span>
}

function Line({ label, value, text, strong, tone }: { label: string; value?: number; text?: string; strong?: boolean; tone?: string }) {
  return (
    <div className="flex justify-between gap-3">
      <span className="text-slate-600">{label}</span>
      <span className={`tabular-nums ${strong ? "font-semibold" : ""} ${tone ?? ""}`}>{text ?? fmtCount(value ?? 0)}</span>
    </div>
  )
}
