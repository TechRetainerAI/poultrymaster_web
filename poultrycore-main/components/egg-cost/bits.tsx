"use client"

// Small shared pieces of the Egg Cost & Profit Analyzer page.

import type { ReactNode } from "react"
import { AlertTriangle, CheckCircle2, Info, CircleHelp } from "lucide-react"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { cn } from "@/lib/utils"
import { getCurrencySymbol, getSelectedCurrency } from "@/lib/utils/currency"
import type { Completeness, Warning } from "@/lib/egg-cost/engine"

export function useMoney() {
  const sym = getCurrencySymbol(getSelectedCurrency())
  const money = (n: number | null | undefined, dp = 2) =>
    n == null || !Number.isFinite(n) ? "—" : `${n < 0 ? "-" : ""}${sym}${Math.abs(n).toLocaleString(undefined, { minimumFractionDigits: dp, maximumFractionDigits: dp })}`
  return { sym, money, perEgg: (n: number | null | undefined) => money(n, 4) }
}

export const num = (n: number | null | undefined, dp = 0) =>
  n == null || !Number.isFinite(n) ? "—" : n.toLocaleString(undefined, { minimumFractionDigits: dp, maximumFractionDigits: dp })
export const pct = (n: number | null | undefined, dp = 1) =>
  n == null || !Number.isFinite(n) ? "—" : `${(n * 100).toFixed(dp)}%`

export function Section({ title, description, icon: Icon, actions, children, className }: {
  title: string; description?: string; icon?: React.ComponentType<{ className?: string }>
  actions?: ReactNode; children: ReactNode; className?: string
}) {
  return (
    <Card className={cn("overflow-hidden border-slate-200", className)}>
      <div className="flex flex-wrap items-start justify-between gap-2 border-b border-slate-100 bg-slate-50/60 px-4 py-3">
        <div className="flex min-w-0 items-start gap-2">
          {Icon && <Icon className="mt-0.5 h-4 w-4 shrink-0 text-sky-600" />}
          <div className="min-w-0">
            <h2 className="text-sm font-semibold text-slate-900">{title}</h2>
            {description && <p className="text-xs text-slate-500">{description}</p>}
          </div>
        </div>
        {actions && <div className="flex flex-wrap items-center gap-2">{actions}</div>}
      </div>
      <CardContent className="p-4">{children}</CardContent>
    </Card>
  )
}

export function Kpi({ label, value, sub, tone = "slate", emphasis, hint }: {
  label: string; value: string; sub?: string; tone?: "slate" | "sky" | "emerald" | "rose" | "amber" | "violet"
  emphasis?: boolean; hint?: string
}) {
  const tones: Record<string, string> = {
    slate: "border-l-slate-400", sky: "border-l-sky-500", emerald: "border-l-emerald-500",
    rose: "border-l-rose-500", amber: "border-l-amber-500", violet: "border-l-violet-500",
  }
  return (
    <div className={cn("rounded-lg border border-slate-200 border-l-4 bg-white p-3 shadow-sm", tones[tone])} title={hint}>
      <p className="flex items-center gap-1 text-[11px] font-medium uppercase tracking-wide text-slate-500">
        {label}{hint && <CircleHelp className="h-3 w-3 text-slate-400" />}
      </p>
      <p className={cn("mt-1 font-semibold tabular-nums text-slate-900", emphasis ? "text-2xl" : "text-xl")}>{value}</p>
      {sub && <p className="mt-0.5 text-xs text-slate-500">{sub}</p>}
    </div>
  )
}

export function CompletenessBadge({ status }: { status: Completeness }) {
  const map: Record<Completeness, string> = {
    Complete: "bg-emerald-100 text-emerald-800 border-emerald-200",
    Estimated: "bg-violet-100 text-violet-800 border-violet-200",
    Partial: "bg-amber-100 text-amber-900 border-amber-200",
    Insufficient: "bg-rose-100 text-rose-800 border-rose-200",
  }
  const label: Record<Completeness, string> = {
    Complete: "Complete for configured inputs", Estimated: "Includes estimates", Partial: "Partial data", Insufficient: "Insufficient data",
  }
  return <Badge variant="outline" className={cn("font-medium", map[status])}>{label[status]}</Badge>
}

export function WarningList({ warnings }: { warnings: Warning[] }) {
  if (!warnings.length) {
    return <p className="flex items-center gap-2 text-sm text-emerald-700"><CheckCircle2 className="h-4 w-4" /> Every input this analysis needs was found for the period.</p>
  }
  const icon = (w: Warning) => w.severity === "missing" ? <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-amber-600" />
    : w.severity === "estimate" ? <CircleHelp className="mt-0.5 h-4 w-4 shrink-0 text-violet-600" />
      : <Info className="mt-0.5 h-4 w-4 shrink-0 text-sky-600" />
  return (
    <ul className="space-y-1.5">
      {warnings.map((w) => (
        <li key={w.code} className="flex items-start gap-2 text-sm text-slate-700">{icon(w)}<span>{w.message}</span></li>
      ))}
    </ul>
  )
}

export const CLASS_TONE: Record<string, string> = {
  Direct: "bg-sky-50 text-sky-800 border-sky-200",
  Allocated: "bg-amber-50 text-amber-900 border-amber-200",
  Estimated: "bg-violet-50 text-violet-800 border-violet-200",
}
