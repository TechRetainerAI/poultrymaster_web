"use client"

// Step-through catch-up: the NORMAL production form, one missed day at a time,
// oldest first, for one flock. Opened from Farm Completeness ("Record N days").
//
// Deliberately not a second form: every day is the real ProductionRecordForm
// with every field and every stock / costing rule, saved exactly as a single
// entry would be. What this adds is only the sequence:
//   * the form opens on the next missed day ("Day 2 of 5") after each save;
//   * birds carry forward because the form seeds from the last record BEFORE
//     the day being entered;
//   * optionally, the previous day's feed and medication lines are carried in
//     as a starting point (still editable, still stock-checked on save).
// Days already in an unposted batch entry are not offered -- posting that
// batch is the fix -- and are listed with a link instead.

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { CheckCircle2, Loader2, SkipForward } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Checkbox } from "@/components/ui/checkbox"
import { cn } from "@/lib/utils"
import { useToast } from "@/hooks/use-toast"
import { ProductionRecordForm } from "@/components/production/production-record-form"
import type { FeedLineDraft } from "@/components/production/feed-lines"
import type { MedLineDraft } from "@/components/production/medication-lines"
import { getFlockMissingProductionDates, type MissingProductionDate } from "@/lib/api/activity-checks"
import { formatShortDate, formatWeekdayDate, missingDateHref, toBusinessDate } from "@/lib/activity/completeness"
import { feedDraftsFrom, medDraftsFrom } from "@/lib/production/carry-lines"

const FORM_ID = "catch-up-production-form"

