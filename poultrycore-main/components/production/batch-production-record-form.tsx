"use client"

// =============================================================================
// BatchProductionRecordForm — the ONE batch production record form.
//
// Same consolidation as ProductionRecordForm, for the batch-level records:
//
//   app/batch-production-records/new/page.tsx        (857 lines)
//   app/batch-production-records/[id]/edit/page.tsx  (821 lines)
//
// were near-identical copies. Unlike the single-flock pair these had NOT
// drifted in what they save — the payloads were field-for-field the same — so
// this consolidation is about stopping the next divergence rather than
// repairing one.
//
// A batch record is deliberately inert: it holds TOTALS for a group of flocks
// and affects nothing until an allocation distributes them (see
// /batch-production-records/[id]/allocate). That is why "save" has two
// outcomes, Draft and PendingAllocation, and why the footer offers both.
//
// The ONLY difference between modal and page is layout.
// =============================================================================

import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { Label } from "@/components/ui/label"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { Button } from "@/components/ui/button"
import { Checkbox } from "@/components/ui/checkbox"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { AlertTriangle, Bird, Boxes, Egg, FileText, Info, Loader2, Pill, Scale, Wheat } from "lucide-react"
import { cn } from "@/lib/utils"
import { useToast } from "@/hooks/use-toast"
import { getUserContext } from "@/lib/utils/user-context"
import { usePickSettings } from "@/hooks/use-pick-settings"
import { getFlocks, type Flock } from "@/lib/api/flock"
import { getFlockBatches, type FlockBatch } from "@/lib/api/flock-batch"
import {
  createBatchProductionRecord, updateBatchProductionRecord,
  getBatchProductionRecord, getBatchProductionRecords,
  type BatchSelectionType, type BatchStatus,
  type ProductionBatchIncludedFlock, type ProductionBatchRecordInput,
  type ProductionBatchUsageLine,
} from "@/lib/api/production-batch"
import {
  listPoultryRawMaterialItems, listPoultryRawMaterialPurchases,
  type PoultryRawMaterialItem, type PoultryRawMaterialPurchase,
} from "@/lib/api/poultry-inventory"
import { MedicationLines, computeMedLines, emptyMedLine, type MedLineDraft } from "@/components/production/medication-lines"
import { FeedLines, computeFeedLines, emptyFeedLine, type FeedLineDraft } from "@/components/production/feed-lines"
import { EGG_GRADE_OPTIONS, EGG_GRADE_SELECT_VALUE_NONE, eggGradeFromApi, eggGradeToApi } from "@/lib/constants/egg-grade"
import { FormSectionCard, CalcField, NumField } from "./production-record-fields"
import {
  cratesEquivalent, effectiveFeedKg as calcEffectiveFeedKg, flockAge as calcFlockAge,
  netSellableEggs as calcNetSellable, pickTotal, totalCostOfProduction as calcTotalCost,
  totalLosses as calcTotalLosses,
} from "@/lib/production/production-record-calc"

// Doc §4a: classify a raw-material item as Feed or Medication by its category.
const isFeedCategory = (c?: string | null) => !!c && /feed/i.test(c)
const isMedicationCategory = (c?: string | null) => !!c && /(medic|vaccin|drug)/i.test(c)

// Sentinels for the batch-scope dropdown.
const SCOPE_ALL = "all"
const SCOPE_CUSTOM = "custom"

const FEED_TYPES = ["Starter Feed", "Grower Feed", "Layer Feed", "Broiler Feed", "Organic Feed", "Custom Mix"]

const numStr = (v: number | null | undefined) => (v == null ? "" : String(v))

