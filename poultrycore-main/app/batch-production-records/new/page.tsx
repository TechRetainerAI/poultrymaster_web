"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Label } from "@/components/ui/label"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Textarea } from "@/components/ui/textarea"
import { Button } from "@/components/ui/button"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Alert, AlertTitle, AlertDescription } from "@/components/ui/alert"
import { Checkbox } from "@/components/ui/checkbox"
import { Popover, PopoverTrigger, PopoverContent } from "@/components/ui/popover"
import { FileText, X, ChevronDown, Info } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { getUserContext } from "@/lib/utils/user-context"
import { usePickSettings } from "@/hooks/use-pick-settings"
import { getFlocks, type Flock } from "@/lib/api/flock"
import { getFlockBatches, type FlockBatch } from "@/lib/api/flock-batch"
import {
  createBatchProductionRecord,
  getBatchProductionRecords,
  type BatchSelectionType,
  type BatchStatus,
  type ProductionBatchIncludedFlock,
  type ProductionBatchRecordInput,
  type ProductionBatchUsageLine,
} from "@/lib/api/production-batch"
import {
  EGG_GRADE_OPTIONS,
  EGG_GRADE_SELECT_VALUE_NONE,
  eggGradeToApi,
} from "@/lib/constants/egg-grade"
import {
  listPoultryRawMaterialItems,
  listPoultryRawMaterialPurchases,
  type PoultryRawMaterialItem,
  type PoultryRawMaterialPurchase,
} from "@/lib/api/poultry-inventory"
import { MedicationLines, computeMedLines, emptyMedLine, type MedLineDraft } from "@/components/production/medication-lines"
import { FeedLines, computeFeedLines, emptyFeedLine, type FeedLineDraft } from "@/components/production/feed-lines"

// Doc §4a: classify a raw-material item as Feed or Medication by its category.
const isFeedCategory = (c?: string | null) => !!c && /feed/i.test(c)
const isMedicationCategory = (c?: string | null) => !!c && /(medic|vaccin|drug)/i.test(c)

// Special sentinel values for the batch-scope dropdown.
const SCOPE_ALL = "all"
const SCOPE_CUSTOM = "custom"

// Map raw-material feed/medication rows to the batch usage-line shape.
function toBatchFeedLines(
  rows: ReturnType<typeof computeFeedLines>["rows"],
): ProductionBatchUsageLine[] {
  return rows
    .filter((r) => r.item && r.qty > 0)
    .map((r) => ({
      itemId: r.item!.poultryRawMaterialItemId,
      itemName: r.item!.itemName,
      qty: r.qty,
      unitCost: r.preview.unitCost,
      totalCost: Number((r.preview.totalCost ?? 0).toFixed(2)),
      method: r.item!.usageMethod ?? null,
    }))
}
function toBatchMedLines(
  rows: ReturnType<typeof computeMedLines>["rows"],
): ProductionBatchUsageLine[] {
  return rows
    .filter((r) => r.item && r.qty > 0)
    .map((r) => ({
      itemId: r.item!.poultryRawMaterialItemId,
      itemName: r.item!.itemName,
      qty: r.qty,
      unitCost: r.preview.unitCost,
      totalCost: Number((r.preview.totalCost ?? 0).toFixed(2)),
      method: r.item!.usageMethod ?? null,
    }))
}

