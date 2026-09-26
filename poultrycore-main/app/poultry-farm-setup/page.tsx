"use client"

// Initial Farm Setup — onboarding for a poultry farm that already has birds.
//
// Route name follows the flat `poultry-*` convention the other 35 poultry routes
// use (/poultry-setup, /poultry-stock, …) rather than /poultry/farm-setup; the
// only nested poultry route in the app is /poultry/reports.
//
// This page is an ORCHESTRATOR. It does not replace Flock Purchases, Houses,
// Flock Groups or Production Records — those stay the normal operational pages,
// and after onboarding the farm never comes back here except to look at what its
// opening position was.
//
// The one thing this page exists to get right: an established farm's historical
// losses are recorded as an OPENING POSITION, never as a production record. A
// flock is created holding what is standing in the pen today, so current-bird
// maths is correct from day one and the first real production record subtracts
// only what really died that day.

import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Checkbox } from "@/components/ui/checkbox"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import {
  AlertCircle, ArrowLeft, ArrowRight, Bird, Boxes, Check, CheckCircle2, ClipboardList,
  Home, Loader2, Plus, Sparkles, Trash2, TriangleAlert, Wand2,
} from "lucide-react"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { getUserContext } from "@/lib/utils/user-context"
import { getSuppliers, type Supplier } from "@/lib/api/supplier"
// updatedat is a whole instant, not a business date with a separate entry time.
import { fmtInstant } from "@/lib/utils/company-datetime"
// The same split the Batch Allocation tool proposes, so the two never disagree.
import { BreedSelect } from "@/components/poultry/breed-select"
import { PenCapacityDialog } from "@/components/poultry/pen-capacity-dialog"
import { NewPenDialog } from "@/components/poultry/new-pen-dialog"
import { BatchSizeDialog } from "@/components/poultry/batch-size-dialog"
import { updateHouse } from "@/lib/api/house"
import { getFlockBatch, updateFlockBatch } from "@/lib/api/flock-batch"
// The SAME fields Flock Purchases renders — see components/poultry/batch-purchase-fields.
import {
  BatchIdentityFields, BatchOrderFields, BatchPurchaseDetailFields,
} from "@/components/poultry/batch-purchase-fields"
import {
  completeFarmSetup, deleteFarmSetupDraft, getFarmSetupContext, getFarmSetupDraft,
  getOpeningPositions, saveFarmSetupDraft,
  type FarmSetupDraft, type FarmSetupResult, type FarmSetupStatus, type FarmSetupWizardContext,
  type OpeningPositionSummary,
} from "@/lib/api/poultry-farm-setup"
import {
  batchRowFromExisting, breakdown, defaultFlockName, emptyBatch, emptyFlock, emptyHouse,
  errorsBySection, flocksNeedingReconciliation, generateBatches, historicalReduction,
  balanceBreakdown, batchAllocationViews, batchDraft, batchEditRows, distributePensEvenly,
  fillPensToCapacity, fromBatchDraft,
  houseCapacityNote, houseLoad, houseRowFromExisting, houseRowViews,
  penOptions, seedReconciliation,
  renameForHouse, summarize, summarizeBatchEditRows, summarizeBatchRows, summarizeHouseRows,
  toRequest, validateSetup, visibleBatchEditRows, visibleBatchRows, visibleHouseRows,
  type BatchAllocationStatus, type SetupRowError,
  type BatchRow, type FlockRow, type HouseRow, type SetupContext, type SetupDraft,
} from "@/lib/farm-setup/wizard"
// Prompt 1's bulk house generator, reused rather than rebuilt.
import { generateRows as generateHouseRows } from "@/lib/houses/bulk"

type Screen = "choose" | "wizard" | "newBatch" | "done" | "completed"
type Step = 0 | 1 | 2 | 3 | 4

// Houses come FIRST. The physical buildings are the one thing that is already
// true before any birds are discussed, and knowing them means the batch step can
// talk about where birds will go and the allocation step has somewhere to put
// them. Asking for batches first meant describing cohorts with no idea yet what
// pens existed to hold them.
const STEPS = ["Houses/Pens", "Batches", "Allocate Batches / Create Flocks", "Opening Reconciliation", "Review"]

// What each step is called in the address bar. Stable, readable names rather
// than indexes, so a URL stays meaningful if a step is ever inserted -- and, as
// here, if the steps are reordered: a bookmarked ?step=batches still lands on
// the batches step rather than on whatever now sits at that index.
const STEP_SLUGS = ["houses", "batches", "flocks", "reconcile", "review"] as const

/**
 * The address bar follows the wizard.
 *
 * Without this the whole flow sat on one URL, so the browser Back button left
 * the page entirely -- losing everything typed -- instead of stepping back, and
 * you could not tell from the URL where you were. Written with history.pushState
 * rather than useSearchParams deliberately: this page is statically rendered,
 * and useSearchParams would drag a Suspense boundary in with it for something
 * that is presentation, not data loading.
 */
function urlFor(screen: Screen, step: Step): string {
  const path = typeof window === "undefined" ? "/poultry-farm-setup" : window.location.pathname
  if (screen === "wizard") return `${path}?step=${STEP_SLUGS[step]}`
  if (screen === "choose") return path
  return `${path}?view=${screen}`
}

