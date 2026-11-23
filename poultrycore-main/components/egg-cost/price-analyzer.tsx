"use client"

import { useState } from "react"
import { Calculator, Tag } from "lucide-react"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import {
  breakageEffect, margin, maxFeedCost, targetPrice, targetProduction, type EggCostAnalysis,
} from "@/lib/egg-cost/engine"
import { Section, num, pct, useMoney } from "./bits"

const n = (s: string) => (s.trim() === "" ? NaN : Number(s))

/** "Am I selling above my production cost?" -- three prices, never mixed. */
export function PriceAnalyzer({ a, view }: { a: EggCostAnalysis; view: "direct" | "full" }) {
  const { money } = useMoney()
  const cost = view === "direct" ? a.directPerCrate : a.fullPerCrate
  const [hypo, setHypo] = useState("")
  const [target, setTarget] = useState("25")
  const actual = a.price.pricePerCrate
  const row = (label: string, price: number | null, note: string) => {
    const m = price != null && cost != null ? margin(cost, price) : null
    return (
      <TableRow key={label}>
        <TableCell className="font-medium">{label}<span className="block text-[11px] font-normal text-slate-500">{note}</span></TableCell>
        <TableCell className="text-right tabular-nums">{money(price)}</TableCell>
        <TableCell className={`text-right tabular-nums ${m && m.margin < 0 ? "text-rose-600" : ""}`}>{money(m?.margin)}</TableCell>
        <TableCell className="text-right tabular-nums">{pct(m?.marginPct)}</TableCell>
        <TableCell className="text-right tabular-nums">{pct(m?.markupPct)}</TableCell>
      </TableRow>
    )
  }
  const t = cost != null && Number.isFinite(n(target)) ? targetPrice(cost, n(target)) : null

  return (
    <Section title="Selling price & margin" icon={Tag}
      description={`Against the ${view === "direct" ? "direct" : "full"} cost of ${money(cost)} a crate. This is an estimated PRODUCTION margin, not realised profit: crates sold this period may have been laid earlier.`}>
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Price</TableHead><TableHead className="text-right">Per crate</TableHead>
              <TableHead className="text-right">Margin / crate</TableHead><TableHead className="text-right">Margin %</TableHead>
              <TableHead className="text-right">Markup %</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {row("Actual average", actual, a.price.eggsSold > 0 ? `${a.price.basis}: ${num(a.price.eggsSold)} eggs for ${money(a.price.revenue)}` : "No egg sales in this period")}
            {row("Your price", Number.isFinite(n(hypo)) ? n(hypo) : null, "Hypothetical -- type a price below")}
            {row("Break-even", cost, "Price at which the margin is zero")}
          </TableBody>
        </Table>
      </div>
      <div className="mt-3 grid gap-3 sm:grid-cols-3">
        <div className="space-y-1">
          <Label htmlFor="ec-hypo" className="text-xs">Your price per crate</Label>
          <Input id="ec-hypo" type="number" min={0} step="0.01" value={hypo} onChange={(e) => setHypo(e.target.value)} placeholder="e.g. 55" />
        </div>
        <div className="space-y-1">
          <Label htmlFor="ec-target" className="text-xs">Target margin %</Label>
          <Input id="ec-target" type="number" min={0} max={99} step="1" value={target} onChange={(e) => setTarget(e.target.value)} />
        </div>
        <div className="rounded-md border border-sky-100 bg-sky-50 p-2 text-sm">
          <p className="text-xs text-slate-600">Price needed</p>
          <p className="font-semibold tabular-nums text-slate-900">{money(t?.byMargin)} <span className="text-xs font-normal text-slate-500">for {target || 0}% margin on price</span></p>
          <p className="tabular-nums text-slate-700">{money(t?.byMarkup)} <span className="text-xs text-slate-500">for {target || 0}% markup on cost</span></p>
        </div>
      </div>
      {a.price.bySize.length > 1 && (
        <div className="mt-4">
          <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-slate-500">Actual price by egg size</p>
          <div className="flex flex-wrap gap-2">
            {a.price.bySize.map((s) => (
              <div key={s.size} className="rounded-md border border-slate-200 px-2.5 py-1.5 text-xs">
                <span className="font-medium text-slate-800">{s.size}</span> · {money(s.pricePerCrate)} a crate · {num(s.eggs)} eggs
              </div>
            ))}
          </div>
          <p className="mt-1 text-[11px] text-slate-500">Every size carries the same production cost per egg: no size is cheaper to lay just because it sells for less.</p>
        </div>
      )}
    </Section>
  )
}

