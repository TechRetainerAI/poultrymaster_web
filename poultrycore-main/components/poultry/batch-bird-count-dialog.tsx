"use client"

// 440: Batch bird count. The farm counts its pens and enters the figures here:
// pick the batch, type each flock's counted birds, see the change (up or down),
// save once. The server posts each flock's change as its own Stock Count
// Correction movement -- the same thing as entering them one at a time on
// "New movement" -- all in one transaction (one refused flock saves none).
// A flock left blank is not counted; a flock whose count matches is skipped.
//
// 441: each flock is compared with its birds at the END of the count date, not
// today -- counted yesterday with today's deaths already entered, today becomes
// "counted - today's deaths". The sheet comes from the server for the chosen
// batch and date. Saving needs poultry.bird-count.create.
//
// BatchBirdCountForm is the whole tool; it is the Tools > Batch Bird Count page
// (/poultry-batch-bird-count) and, wrapped in BatchBirdCountDialog, the
// "Batch bird count" button on Stock Movements.

import { useEffect, useMemo, useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Loader2 } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { cn } from "@/lib/utils"
import {
  listPoultryBirdAdjustmentOptions, postPoultryBatchBirdCount, getPoultryBirdCountSheet,
  type PoultryBirdAdjustmentOption, type PoultryBirdCountSheetRow,
} from "@/lib/api/poultry-inventory"

function localToday(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
}
function newRequestKey(): string {
  try { return crypto.randomUUID() } catch { return `bbc-${Date.now()}-${Math.random().toString(36).slice(2)}` }
}
const fmt = (n: number) => n.toLocaleString()
const signed = (n: number) => (n > 0 ? `+${fmt(n)}` : fmt(n))
const longDate = (d: string) => {
  const [y, m, day] = d.split("-").map(Number)
  return y ? new Date(y, m - 1, day).toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" }) : d
}

/**
 * The count form. It starts fresh (and reloads the flocks) whenever `resetKey`
 * changes -- the dialog bumps it on every open, the page after every save.
 */
