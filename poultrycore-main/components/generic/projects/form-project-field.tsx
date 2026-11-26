"use client"

// The pieces an EXISTING Generic transaction form adds to support projects:
//   <RelatedProjectField>  "Related Project / Contract" on the header
//   <LineProjectButton>    per-line split (100 chairs: 60 to A, 40 to B)
//   loadDocumentProjects() what a saved document is assigned to, for edits
// All of them render nothing when the company has not switched the module on,
// so the forms look and behave exactly as before for everyone else.

import { useState } from "react"
import { Briefcase, Split } from "lucide-react"
import { Label } from "@/components/ui/label"
import { Button } from "@/components/ui/button"
import { cn } from "@/lib/utils"
import { useProjectOptions, useProjectsEnabled } from "@/hooks/use-generic-projects"
import { getAllocations, type CostClass, type ProjectSplit } from "@/lib/api/generic-projects"
import { ProjectPicker } from "./project-picker"
import { ProjectSplitEditor } from "./project-split-editor"

export function RelatedProjectField({
  value, onChange, className, hint, label = "Related project / contract", disabled,
}: {
  value: number | null
  onChange: (v: number | null) => void
  className?: string
  hint?: string
  label?: string
  disabled?: boolean
}) {
  const { enabled } = useProjectsEnabled()
  if (!enabled) return null
  return (
    <div className={cn("space-y-1", className)}>
      <Label className="flex items-center gap-1"><Briefcase className="h-3.5 w-3.5 text-slate-400" />{label}</Label>
      <ProjectPicker value={value} onChange={onChange} disabled={disabled} />
      {hint && <p className="text-[11px] text-slate-500">{hint}</p>}
    </div>
  )
}

/** A line's own split. null/empty = follows the header project. */
export function LineProjectButton({
  splits, onChange, headerProjectId, description, wholeQuantity, wholeAmount, unit, showCostClass,
}: {
  splits: ProjectSplit[] | null | undefined
  onChange: (s: ProjectSplit[] | null) => void
  headerProjectId: number | null
  description: string
  wholeQuantity?: number | null
  wholeAmount: number
  unit?: string | null
  showCostClass?: boolean
}) {
  const { enabled } = useProjectsEnabled()
  const { options } = useProjectOptions()
  const [open, setOpen] = useState(false)
  if (!enabled) return null
  const name = (id: number) => options.find((o) => o.projectId === id)?.projectNumber ?? `#${id}`
  const own = splits && splits.length > 0
  const text = own
    ? splits!.map((s) => `${name(s.projectId)}${s.quantity != null ? ` ${s.quantity}` : s.amount != null ? "" : s.share != null && s.share < 1 ? ` ${Math.round(s.share * 100)}%` : ""}`).join(" · ")
    : headerProjectId ? `${name(headerProjectId)} (as above)` : "General"
  return (
    <>
      <button type="button" onClick={() => setOpen(true)}
        className={cn("mt-1 inline-flex items-center gap-1 rounded px-1 text-[11px] hover:bg-slate-100", own ? "text-indigo-700" : "text-slate-500")}
        title="Split this line between projects">
        <Split className="h-3 w-3" />Project: {text}
      </button>
      {own && (
        <Button type="button" variant="link" size="sm" className="h-auto px-1 text-[11px]" onClick={() => onChange(null)}>use header</Button>
      )}
      <ProjectSplitEditor open={open} onOpenChange={setOpen} title={`Projects for: ${description || "this line"}`}
        wholeQuantity={wholeQuantity} wholeAmount={wholeAmount} unit={unit} initial={splits ?? undefined}
        showCostClass={showCostClass}
        onSave={(s: ProjectSplit[], _c: CostClass) => onChange(s.length ? s : null)} />
    </>
  )
}

/**
 * What a saved document is assigned to, shaped for a form: a header project when
 * every line (or the whole document) sits wholly on one project, and per-line
 * splits otherwise. lineIds are the document's line ids in display order.
 */
export async function loadDocumentProjects(
  documentType: "Sale" | "Purchase" | "Expense" | "OwnerEntry",
  documentId: number,
  lineIds?: number[],
): Promise<{ projectId: number | null; lines: (ProjectSplit[] | null)[] }> {
  try {
    const v = await getAllocations(documentType, documentId)
    if (!lineIds) {
      const a = v.active.filter((x) => x.lineId == null)
      if (a.length === 1 && a[0].share >= 0.999999) return { projectId: a[0].projectId, lines: [] }
      return { projectId: null, lines: a.length ? [a.map((x) => ({ projectId: x.projectId, share: x.share, costClass: x.costClass }))] : [] }
    }
    const per = lineIds.map((id) => v.active.filter((x) => x.lineId === id))
    const whole = per.every((p) => p.length === 1 && p[0].share >= 0.999999) && new Set(per.map((p) => p[0]?.projectId)).size === 1
    if (whole && per.length) return { projectId: per[0][0].projectId, lines: lineIds.map(() => null) }
    return { projectId: null, lines: per.map((p) => (p.length ? p.map((x) => ({ projectId: x.projectId, share: x.share, costClass: x.costClass })) : null)) }
  } catch {
    return { projectId: null, lines: [] }
  }
}

