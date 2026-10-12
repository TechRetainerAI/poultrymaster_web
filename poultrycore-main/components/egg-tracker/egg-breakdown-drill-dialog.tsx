"use client"

// What is behind one line of the Egg tracker's Breakdown ("Sales 1,240"):
// every ledger movement of that kind, the way the Profit & Loss drilldown lists
// the records behind a figure. Coloured by direction -- green for eggs in, red
// for eggs out -- so the dialog reads as the card it was opened from.
//
// It reads the SAME rows the breakdown counted, so the dialog's total is the
// figure that was clicked, to the egg.

import { useEffect, useMemo, useState } from "react"
import { Search, X } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { cn, formatDateShort } from "@/lib/utils"
import type { FlowBucket } from "@/lib/cash/cash-flow"
import type { EggLedgerRow } from "@/lib/utils/egg-ledger"
import { cratesText } from "@/lib/production/egg-sorting"

export interface EggDrill {
  bucket: FlowBucket
  direction: "in" | "out"
}

const TONES = {
  in: {
    band: "bg-emerald-50 text-emerald-900 border-emerald-200", amount: "text-emerald-700",
    rail: "border-l-emerald-400", divide: "divide-emerald-200", row: "border-emerald-200", label: "Eggs in",
  },
  out: {
    band: "bg-rose-50 text-rose-900 border-rose-200", amount: "text-rose-700",
    rail: "border-l-rose-400", divide: "divide-rose-200", row: "border-rose-200", label: "Eggs out",
  },
} as const

/** The rows a bucket counted: same key (the type, or "Other") and same side. */
export function rowsForBucket(rows: EggLedgerRow[], drill: EggDrill): EggLedgerRow[] {
  return rows
    .filter((r) => ((r.type ?? "").trim() || "Other") === drill.bucket.key)
    .filter((r) => (drill.direction === "in" ? r.in : r.out) > 0)
    .sort((a, b) => b.seq - a.seq)                 // newest first
}

export function EggBreakdownDrillDialog({
  drill, rows, onClose,
}: {
  drill: EggDrill | null
  /** The whole egg ledger; the dialog picks out the bucket's rows. */
  rows: EggLedgerRow[]
  onClose: () => void
}) {
  const [query, setQuery] = useState("")
  useEffect(() => { setQuery("") }, [drill])

  const all = useMemo(() => (drill ? rowsForBucket(rows, drill) : []), [rows, drill])
  const qty = (r: EggLedgerRow) => (drill?.direction === "in" ? r.in : r.out)
  const shown = useMemo(() => {
    const q = query.trim().toLowerCase()
    if (!q) return all
    return all.filter((r) => `${r.date} ${formatDateShort(r.date)} ${r.description} ${r.type}`.toLowerCase().includes(q))
  }, [all, query])
  const shownTotal = shown.reduce((s, r) => s + qty(r), 0)
  const filtered = query.trim().length > 0

  const tone = TONES[drill?.direction ?? "in"]

  return (
    <Dialog open={!!drill} onOpenChange={(o) => { if (!o) onClose() }}>
      <DialogContent className="w-[95vw] sm:max-w-3xl">
        <DialogHeader className={cn("-m-6 mb-0 space-y-1 border-b p-6", tone.band)}>
          <DialogTitle className="flex flex-wrap items-baseline gap-x-2 gap-y-1 pr-6 text-left">
            <span className="min-w-0 break-words">{drill?.bucket.label}</span>
            <Badge variant="outline" className={cn("border-current/30 bg-white/60 text-[10px] font-medium", tone.amount)}>
              {tone.label}
            </Badge>
            <span className={cn("ml-auto text-sm font-semibold tabular-nums", tone.amount)}>
              {(drill?.bucket.amount ?? 0).toLocaleString()} eggs
            </span>
          </DialogTitle>
          <p className="text-left text-xs opacity-80">
            Every {drill?.direction === "in" ? "movement that added eggs" : "movement that took eggs out"} of this kind,
            newest first — {all.length} {all.length === 1 ? "entry" : "entries"}
            {drill ? ` (${cratesText(drill.bucket.amount)})` : ""}.
          </p>
        </DialogHeader>

        {all.length === 0 ? (
          <p className="py-8 text-center text-sm text-slate-500">Nothing behind this figure.</p>
        ) : (
          <>
            <div className="relative">
              <Search className="pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
              <Input
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder={`Filter these ${all.length} entries…`}
                className="h-9 pl-8 pr-8"
              />
              {filtered && (
                <button type="button" onClick={() => setQuery("")} aria-label="Clear filter"
                  className="absolute right-2 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600">
                  <X className="h-4 w-4" />
                </button>
              )}
            </div>

            {filtered && shown.length === 0 && (
              <p className="py-6 text-center text-sm text-slate-500">Nothing here matches “{query}”.</p>
            )}

            <div className="-mx-2 max-h-[55vh] overflow-y-auto px-2 sm:mx-0 sm:max-h-[60vh] sm:px-0">
              {/* Phone: one entry per block. */}
              <ul className={cn("divide-y sm:hidden", tone.divide)}>
                {shown.map((r) => (
                  <li key={r.sortKey} className={cn("border-l-2 py-3 pl-2", tone.rail)}>
                    <div className="flex items-baseline justify-between gap-3">
                      <span className="text-xs font-medium uppercase tracking-wide text-slate-500">{formatDateShort(r.date)}</span>
                      <span className={cn("shrink-0 text-sm font-semibold tabular-nums", tone.amount)}>
                        {drill?.direction === "in" ? "+" : "−"}{qty(r).toLocaleString()}
                      </span>
                    </div>
                    <div className="mt-1 break-words text-sm text-slate-900">{r.description || "—"}</div>
                    <div className="text-[11px] text-slate-500">Stock after: {r.balance.toLocaleString()}</div>
                  </li>
                ))}
              </ul>

              {/* Desktop: columns that line up, headings that stay put. */}
              <Table className="hidden table-fixed sm:table">
                <TableHeader className="sticky top-0 z-10 bg-white">
                  <TableRow className={tone.row}>
                    <TableHead className="w-[116px]">Date</TableHead>
                    <TableHead>Detail</TableHead>
                    <TableHead className="w-[110px] text-right">Eggs</TableHead>
                    <TableHead className="w-[120px] text-right">Stock after</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {shown.map((r) => (
                    <TableRow key={r.sortKey} className={cn("[&>td]:align-top", tone.row)}>
                      <TableCell className="whitespace-nowrap text-sm text-slate-500">{formatDateShort(r.date)}</TableCell>
                      <TableCell className="whitespace-normal break-words text-sm">{r.description || "—"}</TableCell>
                      <TableCell className={cn("text-right text-sm font-medium tabular-nums", tone.amount)}>
                        {drill?.direction === "in" ? "+" : "−"}{qty(r).toLocaleString()}
                      </TableCell>
                      <TableCell className="text-right text-sm tabular-nums text-slate-500">{r.balance.toLocaleString()}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>

            <div className={cn("flex items-baseline justify-between border-t pt-3 text-sm", tone.row)}>
              <span className="text-slate-500">
                {filtered ? `${shown.length} of ${all.length} entries shown` : `${all.length} ${all.length === 1 ? "entry" : "entries"}`}
              </span>
              <span className={cn("font-semibold tabular-nums", tone.amount)}>
                {shownTotal.toLocaleString()} eggs
                {filtered && <span className="ml-1 font-normal text-slate-500">of {(drill?.bucket.amount ?? 0).toLocaleString()}</span>}
              </span>
            </div>
          </>
        )}
      </DialogContent>
    </Dialog>
  )
}
