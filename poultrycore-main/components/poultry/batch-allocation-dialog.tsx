"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Checkbox } from "@/components/ui/checkbox"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import {
  AlertCircle, ArrowLeft, Bird, CheckCircle2, Home, Loader2, Plus, Scale, Trash2, Wand2,
} from "lucide-react"
import {
  allocateBatchToFlocks, getBatchAllocationContext,
  type BatchAllocationContext, type FlockAllocationResult,
} from "@/lib/api/flock"
import {
  availableCapacity, buildRows, canFillByCapacity, defaultFlockName, distributeEqually,
  errorsByRow, fillByCapacity, summarize, toPayloadItems, validateRows,
  type AllocationField, type AllocationRow,
} from "@/lib/flocks/allocation"
import { BulkHouseDialog } from "@/components/poultry/bulk-house-dialog"
import { getUserContext } from "@/lib/utils/user-context"
import { useToast } from "@/hooks/use-toast"

// "Divide Into Flocks" — take one purchased batch and spread it across pens,
// creating a flock per pen in a single safe operation.
//
// Host-agnostic on purpose: the Flock Purchases page opens it on a batch, the
// Flock Groups page opens it with no batch and asks for one, and the Farm Setup
// Wizard will do the same later. `source` is what tells them apart in the audit
// trail. The arithmetic lives in lib/flocks/allocation.ts and every rule is
// re-run by the server, which is the one that decides.

/** The minimum a caller needs to offer a batch for selection. */
export interface AllocatableBatch {
  batchId: number
  batchCode: string
  batchName: string
  /** Birds the batch was bought with. */
  numberOfBirds: number
  /**
   * Birds still to be placed, when the host already knows. Omit it and the
   * batch is offered on its original size; the real figure is shown either way
   * once the batch is loaded.
   */
  unallocatedBirds?: number
}

interface BatchAllocationDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  /** Pre-selected batch. Omit to make the user pick one first. */
  batchId?: number | null
  /** Batches to choose from when `batchId` is not given. */
  batches?: AllocatableBatch[]
  /** Which screen is hosting this. Recorded on each created flock's audit row. */
  source?: string
  /** Called after a successful allocation, so the host can refresh its list. */
  onCreated?: (result: FlockAllocationResult) => void | Promise<void>
}

type Step = "batch" | "allocate" | "review" | "done"

