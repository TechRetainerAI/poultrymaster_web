"use client"

// "Enable Projects & Contracts" when a Generic company is created (spec Part
// 2.1: it can be enabled during company setup or later in Business Features).
// Not a business type: any Generic business can tick it.

import { Checkbox } from "@/components/ui/checkbox"

export function SetupProjectsCheckbox({ checked, onChange }: { checked: boolean; onChange: (v: boolean) => void }) {
  return (
    <label className="mt-2 flex cursor-pointer items-start gap-2 rounded-md border border-slate-200 p-3 text-sm">
      <Checkbox checked={checked} onCheckedChange={(v) => onChange(v === true)} className="mt-0.5" />
      <span>
        <span className="font-medium text-slate-900">Enable Projects &amp; Contracts</span>
        <span className="block text-xs text-slate-500">
          Manage multiple jobs, projects, and contracts within one company. Track purchases, expenses, inventory, payments,
          budgets, and profitability separately for each project. You can turn this on or off later in Business Features.
        </span>
      </span>
    </label>
  )
}
