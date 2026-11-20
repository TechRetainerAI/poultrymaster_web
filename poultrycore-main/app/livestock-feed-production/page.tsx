"use client"

// Feed Mixing -- the poultry Feed Production page for livestock. A mixing run
// takes the ingredients out of stock and puts the feed in at what they cost,
// plus any milling or labour cost.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { Factory, Plus } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { useToast } from "@/hooks/use-toast"
import { listFeedRuns, listFormulas, mixFeed, reverseFeedRun, type FeedFormula, type FeedRun } from "@/lib/api/livestock"
import { AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, fmtDate, fmtMoney, fmtNum, todayIso } from "@/components/livestock/livestock-page"

export default function LivestockFeedProductionPage() {
  const [runs, setRuns] = useState<FeedRun[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [mixing, setMixing] = useState(false)
  const [reversing, setReversing] = useState<FeedRun | null>(null)

  const load = useCallback(async () => {
    setError(null)
    try { setRuns(await listFeedRuns()) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [])
  useEffect(() => { load() }, [load])

  return (
    <LivestockPage
      title="Feed mixing"
      description="Mix feed from your formulas: ingredients come out of stock, the feed goes in at what it cost."
      icon={Factory}
      actions={
        <>
          <Button asChild variant="outline"><Link href="/livestock-feed-formulas">Formulas</Link></Button>
          <Button className={AMBER_BUTTON} onClick={() => setMixing(true)}><Plus className="h-4 w-4 mr-1" /> Mix feed</Button>
        </>
      }
    >
      {error ? <LoadError message={error} onRetry={load} /> : !runs ? <Loading /> : runs.length === 0 ? (
        <EmptyState title="No feed mixed yet" />
      ) : (
        <div className="rounded-md border bg-white overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Date</TableHead><TableHead>Formula</TableHead><TableHead className="text-right">Batches</TableHead>
                <TableHead className="text-right">Made</TableHead><TableHead className="text-right">Cost</TableHead>
                <TableHead className="text-right">Cost each</TableHead><TableHead />
              </TableRow>
            </TableHeader>
            <TableBody>
              {runs.map((r) => (
                <TableRow key={r.runId} className={r.reversedAt ? "opacity-50" : undefined}>
                  <TableCell className="whitespace-nowrap">{fmtDate(r.date)}</TableCell>
                  <TableCell>{r.formulaName}{r.reversedAt && <Badge variant="outline" className="ml-2">Reversed</Badge>}
                    {r.reverseReason && <div className="text-xs">{r.reverseReason}</div>}</TableCell>
                  <TableCell className="text-right">{fmtNum(r.batches)}</TableCell>
                  <TableCell className="text-right">{fmtNum(r.outputQuantity)} {r.outputUnit} {r.outputItemName}</TableCell>
                  <TableCell className="text-right">{fmtMoney(r.totalCost)}</TableCell>
                  <TableCell className="text-right">{fmtMoney(r.unitCost)}</TableCell>
                  <TableCell className="text-right">{!r.reversedAt && <Button variant="ghost" size="sm" onClick={() => setReversing(r)}>Reverse</Button>}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}

      {mixing && <MixDialog onClose={() => setMixing(false)} onDone={() => { setMixing(false); load() }} />}
      <PromptDialog
        open={!!reversing}
        onOpenChange={(o) => !o && setReversing(null)}
        title="Reverse this mixing?"
        description="The ingredients go back into stock and the feed comes out. Not possible once some of the feed has been used."
        label="Why"
        confirmLabel="Reverse"
        confirmVariant="destructive"
        onSubmit={async (reason) => { await reverseFeedRun(reversing!.runId, reason); setReversing(null); load() }}
      />
    </LivestockPage>
  )
}

function MixDialog({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const { toast } = useToast()
  const [formulas, setFormulas] = useState<FeedFormula[]>([])
  const [formulaId, setFormulaId] = useState(0)
  const [date, setDate] = useState(todayIso())
  const [batches, setBatches] = useState("1")
  const [output, setOutput] = useState("")
  const [other, setOther] = useState("")
  const [notes, setNotes] = useState("")
  const [saving, setSaving] = useState(false)
  useEffect(() => { listFormulas().then((fs) => setFormulas(fs.filter((f) => f.isActive))).catch(() => setFormulas([])) }, [])
  const f = formulas.find((x) => x.formulaId === formulaId)
  const n = Number(batches) || 0
  const short = f?.lines.filter((l) => l.stock < l.quantity * n) ?? []
  const expected = f ? f.batchQuantity * n : 0
  const cost = (f?.batchCost ?? 0) * n + (Number(other) || 0)
  const save = async () => {
    setSaving(true)
    try {
      await mixFeed({ formulaId, date, batches: n, outputQuantity: output === "" ? null : Number(output), otherCost: other === "" ? null : Number(other), notes: notes.trim() || null })
      toast({ title: "Feed mixed", description: `${fmtNum(output === "" ? expected : Number(output))} ${f?.outputUnit} of ${f?.outputItemName} added to stock.` })
      onDone()
    } catch (e: any) { toast({ title: "Not mixed", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setSaving(false) }
  }
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-lg">
        <DialogHeader><DialogTitle>Mix feed</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <div>
            <Label>Formula</Label>
            <Select value={formulaId ? String(formulaId) : ""} onValueChange={(v) => setFormulaId(Number(v))}>
              <SelectTrigger><SelectValue placeholder={formulas.length ? "Choose" : "Write a formula first"} /></SelectTrigger>
              <SelectContent>{formulas.map((x) => <SelectItem key={x.formulaId} value={String(x.formulaId)}>{x.name} · up to {fmtNum(x.batchesPossible ?? 0)} batch(es)</SelectItem>)}</SelectContent>
            </Select>
          </div>
          <div className="grid grid-cols-3 gap-3">
            <div><Label htmlFor="mx-date">Date</Label><Input id="mx-date" type="date" max={todayIso()} value={date} onChange={(e) => setDate(e.target.value)} /></div>
            <div><Label htmlFor="mx-b">Batches</Label><Input id="mx-b" type="number" min={0} step="any" value={batches} onChange={(e) => setBatches(e.target.value)} /></div>
            <div>
              <Label htmlFor="mx-out">Made{f ? ` (${f.outputUnit})` : ""}</Label>
              <Input id="mx-out" type="number" min={0} step="any" placeholder={expected ? String(expected) : ""} value={output} onChange={(e) => setOutput(e.target.value)} />
            </div>
          </div>
          <div><Label htmlFor="mx-other">Other costs (milling, labour)</Label><Input id="mx-other" type="number" min={0} step="0.01" value={other} onChange={(e) => setOther(e.target.value)} /></div>
          {f && n > 0 && (
            <div className="rounded-md bg-stone-50 border p-3 text-sm space-y-1">
              {f.lines.map((l) => (
                <div key={l.itemId} className={`flex justify-between ${l.stock < l.quantity * n ? "text-rose-700" : ""}`}>
                  <span>{l.itemName}</span><span>{fmtNum(l.quantity * n)} of {fmtNum(l.stock)} {l.unit}</span>
                </div>
              ))}
              <div className="border-t pt-1 flex justify-between font-medium"><span>About</span><span>{fmtMoney(cost)}</span></div>
            </div>
          )}
          <div><Label htmlFor="mx-notes">Notes</Label><Textarea id="mx-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} /></div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || !f || n <= 0 || short.length > 0} onClick={save}>{saving ? "Mixing…" : "Mix"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
