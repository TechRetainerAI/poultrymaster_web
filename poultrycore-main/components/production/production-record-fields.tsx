"use client"

// Small presentational pieces shared by the production record form.
//
// These exist because the old full-page form stretched every numeric input the
// full width of the screen: crates, loose eggs, broken eggs, deaths, age... all
// small numbers in very wide boxes, which made the form feel far heavier than
// the task. NumField is deliberately narrow, CalcField is visibly read-only.

import type { ComponentType, ReactNode } from "react"
import { Label } from "@/components/ui/label"
import { Input } from "@/components/ui/input"
import { cn } from "@/lib/utils"

/**
 * One hue per section, so a long form can be navigated by colour rather than by
 * reading every heading. The hue is chosen for the subject — amber for eggs,
 * rose for losses, emerald for live birds — not picked from a rotation, so the
 * colour carries meaning instead of decorating.
 *
 * Written out as whole class strings on purpose: Tailwind cannot see a class
 * built by interpolation, and would strip these from the bundle.
 */
export type SectionAccent =
  | "sky" | "amber" | "rose" | "emerald" | "orange" | "violet" | "slate" | "indigo"

const ACCENT: Record<SectionAccent, { header: string; rail: string; title: string; icon: string; badge: string }> = {
  sky:     { header: "bg-sky-100 border-sky-200",         rail: "bg-sky-600",     title: "text-sky-900",     icon: "text-sky-700",     badge: "border-sky-300 bg-sky-50 text-sky-800" },
  amber:   { header: "bg-amber-100 border-amber-200",     rail: "bg-amber-600",   title: "text-amber-900",   icon: "text-amber-700",   badge: "border-amber-300 bg-amber-50 text-amber-800" },
  rose:    { header: "bg-rose-100 border-rose-200",       rail: "bg-rose-600",    title: "text-rose-900",    icon: "text-rose-700",    badge: "border-rose-300 bg-rose-50 text-rose-800" },
  emerald: { header: "bg-emerald-100 border-emerald-200", rail: "bg-emerald-600", title: "text-emerald-900", icon: "text-emerald-700", badge: "border-emerald-300 bg-emerald-50 text-emerald-800" },
  orange:  { header: "bg-orange-100 border-orange-200",   rail: "bg-orange-600",  title: "text-orange-900",  icon: "text-orange-700",  badge: "border-orange-300 bg-orange-50 text-orange-800" },
  violet:  { header: "bg-violet-100 border-violet-200",   rail: "bg-violet-600",  title: "text-violet-900",  icon: "text-violet-700",  badge: "border-violet-300 bg-violet-50 text-violet-800" },
  slate:   { header: "bg-slate-200 border-slate-300",     rail: "bg-slate-500",   title: "text-slate-900",   icon: "text-slate-600",   badge: "border-slate-300 bg-slate-50 text-slate-700" },
  indigo:  { header: "bg-indigo-100 border-indigo-200",   rail: "bg-indigo-600",  title: "text-indigo-900",  icon: "text-indigo-700",  badge: "border-indigo-300 bg-indigo-50 text-indigo-800" },
}

export function FormSectionCard({
  title, description, badge, accent = "slate", icon: Icon, children,
}: {
  title: string
  description?: string
  /** Short status shown on the right of the header, e.g. "682 eggs". */
  badge?: string
  accent?: SectionAccent
  icon?: ComponentType<{ className?: string }>
  children: ReactNode
}) {
  const a = ACCENT[accent]
  return (
    <section className="overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm">
      <header className={cn("flex flex-wrap items-center justify-between gap-2 border-b px-4 py-2.5", a.header)}>
        <div className="flex min-w-0 items-center gap-2.5">
          {/* A short colour rail rather than a full border: it reads at a glance
              when scrolling without turning the header into a solid block. */}
          <span aria-hidden className={cn("h-8 w-1 shrink-0 rounded-full", a.rail)} />
          {Icon && <Icon className={cn("h-4 w-4 shrink-0", a.icon)} />}
          <div className="min-w-0">
            <h3 className={cn("text-sm font-semibold", a.title)}>{title}</h3>
            {description && <p className="mt-0.5 text-xs text-slate-500">{description}</p>}
          </div>
        </div>
        {badge && (
          <span className={cn(
            "shrink-0 rounded-full border px-2.5 py-0.5 text-xs font-medium tabular-nums",
            a.badge,
          )}>
            {badge}
          </span>
        )}
      </header>
      <div className="p-4">{children}</div>
    </section>
  )
}

/**
 * A compact numeric input.
 *
 * `text` mode keeps the value as a string so an empty box stays empty rather
 * than snapping to 0 — the form distinguishes "not entered" from "zero" for
 * meaty / soft / lost eggs, which are nullable columns.
 */
export function NumField({
  label, value, onChange, text = false, min = 0, disabled,
}: {
  label: string
  value: number | string
  onChange: (value: number | string) => void
  text?: boolean
  min?: number
  disabled?: boolean
}) {
  return (
    <div className="space-y-1">
      <Label className="text-xs text-slate-600">{label}</Label>
      <Input
        type="number"
        min={min}
        inputMode="numeric"
        disabled={disabled}
        className="h-9 tabular-nums"
        value={text ? (value as string) : String(value ?? 0)}
        onChange={(e) => {
          const raw = e.target.value
          onChange(text ? raw : Number(raw) || 0)
        }}
      />
    </div>
  )
}

/** A calculated, read-only value. Styled so it cannot be mistaken for an input. */
export function CalcField({
  label, value, tone,
}: {
  label: string
  value: string
  tone?: "good" | "bad"
}) {
  return (
    <div className="space-y-1">
      <Label className="text-xs text-slate-600">
        {label} <span className="text-slate-400">(auto)</span>
      </Label>
      <output
        aria-label={`${label}, calculated`}
        className={cn(
          "flex h-9 items-center rounded-md border border-dashed px-3 text-sm font-medium tabular-nums",
          // The toned states are deepened to sit alongside the section headers;
          // the neutral one stays quiet on purpose, or every calculated box
          // would compete with the numbers that actually need attention.
          tone === "good" ? "border-emerald-400 bg-emerald-100 text-emerald-900"
            : tone === "bad" ? "border-red-400 bg-red-100 text-red-900"
            : "border-slate-300 bg-slate-50 text-slate-700",
        )}
      >
        {value}
      </output>
    </div>
  )
}