export function ProductionCatchUpFlow({ flockId, asOf }: { flockId: number; asOf?: string }) {
  const router = useRouter()
  const { toast } = useToast()
  const [queue, setQueue] = useState<string[] | null>(null) // oldest first
  const [pending, setPending] = useState<MissingProductionDate[]>([])
  const [error, setError] = useState<string | null>(null)
  const [pos, setPos] = useState(0)
  const [saved, setSaved] = useState<string[]>([])
  const [skipped, setSkipped] = useState<string[]>([])
  const [carry, setCarry] = useState(true)
  const [carriedFeed, setCarriedFeed] = useState<FeedLineDraft[] | null>(null)
  const [carriedMed, setCarriedMed] = useState<MedLineDraft[] | null>(null)
  const [saving, setSaving] = useState(false)
  const [flockName, setFlockName] = useState<string | null>(null)

  const backHref = asOf ? `/poultry-farm-completeness?date=${asOf}` : "/poultry-farm-completeness"

  useEffect(() => {
    let cancelled = false
    getFlockMissingProductionDates(flockId, asOf, 30)
      .then((d) => {
        if (cancelled) return
        const oldestFirst = [...d.dates].reverse()
        setPending(oldestFirst.filter((x) => x.pendingBatchRecordId != null))
        setQueue(oldestFirst.filter((x) => x.pendingBatchRecordId == null).map((x) => toBusinessDate(x.date)!))
      })
      .catch((e) => { if (!cancelled) setError(e instanceof Error ? e.message : "Could not load the missing days.") })
    return () => { cancelled = true }
  }, [flockId, asOf])

  const current = queue?.[pos] ?? null
  const total = queue?.length ?? 0
  const isLast = pos >= total - 1
  const finished = queue != null && pos >= total

  useEffect(() => {
    if (finished && total > 0) {
      toast({
        title: `${saved.length} day${saved.length === 1 ? "" : "s"} recorded`,
        description: skipped.length ? `${skipped.length} skipped — still missing.` : undefined,
      })
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [finished])

  const stateOf = useMemo(() => (d: string) =>
    saved.includes(d) ? "saved" : skipped.includes(d) ? "skipped" : d === current ? "current" : "todo", [saved, skipped, current])

  if (error) return <Card className="border-rose-200 bg-rose-50"><CardContent className="p-4 text-sm text-rose-800">{error}</CardContent></Card>
  if (queue == null) return <p className="flex items-center gap-2 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Finding the missed days…</p>

  const pendingNote = pending.length > 0 && (
    <Card className="border-sky-200 bg-sky-50">
      <CardContent className="space-y-1 p-3 text-sm text-sky-900">
        <p>Already in a batch entry that has not been posted — post it instead of entering these again:</p>
        <ul className="flex flex-wrap gap-x-3 gap-y-1">
          {pending.map((p) => (
            <li key={p.date}>
              <Link className="underline" href={missingDateHref(flockId, p.date, p.pendingBatchRecordId, p.pendingBatchStatus)}>
                {formatWeekdayDate(p.date)} (batch #{p.pendingBatchRecordId})
              </Link>
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  )

  if (total === 0 || finished) {
    return (
      <div className="space-y-4">
        {pendingNote}
        <Card>
          <CardContent className="space-y-3 p-4">
            {total === 0 ? (
              <p className="text-sm text-slate-700">This flock has no days to enter in the last 30 days.</p>
            ) : (
              <p className="flex items-center gap-2 text-sm text-slate-800">
                <CheckCircle2 className="h-5 w-5 text-emerald-600" />
                {saved.length} of {total} day{total === 1 ? "" : "s"} recorded{flockName ? ` for ${flockName}` : ""}.
                {skipped.length > 0 && ` ${skipped.length} skipped (${skipped.map(formatShortDate).join(", ")}) — still missing.`}
              </p>
            )}
            <Button onClick={() => router.push(backHref)}>Back to Farm Completeness</Button>
          </CardContent>
        </Card>
      </div>
    )
  }

  const next = () => setPos((p) => p + 1)

  return (
    <div className="space-y-4">
      {pendingNote}

      {/* ------------------------------------------------ progress */}
      <Card className="rounded-xl border border-l-4 border-slate-200 border-l-amber-500 bg-white shadow-sm">
        <CardContent className="space-y-3 p-4">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <p className="text-lg font-bold text-slate-900">
              Day {pos + 1} of {total} — {formatWeekdayDate(current)}
              {flockName && <span className="ml-2 text-sm font-normal text-slate-500">{flockName}</span>}
            </p>
            <label className="flex items-center gap-2 text-sm text-slate-700">
              <Checkbox checked={carry} onCheckedChange={(v) => setCarry(v === true)} />
              Start each day with the previous day&apos;s feed &amp; medication
            </label>
          </div>
          <ol className="flex flex-wrap gap-1.5">
            {queue.map((d) => {
              const st = stateOf(d)
              return (
                <li key={d} className={cn(
                  "rounded-full border px-2.5 py-0.5 text-xs",
                  st === "saved" && "border-emerald-200 bg-emerald-50 text-emerald-800",
                  st === "skipped" && "border-slate-200 bg-slate-100 text-slate-500 line-through",
                  st === "current" && "border-amber-300 bg-amber-100 font-semibold text-amber-900",
                  st === "todo" && "border-slate-200 bg-white text-slate-600",
                )}>
                  {formatShortDate(d)}
                </li>
              )
            })}
          </ol>
        </CardContent>
      </Card>

      {/* ------------------------------------------------ the normal form */}
      <ProductionRecordForm
        key={current!}
        mode="create"
        displayMode="page"
        flockId={flockId}
        date={current}
        formId={FORM_ID}
        hideActions
        initialFeedLines={carry ? carriedFeed : null}
        initialMedLines={carry ? carriedMed : null}
        onStateChange={(s) => {
          setSaving(s.saving)
          if (s.flockName) setFlockName(s.flockName)
        }}
        onSaved={(_id, input) => {
          setSaved((prev) => [...prev, current!])
          if (input) {
            const f = feedDraftsFrom(input.feeds)
            const m = medDraftsFrom(input.medications)
            setCarriedFeed(f.length ? f : null)
            setCarriedMed(m.length ? m : null)
          }
          if (!isLast) toast({ title: `${formatWeekdayDate(current)} saved`, description: `Next: ${formatWeekdayDate(queue[pos + 1])}` })
          next()
        }}
      />

      {/* ------------------------------------------------ actions */}
      <div className="sticky bottom-0 z-20 -mx-4 border-t border-slate-200 bg-white/95 px-4 py-3 pb-16 backdrop-blur sm:-mx-6 sm:px-6 lg:pb-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <Button variant="ghost" onClick={() => router.push(backHref)} disabled={saving}>Stop</Button>
          <div className="flex gap-2">
            <Button variant="outline" className="gap-1.5" disabled={saving}
              onClick={() => { setSkipped((prev) => [...prev, current!]); next() }}>
              <SkipForward className="h-4 w-4" /> Skip this day
            </Button>
            <Button type="submit" form={FORM_ID} disabled={saving} className="bg-emerald-600 text-white hover:bg-emerald-700">
              {saving && <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />}
              {isLast ? "Save & finish" : "Save & next missing day"}
            </Button>
          </div>
        </div>
      </div>
    </div>
  )
}
