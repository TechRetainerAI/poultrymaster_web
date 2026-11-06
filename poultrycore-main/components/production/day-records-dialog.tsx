"use client"

import { useEffect, useMemo, useState, type ReactNode } from "react"
import { ChevronLeft, ChevronRight, CalendarDays, Pencil, Filter } from "lucide-react"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Table, TableBody, TableCell, TableFooter, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { toLocalDateKey } from "@/lib/utils/date-key"

type PickColumn = { header: string; key: string }

/** Where each number lives on a record. Production records are the default;
 *  batch production records pass their own field names. */
export type DayFields = {
  date: string; p1: string; p2: string; p3: string; broken: string; eggs: string
  feed: string; birds: string; deaths: string
  /** Birds left field; when absent, left = birds - deaths. */
  left?: string
}

export const PRODUCTION_DAY_FIELDS: DayFields = {
  date: "date", p1: "production9AM", p2: "production12PM", p3: "production4PM", broken: "brokenEggs",
  eggs: "totalProduction", feed: "feedKg", birds: "noOfBirds", deaths: "mortality",
}

/** Shift a yyyy-MM-dd key by whole days, staying in local time. */
function shiftDay(key: string, days: number): string {
  const [y, m, d] = key.split("-").map(Number)
  const dt = new Date(y, m - 1, d + days)
  return `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, "0")}-${String(dt.getDate()).padStart(2, "0")}`
}

function longDate(key: string): string {
  const [y, m, d] = key.split("-").map(Number)
  return new Date(y, m - 1, d).toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric", year: "numeric" })
}

const n = (v: unknown) => Number(v) || 0
const fmt = (v: number) => v.toLocaleString()

/**
 * Every production record logged on one day, across all flocks and batches --
 * the page's own filters do not apply here. Opens on the most recent day that
 * has records; the arrows step one calendar day at a time.
 */