// ---------------------------------------------------------------- one-amount documents

/** The project part of an expense / owner entry form. */
export interface SingleProjectValue {
  projectId: number | null
  /** Shared between several projects; when set it wins over projectId. */
  splits: ProjectSplit[] | null
  costClass: CostClass
}

export const EMPTY_SINGLE_PROJECT: SingleProjectValue = { projectId: null, splits: null, costClass: "Direct" }

/** What to send as "projects" for a one-amount document. */
export function singleAssignment(v: SingleProjectValue) {
  if (v.splits && v.splits.length) return { splits: v.splits.map((s) => ({ ...s, costClass: s.costClass ?? v.costClass })) }
  return { projectId: v.projectId, costClass: v.costClass }
}

export async function loadSingleProject(documentType: "Expense" | "OwnerEntry" | "Loan", id: number): Promise<SingleProjectValue> {
  try {
    const v = await getAllocations(documentType, id)
    const a = v.active.filter((x) => x.lineId == null)
    if (a.length === 0) return EMPTY_SINGLE_PROJECT
    if (a.length === 1 && a[0].share >= 0.999999) return { projectId: a[0].projectId, splits: null, costClass: a[0].costClass }
    return { projectId: null, splits: a.map((x) => ({ projectId: x.projectId, share: x.share, costClass: x.costClass })), costClass: a[0].costClass }
  } catch {
    return EMPTY_SINGLE_PROJECT
  }
}

const KINDS: { value: CostClass; label: string }[] = [
  { value: "Direct", label: "Direct project cost" },
  { value: "Shared", label: "Shared project cost" },
  { value: "Overhead", label: "Company overhead (allocated)" },
  { value: "Selling", label: "Selling / distribution" },
  { value: "Financing", label: "Financing cost" },
  { value: "Capital", label: "Capital expenditure" },
]

export function SingleProjectField({
  value, onChange, amount, showCostClass = true, label = "Related project / contract", hint, className,
}: {
  value: SingleProjectValue
  onChange: (v: SingleProjectValue) => void
  amount: number
  showCostClass?: boolean
  label?: string
  hint?: string
  className?: string
}) {
  const { enabled } = useProjectsEnabled()
  const { options } = useProjectOptions()
  const [open, setOpen] = useState(false)
  if (!enabled) return null
  const split = value.splits && value.splits.length > 0
  const name = (id: number) => options.find((o) => o.projectId === id)?.projectNumber ?? `#${id}`
  return (
    <div className={cn("space-y-1", className)}>
      <Label className="flex items-center gap-1"><Briefcase className="h-3.5 w-3.5 text-slate-400" />{label}</Label>
      {split ? (
        <div className="flex items-center gap-2 rounded-md border border-indigo-200 bg-indigo-50/50 px-3 py-2 text-sm">
          <span className="flex-1 truncate">Shared: {value.splits!.map((s) => `${name(s.projectId)} ${s.amount != null ? s.amount.toLocaleString() : `${Math.round((s.share ?? 0) * 100)}%`}`).join(" · ")}</span>
          <Button type="button" variant="ghost" size="sm" onClick={() => setOpen(true)}>Change</Button>
          <Button type="button" variant="ghost" size="sm" onClick={() => onChange({ ...value, splits: null })}>One project</Button>
        </div>
      ) : (
        <div className="flex gap-2">
          <div className="flex-1"><ProjectPicker value={value.projectId} onChange={(p) => onChange({ ...value, projectId: p })} /></div>
          <Button type="button" variant="outline" size="icon" title="Share between several projects" onClick={() => setOpen(true)} disabled={!(amount > 0)}>
            <Split className="h-4 w-4" />
          </Button>
        </div>
      )}
      {showCostClass && (value.projectId != null || split) && (
        <select className="mt-1 w-full rounded-md border border-slate-200 bg-white px-2 py-1.5 text-sm" value={value.costClass}
          onChange={(e) => onChange({ ...value, costClass: e.target.value as CostClass })} aria-label="Kind of cost">
          {KINDS.map((k) => <option key={k.value} value={k.value}>{k.label}</option>)}
        </select>
      )}
      {hint && <p className="text-[11px] text-slate-500">{hint}</p>}
      <ProjectSplitEditor open={open} onOpenChange={setOpen} title="Share between projects" wholeAmount={amount}
        initial={value.splits ?? (value.projectId ? [{ projectId: value.projectId, share: 1 }] : undefined)}
        showCostClass={showCostClass} initialCostClass={value.costClass}
        onSave={(s, c) => onChange({ projectId: null, splits: s.length ? s : null, costClass: c })} />
    </div>
  )
}
