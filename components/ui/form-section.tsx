"use client"

/**
 * FormSection — the colored-band form group pattern lifted from the poultry
 * data-entry dialogs (see app/customers/page.tsx). Each section has a
 * coloured header band and a white body with a responsive grid for fields.
 *
 * Usage:
 *
 *   <FormSection title="Personal Information" color="indigo">
 *     <FormField label="Full name *">
 *       <Input ... />
 *     </FormField>
 *     <FormField label="Phone">
 *       <Input ... />
 *     </FormField>
 *   </FormSection>
 *
 *   <FormSection title="Address" color="green" columns={1}>
 *     <FormField label="Street">
 *       <Input ... />
 *     </FormField>
 *   </FormSection>
 *
 * Default grid is 2 columns on md+; pass columns={1} for full-width sections
 * (single-field or wide-text-area sections).
 */

import type { ReactNode } from "react"
import { cn } from "@/lib/utils"

const COLORS = {
  indigo:  "bg-indigo-600",
  blue:    "bg-blue-600",
  green:   "bg-green-600",
  sky:     "bg-sky-600",
  emerald: "bg-emerald-600",
  amber:   "bg-amber-600",
  rose:    "bg-rose-600",
  purple:  "bg-purple-600",
  slate:   "bg-slate-600",
} as const

export type FormSectionColor = keyof typeof COLORS

export function FormSection({
  title, color = "indigo", columns = 2, children, className,
}: {
  title: string
  color?: FormSectionColor
  columns?: 1 | 2 | 3
  children: ReactNode
  className?: string
}) {
  // Keep multi-column sections multi-column on mobile too — without this the
  // form felt twice as tall as it needed to be because every Input stretched
  // to the full screen width. Single-column sections (notes, address) still
  // get one row per field.
  const gridClass =
    columns === 1 ? "grid-cols-1" :
    columns === 3 ? "grid-cols-2 md:grid-cols-3" :
    "grid-cols-2"

  return (
    // min-w-0 + w-full so this section can shrink within any grid/flex parent
    // (DialogContent uses display:grid; without min-w-0 here the inner field
    // grid would force the parent to expand to its intrinsic content width,
    // pushing a page-level horizontal scrollbar onto the body).
    <div className={cn("rounded-xl border border-slate-200 overflow-hidden min-w-0 w-full", className)}>
      <div className={cn(COLORS[color], "px-4 py-2 text-sm font-semibold text-white")}>{title}</div>
      <div className={cn("grid gap-3 p-4 bg-white min-w-0", gridClass)}>
        {children}
      </div>
    </div>
  )
}

/**
 * FormField wraps a Label + control so every field has the same vertical
 * rhythm and label styling as the poultry dialogs. The control (Input,
 * Select, Textarea, etc.) is the child.
 *
 *   <FormField label="Full name *">
 *     <Input ... />
 *   </FormField>
 *
 * For fields that should span both columns of a 2-col section:
 *   <FormField label="Notes" full>
 *     <Textarea ... />
 *   </FormField>
 */
export function FormField({
  label, hint, full, children,
}: {
  label: string
  hint?: string
  full?: boolean
  children: ReactNode
}) {
  // `full` now spans both columns on every screen — was md+ only, which
  // made wide fields (Name, Notes, Address) collapse weirdly on mobile.
  return (
    // min-w-0 so the field can shrink inside its parent grid track —
    // otherwise long Select values / numeric inputs with default min-content
    // sizing can prevent the parent dialog from reflowing on narrow widths.
    <div className={cn("space-y-1 min-w-0", full && "col-span-2 md:col-span-2")}>
      <label className="text-xs sm:text-sm font-medium text-slate-700">{label}</label>
      {children}
      {hint && <p className="text-[11px] text-slate-500">{hint}</p>}
    </div>
  )
}
