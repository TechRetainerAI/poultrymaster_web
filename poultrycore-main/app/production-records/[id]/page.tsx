"use client"

import type React from "react"

import { useEffect, useState } from "react"
import { useRouter, useParams } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { EGG_GRADE_OPTIONS, eggGradeFromApi, eggGradeToApi } from "@/lib/constants/egg-grade"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { FileText, X } from "lucide-react"
import { getProductionRecord, updateProductionRecord, type ProductionRecordInput } from "@/lib/api/production-record"
import { getUserContext } from "@/lib/utils/user-context"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { useMemo } from "react"
import {
  listPoultryRawMaterialItems,
  listPoultryRawMaterialPurchases,
  type PoultryRawMaterialItem,
} from "@/lib/api/poultry-inventory"

// Doc §4a: classify a raw-material item as Feed or Medication by its category.
const isFeedCategory = (c?: string | null) => !!c && /feed/i.test(c)
const isMedicationCategory = (c?: string | null) => !!c && /(medic|vaccin|drug)/i.test(c)

export default function EditProductionRecordPage() {
  const router = useRouter()
  const params = useParams()
  const id = Number(params.id)
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
    medication: "",
    production9AM: "",
    production12PM: "",
    production4PM: "",
    brokenEggs: "",
    meatyEggs: "",
    softEggs: "",
    lostEggs: "",
    eggGrade: "",
    // Doc §4a-4c: feed/medication consumed from inventory + costing.
    specificFeedUsedId: "",
    feedUnitCost: "",
    totalFeedConsumed: "",
    specificMedicationUsedId: "",
    medicationUnitCost: "",
    totalMedicationConsumed: "",
  })

  const [rawItems, setRawItems] = useState<PoultryRawMaterialItem[]>([])
  const [latestCost, setLatestCost] = useState<Record<number, number>>({})
  const feedItems = useMemo(() => rawItems.filter((i) => isFeedCategory(i.category)), [rawItems])
  const medItems = useMemo(() => rawItems.filter((i) => isMedicationCategory(i.category)), [rawItems])
  const totalFeedCost = useMemo(() => (parseFloat(formData.feedUnitCost) || 0) * (parseFloat(formData.totalFeedConsumed) || 0), [formData.feedUnitCost, formData.totalFeedConsumed])
  const totalMedicationCost = useMemo(() => (parseFloat(formData.medicationUnitCost) || 0) * (parseFloat(formData.totalMedicationConsumed) || 0), [formData.medicationUnitCost, formData.totalMedicationConsumed])
  const totalCostOfProduction = totalFeedCost + totalMedicationCost

  useEffect(() => {
    loadRecord()
    ;(async () => {
      try {
        const [items, purchases] = await Promise.all([
          listPoultryRawMaterialItems().catch(() => []),
          listPoultryRawMaterialPurchases().catch(() => []),
        ])
        setRawItems(Array.isArray(items) ? items : [])
        const byItemLatest: Record<number, { date: string; cost: number }> = {}
        for (const p of (Array.isArray(purchases) ? purchases : [])) {
          const iid = p.poultryRawMaterialItemId
          const cost = (p.productionUnitCost ?? p.unitCost) || 0
          const prev = byItemLatest[iid]
          if (!prev || (p.purchaseDate || "") >= prev.date) byItemLatest[iid] = { date: p.purchaseDate || "", cost }
        }
        const map: Record<number, number> = {}
        for (const [iid, v] of Object.entries(byItemLatest)) map[Number(iid)] = v.cost
        setLatestCost(map)
      } catch { /* inventory optional */ }
    })()
  }, [])

  const loadRecord = async () => {
    const { userId, farmId } = getUserContext()
    const result = await getProductionRecord(id, userId, farmId)

    if (result.success && result.data) {
      const record = result.data
      setFormData({
        ageInWeeks: String(record.ageInWeeks),
        ageInDays: String(record.ageInDays),
        date: new Date(record.date).toISOString().split("T")[0],
        noOfBirds: String(record.noOfBirds),
        mortality: String(record.mortality),
        feedKg: String(record.feedKg),
        medication: record.medication,
        production9AM: String(record.production9AM),
        production12PM: String(record.production12PM),
        production4PM: String(record.production4PM),
        brokenEggs: String((record as any).brokenEggs ?? 0),
        meatyEggs: (record as any).meatyEggs == null ? "" : String((record as any).meatyEggs),
        softEggs: (record as any).softEggs == null ? "" : String((record as any).softEggs),
        lostEggs: (record as any).lostEggs == null ? "" : String((record as any).lostEggs),
        eggGrade: eggGradeFromApi((record as any).eggGrade),
        specificFeedUsedId: (record as any).specificFeedUsedId == null ? "" : String((record as any).specificFeedUsedId),
        feedUnitCost: (record as any).feedUnitCost == null ? "" : String((record as any).feedUnitCost),
        totalFeedConsumed: (record as any).totalFeedConsumed == null ? "" : String((record as any).totalFeedConsumed),
        specificMedicationUsedId: (record as any).specificMedicationUsedId == null ? "" : String((record as any).specificMedicationUsedId),
        medicationUnitCost: (record as any).medicationUnitCost == null ? "" : String((record as any).medicationUnitCost),
        totalMedicationConsumed: (record as any).totalMedicationConsumed == null ? "" : String((record as any).totalMedicationConsumed),
      })
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
    setLoading(true)
    setError("")

    const { userId, farmId } = getUserContext()

    const totalProduction =
      Number(formData.production9AM) + Number(formData.production12PM) + Number(formData.production4PM)

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
      production9AM: Number(formData.production9AM),
      production12PM: Number(formData.production12PM),
      production4PM: Number(formData.production4PM),
      brokenEggs: Number(formData.brokenEggs) || 0,
      meatyEggs: formData.meatyEggs === "" ? null : Number(formData.meatyEggs) || 0,
      softEggs: formData.softEggs === "" ? null : Number(formData.softEggs) || 0,
      lostEggs: formData.lostEggs === "" ? null : Number(formData.lostEggs) || 0,
      totalProduction,
      eggGrade: eggGradeToApi(formData.eggGrade),
      specificFeedUsedId: formData.specificFeedUsedId ? Number(formData.specificFeedUsedId) : null,
      specificFeedUsedName: formData.specificFeedUsedId ? (feedItems.find((i) => String(i.poultryRawMaterialItemId) === formData.specificFeedUsedId)?.itemName ?? null) : null,
      feedUnitCost: formData.feedUnitCost === "" ? null : Number(formData.feedUnitCost) || 0,
      totalFeedConsumed: formData.totalFeedConsumed === "" ? null : Number(formData.totalFeedConsumed) || 0,
      totalFeedCost: formData.specificFeedUsedId ? Number(totalFeedCost.toFixed(2)) : null,
      specificMedicationUsedId: formData.specificMedicationUsedId ? Number(formData.specificMedicationUsedId) : null,
      specificMedicationUsedName: formData.specificMedicationUsedId ? (medItems.find((i) => String(i.poultryRawMaterialItemId) === formData.specificMedicationUsedId)?.itemName ?? null) : null,
      medicationUnitCost: formData.medicationUnitCost === "" ? null : Number(formData.medicationUnitCost) || 0,
      totalMedicationConsumed: formData.totalMedicationConsumed === "" ? null : Number(formData.totalMedicationConsumed) || 0,
      totalMedicationCost: formData.specificMedicationUsedId ? Number(totalMedicationCost.toFixed(2)) : null,
      totalCostOfProduction: Number(totalCostOfProduction.toFixed(2)),
    }

    const result = await updateProductionRecord(id, record)

    if (result.success) {
      router.push("/production-records")
    } else {
      setError(result.message)
      setLoading(false)
    }
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
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
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
                        className="h-11 max-w-[220px] border-slate-200 focus:border-blue-500 focus:ring-blue-500"
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
                  <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                    <div className="space-y-2">
                      <Label htmlFor="production9AM" className="text-sm font-medium text-slate-700">9 AM *</Label>
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
                      <Label htmlFor="production12PM" className="text-sm font-medium text-slate-700">12 PM *</Label>
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
                      <Label htmlFor="production4PM" className="text-sm font-medium text-slate-700">4 PM *</Label>
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
                    <div className="space-y-2 md:col-span-3">
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

                {/* Feed, Medication & Notes */}
                <div className="space-y-4">
                  <h3 className="text-lg font-semibold text-slate-900">Feed, Medication &amp; Notes</h3>
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
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
                </div>

                {/* Doc §4a-4c: Feed & Medication used from inventory + costing */}
                <div className="space-y-4">
                  <h3 className="text-lg font-semibold text-slate-900">Feed &amp; Medication Used (from inventory)</h3>
                  <div className="grid grid-cols-12 gap-4">
                    <div className="col-span-12 md:col-span-4 space-y-2">
                      <Label className="text-sm font-medium text-slate-700">Specific Feed Used</Label>
                      <Select value={formData.specificFeedUsedId || "none"} onValueChange={(v) => {
                        const iid = v === "none" ? "" : v
                        const cost = iid ? (latestCost[Number(iid)] ?? (Number(formData.feedUnitCost) || 0)) : 0
                        setFormData((p) => ({ ...p, specificFeedUsedId: iid, feedUnitCost: iid ? String(cost) : "" }))
                      }}>
                        <SelectTrigger className="h-11"><SelectValue placeholder="Select feed from inventory" /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="none">None</SelectItem>
                          {feedItems.map((i) => (
                            <SelectItem key={i.poultryRawMaterialItemId} value={String(i.poultryRawMaterialItemId)}>{i.itemName}{i.unitOfMeasure ? ` (${i.unitOfMeasure})` : ""} · {i.currentQuantity} in stock</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                    <div className="col-span-6 md:col-span-2 space-y-2">
                      <Label className="text-sm font-medium text-slate-700">Feed Consumed</Label>
                      <NumberInput step="0.001" min="0" value={formData.totalFeedConsumed} onChange={(e) => setFormData((p) => ({ ...p, totalFeedConsumed: e.target.value }))} className="h-11" />
                    </div>
                    <div className="col-span-6 md:col-span-3 space-y-2">
                      <Label className="text-sm font-medium text-slate-700">Feed Unit Cost</Label>
                      <NumberInput step="0.0001" min="0" value={formData.feedUnitCost} onChange={(e) => setFormData((p) => ({ ...p, feedUnitCost: e.target.value }))} className="h-11" />
                    </div>
                    <div className="col-span-12 md:col-span-3 space-y-2">
                      <Label className="text-sm font-medium text-slate-700">Total Feed Cost</Label>
                      <div className="h-11 flex items-center px-3 rounded-md border border-slate-200 bg-slate-50 font-semibold text-slate-700">{totalFeedCost.toFixed(2)}</div>
                    </div>

                    <div className="col-span-12 md:col-span-4 space-y-2">
                      <Label className="text-sm font-medium text-slate-700">Specific Medication Used</Label>
                      <Select value={formData.specificMedicationUsedId || "none"} onValueChange={(v) => {
                        const iid = v === "none" ? "" : v
                        const cost = iid ? (latestCost[Number(iid)] ?? (Number(formData.medicationUnitCost) || 0)) : 0
                        setFormData((p) => ({ ...p, specificMedicationUsedId: iid, medicationUnitCost: iid ? String(cost) : "" }))
                      }}>
                        <SelectTrigger className="h-11"><SelectValue placeholder="Select medication from inventory" /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="none">None</SelectItem>
                          {medItems.map((i) => (
                            <SelectItem key={i.poultryRawMaterialItemId} value={String(i.poultryRawMaterialItemId)}>{i.itemName}{i.unitOfMeasure ? ` (${i.unitOfMeasure})` : ""} · {i.currentQuantity} in stock</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                    <div className="col-span-6 md:col-span-2 space-y-2">
                      <Label className="text-sm font-medium text-slate-700">Medication Consumed</Label>
                      <NumberInput step="0.001" min="0" value={formData.totalMedicationConsumed} onChange={(e) => setFormData((p) => ({ ...p, totalMedicationConsumed: e.target.value }))} className="h-11" />
                    </div>
                    <div className="col-span-6 md:col-span-3 space-y-2">
                      <Label className="text-sm font-medium text-slate-700">Medication Unit Cost</Label>
                      <NumberInput step="0.0001" min="0" value={formData.medicationUnitCost} onChange={(e) => setFormData((p) => ({ ...p, medicationUnitCost: e.target.value }))} className="h-11" />
                    </div>
                    <div className="col-span-12 md:col-span-3 space-y-2">
                      <Label className="text-sm font-medium text-slate-700">Total Medication Cost</Label>
                      <div className="h-11 flex items-center px-3 rounded-md border border-slate-200 bg-slate-50 font-semibold text-slate-700">{totalMedicationCost.toFixed(2)}</div>
                    </div>

                    <div className="col-span-12 flex items-center justify-between rounded-lg bg-emerald-50 border border-emerald-200 px-4 py-3">
                      <span className="text-sm font-medium text-emerald-800">Total Cost of Production</span>
                      <span className="text-lg font-bold text-emerald-800">{totalCostOfProduction.toFixed(2)}</span>
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