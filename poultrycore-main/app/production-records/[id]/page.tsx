"use client"

import type React from "react"

import { useEffect, useState } from "react"
import { useRouter, useParams } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Textarea } from "@/components/ui/textarea"
import { EGG_GRADE_OPTIONS, eggGradeFromApi, eggGradeToApi } from "@/lib/constants/egg-grade"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { FileText, X } from "lucide-react"
import { getProductionRecord, updateProductionRecord, type ProductionRecordInput } from "@/lib/api/production-record"
import { createFeedUsage, updateFeedUsage, getFeedUsages, type FeedUsageInput } from "@/lib/api/feed-usage"
import { getUserContext } from "@/lib/utils/user-context"
import { usePickSettings } from "@/hooks/use-pick-settings"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { useMemo } from "react"
import {
  listPoultryRawMaterialItems,
  listPoultryRawMaterialPurchases,
  type PoultryRawMaterialItem,
  type PoultryRawMaterialPurchase,
} from "@/lib/api/poultry-inventory"
import { MedicationLines, computeMedLines, emptyMedLine, buildMedCredit, type MedLineDraft } from "@/components/production/medication-lines"
import { FeedLines, computeFeedLines, emptyFeedLine, buildFeedCredit, type FeedLineDraft } from "@/components/production/feed-lines"
import type { ConsumptionCredit } from "@/lib/utils/raw-material-costing"

// Doc §4a: classify a raw-material item as Feed or Medication by its category.
const isFeedCategory = (c?: string | null) => !!c && /feed/i.test(c)
const isMedicationCategory = (c?: string | null) => !!c && /(medic|vaccin|drug)/i.test(c)

// Kept in sync with the add form (production-records/new).
const feedTypes = ["Starter Feed", "Grower Feed", "Layer Feed", "Broiler Feed", "Organic Feed", "Custom Mix"]