export default function PoultryFarmSetupPage() {
  const router = useRouter()
  const handleLogout = useLogout()
  const { toast } = useToast()

  const [loading, setLoading] = useState(true)
  const [context, setContext] = useState<FarmSetupWizardContext | null>(null)
  const [opening, setOpening] = useState<OpeningPositionSummary | null>(null)
  const [screen, setScreen] = useState<Screen>("choose")
  const [step, setStep] = useState<Step>(0)
  const [saving, setSaving] = useState(false)
  const [submitted, setSubmitted] = useState(false)
  const [result, setResult] = useState<FarmSetupResult | null>(null)
  const [serverErrors, setServerErrors] = useState<Record<string, Record<number, Record<string, string>>>>({})

  const [draft, setDraft] = useState<SetupDraft>({ mode: "existing", batches: [], houses: [], flocks: [] })

  // Read by the popstate listener, which is registered once and would otherwise
  // close over the draft as it was on mount.
  const draftRef = useRef(draft)
  useEffect(() => { draftRef.current = draft }, [draft])

  /**
   * The unfinished setup, kept on the SERVER (migration 328).
   *
   * It used to live in sessionStorage, which survived a refresh and nothing
   * else: going to another page for reference and coming back lost it, because
   * restoring needed the URL to still carry ?step= and a nav link gives a bare
   * one. Closing the tab lost it outright. Twenty minutes of typing deserves
   * better than a tab.
   *
   * Kept per COMPANY, so it follows the farm rather than the device.
   */
  const [savedDraft, setSavedDraft] = useState<FarmSetupDraft | null>(null)
  const [draftState, setDraftState] = useState<"idle" | "saving" | "saved" | "error">("idle")

  const clearSavedDraft = useCallback(async () => {
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) return
    await deleteFarmSetupDraft(userId, farmId)
    setSavedDraft(null)
    setDraftState("idle")
  }, [])

  /** Move the wizard AND the address bar together. Never one without the other. */
  const navigate = useCallback((nextScreen: Screen, nextStep: Step = 0, replace = false) => {
    setScreen(nextScreen)
    setStep(nextStep)
    if (typeof window === "undefined") return
    const url = urlFor(nextScreen, nextStep)
    if (url === window.location.pathname + window.location.search) return
    window.history[replace ? "replaceState" : "pushState"]({ nextScreen, nextStep }, "", url)
  }, [])

  // Back/forward. A step deep in the wizard is meaningless once the draft is
  // gone (a refresh, or a Back from another page), so those land on the entry
  // screen rather than on an empty step 4 pretending to hold data.
  useEffect(() => {
    const onPop = () => {
      const params = new URLSearchParams(window.location.search)
      const slug = params.get("step")
      const view = params.get("view")
      if (slug) {
        const i = STEP_SLUGS.indexOf(slug as (typeof STEP_SLUGS)[number])
        const d = draftRef.current
        const hasDraft = d.batches.length > 0 || d.houses.length > 0 || d.flocks.length > 0
        if (i < 0 || (i > 0 && !hasDraft)) { setScreen("choose"); setStep(0); return }
        setScreen("wizard")
        setStep(i as Step)
        return
      }
      if (view === "newBatch" || view === "done" || view === "completed") {
        setScreen(view)
        return
      }
      setScreen("choose")
      setStep(0)
    }
    window.addEventListener("popstate", onPop)
    return () => window.removeEventListener("popstate", onPop)
  }, [])

  // Batch generator. Same idea as the pen generator below: a farm with eight
  // cohorts should not type eight near-identical rows.
  const [batchCount, setBatchCount] = useState("2")
  const [batchPrefix, setBatchPrefix] = useState("Batch")
  const [batchCodePrefix, setBatchCodePrefix] = useState("B")
  const [batchStart, setBatchStart] = useState("1")
  const [batchBreed, setBatchBreed] = useState("")
  const [batchBirds, setBatchBirds] = useState("")
  const [batchDate, setBatchDate] = useState("")

  // House generator (prompt 1's fields), kept beside the grid it fills.
  const [penCount, setPenCount] = useState("6")
  const [penPrefix, setPenPrefix] = useState("Pen")
  const [penStart, setPenStart] = useState("1")
  const [penCapacity, setPenCapacity] = useState("")
  // Off by default: a farm returning to allocate a new batch came for the pens it
  // can still use, not for a list of the eighteen that are full.
  const [showAllHouses, setShowAllHouses] = useState(false)
  // Allocation is done ONE BATCH AT A TIME; this is the one in the workspace.
  // Empty until the farm picks one — the step opens on the batch list.
  const [selectedBatchKey, setSelectedBatchKey] = useState("")
  /**
   * Where the allocation step is in its own sequence: pick a batch, pick the
   * pens, then place the birds.
   *
   * Showing all three at once meant arriving at a wall — a batch already chosen
   * for you, a grid of pens, and a table of rows, with nothing saying what to do
   * first. One question at a time is the whole point of a wizard step.
   */
  const [allocPhase, setAllocPhase] = useState<"batch" | "pens" | "allocate">("batch")
  // Debounced: this fires on every keystroke, and a request per character would
  // be both wasteful and out of order. 1.2s is long enough to coalesce typing
  // and short enough that walking away mid-sentence still keeps the sentence.
  useEffect(() => {
    if (screen !== "wizard") return
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) return

    setDraftState("saving")
    const timer = setTimeout(() => {
      void saveFarmSetupDraft({
        farmId,
        draft: JSON.stringify(draft),
        step,
        phase: allocPhase,
        updatedBy: userId,
      }).then((res) => setDraftState(res.success ? "saved" : "error"))
    }, 1200)
    return () => clearTimeout(timer)
  }, [screen, step, draft, allocPhase])

  // Adding a pen from inside the allocation, when there is nowhere left to put
  // the birds. Draft-only -- see NewPenDialog.
  const [newPenOpen, setNewPenOpen] = useState(false)
  // Off by default: a farm returning to place a new batch should not have to
  // scroll past the three it finished eighteen months ago.
  const [showAllBatches, setShowAllBatches] = useState(false)
  // Off by default: existing assignments are context, and loading them into the
  // form is what makes a farm think its history is being recreated.
  const [showExistingFlocks, setShowExistingFlocks] = useState(false)
  // Off by default: the Batches step is for describing NEW stock. What the farm
  // already has is locked, adds nothing to fill in, and is still available to
  // the allocation step regardless.
  const [showExistingBatches, setShowExistingBatches] = useState(false)
  // The pen whose capacity is being corrected from an allocation row, by key.
  const [capacityPenKey, setCapacityPenKey] = useState<string | null>(null)
  // The batch whose bird count is being corrected from the allocation header.
  const [sizeBatchKey, setSizeBatchKey] = useState<string | null>(null)
  // For the batch cards' supplier picker — the same list Flock Purchases shows.
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [penLocation, setPenLocation] = useState("")

  const status: FarmSetupStatus | null = context?.status ?? null

  const load = useCallback(async () => {
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      setLoading(false)
      return
    }
    setLoading(true)
    const [ctxRes, openRes, supRes, draftRes] = await Promise.all([
      getFarmSetupContext(userId, farmId),
      getOpeningPositions(userId, farmId),
      // The batch cards offer the same supplier list Flock Purchases does, so a
      // farm can record who it bought from without leaving setup.
      getSuppliers(userId, farmId),
      getFarmSetupDraft(userId, farmId),
    ])
    if (supRes.success && supRes.data) setSuppliers(supRes.data)
    if (ctxRes.success && ctxRes.data) {
      setContext(ctxRes.data)

      // TWO WAYS BACK IN, and they deserve different answers.
      //
      // A REFRESH still names its step in the URL, so it resumes silently —
      // being asked "do you want to carry on?" after pressing F5 is noise.
      //
      // ARRIVING FRESH (a nav link, a new device, a day later) has a bare URL.
      // That gets an explicit offer instead, because restoring someone into a
      // half-finished form they were not expecting is worse than asking.
      let restored = false
      const saved = draftRes.success && draftRes.data?.hasDraft ? draftRes.data.draft : null
      if (saved) setSavedDraft(saved)

      if (saved && typeof window !== "undefined") {
        const slug = new URLSearchParams(window.location.search).get("step")
        const i = slug ? STEP_SLUGS.indexOf(slug as (typeof STEP_SLUGS)[number]) : -1
        if (i >= 0) {
          try {
            const parsed = JSON.parse(saved.draft) as SetupDraft
            if (Array.isArray(parsed?.batches) && Array.isArray(parsed?.flocks)) {
              setDraft(parsed)
              if (saved.phase) setAllocPhase(saved.phase as "batch" | "pens" | "allocate")
              navigate("wizard", i as Step, true)
              restored = true
            }
          } catch { /* unreadable draft -- fall through and offer it instead */ }
        }
      }
      if (!restored) navigate(ctxRes.data.status?.isComplete ? "completed" : "choose", 0, true)
    } else {
      toast({ title: "Could not load farm setup", description: ctxRes.message || "Please try again.", variant: "destructive" })
    }
    if (openRes.success && openRes.data) setOpening(openRes.data)
    setLoading(false)
  }, [toast, navigate])

  useEffect(() => { void load() }, [load])

  const setupContext: SetupContext = useMemo(() => ({
    existingBatches: (context?.batches ?? []).map((b: any) => ({
      batchId: b.batchId, batchCode: b.batchCode, batchName: b.batchName,
      breed: b.breed, numberOfBirds: b.numberOfBirds, startDate: b.startDate,
    })),
    existingHouses: (context?.houses ?? []).map((h: any) => ({
      houseId: h.houseId, houseName: h.houseName, capacity: h.capacity,
      occupied: h.occupied ?? 0, availableCapacity: h.availableCapacity, activeFlocks: h.activeFlocks ?? 0,
    })),
    existingFlocks: (context?.flocks ?? []).map((f) => ({
      flockId: f.flockId, name: f.name, batchId: f.batchId, houseId: f.houseId,
      houseName: f.houseName, quantity: f.quantity ?? 0, active: f.active ?? true,
    })),
    existingFlockNames: context?.existingFlockNames ?? [],
    allocatedByBatchId: context?.allocatedByBatchId ?? {},
    businessDate: context?.businessDate ? String(context.businessDate).split("T")[0] : new Date().toISOString().slice(0, 10),
  }), [context])

  const { errors, warnings } = useMemo(
    () => validateSetup(draft, setupContext),
    [draft, setupContext],
  )
  const fieldErrors = useMemo(() => errorsBySection(errors), [errors])
  const setupError = errors.find((e) => e.index < 0)
  const totals = useMemo(() => summarize(draft), [draft])
  const needsReconciliation = useMemo(() => flocksNeedingReconciliation(draft.flocks), [draft.flocks])

  // A returning farm's full pens are hidden by default — see visibleHouseRows.
  // The rows stay in the draft either way; only the view changes.
  const houseViews = useMemo(() => houseRowViews(draft, setupContext), [draft, setupContext])
  const visibleHouses = useMemo(
    () => visibleHouseRows(houseViews, showAllHouses),
    [houseViews, showAllHouses],
  )
  const houseSummary = useMemo(() => summarizeHouseRows(houseViews), [houseViews])

  const batchEditViews = useMemo(() => batchEditRows(draft), [draft])
  const visibleBatchEdits = useMemo(
    () => visibleBatchEditRows(batchEditViews, showExistingBatches),
    [batchEditViews, showExistingBatches],
  )
  const batchEditSummary = useMemo(() => summarizeBatchEditRows(batchEditViews), [batchEditViews])

  // Breeds this farm already uses, offered first in every breed picker. Drawn
  // from the batches it has AND the ones being typed now, so a breed entered on
  // the first batch is one click away on the second.
  const knownBreeds = useMemo(() => {
    const all = [
      ...setupContext.existingBatches.map((b) => b.breed),
      ...draft.batches.map((b) => b.breed),
    ]
    return Array.from(new Set(all.map((b) => (b ?? "").trim()).filter(Boolean)))
  }, [setupContext.existingBatches, draft.batches])

  // ---- The allocation workspace ---------------------------------------
  const batchViews = useMemo(() => batchAllocationViews(draft, setupContext), [draft, setupContext])
  const visibleBatches = useMemo(
    // The batch being worked on stays listed even once it is complete.
    () => visibleBatchRows(batchViews, showAllBatches, selectedBatchKey || undefined),
    [batchViews, showAllBatches, selectedBatchKey],
  )
  const batchSummary = useMemo(() => summarizeBatchRows(batchViews), [batchViews])

  // Exactly what was chosen — never a fallback to "whichever is first".
  //
  // It used to fall back, and the strip is ordered by status: typing into
  // Originally Placed moved a batch from "unallocated" to "partial", it slid
  // down the list, and the workspace followed it onto the next batch
  // mid-keystroke. Choosing is now the farm's act, so nothing can move it.
  const activeBatchKey = selectedBatchKey

  /** Pick a batch and go to its pens — or straight to its rows if it has some. */
  const chooseBatch = (key: string) => {
    setSelectedBatchKey(key)
    setAllocPhase(draft.flocks.some((f) => f.batchKey === key) ? "allocate" : "pens")
  }

  const activeBatch = useMemo(
    () => batchViews.find((v) => v.batch.key === activeBatchKey) ?? null,
    [batchViews, activeBatchKey],
  )

  // Filtered but INDEX-PRESERVING: patchFlock, removeFlock and the error maps all
  // address a flock by its position in the draft, not in this view.
  const activeBatchFlocks = useMemo(
    () => draft.flocks
      .map((row, index) => ({ row, index }))
      .filter(({ row }) => row.batchKey === activeBatchKey),
    [draft.flocks, activeBatchKey],
  )

  /** Pens this batch already has a row for. */
  /** Pens this batch may still be put into — full ones are not choices. */
  const allocatablePens = useMemo(
    () => penOptions(houseViews),
    [houseViews],
  )

  const pensInActiveBatch = useMemo(
    () => new Set(activeBatchFlocks.map(({ row }) => row.houseKey).filter(Boolean)),
    [activeBatchFlocks],
  )

  /**
   * Tick a pen in, or out.
   *
   * Ticking creates the flock row for it, named and dated from the batch, so the
   * farm picks WHERE the birds go and the numbers come after. Unticking removes
   * that row — the rows are the selection, so there is nothing else to keep in
   * step with it.
   */
  const togglePen = (houseKey: string, on: boolean) => {
    const b = draft.batches.find((x) => x.key === activeBatchKey)
    const house = draft.houses.find((h) => h.key === houseKey)
    setDraft((d) => {
      if (!on) {
        return { ...d, flocks: d.flocks.filter((f) => !(f.batchKey === activeBatchKey && f.houseKey === houseKey)) }
      }
      if (d.flocks.some((f) => f.batchKey === activeBatchKey && f.houseKey === houseKey)) return d
      return {
        ...d,
        flocks: [...d.flocks, {
          ...emptyFlock(activeBatchKey, houseKey),
          name: defaultFlockName(b?.batchCode ?? "", house?.houseName ?? ""),
          startDate: b?.startDate ?? "",
        }],
      }
    })
  }

  const selectAllPens = (on: boolean) => {
    if (!activeBatchKey) return
    if (!on) {
      setDraft((d) => ({ ...d, flocks: d.flocks.filter((f) => f.batchKey !== activeBatchKey) }))
      return
    }
    const b = draft.batches.find((x) => x.key === activeBatchKey)
    setDraft((d) => {
      const taken = new Set(d.flocks.filter((f) => f.batchKey === activeBatchKey).map((f) => f.houseKey))
      const added = penOptions(houseRowViews(d, setupContext))
        .filter((v) => !taken.has(v.row.key))
        .map((v) => ({
          ...emptyFlock(activeBatchKey, v.row.key),
          name: defaultFlockName(b?.batchCode ?? "", v.row.houseName),
          startDate: b?.startDate ?? "",
        }))
      return { ...d, flocks: [...d.flocks, ...added] }
    })
  }

  /**
   * Add a pen and put this batch in it.
   *
   * Ticking it straight away is the point: someone opens this because they have
   * birds and nowhere to put them, so the pen existing is only half the answer.
   */
  const addPen = (pen: { name: string; capacity: string; location: string }) => {
    const b = draft.batches.find((x) => x.key === activeBatchKey)
    const row = { ...emptyHouse(pen.capacity, pen.location), houseName: pen.name }
    setDraft((d) => ({
      ...d,
      houses: [...d.houses, row],
      flocks: activeBatchKey
        ? [...d.flocks, {
            ...emptyFlock(activeBatchKey, row.key),
            name: defaultFlockName(b?.batchCode ?? "", pen.name),
            startDate: b?.startDate ?? "",
          }]
        : d.flocks,
    }))
    toast({ title: `${pen.name} added`, description: "It will be created when you finish the setup." })
  }

  /** "Pen 5" when the farm's pens are Pen 1..4 — otherwise just a blank. */
  const suggestedPenName = useMemo(() => {
    const numbers = draft.houses
      .map((h) => /^\s*pen\s+(\d+)\s*$/i.exec(h.houseName || "")?.[1])
      .filter(Boolean)
      .map(Number)
    return numbers.length > 0 ? `Pen ${Math.max(...numbers) + 1}` : ""
  }, [draft.houses])

  const autoFill = (mode: "even" | "capacity") => {
    if (!activeBatch || activeBatchFlocks.length === 0) return
    setDraft((d) => (mode === "even"
      ? distributePensEvenly(d, activeBatch.batch.key, activeBatch.available)
      : fillPensToCapacity(d, setupContext, activeBatch.batch.key, activeBatch.available)))
    toast({
      title: mode === "even" ? "Birds spread evenly" : "Pens filled to capacity",
      description: "Every number is editable — change whatever does not match the farm.",
    })
  }

  /** The next batch still needing work, for the "next batch" button. */
  const nextBatchNeedingWork = useMemo(() => {
    const order = visibleBatches.filter((v) => v.batch.key !== activeBatchKey)
    return order.find((v) => v.status === "over")
      ?? order.find((v) => v.remaining > 0)
      ?? null
  }, [visibleBatches, activeBatchKey])

  const activeBatchPosition = useMemo(
    () => visibleBatches.findIndex((v) => v.batch.key === activeBatchKey) + 1,
    [visibleBatches, activeBatchKey],
  )

  // ---- Correcting a pen's capacity from the row that revealed it ------
  const capacityPen = useMemo(() => {
    if (!capacityPenKey) return null
    const index = draft.houses.findIndex((h) => h.key === capacityPenKey)
    if (index < 0) return null
    return { index, row: draft.houses[index], load: houseLoad(capacityPenKey, draft, setupContext) }
  }, [capacityPenKey, draft, setupContext])

  /**
   * Where the new capacity goes depends on whether the pen exists yet.
   *
   * An EXISTING pen is saved to the server now. Its capacity belongs to the pen,
   * not to this draft, and the wizard would otherwise discard it: the setup
   * payload sends an existing house as a reuse-by-id and the server ignores
   * every other field on the row.
   *
   * A pen this setup is about to create has nowhere to be saved to yet, so it is
   * simply edited in the draft and created with the rest.
   */
  const saveCapacity = async (capacity: number) => {
    if (!capacityPen) return
    const { index, row } = capacityPen

    if (row.existingHouseId == null) {
      patchHouse(index, { capacity: String(capacity) })
      toast({ title: "Capacity updated", description: `${row.houseName || "The pen"} will be created holding ${capacity.toLocaleString()}.` })
      return
    }

    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) throw new Error("Your session has expired. Sign in again.")

    const result = await updateHouse(row.existingHouseId, {
      userId, farmId,
      name: row.houseName,
      capacity,
      location: row.location || null,
    })
    if (!result.success) throw new Error(result.message || "That pen could not be updated.")

    // Re-read so houseLoad, the capacity note and the Houses step all see it.
    await load()
    toast({ title: "Capacity updated", description: `${row.houseName} now holds ${capacity.toLocaleString()} birds.` })
  }

  /**
   * The one-click fix a row problem offers, or null when there is not one.
   *
   * Review is the last screen before the farm is created, so being told a pen is
   * too small there and having to walk back three steps to fix it is the worst
   * version of this message. The index on a row error is its position in
   * draft.houses / draft.batches, which is exactly what the dialogs key on.
   */
  const fixFor = (e: SetupRowError): { label: string; onClick: () => void } | null => {
    if (e.section === "houses" && e.field === "capacity") {
      const row = draft.houses[e.index]
      if (!row) return null
      return { label: `Update ${row.houseName || "this pen"}`, onClick: () => setCapacityPenKey(row.key) }
    }
    if (e.section === "batches" && e.field === "numberOfBirds") {
      const row = draft.batches[e.index]
      if (!row) return null
      return { label: `Update ${row.batchCode || row.batchName || "this batch"}`, onClick: () => setSizeBatchKey(row.key) }
    }
    return null
  }

  const sizeBatch = useMemo(
    () => (sizeBatchKey ? batchViews.find((v) => v.batch.key === sizeBatchKey) ?? null : null),
    [sizeBatchKey, batchViews],
  )

  /**
   * Correct what a batch was bought with.
   *
   * A batch being created here is only edited in the draft. An EXISTING one is
   * saved now — and is read back in full first, because the update overwrites
   * the whole row: sending only the bird count would blank the cost, the
   * supplier and the amount paid. The client payload is sparse but the stored
   * function is not, so "just send what changed" quietly destroys the rest.
   */
  const saveBatchSize = async (numberOfBirds: number) => {
    if (!sizeBatch) return
    const { index, batch: row } = sizeBatch

    if (row.existingBatchId == null) {
      patchBatch(index, { numberOfBirds: String(numberOfBirds) })
      toast({ title: "Bird count updated", description: `${row.batchCode || "The batch"} will be created with ${numberOfBirds.toLocaleString()} birds.` })
      return
    }

    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) throw new Error("Your session has expired. Sign in again.")

    const current = await getFlockBatch(row.existingBatchId, userId, farmId)
    if (!current.success || !current.data) {
      throw new Error(current.message || "That batch could not be read.")
    }
    const b = current.data

    const result = await updateFlockBatch(row.existingBatchId, {
      userId, farmId,
      batchName: b.batchName, batchCode: b.batchCode, breed: b.breed,
      startDate: b.startDate, status: b.status,
      costPerChick: b.costPerChick, totalCost: b.totalCost, amountPaid: b.amountPaid,
      supplierType: b.supplierType, supplierId: b.supplierId,
      dollarConversionRate: b.dollarConversionRate ?? null,
      orderPlacementDate: b.orderPlacementDate ?? null,
      estimatedArrivalDate: b.estimatedArrivalDate ?? null,
      notes: b.notes,
      // The one thing being changed.
      numberOfBirds,
    })
    if (!result.success) throw new Error(result.message || "That batch could not be updated.")

    await load()
    toast({ title: "Bird count updated", description: `${b.batchCode} now has ${numberOfBirds.toLocaleString()} birds.` })
  }

  const activeBatchExistingFlocks = useMemo(() => {
    const batchId = activeBatch?.batch.existingBatchId
    if (batchId == null) return []
    return setupContext.existingFlocks.filter((f) => f.batchId === batchId)
  }, [activeBatch, setupContext])

  const errorFor = (section: string, index: number, field: string) => {
    const live = fieldErrors[section]?.[index]?.[field]
    if (live && submitted) return live
    return serverErrors[section]?.[index]?.[field] ?? (live && step === 4 ? live : undefined)
  }

  // ---- Draft editing -------------------------------------------------
  const patchBatch = (i: number, patch: Partial<BatchRow>) =>
    setDraft((d) => ({ ...d, batches: d.batches.map((b, x) => (x === i ? { ...b, ...patch } : b)) }))
  const patchHouse = (i: number, patch: Partial<HouseRow>) =>
    setDraft((d) => ({ ...d, houses: d.houses.map((h, x) => (x === i ? { ...h, ...patch } : h)) }))
  const patchFlock = (i: number, patch: Partial<FlockRow>) =>
    setDraft((d) => ({ ...d, flocks: d.flocks.map((f, x) => (x === i ? { ...f, ...patch } : f)) }))

  const removeBatch = (i: number) =>
    setDraft((d) => {
      const gone = d.batches[i]
      return {
        ...d,
        batches: d.batches.filter((_, x) => x !== i),
        // A flock cannot point at a batch that is no longer in the setup.
        flocks: d.flocks.map((f) => (f.batchKey === gone.key ? { ...f, batchKey: "" } : f)),
      }
    })
  const removeHouse = (i: number) => {
    const gone = draft.houses[i]
    if (!gone) return
    // Taking a pen out takes its allocations with it -- a flock cannot stand in a
    // pen that is no longer part of the setup. That used to happen in silence.
    const losing = draft.flocks.filter((f) => f.houseKey === gone.key).length
    setDraft((d) => ({
      ...d,
      houses: d.houses.filter((_, x) => x !== i),
      flocks: d.flocks.filter((f) => f.houseKey !== gone.key),
    }))
    if (losing > 0) {
      toast({
        title: `${gone.houseName || "Pen"} removed`,
        description: `${losing} flock${losing === 1 ? "" : "s"} allocated to it ${losing === 1 ? "was" : "were"} removed too.`,
        variant: "warning",
      })
    }
  }
  const removeFlock = (i: number) => setDraft((d) => ({ ...d, flocks: d.flocks.filter((_, x) => x !== i) }))

  /** Pick up an unfinished setup exactly where it was left. */
  const resumeDraft = () => {
    if (!savedDraft) return
    try {
      const parsed = JSON.parse(savedDraft.draft) as SetupDraft
      setDraft(parsed)
      if (savedDraft.phase) setAllocPhase(savedDraft.phase as "batch" | "pens" | "allocate")
      setSubmitted(false)
      setServerErrors({})
      navigate("wizard", Math.min(4, Math.max(0, savedDraft.step)) as Step)
    } catch {
      toast({ title: "That draft could not be opened", description: "Start a new setup instead.", variant: "destructive" })
    }
  }

  const startExistingFarm = () => {
    // Pre-load whatever the farm already has so nothing is created twice.
    setDraft({
      mode: "existing",
      batches: setupContext.existingBatches.map(batchRowFromExisting),
      houses: setupContext.existingHouses.map(houseRowFromExisting),
      flocks: [],
    })
    setSubmitted(false)
    setServerErrors({})
    clearSavedDraft()
    navigate("wizard", 0)
  }

  const generateBatchRows = () => {
    const n = parseInt(batchCount, 10)
    if (!Number.isFinite(n) || n < 1) {
      toast({ title: "Nothing to create", description: "Enter how many batches you have.", variant: "warning" })
      return
    }
    const generated = generateBatches({
      count: n, prefix: batchPrefix, codePrefix: batchCodePrefix,
      startNumber: parseInt(batchStart, 10) || 1,
      breed: batchBreed, numberOfBirds: batchBirds, startDate: batchDate,
    })
    setDraft((d) => ({
      ...d,
      // Batches the farm already has are kept and stay at the top -- they are
      // its own records, not something this generator may overwrite. Only
      // previously generated rows are replaced.
      batches: [
        ...d.batches.filter((b) => b.existingBatchId != null),
        ...generated,
      ],
      // A generated batch gets a new key, so any flock pointing at a replaced
      // row would be pointing at nothing. Clear those rather than leave a row
      // that silently fails validation two steps later.
      flocks: d.flocks.map((f) =>
        d.batches.some((b) => b.key === f.batchKey && b.existingBatchId != null)
          ? f
          : { ...f, batchKey: "" }),
    }))
  }

  const generateHouses = () => {
    const n = parseInt(penCount, 10)
    if (!Number.isFinite(n) || n < 1) {
      toast({ title: "Nothing to create", description: "Enter how many pens you need.", variant: "warning" })
      return
    }
    // Prompt 1's generator, so the naming and limits are identical to the
    // Houses page's "Add Multiple Houses/Pens".
    const generated = generateHouseRows({
      count: n, prefix: penPrefix, startNumber: parseInt(penStart, 10) || 1,
      capacity: penCapacity, location: penLocation,
    })
    setDraft((d) => ({
      ...d,
      // Existing houses are kept; only previously generated new ones are replaced.
      houses: [
        ...d.houses.filter((h) => h.existingHouseId != null),
        ...generated.map((g) => ({ key: g.id, houseName: g.name, capacity: g.capacity, location: g.location })),
      ],
    }))
  }

  const goNext = () => {
    setSubmitted(true)
    // Only what this step can fix. A setup-wide complaint about missing flocks
    // is true — and unfixable — while you are still describing pens and batches,
    // so it must not hold the Continue button hostage.
    const blocking = errors.filter((e) => {
      if (e.index >= 0) return e.section === sectionForStep(step)
      if (e.field === "flocks" && step < 2) return false
      return true
    })
    if (blocking.length > 0) {
      toast({
        title: "Check the rows below",
        description: setupError?.message ?? `${blocking.length} row${blocking.length === 1 ? "" : "s"} need attention.`,
        variant: "warning",
      })
      return
    }
    setSubmitted(false)
    goToStep(Math.min(4, step + 1) as Step)
  }

  /**
   * Jump straight to a step.
   *
   * Free movement in both directions: the rail is how someone goes back to fix
   * one number without clicking Back four times, and refusing to move forward
   * would make it decoration. Nothing is committed by moving — Complete Farm
   * Setup still validates everything, and each step shows its own problems.
   *
   * Moving FORWARD runs the leaving-effect of every step it passes over, or a
   * jump from Houses straight to Reconciliation would arrive at a step with no
   * flock rows to reconcile. Both are functional updates, so they still apply
   * in order when React batches them.
   */
  const goToStep = (target: Step) => {
    if (target === step) return
    if (target > step) {
      // Leaving ALLOCATION (step 2) is the first moment both bird counts exist,
      // so the first moment the mortality default can be worked out.
      if (step <= 2 && target > 2) setDraft(seedReconciliation)
    }
    // Arriving at ALLOCATION, resume where this batch left off rather than
    // restarting the sequence: a farm coming back from Review to fix one number
    // should land on the numbers, not on the batch list.
    if (target === 2) {
      const hasRows = selectedBatchKey && draft.flocks.some((f) => f.batchKey === selectedBatchKey)
      setAllocPhase(hasRows ? "allocate" : selectedBatchKey ? "pens" : "batch")
    }
    setSubmitted(false)
    navigate("wizard", target)
  }

  const submit = async () => {
    setSubmitted(true)
    if (errors.length > 0) {
      toast({ title: "Check the rows below", description: setupError?.message ?? "Some rows still need attention.", variant: "warning" })
      return
    }
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      toast({ title: "Session issue", description: "We could not confirm your farm or user. Please sign in again.", variant: "destructive" })
      return
    }

    setSaving(true)
    try {
      const res = await completeFarmSetup(toRequest(draft, setupContext, userId, farmId))
      if (!res.success) {
        const fromServer: Record<string, Record<number, Record<string, string>>> = {}
        for (const e of res.data?.errors ?? []) {
          if (e.index < 0) continue
          fromServer[e.section] ??= {}
          fromServer[e.section][e.index] = { ...(fromServer[e.section][e.index] ?? {}), [e.field]: e.message }
        }
        setServerErrors(fromServer)
        toast({
          title: "Nothing was created",
          description: res.data?.message || res.message || "Your farm was not set up. Nothing was saved.",
          variant: "destructive",
        })
        return
      }
      setResult(res.data ?? null)
      clearSavedDraft()
      navigate("done")
      await load()
    } catch (e: any) {
      toast({ title: "Nothing was created", description: e?.message || "Something went wrong.", variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6 max-w-[1500px] pb-24 lg:pb-6">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 bg-emerald-100 rounded-lg flex items-center justify-center shrink-0">
                <Sparkles className="w-5 h-5 text-emerald-600" />
              </div>
              <div className="min-w-0">
                <h1 className="text-xl sm:text-2xl font-bold text-slate-900">Initial Farm Setup</h1>
                <p className="text-sm text-slate-600">
                  Your opening farm position — what was true when tracking began.
                </p>
              </div>
            </div>

            {loading ? (
              <div className="flex items-center gap-2 text-slate-600 py-16 justify-center">
                <Loader2 className="w-4 h-4 animate-spin" /> Loading…
              </div>
            ) : (
              <>
                {/* ---- Already done ---------------------------------------- */}
                {/* Offered on arrival, never forced. Shown above BOTH entry
                    screens because a farm can have finished onboarding and still
                    be halfway through a later session. */}
                {savedDraft && (screen === "choose" || screen === "completed") && (
                  <Card className="border-2 border-amber-300 bg-amber-50">
                    <CardContent className="flex flex-col items-start gap-4 p-5 sm:flex-row sm:items-center sm:justify-between">
                      <div className="min-w-0">
                        <h3 className="flex items-center gap-2 text-base font-semibold text-slate-900">
                          You have an unfinished setup
                        </h3>
                        <p className="mt-1 text-sm leading-relaxed text-slate-700">
                          {(() => {
                            try {
                              const d = JSON.parse(savedDraft.draft) as SetupDraft
                              const parts = [
                                `${d.batches?.length ?? 0} batch${(d.batches?.length ?? 0) === 1 ? "" : "es"}`,
                                `${d.houses?.length ?? 0} pen${(d.houses?.length ?? 0) === 1 ? "" : "s"}`,
                                `${d.flocks?.length ?? 0} flock${(d.flocks?.length ?? 0) === 1 ? "" : "s"}`,
                              ]
                              return `${parts.join(" · ")} — ${STEPS[Math.min(4, Math.max(0, savedDraft.step))]}`
                            } catch { return "Saved on this farm." }
                          })()}
                        </p>
                        <p className="mt-0.5 text-xs text-slate-600">
                          Last edited {savedDraft.updatedAt ? fmtInstant(savedDraft.updatedAt) : "recently"}
                          {savedDraft.updatedBy ? ` by ${savedDraft.updatedBy}` : ""}.
                        </p>
                      </div>
                      <div className="flex shrink-0 gap-2">
                        <Button variant="outline" onClick={() => void clearSavedDraft()}>Discard</Button>
                        <Button onClick={resumeDraft} className="gap-2 bg-amber-600 hover:bg-amber-700">
                          Resume <ArrowRight className="h-4 w-4" />
                        </Button>
                      </div>
                    </CardContent>
                  </Card>
                )}

                {screen === "completed" && status && (
                  <CompletedPanel status={status} opening={opening} onSetUpMore={startExistingFarm} />
                )}

                {/* ---- Entry choice ---------------------------------------- */}
                {screen === "choose" && (
                  <div className="space-y-4 max-w-4xl">
                    <Card className="border-slate-200 bg-white">
                      <CardContent className="p-5 space-y-2">
                        <h2 className="text-base font-semibold text-slate-900">Set Up Your Farm</h2>
                        <p className="text-sm leading-relaxed text-slate-600">
                          Tell us about the birds currently on your farm. We&apos;ll help create your batches,
                          houses/pens and flocks, and establish your correct starting bird position.
                        </p>
                        {status && !status.looksEmpty && (
                          <p className="text-sm text-amber-700 flex items-start gap-2 pt-1">
                            <TriangleAlert className="w-4 h-4 shrink-0 mt-0.5" />
                            This company already has {status.existingBatches} batch{status.existingBatches === 1 ? "" : "es"},{" "}
                            {status.existingHouses} house{status.existingHouses === 1 ? "" : "s"} and{" "}
                            {status.existingFlocks} flock{status.existingFlocks === 1 ? "" : "s"}. The wizard will offer
                            them for reuse rather than creating them again.
                          </p>
                        )}
                      </CardContent>
                    </Card>

                    <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 items-stretch">
                      <Card className="hover:shadow-md transition-shadow flex flex-col">
                        <CardContent className="p-6 flex flex-col flex-1 gap-3">
                          <div className="flex items-center gap-2">
                            <Bird className="w-5 h-5 text-emerald-600" />
                            <h3 className="font-semibold text-slate-900">I already have birds on my farm</h3>
                          </div>
                          <p className="text-sm text-slate-600">
                            Use this if your farm has been operating before you started using the system. We&apos;ll
                            record what is standing in each pen today and reconcile it against what was originally
                            placed — without pretending those losses happened today.
                          </p>
                          <Button className="bg-blue-600 hover:bg-blue-700 gap-2 mt-auto self-start" onClick={startExistingFarm}>
                            Quick Farm Setup <ArrowRight className="w-4 h-4" />
                          </Button>
                        </CardContent>
                      </Card>

                      <Card className="hover:shadow-md transition-shadow flex flex-col">
                        <CardContent className="p-6 flex flex-col flex-1 gap-3">
                          <div className="flex items-center gap-2">
                            <Plus className="w-5 h-5 text-slate-500" />
                            <h3 className="font-semibold text-slate-900">I&apos;m starting with a new batch of chicks</h3>
                          </div>
                          <p className="text-sm text-slate-600">
                            Use this if these birds are newly purchased and there is no historical farm position to
                            reconstruct. That is just the ordinary workflow — no reconciliation needed.
                          </p>
                          <Button variant="outline" className="gap-2 mt-auto self-start" onClick={() => navigate("newBatch")}>
                            Show me how <ArrowRight className="w-4 h-4" />
                          </Button>
                        </CardContent>
                      </Card>
                    </div>

                    <p className="text-sm text-slate-500">
                      Prefer to do it yourself?{" "}
                      <Link href="/flock-batch" className="text-blue-600 hover:underline">Set Up Manually</Link>{" "}
                      using Flock Purchases, Houses and Flock Groups.
                    </p>
                  </div>
                )}

                {/* ---- New chicks: send them to the normal flow ------------- */}
                {screen === "newBatch" && (
                  <Card className="max-w-3xl">
                    <CardContent className="p-6 space-y-4">
                      <h2 className="text-lg font-semibold text-slate-900">Starting with a new batch</h2>
                      <p className="text-slate-600">
                        Nothing to reconstruct — these birds start their life here. Use the ordinary workflow:
                      </p>
                      <ol className="list-decimal list-inside space-y-1 text-slate-700">
                        <li>Record the purchase in <b>Flock Purchases</b>.</li>
                        <li>Add your houses/pens if you have not already — the batch tool can do it for you.</li>
                        <li>Use <b>Divide Into Flocks</b> to spread the batch across your pens.</li>
                      </ol>
                      <div className="flex flex-wrap gap-2 pt-1">
                        <Button className="bg-blue-600 hover:bg-blue-700" onClick={() => router.push("/flock-batch")}>
                          Go to Flock Purchases
                        </Button>
                        <Button variant="outline" onClick={() => router.push("/houses")}>Go to Houses</Button>
                        <Button variant="ghost" onClick={() => navigate("choose")}>Back</Button>
                      </div>
                    </CardContent>
                  </Card>
                )}

                {/* ---- Success --------------------------------------------- */}
                {screen === "done" && result && (
                  <Card className="max-w-3xl border-emerald-200 bg-emerald-50">
                    <CardContent className="p-6 text-center space-y-2">
                      <CheckCircle2 className="w-10 h-10 text-emerald-600 mx-auto" />
                      <h2 className="text-xl font-semibold text-emerald-900">Your farm is ready.</h2>
                      <p className="text-emerald-800">
                        {result.batchesCreated} batch{result.batchesCreated === 1 ? "" : "es"} ·{" "}
                        {result.housesCreated} house{result.housesCreated === 1 ? "" : "s"}/pens ·{" "}
                        {result.flocksCreated} flock{result.flocksCreated === 1 ? "" : "s"} ·{" "}
                        {result.openingLiveBirds.toLocaleString()} current birds
                      </p>
                      {result.historicalReduction > 0 && (
                        <p className="text-emerald-800 text-sm">
                          {result.historicalReduction.toLocaleString()} birds were recorded as an opening historical
                          reduction — <b>not</b> as today&apos;s mortality.
                        </p>
                      )}
                      <div className="flex flex-wrap gap-2 justify-center pt-2">
                        <Button className="bg-emerald-600 hover:bg-emerald-700" onClick={() => router.push("/production-records")}>
                          Start Recording Production
                        </Button>
                        <Button variant="outline" onClick={() => navigate("completed")}>
                          View Opening Farm Position
                        </Button>
                      </div>
                    </CardContent>
                  </Card>
                )}

                {/* ---- The wizard ------------------------------------------ */}
                {screen === "wizard" && (
                  <>
                    <StepBar step={step} onGo={goToStep} />

                    {/* Step 1 — Houses/Pens */}
                    {step === 0 && (
                      <Section icon={Home} title="Where are your birds housed?"
                        description="Create a run of new pens, then edit any of them. Pens you already have are listed so you can allocate to them — this step never deletes a pen from your farm.">
                        <div className="grid grid-cols-1 md:grid-cols-5 gap-3 p-4 bg-slate-50 border-b border-slate-200">
                          <Field label="Number of Pens"><NumberInput min="1" value={penCount} onChange={(e) => setPenCount(e.target.value)} /></Field>
                          <Field label="Naming Prefix"><Input value={penPrefix} onChange={(e) => setPenPrefix(e.target.value)} placeholder="Pen" /></Field>
                          <Field label="Starting Number"><NumberInput value={penStart} onChange={(e) => setPenStart(e.target.value)} /></Field>
                          <Field label="Default Capacity"><NumberInput min="0" value={penCapacity} onChange={(e) => setPenCapacity(e.target.value)} placeholder="5000" /></Field>
                          <Field label="Default Location"><Input value={penLocation} onChange={(e) => setPenLocation(e.target.value)} placeholder="Layer House A" /></Field>
                          <div className="md:col-span-5">
                            <Button type="button" onClick={generateHouses} className="bg-indigo-600 hover:bg-indigo-700 gap-2">
                              <Wand2 className="w-4 h-4" /> Create New Houses/Pens
                            </Button>
                            <span className="text-xs text-slate-500 ml-3">
                              Replaces the new rows below; houses you already have are kept. Everything stays editable.
                            </span>
                          </div>
                        </div>
                        {/* A returning farm's full pens are hidden, not dropped: they
                            stay in the draft and are still reused by id. */}
                        {houseSummary.occupied > 0 && (
                          <div className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-slate-200 bg-slate-50 px-3 py-2 text-sm">
                            <span className="text-slate-600">
                              {showAllHouses
                                ? `Showing all ${houseSummary.total.toLocaleString()} pens, including ${houseSummary.occupied.toLocaleString()} that already hold birds.`
                                : `${houseSummary.occupied.toLocaleString()} of your ${houseSummary.existing.toLocaleString()} existing pens already ${houseSummary.occupied === 1 ? "holds" : "hold"} birds and ${houseSummary.occupied === 1 ? "is" : "are"} hidden.`}
                            </span>
                            <label className="flex items-center gap-2 text-slate-700 shrink-0">
                              <Checkbox checked={showAllHouses} onCheckedChange={(v) => setShowAllHouses(v === true)} />
                              Show all houses/pens
                            </label>
                          </div>
                        )}
                        {visibleHouses.length > 0 && (
                          <GridHeader columns={[
                            ["col-span-4", "House/Pen Name *"], ["col-span-2", "Capacity"],
                            ["col-span-5", "Location"], ["col-span-1", ""],
                          ]} />
                        )}
                        {draft.houses.length === 0 && (
                            <p className="text-slate-600 text-sm">No houses/pens yet. Create some above, or add one row at a time.</p>
                          )}
                          {draft.houses.length > 0 && visibleHouses.length === 0 && (
                            <p className="text-slate-600 text-sm">
                              None of your pens are empty. Add a new one above, or tick “Show all houses/pens” to see them.
                            </p>
                          )}
                          {visibleHouses.map(({ row: h, index: i, isExisting, load }) => (
                            <div key={h.key} className={`rounded-lg border px-3 py-3 md:grid md:grid-cols-12 md:gap-3 [&_input]:bg-white [&_button[role=combobox]]:bg-white [&_[data-slot=select-trigger]]:bg-white ${rowShell(i, submitted ? fieldErrors.houses?.[i] : undefined, serverErrors.houses?.[i])}`}>
                              <RowHeader
                                label={h.houseName || `House ${i + 1}`}
                                badge={isExisting
                                  ? <Badge variant="secondary" className="h-6 px-1.5 text-[10px]">Existing</Badge>
                                  : <Badge variant="outline" className="h-6 px-1.5 text-[10px] border-blue-300 text-blue-700">New</Badge>}
                                onRemove={isExisting ? undefined : () => removeHouse(i)}
                              />
                              <div className="grid grid-cols-12 gap-3 md:contents">
                              <Field className="col-span-12 md:col-span-4"
                                label="House/Pen Name *" mobileOnlyLabel error={errorFor("houses", i, "houseName")}
                                hint={(() => {
                                  // Only pens that hold something say anything. The
                                  // list is empty pens by default, so labelling each
                                  // of them "Empty" would be noise; these only show
                                  // at all once "show all" is ticked, and then they
                                  // must not read as free.
                                  if (!load || !isExisting || load.activeFlocks === 0) return undefined
                                  return `Holds ${load.occupied.toLocaleString()} in ${load.activeFlocks} flock${load.activeFlocks === 1 ? "" : "s"}`
                                })()}>
                                <Input value={h.houseName} disabled={isExisting}
                                  onChange={(e) => patchHouse(i, { houseName: e.target.value })} placeholder="Pen 1" />
                              </Field>
                              <Field className="col-span-12 sm:col-span-6 md:col-span-2" label="Capacity" mobileOnlyLabel error={errorFor("houses", i, "capacity")}>
                                <NumberInput min="0" value={h.capacity} onChange={(e) => patchHouse(i, { capacity: e.target.value })} placeholder="5000" />
                              </Field>
                              <Field className="col-span-12 md:col-span-5" label="Location" mobileOnlyLabel>
                                <Input value={h.location} onChange={(e) => patchHouse(i, { location: e.target.value })} placeholder="Layer House A" />
                              </Field>
                              </div>
                              <div className="col-span-12 md:col-span-1 hidden md:flex items-end justify-end">
                                {/* Only a pen this setup is CREATING can be taken
                                    out of it. One the farm already has is not this
                                    wizard's to discard — and a bin next to it reads
                                    like it would delete the pen from the farm, which
                                    it never did. Deleting a real pen is the Houses
                                    page's job, and it refuses while birds are in it. */}
                                {!isExisting && (
                                  <Button type="button" variant="ghost" size="icon" onClick={() => removeHouse(i)}
                                    className="h-9 w-9 shrink-0 text-red-600 hover:bg-red-50" aria-label="Remove house">
                                    <Trash2 className="w-4 h-4" />
                                  </Button>
                                )}
                              </div>
                            </div>
                          ))}
                          <Button type="button" variant="outline" size="sm" onClick={() => setDraft((d) => ({ ...d, houses: [emptyHouse(penCapacity, penLocation), ...d.houses] }))}>
                            <Plus className="w-4 h-4 mr-1" /> Add Another Row
                          </Button>
                      </Section>
                    )}

                    {/* Step 2 — Batches */}
                    {step === 1 && (
                      <Section icon={Boxes} title="What batches/groups of birds do you currently have?"
                        description="Create a run of new batches, then edit any of them. Purchase cost and supplier are optional — if you do not know what you paid, leave them blank. Nothing here posts cash or revenue for a historical purchase.">
                        <div className="grid grid-cols-1 md:grid-cols-6 gap-3 p-4 bg-slate-50 border-b border-slate-200 -mx-4 -mt-4 mb-1">
                          <Field label="Number of Batches"><NumberInput min="1" value={batchCount} onChange={(e) => setBatchCount(e.target.value)} /></Field>
                          <Field label="Name Prefix"><Input value={batchPrefix} onChange={(e) => setBatchPrefix(e.target.value)} placeholder="Batch" /></Field>
                          <Field label="Code Prefix"><Input value={batchCodePrefix} onChange={(e) => setBatchCodePrefix(e.target.value)} placeholder="B" /></Field>
                          <Field label="Starting Number"><NumberInput value={batchStart} onChange={(e) => setBatchStart(e.target.value)} /></Field>
                          {/* The same picker the batch rows use. It seeds every
                              generated batch, so leaving it as free text was the
                              one place a mistyped breed could still reach the
                              whole setup in one go. */}
                          <Field label="Default Breed">
                            <BreedSelect value={batchBreed} known={knownBreeds}
                              onChange={setBatchBreed} placeholder="Pick a breed" />
                          </Field>
                          <Field label="Default Birds"><NumberInput min="0" value={batchBirds} onChange={(e) => setBatchBirds(e.target.value)} placeholder="5000" /></Field>
                          <Field className="md:col-span-2" label="Default Arrival Date">
                            <Input type="date" value={batchDate} onChange={(e) => setBatchDate(e.target.value)} />
                          </Field>
                          <div className="md:col-span-6">
                            <Button type="button" onClick={generateBatchRows} className="bg-blue-600 hover:bg-blue-700 gap-2">
                              <Wand2 className="w-4 h-4" /> Create New Batches
                            </Button>
                            <span className="text-xs text-slate-500 ml-3">
                              Replaces the new rows below; batches you already have are kept. Everything stays editable.
                            </span>
                          </div>
                        </div>
                        {/* Encouraged, not demanded. The optional fields are visible
                            by default (not tucked behind a collapsed panel) because
                            the ones a farm never notices are the ones it has to come
                            back and fill in later. */}
                        <div className="rounded-lg border border-blue-200 bg-blue-50 px-3 py-2 text-sm text-blue-900">
                          <span className="font-medium">Complete batch information now.</span>{" "}
                          You can skip the optional purchase details and add them later, but entering them
                          now means your batch history, supplier and cost reporting are complete from the start.
                        </div>

                        {/* A CARD per batch, not a row. Every field the normal Flock
                            Purchases form captures belongs here, and a dozen of them
                            in one horizontal strip is unreadable. */}
                        {batchEditSummary.existing > 0 && (
                          <label className="flex items-center gap-2 text-sm text-slate-700">
                            <Checkbox checked={showExistingBatches}
                              onCheckedChange={(v) => setShowExistingBatches(v === true)} />
                            Show the {batchEditSummary.existing.toLocaleString()} batch
                            {batchEditSummary.existing === 1 ? "" : "es"} you already have
                          </label>
                        )}
                        {visibleBatchEdits.length === 0 && (
                          <p className="text-slate-600 text-sm">
                            No new batches yet. Create some above, or add one at a time.
                          </p>
                        )}
                        {visibleBatchEdits.map(({ row: b, index: i, isExisting: existing }) => {
                            const locked = existing
                            return (
                            <div key={b.key} className={`rounded-lg border px-3 py-3 space-y-3 [&_input]:bg-white [&_button[role=combobox]]:bg-white [&_[data-slot=select-trigger]]:bg-white ${rowShell(i, submitted ? fieldErrors.batches?.[i] : undefined, serverErrors.batches?.[i])}`}>
                              <div className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-100 pb-2">
                                <span className="flex items-center gap-2 text-sm font-semibold text-slate-800">
                                  {b.batchCode || b.batchName || `Batch ${i + 1}`}
                                  {existing
                                    ? <Badge variant="secondary" className="h-6 px-1.5 text-[10px]">Existing</Badge>
                                    : <Badge variant="outline" className="h-6 px-1.5 text-[10px] border-blue-300 text-blue-700">New</Badge>}
                                </span>
                                <Button type="button" variant="ghost" size="sm" onClick={() => removeBatch(i)}
                                  className="h-8 px-2 text-red-600 hover:bg-red-50" aria-label="Remove batch">
                                  <Trash2 className="w-4 h-4" />
                                </Button>
                              </div>

                              {/* Which kind of purchase this is. The single most
                                  consequential field on the card: it decides whether
                                  an expense is posted, what date the birds take in
                                  the stock ledger, and whether every bird must be in
                                  a pen. An existing batch keeps what it was recorded
                                  as — restating that is not this form's business. */}
                              {!existing && (
                                <div className="rounded-lg border border-slate-200 bg-slate-50 p-3 space-y-2">
                                  <SectionLabel>Where did these birds come from?</SectionLabel>
                                  <RadioRow
                                    checked={b.isHistorical}
                                    onSelect={() => patchBatch(i, { isHistorical: true })}
                                    title="I already had these birds"
                                    detail="Bought before you started using PoultryMaster. Nothing is posted to today's expenses or cash — what you still owe is still recorded."
                                  />
                                  <RadioRow
                                    checked={!b.isHistorical}
                                    onSelect={() => patchBatch(i, { isHistorical: false })}
                                    title="I am buying these birds now"
                                    detail="A real purchase happening now. Posts exactly as Flock Purchases would — expense, supplier balance and cash."
                                  />
                                </div>
                              )}

                              <SectionLabel>Batch details</SectionLabel>
                              <BatchIdentityFields
                                className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3"
                                value={batchDraft(b)} disabled={locked}
                                knownBreeds={knownBreeds}
                                onPatch={(patch) => patchBatch(i, fromBatchDraft(patch))}
                                errors={{
                                  batchName: errorFor("batches", i, "batchName"),
                                  batchCode: errorFor("batches", i, "batchCode"),
                                  breed: errorFor("batches", i, "breed"),
                                  numberOfBirds: errorFor("batches", i, "numberOfBirds"),
                                  startDate: errorFor("batches", i, "startDate"),
                                }}
                              />
                              {!existing && b.isHistorical && (
                                <p className="text-xs text-slate-500">
                                  Every one of these birds must end up in a pen — they are standing on your farm today.
                                </p>
                              )}

                              {!existing && (
                                <>
                                  <SectionLabel>Purchase details <span className="font-normal normal-case text-slate-400">— optional</span></SectionLabel>
                                  <BatchPurchaseDetailFields
                                    className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3"
                                    value={batchDraft(b)} suppliers={suppliers}
                                    onPatch={(patch) => patchBatch(i, fromBatchDraft(patch))}
                                    amountPaidHint={b.isHistorical
                                      ? "Paid before you started tracking — posts no expense, but sets what you still owe."
                                      : undefined}
                                  />

                                  <SectionLabel>Order &amp; delivery <span className="font-normal normal-case text-slate-400">— optional</span></SectionLabel>
                                  <BatchOrderFields
                                    className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3"
                                    value={batchDraft(b)}
                                    onPatch={(patch) => patchBatch(i, fromBatchDraft(patch))}
                                  />
                                </>
                              )}
                            </div>
                            )
                          })}
                          <Button type="button" variant="outline" size="sm" onClick={() => setDraft((d) => ({ ...d, batches: [emptyBatch(), ...d.batches] }))}>
                            <Plus className="w-4 h-4 mr-1" /> Add Another Batch
                          </Button>
                      </Section>
                    )}

                    {/* Step 3 — Flocks & current birds */}
                    {step === 2 && (
                      <Section icon={Bird} title="What is in each house/pen today?"
                        description="Originally placed is what went into the pen. Current live birds is what is standing there now — that is the number tracking starts from.">
                        {/* ONE BATCH AT A TIME. Mixing several batches' flocks in
                            one table is what makes the arithmetic impossible to
                            follow: "is this batch fully allocated?" is the question
                            the step exists to answer, and it can only be answered
                            about one batch. */}
                        {/* The same opening move as Divide Into Flocks on the
                            Flock Groups page: one dropdown, one question. The
                            wizard's batch list is that dialog's, so a farmer who
                            has used one already knows this one. */}
                        {allocPhase === "batch" && (
                        <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                          <div className="bg-blue-600 px-4 py-2 text-sm font-semibold text-white">Select a Batch</div>
                          <div className="p-4 space-y-3">
                            {visibleBatches.length === 0 ? (
                              <p className="text-slate-600 text-sm">
                                Every batch is fully allocated. Tick “Show all batches” to look at one anyway.
                              </p>
                            ) : (
                              <>
                                <Label htmlFor="setup-alloc-batch">Batch</Label>
                                <Select value={activeBatchKey || undefined} onValueChange={chooseBatch}>
                                  <SelectTrigger id="setup-alloc-batch">
                                    <SelectValue placeholder="Choose the batch to divide" />
                                  </SelectTrigger>
                                  <SelectContent>
                                    {visibleBatches.map((v) => (
                                      <SelectItem key={v.batch.key} value={v.batch.key}>
                                        {v.batch.batchCode || v.batch.batchName || `Batch ${v.index + 1}`}
                                        {v.batch.batchName && v.batch.batchCode ? ` · ${v.batch.batchName}` : ""}
                                        {" · "}
                                        {v.status === "over"
                                          ? `${(v.previouslyAllocated + v.thisAllocation - v.batchBirds).toLocaleString()} birds too many`
                                          : `${v.remaining.toLocaleString()} of ${v.batchBirds.toLocaleString()} birds left`}
                                      </SelectItem>
                                    ))}
                                  </SelectContent>
                                </Select>
                                <p className="text-xs text-slate-500">
                                  Pick the batch whose birds you are placing. You will choose the pens next.
                                </p>
                              </>
                            )}
                            {batchSummary.hidden > 0 && (
                              <label className="flex items-center gap-2 pt-1 text-sm text-slate-700">
                                <Checkbox checked={showAllBatches}
                                  onCheckedChange={(v) => setShowAllBatches(v === true)} />
                                Show all batches ({batchSummary.hidden} fully allocated)
                              </label>
                            )}
                          </div>
                        </div>
                        )}

                        {activeBatch && allocPhase !== "batch" && (
                          <div className="rounded-lg border border-slate-200 bg-slate-50 p-3">
                            <div className="flex flex-wrap items-center justify-between gap-2">
                              <span className="text-sm font-semibold text-slate-900">
                                {activeBatch.batch.batchCode || activeBatch.batch.batchName}
                                {activeBatch.batch.breed ? ` · ${activeBatch.batch.breed}` : ""}
                              </span>
                              <span className="flex items-center gap-3">
                                {activeBatch.mustBeFullyAllocated && (
                                  <span className="text-xs text-slate-600">
                                    Birds you already had — every one of them needs a pen
                                  </span>
                                )}
                                <Button type="button" variant="ghost" size="sm" className="h-7"
                                  onClick={() => setAllocPhase("batch")}>Change batch</Button>
                              </span>
                            </div>
                            <div className="mt-2 grid grid-cols-2 gap-3 sm:grid-cols-4">
                              <Figure label="Original birds" value={activeBatch.batchBirds} />
                              <Figure label="Already allocated" value={activeBatch.previouslyAllocated} />
                              <Figure label="This allocation" value={activeBatch.thisAllocation} tone="blue" />
                              <Figure
                                label={activeBatch.status === "over" ? "Over by" : "Remaining"}
                                value={activeBatch.status === "over"
                                  ? activeBatch.previouslyAllocated + activeBatch.thisAllocation - activeBatch.batchBirds
                                  : activeBatch.remaining}
                                tone={activeBatch.status === "over" ? "red" : activeBatch.remaining > 0 ? "amber" : "emerald"}
                              />
                            </div>

                            {/* PICK THE PENS, then let the numbers fill themselves.
                                Choosing where the birds go is the farmer's call;
                                working out how many go in each is arithmetic, and
                                arithmetic is what the application is for. */}
                            {allocPhase === "pens" && (
                            <div className="mt-3 rounded-xl border border-slate-200 overflow-hidden">
                              <div className="bg-blue-600 px-4 py-2 text-sm font-semibold text-white flex items-center justify-between">
                                <span>Choose Houses/Pens</span>
                                <span className="font-normal">{activeBatchFlocks.length} selected</span>
                              </div>
                              <div className="p-4 bg-white">
                              <div className="flex flex-wrap items-center gap-2">
                                <Button type="button" variant="outline" size="sm"
                                  onClick={() => selectAllPens(true)}>Select all</Button>
                                <Button type="button" variant="outline" size="sm"
                                  onClick={() => selectAllPens(false)}
                                  disabled={activeBatchFlocks.length === 0}>Clear</Button>
                                <Button type="button" variant="outline" size="sm" className="ml-auto"
                                  onClick={() => setNewPenOpen(true)}>
                                  <Plus className="mr-1 h-4 w-4" /> New pen
                                </Button>
                              </div>

                              <div className="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-4">
                                {allocatablePens.map((v) => {
                                  const on = pensInActiveBatch.has(v.row.key)
                                  const free = v.load?.capacity == null
                                    ? null
                                    : Math.max(0, v.load.capacity - v.load.occupied)
                                  return (
                                    <label key={v.row.key}
                                      className={`flex cursor-pointer items-start gap-2 rounded-lg border px-3 py-2 text-sm transition-colors ${
                                        on ? "border-blue-400 bg-blue-50" : "border-slate-200 bg-white hover:bg-slate-50"
                                      }`}>
                                      <Checkbox className="mt-0.5" checked={on}
                                        onCheckedChange={(c) => togglePen(v.row.key, c === true)} />
                                      <span className="min-w-0">
                                        <span className="block truncate font-medium text-slate-900">
                                          {v.row.houseName || "(unnamed)"}
                                        </span>
                                        <span className="block text-xs text-slate-500 tabular-nums">
                                          {free == null ? "No limit set" : `${free.toLocaleString()} free`}
                                        </span>
                                      </span>
                                    </label>
                                  )
                                })}
                              </div>
                              {allocatablePens.length === 0 && (
                                <div className="mt-3 rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm">
                                  <p className="flex items-start gap-2 text-amber-900">
                                    <TriangleAlert className="mt-0.5 h-4 w-4 shrink-0" />
                                    <span>
                                      {draft.houses.length === 0
                                        ? "You have no houses or pens yet, so there is nowhere to put these birds."
                                        : "Every pen you have is full, so there is nowhere to put these birds."}
                                    </span>
                                  </p>
                                  <div className="mt-2 flex flex-wrap items-center gap-2">
                                    <Button type="button" size="sm" onClick={() => setNewPenOpen(true)}
                                      className="gap-1 bg-amber-600 hover:bg-amber-700">
                                      <Plus className="h-4 w-4" /> Create a pen
                                    </Button>
                                    {draft.houses.length > 0 && (
                                      <span className="text-xs text-amber-800">
                                        — or raise a pen&apos;s capacity from the note on any row once it is placed.
                                      </span>
                                    )}
                                  </div>
                                </div>
                              )}

                              <div className="mt-3 flex flex-wrap items-center gap-2">
                                <Button type="button" onClick={() => setAllocPhase("allocate")}
                                  disabled={activeBatchFlocks.length === 0}
                                  className="gap-1 bg-blue-600 hover:bg-blue-700">
                                  Continue to allocation <ArrowRight className="h-4 w-4" />
                                </Button>
                                <span className="text-xs text-slate-500">
                                  {activeBatchFlocks.length === 0
                                    ? "Tick the pens these birds are in."
                                    : `${activeBatchFlocks.length} pen${activeBatchFlocks.length === 1 ? "" : "s"} chosen.`}
                                </span>
                              </div>
                              </div>
                            </div>
                            )}

                            {/* Says plainly what will happen to the leftovers rather
                                than letting them go unremarked. */}
                            {activeBatch.status === "over" && (
                              <p className="mt-2 flex items-start gap-2 text-sm text-red-700">
                                <TriangleAlert className="mt-0.5 h-4 w-4 shrink-0" />
                                <span>
                                  This allocation is {(activeBatch.previouslyAllocated + activeBatch.thisAllocation - activeBatch.batchBirds).toLocaleString()} birds
                                  more than {activeBatch.batch.batchCode || "the batch"} has. Lower a pen, or raise the batch.{" "}
                                <button type="button"
                                  onClick={() => setSizeBatchKey(activeBatch.batch.key)}
                                  className="font-medium underline underline-offset-2 hover:no-underline">
                                  Update {activeBatch.batch.batchCode || "this batch"}
                                </button>
                                </span>
                              </p>
                            )}
                            {activeBatch.status === "partial" && activeBatch.remaining > 0 && (
                              <p className="mt-2 text-sm text-amber-700">
                                {activeBatch.mustBeFullyAllocated ? (
                                  <>
                                    {activeBatch.remaining.toLocaleString()} birds still need a pen — these are birds you
                                    already had, so all of them must be somewhere. Put them in a pen, or correct the batch.{" "}
                                <button type="button"
                                  onClick={() => setSizeBatchKey(activeBatch.batch.key)}
                                  className="font-medium underline underline-offset-2 hover:no-underline">
                                  Update {activeBatch.batch.batchCode || "this batch"}
                                </button>
                                  </>
                                ) : (
                                  `${activeBatch.remaining.toLocaleString()} birds will stay unallocated — you can place them later.`
                                )}
                              </p>
                            )}
                            {activeBatch.status === "complete" && (
                              <p className="mt-2 flex items-center gap-2 text-sm text-emerald-700">
                                <CheckCircle2 className="h-4 w-4" /> Fully allocated.
                              </p>
                            )}
                          </div>
                        )}

                        {allocPhase === "allocate" && (
                        <>
                        {/* The two fills, and the way back to the pen list. */}
                        <div className="rounded-xl border border-slate-200 overflow-hidden">
                          <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Allocation</div>
                          <div className="flex flex-wrap items-center gap-2 p-3 bg-white">
                          <Button type="button" variant="outline" size="sm"
                            onClick={() => autoFill("capacity")}
                            disabled={activeBatchFlocks.length === 0 || (activeBatch?.available ?? 0) === 0}>
                            <Wand2 className="mr-1 h-4 w-4" /> Fill pens to capacity
                          </Button>
                          <Button type="button" variant="outline" size="sm"
                            onClick={() => autoFill("even")}
                            disabled={activeBatchFlocks.length === 0 || (activeBatch?.available ?? 0) === 0}>
                            <Wand2 className="mr-1 h-4 w-4" /> Spread evenly
                          </Button>
                          <Button type="button" variant="ghost" size="sm"
                            onClick={() => setAllocPhase("pens")}>Change pens</Button>
                          <span className="ml-auto text-xs text-slate-500">
                            A suggestion — every number stays editable.
                          </span>
                          </div>
                        </div>

                        <div className="rounded-lg border border-blue-200 bg-blue-50 px-3 py-2 text-sm text-blue-900">
                          <span className="font-medium">Complete flock information now.</span>{" "}
                          Only the essential fields are required to continue. You can fill in the rest later,
                          but entering it now gives you a complete flock history from the beginning.
                        </div>

                        {/* Existing assignments are CONTEXT, never editable rows.
                            Loading them into the form is what makes a returning farm
                            think its whole history is being recreated. */}
                        {activeBatchExistingFlocks.length > 0 && (
                          <div className="space-y-2">
                            <label className="flex items-center gap-2 text-sm text-slate-700">
                              <Checkbox checked={showExistingFlocks} onCheckedChange={(v) => setShowExistingFlocks(v === true)} />
                              Show existing flock assignments ({activeBatchExistingFlocks.length})
                            </label>
                            {showExistingFlocks && (
                              <div className="rounded-lg border border-slate-200 bg-slate-50 divide-y divide-slate-200">
                                {activeBatchExistingFlocks.map((f) => (
                                  <div key={f.flockId} className="flex flex-wrap items-center justify-between gap-2 px-3 py-2 text-sm">
                                    <span className="flex items-center gap-2 font-medium text-slate-800">
                                      {f.name}
                                      <Badge variant="secondary" className="h-5 px-1.5 text-[10px]">Existing</Badge>
                                    </span>
                                    <span className="text-slate-600 tabular-nums">
                                      {f.houseName ?? "No pen"} · {f.quantity.toLocaleString()} birds
                                    </span>
                                  </div>
                                ))}
                                <p className="px-3 py-2 text-xs text-slate-500">
                                  Shown for context. Change these on the{" "}
                                  <Link href="/flocks" className="text-blue-600 hover:underline">Flock Groups</Link> page.
                                </p>
                              </div>
                            )}
                          </div>
                        )}

                        <GridHeader columns={[
                          ["col-span-3", "House/Pen *"], ["col-span-3", "Flock Name *"],
                          ["col-span-2", "Originally Placed *"], ["col-span-2", "Current Live Birds *"], ["col-span-2", ""],
                        ]} />
                        {activeBatchFlocks.map(({ row: f, index: i }) => {
                            const reduction = historicalReduction(f)
                            // The pen is the first field on the row, so what it is
                            // carrying is known before the bird counts are typed --
                            // which is why it is said here rather than four clicks
                            // later on Review. Context and a note, never a block:
                            // capacity plans the NEXT placement, it does not get a
                            // vote on what is already standing in the pen.
                            const penLoad = f.houseKey ? houseLoad(f.houseKey, draft, setupContext) : null
                            const penNoteText = penLoad ? houseCapacityNote(penLoad) : null
                            const penHint = (() => {
                              if (!penLoad) return undefined
                              const parts: string[] = []
                              if (penLoad.activeFlocks > 0) {
                                parts.push(`Already holds ${penLoad.occupied.toLocaleString()} in ${penLoad.activeFlocks} flock${penLoad.activeFlocks === 1 ? "" : "s"} — this adds another`)
                              }
                              // Suppressed once the note is showing; it says the same
                              // numbers and says them louder.
                              if (penLoad.capacity != null && !penNoteText) {
                                parts.push(`${Math.max(0, penLoad.capacity - penLoad.total).toLocaleString()} of ${penLoad.capacity.toLocaleString()} still free`)
                              }
                              return parts.length > 0 ? parts.join(" · ") : undefined
                            })()
                            // The note is the moment the farm learns the capacity is
                            // wrong. Making them leave the row, find the pen, fix it
                            // and come back is how a stale number stays stale, so the
                            // fix is offered right here.
                            const penNote = penNoteText ? (
                              <>
                                {penNoteText}{" "}
                                <button type="button"
                                  onClick={() => setCapacityPenKey(f.houseKey)}
                                  className="font-medium underline underline-offset-2 hover:no-underline">
                                  Update {penLoad?.label || "this pen"}
                                </button>
                              </>
                            ) : null
                            return (
                              <div key={f.key} className={`rounded-lg border px-3 py-3 md:grid md:grid-cols-12 md:gap-3 [&_input]:bg-white [&_button[role=combobox]]:bg-white [&_[data-slot=select-trigger]]:bg-white ${rowShell(i, submitted ? fieldErrors.flocks?.[i] : undefined, serverErrors.flocks?.[i])}`}>
                                <RowHeader
                                  label={f.name || `Flock ${i + 1}`}
                                  badge={reduction > 0
                                    ? <Badge variant="outline" className="h-6 px-1.5 text-[10px] border-amber-300 text-amber-700">−{reduction.toLocaleString()}</Badge>
                                    : <Badge variant="outline" className="h-6 px-1.5 text-[10px] border-slate-200 text-slate-500">Balanced</Badge>}
                                  onRemove={() => removeFlock(i)}
                                />
                                <div className="grid grid-cols-12 gap-3 md:contents">
                                <Field className="col-span-12 md:col-span-3" label="House/Pen *" mobileOnlyLabel
                                  error={errorFor("flocks", i, "houseKey")}
                                  hint={penHint}
                                  note={penNote}>
                                  <Select
                                    value={f.houseKey}
                                    onValueChange={(v) => {
                                      const b = draft.batches.find((x) => x.key === f.batchKey)
                                      const from = draft.houses.find((h) => h.key === f.houseKey)
                                      const to = draft.houses.find((h) => h.key === v)
                                      patchFlock(i, {
                                        houseKey: v,
                                        // Follows the pen while the name is still the
                                        // one we generated; leaves a name the farm
                                        // wrote alone. See renameForHouse.
                                        name: renameForHouse(
                                          f.name, b?.batchCode ?? "",
                                          from?.houseName ?? "", to?.houseName ?? "",
                                        ),
                                        startDate: f.startDate || (b?.startDate ?? ""),
                                      })
                                    }}
                                  >
                                    <SelectTrigger><SelectValue placeholder="House" /></SelectTrigger>
                                    <SelectContent>
                                      {penOptions(houseViews, f.houseKey).map((v) => (
                                        <SelectItem key={v.row.key} value={v.row.key}>{v.row.houseName || "(unnamed)"}</SelectItem>
                                      ))}
                                    </SelectContent>
                                  </Select>
                                </Field>
                                <Field className="col-span-12 md:col-span-3"
                                  label="Flock Name *" mobileOnlyLabel error={errorFor("flocks", i, "name")}>
                                  <Input value={f.name} onChange={(e) => patchFlock(i, { name: e.target.value })} placeholder="B1 - Pen 1" />
                                </Field>
                                <Field className="col-span-12 sm:col-span-6 md:col-span-2" label="Originally Placed *" mobileOnlyLabel error={errorFor("flocks", i, "originallyPlaced")}>
                                  <NumberInput min="0" value={f.originallyPlaced} onChange={(e) => patchFlock(i, { originallyPlaced: e.target.value })} placeholder="1000" />
                                </Field>
                                <Field className="col-span-12 sm:col-span-6 md:col-span-2" label="Current Live Birds *" mobileOnlyLabel error={errorFor("flocks", i, "currentLiveBirds")}>
                                  <NumberInput min="0" value={f.currentLiveBirds} onChange={(e) => patchFlock(i, { currentLiveBirds: e.target.value })} placeholder="919" />
                                </Field>
                                </div>
                                <div className="col-span-12 md:col-span-2 hidden md:flex items-end justify-end">
                                  <Button type="button" variant="ghost" size="icon" onClick={() => removeFlock(i)}
                                    className="h-9 w-9 shrink-0 text-red-600 hover:bg-red-50" aria-label="Remove flock">
                                    <Trash2 className="w-4 h-4" />
                                  </Button>
                                </div>

                                {/* Everything else the ordinary Add Flock form asks
                                    for. Shown rather than hidden, so a farm that
                                    knows these does not have to come back and edit
                                    the flock afterwards. */}
                                <div className="col-span-12 grid grid-cols-12 gap-3 border-t border-slate-100 pt-2">
                                  <Field className="col-span-12 md:col-span-3" label="Breed"
                                    hint="Blank takes the batch's breed">
                                    <BreedSelect value={f.breed} known={knownBreeds}
                                      onChange={(breed) => patchFlock(i, { breed })}
                                      placeholder={draft.batches.find((x) => x.key === f.batchKey)?.breed || "Same as the batch"} />
                                  </Field>
                                  <Field className="col-span-12 md:col-span-6" label="Notes">
                                    <Input value={f.notes ?? ""} onChange={(e) => patchFlock(i, { notes: e.target.value })}
                                      placeholder="Anything worth remembering about this flock" />
                                  </Field>
                                  {/* Only meaningful for birds being bought now: an
                                      established farm's birds are standing in the pen
                                      by definition. */}
                                  {!(draft.batches.find((x) => x.key === f.batchKey)?.isHistorical ?? true) && (
                                    <Field className="col-span-12 md:col-span-3" label="Have the birds arrived?">
                                      <label className="flex h-9 items-center gap-2 text-sm text-slate-700">
                                        <Checkbox checked={f.hasArrived}
                                          onCheckedChange={(v) => patchFlock(i, { hasArrived: v === true })} />
                                        Yes, they are in the pen
                                      </label>
                                    </Field>
                                  )}
                                </div>

                                {/* Age or date, per flock. */}
                                <div className="col-span-12 grid grid-cols-12 gap-3 border-t border-slate-100 pt-2">
                                  <Field className="col-span-12 md:col-span-3" label="How do you know its age?">
                                    <Select value={f.ageMode} onValueChange={(v) => patchFlock(i, { ageMode: v as "date" | "age" })}>
                                      <SelectTrigger><SelectValue /></SelectTrigger>
                                      <SelectContent>
                                        <SelectItem value="date">I know the placement/start date</SelectItem>
                                        <SelectItem value="age">I know the current age</SelectItem>
                                      </SelectContent>
                                    </Select>
                                  </Field>
                                  {f.ageMode === "date" ? (
                                    <Field className="col-span-12 md:col-span-3" label="Placement date" error={errorFor("flocks", i, "startDate")}>
                                      <Input type="date" value={f.startDate} onChange={(e) => patchFlock(i, { startDate: e.target.value })} />
                                    </Field>
                                  ) : (
                                    <Field className="col-span-12 md:col-span-3" label="Current age (weeks)" error={errorFor("flocks", i, "currentAgeInWeeks")}
                                      hint="We'll work back from today and record the date as estimated.">
                                      <NumberInput min="0" value={f.currentAgeInWeeks} onChange={(e) => patchFlock(i, { currentAgeInWeeks: e.target.value })} placeholder="70" />
                                    </Field>
                                  )}
                                </div>
                              </div>
                            )
                          })}
                          <Button type="button" variant="outline" size="sm"
                            onClick={() => {
                              // Straight to the dialog when there is nothing to
                              // pick — sending someone to an empty list to read
                              // that it is empty is a wasted click.
                              if (allocatablePens.length === 0) setNewPenOpen(true)
                              else setAllocPhase("pens")
                            }}
                            disabled={!activeBatchKey}>
                            <Plus className="w-4 h-4 mr-1" />
                            {allocatablePens.length === 0 ? "Create a pen for this batch" : "Add a pen to this batch"}
                          </Button>

                          {/* Moving between batches is selection, not saving: the
                              whole setup is posted once, at the end, in one
                              transaction. Saying "save" here would promise
                              something that has not happened. */}
                          {nextBatchNeedingWork && (
                            <div className="flex justify-end pt-1">
                              <Button type="button" variant="outline"
                                onClick={() => chooseBatch(nextBatchNeedingWork.batch.key)}>
                                Next batch: {nextBatchNeedingWork.batch.batchCode || nextBatchNeedingWork.batch.batchName}
                                <ArrowRight className="ml-1 h-4 w-4" />
                              </Button>
                            </div>
                          )}
                        </>
                        )}
                      </Section>
                    )}

                    {/* Step 4 — Opening reconciliation */}
                    {step === 3 && (
                      <Section icon={ClipboardList} title="What happened to the missing birds?"
                        description="We have assumed the missing birds died — change any flock where that is wrong. These losses happened before tracking began, so they are recorded as an opening position and never appear as today’s deaths.">
                        <div className="p-4 space-y-4">
                          {needsReconciliation.length === 0 ? (
                            <div className="text-center py-8">
                              <CheckCircle2 className="w-10 h-10 text-emerald-600 mx-auto mb-2" />
                              <p className="text-slate-700">Every flock balances. No reconciliation needed.</p>
                            </div>
                          ) : (
                            <>
                              {draft.flocks.map((f, i) => {
                                const b = breakdown(f)
                                if (b.difference === 0) return null
                                return (
                                  <div key={f.key} className={`rounded-lg border p-4 space-y-3 [&_input]:bg-white [&_button[role=combobox]]:bg-white [&_[data-slot=select-trigger]]:bg-white ${
                                    i % 2 === 0
                                      ? "bg-blue-200 border-blue-300 border-l-4 border-l-blue-600"
                                      : "bg-white border-slate-200 border-l-4 border-l-slate-300"
                                  }`}>
                                    <div className="flex flex-wrap items-center justify-between gap-3">
                                      <div className="min-w-0">
                                        <p className="font-medium text-slate-900">{f.name || "(unnamed flock)"}</p>
                                        <p className="text-sm text-slate-600">
                                          {Number(f.originallyPlaced || 0).toLocaleString()} placed →{" "}
                                          {Number(f.currentLiveBirds || 0).toLocaleString()} standing today
                                        </p>
                                      </div>
                                      <div className="shrink-0 rounded-xl border border-slate-200 bg-white px-3 py-1.5 text-right shadow-sm">
                                        <p className="text-xs font-medium uppercase tracking-wider text-slate-500">Remaining to account</p>
                                        <p className="text-lg font-bold tabular-nums text-amber-600">{b.difference.toLocaleString()}</p>
                                      </div>
                                    </div>

                                    <label className="flex items-center gap-2 text-sm text-slate-700">
                                      <Checkbox
                                        checked={!f.historyKnown}
                                        onCheckedChange={(v) => patchFlock(i, {
                                          historyKnown: v !== true,
                                          reconciliationTouched: true,
                                          // Saying "I don't know" must actually clear
                                          // the pre-filled figures, or a number the
                                          // farm has just disowned would still be
                                          // sitting in the row.
                                          ...(v === true
                                            ? { historicalMortality: "", historicalSold: "", historicalCulled: "", historicalTransferred: "" }
                                            : {}),
                                        })}
                                      />
                                      I don&apos;t know the historical breakdown
                                    </label>

                                    {f.historyKnown ? (
                                      <>
                                        <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
                                          <Field label="Known mortality" hint="Takes whatever the others do not"><NumberInput min="0" value={f.historicalMortality} onChange={(e) => patchFlock(i, balanceBreakdown(f, { historicalMortality: e.target.value }))} /></Field>
                                          <Field label="Sold"><NumberInput min="0" value={f.historicalSold} onChange={(e) => patchFlock(i, balanceBreakdown(f, { historicalSold: e.target.value }))} /></Field>
                                          <Field label="Culled"><NumberInput min="0" value={f.historicalCulled} onChange={(e) => patchFlock(i, balanceBreakdown(f, { historicalCulled: e.target.value }))} /></Field>
                                          <Field label="Transferred out"><NumberInput min="0" value={f.historicalTransferred} onChange={(e) => patchFlock(i, balanceBreakdown(f, { historicalTransferred: e.target.value }))} /></Field>
                                          <Field label="Other / unknown">
                                            <div className="h-10 flex items-center px-3 rounded-md border border-slate-200 bg-slate-100 text-slate-700 tabular-nums">
                                              {b.other.toLocaleString()}
                                            </div>
                                          </Field>
                                        </div>
                                        <p className={`text-xs ${b.overStated ? "text-red-600" : "text-slate-500"}`}>
                                          {b.overStated
                                            ? `The breakdown adds up to ${b.stated.toLocaleString()} but only ${b.difference.toLocaleString()} birds remain to account for.`
                                            : `${b.stated.toLocaleString()} of ${b.difference.toLocaleString()} accounted for; the remaining ${b.other.toLocaleString()} is recorded as unknown, not as mortality.`}
                                        </p>
                                      </>
                                    ) : (
                                      <p className="text-xs text-slate-500">
                                        All {b.difference.toLocaleString()} will be recorded as an{" "}
                                        <b>opening bird adjustment</b> — not as mortality, and not as a sale.
                                      </p>
                                    )}
                                  </div>
                                )
                              })}
                            </>
                          )}
                        </div>
                      </Section>
                    )}

                    {/* Step 5 — Review */}
                    {step === 4 && (
                      <Section icon={CheckCircle2} title="Farm setup summary"
                        description="Nothing has been saved yet. Check the numbers, then create your farm.">
                        <div className="p-4 space-y-4">
                          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                            <Stat label="Batches" value={totals.batchCount} tone="blue" />
                            <Stat label="Original batch birds" value={totals.batchBirds} tone="blue" />
                            <Stat label="Houses/pens" value={totals.houseCount} tone="violet" />
                            <Stat label="Current flocks" value={totals.flockCount} tone="violet" />
                            <Stat label="Birds originally placed" value={totals.originallyPlaced} />
                            <Stat label="Current live birds" value={totals.openingLiveBirds} tone="emerald" />
                            <Stat label="Historical reduction" value={totals.historicalReduction} tone="amber" />
                            <Stat label="Flocks with unknown history" value={totals.flocksWithUnknownHistory} tone="rose" />
                          </div>

                          <div className="rounded-lg border border-slate-200 bg-white p-4">
                            <p className="font-medium text-slate-900 mb-2">Historical reduction, broken down</p>
                            <div className="grid grid-cols-2 md:grid-cols-5 gap-3 text-sm">
                              <Stat small label="Known mortality" value={totals.historicalMortality} tone="rose" />
                              <Stat small label="Sold" value={totals.historicalSold} tone="blue" />
                              <Stat small label="Culled" value={totals.historicalCulled} tone="violet" />
                              <Stat small label="Transferred" value={totals.historicalTransferred} tone="slate" />
                              <Stat small label="Other / unknown" value={totals.otherAdjustment} tone="amber" />
                            </div>
                            <p className="text-xs text-slate-500 mt-2">
                              None of this is a production record. It establishes what was true on{" "}
                              {setupContext.businessDate} — your company&apos;s business date — and nothing more.
                            </p>
                          </div>

                          {/* WHAT WILL ACTUALLY BE CREATED, separated from what is
                              only being reused. A farm reopening the tool needs to
                              see at a glance that its existing records are not about
                              to be duplicated. */}
                          <div className="grid gap-3 sm:grid-cols-2">
                            <div className="rounded-lg border border-slate-200 bg-white p-3">
                              <p className="mb-1 font-medium text-slate-900">Houses/pens</p>
                              <p className="text-sm text-slate-600">
                                {draft.houses.filter((h) => h.existingHouseId != null).length.toLocaleString()} existing, reused ·{" "}
                                <span className="font-medium text-blue-700">
                                  {draft.houses.filter((h) => h.existingHouseId == null).length.toLocaleString()} to create
                                </span>
                              </p>
                            </div>
                            <div className="rounded-lg border border-slate-200 bg-white p-3">
                              <p className="mb-1 font-medium text-slate-900">Batches</p>
                              <p className="text-sm text-slate-600">
                                {draft.batches.filter((b) => b.existingBatchId != null).length.toLocaleString()} existing, reused ·{" "}
                                <span className="font-medium text-blue-700">
                                  {draft.batches.filter((b) => b.existingBatchId == null).length.toLocaleString()} to create
                                </span>
                              </p>
                            </div>
                          </div>

                          {/* Grouped by batch, because that is the unit the
                              allocation step works in and the unit the arithmetic
                              has to balance in. */}
                          {batchViews.filter((v) => v.thisAllocation > 0 || draft.flocks.some((f) => f.batchKey === v.batch.key)).map((v) => (
                            <div key={v.batch.key} className="rounded-lg border border-slate-200 bg-white">
                              <div className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-100 px-3 py-2">
                                <span className="flex items-center gap-2 font-medium text-slate-900">
                                  {v.batch.batchCode || v.batch.batchName}
                                  <BatchStatusBadge status={v.status} />
                                  {v.batch.existingBatchId == null && !v.batch.isHistorical && (
                                    <Badge variant="outline" className="h-5 px-1.5 text-[10px] border-blue-300 text-blue-700">
                                      New purchase
                                    </Badge>
                                  )}
                                </span>
                                <span className="text-xs text-slate-600 tabular-nums">
                                  original {v.batchBirds.toLocaleString()} · already {v.previouslyAllocated.toLocaleString()} ·
                                  {" "}this {v.thisAllocation.toLocaleString()} · remaining {v.remaining.toLocaleString()}
                                </span>
                              </div>
                              <div className="divide-y divide-slate-100">
                                {draft.flocks.filter((f) => f.batchKey === v.batch.key).map((f) => {
                                  const house = draft.houses.find((h) => h.key === f.houseKey)
                                  const b = breakdown(f)
                                  return (
                                    <div key={f.key} className="flex flex-wrap items-center justify-between gap-2 px-3 py-2 text-sm">
                                      <span className="font-medium text-slate-900">{f.name}</span>
                                      <span className="text-slate-600">
                                        {house?.houseName} · placed {Number(f.originallyPlaced || 0).toLocaleString()} · current{" "}
                                        {Number(f.currentLiveBirds || 0).toLocaleString()}
                                        {b.difference > 0 && <span className="text-amber-700"> · opening reduction {b.difference.toLocaleString()}</span>}
                                      </span>
                                    </div>
                                  )
                                })}
                              </div>
                            </div>
                          ))}

                          {warnings.length > 0 && (
                            <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 space-y-1">
                              {warnings.map((w, i) => {
                                const fix = fixFor(w)
                                return (
                                  <p key={i} className="text-sm text-amber-800 flex items-start gap-2">
                                    <TriangleAlert className="w-4 h-4 shrink-0 mt-0.5" />
                                    <span>
                                      {w.message}
                                      {fix && (
                                        <>
                                          {" "}
                                          <button type="button" onClick={fix.onClick}
                                            className="font-medium underline underline-offset-2 hover:no-underline">
                                            {fix.label}
                                          </button>
                                        </>
                                      )}
                                    </span>
                                  </p>
                                )
                              })}
                            </div>
                          )}

                          {/* Not gated on `submitted`: this step exists to be read
                              before committing, so a problem it can already see --
                              flocks placed with more birds than their batch held,
                              say -- must be on screen now, not after a rejected
                              click. */}
                          {errors.length > 0 && (
                            <div className="rounded-lg border border-red-200 bg-red-50 p-3 space-y-1">
                              {errors.map((e, i) => {
                                const fix = fixFor(e)
                                return (
                                  <p key={i} className="text-sm text-red-700 flex items-start gap-2">
                                    <AlertCircle className="w-4 h-4 shrink-0 mt-0.5" />
                                    <span>
                                      {e.message}
                                      {fix && (
                                        <>
                                          {" "}
                                          <button type="button" onClick={fix.onClick}
                                            className="font-medium underline underline-offset-2 hover:no-underline">
                                            {fix.label}
                                          </button>
                                        </>
                                      )}
                                    </span>
                                  </p>
                                )
                              })}
                            </div>
                          )}
                        </div>
                      </Section>
                    )}

                    {/* Pinned: the running numbers and the way forward stay in
                        view instead of living at the bottom of a long grid. */}
                    <div className="sticky bottom-20 lg:bottom-3 z-30 rounded-xl border border-slate-200 bg-white/95 px-3 sm:px-4 py-3 shadow-lg backdrop-blur supports-[backdrop-filter]:bg-white/85">
                      {step >= 2 && draft.flocks.length > 0 && (
                        <div className="mb-3 grid grid-cols-3 gap-2 border-b border-slate-100 pb-3 sm:flex sm:flex-wrap sm:items-center sm:gap-x-6 sm:gap-y-1">
                          <Running label="Placed" longLabel="Originally placed" value={totals.originallyPlaced} tone="slate" />
                          <Running label="Live" longLabel="Current live birds" value={totals.openingLiveBirds} tone="emerald" />
                          <Running label="Reduction" longLabel="Historical reduction" value={totals.historicalReduction} tone="amber" />
                          {totals.flocksWithUnknownHistory > 0 && (
                            <span className="col-span-3 text-xs text-slate-500">
                              {totals.flocksWithUnknownHistory} flock{totals.flocksWithUnknownHistory === 1 ? "" : "s"} with unknown history
                            </span>
                          )}
                        </div>
                      )}
                      <div className="flex flex-wrap items-center justify-between gap-2">
                        <Button variant="ghost" onClick={() => { if (step === 0) { clearSavedDraft(); navigate("choose") } else navigate("wizard", Math.max(0, step - 1) as Step) }} disabled={saving} className="gap-1">
                          <ArrowLeft className="w-4 h-4" /> {step === 0 ? "Cancel" : "Back & Edit"}
                        </Button>
                        <div className="flex items-center gap-3">
                          <span className="hidden text-xs text-slate-500 sm:inline">
                            {draftState === "saving" ? "Saving…"
                              : draftState === "saved" ? "Saved"
                              : draftState === "error" ? "Not saved — check your connection"
                              : `Step ${step + 1} of ${STEPS.length}`}
                          </span>
                          {step < 4 ? (
                            <Button onClick={goNext} className="gap-1 bg-blue-600 hover:bg-blue-700">
                              Continue <ArrowRight className="w-4 h-4" />
                            </Button>
                          ) : (
                            <Button onClick={submit} disabled={saving} className="bg-emerald-600 hover:bg-emerald-700">
                              {saving ? <span className="flex items-center gap-2"><Loader2 className="w-4 h-4 animate-spin" /> Setting up…</span> : "Complete Farm Setup"}
                            </Button>
                          )}
                        </div>
                      </div>
                    </div>
                  </>
                )}
              </>
            )}
          </div>
        </main>
      </div>

      {/* Opened from the capacity note on an allocation row, so a stale capacity
          can be fixed where it is discovered. */}
      <PenCapacityDialog
        open={capacityPen !== null}
        onOpenChange={(next) => { if (!next) setCapacityPenKey(null) }}
        penName={capacityPen?.load?.label || capacityPen?.row.houseName || ""}
        capacity={capacityPen?.load?.capacity ?? null}
        occupied={capacityPen?.load?.occupied ?? 0}
        standing={capacityPen?.load?.standing ?? 0}
        savesImmediately={capacityPen?.row.existingHouseId != null}
        onSave={saveCapacity}
      />

      {/* Opened when the allocation runs out of pens, so "nowhere to put them"
          comes with the way to fix it rather than directions elsewhere. */}
      <NewPenDialog
        open={newPenOpen}
        onOpenChange={setNewPenOpen}
        suggestedName={suggestedPenName}
        takenNames={draft.houses.map((h) => h.houseName)}
        onCreate={addPen}
      />

      {/* Opened from the batch's own warning, for the same reason: the message
          says "raise the batch", so it should be possible to do it here. */}
      <BatchSizeDialog
        open={sizeBatch !== null}
        onOpenChange={(next) => { if (!next) setSizeBatchKey(null) }}
        batchLabel={sizeBatch?.batch.batchCode || sizeBatch?.batch.batchName || ""}
        batchBirds={sizeBatch?.batchBirds ?? 0}
        previouslyAllocated={sizeBatch?.previouslyAllocated ?? 0}
        thisAllocation={sizeBatch?.thisAllocation ?? 0}
        savesImmediately={sizeBatch?.batch.existingBatchId != null}
        onSave={saveBatchSize}
      />
    </div>
  )
}

// ---------------------------------------------------------------------------
// Small presentational helpers. Local because nothing else needs them.
// ---------------------------------------------------------------------------

/**
 * A row's shell. Invalid rows go red. Otherwise rows alternate amber/white --
 * the daily-closing card list's stripe, applied at every width. A dozen rows of
 * identical fields are hard to tell apart without it, which is exactly what the
 * desktop grid looked like before.
 */
const rowShell = (index: number, live?: Record<string, string>, server?: Record<string, string>) => {
  const invalid = (live && Object.keys(live).length > 0) || (server && Object.keys(server).length > 0)
  if (invalid) return "border-red-300 bg-red-50 border-l-4 border-l-red-500"
  // Blue at -200. blue-50 and blue-100 both washed out against the white card
  // behind them; -200 is the first step that separates a striped row from a
  // plain one at a glance. Every control inside sits on its own white fill
  // (see the row's [&_input] utilities), so nothing loses contrast as the tint
  // deepens.
  return index % 2 === 0
    ? "bg-blue-200 border-blue-300 border-l-4 border-l-blue-600"
    : "bg-white border-slate-200 border-l-4 border-l-slate-300"
}

function sectionForStep(step: Step): string {
  return step === 0 ? "houses" : step === 1 ? "batches" : "flocks"
}

/**
 * Numbered rail. A wizard's progress is the one thing a page like this owes the
 * reader on arrival -- how many steps there are, and how far in they are -- and
 * a row of pills says neither at a glance. Completed steps carry a tick so the
 * rail reads as progress rather than as a menu.
 */
function StepBar({ step, onGo }: { step: Step; onGo: (step: Step) => void }) {
  return (
    <>
      {/* Phones: the rail does not fit, and a horizontal scrollbar hides the
          last two steps. A bar says the same thing in one line. */}
      <div className="sm:hidden">
        <div className="flex items-baseline justify-between gap-2">
          <span className="text-sm font-medium text-slate-900">{STEPS[step]}</span>
          <span className="text-xs text-slate-500">Step {step + 1} of {STEPS.length}</span>
        </div>
        <div className="mt-1.5 h-1.5 w-full overflow-hidden rounded-full bg-slate-200">
          <div className="h-full rounded-full bg-blue-600 transition-all"
            style={{ width: `${((step + 1) / STEPS.length) * 100}%` }} />
        </div>
        <div className="mt-2 flex gap-1">
          {STEPS.map((label, i) => (
            <button key={label} type="button" onClick={() => onGo(i as Step)}
              aria-label={`Go to ${label}`} aria-current={i === step ? "step" : undefined}
              className={`h-7 flex-1 rounded-md text-xs font-medium transition-colors ${
                i === step ? "bg-blue-600 text-white"
                  : i < step ? "bg-blue-100 text-blue-700"
                  : "bg-slate-100 text-slate-500"
              }`}>
              {i + 1}
            </button>
          ))}
        </div>
      </div>

      <ol className="hidden sm:flex items-start gap-1 overflow-x-auto pb-1">
      {STEPS.map((label, i) => {
        const done = i < step
        const current = i === step
        return (
          <li key={label} className="flex items-start gap-1 shrink-0">
            {/* A step is a button. Someone who spots a wrong pen capacity on
                Review should be able to get back to it in one click rather than
                four, and a rail that only ever lights up is furniture. */}
            <button type="button" onClick={() => onGo(i as Step)}
              aria-current={current ? "step" : undefined}
              className="flex flex-col items-center gap-1.5 w-[104px] sm:w-[128px] text-center rounded-md p-1 -m-1 transition-colors hover:bg-slate-50">
              <span className={`w-8 h-8 rounded-full flex items-center justify-center text-sm font-semibold ring-4 transition-colors ${
                current ? "bg-blue-600 text-white ring-blue-100"
                  : done ? "bg-blue-100 text-blue-700 ring-transparent"
                  : "bg-slate-100 text-slate-400 ring-transparent"
              }`}>
                {done ? <Check className="w-4 h-4" /> : i + 1}
              </span>
              <span className={`text-[11px] sm:text-xs leading-tight ${
                current ? "text-slate-900 font-medium" : done ? "text-slate-600" : "text-slate-400"
              }`}>
                {label}
              </span>
            </button>
            {i < STEPS.length - 1 && (
              <span className={`h-8 w-6 sm:w-10 border-t-2 mt-4 ${done ? "border-blue-200" : "border-slate-200"}`} />
            )}
          </li>
          )
        })}
      </ol>
    </>
  )
}

/**
 * A step's container.
 *
 * Deliberately a Card, not the colour-barred panel used elsewhere in this app --
 * that pattern belongs to DIALOGS (customers, flocks, houses all use it inside
 * their create/edit modals) and putting five of them on one page, each a
 * different colour, made the wizard read as five unrelated tools. One accent,
 * carried by the step icon, is what makes it read as one flow.
 */
function Section({ title, description, icon: Icon, children }: {
  title: string; description?: string; icon: React.ElementType; children: React.ReactNode
}) {
  return (
    <Card className="overflow-hidden">
      <CardHeader className="border-b border-slate-100 bg-slate-50/60 py-4">
        <div className="flex items-start gap-3">
          <span className="w-9 h-9 rounded-lg bg-blue-50 flex items-center justify-center shrink-0">
            <Icon className="w-4 h-4 text-blue-600" />
          </span>
          <div className="min-w-0">
            <CardTitle className="text-base">{title}</CardTitle>
            {description && <p className="mt-1 text-sm leading-relaxed text-slate-600">{description}</p>}
          </div>
        </div>
      </CardHeader>
      <CardContent className="p-4 space-y-3">{children}</CardContent>
    </Card>
  )
}

/** The column headings for a grid step. Desktop only -- on mobile each field carries its own. */
function RowHeader({ label, badge, onRemove }: {
  label: string; badge: React.ReactNode
  /** Omitted for a row that is not this setup's to remove. */
  onRemove?: () => void
}) {
  return (
    <div className="mb-3 flex items-center justify-between gap-2 border-b border-slate-100 pb-2 md:hidden">
      <span className="text-xs font-semibold uppercase tracking-wide text-slate-500">{label}</span>
      <span className="flex items-center gap-1">
        {badge}
        {onRemove && (
          <Button type="button" variant="ghost" size="sm" onClick={onRemove} className="h-7 px-2 text-red-600 hover:bg-red-50">
            <Trash2 className="h-4 w-4" />
          </Button>
        )}
      </span>
    </div>
  )
}

/** One number with its label. The allocation header is four of these. */
function Figure({ label, value, tone = "slate" }: {
  label: string; value: number; tone?: "slate" | "blue" | "amber" | "emerald" | "red"
}) {
  const tones = {
    slate: "text-slate-900", blue: "text-blue-700", amber: "text-amber-700",
    emerald: "text-emerald-700", red: "text-red-700",
  } as const
  return (
    <div className="rounded-lg border border-slate-200 bg-white px-3 py-2">
      <p className="text-xs text-slate-500">{label}</p>
      <p className={`text-base font-semibold tabular-nums ${tones[tone]}`}>{value.toLocaleString()}</p>
    </div>
  )
}

/** Where a batch stands, at a glance, in the batch strip. */
function BatchStatusBadge({ status }: { status: BatchAllocationStatus }) {
  const map = {
    over: ["border-red-300 text-red-700", "Over"],
    unallocated: ["border-blue-300 text-blue-700", "New"],
    partial: ["border-amber-300 text-amber-700", "Partial"],
    complete: ["border-emerald-300 text-emerald-700", "Done"],
  } as const
  const [className, label] = map[status]
  return <Badge variant="outline" className={`h-5 px-1.5 text-[10px] ${className}`}>{label}</Badge>
}

/** A quiet heading inside a card, so a long form still reads as sections. */
function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">{children}</p>
  )
}

