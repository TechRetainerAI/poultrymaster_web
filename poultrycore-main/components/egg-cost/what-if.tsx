"use client"

import { useMemo } from "react"
import { FlaskConical, RotateCcw } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Slider } from "@/components/ui/slider"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { NEUTRAL_SCENARIO, runScenario, type EggCostAnalysis, type ScenarioInputs, type ScenarioResult } from "@/lib/egg-cost/engine"
import { Kpi, Section, num, pct, useMoney } from "./bits"

const SLIDERS: { key: keyof ScenarioInputs; label: string; min: number; max: number }[] = [
  { key: "feedPricePct", label: "Feed price", min: -50, max: 100 },
  { key: "feedQuantityPct", label: "Feed eaten", min: -50, max: 50 },
  { key: "eggOutputPct", label: "Egg production", min: -50, max: 50 },
  { key: "birdsPct", label: "Productive birds", min: -50, max: 50 },
  { key: "medicationPct", label: "Medication cost", min: -50, max: 100 },
  { key: "labourPct", label: "Labour cost", min: -50, max: 100 },
  { key: "overheadPct", label: "Utilities & overhead", min: -50, max: 100 },
  { key: "depreciationPct", label: "Depreciation", min: -100, max: 100 },
  { key: "preLayPoolPct", label: "Pre-laying cost", min: -50, max: 100 },
  { key: "expectedLifetimeEggsPct", label: "Expected lifetime eggs", min: -50, max: 50 },
]

export function useScenario(base: EggCostAnalysis | null, inputs: ScenarioInputs): ScenarioResult | null {
  return useMemo(() => (base ? runScenario(base, inputs) : null), [base, inputs])
}

/** Hypothetical only: changes here never post or alter anything. */
export function WhatIfPanel({ base, inputs, onChange, view }: {
  base: EggCostAnalysis; inputs: ScenarioInputs; onChange: (s: ScenarioInputs) => void; view: "direct" | "full"
}) {
  const { money } = useMoney()
  const s = useScenario(base, inputs)!
  const set = (k: keyof ScenarioInputs, v: number | null) => onChange({ ...inputs, [k]: v })
  const basePer = view === "direct" ? base.directPerCrate : base.fullPerCrate
  const scenPer = view === "direct" ? s.directPerCrate : s.fullPerCrate
  const lossNow = base.gross > 0 ? ((base.gross - base.saleable) / base.gross) * 100 : 0

  return (
    <div className="space-y-4">
      <div className="rounded-md border border-violet-200 bg-violet-50 px-3 py-2 text-sm text-violet-900">
        <strong>Hypothetical scenario.</strong> Starts from the recorded analysis of this period and selection. Nothing here changes your records, stock, expenses or P&amp;L.
      </div>
      {!s.valid && <ul className="rounded-md border border-rose-200 bg-rose-50 px-3 py-2 text-sm text-rose-800">{s.errors.map((e) => <li key={e}>{e}</li>)}</ul>}

      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Kpi label="Simulated cost / crate" value={money(scenPer)} tone="violet" emphasis
          sub={basePer != null && scenPer != null ? `${scenPer >= basePer ? "+" : ""}${money(scenPer - basePer)} vs recorded ${money(basePer)}` : undefined} />
        <Kpi label="Simulated margin / crate" value={money(s.marginPerCrate)} tone={s.marginPerCrate != null && s.marginPerCrate < 0 ? "rose" : "emerald"}
          sub={s.marginPct != null ? `${pct(s.marginPct)} of ${money(s.pricePerCrate)}` : "Enter a selling price"} />
        <Kpi label="Simulated break-even" value={money(s.breakEvenPerCrate)} tone="amber" sub="Full cost per crate" />
        <Kpi label="Period margin change" value={pct(s.periodMarginChangePct)} tone="sky"
          sub={s.periodMargin != null ? `${money(s.periodMargin)} over ${num(s.saleableCrates, 0)} crates` : undefined} />
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <Section title="Adjust the assumptions" icon={FlaskConical}
          actions={<Button size="sm" variant="outline" onClick={() => onChange(NEUTRAL_SCENARIO)}><RotateCcw className="mr-1 h-3.5 w-3.5" />Reset</Button>}>
          <div className="space-y-3">
            {SLIDERS.map((d) => {
              const v = inputs[d.key] as number
              return (
                <div key={d.key} className="grid grid-cols-[9rem_1fr_4.5rem] items-center gap-3">
                  <Label className="text-xs">{d.label}</Label>
                  <Slider min={d.min} max={d.max} step={1} value={[v]} onValueChange={([x]) => set(d.key, x)} />
                  <div className="flex items-center gap-1">
                    <Input className="h-7 px-1.5 text-right text-xs" type="number" value={v}
                      onChange={(e) => set(d.key, e.target.value === "" ? 0 : Number(e.target.value))} />
                    <span className="text-xs text-slate-500">%</span>
                  </div>
                </div>
              )
            })}
            <div className="grid grid-cols-[9rem_1fr] items-center gap-3">
              <Label htmlFor="wi-loss" className="text-xs">Broken / lost eggs %</Label>
              <Input id="wi-loss" type="number" min={0} max={99} step="0.1" className="h-8"
                placeholder={`Recorded ${lossNow.toFixed(1)}%`} value={inputs.lossRatePct ?? ""}
                onChange={(e) => set("lossRatePct", e.target.value === "" ? null : Number(e.target.value))} />
            </div>
            <div className="grid grid-cols-[9rem_1fr] items-center gap-3">
              <Label htmlFor="wi-price" className="text-xs">Selling price / crate</Label>
              <Input id="wi-price" type="number" min={0} step="0.01" className="h-8"
                placeholder={base.price.pricePerCrate != null ? `Actual ${base.price.pricePerCrate.toFixed(2)}` : "No sales -- enter a price"}
                value={inputs.sellingPricePerCrate ?? ""}
                onChange={(e) => set("sellingPricePerCrate", e.target.value === "" ? null : Number(e.target.value))} />
            </div>
          </div>
        </Section>

        <Section title="Recorded vs simulated" description="Every simulated figure is hypothetical.">
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow><TableHead>Item</TableHead><TableHead className="text-right">Recorded</TableHead><TableHead className="text-right">Simulated</TableHead></TableRow>
              </TableHeader>
              <TableBody>
                <TableRow><TableCell>Saleable eggs</TableCell><TableCell className="text-right tabular-nums">{num(base.saleable)}</TableCell><TableCell className="text-right tabular-nums">{num(s.saleable)}</TableCell></TableRow>
                {s.components.filter((c) => c.baseline || c.scenario).map((c) => (
                  <TableRow key={c.key}>
                    <TableCell>{c.label}</TableCell>
                    <TableCell className="text-right tabular-nums">{money(c.baseline)}</TableCell>
                    <TableCell className={`text-right tabular-nums ${Math.abs(c.scenario - c.baseline) > 0.005 ? "font-semibold text-violet-700" : ""}`}>{money(c.scenario)}</TableCell>
                  </TableRow>
                ))}
                <TableRow className="bg-slate-50 font-semibold">
                  <TableCell>{view === "direct" ? "Direct" : "Full"} cost / crate</TableCell>
                  <TableCell className="text-right tabular-nums">{money(basePer)}</TableCell>
                  <TableCell className="text-right tabular-nums text-violet-700">{money(scenPer)}</TableCell>
                </TableRow>
              </TableBody>
            </Table>
          </div>
        </Section>
      </div>
    </div>
  )
}
