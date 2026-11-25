"use client"

import { useMemo, useState } from "react"
import { CartesianGrid, Legend, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis, Bar, BarChart } from "recharts"
import { TrendingUp } from "lucide-react"
import { Button } from "@/components/ui/button"
import { trend, type EggCostFacts, type Scope, type TrendGrain } from "@/lib/egg-cost/engine"
import { Section, useMoney } from "./bits"

/** Cost, price and margin per crate over time, on the same settings throughout. */
export function Trends({ facts, scope }: { facts: EggCostFacts; scope: Scope }) {
  const { money } = useMoney()
  const days = Math.round((Date.parse(facts.endDate) - Date.parse(facts.startDate)) / 86_400_000) + 1
  const [grain, setGrain] = useState<TrendGrain>(days > 120 ? "month" : "week")
  const data = useMemo(() => trend(facts, scope, grain).map((p) => ({
    ...p,
    full: p.fullPerCrate != null ? +p.fullPerCrate.toFixed(2) : null,
    direct: p.directPerCrate != null ? +p.directPerCrate.toFixed(2) : null,
    feed: p.feedPerCrate != null ? +p.feedPerCrate.toFixed(2) : null,
    price: p.pricePerCrate != null ? +p.pricePerCrate.toFixed(2) : null,
    margin: p.marginPerCrate != null ? +p.marginPerCrate.toFixed(2) : null,
    brokenPct: p.brokenRate != null ? +(p.brokenRate * 100).toFixed(2) : null,
  })), [facts, scope, grain])

  if (days < 8) {
    return <Section title="Cost trends" icon={TrendingUp}><p className="text-sm text-slate-500">Choose a period longer than a week to see trends.</p></Section>
  }
  return (
    <Section title="Cost trends" icon={TrendingUp}
      description={`Settings version ${facts.settings?.version ?? 0} throughout. Pre-laying allocation follows each bucket's eggs.`}
      actions={
        <div className="flex gap-1">
          {(["week", "month"] as TrendGrain[]).map((g) => (
            <Button key={g} size="sm" variant={grain === g ? "default" : "outline"} onClick={() => setGrain(g)}>{g === "week" ? "Weekly" : "Monthly"}</Button>
          ))}
        </div>
      }>
      <div className="grid gap-4 lg:grid-cols-2">
        <div className="h-64 min-w-0">
          <p className="mb-1 text-xs font-medium text-slate-600">Per crate: cost vs selling price</p>
          <ResponsiveContainer width="100%" height="90%">
            <LineChart data={data}>
              <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
              <XAxis dataKey="label" tick={{ fontSize: 11 }} />
              <YAxis tick={{ fontSize: 11 }} width={50} />
              <Tooltip formatter={(v: number) => money(v)} />
              <Legend wrapperStyle={{ fontSize: 11 }} />
              <Line type="monotone" dataKey="full" name="Full cost" stroke="#0ea5e9" strokeWidth={2} connectNulls />
              <Line type="monotone" dataKey="direct" name="Direct cost" stroke="#10b981" strokeWidth={2} connectNulls />
              <Line type="monotone" dataKey="feed" name="Feed cost" stroke="#f59e0b" strokeWidth={1.5} connectNulls />
              <Line type="monotone" dataKey="price" name="Selling price" stroke="#8b5cf6" strokeWidth={2} strokeDasharray="5 3" connectNulls />
            </LineChart>
          </ResponsiveContainer>
        </div>
        <div className="h-64 min-w-0">
          <p className="mb-1 text-xs font-medium text-slate-600">Saleable eggs and broken-egg rate</p>
          <ResponsiveContainer width="100%" height="90%">
            <BarChart data={data}>
              <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
              <XAxis dataKey="label" tick={{ fontSize: 11 }} />
              <YAxis yAxisId="l" tick={{ fontSize: 11 }} width={55} />
              <YAxis yAxisId="r" orientation="right" tick={{ fontSize: 11 }} width={40} unit="%" />
              <Tooltip />
              <Legend wrapperStyle={{ fontSize: 11 }} />
              <Bar yAxisId="l" dataKey="saleable" name="Saleable eggs" fill="#bae6fd" />
              <Bar yAxisId="r" dataKey="brokenPct" name="Broken / lost %" fill="#fca5a5" />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>
      {data.some((p) => p.completeness !== "Complete") && (
        <p className="mt-2 text-xs text-slate-500">
          Buckets with partial data: {data.filter((p) => p.completeness === "Partial" || p.completeness === "Insufficient").map((p) => p.label).join(", ") || "none"}.
        </p>
      )}
    </Section>
  )
}