/** Raw-material rows -> the batch usage-line shape the API stores. */
function toBatchUsageLines(
  rows: { item: PoultryRawMaterialItem | null; qty: number; preview: { unitCost: number | null; totalCost?: number | null } }[],
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

export interface BatchProductionRecordFormState {
  dirty: boolean
  saving: boolean
  loading: boolean
  scopeLabel: string | null
  date: string
  includedFlockCount: number
  summary: {
    totalEggs: number
    totalCrates: number
    totalPieces: number
    totalLosses: number
    netSellableEggs: number
    deaths: number
    birdsLeft: number | null
    feedCost: number
    medicationCost: number
    totalCost: number
  }
}

export interface BatchProductionRecordFormProps {
  mode: "create" | "edit"
  displayMode: "modal" | "page"
  recordId?: number
  formId?: string
  hideActions?: boolean
  onSaved?: (status: BatchStatus) => void
  onCancel?: () => void
  onStateChange?: (state: BatchProductionRecordFormState) => void
  /** Lets the modal footer drive the two save outcomes. */
  onRegisterSave?: (save: (status: BatchStatus) => void) => void
}

export function BatchProductionRecordForm({
  mode, displayMode, recordId,
  formId = "batch-production-record-form", hideActions = false,
  onSaved, onCancel, onStateChange, onRegisterSave,
}: BatchProductionRecordFormProps) {
  const { toast } = useToast()
  const isEdit = mode === "edit"
  const { labels: pickLabelText, enableFourthPick } = usePickSettings()

  const [saving, setSaving] = useState(false)
  const [loading, setLoading] = useState(isEdit)
  const [error, setError] = useState("")
  const [dirty, setDirty] = useState(false)

  const today = useMemo(() => new Date().toISOString().slice(0, 10), [])

  // ---- Batch scope --------------------------------------------------------
  const [batches, setBatches] = useState<FlockBatch[]>([])
  const [flocks, setFlocks] = useState<Flock[]>([])
  const [priorCustomNames, setPriorCustomNames] = useState<string[]>([])
  const [scopeValue, setScopeValue] = useState<string>(SCOPE_ALL)
  const [batchName, setBatchName] = useState("")
  const [selectedFlockIds, setSelectedFlockIds] = useState<number[]>([])

  const activeFlocks = useMemo(() => flocks.filter((f) => f.active), [flocks])

  const batchSelectionType: BatchSelectionType =
    scopeValue === SCOPE_ALL ? "AllBatches" : scopeValue === SCOPE_CUSTOM ? "CustomBatch" : "SpecificBatch"
  const selectedBirdBatchId = batchSelectionType === "SpecificBatch" ? parseInt(scopeValue) : null
  const specificBatch = useMemo(
    () => batches.find((b) => b.batchId === selectedBirdBatchId) ?? null,
    [batches, selectedBirdBatchId],
  )
  const isSpecific = batchSelectionType === "SpecificBatch"

  const toggleFlock = (flockId: number, checked: boolean) => {
    setDirty(true)
    setSelectedFlockIds((prev) => (checked ? [...new Set([...prev, flockId])] : prev.filter((id) => id !== flockId)))
  }

  /** The frozen flock scope for the current selection — previewed live, reused on save. */
  const includedFlocksList = useMemo(() => {
    if (batchSelectionType === "SpecificBatch") return activeFlocks.filter((f) => f.batchId === selectedBirdBatchId)
    if (batchSelectionType === "AllBatches") return activeFlocks
    return activeFlocks.filter((f) => selectedFlockIds.includes(f.flockId))
  }, [batchSelectionType, activeFlocks, selectedBirdBatchId, selectedFlockIds])

  // ---- Inventory ----------------------------------------------------------
  const [rawItems, setRawItems] = useState<PoultryRawMaterialItem[]>([])
  const [purchases, setPurchases] = useState<PoultryRawMaterialPurchase[]>([])
  const feedItems = useMemo(() => rawItems.filter((i) => isFeedCategory(i.category)), [rawItems])
  const medItems = useMemo(() => rawItems.filter((i) => isMedicationCategory(i.category)), [rawItems])

  const [feedLines, setFeedLines] = useState<FeedLineDraft[]>(isEdit ? [] : [emptyFeedLine(), emptyFeedLine()])
  const addFeedLine = () => { setDirty(true); setFeedLines((d) => [...d, emptyFeedLine()]) }
  const removeFeedLine = (idx: number) => { setDirty(true); setFeedLines((d) => d.filter((_, i) => i !== idx)) }
  const changeFeedLine = (idx: number, p: Partial<FeedLineDraft>) => {
    setDirty(true); setFeedLines((d) => d.map((row, i) => (i === idx ? { ...row, ...p } : row)))
  }

  const [medLines, setMedLines] = useState<MedLineDraft[]>(isEdit ? [] : [emptyMedLine(), emptyMedLine()])
  const addMedLine = () => { setDirty(true); setMedLines((d) => [...d, emptyMedLine()]) }
  const removeMedLine = (idx: number) => { setDirty(true); setMedLines((d) => d.filter((_, i) => i !== idx)) }
  const changeMedLine = (idx: number, p: Partial<MedLineDraft>) => {
    setDirty(true); setMedLines((d) => d.map((row, i) => (i === idx ? { ...row, ...p } : row)))
  }

  const feedComputed = useMemo(() => computeFeedLines(feedLines, feedItems, purchases), [feedLines, feedItems, purchases])
  const medComputed = useMemo(() => computeMedLines(medLines, medItems, purchases), [medLines, medItems, purchases])
  const totalFeedCost = feedComputed.totalCost
  const totalMedicationCost = medComputed.totalCost
  const totalCostOfProduction = calcTotalCost(totalFeedCost, totalMedicationCost)
  const feedFromLines = feedComputed.totalConsumed > 0

  // ---- Core fields --------------------------------------------------------
  const [form, setForm] = useState({
    date: today,
    brokenEggs: "", meatyEggs: "", softEggs: "", lostEggs: "",
    feedType: "", feedKg: "",
    medication: "", deaths: "", birdsLeft: "", notes: "",
    eggGrade: EGG_GRADE_SELECT_VALUE_NONE,
  })
  const patch = useCallback((p: Partial<typeof form>) => {
    setDirty(true)
    setForm((prev) => ({ ...prev, ...p }))
  }, [])

  // Feed comes from the breakdown lines. Allocation computes each flock's share
  // from batch.feeds, and posting passes THAT to spproductionrecord_insert — the
  // batch-level number is never read downstream. Deriving it keeps the figure
  // honest and stops anyone typing a quantity here that silently does nothing.
  const effectiveFeedKg = calcEffectiveFeedKg(feedComputed.totalConsumed, form.feedKg)

  // ---- Crate entry --------------------------------------------------------
  const [picks, setPicks] = useState({
    firstCrates: 0, firstLoose: 0, secondCrates: 0, secondLoose: 0,
    thirdCrates: 0, thirdLoose: 0, fourthCrates: 0, fourthLoose: 0,
  })
  const setPick = (p: Partial<typeof picks>) => { setDirty(true); setPicks((prev) => ({ ...prev, ...p })) }

  const firstTotal = pickTotal(picks.firstCrates, picks.firstLoose)
  const secondTotal = pickTotal(picks.secondCrates, picks.secondLoose)
  const thirdTotal = pickTotal(picks.thirdCrates, picks.thirdLoose)
  const fourthTotal = pickTotal(picks.fourthCrates, picks.fourthLoose)
  const totalEggs = firstTotal + secondTotal + thirdTotal + fourthTotal
  const { crates: totalCrates, pieces: totalPieces } = cratesEquivalent(totalEggs)

  const brokenEggs = parseInt(form.brokenEggs) || 0
  const meatyEggs = parseInt(form.meatyEggs) || 0
  const softEggs = parseInt(form.softEggs) || 0
  const lostEggs = parseInt(form.lostEggs) || 0
  const totalLosses = calcTotalLosses({ broken: brokenEggs, meaty: meatyEggs, soft: softEggs, lost: lostEggs })
  const netSellableEggs = calcNetSellable(totalEggs, totalLosses)

  // Age comes from the specific batch's start date, and only for a single batch —
  // a mixed scope has no one age, which is why the payload sends "Mixed".
  const { ageWeeks, ageDays, ageYears } = useMemo(
    () => (isSpecific ? calcFlockAge(specificBatch?.startDate, form.date) : { ageWeeks: 0, ageDays: 0, ageYears: 0 }),
    [isSpecific, specificBatch, form.date],
  )

  // ---- Load selectors (+ the record, when editing) -------------------------
  const hydrated = useRef(false)
  useEffect(() => {
    (async () => {
      try {
        const { userId, farmId } = getUserContext()
        if (!userId || !farmId) return
        const [batchRes, flockRes, items, purch, recRes] = await Promise.all([
          getFlockBatches(userId, farmId),
          getFlocks(userId, farmId),
          listPoultryRawMaterialItems().catch(() => []),
          listPoultryRawMaterialPurchases().catch(() => []),
          isEdit && recordId != null ? getBatchProductionRecord(recordId, farmId) : Promise.resolve(null),
          ])
        setBatches(batchRes.success ? batchRes.data ?? [] : [])
        setFlocks(flockRes.success ? flockRes.data ?? [] : [])
        setRawItems(Array.isArray(items) ? items : [])
        setPurchases(Array.isArray(purch) ? purch : [])

        if (!isEdit) {
          // Distinct custom batch names already used, for the "reuse a name" list.
          try {
            const recs = await getBatchProductionRecords(userId, farmId)
            if (recs.success && recs.data) {
              const names = new Set<string>()
              for (const r of recs.data) {
                if (r.batchSelectionType === "CustomBatch" && r.batchName?.trim()) names.add(r.batchName.trim())
              }
              setPriorCustomNames([...names])
            }
          } catch { /* optional */ }
        }

        if (isEdit) {
          if (!recRes || !recRes.success || !recRes.data) {
            setError(recRes?.message || "Batch production record not found")
          } else {
            const r = recRes.data
            setScopeValue(
              r.batchSelectionType === "AllBatches" ? SCOPE_ALL
                : r.batchSelectionType === "CustomBatch" ? SCOPE_CUSTOM
                  : String(r.selectedBirdBatchId ?? ""),
            )
            setBatchName(r.batchName ?? "")
            setSelectedFlockIds((r.includedFlocks ?? []).map((f) => f.flockId))
            setPicks({
              firstCrates: r.firstPickCrates ?? 0, firstLoose: r.firstPickLooseEggs ?? 0,
              secondCrates: r.secondPickCrates ?? 0, secondLoose: r.secondPickLooseEggs ?? 0,
              thirdCrates: r.thirdPickCrates ?? 0, thirdLoose: r.thirdPickLooseEggs ?? 0,
              fourthCrates: r.fourthPickCrates ?? 0, fourthLoose: r.fourthPickLooseEggs ?? 0,
            })
            setForm({
              date: (r.productionDate || "").split("T")[0] || today,
              brokenEggs: numStr(r.brokenEggs), meatyEggs: numStr(r.meatyEggs),
              softEggs: numStr(r.softEggs), lostEggs: numStr(r.lostEggs),
              feedType: r.feedType ?? "", feedKg: numStr(r.feedKg),
              medication: r.medication ?? "", deaths: numStr(r.deaths),
              birdsLeft: numStr(r.birdsLeft), notes: r.notes ?? "",
              eggGrade: eggGradeFromApi(r.eggGrade),
            })
            setFeedLines((r.feeds ?? []).length > 0
              ? r.feeds.map((f) => ({ specificFeedUsedId: String(f.itemId), totalFeedConsumed: String(f.qty) }))
              : [emptyFeedLine()])
            setMedLines((r.medications ?? []).length > 0
              ? r.medications.map((m) => ({ specificMedicationUsedId: String(m.itemId), totalMedicationConsumed: String(m.qty) }))
              : [emptyMedLine()])
          }
        }
      } catch (e: any) {
        setError(e?.message || "Failed to load")
      } finally {
        hydrated.current = true
        setDirty(false)
        setLoading(false)
      }
    })()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isEdit, recordId])

  // ---- Lift state ---------------------------------------------------------
  const scopeLabel =
    batchSelectionType === "AllBatches" ? "All batches"
      : batchSelectionType === "CustomBatch" ? (batchName.trim() || "Custom batch")
        : specificBatch?.batchName ?? specificBatch?.batchCode ?? null

  const summary = useMemo(() => ({
    totalEggs, totalCrates, totalPieces, totalLosses, netSellableEggs,
    deaths: parseInt(form.deaths) || 0,
    birdsLeft: form.birdsLeft === "" ? null : parseInt(form.birdsLeft) || 0,
    feedCost: totalFeedCost, medicationCost: totalMedicationCost, totalCost: totalCostOfProduction,
  }), [totalEggs, totalCrates, totalPieces, totalLosses, netSellableEggs,
       form.deaths, form.birdsLeft, totalFeedCost, totalMedicationCost, totalCostOfProduction])

  useEffect(() => {
    onStateChange?.({
      dirty, saving, loading, scopeLabel, date: form.date,
      includedFlockCount: includedFlocksList.length, summary,
    })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dirty, saving, loading, scopeLabel, form.date, includedFlocksList.length, summary])

  // ---- Save ---------------------------------------------------------------
  const handleSave = useCallback(async (status: BatchStatus) => {
    try {
      setSaving(true)
      setError("")
      const { userId, farmId } = getUserContext()
      if (!userId || !farmId) throw new Error("Missing user/farm context")

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
        ...(isEdit && recordId != null ? { id: recordId } : {}),
        farmId, userId, createdBy: userId, updatedBy: userId,
        batchSelectionType,
        selectedBirdBatchId: isSpecific ? selectedBirdBatchId : null,
        batchName: batchName.trim() || null,
        productionDate: form.date,
        ageInWeeks: isSpecific ? ageWeeks : null,
        ageInDays: isSpecific ? ageDays : null,
        ageDisplay,
        firstPickCrates: picks.firstCrates, firstPickLooseEggs: picks.firstLoose, firstPickTotal: firstTotal,
        secondPickCrates: picks.secondCrates, secondPickLooseEggs: picks.secondLoose, secondPickTotal: secondTotal,
        thirdPickCrates: picks.thirdCrates, thirdPickLooseEggs: picks.thirdLoose, thirdPickTotal: thirdTotal,
        fourthPickCrates: picks.fourthCrates, fourthPickLooseEggs: picks.fourthLoose, fourthPickTotal: fourthTotal,
        brokenEggs: form.brokenEggs === "" ? null : parseInt(form.brokenEggs) || 0,
        meatyEggs: form.meatyEggs === "" ? null : parseInt(form.meatyEggs) || 0,
        softEggs: form.softEggs === "" ? null : parseInt(form.softEggs) || 0,
        lostEggs: form.lostEggs === "" ? null : parseInt(form.lostEggs) || 0,
        totalEggs,
        feedKg: effectiveFeedKg,
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
        feeds: toBatchUsageLines(feedComputed.rows),
        medications: toBatchUsageLines(medComputed.rows),
      }

      const res = isEdit && recordId != null
        ? await updateBatchProductionRecord(recordId, input)
        : await createBatchProductionRecord(input)
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

      setDirty(false)
      onSaved?.(status)
    } catch (err: any) {
      setError(err?.message || "Failed to save")
    } finally {
      setSaving(false)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [batchSelectionType, includedFlocksList, isSpecific, ageWeeks, ageDays, selectedBirdBatchId,
      batchName, form, picks, firstTotal, secondTotal, thirdTotal, fourthTotal, totalEggs,
      effectiveFeedKg, totalFeedCost, totalMedicationCost, totalCostOfProduction,
      feedComputed.rows, medComputed.rows, isEdit, recordId])

  // The modal footer owns the two save buttons, so hand it the same function
  // this form's own footer calls — one save path, two entry points.
  useEffect(() => { onRegisterSave?.(handleSave) }, [onRegisterSave, handleSave])

  if (loading) {
    return (
      <div className="flex items-center justify-center gap-2 py-16 text-slate-500">
        <Loader2 className="h-4 w-4 animate-spin" /> Loading batch production record…
      </div>
    )
  }

  const pickRows = [
    { key: "first", label: pickLabelText.first, crates: picks.firstCrates, loose: picks.firstLoose,
      setC: (v: number | string) => setPick({ firstCrates: Number(v) || 0 }), setL: (v: number | string) => setPick({ firstLoose: Number(v) || 0 }), total: firstTotal },
    { key: "second", label: pickLabelText.second, crates: picks.secondCrates, loose: picks.secondLoose,
      setC: (v: number | string) => setPick({ secondCrates: Number(v) || 0 }), setL: (v: number | string) => setPick({ secondLoose: Number(v) || 0 }), total: secondTotal },
    { key: "third", label: pickLabelText.third, crates: picks.thirdCrates, loose: picks.thirdLoose,
      setC: (v: number | string) => setPick({ thirdCrates: Number(v) || 0 }), setL: (v: number | string) => setPick({ thirdLoose: Number(v) || 0 }), total: thirdTotal },
    ...(enableFourthPick
      ? [{ key: "fourth", label: pickLabelText.fourth, crates: picks.fourthCrates, loose: picks.fourthLoose,
           setC: (v: number | string) => setPick({ fourthCrates: Number(v) || 0 }), setL: (v: number | string) => setPick({ fourthLoose: Number(v) || 0 }), total: fourthTotal }]
      : []),
  ]

  return (
    <form
      id={formId}
      onSubmit={(e) => { e.preventDefault(); void handleSave("PendingAllocation") }}
      className={cn("space-y-4", displayMode === "modal" ? "" : "mx-auto w-full max-w-[110rem]")}
    >
      {error && <Alert variant="destructive"><AlertDescription>{error}</AlertDescription></Alert>}

      {/* ------------------------------------------------ Batch scope */}
      <FormSectionCard
        title="Batch & Date"
        description="Which flocks these totals cover, and the day they were collected."
        badge={`${includedFlocksList.length} flock${includedFlocksList.length === 1 ? "" : "s"}`}
        accent="sky"
        icon={Boxes}
      >
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <div className="space-y-1.5">
            <Label>Batch scope</Label>
            <Select value={scopeValue} onValueChange={(v) => { setDirty(true); setScopeValue(v) }}>
              <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value={SCOPE_ALL}>All batches</SelectItem>
                <SelectItem value={SCOPE_CUSTOM}>Custom selection</SelectItem>
                {batches.map((b) => (
                  <SelectItem key={b.batchId} value={String(b.batchId)}>
                    {b.batchName || b.batchCode || `Batch ${b.batchId}`}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="bpr-date">Date <span className="text-red-500">*</span></Label>
            <Input id="bpr-date" type="date" value={form.date} onChange={(e) => patch({ date: e.target.value })} required />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="bpr-name">Batch name</Label>
            <Input
              id="bpr-name" value={batchName}
              onChange={(e) => { setDirty(true); setBatchName(e.target.value) }}
              placeholder="e.g. Morning collection"
              list={priorCustomNames.length ? "bpr-prior-names" : undefined}
            />
            {priorCustomNames.length > 0 && (
              <datalist id="bpr-prior-names">
                {priorCustomNames.map((n) => <option key={n} value={n} />)}
              </datalist>
            )}
          </div>
          <div className="space-y-1.5">
            <Label>Egg grade</Label>
            <Select value={form.eggGrade} onValueChange={(v) => patch({ eggGrade: v })}>
              <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
              <SelectContent>
                {EGG_GRADE_OPTIONS.map((g) => <SelectItem key={g.value} value={g.value}>{g.label}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
        </div>

        {batchSelectionType === "CustomBatch" && (
          <div className="mt-3 rounded-md border border-sky-200 bg-sky-50/60 p-3">
            <Label className="text-xs text-slate-600">Flocks in this batch <span className="text-red-500">*</span></Label>
            <div className="mt-2 grid max-h-44 grid-cols-1 gap-1.5 overflow-y-auto sm:grid-cols-2 lg:grid-cols-3">
              {activeFlocks.length === 0 && <p className="text-xs text-slate-500">No active flocks.</p>}
              {activeFlocks.map((f) => (
                <label key={f.flockId} className="flex items-center gap-2 rounded px-1 py-0.5 text-sm text-slate-700">
                  <Checkbox
                    checked={selectedFlockIds.includes(f.flockId)}
                    onCheckedChange={(c) => toggleFlock(f.flockId, c === true)}
                  />
                  {f.name}
                </label>
              ))}
            </div>
          </div>
        )}

        {isSpecific && specificBatch && (
          <p className="mt-3 flex items-center gap-1.5 text-xs text-slate-500">
            <Info className="h-3.5 w-3.5" />
            Age from this batch&apos;s start date: {ageWeeks}w {ageDays % 7}d ({ageYears}y)
          </p>
        )}
        {!isSpecific && (
          <p className="mt-3 flex items-center gap-1.5 text-xs text-slate-500">
            <Info className="h-3.5 w-3.5" />
            A mixed scope has no single age, so this record saves its age as &ldquo;Mixed&rdquo;.
          </p>
        )}
      </FormSectionCard>

      {/* --------------------------------------------- Egg Production */}
      <FormSectionCard
        title="Egg Production"
        description="Total = crates × 30 + loose eggs. These are BATCH totals, split across flocks at allocation."
        badge={`${totalEggs.toLocaleString()} eggs`}
        accent="amber"
        icon={Egg}
      >
        <div className="space-y-2">
          {pickRows.map((p) => (
            <div key={p.key} className="grid grid-cols-1 items-end gap-3 rounded-lg border border-amber-200 bg-amber-50 px-3 py-2.5 sm:grid-cols-[minmax(8rem,22rem)_8.25rem_8.25rem_8rem]">
              <div className="text-sm font-medium text-slate-700">{p.label}</div>
              <NumField label="Crates" value={p.crates} onChange={p.setC} />
              <NumField label="Loose eggs" value={p.loose} onChange={p.setL} />
              <CalcField label="Total eggs" value={p.total.toLocaleString()} />
            </div>
          ))}
        </div>
        <div className="mt-3 flex flex-wrap items-center gap-x-6 gap-y-1 rounded-md border border-amber-200 bg-amber-100/70 px-3 py-2 text-sm">
          <span className="text-slate-600">Total picked eggs <b className="ml-1 tabular-nums text-slate-900">{totalEggs.toLocaleString()}</b></span>
          <span className="text-slate-600">
            Crates equivalent
            <b className="ml-1 tabular-nums text-slate-900">
              {totalCrates} crate{totalCrates === 1 ? "" : "s"}{totalPieces > 0 ? ` + ${totalPieces} egg${totalPieces === 1 ? "" : "s"}` : ""}
            </b>
          </span>
        </div>
      </FormSectionCard>

      {/* --------------------------------------- Egg Losses/Quality */}
      <FormSectionCard
        title="Egg Losses / Quality"
        description="Eggs that cannot be sold. Net sellable = total picked − these."
        badge={totalLosses > 0 ? `${totalLosses.toLocaleString()} lost` : undefined}
        accent="rose"
        icon={AlertTriangle}
      >
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
          <NumField label="Broken eggs" value={form.brokenEggs} onChange={(v) => patch({ brokenEggs: String(v) })} text />
          <NumField label="Meaty eggs" value={form.meatyEggs} onChange={(v) => patch({ meatyEggs: String(v) })} text />
          <NumField label="Soft eggs" value={form.softEggs} onChange={(v) => patch({ softEggs: String(v) })} text />
          <NumField label="Lost eggs" value={form.lostEggs} onChange={(v) => patch({ lostEggs: String(v) })} text />
          <CalcField label="Net sellable" value={netSellableEggs.toLocaleString()} tone="good" />
        </div>
      </FormSectionCard>

      {/* --------------------------------------------------- Birds */}
      <FormSectionCard
        title="Birds"
        description="Batch-level deaths and remaining birds. Allocation shares deaths across the included flocks."
        accent="emerald"
        icon={Bird}
      >
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <NumField label="Deaths" value={form.deaths} onChange={(v) => patch({ deaths: String(v) })} text />
          <NumField label="Birds left" value={form.birdsLeft} onChange={(v) => patch({ birdsLeft: String(v) })} text />
          <CalcField label="Flocks in scope" value={String(includedFlocksList.length)} />
          <CalcField label="Age" value={isSpecific ? `${ageWeeks}w ${ageDays % 7}d` : "Mixed"} />
        </div>
      </FormSectionCard>

      {/* ---------------------------------------------------- Feed */}
      <FormSectionCard
        title="Feed"
        description="Drawn from inventory. Allocation computes each flock's share from these lines."
        badge={totalFeedCost > 0 ? `Cost ${totalFeedCost.toFixed(2)}` : undefined}
        accent="orange"
        icon={Wheat}
      >
        <div className="grid grid-cols-12 gap-3">
          <FeedLines
            lines={feedLines} rows={feedComputed.rows} feedItems={feedItems}
            stockByItemId={feedComputed.pendingStockByItemId}
            onAdd={addFeedLine} onRemove={removeFeedLine} onChange={changeFeedLine}
          />
        </div>
        <div className="mt-3 grid grid-cols-1 gap-3 border-t pt-3 sm:grid-cols-3">
          <div className="space-y-1.5">
            <Label>Feed type</Label>
            <Select value={form.feedType || "none"} onValueChange={(v) => patch({ feedType: v === "none" ? "" : v })}>
              <SelectTrigger className="w-full"><SelectValue placeholder="Select feed type" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="none">None</SelectItem>
                {FEED_TYPES.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="bpr-feedkg">Feed (kg)</Label>
            <Input
              id="bpr-feedkg" type="number" min="0" step="0.01"
              value={feedFromLines ? String(feedComputed.totalConsumed) : form.feedKg}
              onChange={(e) => patch({ feedKg: e.target.value })}
              readOnly={feedFromLines}
              className={feedFromLines ? "bg-slate-100 text-slate-600" : undefined}
            />
            {feedFromLines && <p className="text-xs text-slate-500">Summed from the feed lines above.</p>}
          </div>
          <CalcField label="Total feed cost" value={totalFeedCost.toFixed(2)} />
        </div>
      </FormSectionCard>

      {/* ---------------------------------------------- Medication */}
      <FormSectionCard
        title="Medication"
        description="Drawn from inventory for the whole batch."
        badge={totalMedicationCost > 0 ? `Cost ${totalMedicationCost.toFixed(2)}` : undefined}
        accent="violet"
        icon={Pill}
      >
        <div className="grid grid-cols-12 gap-3">
          <MedicationLines
            lines={medLines} rows={medComputed.rows} medItems={medItems}
            stockByItemId={medComputed.pendingStockByItemId}
            onAdd={addMedLine} onRemove={removeMedLine} onChange={changeMedLine}
          />
        </div>
        <div className="mt-3 grid grid-cols-1 gap-3 border-t pt-3 sm:grid-cols-3">
          <div className="space-y-1.5 sm:col-span-2">
            <Label htmlFor="bpr-medication">Medication notes</Label>
            <Input id="bpr-medication" value={form.medication} onChange={(e) => patch({ medication: e.target.value })} placeholder="e.g. Newcastle vaccine" />
          </div>
          <CalcField label="Total medication cost" value={totalMedicationCost.toFixed(2)} />
        </div>
      </FormSectionCard>

      {/* --------------------------------------------------- Notes */}
      <FormSectionCard title="Notes" description="Anything worth remembering about this batch." accent="slate" icon={FileText}>
        <Textarea value={form.notes} onChange={(e) => patch({ notes: e.target.value })} rows={3} placeholder="Optional" />
      </FormSectionCard>

      {/* ------------------------------------------------- Summary */}
      <FormSectionCard title="Summary" description="Check these before saving." accent="indigo" icon={Scale}>
        <div className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-3 lg:grid-cols-4">
          <SummaryItem label="Total eggs" value={totalEggs.toLocaleString()} />
          <SummaryItem label="Total crates" value={`${totalCrates} + ${totalPieces}`} />
          <SummaryItem label="Broken" value={brokenEggs.toLocaleString()} />
          <SummaryItem label="Meaty" value={meatyEggs.toLocaleString()} />
          <SummaryItem label="Soft" value={softEggs.toLocaleString()} />
          <SummaryItem label="Lost" value={lostEggs.toLocaleString()} />
          <SummaryItem label="Net sellable" value={netSellableEggs.toLocaleString()} />
          <SummaryItem label="Deaths" value={(parseInt(form.deaths) || 0).toLocaleString()} />
          <SummaryItem label="Flocks in scope" value={String(includedFlocksList.length)} />
          <SummaryItem label="Feed cost" value={totalFeedCost.toFixed(2)} />
          <SummaryItem label="Medication cost" value={totalMedicationCost.toFixed(2)} />
          <SummaryItem label="Total production cost" value={totalCostOfProduction.toFixed(2)} strong />
        </div>
      </FormSectionCard>

      {!hideActions && (
        <div className="flex flex-wrap items-center justify-end gap-2 border-t pt-4">
          {onCancel && <Button type="button" variant="outline" onClick={onCancel} disabled={saving}>Cancel</Button>}
          <Button type="button" variant="outline" disabled={saving} onClick={() => void handleSave("Draft")}>
            {saving ? "Saving…" : "Save as Draft"}
          </Button>
          <Button type="submit" disabled={saving}>
            {saving && <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />}
            {isEdit ? "Save Batch Production" : "Log Batch Production"}
          </Button>
        </div>
      )}
    </form>
  )
}

function SummaryItem({ label, value, strong }: { label: string; value: string; strong?: boolean }) {
  return (
    <div className="flex items-baseline justify-between gap-2 border-b border-dashed border-slate-200 pb-1">
      <span className="text-slate-500">{label}</span>
      <span className={cn("tabular-nums", strong ? "font-semibold text-slate-900" : "text-slate-800")}>{value}</span>
    </div>
  )
}
