"use client"

// =============================================================================
// ProductionRecordForm — the ONE production record form.
//
// Before this component there were three implementations of the same form:
//
//   components/production/production-form.tsx   (the list page's modal)
//   app/production-records/new/page.tsx         (full-page add)
//   app/production-records/[id]/page.tsx        (full-page edit)
//
// They had drifted, and not harmlessly. Two live defects the modal carried that
// the full pages had already fixed:
//
//   1. feedKg ignored the Feed Breakdown lines, so feed entered as inventory
//      lines saved as feedKg: 0.
//   2. It wrote a FeedUsage row itself, matching on flock + date. The database
//      triggers on productionrecords already write that row keyed on
//      sourceproductionrecordid; the page-side write was removed as a bug
//      because it overwrote OTHER records' rows for the same day and created
//      rows with no source link. The modal kept doing it.
//
// The full-page behaviour is canonical here, so both defects are fixed for
// every caller by consolidation alone.
//
// The ONLY difference between modal and page is layout: `displayMode` changes
// the container and whether this component renders its own action row. Every
// calculation, validation rule, payload field and side effect is shared.
// =============================================================================

import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { Label } from "@/components/ui/label"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { Button } from "@/components/ui/button"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { AlertTriangle, Bird, CalendarDays, Egg, FileText, Loader2, Pill, Scale, Wheat } from "lucide-react"
import { cn } from "@/lib/utils"
import { getUserContext } from "@/lib/utils/user-context"
import { getFlockSelectEmptyHint } from "@/lib/utils/flock-utils"
import { useBatchFlockSelect, BATCH_ALL } from "@/hooks/use-batch-flock-select"
import { usePickSettings } from "@/hooks/use-pick-settings"
import {
  createProductionRecord, updateProductionRecord, getProductionRecord, getProductionRecords,
  type ProductionRecordInput, type ProductionRecord,
} from "@/lib/api/production-record"
import { getFeedUsages } from "@/lib/api/feed-usage"
import {
  listPoultryRawMaterialItems, listPoultryRawMaterialPurchases,
  type PoultryRawMaterialItem, type PoultryRawMaterialPurchase,
} from "@/lib/api/poultry-inventory"
import { MedicationLines, computeMedLines, emptyMedLine, buildMedCredit, type MedLineDraft } from "@/components/production/medication-lines"
import { FeedLines, computeFeedLines, emptyFeedLine, buildFeedCredit, type FeedLineDraft } from "@/components/production/feed-lines"
import type { ConsumptionCredit } from "@/lib/utils/raw-material-costing"
import { getBirdsLeftFromRecord, getLatestRecordForFlock } from "@/lib/utils/production-records"
import { EGG_GRADE_OPTIONS, EGG_GRADE_SELECT_VALUE_NONE, eggGradeFromApi, eggGradeToApi } from "@/lib/constants/egg-grade"
import { useToast } from "@/hooks/use-toast"
import { toastFormGuide } from "@/lib/utils/validation-toast"
import { FormSectionCard, CalcField, NumField } from "./production-record-fields"
import {
  EGGS_PER_CRATE, birdsLeft as calcBirdsLeft, cratesEquivalent, effectiveFeedKg as calcEffectiveFeedKg,
  flockAge as calcFlockAge, netSellableEggs as calcNetSellable, pickTotal, resolveAge,
  totalCostOfProduction as calcTotalCost, totalLosses as calcTotalLosses,
} from "@/lib/production/production-record-calc"

// Doc §4a: classify a raw-material item as Feed or Medication by its category.
const isFeedCategory = (c?: string | null) => !!c && /feed/i.test(c)
const isMedicationCategory = (c?: string | null) => !!c && /(medic|vaccin|drug)/i.test(c)

const FEED_TYPES = [
  "Starter Feed", "Grower Feed", "Layer Feed", "Broiler Feed", "Organic Feed", "Custom Mix",
]

/** Everything the modal chrome needs in order to render its header and footer. */
export interface ProductionRecordFormState {
  dirty: boolean
  saving: boolean
  loading: boolean
  flockName: string | null
  date: string
  summary: {
    totalEggs: number
    totalCrates: number
    totalPieces: number
    brokenEggs: number
    meatyEggs: number
    softEggs: number
    lostEggs: number
    totalLosses: number
    netSellableEggs: number
    deaths: number
    birdsLeft: number
    feedCost: number
    medicationCost: number
    totalCost: number
  }
}

export interface ProductionRecordFormProps {
  mode: "create" | "edit"
  displayMode: "modal" | "page"
  /** Edit mode: the record id to load. */
  recordId?: number
  /** Edit mode: a record already in hand, to skip the fetch. */
  record?: ProductionRecord | null
  /** Pre-selects the flock in create mode (e.g. from a flock page). */
  flockId?: number | null
  /** DOM id on the <form>, so a sticky footer button can submit it via form=. */
  formId?: string
  /** Modal chrome renders its own actions; page mode renders its own. */
  hideActions?: boolean
  onSaved?: (recordId: number | null) => void
  onCancel?: () => void
  /** Lifted so the modal header/footer can show context and a live summary. */
  onStateChange?: (state: ProductionRecordFormState) => void
}

