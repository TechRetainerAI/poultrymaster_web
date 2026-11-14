"use client"

// Shared report header and rich summary card components.
// Matches the poultry PoultryReportView visual style: orange accent border,
// company name, period/generated/currency, and colored summary cards.

import { Card, CardContent } from "@/components/ui/card"
import { cn } from "@/lib/utils"
import { useAuthStore } from "@/lib/store/auth-store"

/** Rich summary card with colored left border, large value, and formula lines. */
export function RichCard({ label, value, accent = "slate", lines }: {
  label: string
  value: string
  accent?: "slate" | "emerald" | "red" | "amber" | "orange" | "violet" | "blue" | "cyan"
  lines?: string[]
}) {
  const borderColor: Record<string, string> = {
    slate: "border-l-slate-300", emerald: "border-l-emerald-500", red: "border-l-red-500",
    amber: "border-l-amber-500", orange: "border-l-orange-500", violet: "border-l-violet-500",
    blue: "border-l-blue-500", cyan: "border-l-cyan-500",
  }
  const valueColor: Record<string, string> = {
    slate: "text-slate-900", emerald: "text-emerald-700", red: "text-red-600",
    amber: "text-amber-700", orange: "text-orange-700", violet: "text-violet-700",
    blue: "text-blue-700", cyan: "text-cyan-700",
  }
  const labelColor: Record<string, string> = {
    slate: "text-slate-500", emerald: "text-emerald-600", red: "text-red-500",
    amber: "text-amber-600", orange: "text-orange-600", violet: "text-violet-600",
    blue: "text-blue-600", cyan: "text-cyan-600",
  }

  return (
    <Card className={cn("border-l-4", borderColor[accent])}>
      <CardContent className="p-4">
        <div className={cn("text-[11px] font-semibold uppercase tracking-wider mb-1", labelColor[accent])}>{label}</div>
        <div className={cn("text-xl font-bold tabular-nums", valueColor[accent])}>{value}</div>
        {lines && lines.filter(Boolean).length > 0 && (
          <div className="mt-2 space-y-0.5">
            {lines.filter(Boolean).map((line, i) => (
              <div key={i} className="text-xs text-slate-500">{line}</div>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  )
}

/** Report page header with orange accent border, company name, title, period info. */
export function ReportPageHeader({ title, description, period, children }: {
  title: string
  description: string
  period?: { from: string; to: string }
  children?: React.ReactNode
}) {
  const farmName = useAuthStore((s) => s.activeFarmName)
  const generated = new Intl.DateTimeFormat(undefined, {
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "numeric", minute: "2-digit", second: "2-digit",
  }).format(new Date())

  return (
    <Card className="mb-4 border-t-4 border-t-amber-500">
      <CardContent className="pt-6">
        <div className="text-xs font-bold uppercase tracking-wider text-amber-600 mb-1">{farmName ?? "Company"}</div>
        <h1 className="text-2xl font-bold text-slate-900">{title}</h1>
        <p className="text-sm text-slate-500 mt-1">{description}</p>
        <div className="flex flex-wrap gap-x-8 gap-y-1 mt-3 text-sm text-slate-600">
          {period && <div><span className="text-slate-400">Period:</span> {period.from} → {period.to}</div>}
          <div><span className="text-slate-400">Generated:</span> {generated}</div>
          <div><span className="text-slate-400">Currency:</span> GHS (GHC)</div>
        </div>
        {children && (
          <div className="mt-4 pt-4 border-t border-slate-100">
            {children}
          </div>
        )}
      </CardContent>
    </Card>
  )
}