export function DayRecordsDialog<T extends { id: number }>({
  open,
  onOpenChange,
  records,
  pickColumns,
  flockLabel,
  batchLabel,
  canEdit,
  onEdit,
  onShowInTable,
  fields = PRODUCTION_DAY_FIELDS,
  firstHeader = "Flock",
  secondHeader = "Batch",
  description = "Every production record logged on the chosen day, for all flocks.",
  statusCell,
  editLabel = "Edit",
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  records: T[]
  pickColumns: PickColumn[]
  /** First column (the flock, or the batch name). */
  flockLabel: (r: T) => string
  /** Second column (the batch, or the flocks a batch record covers). */
  batchLabel: (r: T) => string
  canEdit: boolean
  onEdit: (r: T) => void
  /** Apply this day as the page's date filter and close. */
  onShowInTable: (day: string) => void
  fields?: DayFields
  firstHeader?: string
  secondHeader?: string
  description?: string
  /** Optional Status column (batch records). */
  statusCell?: (r: T) => ReactNode
  editLabel?: string
}) {
  const F = fields
  const get = (r: T, k: string) => n((r as any)[k])
  const leftOf = (r: T) => (F.left ? get(r, F.left) : get(r, F.birds) - get(r, F.deaths))
  const latestDay = useMemo(() => {
    let best = ""
    for (const r of records) {
      const k = toLocalDateKey((r as any)[F.date])
      if (k > best) best = k
    }
    return best || toLocalDateKey(new Date().toISOString())
  }, [records, F.date])

  const [day, setDay] = useState(latestDay)
  // Each time the dialog opens, start on the latest day with records.
  useEffect(() => { if (open) setDay(latestDay) }, [open, latestDay])

  const rows = useMemo(
    () =>
      records
        .filter((r) => toLocalDateKey((r as any)[F.date]) === day)
        .sort((a, b) => flockLabel(a).localeCompare(flockLabel(b))),
    [records, day, flockLabel, F.date],
  )

  const totals = useMemo(() => {
    const t = { p9: 0, p12: 0, p4: 0, extra: {} as Record<string, number>, broken: 0, eggs: 0, feed: 0, birds: 0, deaths: 0, left: 0 }
    for (const r of rows) {
      t.p9 += get(r, F.p1); t.p12 += get(r, F.p2); t.p4 += get(r, F.p3)
      for (const c of pickColumns) t.extra[c.key] = (t.extra[c.key] || 0) + get(r, c.key)
      t.broken += get(r, F.broken); t.eggs += get(r, F.eggs); t.feed += get(r, F.feed)
      t.birds += get(r, F.birds); t.deaths += get(r, F.deaths); t.left += leftOf(r)
    }
    return t
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rows, pickColumns, F])

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[90vh] w-[calc(100vw-2rem)] max-w-6xl overflow-hidden flex flex-col sm:max-w-6xl">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <CalendarDays className="h-5 w-5 text-emerald-600" /> Records for a day
          </DialogTitle>
          <DialogDescription>{description}</DialogDescription>
        </DialogHeader>

        <div className="flex flex-wrap items-center gap-2">
          <Button variant="outline" size="icon" className="h-9 w-9" onClick={() => setDay((d) => shiftDay(d, -1))} aria-label="Previous day">
            <ChevronLeft className="h-4 w-4" />
          </Button>
          <Input type="date" value={day} onChange={(e) => e.target.value && setDay(e.target.value)} className="h-9 w-[160px]" />
          <Button variant="outline" size="icon" className="h-9 w-9" onClick={() => setDay((d) => shiftDay(d, 1))} aria-label="Next day">
            <ChevronRight className="h-4 w-4" />
          </Button>
          {day !== latestDay && (
            <Button variant="ghost" size="sm" className="h-9" onClick={() => setDay(latestDay)}>Latest day</Button>
          )}
          <span className="text-sm font-medium text-slate-700">{longDate(day)}</span>
          <span className="text-sm text-slate-500">· {rows.length} {rows.length === 1 ? "record" : "records"}</span>
          <Button variant="outline" size="sm" className="ml-auto h-9" disabled={!rows.length} onClick={() => onShowInTable(day)}>
            <Filter className="mr-2 h-4 w-4" /> Show in table
          </Button>
        </div>

        {rows.length > 0 && (
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            {[
              ["Total eggs", fmt(totals.eggs), "border-emerald-200 bg-emerald-50 text-emerald-800"],
              ["Feed used", `${fmt(Math.round(totals.feed * 100) / 100)} kg`, "border-amber-200 bg-amber-50 text-amber-800"],
              ["Deaths", fmt(totals.deaths), "border-red-200 bg-red-50 text-red-700"],
              ["Birds left", fmt(totals.left), "border-blue-200 bg-blue-50 text-blue-800"],
            ].map(([label, value, tone]) => (
              <div key={label} className={`rounded-lg border px-3 py-2 ${tone}`}>
                <div className="text-xs uppercase tracking-wider opacity-80">{label}</div>
                <div className="text-lg font-bold tabular-nums">{value}</div>
              </div>
            ))}
          </div>
        )}

        <div className="min-h-0 flex-1 overflow-auto rounded-lg border border-slate-200">
          {rows.length === 0 ? (
            <div className="p-10 text-center text-sm text-slate-500">No production records on this day.</div>
          ) : (
            <Table>
              <TableHeader className="sticky top-0 z-10 bg-blue-50">
                <TableRow className="border-b border-blue-200">
                  <TableHead>{firstHeader}</TableHead>
                  <TableHead>{secondHeader}</TableHead>
                  <TableHead className="text-right whitespace-nowrap bg-blue-100 font-semibold text-blue-900">1st Pick</TableHead>
                  <TableHead className="text-right whitespace-nowrap bg-orange-100 font-semibold text-orange-900">2nd Pick</TableHead>
                  <TableHead className="text-right whitespace-nowrap bg-purple-100 font-semibold text-purple-900">3rd Pick</TableHead>
                  {pickColumns.map((c) => <TableHead key={c.key} className="text-right whitespace-nowrap bg-teal-100 font-semibold text-teal-900">{c.header}</TableHead>)}
                  <TableHead className="text-right bg-red-50 font-semibold text-red-800">Brokens</TableHead>
                  <TableHead className="text-right">Total eggs</TableHead>
                  <TableHead className="text-right">Feed (kg)</TableHead>
                  <TableHead className="text-right">Birds</TableHead>
                  <TableHead className="text-right">Deaths</TableHead>
                  <TableHead className="text-right">Left</TableHead>
                  {statusCell && <TableHead>Status</TableHead>}
                  {canEdit && <TableHead className="w-10" />}
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((r, idx) => {
                  return (
                    <TableRow key={r.id} className={idx % 2 === 0 ? "bg-white hover:bg-slate-50/60" : "bg-slate-50/40 hover:bg-slate-50/60"}>
                      <TableCell className="whitespace-nowrap font-medium">{flockLabel(r)}</TableCell>
                      <TableCell className="whitespace-nowrap text-slate-600">{batchLabel(r)}</TableCell>
                      <TableCell className="text-right tabular-nums text-blue-700 bg-blue-50/40">{fmt(get(r, F.p1))}</TableCell>
                      <TableCell className="text-right tabular-nums text-orange-700 bg-orange-50/40">{fmt(get(r, F.p2))}</TableCell>
                      <TableCell className="text-right tabular-nums text-purple-700 bg-purple-50/40">{fmt(get(r, F.p3))}</TableCell>
                      {pickColumns.map((c) => <TableCell key={c.key} className="text-right tabular-nums text-teal-700 bg-teal-50/40">{fmt(get(r, c.key))}</TableCell>)}
                      <TableCell className="text-right tabular-nums text-red-700 bg-red-50/40">{fmt(get(r, F.broken))}</TableCell>
                      <TableCell className="text-right font-semibold tabular-nums">{fmt(get(r, F.eggs))}</TableCell>
                      <TableCell className="text-right tabular-nums">{fmt(get(r, F.feed))}</TableCell>
                      <TableCell className="text-right tabular-nums">{fmt(get(r, F.birds))}</TableCell>
                      <TableCell className="text-right">
                        <span className={get(r, F.deaths) > 0 ? "rounded bg-red-50 px-2 py-0.5 text-xs tabular-nums text-red-700" : "rounded bg-slate-50 px-2 py-0.5 text-xs tabular-nums text-slate-600"}>{fmt(get(r, F.deaths))}</span>
                      </TableCell>
                      <TableCell className="text-right tabular-nums">{fmt(leftOf(r))}</TableCell>
                      {statusCell && <TableCell className="whitespace-nowrap">{statusCell(r)}</TableCell>}
                      {canEdit && (
                        <TableCell>
                          <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => onEdit(r)} aria-label={`${editLabel} ${flockLabel(r)}`} title={editLabel}>
                            <Pencil className="h-3.5 w-3.5" />
                          </Button>
                        </TableCell>
                      )}
                    </TableRow>
                  )
                })}
              </TableBody>
              <TableFooter>
                <TableRow className="font-semibold">
                  <TableCell colSpan={2}>Total</TableCell>
                  <TableCell className="text-right tabular-nums text-blue-800 bg-blue-100/60">{fmt(totals.p9)}</TableCell>
                  <TableCell className="text-right tabular-nums text-orange-800 bg-orange-100/60">{fmt(totals.p12)}</TableCell>
                  <TableCell className="text-right tabular-nums text-purple-800 bg-purple-100/60">{fmt(totals.p4)}</TableCell>
                  {pickColumns.map((c) => <TableCell key={c.key} className="text-right tabular-nums text-teal-800 bg-teal-100/60">{fmt(totals.extra[c.key] || 0)}</TableCell>)}
                  <TableCell className="text-right tabular-nums text-red-800 bg-red-100/60">{fmt(totals.broken)}</TableCell>
                  <TableCell className="text-right tabular-nums">{fmt(totals.eggs)}</TableCell>
                  <TableCell className="text-right tabular-nums">{fmt(Math.round(totals.feed * 100) / 100)}</TableCell>
                  <TableCell className="text-right tabular-nums">{fmt(totals.birds)}</TableCell>
                  <TableCell className="text-right tabular-nums text-red-700">{fmt(totals.deaths)}</TableCell>
                  <TableCell className="text-right tabular-nums">{fmt(totals.left)}</TableCell>
                  {statusCell && <TableCell />}
                  {canEdit && <TableCell />}
                </TableRow>
              </TableFooter>
            </Table>
          )}
        </div>
      </DialogContent>
    </Dialog>
  )
}
