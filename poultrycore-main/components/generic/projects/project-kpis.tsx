"use client"

// The project's numbers, each one its own measure. The labels say what a
// figure IS so nobody mistakes the award value for revenue, cash for revenue,
// a purchase for a cost, or owner money for profit.

import type { ReactNode } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { cn } from "@/lib/utils"
import { useFmt } from "@/lib/currency"
import type { ProjectSummary } from "@/lib/api/generic-projects"

export function Kpi({ label, value, hint, tone }: { label: string; value: ReactNode; hint?: string; tone?: "good" | "bad" | "warn" }) {
  return (
    <div className="rounded-lg border border-slate-200 bg-white p-3">
      <div className="text-xs text-slate-500">{label}</div>
      <div className={cn("mt-1 text-lg font-semibold tabular-nums text-slate-900",
        tone === "good" && "text-emerald-700", tone === "bad" && "text-rose-700", tone === "warn" && "text-amber-700")}>{value}</div>
      {hint && <div className="mt-0.5 text-[11px] leading-tight text-slate-400">{hint}</div>}
    </div>
  )
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <Card>
      <CardHeader className="pb-2"><CardTitle className="text-sm font-semibold text-slate-700">{title}</CardTitle></CardHeader>
      <CardContent className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-4">{children}</CardContent>
    </Card>
  )
}

export function ProjectKpis({ s }: { s: ProjectSummary }) {
  const fmt = useFmt()
  const budgetUsed = s.approvedBudget ? (s.purchaseValue + s.totalCosts - s.costOfGoodsSold) / s.approvedBudget : null
  return (
    <div className="space-y-4">
      <Section title="Contract">
        <Kpi label="Contract award value" value={s.awardValue != null ? fmt(s.awardValue) : "—"} hint="What the contract is worth. Not revenue." />
        <Kpi label="Award not yet earned" value={s.remainingAwardValue != null ? fmt(s.remainingAwardValue) : "—"} hint="Award value minus revenue earned so far." />
        <Kpi label="Approved budget (costs)" value={s.approvedBudget != null ? fmt(s.approvedBudget) : "—"} />
        <Kpi label="Budget used (committed)" value={budgetUsed == null ? "—" : `${(budgetUsed * 100).toFixed(1)}%`}
          tone={budgetUsed != null && budgetUsed > 1 ? "bad" : undefined} hint="Purchases + costs approved for the project." />
      </Section>

      <Section title="Profit (recognised)">
        <Kpi label="Revenue earned" value={fmt(s.revenue)} hint="From sales recorded for the project." />
        <Kpi label="Cost of goods sold" value={fmt(s.costOfGoodsSold)} hint="Cost of what was sold — not everything bought." />
        <Kpi label="Gross profit" value={fmt(s.grossProfit)} tone={s.grossProfit < 0 ? "bad" : undefined} />
        <Kpi label="Operating expenses" value={fmt(s.operatingExpenses)} />
        {s.allocatedOverhead !== 0 && <Kpi label="Allocated overhead" value={fmt(s.allocatedOverhead)} />}
        {s.depreciation !== 0 && <Kpi label="Depreciation" value={fmt(s.depreciation)} />}
        {s.financingCosts !== 0 && <Kpi label="Financing costs" value={fmt(s.financingCosts)} />}
        <Kpi label="Net project profit" value={fmt(s.netProfit)} tone={s.netProfit < 0 ? "bad" : s.netProfit > 0 ? "good" : undefined} />
        <Kpi label="Profit margin" value={s.profitMarginPercent == null ? "—" : `${s.profitMarginPercent}%`} />
      </Section>

      <Section title="Cash (actual money)">
        <Kpi label="Received from customers" value={fmt(s.customerCashReceived)} hint="Payments actually collected." />
        <Kpi label="Paid for purchases" value={fmt(s.procurementCashPaid)} hint="Paid to suppliers, including advances." />
        <Kpi label="Paid for expenses & wages" value={fmt(s.expenseCashPaid)} />
        <Kpi label="Total money in" value={fmt(s.cashIn)} />
        <Kpi label="Total money out" value={fmt(s.cashOut)} />
        <Kpi label="Net attributable cash" value={fmt(s.netCashFlow)} tone={s.netCashFlow < 0 ? "warn" : undefined}
          hint="Includes owner funding. Not profit, and not cash set aside." />
        <Kpi label="Working capital tied up" value={fmt(s.workingCapitalExposure)} tone={s.workingCapitalExposure > 0 ? "warn" : undefined}
          hint="Cash used beyond what the project brought in, before owner money." />
      </Section>

      <Section title="Funding & balances (today)">
        <Kpi label="Owner money put in" value={fmt(s.ownerContributed)} hint="Financing — never profit." />
        <Kpi label="Owner money taken out" value={fmt(s.ownerDrawn)} />
        <Kpi label="Customer still owes" value={fmt(s.receivable)} tone={s.overdueReceivable > 0 ? "warn" : undefined}
          hint={s.overdueReceivable > 0 ? `${fmt(s.overdueReceivable)} overdue` : undefined} />
        <Kpi label="Owed to suppliers" value={fmt(s.payable)} />
        <Kpi label="Purchases made (value)" value={fmt(s.purchaseValue)} hint="Bought for the project. Becomes cost only when sold or used." />
        {s.customerAdvances !== 0 && <Kpi label="Customer advances held" value={fmt(s.customerAdvances)} hint="Received before it was earned." />}
        {s.supplierAdvances !== 0 && <Kpi label="Supplier advances paid" value={fmt(s.supplierAdvances)} hint="Paid ahead; not an expense." />}
      </Section>
    </div>
  )
}
