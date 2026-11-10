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

  const load = useCallback(async () => {
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) return
    const [res, leg] = await Promise.all([getFarmSetupRuns(userId, farmId), getFarmSetupLegacyCandidates(userId, farmId)])
    if (res.success) { setRuns(res.data ?? []); setError("") }
    else setError(res.message || "Could not load your completed setups.")
    if (leg.success) {
      const rows = leg.data ?? []
      setLegacy(rows)
      // Suggested (flocks, reconciliations) start ticked unless something blocks them.
      setTicked(new Set(rows.filter((r) => r.suggested && r.blockers.length === 0).map(keyOf)))
    }
  }, [])
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

  const undoLegacy = async () => {
    if (!reason.trim() || ticked.size === 0) return
    const { userId, farmId } = getUserContext()
    setBusy("undo:legacy")
    const items = legacy.filter((c) => ticked.has(keyOf(c))).map((c) => ({ type: c.type, id: c.id }))
    const res = await reverseFarmSetupLegacy(items, userId, farmId, reason.trim())
    setBusy(null)
    if (res.success) {
      toast({ title: "Undone", description: `${items.length} item(s) from the earlier setup were removed.` })
      setUndoingLegacy(false); setReason("")
      await load(); onChanged?.()
    } else {
      toast({ title: "Not undone", description: res.message, variant: "destructive" })
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
        const groups = (["Batch", "House", "Flock", "Reconciliation"] as const)
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
                            <span className={cn("min-w-0 flex-1 truncate", item.gone ? "text-slate-400 line-through" : "text-slate-800")} title={item.name ?? ""}>
                              {item.name ?? `#${item.id}`}
                            </span>
                            {item.gone ? (
                              <span className="text-[11px] text-slate-400">{item.type === "Reconciliation" ? "Reversed" : "Deleted"}</span>
                            ) : !reversed && item.type !== "Reconciliation" && (
                              <>
                                {href && (
                                  <Button asChild size="icon" variant="ghost" className="h-7 w-7" title="Edit">
                                    <Link href={href}><Pencil className="h-3.5 w-3.5" /></Link>
                                  </Button>
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

      {legacy.length > 0 && (
        <div className="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
          <div className="flex flex-wrap items-center gap-3 border-b border-slate-100 bg-slate-50 px-4 py-3">
            <div className="min-w-0 flex-1">
              <div className="font-semibold text-slate-900">Earlier setups</div>
              <div className="text-xs text-slate-500">
                Completed before setups recorded what they created. Flocks and reconciliations below came from a setup.
                Batches and houses are where those flocks are and may be older — tick them only if the setup created them.
              </div>
            </div>
            <Button size="sm" variant="outline" className="gap-1.5 border-rose-200 text-rose-700 hover:bg-rose-50"
              disabled={ticked.size === 0 || busy !== null} onClick={() => { setUndoingLegacy(true); setReason("") }}>
              <Undo2 className="h-4 w-4" /> Undo ticked ({ticked.size})
            </Button>
          </div>
          <div className="grid grid-cols-1 gap-4 p-4 md:grid-cols-2 xl:grid-cols-4">
            {(["Batch", "House", "Flock", "Reconciliation"] as const).map((t) => {
              const items = legacy.filter((c) => c.type === t)
              if (items.length === 0) return null
              const Icon = KIND[t].icon
              return (
                <div key={t} className="min-w-0">
                  <div className="mb-1.5 flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide text-slate-500">
                    <Icon className="h-3.5 w-3.5" /> {KIND[t].label} ({items.length})
                  </div>
                  <ul className="divide-y divide-slate-100 rounded-lg border border-slate-100">
                    {items.map((c) => {
                      const k = keyOf(c)
                      const blocked = c.blockers.length > 0
                      const href = editHref(c)
                      return (
                        <li key={k} className="flex items-center gap-2 px-2.5 py-1.5 text-sm" title={blocked ? "Cannot be undone: " + c.blockers.join("; ") : undefined}>
                          <Checkbox checked={ticked.has(k)} disabled={blocked || busy !== null}
                            onCheckedChange={(v) => toggle(c, v === true)} aria-label={`Undo ${c.name ?? c.id}`} />
                          <span className={cn("min-w-0 flex-1 truncate", blocked ? "text-slate-400" : "text-slate-800")}>
                            {c.name ?? `#${c.id}`}
                            {!c.suggested && <span className="ml-1 text-[10px] uppercase text-amber-600">maybe older</span>}
                          </span>
                          {c.type !== "Reconciliation" && (
                            <>
                              {href && (
                                <Button asChild size="icon" variant="ghost" className="h-7 w-7" title="Edit">
                                  <Link href={href}><Pencil className="h-3.5 w-3.5" /></Link>
                                </Button>
                              )}
                              <Button size="icon" variant="ghost" className="h-7 w-7 text-rose-600 disabled:text-slate-300"
                                disabled={busy !== null || (c.type !== "Flock" && blocked)}
                                title={c.type !== "Flock" && blocked ? `Cannot delete: ${c.blockers.join("; ")}` : "Delete"}
                                onClick={() => void removeItem("legacy", c)}>
                                {busy === `legacy:${k}` ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Trash2 className="h-3.5 w-3.5" />}
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
          {legacy.some((c) => c.blockers.length > 0) && (
            <div className="border-t border-amber-100 bg-amber-50 px-4 py-2 text-xs text-amber-900">
              Greyed-out items have records against them (hover for the reasons) and cannot be undone.
            </div>
          )}
        </div>
      )}

      <Dialog open={undoingLegacy} onOpenChange={(o) => { if (!o) setUndoingLegacy(false) }}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2"><RotateCcw className="h-5 w-5 text-rose-600" /> Undo {ticked.size} ticked item(s)?</DialogTitle>
            <DialogDescription>
              Removes exactly what you ticked from the earlier setup:{" "}
              {legacy.filter((c) => ticked.has(keyOf(c))).map((c) => c.name ?? `#${c.id}`).join(", ")}.
              It is refused, and nothing changes, if a ticked batch or house still holds a flock you did not tick.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-1.5">
            <label htmlFor="undo-legacy-reason" className="text-sm font-medium text-slate-700">Why is it being undone? *</label>
            <Textarea id="undo-legacy-reason" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. Test data from the first setup" />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setUndoingLegacy(false)} disabled={busy !== null}>Cancel</Button>
            <Button className="bg-rose-600 hover:bg-rose-700" disabled={!reason.trim() || busy !== null} onClick={() => void undoLegacy()}>
              {busy === "undo:legacy" ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin" /> : <Undo2 className="mr-1.5 h-4 w-4" />} Undo
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
    </section>
  )
}
