"use client"

import { useEffect, useMemo, useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import { Home, Plus, Trash2, Wand2, AlertCircle } from "lucide-react"
import { createHousesBulk, type House } from "@/lib/api/house"
import {
  MAX_ROWS,
  applyToAll, emptyRow, errorsByRow, generateRows, summarize, toPayloadItems, validateRows,
  type BulkHouseField, type BulkHouseRow,
} from "@/lib/houses/bulk"
import { getUserContext } from "@/lib/utils/user-context"
import { useToast } from "@/hooks/use-toast"

// "Add Multiple Houses/Pens" -- the bulk counterpart to the single Add House
// form, which is untouched and still the way to add one.
//
// Host-agnostic on purpose: it takes the existing names and hands back the
// created houses, so the Houses page, the Farm Setup Wizard and the
// Batch-to-Flock allocation screen can each mount it. `source` is what tells
// them apart in the audit trail. The rules live in lib/houses/bulk.ts and are
// re-run by the server, which is the one that actually decides.

interface BulkHouseDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  /** House names already on this farm, for the duplicate check. */
  existingNames: string[]
  /** Which screen is hosting this. Recorded on each created house's audit row. */
  source?: string
  /** Called after a successful batch, with the houses as the server stored them. */
  onCreated?: (houses: House[]) => void | Promise<void>
}

const DEFAULT_PREFIX = "Pen"

