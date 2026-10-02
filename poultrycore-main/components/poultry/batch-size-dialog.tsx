"use client"

// Correct a batch's bird count without leaving the allocation that revealed it.
//
// The sibling of pen-capacity-dialog: the allocation step's own message already
// says "lower a pen, or raise the batch", and sending someone to Flock Purchases
// to do the second half is how a wrong number survives.
//
// ONE IMPORTANT DIFFERENCE FROM PEN CAPACITY. A pen's capacity is reference data
// — changing it posts nothing. A batch's bird count is not: for a batch that
// already exists, spmainflockbatch_update re-syncs the bird stock ledger to the
// new figure, so raising 5,000 to 6,000 posts 1,000 birds into stock. That is
// correct when the farm really did buy more than was recorded, and wrong as a
// way to silence a warning, so the dialog says it plainly rather than letting it
// happen quietly.

import { useEffect, useState } from "react"
import { Button } from "@/components/ui/button"
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import { Label } from "@/components/ui/label"
import { NumberInput } from "@/components/ui/number-input"
import { Loader2, TriangleAlert } from "lucide-react"

export interface BatchSizeDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  batchLabel: string
  /** What the batch is recorded as having been bought with. */
  batchBirds: number
  /** Birds earlier sessions already placed out of it. */
  previouslyAllocated: number
  /** Birds this setup is placing. */
  thisAllocation: number
  /** True for a batch that already exists, and will therefore be saved now. */
  savesImmediately: boolean
  onSave: (numberOfBirds: number) => Promise<void> | void
}

export function BatchSizeDialog({
  open, onOpenChange, batchLabel, batchBirds, previouslyAllocated, thisAllocation,
  savesImmediately, onSave,
}: BatchSizeDialogProps) {
  const accountedFor = previouslyAllocated + thisAllocation
  const [value, setValue] = useState("")
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState("")

  // Opens at what the flocks actually account for — the figure that makes the
  // warning go away honestly, and almost always the one that is true.
  useEffect(() => {
    if (!open) return
    setValue(String(accountedFor))
    setError("")
  }, [open, accountedFor])

  const entered = Number(value)
  const valid = Number.isFinite(entered) && entered > 0
  const tooSmall = valid && entered < accountedFor
  const changesStock = savesImmediately && valid && entered !== batchBirds
  const delta = entered - batchBirds

  const submit = async () => {
    if (!valid) {
      setError("Enter how many birds this batch was bought with.")
      return
    }
    if (tooSmall) {
      // Unlike a pen, this one cannot be waved through: flocks holding more
      // birds than their batch ever had is not a thing that can be true, and the
      // validator would refuse the setup anyway.
      setError(`${accountedFor.toLocaleString()} birds are already placed from this batch. It cannot be smaller than that.`)
      return
    }
    setSaving(true)
    setError("")
    try {
      await onSave(Math.floor(entered))
      onOpenChange(false)
    } catch (e) {
      setError(e instanceof Error ? e.message : "That could not be saved. Try again.")
    } finally {
      setSaving(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={(next) => { if (!saving) onOpenChange(next) }}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Update {batchLabel || "batch"} bird count</DialogTitle>
          <DialogDescription>
            {savesImmediately
              ? "This saves to the batch straight away — it is not part of the setup you are filling in."
              : "This batch is being created by this setup, so the change is saved with the rest of it."}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3">
          <div className="grid grid-cols-3 gap-2 text-sm">
            <div className="rounded-lg border border-slate-200 bg-slate-50 px-3 py-2">
              <p className="text-xs text-slate-500">Recorded</p>
              <p className="font-semibold tabular-nums text-slate-900">{batchBirds.toLocaleString()}</p>
            </div>
            <div className="rounded-lg border border-slate-200 bg-slate-50 px-3 py-2">
              <p className="text-xs text-slate-500">Already placed</p>
              <p className="font-semibold tabular-nums text-slate-900">{previouslyAllocated.toLocaleString()}</p>
            </div>
            <div className="rounded-lg border border-slate-200 bg-slate-50 px-3 py-2">
              <p className="text-xs text-slate-500">This setup places</p>
              <p className="font-semibold tabular-nums text-blue-700">{thisAllocation.toLocaleString()}</p>
            </div>
          </div>

          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">Birds bought (original)</Label>
            <NumberInput min="1" value={value} onChange={(e) => setValue(e.target.value)} disabled={saving} />
            <p className="text-xs text-slate-500">
              Your flocks account for {accountedFor.toLocaleString()} birds from this batch.
            </p>
          </div>

          {/* The consequence, before it happens rather than after. */}
          {changesStock && (
            <p className="flex items-start gap-2 text-xs text-amber-700">
              <TriangleAlert className="mt-0.5 h-3.5 w-3.5 shrink-0" />
              This also {delta > 0 ? "adds" : "removes"} {Math.abs(delta).toLocaleString()} bird
              {Math.abs(delta) === 1 ? "" : "s"} {delta > 0 ? "to" : "from"} your bird stock, because the
              batch record is what stock is counted from. Only do this if the batch really was that size.
            </p>
          )}
          {error && <p className="text-xs text-red-600">{error}</p>}
        </div>

        <DialogFooter>
          <Button type="button" variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>
            Cancel
          </Button>
          <Button type="button" onClick={submit} disabled={saving}>
            {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            Save bird count
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
