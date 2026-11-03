"use client"

// Layer / Broiler picker for a flock (migration 399).
//
// On a NEW flock the picker starts "automatic": it shows the type the server
// will give the flock (broiler breed, else the company's business type) and
// sends nothing, so the database rule stays the one authority. Choosing a type
// makes it explicit. On an existing flock the stored type is always explicit.

import { Drumstick, Egg } from "lucide-react"
import { cn } from "@/lib/utils"
import { FLOCK_TYPE_LABELS, FLOCK_TYPES, type FlockType } from "@/lib/poultry/flock-type"

interface FlockTypeSelectProps {
  /** The type shown as selected. */
  value: FlockType
  onChange: (type: FlockType) => void
  /** True while the value is the automatic default rather than a choice. */
  automatic?: boolean
  disabled?: boolean
}

export function FlockTypeSelect({ value, onChange, automatic, disabled }: FlockTypeSelectProps) {
  return (
    <div className="space-y-1.5">
      <div role="radiogroup" aria-label="Flock type" className="grid grid-cols-2 gap-2">
        {FLOCK_TYPES.map((t) => {
          const selected = value === t
          const Icon = t === "Broiler" ? Drumstick : Egg
          return (
            <button
              key={t}
              type="button"
              role="radio"
              aria-checked={selected}
              disabled={disabled}
              onClick={() => onChange(t)}
              className={cn(
                "flex h-10 items-center justify-center gap-2 rounded-md border px-3 text-sm font-medium transition-colors",
                "focus:outline-none focus-visible:ring-2 focus-visible:ring-orange-500 disabled:opacity-50",
                selected
                  ? "border-orange-500 bg-orange-50 text-orange-700"
                  : "border-slate-200 bg-white text-slate-600 hover:bg-slate-50",
              )}
            >
              <Icon className="h-4 w-4" aria-hidden />
              {FLOCK_TYPE_LABELS[t]}
            </button>
          )
        })}
      </div>
      <p className="text-xs text-slate-500">
        {automatic
          ? "Set from the breed and your company type. Change it if it's wrong."
          : value === "Broiler"
            ? "Meat birds: no egg records for this flock."
            : "Laying birds: egg records are kept for this flock."}
      </p>
    </div>
  )
}
