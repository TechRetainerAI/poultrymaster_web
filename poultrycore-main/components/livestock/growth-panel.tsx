"use client"

// A group's growth: weigh-ins, gain per day, and feed per kg gained (feed
// conversion) between weigh-ins. Plus the weigh-in dialog, which also weighs
// a single tagged animal.

import { useCallback, useEffect, useState } from "react"
import { Plus, Trash2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { useToast } from "@/hooks/use-toast"
import { deleteWeighIn, getGrowth, saveWeighIn, type Growth } from "@/lib/api/livestock"
import { AMBER_BUTTON, EmptyState, LoadError, Loading, StatCard, fmtDate, fmtNum, todayIso } from "./livestock-page"

export function GrowthPanel({ groupId, groupStart, canRecord = true }: { groupId: number; groupStart?: string; canRecord?: boolean }) {
  const [g, setG] = useState<Growth | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [adding, setAdding] = useState(false)
  const [deleting, setDeleting] = useState<number | null>(null)

  const load = useCallback(async () => {
    setError(null)
    try { setG(await getGrowth(groupId)) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [groupId])
  useEffect(() => { load() }, [load])
  const pg = usePagination(g?.weighIns ?? [], 10)

  if (error) return <LoadError message={error} onRetry={load} />
  if (!g) return <Loading />

  const latest = g.weighIns[0]
  const withGain = g.weighIns.filter((w) => w.dailyGainG != null)
  const lastFcr = g.weighIns.find((w) => w.fcr != null)?.fcr ?? null

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <div className="grid grid-cols-3 gap-3 flex-1">
          <StatCard label="Latest average weight" value={latest ? `${fmtNum(latest.avgWeightKg)} kg` : "—"} tone="amber"
            hint={latest ? fmtDate(latest.date) : undefined} />
          <StatCard label="Gain per day" value={withGain[0] ? `${fmtNum(withGain[0].dailyGainG)} g` : "—"} hint="Since the weigh-in before" />
          <StatCard label="Feed per kg gained" value={lastFcr != null ? fmtNum(lastFcr) : "—"}
            hint={g.feedWithoutKg ? "Some feed has no kg size, so it is left out" : "Lower is better"} />
        </div>
      </div>
      {canRecord && (
        <div className="flex justify-end">
          <Button className={AMBER_BUTTON} onClick={() => setAdding(true)}><Plus className="h-4 w-4 mr-1" /> Record weigh-in</Button>
        </div>
      )}
      {g.weighIns.length === 0 ? (
        <EmptyState title="No weigh-ins yet">Weigh a sample of the group every week or two to see how fast it grows and how well it turns feed into weight.</EmptyState>
      ) : (
        <div className="rounded-md border bg-white overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Date</TableHead>
                <TableHead className="text-right">Average weight</TableHead>
                <TableHead className="text-right">Weighed</TableHead>
                <TableHead className="text-right">Gain</TableHead>
                <TableHead className="text-right">Per day</TableHead>
                <TableHead className="text-right">Feed eaten</TableHead>
                <TableHead className="text-right">Feed per kg gained</TableHead>
                <TableHead />
              </TableRow>
            </TableHeader>
            <TableBody>
              {pg.pageItems.map((w) => (
                <TableRow key={w.weighInId}>
                  <TableCell className="whitespace-nowrap">{fmtDate(w.date)}</TableCell>
                  <TableCell className="text-right font-medium">{fmtNum(w.avgWeightKg)} kg</TableCell>
                  <TableCell className="text-right">{w.sampleSize ? `${w.sampleSize} of ${w.head}` : "—"}</TableCell>
                  <TableCell className="text-right">{w.gainKg == null ? "—" : `${w.gainKg > 0 ? "+" : ""}${fmtNum(w.gainKg)} kg`}</TableCell>
                  <TableCell className="text-right">{w.dailyGainG == null ? "—" : `${fmtNum(w.dailyGainG)} g`}</TableCell>
                  <TableCell className="text-right">{w.feedKg == null ? "—" : `${fmtNum(w.feedKg)} kg`}</TableCell>
                  <TableCell className="text-right">{w.fcr == null ? "—" : fmtNum(w.fcr)}</TableCell>
                  <TableCell className="text-right">
                    <Button variant="ghost" size="icon" aria-label="Delete weigh-in" onClick={() => setDeleting(w.weighInId)}><Trash2 className="h-4 w-4 text-rose-600" /></Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
          <DataPagination {...pg.paginationProps} variant="records" />
        </div>
      )}
      {g.animalWeighIns.length > 0 && (
        <p className="text-xs text-stone-500">{g.animalWeighIns.length} weighing(s) of single tagged animals are on those animals' pages.</p>
      )}
      {adding && <WeighInDialog target={{ groupId }} minDate={groupStart} onClose={() => setAdding(false)} onDone={() => { setAdding(false); load() }} />}
      <ConfirmDeleteDialog
        open={deleting != null}
        onOpenChange={(o) => !o && setDeleting(null)}
        title="Delete this weigh-in?"
        onConfirm={() => deleteWeighIn(deleting!)}
        onSuccess={() => { setDeleting(null); load() }}
      />
    </div>
  )
}

export function WeighInDialog({ target, minDate, onClose, onDone }: {
  target: { groupId?: number; animalId?: number; label?: string }
  minDate?: string
  onClose: () => void
  onDone: () => void
}) {
  const { toast } = useToast()
  const [date, setDate] = useState(todayIso())
  const [kg, setKg] = useState("")
  const [n, setN] = useState("")
  const [notes, setNotes] = useState("")
  const [saving, setSaving] = useState(false)
  const single = !!target.animalId
  const save = async () => {
    setSaving(true)
    try {
      await saveWeighIn({ groupId: target.groupId ?? null, animalId: target.animalId ?? null, date, avgWeightKg: Number(kg),
        sampleSize: single ? 1 : n ? Number(n) : null, notes: notes.trim() || null })
      toast({ title: "Weigh-in saved" })
      onDone()
    } catch (e: any) {
      toast({ title: "Not saved", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader><DialogTitle>Weigh-in{target.label ? `: ${target.label}` : ""}</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <div className="grid grid-cols-3 gap-3">
            <div>
              <Label htmlFor="wi-date">Date</Label>
              <Input id="wi-date" type="date" min={minDate} max={todayIso()} value={date} onChange={(e) => setDate(e.target.value)} />
            </div>
            <div>
              <Label htmlFor="wi-kg">{single ? "Weight (kg)" : "Average weight (kg)"}</Label>
              <Input id="wi-kg" type="number" min={0} step="0.001" value={kg} onChange={(e) => setKg(e.target.value)} />
            </div>
            {!single && (
              <div>
                <Label htmlFor="wi-n">How many weighed</Label>
                <Input id="wi-n" type="number" min={1} inputMode="numeric" value={n} onChange={(e) => setN(e.target.value)} />
              </div>
            )}
          </div>
          <div>
            <Label htmlFor="wi-notes">Notes</Label>
            <Textarea id="wi-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || !(Number(kg) > 0) || !date} onClick={save}>{saving ? "Saving…" : "Save"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
