"use client"

import { useMemo, useState } from "react"
import { Bird } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Checkbox } from "@/components/ui/checkbox"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { safeDiv, type EggCostAnalysis, type FlockCostRow } from "@/lib/egg-cost/engine"
import { Section, num, pct, useMoney } from "./bits"

type SortKey = "name" | "saleable" | "feed" | "direct" | "full" | "directPerCrate" | "fullPerCrate" | "brokenRate" | "margin"

/** Laying flocks side by side on one cost definition and one period. */
export function FlockComparison({ a }: { a: EggCostAnalysis }) {
  const { money } = useMoney()
  const laying = useMemo(() => a.flocks.filter((r) => r.isLaying && r.inScope), [a])
  const [picked, setPicked] = useState<Set<number> | null>(null)
  const [sort, setSort] = useState<{ key: SortKey; dir: 1 | -1 }>({ key: "fullPerCrate", dir: 1 })
  const epc = a.eggsPerCrate
  const price = a.price.pricePerCrate

  const metric = (r: FlockCostRow, k: SortKey): number | string | null => {
    switch (k) {
      case "name": return r.name
      case "saleable": return r.saleable
      case "feed": return r.feed + r.directFeedExpense
      case "direct": return r.direct
      case "full": return r.full
      case "directPerCrate": { const e = safeDiv(r.direct, r.saleable); return e == null ? null : e * epc }
      case "fullPerCrate": { const e = safeDiv(r.full, r.saleable); return e == null ? null : e * epc }
      case "brokenRate": return safeDiv(r.broken, r.gross)
      case "margin": { const e = safeDiv(r.full, r.saleable); return e == null || price == null ? null : price - e * epc }
    }
  }
  const rows = laying
    .filter((r) => !picked || picked.has(r.flockId))
    .slice()
    .sort((x, y) => {
      const a1 = metric(x, sort.key), b1 = metric(y, sort.key)
      if (a1 == null) return 1
      if (b1 == null) return -1
      return (a1 < b1 ? -1 : a1 > b1 ? 1 : 0) * sort.dir
    })
  const incomplete = (r: FlockCostRow) => r.feedWithoutCostRecords > 0 || r.recordDays < r.activeLayingDays || r.preLay.status === "NoAssumption"
  const head = (k: SortKey, label: string, right = true) => (
    <TableHead className={right ? "text-right" : ""}>
      <button type="button" className="font-medium hover:text-sky-700" onClick={() => setSort((s) => ({ key: k, dir: s.key === k ? (s.dir === 1 ? -1 : 1) : 1 }))}>
        {label}{sort.key === k ? (sort.dir === 1 ? " ▲" : " ▼") : ""}
      </button>
    </TableHead>
  )

  return (
    <Section title="Flock comparison" icon={Bird}
      description={`Same period and cost definition for every flock. Margin uses ${price != null ? `the actual average price (${money(price)} a crate)` : "no price (no egg sales)"}.`}>
      {laying.length === 0 ? <p className="text-sm text-slate-500">No laying flocks in this selection.</p> : (
        <>
          {laying.length > 1 && (
            <div className="mb-3 flex flex-wrap gap-x-4 gap-y-1">
              {laying.map((r) => (
                <label key={r.flockId} className="flex items-center gap-1.5 text-xs text-slate-700">
                  <Checkbox checked={!picked || picked.has(r.flockId)} onCheckedChange={(v) => {
                    const next = new Set(picked ?? laying.map((x) => x.flockId))
                    if (v) next.add(r.flockId); else next.delete(r.flockId)
                    setPicked(next.size === laying.length ? null : next)
                  }} />
                  {r.name}
                </label>
              ))}
            </div>
          )}
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  {head("name", "Flock", false)}
                  <TableHead className="text-right">Avg birds</TableHead>
                  {head("saleable", "Saleable eggs")}
                  <TableHead className="text-right">Hen-day %</TableHead>
                  <TableHead className="text-right">Feed kg</TableHead>
                  {head("feed", "Feed cost")}
                  <TableHead className="text-right">Medication</TableHead>
                  <TableHead className="text-right">Labour</TableHead>
                  <TableHead className="text-right">Overhead</TableHead>
                  {head("direct", "Direct")}
                  {head("full", "Full")}
                  {head("directPerCrate", "Direct / crate")}
                  {head("fullPerCrate", "Full / crate")}
                  {head("brokenRate", "Broken %")}
                  {head("margin", "Margin / crate")}
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((r) => {
                  const hd = r.avgBirds && r.activeLayingDays ? safeDiv(r.gross, r.avgBirds * r.activeLayingDays) : null
                  const m = metric(r, "margin") as number | null
                  return (
                    <TableRow key={r.flockId}>
                      <TableCell className="font-medium">
                        {r.name}
                        <span className="block text-[11px] text-slate-500">{r.batchCode ?? "No batch"}</span>
                        {incomplete(r) && <Badge variant="outline" className="mt-0.5 border-amber-200 bg-amber-50 text-[10px] text-amber-900">Incomplete costs</Badge>}
                      </TableCell>
                      <TableCell className="text-right tabular-nums">{num(r.avgBirds)}</TableCell>
                      <TableCell className="text-right tabular-nums">{num(r.saleable)}</TableCell>
                      <TableCell className="text-right tabular-nums">{pct(hd)}</TableCell>
                      <TableCell className="text-right tabular-nums">{num(r.feedKg, 1)}</TableCell>
                      <TableCell className="text-right tabular-nums">{money(r.feed + r.directFeedExpense)}</TableCell>
                      <TableCell className="text-right tabular-nums">{money(r.medication + r.veterinary)}</TableCell>
                      <TableCell className="text-right tabular-nums">{money(r.labourDirect + r.labourAllocated)}</TableCell>
                      <TableCell className="text-right tabular-nums">{money(r.overheadAllocated + r.otherDirect + r.depreciationAllocated)}</TableCell>
                      <TableCell className="text-right tabular-nums">{money(r.direct)}</TableCell>
                      <TableCell className="text-right tabular-nums">{money(r.full)}</TableCell>
                      <TableCell className="text-right tabular-nums">{money(metric(r, "directPerCrate") as number | null)}</TableCell>
                      <TableCell className="text-right font-semibold tabular-nums">{money(metric(r, "fullPerCrate") as number | null)}</TableCell>
                      <TableCell className="text-right tabular-nums">{pct(metric(r, "brokenRate") as number | null)}</TableCell>
                      <TableCell className={`text-right tabular-nums ${m != null && m < 0 ? "text-rose-600" : ""}`}>{money(m)}</TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          </div>
          <p className="mt-2 text-xs text-slate-500">
            Flocks marked “Incomplete costs” are missing production records, feed costs or pre-laying assumptions, so they are not ranked as definitively cheaper.
            Hen-day % = eggs ÷ (average birds × laying days).
          </p>
        </>
      )}
    </Section>
  )
}