export default function NewBatchProductionRecordPage() {
  const router = useRouter()
  const { toast } = useToast()
  const { labels: pickLabelText, enableFourthPick } = usePickSettings()
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState("")

  const today = useMemo(() => new Date().toISOString().slice(0, 10), [])

  // ---- Batch scope selector ------------------------------------------------
  const [batches, setBatches] = useState<FlockBatch[]>([])
  const [flocks, setFlocks] = useState<Flock[]>([])
  // Distinct custom batch names previously used (for the "reuse a name" dropdown).
  const [priorCustomNames, setPriorCustomNames] = useState<string[]>([])
  // The scope dropdown value: SCOPE_ALL | SCOPE_CUSTOM | String(batchId).
  const [scopeValue, setScopeValue] = useState<string>(SCOPE_ALL)
  const [batchName, setBatchName] = useState("")
  // Custom-batch flock multi-select (set of flockId).
  const [selectedFlockIds, setSelectedFlockIds] = useState<number[]>([])

  const activeFlocks = useMemo(() => flocks.filter((f) => f.active), [flocks])

  useEffect(() => {
    (async () => {
      try {
        const { userId, farmId } = getUserContext()
        if (!userId || !farmId) return
        const [batchRes, flockRes, recRes] = await Promise.all([
          getFlockBatches(userId, farmId),
          getFlocks(userId, farmId),
          getBatchProductionRecords(userId, farmId),
        ])
        setBatches(batchRes.success ? batchRes.data ?? [] : [])
        setFlocks(flockRes.success ? flockRes.data ?? [] : [])
        if (recRes.success && recRes.data) {
          const names = new Set<string>()
          for (const r of recRes.data) {
            if (r.batchSelectionType === "CustomBatch" && r.batchName && r.batchName.trim()) {
              names.add(r.batchName.trim())
            }
          }
          setPriorCustomNames([...names])
        }
      } catch { /* selectors optional */ }
    })()
  }, [])

  // Derive the batch selection type + specific bird-batch id from the scope value.
  const batchSelectionType: BatchSelectionType =
    scopeValue === SCOPE_ALL ? "AllBatches" : scopeValue === SCOPE_CUSTOM ? "CustomBatch" : "SpecificBatch"
  const selectedBirdBatchId = batchSelectionType === "SpecificBatch" ? parseInt(scopeValue) : null
  const specificBatch = useMemo(
    () => batches.find((b) => b.batchId === selectedBirdBatchId) ?? null,
    [batches, selectedBirdBatchId],
  )

  const toggleFlock = (flockId: number, checked: boolean) =>
    setSelectedFlockIds((prev) => (checked ? [...new Set([...prev, flockId])] : prev.filter((id) => id !== flockId)))

  // The frozen flock scope for the current selection — previewed live and reused on save.
  const includedFlocksList = useMemo(() => {
    if (batchSelectionType === "SpecificBatch") return activeFlocks.filter((f) => f.batchId === selectedBirdBatchId)
    if (batchSelectionType === "AllBatches") return activeFlocks
    return activeFlocks.filter((f) => selectedFlockIds.includes(f.flockId))
  }, [batchSelectionType, activeFlocks, selectedBirdBatchId, selectedFlockIds])

  // ---- Inventory (feed + medication) costing pickers ----------------------
  const [rawItems, setRawItems] = useState<PoultryRawMaterialItem[]>([])
  const [purchases, setPurchases] = useState<PoultryRawMaterialPurchase[]>([])
  useEffect(() => {
    (async () => {
      try {
        const [items, purch] = await Promise.all([
          listPoultryRawMaterialItems().catch(() => []),
          listPoultryRawMaterialPurchases().catch(() => []),
        ])
        setRawItems(Array.isArray(items) ? items : [])
        setPurchases(Array.isArray(purch) ? purch : [])
      } catch { /* inventory optional */ }
    })()
  }, [])

  const feedItems = useMemo(() => rawItems.filter((i) => isFeedCategory(i.category)), [rawItems])
  const medItems = useMemo(() => rawItems.filter((i) => isMedicationCategory(i.category)), [rawItems])

  // ---- Feed & medication lines (same components as the single-flock form) --
  const [feedLines, setFeedLines] = useState<FeedLineDraft[]>([emptyFeedLine(), emptyFeedLine()])
  const addFeedLine = () => setFeedLines((d) => [...d, emptyFeedLine()])
  const removeFeedLine = (idx: number) => setFeedLines((d) => d.filter((_, i) => i !== idx))
  const changeFeedLine = (idx: number, patch: Partial<FeedLineDraft>) =>
    setFeedLines((d) => d.map((row, i) => (i === idx ? { ...row, ...patch } : row)))

  const [medLines, setMedLines] = useState<MedLineDraft[]>([emptyMedLine(), emptyMedLine()])
  const addMedLine = () => setMedLines((d) => [...d, emptyMedLine()])
  const removeMedLine = (idx: number) => setMedLines((d) => d.filter((_, i) => i !== idx))
  const changeMedLine = (idx: number, patch: Partial<MedLineDraft>) =>
    setMedLines((d) => d.map((row, i) => (i === idx ? { ...row, ...patch } : row)))

  const feedComputed = useMemo(
    () => computeFeedLines(feedLines, feedItems, purchases),
    [feedLines, feedItems, purchases],
  )
  const medComputed = useMemo(
    () => computeMedLines(medLines, medItems, purchases),
    [medLines, medItems, purchases],
  )
  const totalFeedCost = feedComputed.totalCost
  const totalMedicationCost = medComputed.totalCost
  const totalCostOfProduction = totalFeedCost + totalMedicationCost

  // ---- Core form fields ----------------------------------------------------
  const [form, setForm] = useState({
    date: today,
    brokenEggs: "",
    meatyEggs: "",
    softEggs: "",
    lostEggs: "",
    feedType: "",
    feedKg: "",
    medication: "",
    deaths: "",
    birdsLeft: "",
    notes: "",
    eggGrade: EGG_GRADE_SELECT_VALUE_NONE,
  })

  const feedTypes = ["Starter Feed", "Grower Feed", "Layer Feed", "Broiler Feed", "Organic Feed", "Custom Mix"]

  // ---- Crate-based egg entry (Crates × 30 + Loose → total) ------------------
  const EGGS_PER_CRATE = 30
  const [firstCrates, setFirstCrates] = useState(0)
  const [firstLoose, setFirstLoose] = useState(0)
  const [secondCrates, setSecondCrates] = useState(0)
  const [secondLoose, setSecondLoose] = useState(0)
  const [thirdCrates, setThirdCrates] = useState(0)
  const [thirdLoose, setThirdLoose] = useState(0)
  const [fourthCrates, setFourthCrates] = useState(0)
  const [fourthLoose, setFourthLoose] = useState(0)

  const firstTotal = firstCrates * EGGS_PER_CRATE + firstLoose
  const secondTotal = secondCrates * EGGS_PER_CRATE + secondLoose
  const thirdTotal = thirdCrates * EGGS_PER_CRATE + thirdLoose
  const fourthTotal = fourthCrates * EGGS_PER_CRATE + fourthLoose

  const totalEggs = firstTotal + secondTotal + thirdTotal + fourthTotal
  const totalCrates = Math.floor(totalEggs / EGGS_PER_CRATE)
  const totalPieces = totalEggs % EGGS_PER_CRATE

  // ---- Age: derived from the specific batch's startDate (single batch only) -
  const { ageWeeks, ageDays, ageYears } = useMemo(() => {
    try {
      if (batchSelectionType !== "SpecificBatch" || !specificBatch?.startDate || !form.date)
        return { ageWeeks: 0, ageDays: 0, ageYears: 0 }
      const startStr = (specificBatch.startDate || "").split("T")[0]
      const currStr = form.date.split("T")[0]
      const [sy, sm, sd] = startStr.split("-").map(Number)
      const [cy, cm, cd] = currStr.split("-").map(Number)
      const startUtc = Date.UTC(sy, sm - 1, sd)
      const currUtc = Date.UTC(cy, cm - 1, cd)
      const ms = Math.max(0, currUtc - startUtc)
      const days = Math.floor(ms / (1000 * 60 * 60 * 24))
      return { ageWeeks: Math.floor(days / 7), ageDays: days, ageYears: Math.floor(days / 365) }
    } catch {
      return { ageWeeks: 0, ageDays: 0, ageYears: 0 }
    }
  }, [batchSelectionType, specificBatch, form.date])

  const isSpecific = batchSelectionType === "SpecificBatch"

  // ---- Submit --------------------------------------------------------------
  const handleSave = async (status: BatchStatus) => {
    try {
      setSaving(true)
      setError("")
      const { userId, farmId } = getUserContext()
      if (!userId || !farmId) throw new Error("Missing user/farm context")

      // Freeze the included-flock scope from the current selection.
      if (batchSelectionType === "CustomBatch" && includedFlocksList.length === 0) {
        setError("Select at least one flock for the custom batch.")
        setSaving(false)
        return
      }

      const includedFlocks: ProductionBatchIncludedFlock[] = includedFlocksList.map((f) => ({
        flockId: f.flockId,
        flockName: f.name,
        birdBatchId: f.batchId ?? null,
      }))

      const ageDisplay = isSpecific ? `${ageWeeks}w ${ageDays % 7}d` : "Mixed"

      const input: ProductionBatchRecordInput = {
        farmId,
        userId,
        createdBy: userId,
        updatedBy: userId,
        batchSelectionType,
        selectedBirdBatchId: batchSelectionType === "SpecificBatch" ? selectedBirdBatchId : null,
        batchName: batchName.trim() || null,
        productionDate: form.date,
        ageInWeeks: isSpecific ? ageWeeks : null,
        ageInDays: isSpecific ? ageDays : null,
        ageDisplay,
        firstPickCrates: firstCrates,
        firstPickLooseEggs: firstLoose,
        firstPickTotal: firstTotal,
        secondPickCrates: secondCrates,
        secondPickLooseEggs: secondLoose,
        secondPickTotal: secondTotal,
        thirdPickCrates: thirdCrates,
        thirdPickLooseEggs: thirdLoose,
        thirdPickTotal: thirdTotal,
        fourthPickCrates: fourthCrates,
        fourthPickLooseEggs: fourthLoose,
        fourthPickTotal: fourthTotal,
        brokenEggs: form.brokenEggs === "" ? null : parseInt(form.brokenEggs) || 0,
        meatyEggs: form.meatyEggs === "" ? null : parseInt(form.meatyEggs) || 0,
        softEggs: form.softEggs === "" ? null : parseInt(form.softEggs) || 0,
        lostEggs: form.lostEggs === "" ? null : parseInt(form.lostEggs) || 0,
        totalEggs,
        feedKg: parseFloat(form.feedKg) || 0,
        feedType: form.feedType || null,
        medication: form.medication.trim() || null,
        deaths: parseInt(form.deaths) || 0,
        birdsLeft: form.birdsLeft === "" ? null : parseInt(form.birdsLeft) || 0,
        eggGrade: eggGradeToApi(form.eggGrade),
        totalFeedCost: Number(totalFeedCost.toFixed(2)),
        totalMedicationCost: Number(totalMedicationCost.toFixed(2)),
        totalCostOfProduction: Number(totalCostOfProduction.toFixed(2)),
        status,
        notes: form.notes || null,
        includedFlocks,
        feeds: toBatchFeedLines(feedComputed.rows),
        medications: toBatchMedLines(medComputed.rows),
      }

      const res = await createBatchProductionRecord(input)
      if (!res.success) throw new Error(res.message || "Failed to save batch production record")

      if (status === "PendingAllocation") {
        toast({
          title: "Saved as Pending Allocation",
          description:
            "This batch production record has been saved as Pending Allocation. It will not affect flock records, inventory, birds left, or production reports until allocation is completed.",
        })
      } else {
        toast({ title: "Saved as draft", description: "This batch production record has been saved as a draft." })
      }
      router.push("/batch-production-records")
    } catch (err: any) {
      setError(err?.message || "Failed to save")
    } finally {
      setSaving(false)
    }
  }

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    handleSave("PendingAllocation")
  }

  const handleLogout = () => {
    localStorage.clear()
    router.push("/login")
  }

  const selectedFlockLabel =
    selectedFlockIds.length === 0
      ? "Select flocks"
      : `${selectedFlockIds.length} flock${selectedFlockIds.length === 1 ? "" : "s"} selected`

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6">
            {/* Page Header */}
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 bg-emerald-100 rounded-lg flex items-center justify-center">
                  <FileText className="w-5 h-5 text-emerald-600" />
                </div>
                <div>
                  <h1 className="text-2xl font-bold text-slate-900">Add New Batch Production Record</h1>
                  <p className="text-slate-600 text-sm">Log total production for a batch or group of flocks</p>
                </div>
              </div>
              <Button
                type="button"
                size="sm"
                className="gap-1.5 bg-red-600 hover:bg-red-700 text-white"
                onClick={() => router.push("/batch-production-records")}
              >
                <X className="w-4 h-4" />
                Cancel
              </Button>
            </div>

            {/* Totals banner */}
            <Alert className="border-indigo-200 bg-indigo-50">
              <Info className="h-4 w-4 text-indigo-600" />
              <AlertTitle className="text-indigo-900 font-semibold">Enter batch totals only</AlertTitle>
              <AlertDescription className="text-indigo-800 space-y-2">
                <p>
                  Record the <strong>total</strong> production for the whole selected batch/group — eggs, feed, medication
                  and deaths <strong>combined across every included flock</strong>.
                </p>
                <p className="flex flex-wrap items-center gap-x-1.5 gap-y-1">
                  <span>This record is saved as</span>
                  <span className="inline-flex items-center rounded-full border border-indigo-300 bg-white px-2 py-0.5 text-xs font-semibold text-indigo-700">
                    Pending Allocation
                  </span>
                  <span>
                    and stays inert — it does <strong>not</strong> affect flock records, inventory, birds left, or reports
                    until you complete an allocation.
                  </span>
                </p>
              </AlertDescription>
            </Alert>

            {error && (
              <Alert variant="destructive">
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}

            <form onSubmit={handleSubmit} className="space-y-6">
              {/* Section 1: Batch scope & Date */}
              <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Batch &amp; Date</div>
                <div className="grid grid-cols-12 gap-4 px-4 py-4">
                  <div className="col-span-12 md:col-span-4 space-y-2">
                    <Label>Batch</Label>
                    <Select value={scopeValue} onValueChange={setScopeValue}>
                      <SelectTrigger>
                        <SelectValue placeholder="Select batch scope" />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value={SCOPE_ALL}>All Batches</SelectItem>
                        {batches.map((b) => (
                          <SelectItem key={b.batchId} value={String(b.batchId)}>
                            {b.batchName || b.batchCode || `Batch ${b.batchId}`}
                          </SelectItem>
                        ))}
                        <SelectItem value={SCOPE_CUSTOM}>Custom Batch</SelectItem>
                      </SelectContent>
                    </Select>
                    <div className="text-xs text-slate-500">
                      Choose which flocks these totals cover. Age is only tracked for a single specific batch.
                    </div>
                  </div>

                  <div className="col-span-12 md:col-span-4 space-y-2">
                    <Label>Batch Name (optional)</Label>
                    <Input
                      value={batchName}
                      onChange={(e) => setBatchName(e.target.value)}
                      placeholder="e.g. Morning collection"
                    />
                    {priorCustomNames.length > 0 && (
                      <Select value="" onValueChange={(v) => setBatchName(v)}>
                        <SelectTrigger className="h-8 text-xs">
                          <SelectValue placeholder="Reuse a previous name" />
                        </SelectTrigger>
                        <SelectContent>
                          {priorCustomNames.map((n) => (
                            <SelectItem key={n} value={n}>{n}</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    )}
                  </div>

                  <div className="col-span-12 md:col-span-4 space-y-2">
                    <Label>Date</Label>
                    <Input
                      type="date"
                      value={form.date}
                      onChange={(e) => setForm({ ...form, date: e.target.value })}
                      required
                    />
                    <div className="text-xs text-slate-500">Defaults to today.</div>
                  </div>

                  {/* Custom-batch flock multi-select */}
                  {batchSelectionType === "CustomBatch" && (
                    <div className="col-span-12 space-y-2">
                      <Label>Flocks in this custom batch</Label>
                      <Popover>
                        <PopoverTrigger asChild>
                          <Button type="button" variant="outline" className="w-full justify-between font-normal">
                            {selectedFlockLabel}
                            <ChevronDown className="h-4 w-4 opacity-50" />
                          </Button>
                        </PopoverTrigger>
                        <PopoverContent className="w-[var(--radix-popover-trigger-width)] p-0" align="start">
                          <div className="max-h-64 overflow-y-auto p-2 space-y-1">
                            {activeFlocks.length === 0 && (
                              <div className="px-2 py-1.5 text-xs text-slate-400">No active flocks.</div>
                            )}
                            {activeFlocks.map((f) => (
                              <label
                                key={f.flockId}
                                className="flex items-center gap-2 rounded-md px-2 py-1.5 text-sm hover:bg-slate-50 cursor-pointer"
                              >
                                <Checkbox
                                  checked={selectedFlockIds.includes(f.flockId)}
                                  onCheckedChange={(c) => toggleFlock(f.flockId, c === true)}
                                />
                                <span className="flex-1">{f.name}</span>
                                {f.batchName && <span className="text-xs text-slate-400">{f.batchName}</span>}
                              </label>
                            ))}
                          </div>
                        </PopoverContent>
                      </Popover>
                      <div className="text-xs text-slate-500">At least one flock is required for a custom batch.</div>
                    </div>
                  )}

                  {/* Live preview of the flocks this batch will cover (frozen on save). */}
                  <div className="col-span-12">
                    <div className="rounded-lg border border-slate-200 bg-white px-3 py-2.5">
                      <div className="flex items-center justify-between mb-1.5">
                        <span className="text-xs font-semibold text-slate-600">
                          Included flocks
                          <span className="ml-1.5 inline-flex items-center justify-center rounded-full bg-slate-100 text-slate-600 px-1.5 min-w-[1.25rem] h-5 text-[11px] font-bold">
                            {includedFlocksList.length}
                          </span>
                        </span>
                        <span className="text-xs text-slate-400">
                          {isSpecific ? "Age tracked for this batch" : "Age: Mixed (per flock at allocation)"}
                        </span>
                      </div>
                      {includedFlocksList.length === 0 ? (
                        <p className="text-xs text-slate-400">
                          {batchSelectionType === "CustomBatch"
                            ? "Pick at least one flock above."
                            : "No active flocks match this scope yet."}
                        </p>
                      ) : (
                        <div className="flex flex-wrap gap-1.5">
                          {includedFlocksList.map((f) => (
                            <span
                              key={f.flockId}
                              className="inline-flex items-center rounded-full border border-indigo-100 bg-indigo-50 px-2 py-0.5 text-xs text-indigo-700"
                            >
                              {f.name}
                            </span>
                          ))}
                        </div>
                      )}
                    </div>
                  </div>
                </div>
              </div>

              {/* Section 2: Egg Production */}
              <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Egg Production (batch total)</div>
                <div className="grid grid-cols-12 gap-4 px-4 py-4">
                  {/* 1st Pick */}
                  <div className="col-span-12 p-3 bg-blue-50 border border-blue-200 rounded-lg space-y-2">
                    <Label className="text-blue-800 font-semibold">{pickLabelText.first} — Crates × {EGGS_PER_CRATE} + Loose Eggs</Label>
                    <div className="grid grid-cols-3 gap-3">
                      <div className="space-y-1">
                        <Label className="text-xs">Crates ({EGGS_PER_CRATE} eggs)</Label>
                        <NumberInput min="0" value={firstCrates} onChange={(e) => setFirstCrates(parseInt(e.target.value) || 0)} />
                      </div>
                      <div className="space-y-1">
                        <Label className="text-xs">Loose Eggs</Label>
                        <NumberInput min="0" max="29" value={firstLoose} onChange={(e) => setFirstLoose(parseInt(e.target.value) || 0)} />
                      </div>
                      <div className="space-y-1">
                        <Label className="text-xs">Total</Label>
                        <div className="h-10 px-3 py-2 bg-white border rounded-md flex items-center font-bold text-blue-700">{firstTotal.toLocaleString()}</div>
                      </div>
                    </div>
                    <p className="text-xs text-blue-600">{firstCrates} crates × {EGGS_PER_CRATE} + {firstLoose} loose = {firstTotal.toLocaleString()} eggs</p>
                  </div>

                  {/* 2nd Pick */}
                  <div className="col-span-12 p-3 bg-orange-50 border border-orange-200 rounded-lg space-y-2">
                    <Label className="text-orange-800 font-semibold">{pickLabelText.second} — Crates × {EGGS_PER_CRATE} + Loose Eggs</Label>
                    <div className="grid grid-cols-3 gap-3">
                      <div className="space-y-1">
                        <Label className="text-xs">Crates ({EGGS_PER_CRATE} eggs)</Label>
                        <NumberInput min="0" value={secondCrates} onChange={(e) => setSecondCrates(parseInt(e.target.value) || 0)} />
                      </div>
                      <div className="space-y-1">
                        <Label className="text-xs">Loose Eggs</Label>
                        <NumberInput min="0" max="29" value={secondLoose} onChange={(e) => setSecondLoose(parseInt(e.target.value) || 0)} />
                      </div>
                      <div className="space-y-1">
                        <Label className="text-xs">Total</Label>
                        <div className="h-10 px-3 py-2 bg-white border rounded-md flex items-center font-bold text-orange-700">{secondTotal.toLocaleString()}</div>
                      </div>
                    </div>
                    <p className="text-xs text-orange-600">{secondCrates} crates × {EGGS_PER_CRATE} + {secondLoose} loose = {secondTotal.toLocaleString()} eggs</p>
                  </div>

                  {/* 3rd Pick */}
                  <div className="col-span-12 p-3 bg-purple-50 border border-purple-200 rounded-lg space-y-2">
                    <Label className="text-purple-800 font-semibold">{pickLabelText.third} — Crates × {EGGS_PER_CRATE} + Loose Eggs</Label>
                    <div className="grid grid-cols-3 gap-3">
                      <div className="space-y-1">
                        <Label className="text-xs">Crates ({EGGS_PER_CRATE} eggs)</Label>
                        <NumberInput min="0" value={thirdCrates} onChange={(e) => setThirdCrates(parseInt(e.target.value) || 0)} />
                      </div>
                      <div className="space-y-1">
                        <Label className="text-xs">Loose Eggs</Label>
                        <NumberInput min="0" max="29" value={thirdLoose} onChange={(e) => setThirdLoose(parseInt(e.target.value) || 0)} />
                      </div>
                      <div className="space-y-1">
                        <Label className="text-xs">Total</Label>
                        <div className="h-10 px-3 py-2 bg-white border rounded-md flex items-center font-bold text-purple-700">{thirdTotal.toLocaleString()}</div>
                      </div>
                    </div>
                    <p className="text-xs text-purple-600">{thirdCrates} crates × {EGGS_PER_CRATE} + {thirdLoose} loose = {thirdTotal.toLocaleString()} eggs</p>
                  </div>

                  {/* 4th Pick — hidden when disabled and no value yet. */}
                  {(enableFourthPick || fourthTotal > 0) && (
                    <div className="col-span-12 p-3 bg-teal-50 border border-teal-200 rounded-lg space-y-2">
                      <Label className="text-teal-800 font-semibold">{pickLabelText.fourth} — Crates × {EGGS_PER_CRATE} + Loose Eggs</Label>
                      <div className="grid grid-cols-3 gap-3">
                        <div className="space-y-1">
                          <Label className="text-xs">Crates ({EGGS_PER_CRATE} eggs)</Label>
                          <NumberInput min="0" value={fourthCrates} onChange={(e) => setFourthCrates(parseInt(e.target.value) || 0)} />
                        </div>
                        <div className="space-y-1">
                          <Label className="text-xs">Loose Eggs</Label>
                          <NumberInput min="0" max="29" value={fourthLoose} onChange={(e) => setFourthLoose(parseInt(e.target.value) || 0)} />
                        </div>
                        <div className="space-y-1">
                          <Label className="text-xs">Total</Label>
                          <div className="h-10 px-3 py-2 bg-white border rounded-md flex items-center font-bold text-teal-700">{fourthTotal.toLocaleString()}</div>
                        </div>
                      </div>
                      <p className="text-xs text-teal-600">{fourthCrates} crates × {EGGS_PER_CRATE} + {fourthLoose} loose = {fourthTotal.toLocaleString()} eggs</p>
                    </div>
                  )}

                  {/* Broken / Meaty / Soft / Lost */}
                  <div className="col-span-12 grid grid-cols-2 md:grid-cols-4 gap-3">
                    <div className="p-3 bg-red-50 border border-red-200 rounded-lg space-y-2">
                      <Label className="text-red-800 font-semibold">Broken Eggs</Label>
                      <NumberInput min="0" value={form.brokenEggs} onChange={(e) => setForm({ ...form, brokenEggs: e.target.value })} placeholder="—" />
                    </div>
                    <div className="p-3 bg-amber-50 border border-amber-200 rounded-lg space-y-2">
                      <Label className="text-amber-800 font-semibold">Meaty Eggs</Label>
                      <NumberInput min="0" value={form.meatyEggs} onChange={(e) => setForm({ ...form, meatyEggs: e.target.value })} placeholder="—" />
                    </div>
                    <div className="p-3 bg-violet-50 border border-violet-200 rounded-lg space-y-2">
                      <Label className="text-violet-800 font-semibold">Soft Eggs</Label>
                      <NumberInput min="0" value={form.softEggs} onChange={(e) => setForm({ ...form, softEggs: e.target.value })} placeholder="—" />
                    </div>
                    <div className="p-3 bg-slate-50 border border-slate-200 rounded-lg space-y-2">
                      <Label className="text-slate-700 font-semibold">Lost Eggs</Label>
                      <NumberInput min="0" value={form.lostEggs} onChange={(e) => setForm({ ...form, lostEggs: e.target.value })} placeholder="—" />
                    </div>
                  </div>

                  {/* Total Eggs Summary */}
                  <div className="col-span-12 p-3 bg-emerald-50 border border-emerald-200 rounded-lg">
                    <div className="flex items-center justify-between">
                      <Label className="text-emerald-800 font-semibold">Total Eggs</Label>
                      <div className="text-right">
                        <div className="text-lg font-bold text-emerald-700">{totalEggs.toLocaleString()} eggs</div>
                        <div className="text-xs text-emerald-600">{totalCrates} crates + {totalPieces} pieces</div>
                      </div>
                    </div>
                  </div>

                  <div className="col-span-12 md:col-span-6 space-y-2">
                    <Label>Egg size</Label>
                    <Select value={form.eggGrade} onValueChange={(v) => setForm({ ...form, eggGrade: v })}>
                      <SelectTrigger className="bg-white">
                        <SelectValue placeholder="Select grade" />
                      </SelectTrigger>
                      <SelectContent>
                        {EGG_GRADE_OPTIONS.map((o) => (
                          <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <p className="text-xs text-slate-500">Egg size for this collection (Small, Medium, Large, X-Large, Jumbo).</p>
                  </div>
                </div>
              </div>

              {/* Section 3: Birds & Age */}
              <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Birds &amp; Age</div>
                <div className="grid grid-cols-12 gap-4 px-4 py-4">
                  <div className="col-span-12 md:col-span-4 space-y-2">
                    <Label>Deaths</Label>
                    <NumberInput min="0" value={form.deaths} onChange={(e) => setForm({ ...form, deaths: e.target.value })} placeholder="0" />
                    <p className="text-xs text-slate-500">Total birds lost across the batch on this day.</p>
                  </div>
                  <div className="col-span-12 md:col-span-4 space-y-2">
                    <Label>Birds Left (optional)</Label>
                    <NumberInput min="0" value={form.birdsLeft} onChange={(e) => setForm({ ...form, birdsLeft: e.target.value })} placeholder="—" />
                    <p className="text-xs text-slate-500">Leave blank to let allocation compute it per flock.</p>
                  </div>

                  <div className="col-span-12 md:col-span-4 space-y-2">
                    <Label>Age</Label>
                    {isSpecific ? (
                      <div className="grid grid-cols-3 gap-2">
                        <div className="space-y-1">
                          <Label className="text-xs">Weeks</Label>
                          <div className="h-10 flex items-center px-3 rounded-md border border-slate-200 bg-white font-semibold text-slate-700">{ageWeeks}</div>
                        </div>
                        <div className="space-y-1">
                          <Label className="text-xs">Days</Label>
                          <div className="h-10 flex items-center px-3 rounded-md border border-slate-200 bg-white font-semibold text-slate-700">{ageDays}</div>
                        </div>
                        <div className="space-y-1">
                          <Label className="text-xs">Years</Label>
                          <div className="h-10 flex items-center px-3 rounded-md border border-slate-200 bg-white font-semibold text-slate-700">{ageYears}</div>
                        </div>
                      </div>
                    ) : (
                      <div className="h-10 flex items-center px-3 rounded-md border border-slate-200 bg-white font-semibold text-slate-500">
                        Mixed — age tracked per flock during allocation
                      </div>
                    )}
                  </div>
                </div>
              </div>

              {/* Feed — inventory-based usage & costing (batch total). */}
              <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Feed</div>
                <div className="grid grid-cols-12 gap-4 px-4 py-4">
                  <div className="col-span-12 md:col-span-6 space-y-2">
                    <Label>Feed Type</Label>
                    <Select value={form.feedType} onValueChange={(v) => setForm({ ...form, feedType: v })}>
                      <SelectTrigger>
                        <SelectValue placeholder="Select feed type" />
                      </SelectTrigger>
                      <SelectContent>
                        {feedTypes.map((type) => (
                          <SelectItem key={type} value={type}>{type}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="col-span-12 md:col-span-6 space-y-2">
                    <Label>Feed Description</Label>
                    <NumberInput step="0.01" min="0" value={form.feedKg} onChange={(e) => setForm({ ...form, feedKg: e.target.value })} />
                  </div>

                  <div className="col-span-12 flex items-center gap-2 pt-1">
                    <div className="h-px flex-1 bg-slate-200" />
                    <span className="text-xs font-semibold uppercase tracking-wide text-emerald-700">Feed Breakdown (From Inventory)</span>
                    <div className="h-px flex-1 bg-slate-200" />
                  </div>

                  <FeedLines
                    lines={feedLines}
                    rows={feedComputed.rows}
                    feedItems={feedItems}
                    stockByItemId={feedComputed.pendingStockByItemId}
                    onAdd={addFeedLine}
                    onRemove={removeFeedLine}
                    onChange={changeFeedLine}
                  />

                  <div className="col-span-12 flex items-center justify-between rounded-lg bg-slate-50 border border-slate-200 px-4 py-2">
                    <span className="text-sm font-medium text-slate-700">Total Feed Cost</span>
                    <span className="text-base font-semibold text-slate-800">{totalFeedCost.toFixed(2)}</span>
                  </div>
                </div>
              </div>

              {/* Medication — inventory-based usage & costing (batch total). */}
              <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Medication</div>
                <div className="grid grid-cols-12 gap-4 px-4 py-4">
                  <div className="col-span-12 md:col-span-6 space-y-2">
                    <Label>Medication Description</Label>
                    <Input
                      value={form.medication}
                      onChange={(e) => setForm({ ...form, medication: e.target.value })}
                      placeholder="e.g. Vitamin supplement"
                    />
                  </div>

                  <div className="col-span-12 flex items-center gap-2 pt-1">
                    <div className="h-px flex-1 bg-slate-200" />
                    <span className="text-xs font-semibold uppercase tracking-wide text-emerald-700">Medication Breakdown (From Inventory)</span>
                    <div className="h-px flex-1 bg-slate-200" />
                  </div>

                  <MedicationLines
                    lines={medLines}
                    rows={medComputed.rows}
                    medItems={medItems}
                    stockByItemId={medComputed.pendingStockByItemId}
                    onAdd={addMedLine}
                    onRemove={removeMedLine}
                    onChange={changeMedLine}
                  />

                  <div className="col-span-12 flex items-center justify-between rounded-lg bg-slate-50 border border-slate-200 px-4 py-2">
                    <span className="text-sm font-medium text-slate-700">Total Medication Cost</span>
                    <span className="text-base font-semibold text-slate-800">{totalMedicationCost.toFixed(2)}</span>
                  </div>

                  <div className="col-span-12 flex items-center justify-between rounded-lg bg-emerald-50 border border-emerald-200 px-4 py-3">
                    <span className="text-sm font-medium text-emerald-800">Total Cost of Production</span>
                    <span className="text-lg font-bold text-emerald-800">{totalCostOfProduction.toFixed(2)}</span>
                  </div>
                  <p className="col-span-12 text-xs text-slate-500 -mt-1">
                    Feed/medication lines are recorded on the batch but do <strong>not</strong> reduce inventory until the batch
                    allocation is posted. Unit cost previews the item's FIFO/LIFO/HIFO usage policy.
                  </p>
                </div>
              </div>

              {/* Notes */}
              <div className="rounded-xl border border-slate-200 bg-slate-50 px-4 py-4 space-y-2">
                <Label>Notes</Label>
                <Textarea rows={3} value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} />
              </div>

              {/* Actions */}
              <div className="flex flex-wrap gap-3 justify-end pt-2">
                <Button
                  type="button"
                  onClick={() => router.push("/batch-production-records")}
                  className="min-w-[120px] bg-red-600 hover:bg-red-700 text-white"
                >
                  Cancel
                </Button>
                <Button
                  type="button"
                  variant="outline"
                  disabled={saving}
                  onClick={() => handleSave("Draft")}
                  className="min-w-[140px]"
                >
                  {saving ? "Saving..." : "Save as Draft"}
                </Button>
                <Button type="submit" disabled={saving} className="min-w-[180px]">
                  {saving ? "Saving..." : "Log Batch Production"}
                </Button>
              </div>
            </form>
          </div>
        </main>
      </div>
    </div>
  )
}
