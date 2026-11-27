"use client"

// Split one line (or one expense / owner entry) across several projects --
// e.g. 100 chairs: 60 for Contract A, 40 for Contract B. The parts may add up
// to less than the whole (the rest stays General company activity) but never
// to more. Nothing is posted: this only labels the line.

import { useEffect, useState } from "react"
import { Equal, Plus, Trash2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { ProjectPicker } from "./project-picker"
import { checkSplit, splitEvenly, toSplits, type SplitBasis, type SplitRow } from "@/lib/generic/project-math"
import type { CostClass, ProjectSplit } from "@/lib/api/generic-projects"

const COST_CLASSES: { value: CostClass; label: string }[] = [
  { value: "Direct", label: "Direct project cost" },
  { value: "Shared", label: "Shared project cost" },
  { value: "Overhead", label: "Company overhead (allocated)" },
  { value: "Selling", label: "Selling / distribution" },
  { value: "Financing", label: "Financing cost" },
  { value: "Capital", label: "Capital expenditure" },
]

export function ProjectSplitEditor({
  open, onOpenChange, title, description, wholeQuantity, wholeAmount, unit, initial, onSave, showCostClass = false,
  initialCostClass = "Direct",
}: {
  open: boolean
  onOpenChange: (v: boolean) => void
  title: string
  description?: string
  /** Line quantity; offer a split by quantity when given. */
  wholeQuantity?: number | null
  wholeAmount: number
  unit?: string | null
  initial?: ProjectSplit[] | null
  onSave: (splits: ProjectSplit[], costClass: CostClass) => void | Promise<void>
  /** Expenses: say what kind of cost this is for the project P&L. */
  showCostClass?: boolean
  initialCostClass?: CostClass
}) {
  const canQty = (wholeQuantity ?? 0) > 0
  const [basis, setBasis] = useState<SplitBasis>(canQty ? "quantity" : "amount")
  const [rows, setRows] = useState<SplitRow[]>([{ projectId: null, value: 0 }])
  const [costClass, setCostClass] = useState<CostClass>(initialCostClass)
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    if (!open) return
    setCostClass(initial?.[0]?.costClass ?? initialCostClass)
    if (initial && initial.length) {
      // Shares come back from the server; show them in the basis the user is likely to think in.
      const b: SplitBasis = initial.some((s) => s.quantity != null) && canQty ? "quantity"
        : initial.some((s) => s.amount != null) ? "amount" : canQty ? "quantity" : "amount"
      setBasis(b)
      // Show what was typed when it still matches the saved share (the record
      // has not changed size since); otherwise the share of today's whole,
      // rounded like the whole is shown.
      const pick = (typed: number | undefined, share: number | undefined, whole: number, dp: number) => {
        const fromShare = Math.round((share ?? 0) * whole * 10 ** dp) / 10 ** dp
        if (typed == null) return fromShare
        if (share == null) return typed
        return Math.abs(share * whole - typed) <= Math.max(0.01, whole * 1e-6) ? typed : fromShare
      }
      setRows(initial.map((s) => ({
        projectId: s.projectId,
        value: b === "quantity" ? pick(s.quantity, s.share, wholeQuantity ?? 0, 3) : pick(s.amount, s.share, wholeAmount, 2),
      })))
    } else {
      setBasis(canQty ? "quantity" : "amount")
      setRows([{ projectId: null, value: 0 }, { projectId: null, value: 0 }])
    }
  }, [open]) // eslint-disable-line react-hooks/exhaustive-deps

  const whole = basis === "quantity" ? (wholeQuantity ?? 0) : basis === "amount" ? wholeAmount : 100
  const check = checkSplit(rows, basis, whole)
  const fmt = (n: number) => n.toLocaleString(undefined, { maximumFractionDigits: basis === "quantity" ? 3 : 2 })
  const unitLabel = basis === "quantity" ? (unit ?? "units") : basis === "amount" ? "" : "%"

  const save = async () => {
    setSaving(true)
    try {
      await onSave(toSplits(rows, basis).map((s) => (showCostClass ? { ...s, costClass } : s)), costClass)
      onOpenChange(false)
    } finally {
      setSaving(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-xl">
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>
            {description ?? "Share this between projects. Anything not given to a project stays General company activity. This only labels it: no extra sale, purchase, expense or stock is created."}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="flex flex-wrap items-end gap-3">
            <div className="space-y-1">
              <Label>Split by</Label>
              <Select value={basis} onValueChange={(v) => setBasis(v as SplitBasis)}>
                <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {canQty && <SelectItem value="quantity">Quantity</SelectItem>}
                  <SelectItem value="amount">Amount</SelectItem>
                  <SelectItem value="percent">Percentage</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <p className="text-sm text-slate-600 pb-2">
              Whole: <span className="font-medium">{fmt(whole)} {unitLabel}</span>
            </p>
          </div>

          <div className="space-y-2">
            {rows.map((r, i) => (
              <div key={i} className="flex items-center gap-2">
                <div className="flex-1">
                  <ProjectPicker value={r.projectId} allowGeneral={false} placeholder="Choose a project"
                    onChange={(v) => setRows((rs) => rs.map((x, j) => (j === i ? { ...x, projectId: v } : x)))} />
                </div>
                <NumberInput className="w-32" value={r.value || ""} min={0}
                  onChange={(e: any) => {
                    const v = Number(e?.target?.value ?? e)
                    setRows((rs) => rs.map((x, j) => (j === i ? { ...x, value: Number.isFinite(v) ? v : 0 } : x)))
                  }} />
                <span className="w-10 text-xs text-slate-500">{unitLabel}</span>
                <Button type="button" variant="ghost" size="icon" aria-label="Remove"
                  onClick={() => setRows((rs) => rs.filter((_, j) => j !== i))}><Trash2 className="h-4 w-4" /></Button>
              </div>
            ))}
            <div className="flex flex-wrap gap-2">
              <Button type="button" variant="outline" size="sm" onClick={() => setRows((rs) => [...rs, { projectId: null, value: 0 }])}>
                <Plus className="mr-1 h-4 w-4" /> Add project
              </Button>
              {/* Shares the whole equally between the chosen projects; the last
                  one takes the rounding so it always adds up exactly. */}
              <Button type="button" variant="outline" size="sm" disabled={rows.length < 1 || !(whole > 0)}
                title="Give each chosen project an equal part of the whole"
                onClick={() => setRows((rs) => splitEvenly(rs, basis, whole))}>
                <Equal className="mr-1 h-4 w-4" /> Split evenly
              </Button>
            </div>
          </div>

          {showCostClass && (
            <div className="space-y-1">
              <Label>Kind of cost</Label>
              <Select value={costClass} onValueChange={(v) => setCostClass(v as CostClass)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {COST_CLASSES.map((c) => <SelectItem key={c.value} value={c.value}>{c.label}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
          )}

          <div className={`rounded-md border p-3 text-sm ${check.ok ? "border-slate-200 bg-slate-50" : "border-rose-200 bg-rose-50 text-rose-700"}`}>
            {check.ok
              ? <>Given to projects: <b>{fmt(check.allocated)} {unitLabel}</b> · stays General: <b>{fmt(check.unallocated)} {unitLabel}</b></>
              : check.message}
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button onClick={save} disabled={!check.ok || saving}>{saving ? "Saving…" : "Use this split"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

export { COST_CLASSES }
