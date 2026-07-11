"use client"

// The row of checkboxes that drives useViewMode(). Drop it at the top of any
// list/table page and branch on `vm.mode` / `vm.asTabs` to render.
import { LayoutGrid, Table as TableIcon, Rows3 } from "lucide-react"
import type { useViewMode } from "@/hooks/use-view-mode"

type VM = ReturnType<typeof useViewMode>

function Check({ checked, onChange, label, icon }: { checked: boolean; onChange: (v: boolean) => void; label: string; icon?: React.ReactNode }) {
  return (
    <label className="flex items-center gap-1.5 text-sm text-slate-600 cursor-pointer select-none">
      <input type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)} className="h-4 w-4 rounded border-slate-300 accent-slate-800" />
      {icon}{label}
    </label>
  )
}

export function ViewModeToggle({ vm }: { vm: VM }) {
  return (
    <div className="flex flex-wrap items-center gap-x-4 gap-y-2 rounded-lg border border-slate-200 bg-white px-3 py-2">
      <Check checked={vm.scorecards} onChange={vm.setScorecards} label="View as scorecards"
        icon={vm.scorecards ? <LayoutGrid className="h-4 w-4" /> : <TableIcon className="h-4 w-4" />} />
      <Check checked={vm.alwaysScorecards} onChange={vm.setAlwaysScorecards} label="Always show as scorecards" />
      {vm.scorecards && (
        <Check checked={vm.asTabs} onChange={vm.setAsTabs} label="Show as tabs" icon={<Rows3 className="h-4 w-4" />} />
      )}
    </div>
  )
}
