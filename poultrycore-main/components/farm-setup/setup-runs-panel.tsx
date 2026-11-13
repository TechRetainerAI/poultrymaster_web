"use client"

// Completed setups (migration 416): what each Initial Farm Setup created, with
// Edit / Delete per item and Undo for the whole setup.
//
// Undo is all or nothing and the server refuses it while anything has been
// recorded against what the setup created; the reasons it gives are shown on
// the card before anyone clicks. Item deletes go through the ordinary pages'
// endpoints, so they keep their own guards (a flock with records cannot be
// deleted, a house with flocks cannot be deleted).
//
// Earlier setups (before 416, migration 417) did not record what they made.
// Their flocks and reconciliations are known; their batches and houses are only
// where those flocks are, so they start unticked and the farm decides.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { Bird, Boxes, Home, Loader2, Pencil, RotateCcw, Scale, Trash2, Undo2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Checkbox } from "@/components/ui/checkbox"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { useToast } from "@/hooks/use-toast"
import { getUserContext } from "@/lib/utils/user-context"
import { FlockEditForm } from "@/components/poultry/flock-edit-form"
import { FlockBatchEditForm } from "@/components/poultry/flock-batch-edit-form"
import { HouseEditForm } from "@/components/poultry/house-edit-form"
import { fmtInstant } from "@/lib/utils/company-datetime"
import { cn } from "@/lib/utils"
import {
  getFarmSetupRuns, reverseFarmSetupRun, getFarmSetupLegacyCandidates, reverseFarmSetupLegacy,
  type FarmSetupRun, type FarmSetupRunItem, type FarmSetupLegacyCandidate,
} from "@/lib/api/poultry-farm-setup"
import { deleteFlock } from "@/lib/api/flock"
import { deleteFlockBatch } from "@/lib/api/flock-batch"
import { deleteHouse } from "@/lib/api/house"

const KIND: Record<FarmSetupRunItem["type"], { label: string; icon: React.ComponentType<{ className?: string }> }> = {
  Batch: { label: "Batches", icon: Boxes },
  House: { label: "Houses / pens", icon: Home },
  Flock: { label: "Flocks", icon: Bird },
  Reconciliation: { label: "Batch reconciliations", icon: Scale },
}

type ItemRef = { type: FarmSetupRunItem["type"]; id: number; name: string | null }
const keyOf = (i: { type: string; id: number }) => `${i.type}:${i.id}`

function editHref(item: ItemRef): string | null {
  switch (item.type) {
    case "Batch": return `/flock-batch/${item.id}`
    case "Flock": return `/flocks/${item.id}`
    case "House": return "/poultry-setup?section=production&tab=houses"
    default: return null
  }
}