/** Decision calculators: each states its assumptions. */
export function ReverseCalculators({ a, view }: { a: EggCostAnalysis; view: "direct" | "full" }) {
  const { money } = useMoney()
  const epc = a.eggsPerCrate
  const total = view === "direct" ? a.directTotal : a.fullTotal
  const [planned, setPlanned] = useState(String(Math.round(total)))
  const [targetCpc, setTargetCpc] = useState("")
  const [eggs, setEggs] = useState(String(a.saleable))
  const [other, setOther] = useState(String(Math.round(total - a.feedTotal)))
  const [desired, setDesired] = useState("")
  const grossBrokenPct = a.gross > 0 ? ((a.gross - a.saleable) / a.gross) * 100 : 5
  const [fromPct, setFromPct] = useState(grossBrokenPct.toFixed(1))
  const [toPct, setToPct] = useState("2")

  const tp = Number.isFinite(n(planned)) && n(targetCpc) > 0 ? targetProduction(n(planned), n(targetCpc), epc) : null
  const mf = n(eggs) > 0 && Number.isFinite(n(other)) && n(desired) > 0 ? maxFeedCost(n(eggs), n(other), n(desired), epc) : null
  const be = a.gross > 0 && n(fromPct) >= 0 && n(fromPct) < 100 && n(toPct) >= 0 && n(toPct) < 100
    ? breakageEffect(total, a.gross, n(fromPct), n(toPct), epc) : null

  const field = (id: string, label: string, v: string, set: (s: string) => void, placeholder?: string) => (
    <div className="space-y-1">
      <Label htmlFor={id} className="text-xs">{label}</Label>
      <Input id={id} type="number" min={0} step="any" value={v} onChange={(e) => set(e.target.value)} placeholder={placeholder} />
    </div>
  )

  return (
    <Section title="Reverse calculators" icon={Calculator} description="Work backwards from a target. Each starts from this analysis and states what it assumes.">
      <div className="grid gap-4 md:grid-cols-3">
        <div className="space-y-2 rounded-md border border-slate-200 p-3">
          <p className="text-sm font-semibold">Production needed for a target cost</p>
          {field("rc-planned", "Planned total cost", planned, setPlanned)}
          {field("rc-target", "Target cost per crate", targetCpc, setTargetCpc, "e.g. 30")}
          <p className="text-sm">Crates needed: <span className="font-semibold tabular-nums">{num(tp?.crates, 0)}</span> ({num(tp?.eggs)} saleable eggs)</p>
          <p className="text-[11px] text-slate-500">Assumes the planned cost stays fixed as output changes.</p>
        </div>
        <div className="space-y-2 rounded-md border border-slate-200 p-3">
          <p className="text-sm font-semibold">Most you can spend on feed</p>
          {field("rc-eggs", "Expected saleable eggs", eggs, setEggs)}
          {field("rc-other", "Other production costs", other, setOther)}
          {field("rc-desired", "Desired cost per crate", desired, setDesired, "e.g. 30")}
          <p className="text-sm">Feed allowance: <span className={`font-semibold tabular-nums ${mf && !mf.feasible ? "text-rose-600" : ""}`}>{money(mf?.feedAllowance)}</span></p>
          <p className="text-[11px] text-slate-500">{mf && !mf.feasible ? "Other costs alone already exceed the target." : "Desired cost × crates − other costs."}</p>
        </div>
        <div className="space-y-2 rounded-md border border-slate-200 p-3">
          <p className="text-sm font-semibold">Less breakage</p>
          {field("rc-from", "Broken / lost now %", fromPct, setFromPct)}
          {field("rc-to", "Target %", toPct, setToPct)}
          <p className="text-sm">Cost per crate: <span className="tabular-nums">{money(be?.from.perCrate)}</span> → <span className="font-semibold tabular-nums">{money(be?.to.perCrate)}</span></p>
          <p className="text-sm">Extra saleable eggs: <span className="tabular-nums">{num(be?.extraSaleableEggs)}</span></p>
          <p className="text-[11px] text-slate-500">Same {money(total)} of cost and the same {num(a.gross)} eggs laid; only breakage changes.</p>
        </div>
      </div>
    </Section>
  )
}