/**
 * A radio-style choice with room to say what it MEANS. The historical-versus-new
 * decision changes what gets posted to the books, so it earns a sentence rather
 * than a bare label.
 */
function RadioRow({ checked, onSelect, title, detail }: {
  checked: boolean; onSelect: () => void; title: string; detail: string
}) {
  return (
    <button type="button" onClick={onSelect}
      className={`flex w-full items-start gap-2 rounded-lg border px-3 py-2 text-left transition-colors ${
        checked ? "border-blue-400 bg-blue-50" : "border-slate-200 bg-white hover:bg-slate-50"
      }`}>
      <span className={`mt-0.5 flex h-4 w-4 shrink-0 items-center justify-center rounded-full border-2 ${
        checked ? "border-blue-600" : "border-slate-300"
      }`}>
        {checked && <span className="h-2 w-2 rounded-full bg-blue-600" />}
      </span>
      <span className="min-w-0">
        <span className="block text-sm font-medium text-slate-900">{title}</span>
        <span className="block text-xs leading-relaxed text-slate-600">{detail}</span>
      </span>
    </button>
  )
}

function GridHeader({ columns }: { columns: [string, string][] }) {
  return (
    <div className="hidden md:grid grid-cols-12 gap-3 px-3 pb-1 text-xs font-medium text-slate-500">
      {columns.map(([span, label]) => <div key={label} className={span}>{label}</div>)}
    </div>
  )
}

