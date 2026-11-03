"use client"

// Record Feed Usage (migration 389). Feed is picked from inventory, exactly as
// on a production record, and saving adds it as feed lines to each flock's
// production record for the day -- so stock goes down once, at FIFO / LIFO /
// HIFO cost, and the production record shows the feed.
//
// One flock, or a whole batch. A batch total must be split across its flocks
// (by birds, equally, or by hand) before it can be saved: the server stores and
// checks one line per flock and feed.

import { useCallback, useEffect, useMemo, useState } from "react"
import { Loader2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { cn } from "@/lib/utils"
import { useToast } from "@/hooks/use-toast"
import { FeedLines, computeFeedLines, emptyFeedLine, type FeedLineDraft } from "@/components/production/feed-lines"
import {
  listPoultryRawMaterialItems, listPoultryRawMaterialPurchases,
  type PoultryRawMaterialItem, type PoultryRawMaterialPurchase,
} from "@/lib/api/poultry-inventory"
import { isFinishedFeedCategory } from "@/lib/utils/feed-item-ledger"
import {
  getFeedUsageCandidates, postFeedUsage, InsufficientFeedError,
  type FeedRecordStatus, type FeedUsageCandidate,
} from "@/lib/api/feed-usage-entries"
import {
  batchesFrom, canFeed, recordStatusNote, splitBlocker, splitFeed, sumKg, type SplitBasis,
} from "@/lib/production/feed-usage"

const STATUS_LABEL: Record<FeedRecordStatus, string> = {
  Recorded: "production recorded",
  FeedOnly: "feed only so far",
  None: "no record yet",
  Duplicate: "duplicate records",
}
const STATUS_CLASS: Record<FeedRecordStatus, string> = {
  Recorded: "bg-emerald-50 text-emerald-700",
  FeedOnly: "bg-amber-50 text-amber-800",
  None: "bg-slate-100 text-slate-600",
  Duplicate: "bg-rose-50 text-rose-700",
}

export function StatusPill({ status }: { status: FeedRecordStatus }) {
  return <span className={cn("rounded-full px-2 py-0.5 text-[11px] font-medium", STATUS_CLASS[status])}>{STATUS_LABEL[status]}</span>
}

const kg = (n: number) => `${(Math.round(n * 1000) / 1000).toLocaleString()} kg`

export function RecordFeedUsageDialog({
  open, onOpenChange, today, onSaved,
}: {
  open: boolean
  onOpenChange: (v: boolean) => void
  /** The company's business date: the default, and the latest date allowed. */
  today: string
  onSaved: () => void
}) {
  const { toast } = useToast()
  const [date, setDate] = useState(today)
  const [scope, setScope] = useState<"Flock" | "Batch">("Flock")
  const [flockId, setFlockId] = useState("")
  const [batchId, setBatchId] = useState("")
  const [lines, setLines] = useState<FeedLineDraft[]>([emptyFeedLine()])
  const [basis, setBasis] = useState<SplitBasis>("Birds")
  // Manual split: flockId -> itemId -> text.
  const [manual, setManual] = useState<Record<number, Record<number, string>>>({})
  const [notes, setNotes] = useState("")
  const [candidates, setCandidates] = useState<FeedUsageCandidate[] | null>(null)
  const [loadingCands, setLoadingCands] = useState(false)
  const [rawItems, setRawItems] = useState<PoultryRawMaterialItem[]>([])
  const [purchases, setPurchases] = useState<PoultryRawMaterialPurchase[]>([])
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Fresh form each time it opens.
  useEffect(() => {
    if (!open) return
    setDate(today); setScope("Flock"); setFlockId(""); setBatchId("")
    setLines([emptyFeedLine()]); setBasis("Birds"); setManual({}); setNotes(""); setError(null)
    void (async () => {
      const [items, purch] = await Promise.all([
        listPoultryRawMaterialItems().catch(() => []),
        listPoultryRawMaterialPurchases().catch(() => []),
      ])
      setRawItems(Array.isArray(items) ? items : [])
      setPurchases(Array.isArray(purch) ? purch : [])
    })()
  }, [open, today])

  const loadCandidates = useCallback(async (d: string) => {
    setLoadingCands(true)
    try { setCandidates(await getFeedUsageCandidates(d)) }
    catch (e) { setCandidates([]); setError(e instanceof Error ? e.message : "Could not load the flocks.") }
    finally { setLoadingCands(false) }
  }, [])

  useEffect(() => { if (open && date) void loadCandidates(date) }, [open, date, loadCandidates])

  // Only finished feed can be picked -- an ingredient reaches a flock through a feed batch.
  const feedItems = useMemo(() => rawItems.filter((i) => isFinishedFeedCategory(i.category)), [rawItems])
  const computed = useMemo(() => computeFeedLines(lines, feedItems, purchases), [lines, feedItems, purchases])
  // One total per feed (two lines of the same feed are one draw).
  const feedTotals = useMemo(() => {
    const m = new Map<number, { itemId: number; name: string; qty: number }>()
    for (const r of computed.rows) {
      if (!r.item || !(r.qty > 0)) continue
      const id = r.item.poultryRawMaterialItemId
      const cur = m.get(id) ?? { itemId: id, name: r.item.itemName, qty: 0 }
      cur.qty = sumKg([cur.qty, r.qty])
      m.set(id, cur)
    }
    return [...m.values()]
  }, [computed.rows])

  const batches = useMemo(() => batchesFrom(candidates ?? []), [candidates])
  const flock = candidates?.find((c) => String(c.flockId) === flockId) ?? null
  const batch = batches.find((b) => String(b.batchId) === batchId) ?? null
  const batchFlocks = useMemo(() => (batch?.flocks ?? []).filter(canFeed), [batch])

  // Each feed's share per flock: computed for Birds / Equal, typed for Manual.
  const shares = useMemo(() => {
    const out: Record<number, Record<number, number>> = {}
    for (const f of feedTotals) {
      out[f.itemId] = basis === "Manual"
        ? Object.fromEntries(batchFlocks.map((b) => [b.flockId, parseFloat(manual[b.flockId]?.[f.itemId] ?? "") || 0]))
        : splitFeed(f.qty, batchFlocks.map((b) => ({ flockId: b.flockId, birds: b.birds })), basis)
    }
    return out
  }, [feedTotals, batchFlocks, basis, manual])

  // Switching to "By hand" starts from the bird split, so nobody types it all.
  const chooseBasis = (b: SplitBasis) => {
    if (b === "Manual" && basis !== "Manual") {
      const seed: Record<number, Record<number, string>> = {}
      for (const f of feedTotals) for (const bf of batchFlocks) {
        seed[bf.flockId] = { ...(seed[bf.flockId] ?? {}), [f.itemId]: String(shares[f.itemId]?.[bf.flockId] ?? 0) }
      }
      setManual(seed)
    }
    setBasis(b)
  }

  const blocker = useMemo((): string | null => {
    if (!date) return "Choose the date."
    if (date > today) return "You cannot record feed for a future date."
    if (scope === "Flock") {
      if (!flock) return "Choose the flock."
      if (!canFeed(flock)) return recordStatusNote(flock.recordStatus)
    } else {
      if (!batch) return "Choose the batch."
      if (batchFlocks.length === 0) return "No flock in this batch can be fed on this date."
    }
    if (feedTotals.length === 0) return "Add the feed used: pick a feed and enter how much."
    if (computed.firstShortfall) {
      const r = computed.firstShortfall
      return `Not enough ${r.item?.itemName} in stock: only ${r.preview.quantityCovered} available.`
    }
    if (scope === "Batch") {
      for (const f of feedTotals) {
        const b = splitBlocker(f.name, f.qty, batchFlocks.map((bf) => shares[f.itemId]?.[bf.flockId] ?? 0))
        if (b) return b
      }
    }
    return null
  }, [date, today, scope, flock, batch, batchFlocks, feedTotals, computed.firstShortfall, shares])

  const save = async () => {
    if (blocker) { setError(blocker); return }
    setSaving(true); setError(null)
    try {
      const payload = scope === "Flock"
        ? feedTotals.map((f) => ({ flockId: flock!.flockId, itemId: f.itemId, qty: f.qty, birds: flock!.birds }))
        : batchFlocks.flatMap((bf) => feedTotals.map((f) => ({
            flockId: bf.flockId, itemId: f.itemId, qty: shares[f.itemId]?.[bf.flockId] ?? 0, birds: bf.birds,
          }))).filter((l) => l.qty > 0)
      await postFeedUsage({
        businessDate: date, scope,
        batchId: scope === "Batch" ? batch!.batchId : null,
        splitBasis: scope === "Batch" ? basis : null,
        notes: notes.trim() || null,
        lines: payload,
      })
      const created = scope === "Flock"
        ? (flock!.recordStatus === "None" ? 1 : 0)
        : batchFlocks.filter((b) => b.recordStatus === "None").length
      toast({
        title: "Feed usage recorded",
        description: created > 0
          ? `Taken from stock. ${created} flock${created === 1 ? " has" : "s have"} no production for this day yet. Fill it in from Production Records.`
          : "Taken from stock and added to the production record.",
      })
      onOpenChange(false)
      onSaved()
    } catch (e) {
      const msg = e instanceof Error ? e.message : "Could not record the feed."
      setError(msg)
      toast({ title: e instanceof InsufficientFeedError ? "Not enough feed in stock" : "Feed was not recorded", description: msg, variant: "destructive" })
      if (e instanceof InsufficientFeedError) {
        const purch = await listPoultryRawMaterialPurchases().catch(() => null)
        if (Array.isArray(purch)) setPurchases(purch)
      }
    } finally {
      setSaving(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[92vh] max-w-3xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Record feed usage</DialogTitle>
          <DialogDescription>
            Pick the feed from your stock. It is taken out of inventory and added to the flock&apos;s production record for the day.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <div className="space-y-1">
              <Label htmlFor="fu-date">Date</Label>
              <Input id="fu-date" type="date" value={date} max={today} onChange={(e) => setDate(e.target.value)} />
            </div>
            <div className="space-y-1">
              <Label>Feed for</Label>
              <div className="flex gap-2" role="radiogroup" aria-label="Feed for">
                {(["Flock", "Batch"] as const).map((s) => (
                  <Button key={s} type="button" role="radio" aria-checked={scope === s}
                    variant={scope === s ? "default" : "outline"} className="flex-1"
                    onClick={() => setScope(s)}>
                    {s === "Flock" ? "One flock" : "A whole batch"}
                  </Button>
                ))}
              </div>
            </div>
          </div>

          {scope === "Flock" ? (
            <div className="space-y-1">
              <Label>Flock</Label>
              <Select value={flockId} onValueChange={setFlockId} disabled={loadingCands}>
                <SelectTrigger aria-label="Flock">
                  <SelectValue placeholder={loadingCands ? "Loading flocks…" : "Choose the flock"} />
                </SelectTrigger>
                <SelectContent>
                  {(candidates ?? []).map((c) => (
                    <SelectItem key={c.flockId} value={String(c.flockId)} disabled={!canFeed(c)}>
                      {c.flockName}{c.houseName ? ` · ${c.houseName}` : ""} · {STATUS_LABEL[c.recordStatus]}
                    </SelectItem>
                  ))}
                  {candidates?.length === 0 && <div className="px-2 py-1.5 text-xs text-slate-400">No active flocks on this date.</div>}
                </SelectContent>
              </Select>
              {flock && (
                <p className={cn("text-xs", flock.recordStatus === "None" || flock.recordStatus === "FeedOnly" ? "text-amber-800" : "text-slate-500")}>
                  {recordStatusNote(flock.recordStatus)}
                  {flock.feedLines ? ` Feed already on it: ${flock.feedLines}.` : ""}
                </p>
              )}
            </div>
          ) : (
            <div className="space-y-1">
              <Label>Batch</Label>
              <Select value={batchId} onValueChange={setBatchId} disabled={loadingCands}>
                <SelectTrigger aria-label="Batch">
                  <SelectValue placeholder={loadingCands ? "Loading batches…" : "Choose the batch"} />
                </SelectTrigger>
                <SelectContent>
                  {batches.map((b) => (
                    <SelectItem key={b.batchId} value={String(b.batchId)}>
                      {b.batchName} · {b.flocks.length} flock{b.flocks.length === 1 ? "" : "s"}
                    </SelectItem>
                  ))}
                  {batches.length === 0 && <div className="px-2 py-1.5 text-xs text-slate-400">No batches with active flocks on this date.</div>}
                </SelectContent>
              </Select>
            </div>
          )}

          <div className="space-y-2">
            <Label>Feed used</Label>
            <FeedLines
              lines={lines}
              rows={computed.rows}
              feedItems={feedItems}
              stockByItemId={computed.pendingStockByItemId}
              onAdd={() => setLines((l) => [...l, emptyFeedLine()])}
              onRemove={(i) => setLines((l) => (l.length === 1 ? [emptyFeedLine()] : l.filter((_, k) => k !== i)))}
              onChange={(i, patch) => setLines((l) => l.map((x, k) => (k === i ? { ...x, ...patch } : x)))}
              disabled={saving}
            />
            {feedTotals.length > 0 && (
              <p className="text-sm text-slate-600">
                Total: <span className="font-semibold">{kg(computed.totalConsumed)}</span> · cost{" "}
                <span className="font-semibold">{computed.totalCost.toFixed(2)}</span>
              </p>
            )}
          </div>

          {scope === "Batch" && batch && feedTotals.length > 0 && (
            <div className="space-y-2 rounded-lg border border-sky-200 bg-sky-50/50 p-3">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div>
                  <p className="text-sm font-semibold text-slate-900">Split across the flocks</p>
                  <p className="text-xs text-slate-600">Every kilogram must go to a flock before you can save.</p>
                </div>
                <div className="flex gap-1" role="radiogroup" aria-label="Split">
                  {([["Birds", "By birds"], ["Equal", "Equally"], ["Manual", "By hand"]] as const).map(([k, label]) => (
                    <Button key={k} type="button" size="sm" role="radio" aria-checked={basis === k}
                      variant={basis === k ? "default" : "outline"} onClick={() => chooseBasis(k)}>
                      {label}
                    </Button>
                  ))}
                </div>
              </div>
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="text-left text-xs uppercase tracking-wider text-slate-500">
                    <tr>
                      <th className="py-1 pr-3 font-medium">Flock</th>
                      <th className="py-1 pr-3 text-right font-medium">Birds</th>
                      {feedTotals.map((f) => <th key={f.itemId} className="py-1 pr-3 text-right font-medium">{f.name} (kg)</th>)}
                      <th className="py-1 font-medium">Record</th>
                    </tr>
                  </thead>
                  <tbody>
                    {batch.flocks.map((bf) => {
                      const ok = canFeed(bf)
                      return (
                        <tr key={bf.flockId} className={cn("border-t border-sky-100", !ok && "opacity-50")}>
                          <td className="py-1.5 pr-3 font-medium text-slate-900">{bf.flockName}</td>
                          <td className="py-1.5 pr-3 text-right tabular-nums">{bf.birds?.toLocaleString() ?? "—"}</td>
                          {feedTotals.map((f) => (
                            <td key={f.itemId} className="py-1.5 pr-3 text-right">
                              {!ok ? "—" : basis === "Manual" ? (
                                <Input type="number" step="0.001" min="0" className="ml-auto h-8 w-28 text-right"
                                  aria-label={`${bf.flockName} ${f.name} kg`}
                                  value={manual[bf.flockId]?.[f.itemId] ?? ""}
                                  onChange={(e) => setManual((m) => ({ ...m, [bf.flockId]: { ...(m[bf.flockId] ?? {}), [f.itemId]: e.target.value } }))} />
                              ) : (
                                <span className="tabular-nums">{(shares[f.itemId]?.[bf.flockId] ?? 0).toLocaleString()}</span>
                              )}
                            </td>
                          ))}
                          <td className="py-1.5"><StatusPill status={bf.recordStatus} /></td>
                        </tr>
                      )
                    })}
                    <tr className="border-t border-sky-200 font-semibold">
                      <td className="py-1.5 pr-3">Total</td>
                      <td />
                      {feedTotals.map((f) => {
                        const s = sumKg(batchFlocks.map((bf) => shares[f.itemId]?.[bf.flockId] ?? 0))
                        const off = Math.abs(s - f.qty) > 0.0005
                        return (
                          <td key={f.itemId} className={cn("py-1.5 pr-3 text-right tabular-nums", off && "text-rose-700")}>
                            {s.toLocaleString()} / {f.qty.toLocaleString()}
                          </td>
                        )
                      })}
                      <td />
                    </tr>
                  </tbody>
                </table>
              </div>
              {batchFlocks.some((b) => b.recordStatus === "None") && (
                <p className="text-xs text-amber-800">
                  Flocks with no record yet get a feed-only record. Their production for this day still shows as missing until it is filled in.
                </p>
              )}
            </div>
          )}

          <div className="space-y-1">
            <Label htmlFor="fu-notes">Notes (optional)</Label>
            <Input id="fu-notes" value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="e.g. Morning feeding" />
          </div>

          {(error || blocker) && (
            <p className={cn("text-sm", error ? "text-rose-700" : "text-slate-500")}>{error ?? blocker}</p>
          )}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancel</Button>
          <Button onClick={() => void save()} disabled={saving || !!blocker} className="bg-emerald-600 text-white hover:bg-emerald-700">
            {saving && <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />} Record feed usage
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
