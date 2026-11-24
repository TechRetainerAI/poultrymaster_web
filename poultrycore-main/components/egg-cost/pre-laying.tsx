"use client"

import { useState } from "react"
import { Egg, Pencil, Plus, Undo2 } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Checkbox } from "@/components/ui/checkbox"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Textarea } from "@/components/ui/textarea"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { useToast } from "@/hooks/use-toast"
import { addHistoricalCost, reverseHistoricalCost, saveFlockAssumptions, type HistoricalCostInput } from "@/lib/api/egg-cost"
import { expectedLifetimeEggs, type EggCostAnalysis, type EggCostFacts, type FactFlock } from "@/lib/egg-cost/engine"
import { Section, num, useMoney } from "./bits"

const REMOVE_REASONS = [
  { value: "Entered in error", label: "Entered in error" },
  { value: "Wrong amount", label: "Wrong amount" },
  { value: "Cost is now recorded in VisibilityCore", label: "Cost is now recorded in VisibilityCore" },
  { value: "Other", label: "Other" },
] as const

const STATUS: Record<string, { label: string; tone: string }> = {
  Applied: { label: "Applied", tone: "border-emerald-200 bg-emerald-50 text-emerald-800" },
  NoAssumption: { label: "Needs expected production", tone: "border-amber-200 bg-amber-50 text-amber-900" },
  NoCost: { label: "No pre-laying cost known", tone: "border-slate-200 bg-slate-50 text-slate-700" },
  Excluded: { label: "Excluded in settings", tone: "border-slate-200 bg-slate-50 text-slate-700" },
  NotLaying: { label: "Not laying yet", tone: "border-sky-200 bg-sky-50 text-sky-800" },
}