function Field({ label, error, hint, note, className, children, mobileOnlyLabel }: {
  label?: React.ReactNode; error?: string; hint?: string; className?: string
  /**
   * Amber, for something worth acting on that must not block. Sits under `hint`.
   * A node rather than a string so it can offer the fix as well as name it.
   */
  note?: React.ReactNode
  children: React.ReactNode
  /** The grid already shows this column's heading on desktop; only repeat it on mobile. */
  mobileOnlyLabel?: boolean
}) {
  return (
    <div className={`space-y-1 ${className ?? ""}`}>
      {label && (
        <Label className={`flex items-center gap-1.5 text-xs ${mobileOnlyLabel ? "md:hidden" : ""}`}>{label}</Label>
      )}
      {children}
      {hint && !error && <p className="text-xs text-slate-500">{hint}</p>}
      {note && !error && (
        <p className="text-xs text-amber-700 flex items-start gap-1">
          <TriangleAlert className="w-3 h-3 shrink-0 mt-0.5" /> {note}
        </p>
      )}
      {error && (
        <p className="text-xs text-red-600 flex items-start gap-1">
          <AlertCircle className="w-3 h-3 shrink-0 mt-0.5" /> {error}
        </p>
      )}
    </div>
  )
}

// The value colours /production-records uses on its stat tiles. The card itself
// is always white; only the number is coloured.
const TONES = {
  slate:   "text-slate-900",
  blue:    "text-blue-700",
  emerald: "text-emerald-600",
  amber:   "text-amber-600",
  violet:  "text-purple-700",
  rose:    "text-red-600",
} as const
type Tone = keyof typeof TONES

