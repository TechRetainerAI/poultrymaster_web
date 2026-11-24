// Egg Cost & Profit Analyzer -- PDF and CSV exports. Scenario exports say
// "HYPOTHETICAL" on every figure they change.

import { downloadCsv } from "@/lib/utils/download-csv"
import { exportMultiTablePdf } from "@/lib/utils/pdf-export"
import { safeDiv, type EggCostAnalysis, type ScenarioResult } from "@/lib/egg-cost/engine"

export interface ExportContext {
  a: EggCostAnalysis
  scenario: ScenarioResult | null
  mode: "Recorded" | "Scenario"
  scopeLabel: string
  money: (n: number | null | undefined, dp?: number) => string
  currencyLabel: string
}

const pctTxt = (n: number | null | undefined) => (n == null ? "—" : `${(n * 100).toFixed(1)}%`)

function headline(c: ExportContext): [string, string][] {
  const { a, money } = c
  const rows: [string, string][] = [
    ["Analysis mode", c.mode === "Scenario" ? "HYPOTHETICAL SCENARIO" : "Recorded analysis"],
    ["Selection", c.scopeLabel],
    ["Period", `${a.startDate} to ${a.endDate}`],
    ["Data completeness", a.completeness],
    ["Eggs per crate", String(a.eggsPerCrate)],
    ["Gross eggs", a.gross.toLocaleString()],
    ["Broken / lost eggs", (a.gross - a.saleable).toLocaleString()],
    ["Saleable eggs", a.saleable.toLocaleString()],
    ["Saleable crates", a.saleableCrates.toFixed(1)],
    [a.directLabel, money(a.directPerCrate)],
    [a.fullLabel, money(a.fullPerCrate)],
    ["Feed cost per crate", money(a.feedPerCrate)],
    ["Packaged cost per crate", money(a.packagedPerCrate)],
    ["Cost per saleable egg (full)", money(a.fullPerEgg, 4)],
    ["Actual average selling price per crate", money(a.price.pricePerCrate)],
    ["Estimated margin per crate", money(a.marginPerCrate)],
    ["Estimated margin %", pctTxt(a.marginPct)],
    ["Break-even price per crate", money(a.breakEvenPerCrate)],
  ]
  if (c.scenario) {
    rows.push(
      ["HYPOTHETICAL full cost per crate", money(c.scenario.fullPerCrate)],
      ["HYPOTHETICAL direct cost per crate", money(c.scenario.directPerCrate)],
      ["HYPOTHETICAL selling price per crate", money(c.scenario.pricePerCrate)],
      ["HYPOTHETICAL margin per crate", money(c.scenario.marginPerCrate)],
      ["HYPOTHETICAL saleable eggs", Math.round(c.scenario.saleable).toLocaleString()],
    )
  }
  rows.push(["Calculation version", a.calcVersion], ["Settings version", String(a.settings.version)], ["Calculated", new Date().toLocaleString()])
  return rows
}

