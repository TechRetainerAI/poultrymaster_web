"use client"

// Smart Repeat / Copy Previous Entry — the shared UI.
//
//   <RepeatPreviousButton>   "Repeat previous" on a NEW form. It only fills the
//                            form; it never saves anything.
//   <PrefilledBanner>        "Prefilled from previous entry — review before
//                            saving.", what was copied, what needs checking,
//                            what was dropped because it is no longer valid,
//                            and what is never copied.
//   <ReviewMark>             a "Check" tag beside a field copied as REVIEW,
//                            shown until the person edits or confirms it.
//
// The rules themselves live in lib/repeat/repeat-previous.ts and one policy
// file per form (lib/repeat/policies.ts).

import { AlertTriangle, Copy, Info, X } from "lucide-react"
import { Button } from "@/components/ui/button"
import { cn } from "@/lib/utils"
import type { RepeatPrefill } from "@/lib/repeat/repeat-previous"

export function RepeatPreviousButton({ available, label, onClick, className, size = "sm" }: {
  /** False when there is no previous entry to repeat (button disabled, says why). */
  available: boolean
  /** Short description of what would be repeated, e.g. "Layer Mash · 12 Sep". */
  label?: string | null
  onClick: () => void
  className?: string
  size?: "sm" | "default"
}) {
  return (
    <Button type="button" variant="outline" size={size} className={cn("gap-1", className)} disabled={!available} onClick={onClick}
      title={available ? `Prefill this form from your last entry${label ? ` (${label})` : ""}. Nothing is saved until you press Save.` : "No previous entry to repeat yet."}>
      <Copy className="h-4 w-4" /> Repeat previous
    </Button>
  )
}

export function PrefilledBanner<T>({ prefill, fieldLabels, onClear, unconfirmed = [], confirmed = false, onConfirmedChange }: {
  prefill: RepeatPrefill<T>
  /** Human labels for field keys ("quantityUsed" -> "Quantity"). */
  fieldLabels: Record<string, string>
  /** Discard the prefill and start from an empty form. */
  onClear: () => void
  /** Review fields still holding the copied value (see unconfirmedFields). */
  unconfirmed?: string[]
  confirmed?: boolean
  onConfirmedChange?: (v: boolean) => void
}) {
  const name = (k: string) => fieldLabels[k] ?? k
  const copied = Object.keys(prefill.values).filter((k) => !prefill.review.includes(k) && fieldLabels[k])
  return (
    <div role="status" className="rounded-md border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900 space-y-1.5">
      <div className="flex items-start justify-between gap-2">
        <div className="flex gap-2 font-medium">
          <Copy className="h-4 w-4 mt-0.5 shrink-0" />
          Prefilled from previous entry — review before saving.
        </div>
        <button type="button" onClick={onClear} className="text-amber-800 hover:text-amber-950 inline-flex items-center gap-1 text-xs" title="Clear the copied values">
          <X className="h-3.5 w-3.5" /> Clear
        </button>
      </div>
      <div className="text-xs text-amber-800 pl-6 space-y-1">
        <div>From the {prefill.source.noun} of {prefill.source.date ?? "—"}: {prefill.source.label}. This is a NEW {prefill.source.noun}; the old one is not changed or re-posted.</div>
        {copied.length > 0 && <div>Copied: {copied.map(name).join(", ")}.</div>}
        {prefill.review.length > 0 && (
          <div className="flex gap-1"><AlertTriangle className="h-3.5 w-3.5 mt-0.5 shrink-0" /> Check before saving: <strong>{prefill.review.map(name).join(", ")}</strong> — copied from last time, may not be right today.</div>
        )}
        {prefill.dropped.map((d) => (
          <div key={d.field} className="flex gap-1"><AlertTriangle className="h-3.5 w-3.5 mt-0.5 shrink-0" /> {name(d.field)}: {d.reason}</div>
        ))}
        {prefill.neverCopied.filter((d) => fieldLabels[d.field]).length > 0 && (
          <div className="flex gap-1"><Info className="h-3.5 w-3.5 mt-0.5 shrink-0" /> Not copied (enter fresh): {prefill.neverCopied.filter((d) => fieldLabels[d.field]).map((d) => name(d.field)).join(", ")}.</div>
        )}
        {unconfirmed.length > 0 && onConfirmedChange && (
          <label className="flex items-center gap-2 pt-1 font-medium text-amber-900">
            <input type="checkbox" className="h-4 w-4" checked={confirmed} onChange={(e) => onConfirmedChange(e.target.checked)} />
            I&apos;ve checked these: {unconfirmed.map(name).join(", ")} are right for this entry.
          </label>
        )}
        {prefill.dateField && (
          <div>Date set to today ({String((prefill.values as Record<string, unknown>)[prefill.dateField] ?? "—")}), not the previous entry&apos;s date.</div>
        )}
      </div>
    </div>
  )
}

/** A small "Check" tag for a field label; render it only while the field is unconfirmed. */
export function ReviewMark({ show }: { show: boolean }) {
  if (!show) return null
  return <span className="ml-1 rounded bg-amber-200 px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-amber-900">Check</span>
}

/** Ring an input while its copied value is unconfirmed. */
export const reviewRing = (show: boolean) => (show ? "ring-2 ring-amber-400 border-amber-400" : "")
