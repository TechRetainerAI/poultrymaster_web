"use client"

// Fix a pen's capacity without leaving the row that revealed it was wrong.
//
// Capacity is a forward-planning figure — it decides where the NEXT batch can
// go — so a stale one costs nothing today and everything later. The allocation
// step is the moment a farm discovers it is stale, and sending them off to the
// Houses page to fix it is how it stays stale.
//
// The dialog collects a number and hands it back. WHERE it goes is the caller's
// business, and the two cases genuinely differ: a pen that already exists is
// saved to the server straight away, because its capacity belongs to the pen and
// not to this draft; a pen being created in this setup is only edited in the
// draft, because there is nothing to save to yet. `savesImmediately` is how the
// dialog says which is happening, so nobody is surprised.

import { useEffect, useState } from "react"
import { Button } from "@/components/ui/button"
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import { Label } from "@/components/ui/label"
import { NumberInput } from "@/components/ui/number-input"
import { Loader2, TriangleAlert } from "lucide-react"

export interface PenCapacityDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  penName: string
  /** What the pen is recorded as taking. Null when nothing is recorded. */
  capacity: number | null
  /** Birds held by flocks outside this setup. */
  occupied: number
  /** Birds this setup is putting in it. */
  standing: number
  /** True for a pen that already exists, and will therefore be saved now. */
  savesImmediately: boolean
  onSave: (capacity: number) => Promise<void> | void
}

export function PenCapacityDialog({
  open, onOpenChange, penName, capacity, occupied, standing, savesImmediately, onSave,
}: PenCapacityDialogProps) {
  const total = occupied + standing
  const [value, setValue] = useState("")
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState("")

  // Opens showing what is ACTUALLY in the pen, because that is the number the
  // farm just told us and almost certainly the one they mean.
  useEffect(() => {
    if (!open) return
    setValue(String(total))
    setError("")
  }, [open, total])

  const entered = Number(value)
  const tooSmall = Number.isFinite(entered) && entered > 0 && entered < total

  const submit = async () => {
    if (!Number.isFinite(entered) || entered < 0) {
      setError("Enter how many birds this pen can hold.")
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
          <DialogTitle>Update {penName || "pen"} capacity</DialogTitle>
          <DialogDescription>
            {savesImmediately
              ? "This saves to the pen straight away — it is not part of the setup you are filling in."
              : "This pen is being created by this setup, so the change is saved with the rest of it."}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3">
          <div className="grid grid-cols-3 gap-2 text-sm">
            <div className="rounded-lg border border-slate-200 bg-slate-50 px-3 py-2">
              <p className="text-xs text-slate-500">Recorded</p>
              <p className="font-semibold tabular-nums text-slate-900">
                {capacity == null ? "—" : capacity.toLocaleString()}
              </p>
            </div>
            <div className="rounded-lg border border-slate-200 bg-slate-50 px-3 py-2">
              <p className="text-xs text-slate-500">Already in it</p>
              <p className="font-semibold tabular-nums text-slate-900">{occupied.toLocaleString()}</p>
            </div>
            <div className="rounded-lg border border-slate-200 bg-slate-50 px-3 py-2">
              <p className="text-xs text-slate-500">This setup adds</p>
              <p className="font-semibold tabular-nums text-blue-700">{standing.toLocaleString()}</p>
            </div>
          </div>

          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">Capacity (birds)</Label>
            <NumberInput min="0" value={value} onChange={(e) => setValue(e.target.value)} disabled={saving} />
            <p className="text-xs text-slate-500">
              {total.toLocaleString()} birds are in this pen. Leave it at 0 if the pen has no limit.
            </p>
          </div>

          {/* Allowed, not blocked: a farm may be telling us the pen is genuinely
              over its rating, which is a fact about today, not a typo. */}
          {tooSmall && (
            <p className="flex items-start gap-2 text-xs text-amber-700">
              <TriangleAlert className="mt-0.5 h-3.5 w-3.5 shrink-0" />
              That is less than the {total.toLocaleString()} birds already in the pen. You can still save it.
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
            Save capacity
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