export function SetupRunsPanel({ onChanged }: { onChanged?: () => void }) {
  const { toast } = useToast()
  const [runs, setRuns] = useState<FarmSetupRun[] | null>(null)
  const [error, setError] = useState("")
  const [busy, setBusy] = useState<string | null>(null)
  const [undoing, setUndoing] = useState<FarmSetupRun | null>(null)
  const [reason, setReason] = useState("")
  // Earlier setups (417): candidates, and which of them are ticked.
  const [legacy, setLegacy] = useState<FarmSetupLegacyCandidate[]>([])
  const [ticked, setTicked] = useState<Set<string>>(new Set())
  const [undoingLegacy, setUndoingLegacy] = useState(false)
  // "Undo this setup" on one earlier setup (one setup date). `extra` = the
  // batches/pens the farm confirms that setup created; never assumed.
  const [undoGroup, setUndoGroup] = useState<{ date: string; extra: Set<string> } | null>(null)
  // Editing a flock, batch or pen opens in a popup, not a full page.
  const [editItem, setEditItem] = useState<ItemRef | null>(null)

  const load = useCallback(async () => {
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) return
    const [res, leg] = await Promise.all([getFarmSetupRuns(userId, farmId), getFarmSetupLegacyCandidates(userId, farmId)])
    if (res.success) { setRuns(res.data ?? []); setError("") }
    else setError(res.message || "Could not load your completed setups.")
    if (leg.success) {
      const rows = leg.data ?? []
      setLegacy(rows)
      // Nothing starts ticked: the farm chooses what to remove ("Select what the
      // setup made" ticks the flocks and reconciliations in one click).
      setTicked(new Set())
    }
  }, [])

  /** After a popup edit: close it, refresh the list, tell the page. */
  const afterEdit = () => { setEditItem(null); void load(); onChanged?.() }
  useEffect(() => { void load() }, [load])

  const toggle = (c: FarmSetupLegacyCandidate, on: boolean) => {
    setTicked((prev) => {
      const next = new Set(prev)
      const apply = (k: string) => (on ? next.add(k) : next.delete(k))
      apply(keyOf(c))
      // A batch takes its setup reconciliations with it.
      if (c.type === "Batch") legacy.filter((r) => r.type === "Reconciliation" && r.batchid === c.id).forEach((r) => apply(keyOf(r)))
      return next
    })
  }

  /** Earlier setups, one per setup date. A reconciliation goes with its batch. */
  const legacyDateOf = (c: FarmSetupLegacyCandidate): string => {
    if (c.type === "Reconciliation") {
      const b = legacy.find((x) => x.type === "Batch" && x.id === c.batchid)
      if (b?.setupdate) return b.setupdate.slice(0, 10)
    }
    return c.setupdate ? c.setupdate.slice(0, 10) : "unknown"
  }
  const legacyGroups = Array.from(new Set(legacy.map(legacyDateOf)))
    .sort((a, b) => (a === "unknown" ? 1 : b === "unknown" ? -1 : b.localeCompare(a)))
    .map((date) => {
      const items = legacy.filter((c) => legacyDateOf(c) === date)
      const certain = items.filter((c) => c.type === "Flock" || c.type === "Reconciliation")
      const maybe = items.filter((c) => c.type === "Batch" || c.type === "House")
      return { date, items, certain, maybe, blocked: certain.filter((c) => c.blockers.length > 0) }
    })

  const undoLegacyGroup = async () => {
    if (!undoGroup || !reason.trim()) return
    const g = legacyGroups.find((x) => x.date === undoGroup.date)
    if (!g) return
    const { userId, farmId } = getUserContext()
    setBusy("undo:legacygroup")
    const items = [...g.certain, ...g.maybe.filter((c) => undoGroup.extra.has(keyOf(c)))]
      .map((c) => ({ type: c.type, id: c.id }))
    const res = await reverseFarmSetupLegacy(items, userId, farmId, reason.trim())
    setBusy(null)
    if (res.success) {
      toast({ title: "Setup undone", description: `${items.length} item(s) that setup created were removed.` })
      setUndoGroup(null); setReason("")
      await load(); onChanged?.()
    } else {
      toast({ title: "Setup not undone", description: res.message, variant: "destructive" })
    }
  }

  const undoLegacy = async () => {
    if (!reason.trim() || ticked.size === 0) return
    const { userId, farmId } = getUserContext()
    setBusy("undo:legacy")
    const items = legacy.filter((c) => ticked.has(keyOf(c))).map((c) => ({ type: c.type, id: c.id }))
    const res = await reverseFarmSetupLegacy(items, userId, farmId, reason.trim())
    setBusy(null)
    if (res.success) {
      toast({ title: "Removed", description: `${items.length} item(s) from the earlier setup were removed.` })
      setUndoingLegacy(false); setReason("")
      await load(); onChanged?.()
    } else {
      toast({ title: "Nothing was removed", description: res.message, variant: "destructive" })
    }
  }

  const removeItem = async (scope: string, item: ItemRef) => {
    if (!window.confirm(`Delete ${item.type.toLowerCase()} "${item.name ?? item.id}"? This cannot be undone.`)) return
    const { userId, farmId } = getUserContext()
    setBusy(`${scope}:${item.type}:${item.id}`)
    const res = item.type === "Flock" ? await deleteFlock(item.id, userId, farmId)
      : item.type === "Batch" ? await deleteFlockBatch(item.id, userId, farmId)
      : await deleteHouse(item.id, userId, farmId)
    setBusy(null)
    if (res.success) {
      toast({ title: `${item.name ?? item.type} deleted` })
      await load(); onChanged?.()
    } else {
      toast({ title: "Not deleted", description: res.message, variant: "destructive" })
    }
  }

  const undo = async () => {
    if (!undoing || !reason.trim()) return
    const { userId, farmId } = getUserContext()
    setBusy(`undo:${undoing.setuprunid}`)
    const res = await reverseFarmSetupRun(undoing.setuprunid, userId, farmId, reason.trim())
    setBusy(null)
    if (res.success) {
      toast({ title: "Setup undone", description: "Everything it created has been removed." })
      setUndoing(null); setReason("")
      await load(); onChanged?.()
    } else {
      toast({ title: "Setup not undone", description: res.message, variant: "destructive" })
    }
  }

  if (error) return <p className="text-sm text-rose-700">{error}</p>
  if (!runs) return <div className="flex items-center gap-2 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading completed setups…</div>
  if (runs.length === 0 && legacy.length === 0) return null

  return (
    <section className="space-y-3">
      <div>
        <h2 className="text-base font-semibold text-slate-900">Completed setups</h2>
        <p className="text-sm text-slate-600">
          What each setup created. Edit or delete single items, or undo a whole setup while nothing has been recorded against it.
        </p>
      </div>

      {runs.map((run) => {
        const reversed = run.status === "Reversed"
        const liveFlocks = run.items.some((i) => i.type === "Flock" && !i.gone)
        const groups = (["Batch", "Reconciliation", "House", "Flock"] as const)
          .map((t) => ({ t, items: run.items.filter((i) => i.type === t) }))
          .filter((g) => g.items.length > 0)
        return (
          <div key={run.setuprunid} className={cn("overflow-hidden rounded-xl border bg-white shadow-sm", reversed ? "border-slate-200 opacity-75" : "border-slate-200")}>
            <div className="flex flex-wrap items-center gap-3 border-b border-slate-100 bg-slate-50 px-4 py-3">
              <div className="min-w-0 flex-1">
                <div className="font-semibold text-slate-900">Setup #{run.setuprunid}{run.businessdate ? ` · ${run.businessdate.slice(0, 10)}` : ""}</div>
                <div className="text-xs text-slate-500">
                  Completed {fmtInstant(run.completedat)}
                  {reversed && run.reversedat ? ` · undone ${fmtInstant(run.reversedat)}${run.reversalreason ? ` (${run.reversalreason})` : ""}` : ""}
                </div>
              </div>
              <span className={cn("rounded-full px-2.5 py-0.5 text-xs font-medium",
                reversed ? "bg-slate-200 text-slate-700" : "bg-emerald-100 text-emerald-800")}>
                {reversed ? "Undone" : "Completed"}
              </span>
              {!reversed && (
                <Button size="sm" variant="outline" className="gap-1.5 border-rose-200 text-rose-700 hover:bg-rose-50"
                  disabled={run.blockers.length > 0 || busy !== null}
                  title={run.blockers.length > 0 ? "Cannot undo: " + run.blockers.join("; ") : "Remove everything this setup created"}
                  onClick={() => { setUndoing(run); setReason("") }}>
                  <Undo2 className="h-4 w-4" /> Undo setup
                </Button>
              )}
            </div>

            {!reversed && run.blockers.length > 0 && (
              <div className="border-b border-amber-100 bg-amber-50 px-4 py-2 text-xs text-amber-900">
                Cannot be undone while things are recorded against it: {run.blockers.join("; ")}.
              </div>
            )}

            <div className="grid grid-cols-1 gap-4 p-4 md:grid-cols-2 xl:grid-cols-4">
              {groups.map(({ t, items }) => {
                const Icon = KIND[t].icon
                return (
                  <div key={t} className="min-w-0">
                    <div className="mb-1.5 flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide text-slate-500">
                      <Icon className="h-3.5 w-3.5" /> {KIND[t].label} ({items.length})
                    </div>
                    <ul className="divide-y divide-slate-100 rounded-lg border border-slate-100">
                      {items.map((item) => {
                        const href = editHref(item)
                        const key = `${run.setuprunid}:${item.type}:${item.id}`
                        // A batch's flocks go first, or they would be left pointing at nothing.
                        const blocked = item.blockers.length > 0 || (item.type === "Batch" && liveFlocks)
                        const why = item.blockers.length > 0 ? item.blockers.join("; ")
                          : item.type === "Batch" && liveFlocks ? "Delete this setup's flocks first." : ""
                        return (
                          <li key={key} className="flex items-center gap-2 px-2.5 py-1.5 text-sm">
                            <span className={cn("min-w-0 flex-1 break-words", item.gone ? "text-slate-400 line-through" : "text-slate-800")} title={item.name ?? ""}>
                              {item.name ?? `#${item.id}`}
                            </span>
                            {item.gone ? (
                              <span className="text-[11px] text-slate-400">{item.type === "Reconciliation" ? "Reversed" : "Deleted"}</span>
                            ) : !reversed && item.type !== "Reconciliation" && (
                              <>
                                {href && (
                                  (item.type === "Flock" || item.type === "Batch" || item.type === "House") ? (
                                    <Button size="icon" variant="ghost" className="h-7 w-7" title="Edit"
                                      onClick={() => setEditItem({ type: item.type, id: item.id, name: item.name })}>
                                      <Pencil className="h-3.5 w-3.5" />
                                    </Button>
                                  ) : (
                                  <Button asChild size="icon" variant="ghost" className="h-7 w-7" title="Edit">
                                    <Link href={href}><Pencil className="h-3.5 w-3.5" /></Link>
                                  </Button>
                                  )
                                )}
                                <Button size="icon" variant="ghost" className="h-7 w-7 text-rose-600 disabled:text-slate-300"
                                  disabled={blocked || busy !== null} title={blocked ? `Cannot delete: ${why}` : "Delete"}
                                  onClick={() => void removeItem(String(run.setuprunid), item)}>
                                  {busy === key ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Trash2 className="h-3.5 w-3.5" />}
                                </Button>
                              </>
                            )}
                          </li>
                        )
                      })}
                    </ul>
                  </div>
                )
              })}
            </div>
          </div>
        )
      })}

      {legacy.length > 0 && (() => {
        const chosen = legacy.filter((c) => ticked.has(keyOf(c)))
        const countBy = (t: FarmSetupLegacyCandidate["type"]) => chosen.filter((c) => c.type === t).length
        const chosenSummary = ([
          ["Batch", "batch", "batches"], ["House", "house/pen", "houses/pens"],
          ["Flock", "flock", "flocks"], ["Reconciliation", "batch reconciliation", "batch reconciliations"],
        ] as const)
          .map(([t, one, many]) => { const n = countBy(t); return n ? `${n} ${n === 1 ? one : many}` : "" })
          .filter(Boolean).join(", ")
        const madeBySetup = legacy.filter((c) => c.suggested && c.blockers.length === 0)
        return (
        <div className="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
          <div className="border-b border-slate-100 bg-slate-50 px-4 py-3">
            <div className="font-semibold text-slate-900">Earlier setups</div>
            <p className="mt-1 max-w-3xl text-sm text-slate-600">
              Done before the app kept a list of what each setup created. Press
              <span className="font-medium text-slate-800"> Undo this setup</span> to remove a whole setup, or tick single
              items and press <span className="font-medium text-slate-800">Remove selected</span> at the bottom.
            </p>
            <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-slate-600">
              <span className="flex items-center gap-1.5"><span className="h-2 w-2 rounded-full bg-emerald-500" /> Made by the setup</span>
              <span className="flex items-center gap-1.5"><span className="h-2 w-2 rounded-full bg-amber-500" /> May have existed before the setup — tick only if the setup made it</span>
              <span className="flex items-center gap-1.5"><span className="h-2 w-2 rounded-full bg-slate-400" /> Has records against it — can&apos;t be removed</span>
            </div>
          </div>

          {legacyGroups.map((g) => (
          <div key={g.date} className="border-b border-slate-100 last:border-b-0">
          <div className="flex flex-wrap items-center gap-3 px-4 pt-4">
            <div className="min-w-0 flex-1">
              <div className="font-semibold text-slate-900">
                Setup {g.date === "unknown" ? "(date not recorded)" : `of ${g.date}`}
              </div>
              <div className="text-xs text-slate-500">
                {g.certain.filter((c) => c.type === "Flock").length} flock(s) · {g.certain.filter((c) => c.type === "Reconciliation").length} reconciliation(s)
                {g.maybe.length > 0 && ` · ${g.maybe.length} batch(es)/pen(s) it may have created`}
              </div>
            </div>
            <Button size="sm" variant="outline" className="gap-1.5 border-rose-200 text-rose-700 hover:bg-rose-50"
              disabled={busy !== null || g.blocked.length > 0}
              title={g.blocked.length > 0 ? "Cannot undo: " + g.blocked.map((c) => `${c.name}: ${c.blockers.join("; ")}`).join(" · ") : "Remove everything this setup created"}
              onClick={() => { setUndoGroup({ date: g.date, extra: new Set() }); setReason("") }}>
              <Undo2 className="h-4 w-4" /> Undo this setup
            </Button>
          </div>
          {g.blocked.length > 0 && (
            <div className="mx-4 mt-2 rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-900">
              This setup can&apos;t be undone as a whole while {g.blocked.length === 1 ? "this flock has" : "these flocks have"} records:{" "}
              {g.blocked.map((c) => c.name ?? `#${c.id}`).join(", ")}. You can still remove the other items one by one below.
            </div>
          )}
          <div className="grid grid-cols-1 gap-4 p-4 lg:grid-cols-2">
            {(["Batch", "Reconciliation", "House", "Flock"] as const).map((t) => {
              const items = g.items.filter((c) => c.type === t)
              if (items.length === 0) return null
              const Icon = KIND[t].icon
              return (
                <div key={t} className="min-w-0">
                  <div className="mb-1.5 flex items-center gap-1.5 text-sm font-semibold text-slate-700">
                    <Icon className="h-4 w-4 text-slate-500" /> {KIND[t].label} ({items.length})
                  </div>
                  <ul className="divide-y divide-slate-100 rounded-lg border border-slate-200">
                    {items.map((c) => {
                      const k = keyOf(c)
                      const blocked = c.blockers.length > 0
                      const on = ticked.has(k)
                      const href = editHref(c)
                      const editable = c.type === "Flock" || c.type === "Batch" || c.type === "House"
                      return (
                        <li key={k} className={cn("flex items-start gap-3 px-3 py-2.5", on && "bg-rose-50/60", blocked && "bg-slate-50")}>
                          <Checkbox className="mt-0.5" checked={on} disabled={blocked || busy !== null}
                            onCheckedChange={(v) => toggle(c, v === true)} aria-label={`Remove ${c.name ?? c.id}`} />
                          <div className="min-w-0 flex-1">
                            <div className={cn("break-words text-sm font-medium", blocked ? "text-slate-500" : "text-slate-900")}>
                              {c.name ?? `#${c.id}`}
                            </div>
                            {blocked ? (
                              <div className="mt-0.5 text-xs text-slate-500">
                                <span className="font-medium text-slate-600">Can&apos;t be removed:</span> {c.blockers.join("; ")}
                              </div>
                            ) : c.suggested ? (
                              <div className="mt-0.5 flex items-center gap-1.5 text-xs text-emerald-700">
                                <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" /> Made by the setup
                              </div>
                            ) : (
                              <div className="mt-0.5 flex items-center gap-1.5 text-xs text-amber-700">
                                <span className="h-1.5 w-1.5 rounded-full bg-amber-500" /> May have existed before the setup
                              </div>
                            )}
                            {on && <div className="mt-0.5 text-xs font-medium text-rose-700">Will be removed</div>}
                          </div>
                          {c.type !== "Reconciliation" && (
                            <div className="flex shrink-0 items-center gap-1">
                              {href && editable && (
                                <Button size="sm" variant="ghost" className="h-7 gap-1 px-2 text-xs text-slate-700"
                                  onClick={() => setEditItem({ type: c.type, id: c.id, name: c.name })}>
                                  <Pencil className="h-3.5 w-3.5" /> Edit
                                </Button>
                              )}
                              {!(c.type !== "Flock" && blocked) && (
                                <Button size="sm" variant="ghost" className="h-7 gap-1 px-2 text-xs text-rose-600 hover:bg-rose-50"
                                  disabled={busy !== null} onClick={() => void removeItem("legacy", c)}>
                                  {busy === `legacy:${k}` ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Trash2 className="h-3.5 w-3.5" />} Delete
                                </Button>
                              )}
                            </div>
                          )}
                        </li>
                      )
                    })}
                  </ul>
                </div>
              )
            })}
          </div>
          </div>
          ))}

          <div className="flex flex-col gap-3 border-t border-slate-100 bg-slate-50 px-4 py-3 sm:flex-row sm:items-center">
            <div className="min-w-0 flex-1 text-sm">
              {chosen.length === 0
                ? <span className="text-slate-600">Nothing selected. Tick the items you want to remove.</span>
                : <span className="text-slate-800"><span className="font-semibold">Selected to remove:</span> {chosenSummary}.</span>}
            </div>
            <div className="flex flex-wrap items-center gap-2">
              <Button size="sm" variant="ghost" disabled={busy !== null}
                onClick={() => setTicked(new Set(madeBySetup.map(keyOf)))}>Select what the setup made</Button>
              <Button size="sm" variant="ghost" disabled={busy !== null || chosen.length === 0}
                onClick={() => setTicked(new Set())}>Clear</Button>
              <Button size="sm" className="gap-1.5 bg-rose-600 hover:bg-rose-700"
                disabled={chosen.length === 0 || busy !== null} onClick={() => { setUndoingLegacy(true); setReason("") }}>
                <Undo2 className="h-4 w-4" /> Remove selected ({chosen.length})
              </Button>
            </div>
          </div>
        </div>
        )
      })()}

      {(() => {
        const g = undoGroup ? legacyGroups.find((x) => x.date === undoGroup.date) : undefined
        const flocks = g?.certain.filter((c) => c.type === "Flock") ?? []
        const recs = g?.certain.filter((c) => c.type === "Reconciliation") ?? []
        return (
      <Dialog open={!!undoGroup} onOpenChange={(o) => { if (!o) setUndoGroup(null) }}>
        <DialogContent className="sm:max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2"><RotateCcw className="h-5 w-5 text-rose-600" />
              Undo the setup {undoGroup?.date === "unknown" ? "" : `of ${undoGroup?.date}`}?</DialogTitle>
            <DialogDescription>Everything this setup created is removed. It cannot be redone; you would run the setup again.</DialogDescription>
          </DialogHeader>
          {g && (
            <div className="space-y-3 text-sm">
              <div>
                <div className="font-medium text-slate-800">Will be removed</div>
                <ul className="mt-1 list-disc pl-5 text-slate-700">
                  {flocks.length > 0 && <li>{flocks.length} flock(s): {flocks.map((c) => c.name ?? `#${c.id}`).join(", ")}</li>}
                  {recs.length > 0 && <li>{recs.length} batch reconciliation(s): {recs.map((c) => c.name ?? `#${c.id}`).join(", ")}</li>}
                </ul>
              </div>
              {g.maybe.length > 0 && (
                <div>
                  <div className="font-medium text-slate-800">Did this setup also create these?</div>
                  <p className="text-xs text-slate-500">Tick only the ones the setup made. Ones you already had before the setup stay.</p>
                  <ul className="mt-1.5 divide-y divide-slate-100 rounded-md border border-slate-200">
                    {g.maybe.map((c) => {
                      const k = keyOf(c)
                      const blocked = c.blockers.length > 0
                      return (
                        <li key={k} className="flex items-start gap-2.5 px-3 py-2">
                          <Checkbox className="mt-0.5" disabled={blocked || busy !== null} checked={undoGroup?.extra.has(k) ?? false}
                            onCheckedChange={(v) => setUndoGroup((u) => {
                              if (!u) return u
                              const extra = new Set(u.extra)
                              if (v === true) extra.add(k); else extra.delete(k)
                              return { ...u, extra }
                            })} />
                          <div className="min-w-0">
                            <div className={cn("break-words", blocked ? "text-slate-500" : "text-slate-800")}>
                              {c.type === "Batch" ? "Batch" : "House/pen"}: {c.name ?? `#${c.id}`}
                            </div>
                            {blocked && <div className="text-xs text-slate-500">Stays — {c.blockers.join("; ")}</div>}
                          </div>
                        </li>
                      )
                    })}
                  </ul>
                </div>
              )}
              <div className="space-y-1.5">
                <label htmlFor="undo-group-reason" className="text-sm font-medium text-slate-700">Why is it being undone? *</label>
                <Textarea id="undo-group-reason" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. Entered the wrong numbers, starting again" />
              </div>
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => setUndoGroup(null)} disabled={busy !== null}>Cancel</Button>
            <Button className="bg-rose-600 hover:bg-rose-700" disabled={!reason.trim() || busy !== null} onClick={() => void undoLegacyGroup()}>
              {busy === "undo:legacygroup" ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin" /> : <Undo2 className="mr-1.5 h-4 w-4" />} Undo setup
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
        )
      })()}

      <Dialog open={undoingLegacy} onOpenChange={(o) => { if (!o) setUndoingLegacy(false) }}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2"><RotateCcw className="h-5 w-5 text-rose-600" /> Remove {ticked.size} selected item(s)?</DialogTitle>
            <DialogDescription>
              These will be removed:{" "}
              {legacy.filter((c) => ticked.has(keyOf(c))).map((c) => c.name ?? `#${c.id}`).join(", ")}.
              If a selected batch or house/pen still has a flock you did not select, nothing is removed and you are told why.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-1.5">
            <label htmlFor="undo-legacy-reason" className="text-sm font-medium text-slate-700">Why is it being undone? *</label>
            <Textarea id="undo-legacy-reason" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. Test data from the first setup" />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setUndoingLegacy(false)} disabled={busy !== null}>Cancel</Button>
            <Button className="bg-rose-600 hover:bg-rose-700" disabled={!reason.trim() || busy !== null} onClick={() => void undoLegacy()}>
              {busy === "undo:legacy" ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin" /> : <Undo2 className="mr-1.5 h-4 w-4" />} Remove
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={!!undoing} onOpenChange={(o) => { if (!o) setUndoing(null) }}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2"><RotateCcw className="h-5 w-5 text-rose-600" /> Undo setup #{undoing?.setuprunid}?</DialogTitle>
            <DialogDescription>
              This removes everything this setup created: {undoing?.items.filter((i) => !i.gone).length ?? 0} item(s) — its flocks,
              batches, houses and batch reconciliations. It cannot be redone; you would run the setup again.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-1.5">
            <label htmlFor="undo-reason" className="text-sm font-medium text-slate-700">Why is it being undone? *</label>
            <Textarea id="undo-reason" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. Entered the wrong batch sizes" />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setUndoing(null)} disabled={busy !== null}>Cancel</Button>
            <Button className="bg-rose-600 hover:bg-rose-700" disabled={!reason.trim() || busy !== null} onClick={() => void undo()}>
              {busy?.startsWith("undo:") ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin" /> : <Undo2 className="mr-1.5 h-4 w-4" />} Undo setup
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={!!editItem} onOpenChange={(o) => { if (!o) setEditItem(null) }}>
        <DialogContent className="w-[95vw] sm:max-w-3xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              {editItem?.type === "Batch" ? <Boxes className="h-5 w-5 text-indigo-600" />
                : editItem?.type === "House" ? <Home className="h-5 w-5 text-blue-600" />
                : <Bird className="h-5 w-5 text-green-600" />}
              Edit {editItem?.type === "Batch" ? "batch" : editItem?.type === "House" ? "house / pen" : "flock"}
              {editItem?.name ? ` — ${editItem.name}` : ""}
            </DialogTitle>
            <DialogDescription>Update the information below.</DialogDescription>
          </DialogHeader>
          {editItem?.type === "Flock" && (
            <FlockEditForm flockId={String(editItem.id)} showTreatments={false}
              onCancel={() => setEditItem(null)} onSaved={afterEdit} />
          )}
          {editItem?.type === "Batch" && (
            <FlockBatchEditForm batchId={String(editItem.id)}
              onCancel={() => setEditItem(null)}
              onSaved={afterEdit} />
          )}
          {editItem?.type === "House" && (
            <HouseEditForm houseId={editItem.id} onCancel={() => setEditItem(null)} onSaved={afterEdit} />
          )}
        </DialogContent>
      </Dialog>
    </section>
  )
}
