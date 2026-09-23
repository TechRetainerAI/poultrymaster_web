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
import {
  completeFarmSetup, getFarmSetupContext, getOpeningPositions,
  type FarmSetupResult, type FarmSetupStatus, type FarmSetupWizardContext,
  type OpeningPositionSummary,
} from "@/lib/api/poultry-farm-setup"
import {
  batchRowFromExisting, breakdown, defaultFlockName, emptyBatch, emptyFlock, emptyHouse,
  errorsBySection, flocksNeedingReconciliation, generateBatches, historicalReduction,
  houseRowFromExisting, summarize, toRequest, validateSetup,
  type BatchRow, type FlockRow, type HouseRow, type SetupContext, type SetupDraft,
} from "@/lib/farm-setup/wizard"
// Prompt 1's bulk house generator, reused rather than rebuilt.
import { generateRows as generateHouseRows } from "@/lib/houses/bulk"

type Screen = "choose" | "wizard" | "newBatch" | "done" | "completed"
type Step = 0 | 1 | 2 | 3 | 4

const STEPS = ["Batches", "Houses/Pens", "Flocks or Birds Groupings", "Opening Reconciliation", "Review"]

// What each step is called in the address bar. Stable, readable names rather
// than indexes, so a URL stays meaningful if a step is ever inserted.
const STEP_SLUGS = ["batches", "houses", "flocks", "reconcile", "review"] as const

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

  /** Survives F5, not the tab closing, and never reaches the server. */
  const draftKey = () => {
    const { farmId } = getUserContext()
    return farmId ? `poultry-farm-setup:${farmId}` : null
  }

  const clearSavedDraft = useCallback(() => {
    try {
      const k = draftKey()
      if (k) window.sessionStorage.removeItem(k)
    } catch { /* private mode, blocked storage -- the wizard still works */ }
  }, [])

  // Save on every change while the wizard is open. Small, and the alternative is
  // losing a farm's worth of typing to a stray refresh.
  useEffect(() => {
    if (screen !== "wizard") return
    try {
      const k = draftKey()
      if (k) window.sessionStorage.setItem(k, JSON.stringify({ step, draft }))
    } catch { /* ignore */ }
  }, [screen, step, draft])

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
  const [penLocation, setPenLocation] = useState("")

  const status: FarmSetupStatus | null = context?.status ?? null

  const load = useCallback(async () => {
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      setLoading(false)
      return
    }
    setLoading(true)
    const [ctxRes, openRes] = await Promise.all([
      getFarmSetupContext(userId, farmId),
      getOpeningPositions(userId, farmId),
    ])
    if (ctxRes.success && ctxRes.data) {
      setContext(ctxRes.data)

      // A refresh mid-wizard should land where it left off, not throw the work
      // away. Only when the URL still names a step AND this tab has the draft
      // that went with it -- a bare ?step= with no draft is someone else's link.
      let restored = false
      if (!ctxRes.data.status?.isComplete && typeof window !== "undefined") {
        const slug = new URLSearchParams(window.location.search).get("step")
        const i = slug ? STEP_SLUGS.indexOf(slug as (typeof STEP_SLUGS)[number]) : -1
        if (i >= 0) {
          try {
            const raw = window.sessionStorage.getItem(`poultry-farm-setup:${farmId}`)
            const saved = raw ? JSON.parse(raw) : null
            if (saved?.draft?.flocks && Array.isArray(saved.draft.batches)) {
              setDraft(saved.draft as SetupDraft)
              navigate("wizard", i as Step, true)
              restored = true
            }
          } catch { /* corrupt or blocked storage -- fall through to the entry screen */ }
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
  const removeHouse = (i: number) =>
    setDraft((d) => {
      const gone = d.houses[i]
      return {
        ...d,
        houses: d.houses.filter((_, x) => x !== i),
        flocks: d.flocks.filter((f) => f.houseKey !== gone.key),
      }
    })
  const removeFlock = (i: number) => setDraft((d) => ({ ...d, flocks: d.flocks.filter((_, x) => x !== i) }))

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
      toast({ title: "Nothing to generate", description: "Enter how many batches you have.", variant: "warning" })
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
      toast({ title: "Nothing to generate", description: "Enter how many pens you need.", variant: "warning" })
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

  /** One flock row per house, named after its batch — the allocation convention. */
  /**
   * The birds already in a house, as the server counted them (active flocks
   * placed there). Null for a house this wizard is about to create, which by
   * definition holds nothing yet.
   */
  const houseOccupancy = useCallback((houseKey: string, houses: HouseRow[]) => {
    const row = houses.find((h) => h.key === houseKey)
    if (!row?.existingHouseId) return null
    return setupContext.existingHouses.find((h) => h.houseId === row.existingHouseId) ?? null
  }, [setupContext])

  const buildFlockRows = () => {
    const firstBatch = draft.batches[0]
    setDraft((d) => {
      const covered = new Set(d.flocks.map((f) => f.houseKey).filter(Boolean))
      const added = d.houses
        .filter((h) => !covered.has(h.key))
        .map((h) => {
          // Start from what is already standing in the pen, so a farm that has
          // told us its houses does not then retype every bird count. Equal on
          // both sides -- the difference is what the farm LOST, and it says so
          // by lowering Current Live Birds, not by us guessing at it.
          const held = houseOccupancy(h.key, d.houses)?.occupied ?? 0
          return {
            ...emptyFlock(firstBatch?.key ?? "", h.key),
            name: defaultFlockName(firstBatch?.batchCode ?? "", h.houseName),
            startDate: firstBatch?.startDate ?? "",
            originallyPlaced: held > 0 ? String(held) : "",
            currentLiveBirds: held > 0 ? String(held) : "",
          }
        })
      return { ...d, flocks: [...added, ...d.flocks] }
    })
  }

  const goNext = () => {
    setSubmitted(true)
    // Only what this step can fix. A setup-wide complaint about missing flocks
    // is true — and unfixable — while you are still filling in the batches, so
    // it must not hold the Continue button hostage.
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
    if (step === 1) buildFlockRows()
    navigate("wizard", Math.min(4, step + 1) as Step)
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
                {screen === "completed" && status && (
                  <CompletedPanel status={status} opening={opening} />
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
                    <StepBar step={step} />

                    {/* Step 1 — Batches */}
                    {step === 0 && (
                      <Section icon={Boxes} title="What batches/groups of birds do you currently have?"
                        description="Generate a run of batches, then edit any of them. Purchase cost and supplier are optional — if you do not know what you paid, leave them blank. Nothing here posts cash or revenue for a historical purchase.">
                        <div className="grid grid-cols-1 md:grid-cols-6 gap-3 p-4 bg-slate-50 border-b border-slate-200 -mx-4 -mt-4 mb-1">
                          <Field label="Number of Batches"><NumberInput min="1" value={batchCount} onChange={(e) => setBatchCount(e.target.value)} /></Field>
                          <Field label="Name Prefix"><Input value={batchPrefix} onChange={(e) => setBatchPrefix(e.target.value)} placeholder="Batch" /></Field>
                          <Field label="Code Prefix"><Input value={batchCodePrefix} onChange={(e) => setBatchCodePrefix(e.target.value)} placeholder="B" /></Field>
                          <Field label="Starting Number"><NumberInput value={batchStart} onChange={(e) => setBatchStart(e.target.value)} /></Field>
                          <Field label="Default Breed"><Input value={batchBreed} onChange={(e) => setBatchBreed(e.target.value)} placeholder="Bovan Brown" /></Field>
                          <Field label="Default Birds"><NumberInput min="0" value={batchBirds} onChange={(e) => setBatchBirds(e.target.value)} placeholder="5000" /></Field>
                          <Field className="md:col-span-2" label="Default Arrival Date">
                            <Input type="date" value={batchDate} onChange={(e) => setBatchDate(e.target.value)} />
                          </Field>
                          <div className="md:col-span-6">
                            <Button type="button" onClick={generateBatchRows} className="bg-blue-600 hover:bg-blue-700 gap-2">
                              <Wand2 className="w-4 h-4" /> Generate
                            </Button>
                            <span className="text-xs text-slate-500 ml-3">
                              Replaces the new rows below; batches you already have are kept. Everything stays editable.
                            </span>
                          </div>
                        </div>
                        <GridHeader columns={[
                          ["col-span-3", "Batch Name *"], ["col-span-2", "Batch Code *"], ["col-span-2", "Breed *"],
                          ["col-span-2", "Original Birds *"], ["col-span-2", "Arrival Date *"], ["col-span-1", ""],
                        ]} />
                        {draft.batches.map((b, i) => (
                            <div key={b.key} className={`rounded-lg border px-3 py-3 md:grid md:grid-cols-12 md:gap-3 [&_input]:bg-white [&_button[role=combobox]]:bg-white [&_[data-slot=select-trigger]]:bg-white ${rowShell(i, submitted ? fieldErrors.batches?.[i] : undefined, serverErrors.batches?.[i])}`}>
                              <RowHeader
                                label={`Batch ${i + 1}`}
                                badge={b.existingBatchId != null
                                  ? <Badge variant="secondary" className="h-6 px-1.5 text-[10px]">Existing</Badge>
                                  : <Badge variant="outline" className="h-6 px-1.5 text-[10px] border-blue-300 text-blue-700">New</Badge>}
                                onRemove={() => removeBatch(i)}
                              />
                              <div className="grid grid-cols-12 gap-3 md:contents">
                              <Field className="col-span-12 md:col-span-3"
                                label="Batch Name *" mobileOnlyLabel error={errorFor("batches", i, "batchName")}>
                                <Input value={b.batchName} disabled={b.existingBatchId != null}
                                  onChange={(e) => patchBatch(i, { batchName: e.target.value })} placeholder="B1" />
                              </Field>
                              <Field className="col-span-12 sm:col-span-6 md:col-span-2" label="Batch Code *" mobileOnlyLabel error={errorFor("batches", i, "batchCode")}>
                                <Input value={b.batchCode} disabled={b.existingBatchId != null}
                                  onChange={(e) => patchBatch(i, { batchCode: e.target.value })} placeholder="B001" />
                              </Field>
                              <Field className="col-span-12 sm:col-span-6 md:col-span-2" label="Breed *" mobileOnlyLabel error={errorFor("batches", i, "breed")}>
                                <Input value={b.breed} disabled={b.existingBatchId != null}
                                  onChange={(e) => patchBatch(i, { breed: e.target.value })} placeholder="Bovan Brown" />
                              </Field>
                              <Field className="col-span-12 sm:col-span-6 md:col-span-2" label="Original Birds *" mobileOnlyLabel error={errorFor("batches", i, "numberOfBirds")}>
                                <NumberInput min="0" value={b.numberOfBirds} disabled={b.existingBatchId != null}
                                  onChange={(e) => patchBatch(i, { numberOfBirds: e.target.value })} placeholder="6000" />
                              </Field>
                              <Field className="col-span-12 sm:col-span-6 md:col-span-2" label="Arrival Date *" mobileOnlyLabel error={errorFor("batches", i, "startDate")}>
                                <Input type="date" value={b.startDate} disabled={b.existingBatchId != null}
                                  onChange={(e) => patchBatch(i, { startDate: e.target.value })} />
                              </Field>
                              </div>
                              <div className="col-span-12 md:col-span-1 hidden md:flex items-end justify-end">
                                <Button type="button" variant="ghost" size="icon" onClick={() => removeBatch(i)}
                                  className="h-9 w-9 shrink-0 text-red-600 hover:bg-red-50" aria-label="Remove batch">
                                  <Trash2 className="w-4 h-4" />
                                </Button>
                              </div>
                            </div>
                          ))}
                          <Button type="button" variant="outline" size="sm" onClick={() => setDraft((d) => ({ ...d, batches: [emptyBatch(), ...d.batches] }))}>
                            <Plus className="w-4 h-4 mr-1" /> Add Another Batch
                          </Button>
                      </Section>
                    )}

                    {/* Step 2 — Houses */}
                    {step === 1 && (
                      <Section icon={Home} title="Where are your birds housed?"
                        description="Generate a run of pens, then edit any of them. Houses you already have are listed and kept.">
                        <div className="grid grid-cols-1 md:grid-cols-5 gap-3 p-4 bg-slate-50 border-b border-slate-200">
                          <Field label="Number of Pens"><NumberInput min="1" value={penCount} onChange={(e) => setPenCount(e.target.value)} /></Field>
                          <Field label="Naming Prefix"><Input value={penPrefix} onChange={(e) => setPenPrefix(e.target.value)} placeholder="Pen" /></Field>
                          <Field label="Starting Number"><NumberInput value={penStart} onChange={(e) => setPenStart(e.target.value)} /></Field>
                          <Field label="Default Capacity"><NumberInput min="0" value={penCapacity} onChange={(e) => setPenCapacity(e.target.value)} placeholder="5000" /></Field>
                          <Field label="Default Location"><Input value={penLocation} onChange={(e) => setPenLocation(e.target.value)} placeholder="Layer House A" /></Field>
                          <div className="md:col-span-5">
                            <Button type="button" onClick={generateHouses} className="bg-indigo-600 hover:bg-indigo-700 gap-2">
                              <Wand2 className="w-4 h-4" /> Generate
                            </Button>
                            <span className="text-xs text-slate-500 ml-3">
                              Replaces the new rows below; houses you already have are kept. Everything stays editable.
                            </span>
                          </div>
                        </div>
                        {draft.houses.length > 0 && (
                          <GridHeader columns={[
                            ["col-span-4", "House/Pen Name *"], ["col-span-2", "Capacity"],
                            ["col-span-5", "Location"], ["col-span-1", ""],
                          ]} />
                        )}
                        {draft.houses.length === 0 && (
                            <p className="text-slate-600 text-sm">No houses/pens yet. Generate some above, or add one row at a time.</p>
                          )}
                          {draft.houses.map((h, i) => (
                            <div key={h.key} className={`rounded-lg border px-3 py-3 md:grid md:grid-cols-12 md:gap-3 [&_input]:bg-white [&_button[role=combobox]]:bg-white [&_[data-slot=select-trigger]]:bg-white ${rowShell(i, submitted ? fieldErrors.houses?.[i] : undefined, serverErrors.houses?.[i])}`}>
                              <RowHeader
                                label={h.houseName || `House ${i + 1}`}
                                badge={h.existingHouseId != null
                                  ? <Badge variant="secondary" className="h-6 px-1.5 text-[10px]">Existing</Badge>
                                  : <Badge variant="outline" className="h-6 px-1.5 text-[10px] border-blue-300 text-blue-700">New</Badge>}
                                onRemove={() => removeHouse(i)}
                              />
                              <div className="grid grid-cols-12 gap-3 md:contents">
                              <Field className="col-span-12 md:col-span-4"
                                label="House/Pen Name *" mobileOnlyLabel error={errorFor("houses", i, "houseName")}>
                                <Input value={h.houseName} disabled={h.existingHouseId != null}
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
                                <Button type="button" variant="ghost" size="icon" onClick={() => removeHouse(i)}
                                  className="h-9 w-9 shrink-0 text-red-600 hover:bg-red-50" aria-label="Remove house">
                                  <Trash2 className="w-4 h-4" />
                                </Button>
                              </div>
                            </div>
                          ))}
                          <Button type="button" variant="outline" size="sm" onClick={() => setDraft((d) => ({ ...d, houses: [emptyHouse(penCapacity, penLocation), ...d.houses] }))}>
                            <Plus className="w-4 h-4 mr-1" /> Add Another Row
                          </Button>
                      </Section>
                    )}

                    {/* Step 3 — Flocks & current birds */}
                    {step === 2 && (
                      <Section icon={Bird} title="What is in each house/pen today?"
                        description="Originally placed is what went into the pen. Current live birds is what is standing there now — that is the number tracking starts from.">
                        <GridHeader columns={[
                          ["col-span-2", "House/Pen *"], ["col-span-2", "Batch *"], ["col-span-2", "Flock Name *"],
                          ["col-span-2", "Originally Placed *"], ["col-span-2", "Current Live Birds *"], ["col-span-2", ""],
                        ]} />
                        {draft.flocks.map((f, i) => {
                            const reduction = historicalReduction(f)
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
                                <Field className="col-span-12 md:col-span-2" label="House/Pen *" mobileOnlyLabel
                                  error={errorFor("flocks", i, "houseKey")}
                                  hint={(() => {
                                    // The birds in that pen are already being counted by the flock
                                    // that is in it. Creating a second flock here counts them twice,
                                    // and nothing downstream will tell you that happened.
                                    const occ = houseOccupancy(f.houseKey, draft.houses)
                                    return occ && occ.activeFlocks > 0
                                      ? `Already holds ${occ.occupied.toLocaleString()} in ${occ.activeFlocks} flock${occ.activeFlocks === 1 ? "" : "s"} — this adds another`
                                      : undefined
                                  })()}>
                                  <Select
                                    value={f.houseKey}
                                    onValueChange={(v) => {
                                      // Only fill a row the user has not typed into; overwriting
                                      // their numbers because they corrected the pen would be worse
                                      // than not helping at all.
                                      const held = houseOccupancy(v, draft.houses)?.occupied ?? 0
                                      const untouched = !f.originallyPlaced.trim() && !f.currentLiveBirds.trim()
                                      patchFlock(i, untouched && held > 0
                                        ? { houseKey: v, originallyPlaced: String(held), currentLiveBirds: String(held) }
                                        : { houseKey: v })
                                    }}
                                  >
                                    <SelectTrigger><SelectValue placeholder="House" /></SelectTrigger>
                                    <SelectContent>
                                      {draft.houses.map((h) => <SelectItem key={h.key} value={h.key}>{h.houseName || "(unnamed)"}</SelectItem>)}
                                    </SelectContent>
                                  </Select>
                                </Field>
                                <Field className="col-span-12 md:col-span-2" label="Batch *" mobileOnlyLabel error={errorFor("flocks", i, "batchKey")}>
                                  <Select
                                    value={f.batchKey}
                                    onValueChange={(v) => {
                                      const b = draft.batches.find((x) => x.key === v)
                                      const house = draft.houses.find((h) => h.key === f.houseKey)
                                      patchFlock(i, {
                                        batchKey: v,
                                        name: defaultFlockName(b?.batchCode ?? "", house?.houseName ?? ""),
                                        startDate: f.startDate || (b?.startDate ?? ""),
                                      })
                                    }}
                                  >
                                    <SelectTrigger><SelectValue placeholder="Batch" /></SelectTrigger>
                                    <SelectContent>
                                      {draft.batches.map((b) => <SelectItem key={b.key} value={b.key}>{b.batchCode || b.batchName || "(unnamed)"}</SelectItem>)}
                                    </SelectContent>
                                  </Select>
                                </Field>
                                <Field className="col-span-12 md:col-span-2"
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
                            onClick={() => setDraft((d) => ({ ...d, flocks: [emptyFlock(d.batches[0]?.key ?? "", ""), ...d.flocks] }))}>
                            <Plus className="w-4 h-4 mr-1" /> Add Another Flock
                          </Button>
                      </Section>
                    )}

                    {/* Step 4 — Opening reconciliation */}
                    {step === 3 && (
                      <Section icon={ClipboardList} title="What happened to the missing birds?"
                        description="These losses happened before tracking began. They are recorded as an opening position and never appear as today’s deaths.">
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
                                        onCheckedChange={(v) => patchFlock(i, { historyKnown: v !== true })}
                                      />
                                      I don&apos;t know the historical breakdown
                                    </label>

                                    {f.historyKnown ? (
                                      <>
                                        <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
                                          <Field label="Known mortality"><NumberInput min="0" value={f.historicalMortality} onChange={(e) => patchFlock(i, { historicalMortality: e.target.value })} /></Field>
                                          <Field label="Sold"><NumberInput min="0" value={f.historicalSold} onChange={(e) => patchFlock(i, { historicalSold: e.target.value })} /></Field>
                                          <Field label="Culled"><NumberInput min="0" value={f.historicalCulled} onChange={(e) => patchFlock(i, { historicalCulled: e.target.value })} /></Field>
                                          <Field label="Transferred out"><NumberInput min="0" value={f.historicalTransferred} onChange={(e) => patchFlock(i, { historicalTransferred: e.target.value })} /></Field>
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

                          <div className="rounded-lg border border-slate-200 bg-white divide-y divide-slate-100">
                            {draft.flocks.map((f) => {
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

                          {warnings.length > 0 && (
                            <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 space-y-1">
                              {warnings.map((w, i) => (
                                <p key={i} className="text-sm text-amber-800 flex items-start gap-2">
                                  <TriangleAlert className="w-4 h-4 shrink-0 mt-0.5" /> {w.message}
                                </p>
                              ))}
                            </div>
                          )}

                          {/* Not gated on `submitted`: this step exists to be read
                              before committing, so a problem it can already see --
                              flocks placed with more birds than their batch held,
                              say -- must be on screen now, not after a rejected
                              click. */}
                          {errors.length > 0 && (
                            <div className="rounded-lg border border-red-200 bg-red-50 p-3 space-y-1">
                              {errors.map((e, i) => (
                                <p key={i} className="text-sm text-red-700 flex items-start gap-2">
                                  <AlertCircle className="w-4 h-4 shrink-0 mt-0.5" /> {e.message}
                                </p>
                              ))}
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
                          <span className="hidden text-xs text-slate-500 sm:inline">Step {step + 1} of {STEPS.length}</span>
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
  return step === 0 ? "batches" : step === 1 ? "houses" : "flocks"
}

/**
 * Numbered rail. A wizard's progress is the one thing a page like this owes the
 * reader on arrival -- how many steps there are, and how far in they are -- and
 * a row of pills says neither at a glance. Completed steps carry a tick so the
 * rail reads as progress rather than as a menu.
 */
function StepBar({ step }: { step: Step }) {
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
      </div>

      <ol className="hidden sm:flex items-start gap-1 overflow-x-auto pb-1">
      {STEPS.map((label, i) => {
        const done = i < step
        const current = i === step
        return (
          <li key={label} className="flex items-start gap-1 shrink-0">
            <div className="flex flex-col items-center gap-1.5 w-[104px] sm:w-[128px] text-center">
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
            </div>
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
function RowHeader({ label, badge, onRemove }: { label: string; badge: React.ReactNode; onRemove: () => void }) {
  return (
    <div className="mb-3 flex items-center justify-between gap-2 border-b border-slate-100 pb-2 md:hidden">
      <span className="text-xs font-semibold uppercase tracking-wide text-slate-500">{label}</span>
      <span className="flex items-center gap-1">
        {badge}
        <Button type="button" variant="ghost" size="sm" onClick={onRemove} className="h-7 px-2 text-red-600 hover:bg-red-50">
          <Trash2 className="h-4 w-4" />
        </Button>
      </span>
    </div>
  )
}

function GridHeader({ columns }: { columns: [string, string][] }) {
  return (
    <div className="hidden md:grid grid-cols-12 gap-3 px-3 pb-1 text-xs font-medium text-slate-500">
      {columns.map(([span, label]) => <div key={label} className={span}>{label}</div>)}
    </div>
  )
}

function Field({ label, error, hint, className, children, mobileOnlyLabel }: {
  label?: React.ReactNode; error?: string; hint?: string; className?: string
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
function CompletedPanel({ status, opening }: { status: FarmSetupStatus; opening: OpeningPositionSummary | null }) {
  return (
    <div className="space-y-4">
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
            A new batch six months from now goes through Flock Purchases and Divide Into Flocks — not through here.
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
