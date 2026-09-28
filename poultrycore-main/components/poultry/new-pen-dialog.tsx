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

import { useEffect, useMemo, useState } from "react"
import { Button } from "@/components/ui/button"
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { NumberInput } from "@/components/ui/number-input"
import { MAX_ROWS, generateRows, nextStartNumber } from "@/lib/houses/bulk"

export interface NewPen { name: string; capacity: string; location: string }

export interface NewPenDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  /** Suggested name, e.g. the next number in the farm's run of pens. */
  suggestedName?: string
  /** Names already taken, compared loosely — "pen 1" and "Pen  1" are one name. */
  takenNames: readonly string[]
  /** One pen in Single mode, the whole run in Multiple mode. */
  onCreate: (pens: NewPen[]) => void
}

const key = (raw: string) => raw.trim().replace(/\s+/g, " ").toLowerCase()

export function NewPenDialog({
  open, onOpenChange, suggestedName = "", takenNames, onCreate,
}: NewPenDialogProps) {
  const [name, setName] = useState("")
  const [capacity, setCapacity] = useState("")
  const [location, setLocation] = useState("")
  const [error, setError] = useState("")
  const [mode, setMode] = useState<"single" | "multiple">("single")
  const [count, setCount] = useState("4")
  const [prefix, setPrefix] = useState("Pen")
  // null = continue the farm's series for this prefix; typing takes over.
  const [startOverride, setStartOverride] = useState<string | null>(null)

  useEffect(() => {
    if (!open) return
    setName(suggestedName)
    setCapacity("")
    setLocation("")
    setError("")
    setMode("single")
    setCount("4")
    setPrefix("Pen")
    setStartOverride(null)
  }, [open, suggestedName])

  const suggestedStart = useMemo(() => nextStartNumber(prefix, [...takenNames]), [prefix, takenNames])
  const start = startOverride ?? String(suggestedStart)
  // The same generator as the Houses step, so the names come out identically.
  const preview = useMemo(() => mode === "multiple"
    ? generateRows({
        count: parseInt(count, 10) || 0, prefix,
        startNumber: parseInt(start, 10) || 1, capacity, location,
      })
    : [], [mode, count, prefix, start, capacity, location])

  const submitMultiple = () => {
    const n = parseInt(count, 10)
    if (!Number.isFinite(n) || n < 1) {
      setError("Enter how many pens to add.")
      return
    }
    if (n > MAX_ROWS) {
      setError(`Add at most ${MAX_ROWS} pens at a time.`)
      return
    }
    const clash = preview.find((r) => takenNames.some((t) => key(t) === key(r.name)))
    if (clash) {
      setError(`You already have a pen called "${clash.name}". Change the starting number or prefix.`)
      return
    }
    onCreate(preview.map((r) => ({ name: r.name, capacity: r.capacity, location: r.location })))
    onOpenChange(false)
  }

  const submit = () => {
    if (mode === "multiple") return submitMultiple()
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
    onCreate([{ name: trimmed, capacity: capacity.trim(), location: location.trim() }])
    onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>New house/pen</DialogTitle>
          <DialogDescription>
            Added to this setup and selected for this batch. Created along with everything else when you finish.
          </DialogDescription>
        </DialogHeader>

        <div role="group" aria-label="How many pens" className="inline-flex w-fit justify-self-start rounded-md border border-slate-300 bg-white p-0.5">
          {([["single", "Add single pen"], ["multiple", "Add multiple pens"]] as const).map(([value, label]) => (
            <button key={value} type="button" aria-pressed={mode === value}
              onClick={() => { setMode(value); setError("") }}
              className={`rounded px-3 py-1 text-xs font-medium transition-colors ${mode === value ? "bg-indigo-600 text-white" : "text-slate-700 hover:bg-slate-100"}`}>
              {label}
            </button>
          ))}
        </div>

        <div className="space-y-3">
          {mode === "multiple" ? (
            <div className="grid grid-cols-3 gap-3">
              <div className="space-y-2">
                <Label className="text-sm font-medium text-slate-700">Number of pens *</Label>
                <NumberInput autoFocus min="1" value={count}
                  onChange={(e) => { setCount(e.target.value); setError("") }} />
              </div>
              <div className="space-y-2">
                <Label className="text-sm font-medium text-slate-700">Prefix</Label>
                <Input value={prefix} placeholder="Pen"
                  onChange={(e) => { setPrefix(e.target.value); setError("") }} />
              </div>
              <div className="space-y-2">
                <Label className="text-sm font-medium text-slate-700">Starting number</Label>
                <NumberInput value={start} placeholder={String(suggestedStart)}
                  onChange={(e) => { setStartOverride(e.target.value.trim() === "" ? null : e.target.value); setError("") }} />
              </div>
            </div>
          ) : (
          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">House/Pen name *</Label>
            <Input autoFocus value={name} placeholder="Pen 5"
              onChange={(e) => { setName(e.target.value); setError("") }}
              onKeyDown={(e) => { if (e.key === "Enter") submit() }} />
          </div>
          )}
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
            {mode === "multiple" && " Capacity and location apply to every pen."}
          </p>
          {mode === "multiple" && preview.length > 0 && (
            <p className="text-xs text-slate-600">
              Will add:{" "}
              <span className="font-medium text-slate-800">
                {preview.length <= 4
                  ? preview.map((r) => r.name).join(", ")
                  : `${preview[0].name}, ${preview[1].name} … ${preview[preview.length - 1].name}`}
              </span>{" "}
              ({preview.length} pen{preview.length === 1 ? "" : "s"})
            </p>
          )}
          {error && <p className="text-xs text-red-600">{error}</p>}
        </div>

        <DialogFooter>
          <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button type="button" onClick={submit}>
            {mode === "multiple" && preview.length > 1 ? `Add ${preview.length} pens` : "Add pen"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