export function BatchAllocationDialog({
  open, onOpenChange, batchId, batches = [], source, onCreated,
}: BatchAllocationDialogProps) {
  const router = useRouter()
  const { toast } = useToast()

  const [step, setStep] = useState<Step>("allocate")
  const [selectedBatchId, setSelectedBatchId] = useState<number | null>(batchId ?? null)
  const [context, setContext] = useState<BatchAllocationContext | null>(null)
  const [contextLoading, setContextLoading] = useState(false)
  const [contextError, setContextError] = useState("")

  const [selectedHouseIds, setSelectedHouseIds] = useState<number[]>([])
  const [rows, setRows] = useState<AllocationRow[]>([])
  const [submitted, setSubmitted] = useState(false)
  const [saving, setSaving] = useState(false)
  const [serverErrors, setServerErrors] = useState<Record<number, Partial<Record<string, string>>>>({})
  const [result, setResult] = useState<FlockAllocationResult | null>(null)
  const [bulkHouseOpen, setBulkHouseOpen] = useState(false)
  /** Explains where "Distribute Equally" put the odd birds, when there were any. */
  const [distributionNote, setDistributionNote] = useState("")

  const loadContext = useCallback(async (id: number) => {
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      setContextError("We could not confirm your farm or user. Please sign in again.")
      return
    }
    setContextLoading(true)
    setContextError("")
    const res = await getBatchAllocationContext(id, userId, farmId)
    if (res.success && res.data) {
      setContext(res.data)
    } else {
      setContext(null)
      setContextError(res.message || "Could not load this batch.")
    }
    setContextLoading(false)
  }, [])

  // Start each visit clean. A grid left from last time is a trap: the flocks it
  // names may since exist, and the batch may since have been spent.
  useEffect(() => {
    if (!open) return
    setSelectedBatchId(batchId ?? null)
    setStep(batchId ? "allocate" : "batch")
    setContext(null)
    setContextError("")
    setSelectedHouseIds([])
    setRows([])
    setSubmitted(false)
    setServerErrors({})
    setResult(null)
    setDistributionNote("")
    if (batchId) void loadContext(batchId)
  }, [open, batchId, loadContext])

  const houses = context?.houses ?? []
  const batch = context?.batch ?? null
  const availableBirds = batch?.unallocatedBirds ?? 0

  const errors = useMemo(
    () => (context ? validateRows(rows, {
      availableBirds,
      houses,
      existingNames: context.existingFlockNames,
    }) : []),
    [rows, availableBirds, houses, context],
  )
  const rowErrors = useMemo(() => errorsByRow(errors), [errors])
  const batchError = errors.find((e) => e.index < 0)
  const totals = useMemo(
    () => summarize(rows, batch?.originalBirds ?? 0, batch?.allocatedBirds ?? 0),
    [rows, batch],
  )

  // Quiet until the user tries to move on, except for the problems that are the
  // whole point of showing a preview — duplicates, and a pen that cannot hold
  // what is being put in it.
  const showErrorFor = (index: number, field: AllocationField) => {
    const message = rowErrors[index]?.[field]
    if (!message) return serverErrors[index]?.[field]
    if (submitted) return message
    return message.includes("already exists") || message.includes("more than once") || message.includes("will fit")
      ? message
      : undefined
  }

  const chooseBatch = async (id: number) => {
    setSelectedBatchId(id)
    setStep("allocate")
    setSelectedHouseIds([])
    setRows([])
    await loadContext(id)
  }

  // House selection drives the grid: ticking a pen adds its row (pre-named and
  // empty), unticking removes it. Quantities already typed into other rows are
  // left alone.
  const toggleHouse = (houseId: number, checked: boolean) => {
    setDistributionNote("")
    setServerErrors({})
    setSelectedHouseIds((prev) => (checked ? [...prev, houseId] : prev.filter((id) => id !== houseId)))
    setRows((prev) => {
      if (!checked) return prev.filter((r) => r.houseId !== houseId)
      if (prev.some((r) => r.houseId === houseId)) return prev
      const house = houses.find((h) => h.houseId === houseId)
      if (!house) return prev
      return [...prev, ...buildRows(batch?.batchCode ?? "", [house])]
    })
  }

  const selectAllHouses = () => {
    setDistributionNote("")
    setSelectedHouseIds(houses.map((h) => h.houseId))
    setRows(buildRows(batch?.batchCode ?? "", houses))
  }

  const clearHouses = () => {
    setDistributionNote("")
    setSelectedHouseIds([])
    setRows([])
  }

  const patchRow = (index: number, patch: Partial<AllocationRow>) => {
    setRows((prev) => prev.map((r, i) => (i === index ? { ...r, ...patch } : r)))
    setServerErrors({})
  }

  const removeRow = (index: number) => {
    const row = rows[index]
    setRows((prev) => prev.filter((_, i) => i !== index))
    setSelectedHouseIds((prev) => prev.filter((id) => id !== row?.houseId))
    setServerErrors({})
  }

  const runDistributeEqually = () => {
    const { rows: next, base, remainder } = distributeEqually(availableBirds, rows)
    setRows(next)
    setServerErrors({})
    setDistributionNote(
      remainder > 0
        ? `${base.toLocaleString()} birds each; the first ${remainder} ${remainder === 1 ? "pen takes" : "pens take"} one extra so none are lost.`
        : `${base.toLocaleString()} birds each.`,
    )
  }

  const runFillByCapacity = () => {
    setRows(fillByCapacity(availableBirds, rows, houses))
    setServerErrors({})
    setDistributionNote("Each pen filled to its remaining capacity, in order, until the birds ran out. Edit any row.")
  }

  const fillDisabled = !canFillByCapacity(rows, houses)

  const goToReview = () => {
    setSubmitted(true)
    if (errors.length > 0) {
      toast({
        title: "Check the rows below",
        description: batchError?.message ?? `${errors.length} row${errors.length === 1 ? "" : "s"} need attention.`,
        variant: "warning",
      })
      return
    }
    setStep("review")
  }

  const submit = async () => {
    if (!batch) return
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      toast({ title: "Session issue", description: "We could not confirm your farm or user. Please sign in again.", variant: "destructive" })
      return
    }

    setSaving(true)
    try {
      const res = await allocateBatchToFlocks({
        userId,
        farmId,
        batchId: batch.batchId,
        source: source ?? "Batch Allocation Tool",
        allocations: toPayloadItems(rows),
      })

      if (!res.success) {
        // The server re-runs every rule under a lock on the batch. When it
        // disagrees — usually because someone else allocated from this batch
        // while the tool was open — pin its messages to the same rows and send
        // the user back to edit rather than replacing what they typed.
        const fromServer: Record<number, Partial<Record<string, string>>> = {}
        for (const e of res.data?.errors ?? []) {
          if (e.index < 0) continue
          fromServer[e.index] = { ...(fromServer[e.index] ?? {}), [e.field]: e.message }
        }
        setServerErrors(fromServer)
        setStep("allocate")
        // Reload so the header and the capacity numbers reflect whatever changed.
        void loadContext(batch.batchId)
        toast({
          title: "No flocks were created",
          description: res.data?.message || res.message || "The allocation was rejected. Nothing was saved.",
          variant: "destructive",
        })
        return
      }

      setResult(res.data ?? null)
      setStep("done")
      await onCreated?.(res.data as FlockAllocationResult)
    } catch (e: any) {
      toast({
        title: "No flocks were created",
        description: e?.message || "Something went wrong. Nothing was saved.",
        variant: "destructive",
      })
    } finally {
      setSaving(false)
    }
  }

  // Nothing left to place means nothing to divide.
  const allocatableBatches = batches.filter((b) => (b.unallocatedBirds ?? b.numberOfBirds) > 0)

  return (
    <>
      <Dialog open={open} onOpenChange={onOpenChange}>
        <DialogContent className="w-[95vw] max-w-[1600px] max-h-[90vh] flex flex-col">
          <DialogHeader>
            <DialogTitle>
              {step === "done" ? "Flocks created" : "Divide Batch Into Flocks"}
            </DialogTitle>
            <DialogDescription>
              {step === "batch"
                ? "Pick the batch whose birds you want to divide across your houses/pens."
                : step === "review"
                  ? "Check the allocation before it is created. Nothing has been saved yet."
                  : step === "done"
                    ? "The birds are placed and the flocks are ready to use."
                    : "Choose the houses/pens, set how many birds go into each, then create every flock in one go."}
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-5 py-4 overflow-y-auto pr-1">
            {/* ---- Step 1: pick a batch ------------------------------------- */}
            {step === "batch" && (
              <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                <div className="bg-blue-600 px-4 py-2 text-sm font-semibold text-white">Select a Batch</div>
                <div className="p-4 space-y-3">
                  {allocatableBatches.length === 0 ? (
                    <p className="text-slate-600 text-sm">
                      No batches to divide yet. Record a flock purchase first, then come back here.
                    </p>
                  ) : (
                    <>
                      <Label htmlFor="alloc-batch">Batch</Label>
                      <Select onValueChange={(v) => void chooseBatch(Number(v))}>
                        <SelectTrigger id="alloc-batch">
                          <SelectValue placeholder="Choose the batch to divide" />
                        </SelectTrigger>
                        <SelectContent>
                          {allocatableBatches.map((b) => (
                            <SelectItem key={b.batchId} value={String(b.batchId)}>
                              {b.batchCode} · {b.batchName} ·{" "}
                              {b.unallocatedBirds != null
                                ? `${b.unallocatedBirds.toLocaleString()} of ${b.numberOfBirds.toLocaleString()} birds left`
                                : `${b.numberOfBirds.toLocaleString()} birds`}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      <p className="text-xs text-slate-500">
                        How many of those birds are still unallocated is shown once you pick one.
                      </p>
                    </>
                  )}
                </div>
              </div>
            )}

            {contextLoading && (
              <div className="flex items-center gap-2 text-slate-600 py-8 justify-center">
                <Loader2 className="w-4 h-4 animate-spin" /> Loading batch…
              </div>
            )}

            {contextError && !contextLoading && (
              <div className="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700 flex items-center gap-2">
                <AlertCircle className="w-4 h-4 shrink-0" /> {contextError}
              </div>
            )}

            {/* ---- Batch header: what there is to divide -------------------- */}
            {batch && step !== "batch" && (
              <div className="rounded-xl border border-slate-200 overflow-hidden bg-white">
                <div className="bg-slate-800 px-4 py-2 text-sm font-semibold text-white">
                  Batch {batch.batchCode} — {batch.batchName}
                </div>
                <div className="grid grid-cols-2 md:grid-cols-5 gap-4 p-4 text-sm">
                  <div>
                    <p className="text-slate-500">Original birds</p>
                    <p className="font-semibold text-slate-900">{batch.originalBirds.toLocaleString()}</p>
                  </div>
                  <div>
                    <p className="text-slate-500">Already allocated</p>
                    <p className="font-semibold text-slate-900">{batch.allocatedBirds.toLocaleString()}</p>
                  </div>
                  <div>
                    <p className="text-slate-500">Available</p>
                    <p className="font-semibold text-blue-700">{batch.unallocatedBirds.toLocaleString()}</p>
                  </div>
                  <div>
                    <p className="text-slate-500">Breed</p>
                    <p className="font-medium text-slate-900">{batch.breed || "—"}</p>
                  </div>
                  <div>
                    <p className="text-slate-500">Start date</p>
                    <p className="font-medium text-slate-900">
                      {batch.startDate ? String(batch.startDate).split("T")[0] : "—"}
                    </p>
                  </div>
                </div>
              </div>
            )}

            {/* ---- Step 2: houses + grid ------------------------------------ */}
            {batch && step === "allocate" && (
              <>
                <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                  <div className="bg-blue-600 px-4 py-2 text-sm font-semibold text-white flex items-center justify-between">
                    <span>Choose Houses/Pens</span>
                    <span className="font-normal">{selectedHouseIds.length} selected</span>
                  </div>
                  <div className="p-4 space-y-3">
                    <div className="flex flex-wrap items-center gap-2">
                      <Button type="button" variant="outline" size="sm" onClick={selectAllHouses} disabled={houses.length === 0}>
                        Select all
                      </Button>
                      <Button type="button" variant="outline" size="sm" onClick={clearHouses} disabled={rows.length === 0}>
                        Clear
                      </Button>
                      {/* Reuses the bulk house tool rather than a second house form. */}
                      <Button type="button" variant="outline" size="sm" onClick={() => setBulkHouseOpen(true)} className="gap-1">
                        <Plus className="w-4 h-4" />
                        Quickly Add Houses/Pens
                      </Button>
                    </div>

                    {houses.length === 0 ? (
                      <div className="text-center py-8">
                        <Home className="h-10 w-10 text-slate-400 mx-auto mb-3" />
                        <p className="text-slate-600">
                          No houses/pens on this farm yet. Add some above and they will appear here straight away.
                        </p>
                      </div>
                    ) : (
                      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
                        {houses.map((h) => {
                          const room = availableCapacity(h)
                          const checked = selectedHouseIds.includes(h.houseId)
                          return (
                            <label
                              key={h.houseId}
                              className={`flex items-start gap-3 rounded-lg border px-3 py-2 cursor-pointer bg-white ${
                                checked ? "border-blue-400 ring-1 ring-blue-200" : "border-slate-200"
                              }`}
                            >
                              <Checkbox
                                checked={checked}
                                onCheckedChange={(v) => toggleHouse(h.houseId, v === true)}
                                className="mt-1"
                              />
                              <span className="min-w-0">
                                <span className="block font-medium text-slate-900 truncate">{h.houseName}</span>
                                <span className="block text-xs text-slate-500">
                                  {h.capacity ? `Capacity ${h.capacity.toLocaleString()}` : "No capacity set"}
                                  {h.occupied > 0 && ` · holds ${h.occupied.toLocaleString()}`}
                                  {room != null && ` · ${room.toLocaleString()} free`}
                                </span>
                              </span>
                            </label>
                          )
                        })}
                      </div>
                    )}
                  </div>
                </div>

                <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                  <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Allocation</div>

                  {rows.length === 0 ? (
                    <div className="text-center py-10 px-4">
                      <Bird className="h-10 w-10 text-slate-400 mx-auto mb-3" />
                      <p className="text-slate-600">Tick the houses/pens above to start allocating.</p>
                    </div>
                  ) : (
                    <div className="p-4 space-y-3">
                      <div className="flex flex-wrap items-center gap-2">
                        <Button type="button" variant="outline" size="sm" onClick={runDistributeEqually} className="gap-1">
                          <Scale className="w-4 h-4" />
                          Distribute Equally
                        </Button>
                        <Button
                          type="button"
                          variant="outline"
                          size="sm"
                          onClick={runFillByCapacity}
                          disabled={fillDisabled}
                          className="gap-1"
                          title={fillDisabled ? "Every selected pen needs a capacity for this" : undefined}
                        >
                          <Wand2 className="w-4 h-4" />
                          Fill by Capacity
                        </Button>
                        {fillDisabled && rows.length > 0 && (
                          <span className="text-xs text-slate-500">
                            Fill by Capacity needs a capacity on every selected pen.
                          </span>
                        )}
                      </div>

                      {distributionNote && (
                        <p className="text-xs text-slate-600 bg-white border border-slate-200 rounded-md px-3 py-2">
                          {distributionNote} Every number stays editable.
                        </p>
                      )}

                      <div className="hidden md:grid grid-cols-12 gap-3 px-3 text-xs font-medium text-slate-500">
                        <div className="col-span-3">House/Pen</div>
                        <div className="col-span-2">Capacity</div>
                        <div className="col-span-4">Flock Name *</div>
                        <div className="col-span-2">Birds to Place *</div>
                        <div className="col-span-1 text-right">Action</div>
                      </div>

                      {rows.map((row, index) => {
                        const house = houses.find((h) => h.houseId === row.houseId)
                        const room = house ? availableCapacity(house) : null
                        const nameError = showErrorFor(index, "name")
                        const qtyError = showErrorFor(index, "quantity")
                        const houseError = showErrorFor(index, "houseId")
                        return (
                          <div
                            key={row.id}
                            className={`grid grid-cols-12 gap-3 items-start rounded-lg border px-3 py-3 bg-white ${
                              nameError || qtyError || houseError ? "border-red-300" : "border-slate-200"
                            }`}
                          >
                            <div className="col-span-12 md:col-span-3 min-w-0">
                              <p className="font-medium text-slate-900 truncate">{house?.houseName ?? `House ${row.houseId}`}</p>
                              {houseError && <p className="text-xs text-red-600">{houseError}</p>}
                            </div>
                            <div className="col-span-6 md:col-span-2 text-sm text-slate-600">
                              {house?.capacity ? (
                                <>
                                  <span className="block">{house.capacity.toLocaleString()}</span>
                                  <span className="block text-xs text-slate-500">
                                    {room != null ? `${room.toLocaleString()} free` : ""}
                                  </span>
                                </>
                              ) : (
                                <span className="text-slate-400">Not set</span>
                              )}
                            </div>
                            <div className="col-span-12 md:col-span-4 space-y-1">
                              <Input
                                aria-label={`Flock name, row ${index + 1}`}
                                value={row.name}
                                onChange={(e) => patchRow(index, { name: e.target.value })}
                                placeholder={defaultFlockName(batch.batchCode, house?.houseName ?? "")}
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
                                aria-label={`Birds to place, row ${index + 1}`}
                                min="0"
                                value={row.quantity}
                                onChange={(e) => patchRow(index, { quantity: e.target.value })}
                                placeholder="0"
                              />
                              {qtyError && <p className="text-xs text-red-600">{qtyError}</p>}
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
                    </div>
                  )}
                </div>
              </>
            )}

            {/* ---- Step 3: review ------------------------------------------- */}
            {batch && step === "review" && (
              <div className="rounded-xl border border-slate-200 overflow-hidden bg-white">
                <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Review</div>
                <div className="p-4 space-y-3">
                  <p className="text-slate-900">
                    <span className="font-semibold">{totals.flockCount}</span>{" "}
                    {totals.flockCount === 1 ? "flock" : "flocks"} will be created, placing{" "}
                    <span className="font-semibold">{totals.thisAllocation.toLocaleString()}</span> birds from{" "}
                    {batch.batchCode}.
                  </p>
                  <div className="divide-y divide-slate-100 border border-slate-200 rounded-lg">
                    {rows.map((row) => {
                      const house = houses.find((h) => h.houseId === row.houseId)
                      return (
                        <div key={row.id} className="flex items-center justify-between px-3 py-2 text-sm">
                          <span className="font-medium text-slate-900 truncate">{row.name}</span>
                          <span className="text-slate-600 shrink-0">
                            {house?.houseName ?? `House ${row.houseId}`} · {Number(row.quantity || 0).toLocaleString()} birds
                          </span>
                        </div>
                      )
                    })}
                  </div>
                  {totals.remaining > 0 && (
                    <p className="text-sm text-slate-600">
                      {totals.remaining.toLocaleString()} birds stay unallocated — you can come back and place them later.
                    </p>
                  )}
                </div>
              </div>
            )}

            {/* ---- Step 4: success ------------------------------------------ */}
            {step === "done" && result && (
              <div className="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-5 text-center space-y-2">
                <CheckCircle2 className="w-10 h-10 text-emerald-600 mx-auto" />
                <p className="text-lg font-semibold text-emerald-900">
                  {result.createdCount === 1 ? "1 flock created successfully." : `${result.createdCount} flocks created successfully.`}
                </p>
                <p className="text-emerald-800">
                  {result.birdsAllocated.toLocaleString()} birds allocated from {result.batch?.batchCode ?? "the batch"}.
                </p>
                <p className="text-emerald-800">
                  {(result.batch?.unallocatedBirds ?? 0).toLocaleString()} birds remain unallocated.
                </p>
              </div>
            )}

            {/* ---- Live totals ---------------------------------------------- */}
            {batch && (step === "allocate" || step === "review") && rows.length > 0 && (
              <div className={`rounded-xl border px-4 py-3 ${totals.overAllocated ? "border-red-300 bg-red-50" : "border-slate-200 bg-white"}`}>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                  <div>
                    <p className="text-slate-500">Batch birds</p>
                    <p className="font-semibold text-slate-900">{totals.batchBirds.toLocaleString()}</p>
                  </div>
                  <div>
                    <p className="text-slate-500">Previously allocated</p>
                    <p className="font-semibold text-slate-900">{totals.previouslyAllocated.toLocaleString()}</p>
                  </div>
                  <div>
                    <p className="text-slate-500">This allocation</p>
                    <p className={`font-semibold ${totals.overAllocated ? "text-red-700" : "text-blue-700"}`}>
                      {totals.thisAllocation.toLocaleString()}
                    </p>
                  </div>
                  <div>
                    <p className="text-slate-500">Remaining unallocated</p>
                    <p className="font-semibold text-slate-900">{totals.remaining.toLocaleString()}</p>
                  </div>
                </div>
                {batchError && (
                  <p className="text-sm text-red-700 mt-2 flex items-center gap-1">
                    <AlertCircle className="w-4 h-4 shrink-0" />
                    {batchError.message}
                  </p>
                )}
              </div>
            )}
          </div>

          {/* ---- Footer ------------------------------------------------------ */}
          <div className="flex justify-end gap-2 pt-2 border-t">
            {step === "done" ? (
              <>
                <Button variant="outline" onClick={() => onOpenChange(false)}>Return to Batch</Button>
                <Button
                  className="bg-blue-600 hover:bg-blue-700"
                  onClick={() => { onOpenChange(false); router.push("/flocks") }}
                >
                  View Flocks
                </Button>
              </>
            ) : step === "review" ? (
              <>
                <Button variant="outline" onClick={() => setStep("allocate")} disabled={saving} className="gap-1">
                  <ArrowLeft className="w-4 h-4" />
                  Back &amp; Edit
                </Button>
                <Button onClick={submit} disabled={saving} className="bg-blue-600 hover:bg-blue-700">
                  {saving ? (
                    <span className="flex items-center gap-2">
                      <Loader2 className="w-4 h-4 animate-spin" />
                      Creating…
                    </span>
                  ) : (
                    `Create ${totals.flockCount} ${totals.flockCount === 1 ? "Flock" : "Flocks"}`
                  )}
                </Button>
              </>
            ) : (
              <>
                <Button onClick={() => onOpenChange(false)} className="bg-red-600 hover:bg-red-700 text-white">
                  Cancel
                </Button>
                <Button
                  onClick={goToReview}
                  disabled={rows.length === 0 || contextLoading}
                  className="bg-blue-600 hover:bg-blue-700"
                >
                  Review &amp; Create
                </Button>
              </>
            )}
          </div>
        </DialogContent>
      </Dialog>

      {/* The bulk house tool from the Houses page, reused rather than rebuilt.
          Reloading the context is what makes new pens selectable immediately. */}
      <BulkHouseDialog
        open={bulkHouseOpen}
        onOpenChange={setBulkHouseOpen}
        existingNames={houses.map((h) => h.houseName)}
        source="Batch Allocation"
        onCreated={async () => {
          if (selectedBatchId) await loadContext(selectedBatchId)
        }}
      />
    </>
  )
}
