"use client"

// Report 6: hosting / cloud cost, and what share of revenue it eats.
//
// Written for SaaS but useful to anyone with a big fixed supplier line.
//
// The report cannot know which categories count as hosting -- every company
// names its own -- so the server SUGGESTS the ones whose names look like it and
// the owner corrects the selection here. Guessing silently would produce a
// number that is confidently wrong; a checkbox list is a number the owner
// agreed to.
//
// Unticking everything is a real answer, not "go back to the guess": the client
// sends useSuggested=false and the report correctly reads zero.

import { useEffect, useState } from "react"
import { Cloud } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { getHostingCost, type GenericHostingCostReport } from "@/lib/api/generic-reports"
import {
  GenericReportShell, ReportStat, ReportTable, fmtMonth, fmtMoney, fmtPct,
  trailingMonthsRange, type DateRange,
} from "@/components/generic/report-shell"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Checkbox } from "@/components/ui/checkbox"

export default function HostingCostReportPage() {
  const { toast } = useToast()

  const [range, setRange] = useState<DateRange>(trailingMonthsRange(12))
  const [data, setData] = useState<GenericHostingCostReport | null>(null)
  const [loading, setLoading] = useState(true)
  // null = "server's suggestion"; an array = the owner has chosen, even if empty.
  const [chosen, setChosen] = useState<number[] | null>(null)

  const load = async (r: DateRange = range, ids: number[] | null = chosen) => {
    setLoading(true)
    try {
      const d = await getHostingCost(r.fromDate, r.toDate, ids ?? undefined)
      setData(d)
      // First load adopts the suggestion so the checkboxes show what was used.
      if (ids === null) setChosen(d.categories.filter((c) => c.isSuggested).map((c) => c.genericExpenseCategoryId))
    } catch (e: any) {
      toast({ title: "Could not load report", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    void load(range, null)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const months = data?.months ?? []
  const totalHosting = months.reduce((s, m) => s + m.hostingCost, 0)
  const totalRevenue = months.reduce((s, m) => s + m.totalRevenue, 0)
  const avgMonthly = months.length ? totalHosting / months.length : 0
  const sharePct = totalRevenue > 0 ? (totalHosting * 100) / totalRevenue : 0

  const toggle = (id: number) => {
    setChosen((prev) => {
      const cur = prev ?? []
      return cur.includes(id) ? cur.filter((x) => x !== id) : [...cur, id]
    })
  }

  return (
    <GenericReportShell
      title="Hosting &amp; cloud cost"
      description="What infrastructure costs each month, and how much of revenue it consumes."
      icon={Cloud}
      range={range}
      onRangeChange={setRange}
      onRun={() => load()}
      loading={loading}
    >
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
        <ReportStat title="Total hosting" value={fmtMoney(totalHosting)} hint={`${months.length} month(s)`} />
        <ReportStat title="Average a month" value={fmtMoney(avgMonthly)} />
        <ReportStat
          title="Share of revenue"
          value={fmtPct(sharePct)}
          hint={totalRevenue > 0 ? `of ${fmtMoney(totalRevenue)}` : "No revenue in range"}
          accent={sharePct > 30 ? "rose" : sharePct > 15 ? "amber" : "emerald"}
        />
        <ReportStat title="Categories counted" value={(chosen ?? []).length} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <Card className="lg:col-span-1">
          <CardHeader className="pb-2">
            <CardTitle className="text-xs uppercase tracking-wide text-slate-500">
              Which categories count
            </CardTitle>
          </CardHeader>
          <CardContent>
            {(data?.categories ?? []).length === 0 ? (
              <p className="text-sm text-slate-500">No expense categories yet.</p>
            ) : (
              <>
                <ul className="space-y-2">
                  {data!.categories.map((c) => (
                    <li key={c.genericExpenseCategoryId} className="flex items-start gap-2 text-sm">
                      <Checkbox
                        id={`cat-${c.genericExpenseCategoryId}`}
                        checked={(chosen ?? []).includes(c.genericExpenseCategoryId)}
                        onCheckedChange={() => toggle(c.genericExpenseCategoryId)}
                        className="mt-0.5"
                      />
                      <label htmlFor={`cat-${c.genericExpenseCategoryId}`} className="min-w-0 flex-1 cursor-pointer">
                        <span className="block truncate">{c.categoryName}</span>
                        <span className="text-xs text-slate-500">
                          {fmtMoney(c.totalAmount)} all time{c.isSuggested ? " · suggested" : ""}
                        </span>
                      </label>
                    </li>
                  ))}
                </ul>
                <p className="text-xs text-slate-500 mt-3">
                  Suggestions come from the category name. Change the ticks and press Run —
                  unticking everything reports zero rather than falling back to the guess.
                </p>
              </>
            )}
          </CardContent>
        </Card>

        <div className="lg:col-span-2">
          <ReportTable
            title="Month by month"
            rows={months}
            empty="No months in this range."
            columns={[
              { key: "m", header: "Month", render: (r) => fmtMonth(r.monthStart) },
              { key: "h", header: "Hosting", align: "right", render: (r) => fmtMoney(r.hostingCost) },
              { key: "n", header: "Bills", align: "right", render: (r) => r.expenseCount },
              { key: "rev", header: "Revenue", align: "right", render: (r) => fmtMoney(r.totalRevenue) },
              {
                key: "pr", header: "% of revenue", align: "right",
                render: (r) => (
                  <span className={r.pctOfRevenue > 30 ? "text-rose-600" : ""}>
                    {r.totalRevenue > 0 ? fmtPct(r.pctOfRevenue) : "—"}
                  </span>
                ),
              },
              { key: "pe", header: "% of costs", align: "right", render: (r) => (r.totalExpenses > 0 ? fmtPct(r.pctOfExpenses) : "—") },
            ]}
          />
        </div>
      </div>
    </GenericReportShell>
  )
}
