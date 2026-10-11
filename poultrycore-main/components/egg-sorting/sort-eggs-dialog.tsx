"use client"

// Sort a pick / Sort all available eggs (Egg Sorting Workspace).
//
// The user never retypes production: what is left to sort comes from the
// production record. They enter only how the eggs graded -- sizes and losses
// -- and the input is the sum of those lines, so a sorting always balances:
//   input = sized eggs + losses,  remaining after = available - input.

import { useEffect, useMemo, useState } from "react"
import { Loader2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Checkbox } from "@/components/ui/checkbox"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { cn } from "@/lib/utils"
import { useToast } from "@/hooks/use-toast"
import {
  EggSortingConflictError,
  saveEggSorting,
  type EggClass,
  type EggSortingPick,
  type EggSortingSession,
  type SortingLineType,
  type SortingMode,
} from "@/lib/api/egg-sorting"
import {
  LOSS_TYPES,
  cratesText,
  fmtCount,
  pct,
  pickLabel,
  sortingBalance,
  sortingBlocker,
  toApiLines,
  type ProductionDay,
} from "@/lib/production/egg-sorting"
import { formatLongDate } from "@/lib/closing/daily-closing"
import { useEggsPerCrate } from "@/hooks/use-eggs-per-crate"

type PickLabels = { first: string; second: string; third: string; fourth: string; fifth: string; sixth: string }

export interface SortTarget {
  mode: SortingMode
  /** The day the action was started from. */
  day: ProductionDay
  /** ByPick only. */
  pick?: EggSortingPick | null
  /** Combined only: other days of the same flock that still have eggs left. */
  otherDays?: ProductionDay[]
  /** Editing a draft: its saved lines, scope and date. */
  draft?: EggSortingSession | null
}

function newRequestId(): string {
  try { return crypto.randomUUID() } catch { return `${Date.now()}-${Math.random().toString(16).slice(2)}` }
}