export default function EditProductionRecordPage() {
  const router = useRouter()
  const params = useParams()
  const id = Number(params.id)
  const { labels: pickLabelText, enableFourthPick } = usePickSettings()
  const [loading, setLoading] = useState(false)
  const [fetchLoading, setFetchLoading] = useState(true)
  const [error, setError] = useState("")
  const [formData, setFormData] = useState({
    ageInWeeks: "",
    ageInDays: "",
    date: "",
    noOfBirds: "",
    mortality: "",
    feedKg: "",
    feedType: "",
    medication: "",
    notes: "",
    production9AM: "",
    production12PM: "",
    production4PM: "",
    production4thPick: "",
    brokenEggs: "",
    meatyEggs: "",
    softEggs: "",
    lostEggs: "",
    eggGrade: "",
    // Feed & medication are now multiple inventory lines (migrations 147/148) —
    // see feedLines / medLines below. The manual Feed Type + Feed (kg) fields stay.
  })

  // Credit back this record's own prior consumption so editing doesn't falsely
  // block on stock the record itself is holding (set from the loaded record).
  const [feedCredit, setFeedCredit] = useState<ConsumptionCredit>({})
  const [medCredit, setMedCredit] = useState<ConsumptionCredit>({})

  // Migration 148: multiple feed lines.
  const [feedLines, setFeedLines] = useState<FeedLineDraft[]>([])
  const addFeedLine = () => setFeedLines((d) => [...d, emptyFeedLine()])
  const removeFeedLine = (idx: number) => setFeedLines((d) => d.filter((_, i) => i !== idx))
  const changeFeedLine = (idx: number, patch: Partial<FeedLineDraft>) =>
    setFeedLines((d) => d.map((row, i) => (i === idx ? { ...row, ...patch } : row)))

  // Migration 147: multiple medication lines.
  const [medLines, setMedLines] = useState<MedLineDraft[]>([])
  const addMedLine = () => setMedLines((d) => [...d, emptyMedLine()])
  const removeMedLine = (idx: number) => setMedLines((d) => d.filter((_, i) => i !== idx))
  const changeMedLine = (idx: number, patch: Partial<MedLineDraft>) =>
    setMedLines((d) => d.map((row, i) => (i === idx ? { ...row, ...patch } : row)))

  const [rawItems, setRawItems] = useState<PoultryRawMaterialItem[]>([])
  const [purchases, setPurchases] = useState<PoultryRawMaterialPurchase[]>([])
  // Flock of the record being edited (from the API, not user-editable here) —
  // needed to sync the matching FeedUsage row on save.
  const [flockId, setFlockId] = useState<number | null>(null)
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
  const totalCostOfProduction = totalFeedCost + totalMedicationCost

  useEffect(() => {
    loadRecord()
    ;(async () => {
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

  const loadRecord = async () => {
    const { userId, farmId } = getUserContext()
    const result = await getProductionRecord(id, userId, farmId)

    if (result.success && result.data) {
      const record = result.data
      const dateStr = new Date(record.date).toISOString().split("T")[0]
      const fId = (record as any).flockId ?? null
      setFlockId(fId)
      setFormData({
        ageInWeeks: String(record.ageInWeeks),
        ageInDays: String(record.ageInDays),
        date: dateStr,
        noOfBirds: String(record.noOfBirds),
        mortality: String(record.mortality),
        feedKg: String(record.feedKg),
        feedType: "",
        medication: record.medication,
        notes: (record as any).notes ?? "",
        production9AM: String(record.production9AM),
        production12PM: String(record.production12PM),
        production4PM: String(record.production4PM),
        production4thPick: String((record as any).production4thPick ?? 0),
        brokenEggs: String((record as any).brokenEggs ?? 0),
        meatyEggs: (record as any).meatyEggs == null ? "" : String((record as any).meatyEggs),
        softEggs: (record as any).softEggs == null ? "" : String((record as any).softEggs),
        lostEggs: (record as any).lostEggs == null ? "" : String((record as any).lostEggs),
        eggGrade: eggGradeFromApi((record as any).eggGrade),
      })

      // Credit = what this record already consumed (from the saved lines), so the
      // edit preview reverses it back the way the server will on save. Fall back to
      // the legacy single feed/medication column for records saved before 147/148.
      const r0 = record as any
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

      // Migration 148: hydrate the feed lines. Fall back to the legacy single-feed
      // column if an old record has no line rows yet.
      const feedRows = (record as any).feeds as
        | { specificFeedUsedId?: number | null; totalFeedConsumed?: number | null }[]
        | undefined
      if (Array.isArray(feedRows) && feedRows.length > 0) {
        setFeedLines(
          feedRows.map((f) => ({
            specificFeedUsedId: f.specificFeedUsedId == null ? "" : String(f.specificFeedUsedId),
            totalFeedConsumed: f.totalFeedConsumed == null ? "" : String(f.totalFeedConsumed),
          })),
        )
      } else if ((record as any).specificFeedUsedId != null) {
        setFeedLines([
          {
            specificFeedUsedId: String((record as any).specificFeedUsedId),
            totalFeedConsumed: (record as any).totalFeedConsumed == null ? "" : String((record as any).totalFeedConsumed),
          },
        ])
      } else {
        setFeedLines([])
      }

      // Migration 147: hydrate the medication lines. Fall back to the legacy
      // single-medication column if an old record has no line rows yet.
      const medRows = (record as any).medications as
        | { specificMedicationUsedId?: number | null; totalMedicationConsumed?: number | null }[]
        | undefined
      if (Array.isArray(medRows) && medRows.length > 0) {
        setMedLines(
          medRows.map((m) => ({
            specificMedicationUsedId: m.specificMedicationUsedId == null ? "" : String(m.specificMedicationUsedId),
            totalMedicationConsumed: m.totalMedicationConsumed == null ? "" : String(m.totalMedicationConsumed),
          })),
        )
      } else if ((record as any).specificMedicationUsedId != null) {
        setMedLines([
          {
            specificMedicationUsedId: String((record as any).specificMedicationUsedId),
            totalMedicationConsumed: (record as any).totalMedicationConsumed == null ? "" : String((record as any).totalMedicationConsumed),
          },
        ])
      } else {
        setMedLines([])
      }

      // Feed Type isn't stored on the production record — pull it from the
      // matching FeedUsage row (same flock + date) so it can be edited/re-synced.
      if (fId) {
        try {
          const fuRes = await getFeedUsages(userId, farmId)
          if (fuRes.success && fuRes.data) {
            const match = (fuRes.data as any[]).find(
              (fu) => fu.flockId === fId && new Date(fu.usageDate).toISOString().split("T")[0] === dateStr,
            )
            if (match?.feedType) setFormData((p) => ({ ...p, feedType: match.feedType }))
          }
        } catch { /* feed usage optional */ }
      }
    } else {
      setError(result.message)
    }

    setFetchLoading(false)
  }

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setFormData({ ...formData, [e.target.name]: e.target.value })
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError("")

    if (feedComputed.firstShortfall) {
      const s = feedComputed.firstShortfall
      setError(`Not enough purchased stock tracked for "${s.item?.itemName ?? "this feed"}" to cover ${s.qty} — record a new purchase first.`)
      return
    }
    if (medComputed.firstShortfall) {
      const s = medComputed.firstShortfall
      setError(`Not enough purchased stock tracked for "${s.item?.itemName ?? "this medication"}" to cover ${s.qty} — record a new purchase first.`)
      return
    }

    setLoading(true)

    const { userId, farmId } = getUserContext()

    const totalProduction =
      Number(formData.production9AM) + Number(formData.production12PM) + Number(formData.production4PM) + Number(formData.production4thPick)

    const noOfBirdsLeft = Number(formData.noOfBirds) - Number(formData.mortality)

    const record: ProductionRecordInput = {
      farmId,
      userId,
      createdBy: userId,
      updatedBy: userId,
      ageInWeeks: Number(formData.ageInWeeks),
      ageInDays: Number(formData.ageInDays),
      date: new Date(formData.date).toISOString(),
      noOfBirds: Number(formData.noOfBirds),
      mortality: Number(formData.mortality),
      noOfBirdsLeft,
      feedKg: Number(formData.feedKg),
      medication: formData.medication,
      notes: formData.notes || null,
      production9AM: Number(formData.production9AM),
      production12PM: Number(formData.production12PM),
      production4PM: Number(formData.production4PM),
      production4thPick: Number(formData.production4thPick),
      brokenEggs: Number(formData.brokenEggs) || 0,
      meatyEggs: formData.meatyEggs === "" ? null : Number(formData.meatyEggs) || 0,
      softEggs: formData.softEggs === "" ? null : Number(formData.softEggs) || 0,
      lostEggs: formData.lostEggs === "" ? null : Number(formData.lostEggs) || 0,
      totalProduction,
      eggGrade: eggGradeToApi(formData.eggGrade),
      // Migration 148: feed lines drive the aggregate columns server-side.
      specificFeedUsedId: null,
      specificFeedUsedName: null,
      feedUnitCost: null,
      totalFeedConsumed: null,
      totalFeedCost: null,
      feeds: feedComputed.feeds,
      // Migration 147: medication lines drive the aggregate columns server-side.
      specificMedicationUsedId: null,
      specificMedicationUsedName: null,
      medicationUnitCost: null,
      totalMedicationConsumed: null,
      totalMedicationCost: null,
      medications: medComputed.medications,
      totalCostOfProduction: Number(totalCostOfProduction.toFixed(2)),
    }

    const result = await updateProductionRecord(id, record)

    if (!result.success) {
      setError(result.message)
      setLoading(false)
      return
    }

    // Sync the matching FeedUsage row (create or update) — mirrors the add form.
    if (parseFloat(formData.feedKg) > 0 && flockId && formData.feedType) {
      try {
        if (userId && farmId) {
          const feedUsagesRes = await getFeedUsages(userId, farmId)
          let existingFeedUsage: any = null
          if (feedUsagesRes.success && feedUsagesRes.data) {
            existingFeedUsage = (feedUsagesRes.data as any[]).find(
              (fu) => fu.flockId === flockId && new Date(fu.usageDate).toISOString().split("T")[0] === formData.date,
            )
          }
          const feedUsageData: FeedUsageInput = {
            farmId,
            userId,
            flockId,
            usageDate: formData.date + "T00:00:00Z",
            feedType: formData.feedType,
            quantityKg: parseFloat(formData.feedKg) || 0,
          }
          if (existingFeedUsage) await updateFeedUsage(existingFeedUsage.feedUsageId, feedUsageData)
          else await createFeedUsage(feedUsageData)
        }
      } catch (feedError) {
        console.error("Error syncing feed usage:", feedError)
      }
    }

    router.push("/production-records")
  }

  const handleLogout = () => {
    localStorage.removeItem("auth_token")
    localStorage.removeItem("refresh_token")
    localStorage.removeItem("username")
    localStorage.removeItem("userId")
    localStorage.removeItem("farmId")
    localStorage.removeItem("farmName")
    localStorage.removeItem("isStaff")
    localStorage.removeItem("isSubscriber")
    router.push("/login")
  }

  if (fetchLoading) {
    return (
      <div className="flex min-h-screen bg-slate-50">
        {/* Sidebar */}
        <DashboardSidebar onLogout={handleLogout} />
        
        {/* Main Content */}
        <div className="flex-1 flex flex-col min-w-0">
          {/* Header */}
          <DashboardHeader />
          
          {/* Main Content Area */}
          <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
            <div className="flex items-center justify-center h-full">
              <div className="text-center">
                <div className="w-8 h-8 border-4 border-blue-600 border-t-transparent rounded-full animate-spin mx-auto mb-4"></div>
                <p className="text-slate-600">Loading production record...</p>
              </div>
            </div>
          </main>
        </div>
      </div>
    )
  }

  return (
    <div className="flex min-h-screen bg-slate-50">
      {/* Sidebar */}
      <DashboardSidebar onLogout={handleLogout} />
      
      {/* Main Content */}
      <div className="flex-1 flex flex-col min-w-0">
        {/* Header */}
        <DashboardHeader />
        
        {/* Main Content Area */}
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6 space-y-6">
            {/* Page Header */}
            <div className="flex items-center justify-between mb-6">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 bg-green-100 rounded-lg flex items-center justify-center">
                  <FileText className="w-5 h-5 text-green-600" />
                </div>
                <div>
                  <h1 className="text-2xl font-bold text-slate-900">Edit Egg Production Record</h1>
                  <p className="text-slate-600">Update production record details</p>
                </div>
              </div>
              <Button
                type="button"
                size="sm"
                className="gap-1.5 bg-red-600 hover:bg-red-700 text-white"
                onClick={() => router.push("/production-records")}
              >
                <X className="w-4 h-4" />
                Cancel
              </Button>
            </div>

            {/* Error Alert */}
            {error && (
              <Alert variant="destructive">
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}

            {/* Form */}
            <form onSubmit={handleSubmit} className="space-y-6">
              {/* Form Fields */}
              <div className="space-y-6">
                {/* Basic Information */}
                <div className="space-y-4">
                  <h3 className="text-lg font-semibold text-slate-900">Basic Information</h3>
                  <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                    <div className="space-y-2">
                      <Label htmlFor="date" className="text-sm font-medium text-slate-700">Date *</Label>
                      <Input
                        id="date"
                        name="date"
                        type="date"
                        value={formData.date}
                        onChange={handleChange}
                        required
                        disabled={loading}
                        className="h-11 border-slate-200 focus:border-blue-500 focus:ring-blue-500"
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="ageInWeeks" className="text-sm font-medium text-slate-700">Age in Weeks *</Label>
                      <NumberInput
                        id="ageInWeeks"
                        name="ageInWeeks"
                        
                        value={formData.ageInWeeks}
                        onChange={handleChange}
                        required
                        min="0"
                        disabled={loading}
                        className="h-11 border-slate-200 focus:border-blue-500 focus:ring-blue-500"
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="ageInDays" className="text-sm font-medium text-slate-700">Age in Days *</Label>
                      <NumberInput
                        id="ageInDays"
                        name="ageInDays"
                        
                        value={formData.ageInDays}
                        onChange={handleChange}
                        required
                        min="0"
                        disabled={loading}
                        className="h-11 border-slate-200 focus:border-blue-500 focus:ring-blue-500"
                      />
                    </div>
                  </div>
                </div>

                {/* Egg Production */}
                <div className="space-y-4">
                  <h3 className="text-lg font-semibold text-slate-900">Egg Production</h3>
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-6">
                    <div className="space-y-2">
                      <Label htmlFor="production9AM" className="text-sm font-medium text-slate-700">{pickLabelText.first} *</Label>
                      <NumberInput
                        id="production9AM"
                        name="production9AM"

                        value={formData.production9AM}
                        onChange={handleChange}
                        required
                        min="0"
                        disabled={loading}
                        className="h-11 border-slate-200 focus:border-blue-500 focus:ring-blue-500"
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="production12PM" className="text-sm font-medium text-slate-700">{pickLabelText.second} *</Label>
                      <NumberInput
                        id="production12PM"
                        name="production12PM"

                        value={formData.production12PM}
                        onChange={handleChange}
                        required
                        min="0"
                        disabled={loading}
                        className="h-11 border-slate-200 focus:border-blue-500 focus:ring-blue-500"
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="production4PM" className="text-sm font-medium text-slate-700">{pickLabelText.third} *</Label>
                      <NumberInput
                        id="production4PM"
                        name="production4PM"

                        value={formData.production4PM}
                        onChange={handleChange}
                        required
                        min="0"
                        disabled={loading}
                        className="h-11 border-slate-200 focus:border-blue-500 focus:ring-blue-500"
                      />
                    </div>
                    {(enableFourthPick || Number(formData.production4thPick) > 0) && (
                    <div className="space-y-2">
                      <Label htmlFor="production4thPick" className="text-sm font-medium text-slate-700">{pickLabelText.fourth}</Label>
                      <NumberInput
                        id="production4thPick"
                        name="production4thPick"
                        value={formData.production4thPick}
                        onChange={handleChange}
                        min="0"
                        disabled={loading}
                        className="h-11 border-slate-200 focus:border-blue-500 focus:ring-blue-500"
                      />
                    </div>
                    )}
                  </div>
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-6">
                    <div className="space-y-2">
                      <Label htmlFor="brokenEggs" className="text-sm font-medium text-red-700">Broken Eggs</Label>
                      <NumberInput
                        id="brokenEggs"
                        name="brokenEggs"

                        value={formData.brokenEggs}
                        onChange={handleChange}
                        min="0"
                        disabled={loading}
                        className="h-11 border-red-200 focus:border-red-500 focus:ring-red-500"
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="meatyEggs" className="text-sm font-medium text-amber-800">Meaty Eggs</Label>
                      <NumberInput
                        id="meatyEggs"
                        name="meatyEggs"

                        value={formData.meatyEggs}
                        onChange={handleChange}
                        min="0"
                        placeholder="—"
                        disabled={loading}
                        className="h-11 border-amber-200 focus:border-amber-500 focus:ring-amber-500"
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="softEggs" className="text-sm font-medium text-violet-800">Soft Eggs</Label>
                      <NumberInput
                        id="softEggs"
                        name="softEggs"

                        value={formData.softEggs}
                        onChange={handleChange}
                        min="0"
                        placeholder="—"
                        disabled={loading}
                        className="h-11 border-violet-200 focus:border-violet-500 focus:ring-violet-500"
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="lostEggs" className="text-sm font-medium text-slate-700">Lost Eggs</Label>
                      <NumberInput
                        id="lostEggs"
                        name="lostEggs"

                        value={formData.lostEggs}
                        onChange={handleChange}
                        min="0"
                        placeholder="—"
                        disabled={loading}
                        className="h-11 border-slate-200 focus:border-slate-500 focus:ring-slate-500"
                      />
                    </div>
                  </div>
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Egg size</Label>
                    <Select
                      value={formData.eggGrade}
                      onValueChange={(v) => setFormData((prev) => ({ ...prev, eggGrade: v }))}
                      disabled={loading}
                    >
                      <SelectTrigger className="h-11 max-w-md">
                        <SelectValue placeholder="Select grade" />
                      </SelectTrigger>
                      <SelectContent>
                        {EGG_GRADE_OPTIONS.map((o) => (
                          <SelectItem key={o.value} value={o.value}>
                            {o.label}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                </div>

                {/* Birds & Age */}
                <div className="space-y-4">
                  <h3 className="text-lg font-semibold text-slate-900">Birds &amp; Age</h3>
                  <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                    <div className="space-y-2">
                      <Label htmlFor="noOfBirds" className="text-sm font-medium text-slate-700">Number of Birds *</Label>
                      <NumberInput
                        id="noOfBirds"
                        name="noOfBirds"
                        
                        value={formData.noOfBirds}
                        onChange={handleChange}
                        required
                        min="0"
                        disabled={loading}
                        className="h-11 border-slate-200 focus:border-blue-500 focus:ring-blue-500"
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="mortality" className="text-sm font-medium text-slate-700">Deaths *</Label>
                      <NumberInput
                        id="mortality"
                        name="mortality"
                        
                        value={formData.mortality}
                        onChange={handleChange}
                        required
                        min="0"
                        disabled={loading}
                        className="h-11 border-slate-200 focus:border-blue-500 focus:ring-blue-500"
                      />
                    </div>
                    <div className="space-y-2">
                      <Label className="text-sm font-medium text-slate-700">Birds Left</Label>
                      <div className="h-11 flex items-center font-semibold text-slate-900">
                        {(Number(formData.noOfBirds) || 0) - (Number(formData.mortality) || 0)}
                      </div>
                    </div>
                  </div>
                </div>

                {/* Feed, Medication & Notes — combined with the inventory-based
                    feed/medication usage & costing (Doc §4a-4c). */}
                <div className="space-y-4">
                  <h3 className="text-lg font-semibold text-slate-900">Feed, Medication &amp; Notes</h3>
                  <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                    <div className="space-y-2">
                      <Label className="text-sm font-medium text-slate-700">Feed Type</Label>
                      <Select value={formData.feedType} onValueChange={(v) => setFormData((p) => ({ ...p, feedType: v }))}>
                        <SelectTrigger className="h-11"><SelectValue placeholder="Select feed type" /></SelectTrigger>
                        <SelectContent>
                          {feedTypes.map((type) => (
                            <SelectItem key={type} value={type}>{type}</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="feedKg" className="text-sm font-medium text-slate-700">Feed (kg) *</Label>
                      <NumberInput
                        id="feedKg"
                        name="feedKg"

                        step="0.01"
                        value={formData.feedKg}
                        onChange={handleChange}
                        required
                        min="0"
                        disabled={loading}
                        className="h-11 border-slate-200 focus:border-blue-500 focus:ring-blue-500"
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="medication" className="text-sm font-medium text-slate-700">Medication</Label>
                      <Input
                        id="medication"
                        name="medication"
                        type="text"
                        value={formData.medication}
                        onChange={handleChange}
                        placeholder="None"
                        disabled={loading}
                        className="h-11 border-slate-200 focus:border-blue-500 focus:ring-blue-500"
                      />
                    </div>
                  </div>

                  {/* Used (from inventory) — reduces Raw-Material stock on save */}
                  <div className="flex items-center gap-2 pt-1">
                    <div className="h-px flex-1 bg-slate-200" />
                    <span className="text-xs font-semibold uppercase tracking-wide text-emerald-700">Used (from inventory)</span>
                    <div className="h-px flex-1 bg-slate-200" />
                  </div>

                  <div className="grid grid-cols-12 gap-4">
                    <div className="col-span-12 flex items-center gap-2">
                      <span className="text-xs font-semibold uppercase tracking-wide text-slate-500">Feed lines</span>
                    </div>
                    <FeedLines
                      lines={feedLines}
                      rows={feedComputed.rows}
                      feedItems={feedItems}
                      stockByItemId={feedComputed.pendingStockByItemId}
                      onAdd={addFeedLine}
                      onRemove={removeFeedLine}
                      onChange={changeFeedLine}
                      disabled={loading}
                    />
                    <div className="col-span-12 flex items-center justify-between rounded-lg bg-slate-50 border border-slate-200 px-4 py-2">
                      <span className="text-sm font-medium text-slate-700">Total Feed Cost</span>
                      <span className="text-base font-semibold text-slate-800">{totalFeedCost.toFixed(2)}</span>
                    </div>

                    <div className="col-span-12 flex items-center gap-2">
                      <span className="text-xs font-semibold uppercase tracking-wide text-slate-500">Medication lines</span>
                    </div>
                    <MedicationLines
                      lines={medLines}
                      rows={medComputed.rows}
                      medItems={medItems}
                      stockByItemId={medComputed.pendingStockByItemId}
                      onAdd={addMedLine}
                      onRemove={removeMedLine}
                      onChange={changeMedLine}
                      disabled={loading}
                    />
                    <div className="col-span-12 flex items-center justify-between rounded-lg bg-slate-50 border border-slate-200 px-4 py-2">
                      <span className="text-sm font-medium text-slate-700">Total Medication Cost</span>
                      <span className="text-base font-semibold text-slate-800">{totalMedicationCost.toFixed(2)}</span>
                    </div>

                    <div className="col-span-12 flex items-center justify-between rounded-lg bg-emerald-50 border border-emerald-200 px-4 py-3">
                      <span className="text-sm font-medium text-emerald-800">Total Cost of Production</span>
                      <span className="text-lg font-bold text-emerald-800">{totalCostOfProduction.toFixed(2)}</span>
                    </div>

                    <div className="col-span-12 space-y-2">
                      <Label htmlFor="notes" className="text-sm font-medium text-slate-700">Notes</Label>
                      <Textarea
                        id="notes"
                        name="notes"
                        rows={3}
                        value={formData.notes}
                        onChange={(e) => setFormData((p) => ({ ...p, notes: e.target.value }))}
                        disabled={loading}
                        className="border-slate-200 focus:border-blue-500 focus:ring-blue-500"
                      />
                    </div>
                  </div>
                </div>
              </div>

              {/* Form Actions */}
              <div className="flex gap-4">
                <Button
                  type="button"
                  className="flex-1 h-11 bg-red-600 hover:bg-red-700 text-white"
                  disabled={loading}
                  onClick={() => router.push("/production-records")}
                >
                  Cancel
                </Button>
                <Button
                  type="submit"
                  className="flex-1 h-11 bg-blue-600 hover:bg-blue-700"
                  disabled={loading}
                >
                  {loading ? "Updating..." : "Update Record"}
                </Button>
              </div>
            </form>
          </div>
        </main>
      </div>
    </div>
  )
}