"use client"

// Egg size composition and unsorted carryover (Egg Sorting Workspace).
//
// Honesty rules, enforced by the API and repeated here so nobody misreads the
// table: "By pick" uses only sortings recorded pick by pick; a combined
// sorting is never attributed to a pick. Other groupings share a combined
// sorting across its source days by quantity, and say how many they include.

import { useCallback, useEffect, useMemo, useState } from "react"
import { Loader2 } from "lucide-react"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import {
  getEggCarryover,
  getEggComposition,
  type CompositionGroupBy,
  type EggCarryoverRow,
  type EggCompositionRow,
} from "@/lib/api/egg-sorting"
import { fmtCount, lineTypeLabel, pct } from "@/lib/production/egg-sorting"
import { formatLongDate } from "@/lib/closing/daily-closing"
import { usePagination } from "@/hooks/use-pagination"
import { DataPagination } from "@/components/ui/data-pagination"

const GROUPS: { key: CompositionGroupBy; label: string }[] = [
  { key: "productiondate", label: "Production date" },
  { key: "sortingdate", label: "Sorting date" },
  { key: "flock", label: "Flock" },
  { key: "batch", label: "Batch" },
  { key: "age", label: "Flock age (weeks)" },
  { key: "pick", label: "Pick" },
]

export function CompositionReport({ from: initialFrom, to: initialTo, flockId }: { from: string; to: string; flockId: number | null }) {
  const [from, setFrom] = useState(initialFrom)
  const [to, setTo] = useState(initialTo)
  const [groupBy, setGroupBy] = useState<CompositionGroupBy>("productiondate")
  const [rows, setRows] = useState<EggCompositionRow[] | null>(null)
  const [carry, setCarry] = useState<EggCarryoverRow[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    setRows(null); setCarry(null); setError(null)
    try {
      const [c, k] = await Promise.all([getEggComposition(from, to, groupBy, flockId), getEggCarryover(from, to, flockId)])
      setRows(c); setCarry(k)
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not load the report.")
    }
  }, [from, to, groupBy, flockId])
  useEffect(() => { void load() }, [load])

  // Columns: sizes in their order, then loss types.
  const columns = useMemo(() => {
    const m = new Map<string, { key: string; label: string; sort: number; loss: boolean }>()
    for (const r of rows ?? []) {
      const key = r.lineType === "SizedOutput" ? `s${r.eggSizeId}` : r.lineType
      if (!m.has(key)) m.set(key, { key, label: lineTypeLabel(r.lineType, r.sizeName), sort: r.lineType === "SizedOutput" ? r.sizeSort : 100000 + key.length, loss: r.lineType !== "SizedOutput" })
    }
    return [...m.values()].sort((a, b) => a.sort - b.sort)
  }, [rows])

  const groups = useMemo(() => {
    const m = new Map<string, { key: string; label: string; sort: string; total: number; cells: Record<string, number>; combined: number }>()
    for (const r of rows ?? []) {
      const g = m.get(r.groupKey) ?? { key: r.groupKey, label: r.groupLabel, sort: r.groupSort, total: 0, cells: {}, combined: 0 }
      const col = r.lineType === "SizedOutput" ? `s${r.eggSizeId}` : r.lineType
      g.cells[col] = (g.cells[col] ?? 0) + Number(r.quantity)
      g.total += Number(r.quantity)
      g.combined = Math.max(g.combined, r.combinedSessions)
      m.set(r.groupKey, g)
    }
    return [...m.values()].sort((a, b) => groupBy.endsWith("date") ? b.sort.localeCompare(a.sort) : a.sort.localeCompare(b.sort, undefined, { numeric: true }))
  }, [rows, groupBy])

  const anyCombined = groups.some((g) => g.combined > 0)
  const groupsPg = usePagination(groups, 10)
  const carryPg = usePagination(carry ?? [], 10)

  return (
    <div className="space-y-4">
      <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
        <CardContent className="grid grid-cols-1 gap-3 p-4 sm:grid-cols-3">
          <div className="space-y-1">
            <Label className="text-xs text-slate-500">From</Label>
            <Input type="date" value={from} max={to} onChange={(e) => setFrom(e.target.value)} />
          </div>
          <div className="space-y-1">
            <Label className="text-xs text-slate-500">To</Label>
            <Input type="date" value={to} min={from} onChange={(e) => setTo(e.target.value)} />
          </div>
          <div className="space-y-1">
            <Label className="text-xs text-slate-500">Size composition by</Label>
            <Select value={groupBy} onValueChange={(v) => setGroupBy(v as CompositionGroupBy)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>{GROUPS.map((g) => <SelectItem key={g.key} value={g.key}>{g.label}</SelectItem>)}</SelectContent>
            </Select>
          </div>
        </CardContent>
      </Card>

      {error && <Card className="border-rose-200 bg-rose-50"><CardContent className="p-4 text-sm text-rose-800">{error}</CardContent></Card>}
      {!rows && !error && <p className="flex items-center gap-2 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</p>}

      {rows && (
        <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
          <CardContent className="p-0">
            <div className="border-b border-slate-100 px-4 py-3 text-xs text-slate-600">
              {groupBy === "pick"
                ? "Only sortings recorded pick by pick are counted here. Eggs sorted as a combined pool are left out, because their sizes cannot honestly be attributed to one pick."
                : anyCombined
                  ? "Includes combined sortings, shared across their source days by quantity. Percentages are of all eggs sorted in the group, losses included."
                  : "Percentages are of all eggs sorted in the group, losses included."}
            </div>
            <div className="overflow-x-auto">
              <table className="w-full min-w-[40rem] text-sm">
                <thead className="bg-slate-50 text-left text-xs uppercase tracking-wider text-slate-500">
                  <tr>
                    <th className="px-3 py-2 font-medium">{GROUPS.find((g) => g.key === groupBy)?.label}</th>
                    {columns.map((c) => <th key={c.key} className={`px-3 py-2 text-right font-medium ${c.loss ? "text-rose-700" : ""}`}>{c.label}</th>)}
                    <th className="px-3 py-2 text-right font-medium">Sorted</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {groups.length === 0 && (
                    <tr><td colSpan={columns.length + 2} className="px-3 py-4 text-slate-500">No posted sorting in this period.</td></tr>
                  )}
                  {groupsPg.pageItems.map((g) => (
                    <tr key={g.key}>
                      <td className="px-3 py-2 font-medium text-slate-900">
                        {g.label}
                        {g.combined > 0 && groupBy !== "pick" && <span className="ml-1.5 rounded bg-slate-100 px-1.5 py-0.5 text-[10px] text-slate-600">incl. combined</span>}
                      </td>
                      {columns.map((c) => (
                        <td key={c.key} className="px-3 py-2 text-right tabular-nums">
                          {g.cells[c.key] ? (
                            <>
                              <div className="font-medium">{pct(g.cells[c.key], g.total)}</div>
                              <div className="text-[11px] text-slate-500">{fmtCount(g.cells[c.key])}</div>
                            </>
                          ) : <span className="text-slate-300">—</span>}
                        </td>
                      ))}
                      <td className="px-3 py-2 text-right font-semibold tabular-nums">{fmtCount(g.total)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="border-t border-slate-100 px-3 py-2">
              <DataPagination {...groupsPg.paginationProps} />
            </div>
          </CardContent>
        </Card>
      )}

      {carry && (
        <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
          <CardContent className="p-0">
            <div className="border-b border-slate-100 px-4 py-3">
              <div className="font-semibold text-slate-900">Unsorted carryover</div>
              <p className="text-xs text-slate-600">
                Per production date: saleable eggs (collected less broken, meaty, soft and lost) = sorted + still unsorted.
                Eggs sold or used unsorted also show as unsorted here.
              </p>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full min-w-[36rem] text-sm">
                <thead className="bg-slate-50 text-left text-xs uppercase tracking-wider text-slate-500">
                  <tr>
                    <th className="px-3 py-2 font-medium">Production date</th>
                    <th className="px-3 py-2 text-right font-medium">Collected</th>
                    <th className="px-3 py-2 text-right font-medium">Collection loss</th>
                    <th className="px-3 py-2 text-right font-medium">Saleable</th>
                    <th className="px-3 py-2 text-right font-medium">Sorted</th>
                    <th className="px-3 py-2 text-right font-medium">Not sorted</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {carry.length === 0 && <tr><td colSpan={6} className="px-3 py-4 text-slate-500">No production in this period.</td></tr>}
                  {carryPg.pageItems.map((c) => (
                    <tr key={c.productionDate}>
                      <td className="px-3 py-2">{formatLongDate(c.productionDate.slice(0, 10))}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{fmtCount(c.gross)}</td>
                      <td className="px-3 py-2 text-right tabular-nums text-rose-700">{c.collectionLoss ? fmtCount(c.collectionLoss) : "—"}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{fmtCount(c.saleable)}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{fmtCount(c.sorted)} <span className="text-xs text-slate-500">({pct(c.sorted, c.saleable)})</span></td>
                      <td className="px-3 py-2 text-right font-medium tabular-nums">{fmtCount(c.leftUnsorted)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="border-t border-slate-100 px-3 py-2">
              <DataPagination {...carryPg.paginationProps} />
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  )
}
