import { Card, CardContent } from "@/components/ui/card"

/**
 * Poultry's money-page scorecard (the local `Stat` in app/poultry-owner-money,
 * -loans, -cash-transfers, -employee-loans), shared by the Restaurant money
 * pages so they read the same: small uppercase label, bold figure, one hint.
 */
export function MoneyStat({ label, value, hint, accent = "slate" }: {
  label: string
  value: string
  hint?: string
  accent?: "slate" | "emerald" | "orange" | "rose" | "indigo" | "amber" | "violet"
}) {
  const colour = {
    slate: "text-slate-900",
    emerald: "text-emerald-700",
    orange: "text-orange-700",
    rose: "text-rose-600",
    indigo: "text-indigo-700",
    amber: "text-amber-700",
    violet: "text-violet-700",
  }[accent]
  return (
    <Card>
      <CardContent className="p-4">
        <p className="text-xs font-medium text-slate-500 uppercase tracking-wider truncate">{label}</p>
        <div className={`text-lg sm:text-xl font-bold mt-1 truncate ${colour}`}>{value}</div>
        {hint && <div className="text-xs text-slate-500 mt-0.5 truncate">{hint}</div>}
      </CardContent>
    </Card>
  )
}
