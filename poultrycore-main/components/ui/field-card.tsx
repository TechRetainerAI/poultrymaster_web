import type { ReactNode } from "react"

// Mobile card for a table row: a title (+ optional badge), a 2-column field grid,
// and an optional actions row. Pages render a table on md+ and these cards below
// md so data-heavy lists read well on phones.
export function FieldCard({ title, badge, fields, actions }: {
  title: ReactNode
  badge?: ReactNode
  fields: [string, ReactNode][]
  actions?: ReactNode
}) {
  return (
    <div className="rounded-lg border border-slate-200 p-3">
      <div className="flex items-center justify-between gap-2">
        <div className="font-medium text-slate-900 min-w-0 truncate">{title}</div>
        {badge}
      </div>
      <div className="mt-2 grid grid-cols-2 gap-x-3 gap-y-1 text-sm">
        {fields.map(([l, v], idx) => (
          <div key={idx} className="min-w-0 truncate"><span className="text-slate-500">{l}: </span><span className="tabular-nums">{v}</span></div>
        ))}
      </div>
      {actions && <div className="mt-2 flex justify-end gap-1 border-t pt-2">{actions}</div>}
    </div>
  )
}