export function PreLayingPanel({ facts, a, canManage, onChanged }: {
  facts: EggCostFacts; a: EggCostAnalysis; canManage: boolean; onChanged: () => void
}) {
  const { money, perEgg } = useMoney()
  const [edit, setEdit] = useState<FactFlock | null>(null)
  const [addFor, setAddFor] = useState<FactFlock | null>(null)
  const rows = a.flocks.filter((r) => r.inScope && (r.flockType ?? "").toLowerCase() !== "broiler")
  const { toast } = useToast()

  const [removeId, setRemoveId] = useState<number | null>(null)
  async function reverse(reason: string) {
    if (removeId == null) return
    const r = await reverseHistoricalCost(removeId, reason.trim())
    if (!r.success) { toast({ title: "Not removed", description: r.message, variant: "destructive" }); return }
    setRemoveId(null)
    toast({ title: "Historical cost removed" })
    onChanged()
  }

  return (
    <Section title="Pre-laying cost" icon={Egg}
      description="What it cost to bring each flock to lay -- birds, rearing feed and medication, plus historical entries -- spread over its expected lifetime saleable eggs. Management analysis only: nothing is re-expensed or capitalised.">
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Flock</TableHead><TableHead>First egg</TableHead>
              <TableHead className="text-right">Birds</TableHead><TableHead className="text-right">Rearing feed + med</TableHead>
              <TableHead className="text-right">Historical</TableHead><TableHead className="text-right">Pool</TableHead>
              <TableHead className="text-right">Expected lifetime eggs</TableHead><TableHead className="text-right">Per egg</TableHead>
              <TableHead className="text-right">Per crate</TableHead><TableHead className="text-right">This period</TableHead>
              <TableHead>Status</TableHead>{canManage && <TableHead />}
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((r) => {
              const f = facts.flocks.find((x) => x.flockId === r.flockId)!
              const st = STATUS[r.preLay.status]
              return (
                <TableRow key={r.flockId}>
                  <TableCell className="font-medium">{r.name}<span className="block text-[11px] text-slate-500">{r.batchCode ?? ""}</span></TableCell>
                  <TableCell className="whitespace-nowrap text-sm">{f.firstEggDate?.slice(0, 10) ?? "—"}</TableCell>
                  <TableCell className="text-right tabular-nums" title={f.birdCostBasis ?? undefined}>{money(r.preLay.birdCost || null)}</TableCell>
                  <TableCell className="text-right tabular-nums">
                    {money(r.preLay.rearingFeed + r.preLay.rearingMedication || null)}
                    {f.preLayFeedWithoutCost > 0 && <span className="block text-[11px] text-amber-700">{f.preLayFeedWithoutCost} record(s) without feed cost</span>}
                  </TableCell>
                  <TableCell className="text-right tabular-nums">
                    {money(r.preLay.historical || null)}
                    {f.historicalCostHasEstimate && <span className="block text-[11px] text-violet-700">includes estimates</span>}
                  </TableCell>
                  <TableCell className="text-right font-medium tabular-nums">{money(r.preLay.pool || null)}</TableCell>
                  <TableCell className="text-right tabular-nums" title={r.preLay.expectedBasis ?? undefined}>{num(r.preLay.expectedLifetimeEggs)}</TableCell>
                  <TableCell className="text-right tabular-nums">{perEgg(r.preLay.ratePerEgg)}</TableCell>
                  <TableCell className="text-right tabular-nums">{money(r.preLay.ratePerEgg == null ? null : r.preLay.ratePerEgg * a.eggsPerCrate)}</TableCell>
                  <TableCell className="text-right tabular-nums">{money(r.preLay.allocated || null)}</TableCell>
                  <TableCell><Badge variant="outline" className={`text-[10px] ${st.tone}`}>{st.label}</Badge></TableCell>
                  {canManage && (
                    <TableCell className="whitespace-nowrap">
                      <Button size="sm" variant="ghost" title="Lifetime assumptions" onClick={() => setEdit(f)}><Pencil className="h-3.5 w-3.5" /></Button>
                      <Button size="sm" variant="ghost" title="Add a historical cost" onClick={() => setAddFor(f)}><Plus className="h-3.5 w-3.5" /></Button>
                    </TableCell>
                  )}
                </TableRow>
              )
            })}
          </TableBody>
        </Table>
      </div>

      {facts.historicalCosts.length > 0 && (
        <div className="mt-4">
          <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-slate-500">Historical cost entries (before VisibilityCore)</p>
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow><TableHead>For</TableHead><TableHead>Category</TableHead><TableHead className="text-right">Amount</TableHead>
                  <TableHead>Period</TableHead><TableHead>Reason / reference</TableHead><TableHead>Kind</TableHead><TableHead>Entered</TableHead>{canManage && <TableHead />}</TableRow>
              </TableHeader>
              <TableBody>
                {facts.historicalCosts.map((h) => (
                  <TableRow key={h.historicalCostId}>
                    <TableCell>{h.flockId ? facts.flocks.find((f) => f.flockId === h.flockId)?.name ?? `Flock #${h.flockId}` : `Batch #${h.batchId}`}</TableCell>
                    <TableCell>{h.category}</TableCell>
                    <TableCell className="text-right tabular-nums">{money(h.amount)}</TableCell>
                    <TableCell className="whitespace-nowrap text-xs">{[h.periodFrom?.slice(0, 10), h.periodTo?.slice(0, 10)].filter(Boolean).join(" → ") || "—"}</TableCell>
                    <TableCell className="text-sm">{h.reason}{h.reference && <span className="block text-[11px] text-slate-500">{h.reference}</span>}</TableCell>
                    <TableCell><Badge variant="outline" className="text-[10px]">{h.isEstimate ? "Estimate" : "Actual"}</Badge></TableCell>
                    <TableCell className="text-xs text-slate-600">{h.enteredBy ?? ""}<span className="block">{h.enteredAt?.slice(0, 10)}</span></TableCell>
                    {canManage && <TableCell><Button size="sm" variant="ghost" title="Remove" onClick={() => setRemoveId(h.historicalCostId)}><Undo2 className="h-3.5 w-3.5" /></Button></TableCell>}
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </div>
      )}
      {!canManage && <p className="mt-2 text-xs text-slate-500">Only an owner or admin can change lifetime assumptions or add historical costs.</p>}

      <PromptDialog
        open={removeId != null}
        onOpenChange={(o) => { if (!o) setRemoveId(null) }}
        title="Remove historical cost"
        description="It stops counting in the pre-laying analysis. The entry stays in the change history."
        label="Reason"
        options={REMOVE_REASONS}
        confirmLabel="Remove"
        confirmVariant="destructive"
        onSubmit={reverse}
      />
      {edit && <AssumptionDialog flock={edit} onClose={() => setEdit(null)} onSaved={() => { setEdit(null); onChanged() }} />}
      {addFor && <HistoricalDialog flock={addFor} onClose={() => setAddFor(null)} onSaved={() => { setAddFor(null); onChanged() }} />}
    </Section>
  )
}

function AssumptionDialog({ flock, onClose, onSaved }: { flock: FactFlock; onClose: () => void; onSaved: () => void }) {
  const a = flock.assumptions
  const [eggs, setEggs] = useState(a?.expectedLifetimeSaleableEggs?.toString() ?? "")
  const [weeks, setWeeks] = useState(a?.expectedLayingWeeks?.toString() ?? "")
  const [rate, setRate] = useState(a?.expectedLayRatePct?.toString() ?? "")
  const [mort, setMort] = useState(a?.expectedMortalityPct?.toString() ?? "")
  const [resid, setResid] = useState(a?.expectedResidualValue?.toString() ?? "")
  const [useResid, setUseResid] = useState(!!a?.useResidualValue)
  const [notes, setNotes] = useState(a?.notes ?? "")
  const [saving, setSaving] = useState(false)
  const { toast } = useToast()
  const derived = expectedLifetimeEggs({
    originallyPlaced: flock.originallyPlaced,
    assumptions: { expectedLifetimeSaleableEggs: null, expectedLayingWeeks: weeks ? +weeks : null, expectedLayRatePct: rate ? +rate : null,
      expectedMortalityPct: mort ? +mort : null, expectedResidualValue: null, useResidualValue: false, notes: null },
  })

  async function save() {
    setSaving(true)
    const r = await saveFlockAssumptions(flock.flockId, {
      expectedLifetimeSaleableEggs: eggs ? +eggs : null, expectedLayingWeeks: weeks ? +weeks : null,
      expectedLayRatePct: rate ? +rate : null, expectedMortalityPct: mort ? +mort : null,
      expectedResidualValue: resid ? +resid : null, useResidualValue: useResid, notes: notes || null,
    })
    setSaving(false)
    if (!r.success) { toast({ title: "Not saved", description: r.message, variant: "destructive" }); return }
    toast({ title: "Assumptions saved", description: "The analysis is recalculated with them." })
    onSaved()
  }

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Lifetime assumptions — {flock.name}</DialogTitle>
          <DialogDescription>
            Pre-laying cost is spread over the eggs you expect this flock to lay in its life. State the number, or the laying weeks and lay rate it comes from.
            VisibilityCore does not assume breed figures.
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-3 sm:grid-cols-2">
          <div className="space-y-1 sm:col-span-2">
            <Label htmlFor="as-eggs">Expected lifetime saleable eggs</Label>
            <Input id="as-eggs" type="number" min={1} value={eggs} onChange={(e) => setEggs(e.target.value)} placeholder="Leave blank to work it out below" />
          </div>
          <div className="space-y-1"><Label htmlFor="as-weeks">Laying weeks</Label><Input id="as-weeks" type="number" min={1} max={260} value={weeks} onChange={(e) => setWeeks(e.target.value)} /></div>
          <div className="space-y-1"><Label htmlFor="as-rate">Average lay rate %</Label><Input id="as-rate" type="number" min={0} max={100} value={rate} onChange={(e) => setRate(e.target.value)} /></div>
          <div className="space-y-1"><Label htmlFor="as-mort">Expected mortality %</Label><Input id="as-mort" type="number" min={0} max={100} value={mort} onChange={(e) => setMort(e.target.value)} /></div>
          <div className="space-y-1"><Label>Birds placed</Label><p className="pt-2 text-sm tabular-nums">{num(flock.originallyPlaced)}</p></div>
          {!eggs && derived.eggs != null && (
            <p className="text-xs text-slate-600 sm:col-span-2">Works out to <strong>{num(derived.eggs)}</strong> eggs: {derived.basis}.</p>
          )}
          <div className="space-y-1"><Label htmlFor="as-res">Expected residual value (spent hens)</Label><Input id="as-res" type="number" min={0} value={resid} onChange={(e) => setResid(e.target.value)} /></div>
          <label className="flex items-center gap-2 pt-6 text-sm"><Checkbox checked={useResid} onCheckedChange={(v) => setUseResid(!!v)} />Deduct it from the pool</label>
          <div className="space-y-1 sm:col-span-2"><Label htmlFor="as-notes">Notes</Label><Textarea id="as-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Where these figures come from" /></div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button onClick={save} disabled={saving}>{saving ? "Saving…" : "Save"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

const CATS: HistoricalCostInput["category"][] = ["BirdPurchase", "Feed", "Medication", "Labour", "Overhead", "Other"]
const CAT_LABEL: Record<string, string> = { BirdPurchase: "Bird purchase", Feed: "Feed", Medication: "Medication & vaccines", Labour: "Labour", Overhead: "Overhead", Other: "Other" }

function HistoricalDialog({ flock, onClose, onSaved }: { flock: FactFlock; onClose: () => void; onSaved: () => void }) {
  const [level, setLevel] = useState<"flock" | "batch">("flock")
  const [cat, setCat] = useState<HistoricalCostInput["category"]>("Feed")
  const [amount, setAmount] = useState("")
  const [from, setFrom] = useState(flock.startDate?.slice(0, 10) ?? "")
  const [to, setTo] = useState(flock.firstEggDate?.slice(0, 10) ?? "")
  const [reason, setReason] = useState("")
  const [ref, setRef] = useState("")
  const [est, setEst] = useState(true)
  const [saving, setSaving] = useState(false)
  const { toast } = useToast()

  async function save() {
    setSaving(true)
    const r = await addHistoricalCost({
      flockId: level === "flock" ? flock.flockId : null, batchId: level === "batch" ? flock.batchId : null,
      category: cat, amount: Number(amount), periodFrom: from || null, periodTo: to || null,
      reason, reference: ref || null, isEstimate: est,
    })
    setSaving(false)
    if (!r.success) { toast({ title: "Not saved", description: r.message, variant: "destructive" }); return }
    toast({ title: "Historical cost added", description: "Analysis only: no expense or cash movement was created." })
    onSaved()
  }

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Historical rearing cost</DialogTitle>
          <DialogDescription>
            A cost from before this flock's records were kept in VisibilityCore. It only feeds the pre-laying analysis — it never becomes an expense, a payment or a P&amp;L line.
            Costs VisibilityCore already holds are refused.
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-3 sm:grid-cols-2">
          <div className="space-y-1">
            <Label>For</Label>
            <Select value={level} onValueChange={(v) => setLevel(v as "flock" | "batch")}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="flock">This flock ({flock.name})</SelectItem>
                {flock.batchId != null && <SelectItem value="batch">The whole batch {flock.batchCode ?? ""} (shared by birds placed)</SelectItem>}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1">
            <Label>Category</Label>
            <Select value={cat} onValueChange={(v) => setCat(v as HistoricalCostInput["category"])}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>{CATS.map((c) => <SelectItem key={c} value={c}>{CAT_LABEL[c]}</SelectItem>)}</SelectContent>
            </Select>
          </div>
          <div className="space-y-1"><Label htmlFor="hc-amt">Amount</Label><Input id="hc-amt" type="number" min={0} step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} /></div>
          <label className="flex items-center gap-2 pt-6 text-sm"><Checkbox checked={est} onCheckedChange={(v) => setEst(!!v)} />This is an estimate</label>
          <div className="space-y-1"><Label htmlFor="hc-from">From</Label><Input id="hc-from" type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></div>
          <div className="space-y-1"><Label htmlFor="hc-to">To</Label><Input id="hc-to" type="date" value={to} onChange={(e) => setTo(e.target.value)} /></div>
          <div className="space-y-1 sm:col-span-2"><Label htmlFor="hc-reason">Reason</Label><Input id="hc-reason" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. Rearing feed bought before we started using VisibilityCore" /></div>
          <div className="space-y-1 sm:col-span-2"><Label htmlFor="hc-ref">Supporting reference</Label><Input id="hc-ref" value={ref} onChange={(e) => setRef(e.target.value)} placeholder="Invoice or notebook reference (optional)" /></div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button onClick={save} disabled={saving || !(Number(amount) > 0) || !reason.trim()}>{saving ? "Saving…" : "Add"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
