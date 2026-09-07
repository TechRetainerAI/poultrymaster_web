"use client"

/**
 * The two panels a cash-flow report needs beyond a table: a share-of-total
 * breakdown, and plain-English readings of the figures.
 *
 * Lifted out of components/poultry-reports/poultry-report-ui.tsx rather than
 * imported from it. Those renderers are driven by the poultry report DEFINITION
 * types (cells that take a summary object and a formatter context), which the
 * water reports do not have — they hold their own arrays. Same look, plain
 * props, and nothing here knows which rail it is drawing.
 *
 * Dumb by design: every number arrives already computed and already formatted.
 */

export interface CashBreakdownItem {
  key: string
  label: string
  /** Positive magnitude, formatted by the caller. */
  value: string
  /** 0-100. Drives the bar width and the parenthesised share. */
  percent: number
}

export function CashBreakdownPanel({
  title, total, accent, items, emptyText,
}: {
  title: string
  total: string
  accent: "green" | "rose"
  items: CashBreakdownItem[]
  emptyText: string
}) {
  const barCls = accent === "green" ? "bg-emerald-500" : "bg-rose-500"
  return (
    <div className="rounded-lg border border-slate-200 p-4 print:border">
      <div className="flex items-center justify-between mb-3">
        <h3 className="text-sm font-semibold text-slate-800">{title}</h3>
        <span className="text-sm font-semibold tabular-nums text-slate-900">{total}</span>
      </div>
      {items.length === 0 ? (
        <p className="py-4 text-center text-xs text-slate-500">{emptyText}</p>
      ) : (
        <div className="space-y-3">
          {items.map((it) => (
            <div key={it.key}>
              <div className="flex items-center justify-between text-xs mb-1">
                <span className="min-w-0 truncate text-slate-600" title={it.label}>{it.label}</span>
                <span className="tabular-nums text-slate-800 whitespace-nowrap">
                  {it.value}
                  <span className="text-slate-400 ml-1">({it.percent.toFixed(1)}%)</span>
                </span>
              </div>
              <div className="h-2 rounded-full bg-slate-100 overflow-hidden">
                <div
                  className={`h-full ${barCls} rounded-full`}
                  style={{ width: `${Math.min(100, Math.max(0, it.percent))}%` }}
                />
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

/**
 * Tone is carried by a left rail and the title colour only — no filled alert
 * boxes, because most of these are ordinary observations and a page of amber
 * panels reads as a page of problems.
 */
export function CashAnalysisPanel({
  title, items,
}: {
  title: string
  items: Array<{ id: string; tone: "good" | "watch" | "neutral"; title: string; detail: string }>
}) {
  if (!items.length) return null
  return (
    <div className="rounded-lg border border-slate-200 p-4 print:border">
      <h3 className="text-sm font-semibold text-slate-800 mb-3">{title}</h3>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-3 print:grid-cols-2">
        {items.map((a) => {
          const rail =
            a.tone === "good" ? "bg-emerald-500" :
            a.tone === "watch" ? "bg-amber-500" : "bg-slate-300"
          const head =
            a.tone === "good" ? "text-emerald-800" :
            a.tone === "watch" ? "text-amber-800" : "text-slate-800"
          return (
            <div key={a.id} className="relative rounded-md border border-slate-200 bg-white pl-4 pr-3 py-2.5 overflow-hidden">
              <div className={`absolute inset-y-0 left-0 w-1 ${rail}`} />
              <div className={`text-xs font-semibold ${head}`}>{a.title}</div>
              <div className="mt-1 text-[11px] leading-snug text-slate-600">{a.detail}</div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