export async function exportPdf(c: ExportContext) {
  const { a, money } = c
  await exportMultiTablePdf({
    title: c.mode === "Scenario" ? "Egg Cost & Profit Analyzer — HYPOTHETICAL SCENARIO" : "Egg Cost & Profit Analyzer",
    filename: `egg-cost-analysis-${a.startDate}-${a.endDate}`,
    fromDate: a.startDate, toDate: a.endDate, currencyLabel: c.currencyLabel,
    filtersUsed: [{ label: "Selection", value: c.scopeLabel }, { label: "Mode", value: c.mode }],
    summaryCards: [
      { label: a.fullLabel, value: money(a.fullPerCrate) },
      { label: a.directLabel, value: money(a.directPerCrate) },
      { label: "Saleable crates", value: a.saleableCrates.toFixed(1) },
      { label: "Margin / crate", value: money(a.marginPerCrate), accent: a.marginPerCrate != null && a.marginPerCrate < 0 ? "rose" : "green" },
    ],
    tables: [
      { heading: "Summary", columns: [{ header: "Item" }, { header: "Value", align: "right" }], rows: headline(c) },
      {
        heading: "Cost breakdown",
        columns: [{ header: "Category" }, { header: "Cost", align: "right" }, { header: "Per crate", align: "right" }, { header: "Basis" }, { header: "In" }],
        rows: a.components.map((x) => {
          const e = safeDiv(x.amount, a.saleable)
          return [x.label, money(x.amount), money(e == null ? null : e * a.eggsPerCrate), x.classification,
            [x.inDirect && "Direct", x.inFull && "Full", x.inPackaged && "Packaged"].filter(Boolean).join(", ")]
        }),
      },
      ...(c.scenario ? [{
        heading: "HYPOTHETICAL scenario vs recorded",
        columns: [{ header: "Item" }, { header: "Recorded", align: "right" as const }, { header: "HYPOTHETICAL", align: "right" as const }],
        rows: c.scenario.components.map((x) => [x.label, money(x.baseline), money(x.scenario)]),
      }] : []),
      {
        heading: "Flocks",
        columns: [{ header: "Flock" }, { header: "Saleable eggs", align: "right" }, { header: "Direct", align: "right" }, { header: "Full", align: "right" }, { header: "Full / crate", align: "right" }],
        rows: a.flocks.filter((r) => r.inScope && r.isLaying).map((r) => {
          const e = safeDiv(r.full, r.saleable)
          return [r.name, r.saleable.toLocaleString(), money(r.direct), money(r.full), money(e == null ? null : e * a.eggsPerCrate)]
        }),
      },
      {
        heading: "Assumptions, completeness and exclusions",
        columns: [{ header: "Note" }],
        rows: [
          [`Shared labour allocated by ${a.settings.labourAllocation === "BirdDays" ? "bird-days" : "saleable eggs"}; overhead and depreciation by ${a.settings.overheadAllocation === "BirdDays" ? "bird-days" : "saleable eggs"}.`],
          ["Feed and medication are the quantities consumed, valued by the stock cost layers; purchase and consumption expenses for the same stock are excluded."],
          ...a.warnings.map((w) => [`${w.severity === "missing" ? "MISSING" : w.severity === "estimate" ? "ESTIMATE" : "NOTE"}: ${w.message}`]),
          ...a.excluded.map((x) => [`Excluded: ${x.label} — ${money(x.amount)} (${x.count})`]),
          ...a.notEggCost.map((x) => [`Not egg cost: ${x.label} — ${money(x.amount)}`]),
          ["This is a management production-cost analysis. It does not change the Profit & Loss, which recognises costs when they are expensed."],
        ],
      },
    ],
  })
}

export function exportCsv(c: ExportContext) {
  const { a, money } = c
  const rows: (string | number)[][] = []
  for (const [k, v] of headline(c)) rows.push(["Summary", k, v])
  for (const x of a.components) {
    const e = safeDiv(x.amount, a.saleable)
    rows.push(["Cost", x.label, x.amount.toFixed(2), e == null ? "" : (e * a.eggsPerCrate).toFixed(4), x.classification])
  }
  if (c.scenario) for (const x of c.scenario.components) rows.push(["HYPOTHETICAL", x.label, x.baseline.toFixed(2), x.scenario.toFixed(2)])
  for (const r of a.flocks.filter((f) => f.inScope && f.isLaying)) {
    rows.push(["Flock", r.name, r.saleable, r.direct.toFixed(2), r.full.toFixed(2)])
  }
  for (const w of a.warnings) rows.push(["Warning", w.severity, w.message])
  for (const x of a.excluded) rows.push(["Excluded", x.label, money(x.amount), x.count])
  downloadCsv(`egg-cost-analysis-${a.startDate}-${a.endDate}${c.mode === "Scenario" ? "-scenario" : ""}.csv`,
    ["Section", "Item", "Value", "Value 2", "Value 3"], rows)
}