/**
 * A figure in the pinned bar. On a phone it is a tinted tile -- three of them
 * across, colour-coded so placed / live / lost are told apart at a glance rather
 * than read. On wider screens the tint is dropped and they sit inline, where
 * there is room for the full label and the colour would only add noise.
 */
function Running({ label, longLabel, value, tone = "slate" }: {
  label: string; longLabel?: string; value: number; tone?: Tone
}) {
  return (
    <span className="rounded-lg border border-slate-200 bg-white px-2 py-1.5 text-center leading-tight shadow-sm sm:border-0 sm:px-0 sm:py-0 sm:text-left sm:shadow-none">
      <span className="block text-[10px] font-medium uppercase tracking-wider text-slate-500 sm:text-[11px]">
        <span className="sm:hidden">{label}</span>
        <span className="hidden sm:inline">{longLabel ?? label}</span>
      </span>
      <span className={`block font-bold tabular-nums ${TONES[tone]} text-base`}>
        {value.toLocaleString()}
      </span>
    </span>
  )
}

/**
 * A scorecard. Tinted and bordered on phones, where these are the page's main
 * content and a grid of grey numbers reads as a spreadsheet; on desktop the
 * tint is kept but lightened, since the surrounding card already groups them.
 */
/** The same tile /production-records uses: white card, coloured number. */
function Stat({ label, value, tone = "slate", small }: {
  label: string; value: number; tone?: Tone; small?: boolean
}) {
  return (
    <div className={`rounded-xl border border-slate-200 bg-white shadow-sm ${small ? "p-3" : "p-4"}`}>
      <span className="text-xs font-medium uppercase tracking-wider text-slate-500">{label}</span>
      <p className={`mt-0.5 font-bold leading-tight tabular-nums ${TONES[tone]} ${small ? "text-lg" : "text-xl"}`}>
        {value.toLocaleString()}
      </p>
    </div>
  )
}