export function BulkHouseDialog({ open, onOpenChange, existingNames, source, onCreated }: BulkHouseDialogProps) {
  const { toast } = useToast()

  // Generator inputs. Only a convenience -- everything they produce stays
  // editable in the grid below.
  const [count, setCount] = useState("10")
  const [prefix, setPrefix] = useState(DEFAULT_PREFIX)
  const [startNumber, setStartNumber] = useState("1")
  const [defaultCapacity, setDefaultCapacity] = useState("")
  const [defaultLocation, setDefaultLocation] = useState("")

  const [rows, setRows] = useState<BulkHouseRow[]>([])
  const [submitted, setSubmitted] = useState(false)
  const [saving, setSaving] = useState(false)
  /** Row errors the SERVER rejected the batch with, keyed like the local ones. */
  const [serverErrors, setServerErrors] = useState<Record<number, Partial<Record<string, string>>>>({})

  // Start each visit clean: a half-filled grid from last time is a trap, since
  // the names it holds may since have been created.
  useEffect(() => {
    if (!open) return
    setCount("10")
    setPrefix(DEFAULT_PREFIX)
    setStartNumber("1")
    setDefaultCapacity("")
    setDefaultLocation("")
    setRows([])
    setSubmitted(false)
    setServerErrors({})
  }, [open])

  const errors = useMemo(() => validateRows(rows, existingNames), [rows, existingNames])
  const rowErrors = useMemo(() => errorsByRow(errors), [errors])
  const batchError = errors.find((e) => e.index < 0)
  const summary = useMemo(() => summarize(rows), [rows])

  // Quiet until the user has tried to submit, so a freshly generated grid isn't
  // already shouting -- except duplicates, which are the whole point of showing
  // the preview and are worth flagging the moment they appear.
  const showErrorsFor = (index: number, field: BulkHouseField) => {
    const message = rowErrors[index]?.[field]
    if (!message) return serverErrors[index]?.[field]
    if (submitted) return message
    return message.includes("already exists") || message.includes("more than once") ? message : undefined
  }

  const generate = () => {
    const n = parseInt(count, 10)
    if (!Number.isFinite(n) || n < 1) {
      toast({ title: "Nothing to generate", description: "Enter how many houses/pens you need.", variant: "warning" })
      return
    }
    if (n > MAX_ROWS) {
      toast({
        title: "Too many at once",
        description: `A single batch can create at most ${MAX_ROWS} houses/pens. Generate them in smaller batches.`,
        variant: "warning",
      })
      return
    }
    setRows(generateRows({
      count: n,
      prefix,
      startNumber: parseInt(startNumber, 10) || 1,
      capacity: defaultCapacity,
      location: defaultLocation,
    }))
    setSubmitted(false)
    setServerErrors({})
  }

  const patchRow = (index: number, patch: Partial<BulkHouseRow>) => {
    setRows((prev) => prev.map((r, i) => (i === index ? { ...r, ...patch } : r)))
    setServerErrors({})
  }

  const removeRow = (index: number) => {
    setRows((prev) => prev.filter((_, i) => i !== index))
    setServerErrors({})
  }

  const addRow = () => {
    setRows((prev) => [...prev, emptyRow(defaultCapacity, defaultLocation)])
    setServerErrors({})
  }

  const submit = async () => {
    setSubmitted(true)
    setServerErrors({})

    if (errors.length > 0) {
      toast({
        title: "Check the rows below",
        description: batchError?.message ?? `${errors.length} row${errors.length === 1 ? "" : "s"} need attention before these houses can be created.`,
        variant: "warning",
      })
      return
    }

    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      toast({
        title: "Session issue",
        description: "We could not confirm your farm or user. Please sign in again.",
        variant: "destructive",
      })
      return
    }

    setSaving(true)
    try {
      const res = await createHousesBulk({
        userId,
        farmId,
        source: source ?? "Houses page",
        houses: toPayloadItems(rows),
      })

      if (!res.success) {
        // The server re-runs every rule. When it disagrees -- usually because
        // someone else created a house with the same name in the meantime --
        // pin its messages to the same rows rather than replacing the grid.
        const fromServer: Record<number, Partial<Record<string, string>>> = {}
        for (const e of res.data?.errors ?? []) {
          if (e.index < 0) continue
          fromServer[e.index] = { ...(fromServer[e.index] ?? {}), [e.field]: e.message }
        }
        setServerErrors(fromServer)
        toast({
          title: "No houses were created",
          description: res.data?.message || res.message || "The batch was rejected. Nothing was saved.",
          variant: "destructive",
        })
        return
      }

      const created = res.data?.houses ?? []
      toast({
        title: "Houses created",
        description: res.data?.message || `${created.length} houses/pens created successfully.`,
      })
      onOpenChange(false)
      await onCreated?.(created)
    } catch (e: any) {
      toast({
        title: "No houses were created",
        description: e?.message || "Something went wrong. Nothing was saved.",
        variant: "destructive",
      })
    } finally {
      setSaving(false)
    }
  }

  const createLabel = summary.count === 1
    ? "Create 1 House/Pen"
    : `Create ${summary.count} Houses/Pens`

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="w-[95vw] max-w-[1600px] max-h-[90vh] flex flex-col">
        <DialogHeader>
          <DialogTitle>Add Multiple Houses/Pens</DialogTitle>
          <DialogDescription>
            Generate a batch, edit any row, then create them all at once. Nothing is saved until you click create — and
            if one row cannot be created, none of them are.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-5 py-4 overflow-y-auto pr-1">
          {/* ---- Generator -------------------------------------------------- */}
          <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
            <div className="bg-blue-600 px-4 py-2 text-sm font-semibold text-white">Generate Houses/Pens</div>
            <div className="grid grid-cols-1 md:grid-cols-5 gap-4 p-4">
              <div className="space-y-2">
                <Label htmlFor="bulk-count">Number of Houses/Pens *</Label>
                <NumberInput id="bulk-count" min="1" max={String(MAX_ROWS)} value={count} onChange={(e) => setCount(e.target.value)} placeholder="10" />
              </div>
              <div className="space-y-2">
                <Label htmlFor="bulk-prefix">Naming Prefix</Label>
                <Input id="bulk-prefix" value={prefix} onChange={(e) => setPrefix(e.target.value)} placeholder="Pen" />
              </div>
              <div className="space-y-2">
                <Label htmlFor="bulk-start">Starting Number</Label>
                <NumberInput id="bulk-start" value={startNumber} onChange={(e) => setStartNumber(e.target.value)} placeholder="1" />
              </div>
              <div className="space-y-2">
                <Label htmlFor="bulk-capacity">Default Capacity (birds)</Label>
                <NumberInput id="bulk-capacity" min="0" value={defaultCapacity} onChange={(e) => setDefaultCapacity(e.target.value)} placeholder="2000" />
              </div>
              <div className="space-y-2">
                <Label htmlFor="bulk-location">Default Location</Label>
                <Input id="bulk-location" value={defaultLocation} onChange={(e) => setDefaultLocation(e.target.value)} placeholder="Layer House A" />
              </div>
            </div>
            <div className="flex flex-wrap items-center gap-2 px-4 pb-4">
              <Button type="button" onClick={generate} className="bg-blue-600 hover:bg-blue-700 flex items-center gap-2">
                <Wand2 className="w-4 h-4" />
                Generate
              </Button>
              {rows.length > 0 && (
                <>
                  <Button type="button" variant="outline" size="sm" onClick={() => setRows(applyToAll(rows, { capacity: defaultCapacity }))}>
                    Apply Capacity to All
                  </Button>
                  <Button type="button" variant="outline" size="sm" onClick={() => setRows(applyToAll(rows, { location: defaultLocation }))}>
                    Apply Location to All
                  </Button>
                </>
              )}
              <span className="text-xs text-slate-500">
                Generating replaces the rows below. Everything stays editable.
              </span>
            </div>
          </div>

          {/* ---- Editable preview ------------------------------------------- */}
          <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
            <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Preview &amp; Edit</div>

            {rows.length === 0 ? (
              <div className="text-center py-10 px-4">
                <Home className="h-10 w-10 text-slate-400 mx-auto mb-3" />
                <p className="text-slate-600">No rows yet. Generate a batch above, or add a single row.</p>
                <Button type="button" variant="outline" size="sm" onClick={addRow} className="mt-3">
                  <Plus className="w-4 h-4 mr-1" />
                  Add Another Row
                </Button>
              </div>
            ) : (
              <div className="p-4 space-y-3">
                <div className="hidden md:grid grid-cols-12 gap-3 px-3 text-xs font-medium text-slate-500">
                  <div className="col-span-5">House/Pen Name *</div>
                  <div className="col-span-2">Capacity</div>
                  <div className="col-span-4">Location</div>
                  <div className="col-span-1 text-right">Action</div>
                </div>

                {rows.map((row, index) => {
                  const nameError = showErrorsFor(index, "houseName")
                  const capacityError = showErrorsFor(index, "capacity")
                  const locationError = showErrorsFor(index, "location")
                  return (
                    <div
                      key={row.id}
                      className={`grid grid-cols-12 gap-3 items-start rounded-lg border px-3 py-3 bg-white ${
                        nameError || capacityError || locationError ? "border-red-300" : "border-slate-200"
                      }`}
                    >
                      <div className="col-span-12 md:col-span-5 space-y-1">
                        <Input
                          aria-label={`House name, row ${index + 1}`}
                          value={row.name}
                          onChange={(e) => patchRow(index, { name: e.target.value })}
                          placeholder="Pen 1"
                        />
                        {nameError && (
                          <p className="text-xs text-red-600 flex items-center gap-1">
                            <AlertCircle className="w-3 h-3 shrink-0" />
                            {nameError}
                          </p>
                        )}
                      </div>
                      <div className="col-span-6 md:col-span-2 space-y-1">
                        <NumberInput
                          aria-label={`Capacity, row ${index + 1}`}
                          min="0"
                          value={row.capacity}
                          onChange={(e) => patchRow(index, { capacity: e.target.value })}
                          placeholder="2000"
                        />
                        {capacityError && <p className="text-xs text-red-600">{capacityError}</p>}
                      </div>
                      <div className="col-span-12 md:col-span-4 space-y-1">
                        <Input
                          aria-label={`Location, row ${index + 1}`}
                          value={row.location}
                          onChange={(e) => patchRow(index, { location: e.target.value })}
                          placeholder="Layer House A"
                        />
                        {locationError && <p className="text-xs text-red-600">{locationError}</p>}
                      </div>
                      <div className="col-span-6 md:col-span-1 flex md:justify-end">
                        <Button
                          type="button"
                          variant="ghost"
                          size="sm"
                          onClick={() => removeRow(index)}
                          className="text-red-600 hover:text-red-700 hover:bg-red-50"
                        >
                          <Trash2 className="h-4 w-4 md:mr-0 mr-1" />
                          <span className="md:hidden">Remove</span>
                        </Button>
                      </div>
                    </div>
                  )
                })}

                <Button type="button" variant="outline" size="sm" onClick={addRow}>
                  <Plus className="w-4 h-4 mr-1" />
                  Add Another Row
                </Button>
              </div>
            )}
          </div>

          {/* ---- Review ------------------------------------------------------ */}
          {rows.length > 0 && (
            <div className="rounded-xl border border-slate-200 bg-white px-4 py-3">
              <p className="font-medium text-slate-900">
                {summary.count === 1 ? "1 house/pen will be created." : `${summary.count} houses/pens will be created.`}
              </p>
              <p className="text-sm text-slate-600">
                Total capacity: {summary.totalCapacity.toLocaleString()} birds
                {summary.withoutCapacity > 0 && (
                  <span className="text-slate-500">
                    {" "}
                    ({summary.withoutCapacity} {summary.withoutCapacity === 1 ? "row has" : "rows have"} no capacity set)
                  </span>
                )}
              </p>
              {submitted && errors.length > 0 && (
                <p className="text-sm text-red-600 mt-1 flex items-center gap-1">
                  <AlertCircle className="w-4 h-4 shrink-0" />
                  {batchError?.message ?? `${errors.length} row${errors.length === 1 ? "" : "s"} need attention.`}
                </p>
              )}
            </div>
          )}
        </div>

        <div className="flex justify-end space-x-2 pt-2 border-t">
          <Button onClick={() => onOpenChange(false)} disabled={saving} className="bg-red-600 hover:bg-red-700 text-white">
            Cancel
          </Button>
          <Button onClick={submit} disabled={saving || rows.length === 0} className="bg-blue-600 hover:bg-blue-700">
            {saving ? (
              <span className="flex items-center gap-2">
                <span className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin"></span>
                Creating...
              </span>
            ) : (
              createLabel
            )}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}
