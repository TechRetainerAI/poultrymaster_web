"use client"

// Add a pen without leaving the allocation.
//
// Running out of somewhere to put the birds is a normal thing to discover
// halfway through placing them, and "go back to the Houses step" is a poor
// answer to it — by the time someone has walked back, added a pen and returned,
// they have lost their place.
//
// It adds the pen to the DRAFT, not to the farm. Everything else on this step
// is pending until Complete Farm Setup posts it in one transaction, and a pen
// that appeared on the server immediately would be the one thing that survived
// abandoning the wizard. Houses are created before flocks in that transaction,
// so a pen added here is a real pen by the time the flock needs it.

import { useEffect, useState } from "react"
import { Button } from "@/components/ui/button"
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { NumberInput } from "@/components/ui/number-input"

export interface NewPenDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  /** Suggested name, e.g. the next number in the farm's run of pens. */
  suggestedName?: string
  /** Names already taken, compared loosely — "pen 1" and "Pen  1" are one name. */
  takenNames: readonly string[]
  onCreate: (pen: { name: string; capacity: string; location: string }) => void
}

const key = (raw: string) => raw.trim().replace(/\s+/g, " ").toLowerCase()

export function NewPenDialog({
  open, onOpenChange, suggestedName = "", takenNames, onCreate,
}: NewPenDialogProps) {
  const [name, setName] = useState("")
  const [capacity, setCapacity] = useState("")
  const [location, setLocation] = useState("")
  const [error, setError] = useState("")

  useEffect(() => {
    if (!open) return
    setName(suggestedName)
    setCapacity("")
    setLocation("")
    setError("")
  }, [open, suggestedName])

  const submit = () => {
    const trimmed = name.trim()
    if (!trimmed) {
      setError("Give the pen a name.")
      return
    }
    // Caught here rather than three steps later: a duplicate name is refused by
    // the setup's validation, and finding that out on Review is too late.
    if (takenNames.some((t) => key(t) === key(trimmed))) {
      setError(`You already have a pen called "${trimmed}".`)
      return
    }
    onCreate({ name: trimmed, capacity: capacity.trim(), location: location.trim() })
    onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>New house/pen</DialogTitle>
          <DialogDescription>
            It is added to this setup and created along with everything else when you finish.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3">
          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">House/Pen name *</Label>
            <Input autoFocus value={name} placeholder="Pen 5"
              onChange={(e) => { setName(e.target.value); setError("") }}
              onKeyDown={(e) => { if (e.key === "Enter") submit() }} />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-2">
              <Label className="text-sm font-medium text-slate-700">Capacity</Label>
              <NumberInput min="0" value={capacity} placeholder="2000"
                onChange={(e) => setCapacity(e.target.value)} />
            </div>
            <div className="space-y-2">
              <Label className="text-sm font-medium text-slate-700">Location</Label>
              <Input value={location} placeholder="Layer House A"
                onChange={(e) => setLocation(e.target.value)} />
            </div>
          </div>
          <p className="text-xs text-slate-500">
            Leave the capacity blank if the pen has no set limit.
          </p>
          {error && <p className="text-xs text-red-600">{error}</p>}
        </div>

        <DialogFooter>
          <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button type="button" onClick={submit}>Add pen</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