/**
 * What the page shows once setup is done: a record, not another "Create Farm"
 * button. Re-running the wizard would create the whole farm a second time, so
 * the way back in is deliberately absent.
 */
function CompletedPanel({ status, opening, onSetUpMore }: {
  status: FarmSetupStatus; opening: OpeningPositionSummary | null; onSetUpMore: () => void
}) {
  return (
    <div className="space-y-4">
      {/* FIRST on the page. The tool is no longer one-shot, and starting another
          setup is the only reason a farm opens this screen — everything below is
          a record of what already happened. */}
      <Card className="border-2 border-blue-300 bg-blue-50">
        <CardContent className="flex flex-col items-start gap-4 p-6 sm:flex-row sm:items-center sm:justify-between">
          <div className="min-w-0">
            <h3 className="text-lg font-semibold text-slate-900">Do another bulk setup</h3>
            <p className="mt-1 text-sm leading-relaxed text-slate-600">
              Built new pens, or bought another batch? Run the setup again to add and allocate them in one go.
              Your existing pens, batches and flocks are kept — nothing here is created twice.
            </p>
          </div>
          <Button size="lg" onClick={onSetUpMore}
            className="w-full shrink-0 gap-2 bg-blue-600 px-8 text-base hover:bg-blue-700 sm:w-auto">
            <Plus className="h-5 w-5" /> Do another bulk setup
          </Button>
        </CardContent>
      </Card>

      <Card className="border-emerald-200">
        <CardContent className="p-6 space-y-3">
          <div className="flex items-center gap-2">
            <CheckCircle2 className="w-5 h-5 text-emerald-600" />
            <h2 className="text-lg font-semibold text-slate-900">Initial Farm Setup Completed</h2>
          </div>
          <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
            <div>
              <p className="text-xs text-slate-500">Completed</p>
              <p className="text-sm font-semibold text-slate-900">
                {status.completedBusinessDate ? String(status.completedBusinessDate).split("T")[0] : "—"}
              </p>
            </div>
            <Stat small label="Batches" value={status.batchCount} tone="blue" />
            <Stat small label="Flocks" value={status.flockCount} tone="blue" />
            <Stat small label="Opening live birds" value={status.openingLiveBirds} tone="emerald" />
            <Stat small label="Historical reconciliation" value={status.historicalReduction} tone="amber" />
          </div>
          <p className="text-sm text-slate-600">
            Day-to-day work happens on{" "}
            <Link href="/flock-batch" className="text-blue-600 hover:underline">Flock Purchases</Link>,{" "}
            <Link href="/houses" className="text-blue-600 hover:underline">Houses</Link>,{" "}
            <Link href="/flocks" className="text-blue-600 hover:underline">Flock Groups</Link> and{" "}
            <Link href="/production-records" className="text-blue-600 hover:underline">Production Records</Link>.
          </p>
        </CardContent>
      </Card>

      {opening && opening.flockCount > 0 && (
        <Card>
          <CardContent className="p-6 space-y-4">
            <div className="flex items-center gap-2">
              <ClipboardList className="w-5 h-5 text-slate-600" />
              <h3 className="font-semibold text-slate-900">Opening Farm Position</h3>
            </div>
            <p className="text-sm text-slate-600">
              What was true when tracking began. These figures are <b>not</b> operational events: none of them appears
              in Production Records, in Total Deaths, or in any dated mortality report.
            </p>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <Stat label="Birds originally placed" value={opening.originallyPlaced} tone="blue" />
              <Stat label="Opening live birds" value={opening.openingLiveBirds} tone="emerald" />
              <Stat label="Historical reduction" value={opening.historicalReduction} tone="amber" />
              <Stat label="Opening historical mortality" value={opening.historicalMortality} tone="rose" />
            </div>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
              <Stat small label="Sold" value={opening.historicalSold} />
              <Stat small label="Culled" value={opening.historicalCulled} />
              <Stat small label="Transferred" value={opening.historicalTransferred} />
              <Stat small label="Other / unknown" value={opening.otherAdjustment} />
            </div>
            {opening.otherAdjustment > 0 && (
              <p className="text-xs text-slate-500">
                {opening.otherAdjustment.toLocaleString()} birds have no stated cause across{" "}
                {opening.flocksWithUnknownHistory} flock{opening.flocksWithUnknownHistory === 1 ? "" : "s"}. They are
                counted as an opening adjustment, never as mortality — known lifetime mortality is the opening
                mortality above plus whatever has been recorded since.
              </p>
            )}

            <div className="rounded-lg border border-slate-200 divide-y divide-slate-100">
              {opening.positions.map((p) => (
                <div key={p.openingPositionId} className="flex flex-wrap items-center justify-between gap-2 px-3 py-2 text-sm">
                  <span className="font-medium text-slate-900">
                    {p.flockName ?? `Flock #${p.flockId}`}
                    {p.startDateEstimated && <Badge variant="outline" className="ml-2 h-5 text-[11px] border-slate-300 text-slate-500">age estimated</Badge>}
                  </span>
                  <span className="text-slate-600">
                    placed {p.originallyPlaced.toLocaleString()} · opening {p.openingLiveBirds.toLocaleString()}
                    {p.historicalReduction > 0 && (
                      <span className="text-amber-700">
                        {" "}· reduction {p.historicalReduction.toLocaleString()}
                        {p.historyKnown ? ` (mortality ${p.historicalMortality.toLocaleString()})` : " (unknown)"}
                      </span>
                    )}
                  </span>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {opening && opening.flockCount === 0 && (
        <Card>
          <CardContent className="p-6 text-center text-slate-600">
            <Home className="h-10 w-10 text-slate-400 mx-auto mb-2" />
            No opening positions were recorded — this farm started with new birds, so there was no history to reconstruct.
          </CardContent>
        </Card>
      )}
    </div>
  )
}