export function BatchBirdCountForm({
  resetKey = 0, onSaved, onCancel, layout = "dialog",
}: {
  resetKey?: number
  /** "page": full width -- batch, date and note on one row, totals as tiles. */
  layout?: "dialog" | "page"
  onSaved: () => void
  /** Shown as a Cancel button when given (the dialog). */
  onCancel?: () => void
}) {
  const { toast } = useToast()
  const canSave = usePermissions().can("poultry.bird-count.create")
  const [options, setOptions] = useState<PoultryBirdAdjustmentOption[] | null>(null)
  /** The chosen batch's flocks with their birds on the count date (441). */
  const [sheet, setSheet] = useState<PoultryBirdCountSheetRow[] | null>(null)
  const [sheetLoading, setSheetLoading] = useState(false)
  /** Bumped to fetch the sheet again (after a "changed since" refusal). */
  const [sheetVersion, setSheetVersion] = useState(0)
  const [batchId, setBatchId] = useState("")
  const [date, setDate] = useState("")
  const [note, setNote] = useState("")
  /** flockId -> what was typed ("" = not counted). */
  const [counts, setCounts] = useState<Record<number, string>>({})
  const [saving, setSaving] = useState(false)
  const [requestKey, setRequestKey] = useState(newRequestKey)

  const load = () =>
    listPoultryBirdAdjustmentOptions()
      .then(setOptions)
      .catch((e: any) => toast({ title: "Could not load batches and flocks", description: e?.message, variant: "destructive" }))

  useEffect(() => {
    setBatchId(""); setDate(localToday()); setNote(""); setCounts({})
    setRequestKey(newRequestKey())
    setOptions(null)
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [resetKey])

  // Batches that have at least one open flock.
  const batches = useMemo(() => {
    const seen = new Map<number, PoultryBirdAdjustmentOption>()
    for (const o of options ?? []) if (o.flockId != null && !o.isClosed && !seen.has(o.batchId)) seen.set(o.batchId, o)
    return Array.from(seen.values())
  }, [options])

  // 441: the birds each flock had at the end of the count date.
  useEffect(() => {
    let cancelled = false
    if (!batchId || !date) { setSheet(null); return }
    setSheetLoading(true)
    getPoultryBirdCountSheet(Number(batchId), date)
      .then((r) => { if (!cancelled) setSheet(r) })
      .catch((e: any) => { if (!cancelled) { setSheet(null); toast({ title: "Could not load the flocks", description: e?.message, variant: "destructive" }) } })
      .finally(() => { if (!cancelled) setSheetLoading(false) })
    return () => { cancelled = true }
  }, [batchId, date, sheetVersion, toast])

  const isToday = date === localToday()
  const rows = (sheet ?? []).map((f) => {
    const started = f.birdsOnDate != null
    const now = f.birdsOnDate ?? 0
    const text = started ? counts[f.flockId] ?? "" : ""
    const counted = text.trim() === "" ? null : Number(text)
    const valid = counted == null || (Number.isInteger(counted) && counted >= 0)
    return { f, started, now, text, counted, valid, change: counted == null || !valid ? null : counted - now }
  })
  const countedRows = rows.filter((r) => r.counted != null)
  const totalNow = rows.reduce((s, r) => s + r.now, 0)
  const totalNew = rows.reduce((s, r) => s + (r.change == null ? r.now : (r.counted as number)), 0)
  const totalChange = totalNew - totalNow
  const toPost = rows.filter((r) => r.change != null && r.change !== 0).length

  async function save() {
    if (!canSave) { toast({ title: "You cannot save bird counts", description: "Ask an admin for the Batch Bird Count permission.", variant: "destructive" }); return }
    if (!batchId) { toast({ title: "Choose the batch", variant: "destructive" }); return }
    if (!date) { toast({ title: "Enter the date the birds were counted", variant: "destructive" }); return }
    if (date > localToday()) { toast({ title: "The count date is in the future", variant: "destructive" }); return }
    const bad = rows.find((r) => !r.valid)
    if (bad) { toast({ title: `${bad.f.flockName}: enter a whole number, 0 or more`, variant: "destructive" }); return }
    if (countedRows.length === 0) { toast({ title: "Enter the counted birds for at least one flock", variant: "destructive" }); return }
    if (toPost === 0) { toast({ title: "Every count matches the birds now", description: "There is nothing to adjust.", variant: "destructive" }); return }

    setSaving(true)
    try {
      const res = await postPoultryBatchBirdCount({
        batchId: Number(batchId),
        effectiveDate: date,
        lines: countedRows.map((r) => ({ flockId: r.f.flockId, countedBirds: r.counted as number, currentBirds: r.now })),
        note: note.trim() || null,
        requestKey,
      })
      const posted = res.movements.filter((m) => m.movementNo)
      toast({
        title: res.repeated ? "This count was already saved" : `${posted.length} flock${posted.length === 1 ? "" : "s"} adjusted`,
        description: posted.map((m) => m.movementNo).join(", ") || undefined,
      })
      onSaved()
    } catch (e: any) {
      toast({ title: "Save failed", description: e?.message, variant: "destructive" })
      // A flock that changed since: show the new figures to count against.
      if (/Reload/i.test(e?.message ?? "")) { load(); setSheetVersion((v) => v + 1) }
    } finally { setSaving(false) }
  }

  const isPage = layout === "page"
  const noteField = (
    <FormField label="Note" full={!isPage}>
      <Input value={note} onChange={(e) => setNote(e.target.value)} placeholder="e.g. Physical count, Front and Back houses" />
    </FormField>
  )
  const tiles = [
    { label: "Flocks", value: fmt(rows.length), note: countedRows.length ? `${fmt(countedRows.length)} counted` : "none counted yet", tone: "text-slate-900" },
    { label: isToday ? "Birds now" : "Birds on that day", value: fmt(totalNow), note: isToday ? "in the system" : `end of ${longDate(date)}`, tone: "text-slate-900" },
    { label: "After the count", value: fmt(totalNew), note: "blank flocks keep their birds", tone: "text-blue-700" },
    { label: "Adjustment", value: totalChange === 0 ? "0" : signed(totalChange), note: `${fmt(toPost)} flock${toPost === 1 ? "" : "s"} to adjust`,
      tone: totalChange > 0 ? "text-emerald-600" : totalChange < 0 ? "text-red-600" : "text-slate-500" },
  ]

  return (
    <div className="space-y-4">
      <FormSection title="Count" color="blue" columns={isPage ? 3 : 2}>
        <FormField label="Batch *">
          <Select value={batchId} onValueChange={(v) => { setBatchId(v); setCounts({}) }}>
            <SelectTrigger><SelectValue placeholder={options ? "Choose the batch" : "Loading batches..."} /></SelectTrigger>
            <SelectContent>
              {batches.map((b) => (
                <SelectItem key={b.batchId} value={String(b.batchId)}>{b.batchCode} — {b.batchName}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </FormField>
        <FormField label="Date counted *" hint="The day of the count. Each flock is compared with its birds at the end of that day.">
          <Input type="date" value={date} max={localToday()} onChange={(e) => setDate(e.target.value)} />
        </FormField>
        {isPage && noteField}
      </FormSection>

      {isPage && batchId && rows.length > 0 && (
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
          {tiles.map((t) => (
            <div key={t.label} className="rounded-lg border border-slate-200 bg-white px-4 py-3">
              <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">{t.label}</div>
              <div className={cn("mt-1 text-2xl font-bold tabular-nums", t.tone)}>{t.value}</div>
              <div className="text-xs text-slate-400">{t.note}</div>
            </div>
          ))}
        </div>
      )}

      {isPage && !batchId && (
        <div className="rounded-lg border border-dashed border-slate-300 bg-white px-4 py-12 text-center text-sm text-slate-500">
          Choose a batch to list its flocks. Then type the birds you counted in each one.
        </div>
      )}

      {batchId && (
        <div className="overflow-x-auto rounded-lg border border-slate-200 bg-white">
          <table className="w-full text-sm">
            <thead className="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th className="px-3 py-2 text-left">Flock</th>
                <th className="px-3 py-2 text-right">{isToday ? "Birds now" : `Birds on ${longDate(date)}`}</th>
                <th className="px-3 py-2 text-right w-36">Counted</th>
                <th className="px-3 py-2 text-right">Adjustment</th>
              </tr>
            </thead>
            <tbody>
              {sheetLoading && rows.length === 0 && (
                <tr><td colSpan={4} className="px-3 py-6 text-center text-slate-500"><Loader2 className="mr-1 inline h-4 w-4 animate-spin" /> Loading flocks...</td></tr>
              )}
              {!sheetLoading && rows.length === 0 && (
                <tr><td colSpan={4} className="px-3 py-6 text-center text-slate-500">This batch has no open flocks.</td></tr>
              )}
              {rows.map((r) => (
                <tr key={r.f.flockId} className="border-t border-slate-100">
                  <td className="px-3 py-1.5 font-medium text-slate-900">{r.f.flockName}</td>
                  <td className="px-3 py-1.5 text-right tabular-nums">
                    {r.started ? fmt(r.now) : <span className="text-slate-400">Not started</span>}
                    {r.started && !isToday && r.f.birdsNow !== r.now && (
                      <span className="block text-[11px] text-slate-400">{fmt(r.f.birdsNow)} now</span>
                    )}
                  </td>
                  <td className="px-3 py-1.5">
                    <Input
                      disabled={!r.started || !canSave}
                      type="number" inputMode="numeric" min={0} step={1}
                      className={cn("h-8 text-right tabular-nums", !r.valid && "border-red-500")}
                      placeholder={fmt(r.now)}
                      aria-label={`${r.f.flockName} counted birds`}
                      value={r.text}
                      onChange={(e) => setCounts((c) => ({ ...c, [r.f.flockId]: e.target.value }))}
                    />
                  </td>
                  <td className={cn("px-3 py-1.5 text-right tabular-nums font-semibold",
                    r.change == null ? "text-slate-300" : r.change > 0 ? "text-emerald-600" : r.change < 0 ? "text-red-600" : "text-slate-400")}>
                    {r.change == null ? "—" : r.change === 0 ? "No change" : signed(r.change)}
                  </td>
                </tr>
              ))}
            </tbody>
            {rows.length > 0 && (
              <tfoot className="border-t border-slate-200 bg-slate-50 font-semibold">
                <tr>
                  <td className="px-3 py-2">Total</td>
                  <td className="px-3 py-2 text-right tabular-nums">{fmt(totalNow)}</td>
                  <td className="px-3 py-2 text-right tabular-nums">{fmt(totalNew)}</td>
                  <td className={cn("px-3 py-2 text-right tabular-nums",
                    totalChange > 0 ? "text-emerald-600" : totalChange < 0 ? "text-red-600" : "text-slate-500")}>
                    {totalChange === 0 ? "0" : signed(totalChange)}
                  </td>
                </tr>
              </tfoot>
            )}
          </table>
          <p className="border-t border-slate-100 px-3 py-2 text-xs text-slate-500">
            Leave a flock blank if it was not counted. A flock that went down becomes a decrease, one that went up an increase.
            {!isToday && " Deaths and sales recorded after the count date still come off: today = counted minus what happened since."}
          </p>
        </div>
      )}

      {!isPage && noteField}

      <div className="flex items-center justify-end gap-2 pt-1">
        {onCancel && <Button variant="outline" onClick={onCancel} disabled={saving}>Cancel</Button>}
        {!canSave && <span className="mr-auto text-xs text-slate-500">You can view counts but not save them. Ask an admin for the Batch Bird Count permission.</span>}
        <Button onClick={save} disabled={saving || toPost === 0 || !canSave}>
          {saving && <Loader2 className="w-4 h-4 mr-1 animate-spin" />}
          Save {toPost > 0 ? `${toPost} adjustment${toPost === 1 ? "" : "s"}` : ""}
        </Button>
      </div>
    </div>
  )
}

/** The same form in a window -- the "Batch bird count" button on Stock Movements. */
export function BatchBirdCountDialog({
  open, onOpenChange, onSaved,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  onSaved: () => void
}) {
  const [resetKey, setResetKey] = useState(0)
  useEffect(() => { if (open) setResetKey((k) => k + 1) }, [open])
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Batch bird count</DialogTitle>
          <DialogDescription>
            Enter the birds you counted in each flock. Each flock&apos;s difference is saved as its own
            Stock Count Correction, the same as entering them one at a time.
          </DialogDescription>
        </DialogHeader>
        {open && (
          <BatchBirdCountForm
            resetKey={resetKey}
            onCancel={() => onOpenChange(false)}
            onSaved={() => { onOpenChange(false); onSaved() }}
          />
        )}
      </DialogContent>
    </Dialog>
  )
}
