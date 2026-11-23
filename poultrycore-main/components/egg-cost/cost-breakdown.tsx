"use client"

import { useMemo } from "react"
import { Cell, Pie, PieChart, ResponsiveContainer, Tooltip } from "recharts"
import { Layers, Search } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { cn } from "@/lib/utils"
import { safeDiv, type EggCostAnalysis, type SourceRow } from "@/lib/egg-cost/engine"
import { CLASS_TONE, Section, pct, useMoney } from "./bits"

const COLORS = ["#0ea5e9", "#10b981", "#f59e0b", "#8b5cf6", "#ef4444", "#14b8a6", "#6366f1", "#84cc16", "#f97316", "#64748b", "#ec4899"]

export function CostBreakdown({ a, view, onDrill }: { a: EggCostAnalysis; view: "direct" | "full"; onDrill: (key: string, label: string) => void }) {
  const { money, perEgg } = useMoney()
  const lines = useMemo(() => a.components.filter((c) => (view === "direct" ? c.inDirect : c.inFull)), [a, view])
  const total = view === "direct" ? a.directTotal : a.fullTotal
  const extra = a.components.filter((c) => !(view === "direct" ? c.inDirect : c.inFull) && c.amount !== 0)
  const chart = lines.filter((c) => c.amount > 0).map((c, i) => ({ name: c.label, value: c.amount, key: c.key, color: COLORS[i % COLORS.length] }))

  return (
    <Section
      title={view === "direct" ? "Direct production cost" : "Full production cost"}
      description="Click a line to see the records behind it."
      icon={Layers}
    >
      <div className="grid gap-4 lg:grid-cols-[1fr_240px]">
        <div className="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Category</TableHead>
                <TableHead className="text-right">Cost</TableHead>
                <TableHead className="text-right">Per egg</TableHead>
                <TableHead className="text-right">Per crate</TableHead>
                <TableHead className="text-right">Share</TableHead>
                <TableHead>Basis</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {lines.map((c) => {
                const e = safeDiv(c.amount, a.saleable)
                return (
                  <TableRow key={c.key} className="cursor-pointer hover:bg-sky-50/60" onClick={() => onDrill(c.key, c.label)}>
                    <TableCell className="font-medium text-slate-800">
                      <span className="flex items-center gap-1.5">{c.label}<Search className="h-3 w-3 text-slate-400" /></span>
                      {c.note && <span className="block text-[11px] font-normal text-slate-500">{c.note}</span>}
                    </TableCell>
                    <TableCell className="text-right tabular-nums">{money(c.amount)}</TableCell>
                    <TableCell className="text-right tabular-nums">{perEgg(e)}</TableCell>
                    <TableCell className="text-right tabular-nums">{money(e == null ? null : e * a.eggsPerCrate)}</TableCell>
                    <TableCell className="text-right tabular-nums">{pct(safeDiv(c.amount, total))}</TableCell>
                    <TableCell><Badge variant="outline" className={cn("text-[11px]", CLASS_TONE[c.classification])}>{c.classification}</Badge></TableCell>
                  </TableRow>
                )
              })}
              <TableRow className="bg-slate-50 font-semibold">
                <TableCell>Total</TableCell>
                <TableCell className="text-right tabular-nums">{money(total)}</TableCell>
                <TableCell className="text-right tabular-nums">{perEgg(safeDiv(total, a.saleable))}</TableCell>
                <TableCell className="text-right tabular-nums">{money(view === "direct" ? a.directPerCrate : a.fullPerCrate)}</TableCell>
                <TableCell className="text-right">100%</TableCell>
                <TableCell />
              </TableRow>
            </TableBody>
          </Table>
          {extra.length > 0 && (
            <p className="mt-2 text-xs text-slate-500">
              Not in this view: {extra.map((c) => `${c.label} ${money(c.amount)}`).join(" · ")}
              {view === "direct" ? " (part of the full cost)." : " (packaged cost only)."}
            </p>
          )}
        </div>
        <div className="h-56 min-w-0">
          {chart.length > 0 ? (
            <ResponsiveContainer width="100%" height="100%">
              <PieChart>
                <Pie data={chart} dataKey="value" nameKey="name" innerRadius={52} outerRadius={90} paddingAngle={1}
                  onClick={(d: any) => d?.payload?.key && onDrill(d.payload.key, d.payload.name)} className="cursor-pointer">
                  {chart.map((d) => <Cell key={d.key} fill={d.color} />)}
                </Pie>
                <Tooltip formatter={(v: number) => money(v)} />
              </PieChart>
            </ResponsiveContainer>
          ) : <p className="pt-16 text-center text-sm text-slate-500">No cost recorded.</p>}
        </div>
      </div>
    </Section>
  )
}

export function DrilldownDialog({ open, title, rows, onOpenChange }: {
  open: boolean; title: string; rows: SourceRow[]; onOpenChange: (o: boolean) => void
}) {
  const { money, perEgg } = useMoney()
  const total = rows.reduce((s, r) => s + r.amount, 0)
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[85vh] max-w-4xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>
            The records behind this figure. Shared costs show the original amount and the share that falls on this selection.
          </DialogDescription>
        </DialogHeader>
        {rows.length === 0 ? <p className="text-sm text-slate-500">No records.</p> : (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Date</TableHead><TableHead>Flock</TableHead><TableHead>Source</TableHead>
                  <TableHead>Description</TableHead><TableHead className="text-right">Qty</TableHead>
                  <TableHead className="text-right">Unit cost</TableHead><TableHead className="text-right">Amount</TableHead><TableHead>Type</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((r, i) => (
                  <TableRow key={i}>
                    <TableCell className="whitespace-nowrap">{r.date ? r.date.slice(0, 10) : "—"}</TableCell>
                    <TableCell>{r.flock}</TableCell>
                    <TableCell className="text-xs text-slate-600">{r.reference}</TableCell>
                    <TableCell className="max-w-[18rem] text-sm">
                      {r.description}
                      {r.formula && <span className="block text-[11px] text-slate-500">{r.formula}</span>}
                    </TableCell>
                    <TableCell className="text-right tabular-nums">{r.quantity}</TableCell>
                    <TableCell className="text-right tabular-nums">{r.unitCost == null ? "" : perEgg(r.unitCost)}</TableCell>
                    <TableCell className="text-right tabular-nums">{money(r.amount)}</TableCell>
                    <TableCell><Badge variant="outline" className={cn("text-[11px]", CLASS_TONE[r.classification])}>{r.classification}</Badge></TableCell>
                  </TableRow>
                ))}
                <TableRow className="bg-slate-50 font-semibold">
                  <TableCell colSpan={6}>Total ({rows.length} record{rows.length === 1 ? "" : "s"})</TableCell>
                  <TableCell className="text-right tabular-nums">{money(total)}</TableCell>
                  <TableCell />
                </TableRow>
              </TableBody>
            </Table>
          </div>
        )}
        <div className="flex justify-end"><Button variant="outline" onClick={() => onOpenChange(false)}>Close</Button></div>
      </DialogContent>
    </Dialog>
  )
}
