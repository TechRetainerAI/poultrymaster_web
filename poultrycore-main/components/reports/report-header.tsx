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
    slate: "border-t-slate-200", emerald: "border-t-emerald-500", red: "border-t-red-500",
    amber: "border-t-amber-500", orange: "border-t-orange-500", violet: "border-t-violet-500",
    blue: "border-t-blue-500", cyan: "border-t-cyan-500",
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
    <Card className={cn("border-t-[3px]", borderColor[accent])}>
      <CardContent className="p-4 pt-5">
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
        <div className="mt-3 space-y-0.5 text-sm">
          <div className="flex items-center justify-between">
            {period && <div className="text-slate-600"><span className="text-slate-400 font-medium">Period:</span> {period.from} → {period.to}</div>}
            <div className="text-slate-600"><span className="text-slate-400 font-medium">Currency:</span> <span className="text-emerald-700">GHS (GHC)</span></div>
          </div>
          <div className="text-slate-600"><span className="text-slate-400 font-medium">Generated:</span> {generated}</div>
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