export function SortEggsDialog({
  target, onClose, sizes, today, labels, canPost, onDone,
}: {
  target: SortTarget | null
  onClose: () => void
  sizes: EggClass[]
  today: string
  labels: PickLabels
  canPost: boolean
  onDone: (message: string, refresh: boolean) => void
}) {
  const { toast } = useToast()
  useEggsPerCrate()
  const [sortingDate, setSortingDate] = useState(today)
  const [scope, setScope] = useState<Set<number>>(new Set())
  const [qty, setQty] = useState<Record<string, string>>({})
  const [notes, setNotes] = useState("")
  const [requestId, setRequestId] = useState(newRequestId())
  const [busy, setBusy] = useState<"draft" | "post" | null>(null)

  const activeSizes = useMemo(
    () => sizes.filter((s) => s.classKind === "Size" && s.isActive).sort((a, b) => a.sortOrder - b.sortOrder || a.name.localeCompare(b.name)),
    [sizes],
  )

  // Reset each time a new target opens.
  useEffect(() => {
    if (!target) return
    const d = target.draft
    setSortingDate(d?.sortingDate?.slice(0, 10) ?? (target.day.productionDate > today ? target.day.productionDate : today))
    setScope(new Set(d?.scopeRecordIds?.length ? d.scopeRecordIds : [target.day.productionRecordId]))
    const q: Record<string, string> = {}
    for (const l of d?.lines ?? []) {
      const key = l.lineType === "SizedOutput" ? `size:${l.eggSizeId}` : `loss:${l.lineType}`
      q[key] = String(l.quantity)
    }
    setQty(q)
    setNotes(d?.notes ?? "")
    setRequestId(newRequestId())
    setBusy(null)
  }, [target, today])

  const allDays = useMemo(() => {
    if (!target) return []
    const seen = new Map<number, ProductionDay>()
    for (const d of [target.day, ...(target.otherDays ?? [])]) seen.set(d.productionRecordId, d)
    return [...seen.values()].sort((a, b) => a.productionDate.localeCompare(b.productionDate))
  }, [target])

  const available = useMemo(() => {
    if (!target) return 0
    if (target.mode === "ByPick") return Math.max(0, target.pick?.available ?? 0)
    return allDays.filter((d) => scope.has(d.productionRecordId)).reduce((s, d) => s + Math.max(0, d.left), 0)
  }, [target, allDays, scope])

  const lineInputs = useMemo(() => [
    ...activeSizes.map((s) => ({ key: `size:${s.eggSizeId}`, lineType: "SizedOutput" as SortingLineType, eggSizeId: s.eggSizeId, text: qty[`size:${s.eggSizeId}`] ?? "" })),
    ...LOSS_TYPES.map((l) => ({ key: `loss:${l.key}`, lineType: l.key as SortingLineType, eggSizeId: null, text: qty[`loss:${l.key}`] ?? "" })),
  ], [activeSizes, qty])

  const bal = sortingBalance(available, lineInputs)
  const blocker = sortingBlocker(bal)
  const earliest = allDays.filter((d) => scope.has(d.productionRecordId)).map((d) => d.productionDate).sort()[0] ?? target?.day.productionDate
  const dateProblem = sortingDate > today ? "The sorting date cannot be in the future."
    : earliest && sortingDate < earliest ? "Eggs cannot be sorted before they were collected." : null

  const submit = async (post: boolean) => {
    if (!target) return
    setBusy(post ? "post" : "draft")
    try {
      const recordIds = target.mode === "ByPick" ? [target.day.productionRecordId] : [...scope]
      await saveEggSorting({
        sortingMode: target.mode,
        sortingDate,
        productionRecordIds: recordIds,
        pickNumber: target.mode === "ByPick" ? target.pick?.pickNumber ?? null : null,
        lines: toApiLines(lineInputs),
        notes: notes.trim() || null,
        clientRequestId: target.draft ? null : requestId,
        post,
      }, target.draft?.sessionId ?? null)
      onDone(post
        ? `${fmtCount(bal.input)} eggs sorted: ${fmtCount(bal.sized)} into sizes${bal.loss ? `, ${fmtCount(bal.loss)} lost` : ""}.`
        : "Draft saved. It moves no stock until you post it.", true)
    } catch (e) {
      const conflict = e instanceof EggSortingConflictError
      toast({ title: conflict ? "Not enough eggs left" : post ? "Not posted" : "Not saved", description: e instanceof Error ? e.message : "", variant: "destructive" })
      if (conflict) onDone("", true)
    } finally {
      setBusy(null)
    }
  }

  if (!target) return null
  const { day, pick, mode } = target
  const title = mode === "ByPick"
    ? `Sort ${pick ? pickLabel(pick.pickNumber, labels) : "pick"}`
    : "Sort all available eggs"

  return (
    <Dialog open={!!target} onOpenChange={(v) => { if (!v && !busy) onClose() }}>
      {/* Phone: full screen, one size per row, the totals and buttons pinned
          to the bottom. From sm up: the wide dialog built to fit a laptop
          screen without scrolling, every section kept to as few rows as it
          can be. */}
      <DialogContent className="left-0 top-0 h-[100dvh] max-h-[100dvh] w-full max-w-full translate-x-0 translate-y-0 grid-cols-1 content-start gap-3 overflow-x-hidden overflow-y-auto rounded-none p-4 pb-0
        sm:left-[50%] sm:top-[50%] sm:h-auto sm:max-h-[96vh] sm:w-[95vw] sm:max-w-6xl sm:translate-x-[-50%] sm:translate-y-[-50%] sm:rounded-lg sm:p-5">
        <DialogHeader>
          <DialogTitle className="pr-8 text-left">{title}{target.draft ? ` — draft ${target.draft.sessionNo}` : ""}</DialogTitle>
          <DialogDescription className="text-left">
            {day.flockName}{day.batchName ? ` · ${day.batchName}` : ""}{day.houseName ? ` · ${day.houseName}` : ""}
          </DialogDescription>
        </DialogHeader>

        {/* What is being sorted (read from production, never retyped), the
            sorting date and notes: one row. */}
        {(() => {
          const dateField = (
            <div className="space-y-1">
              <Label htmlFor="es-date" className="text-[11px] uppercase tracking-wide text-slate-500">Sorting date</Label>
              <Input id="es-date" type="date" className="h-9" value={sortingDate} min={earliest} max={today} onChange={(e) => setSortingDate(e.target.value)} />
              {dateProblem && <p className="text-xs text-rose-700">{dateProblem}</p>}
            </div>
          )
          const notesField = (
            <div className="space-y-1">
              <Label htmlFor="es-notes" className="text-[11px] uppercase tracking-wide text-slate-500">Notes</Label>
              <Input id="es-notes" className="h-9" value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Optional" />
            </div>
          )
          return mode === "ByPick" && pick ? (
            <div className="grid grid-cols-2 items-end gap-2 sm:grid-cols-4 lg:grid-cols-[repeat(4,minmax(0,1fr))_11rem_minmax(0,1.3fr)]">
              <Fact label="Production date" value={formatLongDate(day.productionDate)} />
              <Fact label="Collected" value={fmtCount(pick.pickGross)} sub={cratesText(pick.pickGross)} />
              <Fact label="Already sorted" value={fmtCount(pick.pickSorted)} />
              <Fact label="Left to sort" value={fmtCount(pick.available)} sub={cratesText(pick.available)} strong />
              {dateField}
              {notesField}
            </div>
          ) : (
            <div className="grid grid-cols-1 gap-3 lg:grid-cols-[minmax(0,2fr)_11rem_minmax(0,1fr)] lg:items-start">
              <div className="min-w-0 space-y-1">
                <Label className="text-[11px] uppercase tracking-wide text-slate-500">
                  Eggs from <span className="block normal-case tracking-normal sm:inline">— oldest used first (earliest day, then pick)</span>
                </Label>
                <div className="max-h-32 divide-y divide-slate-100 overflow-y-auto rounded-lg border border-slate-200">
                  {allDays.map((d) => (
                    <label key={d.productionRecordId} className={cn("flex items-center gap-3 px-3 py-1.5 text-sm", d.left <= 0 && "opacity-60")}>
                      <Checkbox
                        checked={scope.has(d.productionRecordId)}
                        disabled={d.left <= 0 && !scope.has(d.productionRecordId)}
                        onCheckedChange={(v) => setScope((prev) => {
                          const next = new Set(prev)
                          if (v === true) next.add(d.productionRecordId); else next.delete(d.productionRecordId)
                          return next
                        })} />
                      <span className="min-w-0 flex-1 truncate">
                        <span className="font-medium text-slate-900">{formatLongDate(d.productionDate)}</span>
                        <span className="ml-2 text-slate-500">
                          {d.picks.filter((p) => p.available > 0).map((p) => `${pickLabel(p.pickNumber, labels).split(" (")[0]} ${fmtCount(p.available)}`).join(" · ") || "nothing left"}
                        </span>
                      </span>
                      <span className="tabular-nums font-medium">{fmtCount(d.left)}</span>
                    </label>
                  ))}
                </div>
              </div>
              {dateField}
              {notesField}
            </div>
          )
        })()}

        {activeSizes.length === 0 && (
          <p className="rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-900">
            No active egg sizes. Add them under Sizes &amp; settings first.
          </p>
        )}

        {/* Phone: one size (then each loss) per row, the box to type in on the
            right, crates and share underneath. */}
        <div className="divide-y divide-slate-100 rounded-lg border border-slate-200 sm:hidden">
          <div className="bg-slate-50 px-3 py-1.5 text-[11px] font-medium uppercase tracking-wider text-slate-500">Egg size / grade</div>
          {lineInputs.map((l, i) => {
            const n = Number(l.text) || 0
            const isLoss = l.lineType !== "SizedOutput"
            const name = isLoss ? LOSS_TYPES.find((x) => x.key === l.lineType)?.label : activeSizes.find((s) => s.eggSizeId === l.eggSizeId)?.name
            return (
              <div key={l.key} className={cn("flex items-center gap-3 px-3 py-2", isLoss && "bg-rose-50/50", i === activeSizes.length && "border-t-2 border-slate-300")}>
                <div className="min-w-0 flex-1">
                  <div className={cn("font-medium", isLoss ? "text-rose-800" : "text-slate-900")}>{name}</div>
                  <div className="text-[11px] text-slate-500">
                    {isLoss && <span className="text-rose-700">loss — not stocked · </span>}
                    {n ? `${cratesText(n)} · ${pct(n, bal.input)}` : "—"}
                  </div>
                </div>
                <Input inputMode="numeric" className="h-10 w-24 text-right text-base" value={l.text} placeholder="0"
                  aria-label={`Eggs — ${name}`}
                  onChange={(e) => setQty((p) => ({ ...p, [l.key]: e.target.value.replace(/[^\d]/g, "") }))} />
              </div>
            )
          })}
        </div>

        {/* Grading grid: one column per size / loss, the measures as rows. */}
        <div className="hidden overflow-x-auto rounded-lg border border-slate-200 sm:block">
          <table className="w-full text-sm">
            <tbody className="divide-y divide-slate-100">
              <tr className="bg-slate-50">
                <th scope="row" className="sticky left-0 z-10 whitespace-nowrap bg-slate-50 px-3 py-2 text-left text-xs font-medium uppercase tracking-wider text-slate-500">
                  Egg size / grade
                </th>
                {lineInputs.map((l, i) => {
                  const isLoss = l.lineType !== "SizedOutput"
                  const name = isLoss ? LOSS_TYPES.find((x) => x.key === l.lineType)?.label : activeSizes.find((s) => s.eggSizeId === l.eggSizeId)?.name
                  return (
                    <th key={l.key} scope="col"
                      className={cn("min-w-[5.5rem] px-2 py-2 text-center align-bottom", isLoss && "bg-rose-50", i === activeSizes.length && "border-l-2 border-slate-300")}>
                      <span className={cn("block font-semibold", isLoss ? "text-rose-800" : "text-slate-900")}>{name}</span>
                      {isLoss && <span className="block text-[10px] font-normal text-rose-700">loss — not stocked</span>}
                    </th>
                  )
                })}
              </tr>
              <tr>
                <th scope="row" className="sticky left-0 z-10 bg-white px-3 py-1.5 text-left text-xs font-medium uppercase tracking-wider text-slate-500">Eggs</th>
                {lineInputs.map((l, i) => (
                  <td key={l.key} className={cn("px-2 py-1.5", l.lineType !== "SizedOutput" && "bg-rose-50/40", i === activeSizes.length && "border-l-2 border-slate-300")}>
                    <Input inputMode="numeric" className="h-8 text-right" value={l.text} placeholder="0"
                      aria-label={`Eggs — ${l.lineType === "SizedOutput" ? activeSizes.find((s) => s.eggSizeId === l.eggSizeId)?.name : LOSS_TYPES.find((x) => x.key === l.lineType)?.label}`}
                      onChange={(e) => setQty((p) => ({ ...p, [l.key]: e.target.value.replace(/[^\d]/g, "") }))} />
                  </td>
                ))}
              </tr>
              <tr>
                <th scope="row" className="sticky left-0 z-10 bg-white px-3 py-1.5 text-left text-xs font-medium uppercase tracking-wider text-slate-500">Crates</th>
                {lineInputs.map((l, i) => {
                  const n = Number(l.text) || 0
                  return (
                    <td key={l.key} className={cn("px-2 py-1.5 text-center text-xs text-slate-500", l.lineType !== "SizedOutput" && "bg-rose-50/40", i === activeSizes.length && "border-l-2 border-slate-300")}>
                      {n ? cratesText(n) : "—"}
                    </td>
                  )
                })}
              </tr>
              <tr>
                <th scope="row" className="sticky left-0 z-10 bg-white px-3 py-1.5 text-left text-xs font-medium uppercase tracking-wider text-slate-500">% of sorted</th>
                {lineInputs.map((l, i) => {
                  const n = Number(l.text) || 0
                  return (
                    <td key={l.key} className={cn("px-2 py-1.5 text-center tabular-nums text-slate-600", l.lineType !== "SizedOutput" && "bg-rose-50/40", i === activeSizes.length && "border-l-2 border-slate-300")}>
                      {n ? pct(n, bal.input) : "—"}
                    </td>
                  )
                })}
              </tr>
            </tbody>
          </table>
        </div>

        {/* Totals and buttons. On a phone they stay pinned to the bottom while
            the sizes scroll, so the balance is always in view. */}
        <div className="sticky bottom-0 -mx-4 space-y-2 border-t border-slate-200 bg-white px-4 pb-4 pt-3 sm:static sm:mx-0 sm:space-y-3 sm:border-0 sm:p-0">
        {/* Live balance, one strip */}
        <div className="flex flex-wrap items-center gap-x-5 gap-y-1 rounded-lg border border-slate-200 bg-slate-50 px-3 py-2 text-sm">
          <Tally label="Available" value={fmtCount(bal.available)} />
          <Tally label="Into sizes" value={fmtCount(bal.sized)} />
          <Tally label="Loss" value={fmtCount(bal.loss)} />
          <Tally label="Sorted now" value={fmtCount(bal.input)} strong />
          <Tally label="Left unsorted after" value={fmtCount(bal.remainingAfter)}
            tone={bal.remainingAfter < 0 ? "bad" : bal.remainingAfter === 0 && bal.input > 0 ? "good" : undefined} />
        </div>
        {blocker && bal.input > 0 && <p className="text-sm text-rose-700">{blocker}</p>}
        {!blocker && bal.remainingAfter > 0 && (
          <p className="text-xs text-slate-500">Partial sorting: {fmtCount(bal.remainingAfter)} eggs stay unsorted and can be sorted later.</p>
        )}

        <DialogFooter className="grid grid-cols-3 gap-2 sm:flex">
          <Button variant="outline" onClick={onClose} disabled={!!busy}>Cancel</Button>
          <Button variant="outline" onClick={() => void submit(false)}
            disabled={!!busy || !!dateProblem || bal.invalidLines > 0 || (mode === "Combined" && scope.size === 0)}>
            {busy === "draft" && <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />} Save draft
          </Button>
          <Button onClick={() => void submit(true)} disabled={!canPost || !!busy || !!blocker || !!dateProblem || activeSizes.length === 0}
            className="bg-emerald-600 text-white hover:bg-emerald-700">
            {busy === "post" && <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />} Post sorting
          </Button>
        </DialogFooter>
        </div>
      </DialogContent>
    </Dialog>
  )
}

function Fact({ label, value, sub, strong, tone }: { label: string; value: string; sub?: string; strong?: boolean; tone?: "bad" | "good" }) {
  return (
    <div className="rounded-lg border border-slate-200 bg-white px-3 py-1.5">
      <div className="text-[11px] uppercase tracking-wide text-slate-500">{label}</div>
      <div className={cn("tabular-nums", strong ? "font-bold" : "font-semibold",
        tone === "bad" ? "text-rose-700" : tone === "good" ? "text-emerald-700" : "text-slate-900")}>{value}</div>
      {sub && <div className="text-[11px] text-slate-500">{sub}</div>}
    </div>
  )
}

function Tally({ label, value, strong, tone }: { label: string; value: string; strong?: boolean; tone?: "bad" | "good" }) {
  return (
    <span className="whitespace-nowrap">
      <span className="text-xs text-slate-500">{label}</span>{" "}
      <b className={cn("tabular-nums", strong ? "font-bold" : "font-semibold",
        tone === "bad" ? "text-rose-700" : tone === "good" ? "text-emerald-700" : "text-slate-900")}>{value}</b>
    </span>
  )
}
