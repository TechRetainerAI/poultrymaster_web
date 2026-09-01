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
import { Info } from "lucide-react"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { cn } from "@/lib/utils"

/**
 * A tap-to-read note beside a field label. Popover rather than Tooltip on
 * purpose: hover does not exist on a phone, and long explanations are exactly
 * what you want out of the layout on a small screen.
 *
 * Exported so tables and other non-FormField labels can use the same control.
 */
export function InfoTip({ label, children }: { label: string; children: ReactNode }) {
  return (
    <Popover>
      <PopoverTrigger asChild>
        <button
          type="button"
          aria-label={`What "${label}" means`}
          className="grid h-4 w-4 shrink-0 place-items-center rounded-full text-slate-400 transition-colors hover:text-slate-600 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-slate-400"
        >
          <Info className="h-3.5 w-3.5" />
        </button>
      </PopoverTrigger>
      <PopoverContent side="top" align="start" className="w-64 p-2.5 text-xs font-normal leading-relaxed text-slate-600">
        {children}
      </PopoverContent>
    </Popover>
  )
}

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
  title, color = "indigo", columns = 2, stackOnMobile = false, children, className,
}: {
  title: string
  color?: FormSectionColor
  columns?: 1 | 2 | 3
  /**
   * Opt this section out of the multi-column-on-mobile default below. Use it
   * where half a phone screen genuinely isn't enough for the control — long
   * Select labels that truncate, or a section whose child is itself a grid of
   * repeated rows. Off by default so existing forms are untouched.
   */
  stackOnMobile?: boolean
  children: ReactNode
  className?: string
}) {
  // Keep multi-column sections multi-column on mobile too — without this the
  // form felt twice as tall as it needed to be because every Input stretched
  // to the full screen width. Single-column sections (notes, address) still
  // get one row per field.
  const gridClass =
    columns === 1 ? "grid-cols-1" :
    columns === 3 ? (stackOnMobile ? "grid-cols-1 sm:grid-cols-2 md:grid-cols-3" : "grid-cols-2 md:grid-cols-3") :
    stackOnMobile ? "grid-cols-1 sm:grid-cols-2" : "grid-cols-2"

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
  label, hint, info, full, children,
}: {
  label: string
  hint?: string
  /**
   * A longer explanation, behind a tap-to-read ⓘ beside the label. Prefer this
   * over `hint` when the text runs to more than a few words — a `hint` renders
   * inline and costs two or three lines of a phone screen per field.
   */
  info?: ReactNode
  full?: boolean
  children: ReactNode
}) {
  // `full` spans every column of whatever grid it lands in, at every width.
  // `col-span-full` rather than `col-span-2`: in a one-column grid (columns={1},
  // or a stackOnMobile section on a phone) a hard span of 2 makes the item
  // reach into an implicit second column and widens the whole grid.
  return (
    // min-w-0 so the field can shrink inside its parent grid track —
    // otherwise long Select values / numeric inputs with default min-content
    // sizing can prevent the parent dialog from reflowing on narrow widths.
    <div className={cn("space-y-1 min-w-0", full && "col-span-full")}>
      <div className="flex items-center gap-1">
        <label className="text-xs sm:text-sm font-medium text-slate-700">{label}</label>
        {info && <InfoTip label={label}>{info}</InfoTip>}
      </div>
      {children}
      {hint && <p className="text-[11px] text-slate-500">{hint}</p>}
    </div>
  )
}