export function ProductionRecordForm({
  mode, displayMode, recordId, record: recordProp, flockId: initialFlockId,
  formId = "production-record-form", hideActions = false,
  onSaved, onCancel, onStateChange,
}: ProductionRecordFormProps) {
  const { toast } = useToast()
  const isEdit = mode === "edit"
  const isModal = displayMode === "modal"

  const { labels: pickLabelText, enableFourthPick } = usePickSettings()
  const {
    batchOptions, selectedBatchId, setSelectedBatchId,
    allFlocks, flockOptions: flocksForSelect,
    loading: batchFlockLoading, error: batchFlockError,
  } = useBatchFlockSelect()

  const [saving, setSaving] = useState(false)
  const [loading, setLoading] = useState(isEdit && !recordProp)
  const [error, setError] = useState("")
  const [flocksError, setFlocksError] = useState("")
  const [dirty, setDirty] = useState(false)

  const today = useMemo(() => new Date().toISOString().slice(0, 10), [])

  const [form, setForm] = useState({
    flockId: initialFlockId != null ? String(initialFlockId) : "",
    date: today,
    morning: "", noon: "", evening: "", fourth: "",
    brokenEggs: "", meatyEggs: "", softEggs: "", lostEggs: "",
    feedKg: "", feedType: "",
    mortality: "", numBirds: "",
    notes: "", medication: "",
    eggGrade: EGG_GRADE_SELECT_VALUE_NONE,
  })

  // Mark dirty on any user edit. Hydration uses setForm directly so loading a
  // record for edit does not itself count as a change.
  const patch = useCallback((p: Partial<typeof form>) => {
    setDirty(true)
    setForm((prev) => ({ ...prev, ...p }))
  }, [])

  // ---------------------------------------------------------------- feed/med
  const [feedLines, setFeedLines] = useState<FeedLineDraft[]>(
    isEdit ? [] : [emptyFeedLine(), emptyFeedLine()],
  )
  const addFeedLine = () => { setDirty(true); setFeedLines((d) => [...d, emptyFeedLine()]) }
  const removeFeedLine = (idx: number) => { setDirty(true); setFeedLines((d) => d.filter((_, i) => i !== idx)) }
  const changeFeedLine = (idx: number, p: Partial<FeedLineDraft>) => {
    setDirty(true)
    setFeedLines((d) => d.map((row, i) => (i === idx ? { ...row, ...p } : row)))
  }

  const [medLines, setMedLines] = useState<MedLineDraft[]>(
    isEdit ? [] : [emptyMedLine(), emptyMedLine()],
  )
  const addMedLine = () => { setDirty(true); setMedLines((d) => [...d, emptyMedLine()]) }
  const removeMedLine = (idx: number) => { setDirty(true); setMedLines((d) => d.filter((_, i) => i !== idx)) }
  const changeMedLine = (idx: number, p: Partial<MedLineDraft>) => {
    setDirty(true)
    setMedLines((d) => d.map((row, i) => (i === idx ? { ...row, ...p } : row)))
  }

  // Credit back this record's own prior consumption so editing doesn't falsely
  // block on stock the record itself is holding.
  const [feedCredit, setFeedCredit] = useState<ConsumptionCredit>({})
  const [medCredit, setMedCredit] = useState<ConsumptionCredit>({})

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

  // Client-side preview of the FIFO/LIFO/HIFO batch draw (mirrors the server's
  // spPoultryRawMaterialItem_ConsumeBatches). The server recomputes and persists
  // the authoritative cost at save time — this is just a live preview.
  const feedComputed = useMemo(
    () => computeFeedLines(feedLines, feedItems, purchases, feedCredit),
    [feedLines, feedItems, purchases, feedCredit],
  )
  const medComputed = useMemo(
    () => computeMedLines(medLines, medItems, purchases, medCredit),
    [medLines, medItems, purchases, medCredit],
  )

  const totalFeedCost = feedComputed.totalCost
  const totalMedicationCost = medComputed.totalCost
  const totalCostOfProduction = calcTotalCost(totalFeedCost, totalMedicationCost)

  // The Feed Breakdown is authoritative when it has lines: the same feed must
  // not be entered twice. With lines present the manual box shows their sum and
  // is read-only; with none it behaves as before, which is how most farms still
  // record feed. Every feed raw-material item is measured in kilograms, so
  // summing the line quantities into this field is unit-safe.
  const feedFromLines = feedComputed.totalConsumed > 0
  const effectiveFeedKg = calcEffectiveFeedKg(feedComputed.totalConsumed, form.feedKg)

  // ------------------------------------------------------------ crate entry
  const [picks, setPicks] = useState({
    morningCrates: 0, morningLoose: 0,
    noonCrates: 0, noonLoose: 0,
    eveningCrates: 0, eveningLoose: 0,
    fourthCrates: 0, fourthLoose: 0,
  })
  const setPick = (p: Partial<typeof picks>) => { setDirty(true); setPicks((prev) => ({ ...prev, ...p })) }

  const morningTotal = pickTotal(picks.morningCrates, picks.morningLoose)
  const noonTotal = pickTotal(picks.noonCrates, picks.noonLoose)
  const eveningTotal = pickTotal(picks.eveningCrates, picks.eveningLoose)
  const fourthTotal = pickTotal(picks.fourthCrates, picks.fourthLoose)

  // Crates/loose drive the stored per-pick egg counts. Guarded on change so
  // hydrating an edit (which sets the totals directly) is not overwritten by a
  // zeroed crate breakdown — the saved record stores eggs, not crates.
  const hydrated = useRef(false)
  useEffect(() => {
    if (isEdit && !hydrated.current) return
    setForm((prev) => ({
      ...prev,
      morning: String(morningTotal), noon: String(noonTotal),
      evening: String(eveningTotal), fourth: String(fourthTotal),
    }))
  }, [morningTotal, noonTotal, eveningTotal, fourthTotal, isEdit])

  const total =
    (parseInt(form.morning) || 0) + (parseInt(form.noon) || 0) +
    (parseInt(form.evening) || 0) + (parseInt(form.fourth) || 0)
  const { crates: totalCrates, pieces: totalPieces } = cratesEquivalent(total)

  const brokenEggs = parseInt(form.brokenEggs) || 0
  const meatyEggs = parseInt(form.meatyEggs) || 0
  const softEggs = parseInt(form.softEggs) || 0
  const lostEggs = parseInt(form.lostEggs) || 0
  // Migration 198's rule: an egg counts towards stock on hand only if it is not
  // broken, meaty, soft-shelled or lost. Same definition as the Egg Stock
  // Balance report, so the two cannot disagree.
  const totalLosses = calcTotalLosses({ broken: brokenEggs, meaty: meatyEggs, soft: softEggs, lost: lostEggs })
  const netSellableEggs = calcNetSellable(total, totalLosses)

  // Birds left must always equal numBirds - mortality to keep data consistent.
  const numBirdsNum = parseInt(form.numBirds) || 0
  const mortalityNum = parseInt(form.mortality) || 0
  const birdsLeft = calcBirdsLeft(numBirdsNum, mortalityNum)

  // ------------------------------------------------------------------- age
  const [manualAge, setManualAge] = useState(false)
  const [manualWeeks, setManualWeeks] = useState("")
  const [manualDays, setManualDays] = useState("")
  const [manualYears, setManualYears] = useState("")
  const [previousBirdsLeft, setPreviousBirdsLeft] = useState<number | null>(null)

  const selectedFlock = useMemo(
    () => allFlocks.find((f) => String(f.flockId) === form.flockId),
    [allFlocks, form.flockId],
  )

  const { ageWeeks, ageDays, ageYears } = useMemo(
    () => calcFlockAge(selectedFlock?.startDate, form.date),
    [selectedFlock, form.date],
  )

  useEffect(() => {
    if (batchFlockLoading) return
    if (batchFlockError) { setFlocksError(batchFlockError); return }
    setFlocksError(flocksForSelect.length === 0 ? getFlockSelectEmptyHint("production") : "")
  }, [batchFlockLoading, batchFlockError, flocksForSelect.length])

  // If the user picks a batch and their selected flock isn't in it, clear the
  // flockId so they don't accidentally save against a hidden flock. Applies in
  // edit mode too, now that the flock can be changed there.
  useEffect(() => {
    if (selectedBatchId === BATCH_ALL) return
    if (!form.flockId) return
    if (!flocksForSelect.some((o) => o.value === form.flockId)) {
      setForm((prev) => ({ ...prev, flockId: "" }))
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedBatchId, flocksForSelect, isEdit])

  // "Number of birds" is seeded from the flock's last record.
  //
  // In edit mode this only ever reports the hint: the fill below is guarded on
  // an EMPTY box, and an edit always arrives with the saved figure in it. So
  // changing flock here surfaces that flock's last count for comparison without
  // silently rewriting a number the user already saved.
  useEffect(() => {
    const run = async () => {
      if (!form.flockId || !form.date) { setPreviousBirdsLeft(null); return }
      try {
        const { userId, farmId } = getUserContext()
        if (!userId || !farmId) return
        const res = await getProductionRecords(userId, farmId)
        if (!res.success || !res.data) return
        const flockIdNum = parseInt(form.flockId)
        // Exclude the record being edited, or it reports itself as the flock's
        // previous entry.
        const editingId = recordId ?? loadedRecord?.id
        const pool = editingId != null ? res.data.filter((r: any) => r.id !== editingId) : res.data
        const mostRecent = getLatestRecordForFlock(pool, flockIdNum)
        if (mostRecent) {
          const lastBirdsLeft = getBirdsLeftFromRecord(mostRecent)
          setPreviousBirdsLeft(lastBirdsLeft)
          if (!form.numBirds && lastBirdsLeft > 0) {
            setForm((prev) => ({ ...prev, numBirds: String(lastBirdsLeft) }))
          }
        } else {
          const flock = allFlocks.find((f) => f.flockId === flockIdNum)
          if (flock) {
            setPreviousBirdsLeft(flock.quantity || 0)
            if (!form.numBirds) setForm((prev) => ({ ...prev, numBirds: String(flock.quantity || 0) }))
          } else {
            setPreviousBirdsLeft(null)
          }
        }
      } catch {
        setPreviousBirdsLeft(null)
      }
    }
    void run()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [form.flockId, form.date, allFlocks, isEdit])

  // -------------------------------------------------------------- hydration
  const [loadedRecord, setLoadedRecord] = useState<ProductionRecord | null>(recordProp ?? null)

  const hydrate = useCallback(async (rec: ProductionRecord) => {
    const r0 = rec as any
    const dateStr = new Date(rec.date).toISOString().split("T")[0]
    setLoadedRecord(rec)
    setForm({
      flockId: r0.flockId != null ? String(r0.flockId) : "",
      date: dateStr,
      morning: String(rec.production9AM ?? 0),
      noon: String(rec.production12PM ?? 0),
      evening: String(rec.production4PM ?? 0),
      fourth: String(r0.production4thPick ?? 0),
      brokenEggs: String(r0.brokenEggs ?? 0),
      meatyEggs: r0.meatyEggs == null ? "" : String(r0.meatyEggs),
      softEggs: r0.softEggs == null ? "" : String(r0.softEggs),
      lostEggs: r0.lostEggs == null ? "" : String(r0.lostEggs),
      feedKg: String(rec.feedKg ?? ""),
      feedType: "",
      mortality: String(rec.mortality ?? ""),
      numBirds: String(rec.noOfBirds ?? ""),
      notes: r0.notes ?? "",
      medication: rec.medication ?? "",
      eggGrade: eggGradeFromApi(r0.eggGrade),
    })

    // Crate boxes reflect the stored egg counts so the breakdown is editable.
    setPicks({
      morningCrates: Math.floor((rec.production9AM ?? 0) / EGGS_PER_CRATE),
      morningLoose: (rec.production9AM ?? 0) % EGGS_PER_CRATE,
      noonCrates: Math.floor((rec.production12PM ?? 0) / EGGS_PER_CRATE),
      noonLoose: (rec.production12PM ?? 0) % EGGS_PER_CRATE,
      eveningCrates: Math.floor((rec.production4PM ?? 0) / EGGS_PER_CRATE),
      eveningLoose: (rec.production4PM ?? 0) % EGGS_PER_CRATE,
      fourthCrates: Math.floor((r0.production4thPick ?? 0) / EGGS_PER_CRATE),
      fourthLoose: (r0.production4thPick ?? 0) % EGGS_PER_CRATE,
    })

    // Credit = what this record already consumed, so the edit preview reverses
    // it the way the server will on save. Fall back to the legacy single
    // feed/medication column for records saved before 147/148.
    const feedsForCredit = Array.isArray(r0.feeds) && r0.feeds.length > 0
      ? r0.feeds
      : r0.specificFeedUsedId != null
        ? [{ specificFeedUsedId: r0.specificFeedUsedId, totalFeedConsumed: r0.totalFeedConsumed, feedUnitCost: r0.feedUnitCost }]
        : []
    const medsForCredit = Array.isArray(r0.medications) && r0.medications.length > 0
      ? r0.medications
      : r0.specificMedicationUsedId != null
        ? [{ specificMedicationUsedId: r0.specificMedicationUsedId, totalMedicationConsumed: r0.totalMedicationConsumed, medicationUnitCost: r0.medicationUnitCost }]
        : []
    setFeedCredit(buildFeedCredit(feedsForCredit))
    setMedCredit(buildMedCredit(medsForCredit))

    const feedRows = r0.feeds as { specificFeedUsedId?: number | null; totalFeedConsumed?: number | null }[] | undefined
    if (Array.isArray(feedRows) && feedRows.length > 0) {
      setFeedLines(feedRows.map((f) => ({
        specificFeedUsedId: f.specificFeedUsedId == null ? "" : String(f.specificFeedUsedId),
        totalFeedConsumed: f.totalFeedConsumed == null ? "" : String(f.totalFeedConsumed),
      })))
    } else if (r0.specificFeedUsedId != null) {
      setFeedLines([{
        specificFeedUsedId: String(r0.specificFeedUsedId),
        totalFeedConsumed: r0.totalFeedConsumed == null ? "" : String(r0.totalFeedConsumed),
      }])
    } else {
      setFeedLines([])
    }

    const medRows = r0.medications as { specificMedicationUsedId?: number | null; totalMedicationConsumed?: number | null }[] | undefined
    if (Array.isArray(medRows) && medRows.length > 0) {
      setMedLines(medRows.map((m) => ({
        specificMedicationUsedId: m.specificMedicationUsedId == null ? "" : String(m.specificMedicationUsedId),
        totalMedicationConsumed: m.totalMedicationConsumed == null ? "" : String(m.totalMedicationConsumed),
      })))
    } else if (r0.specificMedicationUsedId != null) {
      setMedLines([{
        specificMedicationUsedId: String(r0.specificMedicationUsedId),
        totalMedicationConsumed: r0.totalMedicationConsumed == null ? "" : String(r0.totalMedicationConsumed),
      }])
    } else {
      setMedLines([])
    }

    // Feed Type isn't stored on the production record — pull it from the
    // matching FeedUsage row (same flock + date) so it can be shown.
    if (r0.flockId) {
      try {
        const { userId, farmId } = getUserContext()
        const fuRes = await getFeedUsages(userId, farmId)
        if (fuRes.success && fuRes.data) {
          const match = (fuRes.data as any[]).find(
            (fu) => fu.flockId === r0.flockId && new Date(fu.usageDate).toISOString().split("T")[0] === dateStr,
          )
          if (match?.feedType) setForm((p) => ({ ...p, feedType: match.feedType }))
        }
      } catch { /* feed usage optional */ }
    }

    hydrated.current = true
    setDirty(false)
  }, [])

  useEffect(() => {
    if (!isEdit) { hydrated.current = true; return }
    // ALWAYS re-fetch by id, even when a record was handed in. The list payload
    // is not guaranteed to carry the feeds / medications line arrays, and
    // hydrating from a record without them would show an empty Feed Breakdown
    // and then SAVE that emptiness over the real lines. The single-record
    // endpoint is the one the full-page edit has always used.
    const id = recordId ?? recordProp?.id
    if (id == null) return
    ;(async () => {
      setLoading(true)
      try {
        const { userId, farmId } = getUserContext()
        const res = await getProductionRecord(id, userId, farmId)
        if (res.success && res.data) await hydrate(res.data)
        else setError(res.message || "Could not load this production record.")
      } catch (e: any) {
        setError(e?.message || "Could not load this production record.")
      } finally {
        setLoading(false)
      }
    })()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isEdit, recordId, recordProp])

  // ------------------------------------------------------------ lift state
  const summary = useMemo(() => ({
    totalEggs: total, totalCrates, totalPieces,
    brokenEggs, meatyEggs, softEggs, lostEggs,
    totalLosses, netSellableEggs,
    deaths: mortalityNum, birdsLeft,
    feedCost: totalFeedCost, medicationCost: totalMedicationCost, totalCost: totalCostOfProduction,
  }), [total, totalCrates, totalPieces, brokenEggs, meatyEggs, softEggs, lostEggs,
       totalLosses, netSellableEggs, mortalityNum, birdsLeft,
       totalFeedCost, totalMedicationCost, totalCostOfProduction])

  // True once the user has moved an existing record to a different flock —
  // drives the warning under the picker.
  const originalFlockId = loadedRecord ? (loadedRecord as any).flockId ?? null : null
  const flockChanged =
    isEdit && originalFlockId != null && form.flockId !== "" &&
    parseInt(form.flockId) !== Number(originalFlockId)

  const flockName = selectedFlock?.name
    ?? (loadedRecord ? (loadedRecord as any).flockName ?? null : null)
    ?? null

  useEffect(() => {
    onStateChange?.({ dirty, saving, loading, flockName, date: form.date, summary })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dirty, saving, loading, flockName, form.date, summary])

  // ---------------------------------------------------------------- submit
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    try {
      setSaving(true)
      setError("")
      const { userId, farmId } = getUserContext()
      if (!userId || !farmId) throw new Error("Missing user/farm context")

      const numBirds = parseInt(form.numBirds) || 0
      const mortality = parseInt(form.mortality) || 0
      // Always numBirds - mortality, to keep noOfBirds and noOfBirdsLeft consistent.
      const calculatedLeft = numBirds - mortality

      if (mortality > numBirds) {
        const msg = `Deaths (${mortality}) cannot be greater than number of birds (${numBirds})`
        setError(msg); toastFormGuide(toast, msg, "Double-check numbers"); setSaving(false); return
      }
      if (calculatedLeft < 0) {
        const msg = "Birds left cannot be negative. Check your deaths and number of birds."
        setError(msg); toastFormGuide(toast, msg, "Double-check numbers"); setSaving(false); return
      }
      if (!form.flockId) {
        const msg = "Choose which flock this production entry is for."
        setError(msg); toastFormGuide(toast, msg); setSaving(false); return
      }
      if (feedComputed.firstShortfall) {
        const s = feedComputed.firstShortfall
        const msg = `Not enough purchased stock tracked for "${s.item?.itemName ?? "this feed"}" to cover ${s.qty} — record a new purchase first.`
        setError(msg); toastFormGuide(toast, msg); setSaving(false); return
      }
      if (medComputed.firstShortfall) {
        const s = medComputed.firstShortfall
        const msg = `Not enough purchased stock tracked for "${s.item?.itemName ?? "this medication"}" to cover ${s.qty} — record a new purchase first.`
        setError(msg); toastFormGuide(toast, msg); setSaving(false); return
      }

      const { ageInDays: resolvedDays, ageInWeeks: resolvedWeeks } = resolveAge(
        manualAge,
        { weeks: manualWeeks, days: manualDays, years: manualYears },
        { ageWeeks, ageDays },
      )

      const input: ProductionRecordInput = {
        farmId, userId, createdBy: userId, updatedBy: userId,
        ageInWeeks: resolvedWeeks,
        ageInDays: resolvedDays,
        date: form.date,
        noOfBirds: numBirds,
        mortality,
        noOfBirdsLeft: calculatedLeft,
        feedKg: effectiveFeedKg,
        medication: form.medication || "None",
        notes: form.notes || null,
        production9AM: parseInt(form.morning) || 0,
        production12PM: parseInt(form.noon) || 0,
        production4PM: parseInt(form.evening) || 0,
        production4thPick: parseInt(form.fourth) || 0,
        brokenEggs: parseInt(form.brokenEggs) || 0,
        meatyEggs: form.meatyEggs === "" ? null : parseInt(form.meatyEggs) || 0,
        softEggs: form.softEggs === "" ? null : parseInt(form.softEggs) || 0,
        lostEggs: form.lostEggs === "" ? null : parseInt(form.lostEggs) || 0,
        totalProduction: total,
        flockId: form.flockId ? parseInt(form.flockId) : null,
        eggGrade: eggGradeToApi(form.eggGrade),
        // Migrations 147/148: the line arrays drive the aggregate columns
        // server-side, so the single-feed / single-medication fields stay null.
        specificFeedUsedId: null, specificFeedUsedName: null, feedUnitCost: null,
        totalFeedConsumed: null, totalFeedCost: null,
        feeds: feedComputed.feeds,
        specificMedicationUsedId: null, specificMedicationUsedName: null, medicationUnitCost: null,
        totalMedicationConsumed: null, totalMedicationCost: null,
        medications: medComputed.medications,
        totalCostOfProduction: Number(totalCostOfProduction.toFixed(2)),
      }

      let savedId: number | null = null
      if (isEdit) {
        const id = recordId ?? loadedRecord?.id
        if (id == null) throw new Error("Missing record id")
        const res = await updateProductionRecord(id, input)
        if (!res.success) throw new Error(res.message || "Failed to save record")
        savedId = id
      } else {
        const res = await createProductionRecord(input)
        if (!res.success) throw new Error(res.message || "Failed to save record")
        savedId = ((res as any).data as any)?.id ?? null
      }

      // FeedUsage is written by the database triggers on productionrecords
      // (trg_productionrecord_insertfeedusage / _update / _delete), keyed on
      // sourceproductionrecordid. Writing it from here as well — matching on
      // flock + date — overwrote other records' rows for the same day and
      // created rows with no source link. The trigger is the writer.

      setDirty(false)
      onSaved?.(savedId)
    } catch (err: any) {
      setError(err?.message || "Failed to save")
    } finally {
      setSaving(false)
    }
  }

  // ---------------------------------------------------------------- render
  if (loading) {
    return (
      <div className="flex items-center justify-center gap-2 py-16 text-slate-500">
        <Loader2 className="h-4 w-4 animate-spin" /> Loading production record…
      </div>
    )
  }

  const pickRows = [
    { key: "morning", label: pickLabelText.first, crates: picks.morningCrates, loose: picks.morningLoose,
      setC: (v: number | string) => setPick({ morningCrates: Number(v) || 0 }), setL: (v: number | string) => setPick({ morningLoose: Number(v) || 0 }), total: morningTotal },
    { key: "noon", label: pickLabelText.second, crates: picks.noonCrates, loose: picks.noonLoose,
      setC: (v: number | string) => setPick({ noonCrates: Number(v) || 0 }), setL: (v: number | string) => setPick({ noonLoose: Number(v) || 0 }), total: noonTotal },
    { key: "evening", label: pickLabelText.third, crates: picks.eveningCrates, loose: picks.eveningLoose,
      setC: (v: number | string) => setPick({ eveningCrates: Number(v) || 0 }), setL: (v: number | string) => setPick({ eveningLoose: Number(v) || 0 }), total: eveningTotal },
    ...(enableFourthPick
      ? [{ key: "fourth", label: pickLabelText.fourth, crates: picks.fourthCrates, loose: picks.fourthLoose,
           setC: (v: number | string) => setPick({ fourthCrates: Number(v) || 0 }), setL: (v: number | string) => setPick({ fourthLoose: Number(v) || 0 }), total: fourthTotal }]
      : []),
  ]

  return (
    <form id={formId} onSubmit={handleSubmit} className={cn("space-y-4", isModal ? "" : "max-w-6xl")}>
      {error && (
        <Alert variant="destructive">
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}
      {flocksError && !error && (
        <Alert>
          <AlertDescription>{flocksError}</AlertDescription>
        </Alert>
      )}

      {/* ------------------------------------------------ Flock & Date */}
      <FormSectionCard title="Flock & Date" description="Which flock this record is for, and the day it covers." accent="sky" icon={CalendarDays}>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <div className="space-y-1.5">
            <Label>Batch</Label>
            <Select value={selectedBatchId} onValueChange={setSelectedBatchId}>
              <SelectTrigger className="w-full"><SelectValue placeholder="All batches" /></SelectTrigger>
              <SelectContent>
                {batchOptions.map((b) => (
                  <SelectItem key={b.value} value={b.value}>{b.label}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label>Flock <span className="text-red-500">*</span></Label>
            <Select
              value={form.flockId}
              onValueChange={(v) => patch({ flockId: v })}
              disabled={batchFlockLoading}
            >
              <SelectTrigger className="w-full"><SelectValue placeholder="Select a flock" /></SelectTrigger>
              <SelectContent>
                {flocksForSelect.map((o) => (
                  <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            {isEdit && flockChanged && (
              <p className="text-xs text-amber-700">
                Moving this record to a different flock. Its eggs, deaths and feed/medication
                usage move with it — check the bird numbers below still make sense.
              </p>
            )}
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="pr-date">Date <span className="text-red-500">*</span></Label>
            <Input id="pr-date" type="date" value={form.date} onChange={(e) => patch({ date: e.target.value })} required />
          </div>
          <div className="space-y-1.5">
            <Label>Egg grade</Label>
            <Select value={form.eggGrade} onValueChange={(v) => patch({ eggGrade: v })}>
              <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
              <SelectContent>
                {EGG_GRADE_OPTIONS.map((g) => (
                  <SelectItem key={g.value} value={g.value}>{g.label}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </div>
      </FormSectionCard>

      {/* --------------------------------------------- Egg Production */}
      <FormSectionCard
        title="Egg Production"
        description="Total = crates × 30 + loose eggs"
        badge={`${total.toLocaleString()} eggs`}
        accent="amber"
        icon={Egg}
      >
        <div className="space-y-2">
          {pickRows.map((p) => (
            <div key={p.key} className="grid grid-cols-1 items-end gap-3 rounded-lg border border-amber-200 bg-amber-50 px-3 py-2.5 sm:grid-cols-[minmax(0,1fr)_5.5rem_5.5rem_7rem]">
              <div className="text-sm font-medium text-slate-700">{p.label}</div>
              <NumField label="Crates" value={p.crates} onChange={p.setC} />
              <NumField label="Loose eggs" value={p.loose} onChange={p.setL} />
              <CalcField label="Total eggs" value={p.total.toLocaleString()} />
            </div>
          ))}
        </div>
        <div className="mt-3 flex flex-wrap items-center gap-x-6 gap-y-1 rounded-md border border-amber-200 bg-amber-100/70 px-3 py-2 text-sm">
          <span className="text-slate-500">Total picked eggs <b className="ml-1 text-slate-900 tabular-nums">{total.toLocaleString()}</b></span>
          <span className="text-slate-500">
            Crates equivalent
            <b className="ml-1 text-slate-900 tabular-nums">
              {totalCrates} crate{totalCrates === 1 ? "" : "s"}{totalPieces > 0 ? ` + ${totalPieces} egg${totalPieces === 1 ? "" : "s"}` : ""}
            </b>
          </span>
        </div>
      </FormSectionCard>

      {/* ------------------------------------------ Egg Losses/Quality */}
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

      {/* --------------------------------------------- Birds & Age */}
      <FormSectionCard
        title="Birds & Age"
        description={previousBirdsLeft != null ? `Last recorded birds left for this flock: ${previousBirdsLeft.toLocaleString()}` : undefined}
        accent="emerald"
        icon={Bird}
      >
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
          <NumField label="Number of birds" value={form.numBirds} onChange={(v) => patch({ numBirds: String(v) })} text />
          <NumField label="Deaths" value={form.mortality} onChange={(v) => patch({ mortality: String(v) })} text />
          <CalcField label="Birds left" value={birdsLeft.toLocaleString()} tone={birdsLeft < 0 ? "bad" : undefined} />
          {manualAge ? (
            <>
              <NumField label="Age (weeks)" value={manualWeeks} onChange={(v) => { setDirty(true); setManualWeeks(String(v)) }} text />
              <NumField label="Age (days)" value={manualDays} onChange={(v) => { setDirty(true); setManualDays(String(v)) }} text />
              <NumField label="Age (years)" value={manualYears} onChange={(v) => { setDirty(true); setManualYears(String(v)) }} text />
            </>
          ) : (
            <>
              <CalcField label="Age (weeks)" value={String(ageWeeks)} />
              <CalcField label="Age (days)" value={String(ageDays)} />
              <CalcField label="Age (years)" value={String(ageYears)} />
            </>
          )}
        </div>
        <label className="mt-3 flex items-center gap-2 text-sm text-slate-600">
          <input
            type="checkbox"
            checked={manualAge}
            onChange={(e) => { setDirty(true); setManualAge(e.target.checked) }}
            className="h-4 w-4 rounded border-slate-300"
          />
          Enter age manually
          <span className="text-xs text-slate-400">
            (otherwise calculated from the flock&apos;s start date)
          </span>
        </label>
      </FormSectionCard>

      {/* ------------------------------------------------------ Feed */}
      <FormSectionCard
        title="Feed"
        description="Draw feed from inventory as lines, or record a plain quantity."
        badge={totalFeedCost > 0 ? `Cost ${totalFeedCost.toFixed(2)}` : undefined}
        accent="orange"
        icon={Wheat}
      >
        <div className="grid grid-cols-12 gap-3">
          <FeedLines
            lines={feedLines}
            rows={feedComputed.rows}
            feedItems={feedItems}
            stockByItemId={feedComputed.pendingStockByItemId}
            onAdd={addFeedLine}
            onRemove={removeFeedLine}
            onChange={changeFeedLine}
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
            <Label htmlFor="pr-feedkg">Feed (kg)</Label>
            <Input
              id="pr-feedkg" type="number" min="0" step="0.01"
              value={feedFromLines ? String(feedComputed.totalConsumed) : form.feedKg}
              onChange={(e) => patch({ feedKg: e.target.value })}
              readOnly={feedFromLines}
              className={feedFromLines ? "bg-slate-100 text-slate-600" : undefined}
            />
            {feedFromLines && (
              <p className="text-xs text-slate-500">Summed from the feed lines above, so it isn&apos;t counted twice.</p>
            )}
          </div>
          <CalcField label="Total feed cost" value={totalFeedCost.toFixed(2)} />
        </div>
      </FormSectionCard>

      {/* ------------------------------------------------ Medication */}
      <FormSectionCard
        title="Medication"
        description="Medication drawn from inventory for this flock on this day."
        badge={totalMedicationCost > 0 ? `Cost ${totalMedicationCost.toFixed(2)}` : undefined}
        accent="violet"
        icon={Pill}
      >
        <div className="grid grid-cols-12 gap-3">
          <MedicationLines
            lines={medLines}
            rows={medComputed.rows}
            medItems={medItems}
            stockByItemId={medComputed.pendingStockByItemId}
            onAdd={addMedLine}
            onRemove={removeMedLine}
            onChange={changeMedLine}
          />
        </div>
        <div className="mt-3 grid grid-cols-1 gap-3 border-t pt-3 sm:grid-cols-3">
          <div className="space-y-1.5 sm:col-span-2">
            <Label htmlFor="pr-medication">Medication notes</Label>
            <Input
              id="pr-medication" value={form.medication}
              onChange={(e) => patch({ medication: e.target.value })}
              placeholder="e.g. Newcastle vaccine"
            />
          </div>
          <CalcField label="Total medication cost" value={totalMedicationCost.toFixed(2)} />
        </div>
      </FormSectionCard>

      {/* ----------------------------------------------------- Notes */}
      <FormSectionCard title="Notes" description="Anything worth remembering about this day." accent="slate" icon={FileText}>
        <Textarea
          value={form.notes}
          onChange={(e) => patch({ notes: e.target.value })}
          rows={3}
          placeholder="Optional"
        />
      </FormSectionCard>

      {/* --------------------------------------------------- Summary */}
      <FormSectionCard title="Summary" description="Check these before saving." accent="indigo" icon={Scale}>
        <div className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-3 lg:grid-cols-4">
          <SummaryItem label="Total eggs" value={total.toLocaleString()} />
          <SummaryItem label="Total crates" value={`${totalCrates} + ${totalPieces}`} />
          <SummaryItem label="Broken" value={brokenEggs.toLocaleString()} />
          <SummaryItem label="Meaty" value={meatyEggs.toLocaleString()} />
          <SummaryItem label="Soft" value={softEggs.toLocaleString()} />
          <SummaryItem label="Lost" value={lostEggs.toLocaleString()} />
          <SummaryItem label="Net sellable" value={netSellableEggs.toLocaleString()} />
          <SummaryItem label="Deaths" value={mortalityNum.toLocaleString()} />
          <SummaryItem label="Birds left" value={birdsLeft.toLocaleString()} />
          <SummaryItem label="Feed cost" value={totalFeedCost.toFixed(2)} />
          <SummaryItem label="Medication cost" value={totalMedicationCost.toFixed(2)} />
          <SummaryItem label="Total production cost" value={totalCostOfProduction.toFixed(2)} strong />
        </div>
      </FormSectionCard>

      {!hideActions && (
        <div className="flex flex-wrap items-center justify-end gap-2 border-t pt-4">
          {onCancel && (
            <Button type="button" variant="outline" onClick={onCancel} disabled={saving}>Cancel</Button>
          )}
          <Button type="submit" disabled={saving}>
            {saving && <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />}
            {isEdit ? "Update Production Record" : "Save Production Record"}
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
