"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter, useParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Textarea } from "@/components/ui/textarea"
import { Egg } from "lucide-react"
import { getEggProduction, updateEggProduction, type EggProductionInput } from "@/lib/api/egg-production"
import { usePickSettings } from "@/hooks/use-pick-settings"
import { EGG_GRADE_OPTIONS, EGG_GRADE_SELECT_VALUE_NONE, eggGradeFromApi, eggGradeToApi } from "@/lib/constants/egg-grade"
import { getFlockBatches, type FlockBatch } from "@/lib/api/flock-batch"
import { getUserContext } from "@/lib/utils/user-context"
import { getProductionRecords, createProductionRecord, updateProductionRecord, type ProductionRecordInput } from "@/lib/api/production-record"
import { getFlocks } from "@/lib/api/flock"

export default function EditEggProductionPage() {
  const router = useRouter()
  const params = useParams()
  const productionId = params.id as string
  const { labels: pickLabelText, enableFourthPick } = usePickSettings()

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState("")
  const [flockBatches, setFlockBatches] = useState<FlockBatch[]>([])
  const [flocks, setFlocks] = useState<any[]>([])

  const [formData, setFormData] = useState<Partial<EggProductionInput>>({
    flockId: 0,
    productionDate: "",
    eggCount: 0,
    production9AM: 0,
    production12PM: 0,
    production4PM: 0,
    production4thPick: 0,
    brokenEggs: 0,
    notes: "",
    eggGrade: EGG_GRADE_SELECT_VALUE_NONE,
  })

  // Crate-based egg entry state for each pick
  const EGGS_PER_CRATE = 30
  const [morningCrates, setMorningCrates] = useState(0)
  const [morningLoose, setMorningLoose] = useState(0)
  const [noonCrates, setNoonCrates] = useState(0)
  const [noonLoose, setNoonLoose] = useState(0)
  const [eveningCrates, setEveningCrates] = useState(0)
  const [eveningLoose, setEveningLoose] = useState(0)
  const [fourthCrates, setFourthCrates] = useState(0)
  const [fourthLoose, setFourthLoose] = useState(0)

  const morningTotal = (morningCrates * EGGS_PER_CRATE) + morningLoose
  const noonTotal = (noonCrates * EGGS_PER_CRATE) + noonLoose
  const eveningTotal = (eveningCrates * EGGS_PER_CRATE) + eveningLoose
  const fourthTotal = (fourthCrates * EGGS_PER_CRATE) + fourthLoose

  // Sync crate values into formData
  useEffect(() => {
    setFormData(prev => ({ ...prev, production9AM: morningTotal }))
  }, [morningTotal])
  useEffect(() => {
    setFormData(prev => ({ ...prev, production12PM: noonTotal }))
  }, [noonTotal])
  useEffect(() => {
    setFormData(prev => ({ ...prev, production4PM: eveningTotal }))
  }, [eveningTotal])
  useEffect(() => {
    setFormData(prev => ({ ...prev, production4thPick: fourthTotal }))
  }, [fourthTotal])

  const totalProduction = useMemo(() => {
    return (formData.production9AM || 0) + (formData.production12PM || 0) + (formData.production4PM || 0) + (formData.production4thPick || 0);
  }, [formData.production9AM, formData.production12PM, formData.production4PM, formData.production4thPick]);
  const totalCrates = Math.floor(totalProduction / EGGS_PER_CRATE)
  const totalPieces = totalProduction % EGGS_PER_CRATE

  useEffect(() => {
    load()
  }, [productionId])

  const load = async () => {
    const { farmId, userId } = getUserContext()
    
    if (!farmId || !userId) {
      setError("Farm ID or User ID not found")
      setLoading(false)
      return
    }

    const [eggProductionRes, batchesRes, flocksRes] = await Promise.all([
        getEggProduction(parseInt(productionId), userId, farmId),
        getFlockBatches(userId, farmId),
        getFlocks(userId, farmId)
    ])

    // Set flock batches first so we can use them for matching
    let batches: FlockBatch[] = []
    if(batchesRes.success && batchesRes.data) {
        batches = batchesRes.data
        setFlockBatches(batches)
    }

    // Set flocks for the dropdown
    let flocksList: any[] = []
    if(flocksRes.success && flocksRes.data) {
        flocksList = flocksRes.data
        setFlocks(flocksList)
    }

    if (eggProductionRes.success && eggProductionRes.data) {
      const eggProd = eggProductionRes.data
      
      // Try to find the matching flock
      let matchedFlockId = eggProd.flockId
      
      // If we have a flockName, try to match by name (more reliable)
      if (eggProd.flockName && flocksList.length > 0) {
        const matchedFlock = flocksList.find(
          (f: any) => f.name?.toLowerCase() === eggProd.flockName?.toLowerCase() ||
               f.flockId === eggProd.flockId
        )
        if (matchedFlock) {
          matchedFlockId = matchedFlock.flockId
        }
      }
      
      // Also check if the flockId directly matches a flock
      const directMatch = flocksList.find((f: any) => f.flockId === eggProd.flockId)
      if (directMatch) {
        matchedFlockId = directMatch.flockId
      }
      
      console.log("[v0] Edit: Original flockId:", eggProd.flockId, "FlockName:", eggProd.flockName, "Matched to flockId:", matchedFlockId)
      
      setFormData({
        ...eggProd,
        flockId: matchedFlockId,
        productionDate: eggProd.productionDate.split("T")[0],
        eggGrade: eggGradeFromApi(eggProd.eggGrade),
      })
      // Decompose stored totals into crates + loose
      const m = eggProd.production9AM ?? 0
      const n = eggProd.production12PM ?? 0
      const ev = eggProd.production4PM ?? 0
      const fp = (eggProd as any).production4thPick ?? 0
      setMorningCrates(Math.floor(m / EGGS_PER_CRATE)); setMorningLoose(m % EGGS_PER_CRATE)
      setNoonCrates(Math.floor(n / EGGS_PER_CRATE)); setNoonLoose(n % EGGS_PER_CRATE)
      setEveningCrates(Math.floor(ev / EGGS_PER_CRATE)); setEveningLoose(ev % EGGS_PER_CRATE)
      setFourthCrates(Math.floor(fp / EGGS_PER_CRATE)); setFourthLoose(fp % EGGS_PER_CRATE)
    } else {
      setError(eggProductionRes.message || "Failed to load production data")
    }
    
    setLoading(false)
  }

  const handleInputChange = (field: keyof EggProductionInput, value: string | number) => {
    setFormData(prev => ({
      ...prev,
      [field]: value
    }))
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    const { farmId, userId } = getUserContext()
    
    if (!farmId || !userId) {
      setError("Farm ID or User ID not found")
      return
    }

    if (!formData.flockId || formData.flockId <= 0) {
      setError("Choose which flock this egg record is for.")
      return
    }

    // Client-side validation for production numbers
    if (formData.production9AM === null || formData.production9AM === undefined || isNaN(formData.production9AM) || formData.production9AM < 0) {
      setError("1st Pick must be a non-negative number.")
      return
    }
    if (formData.production12PM === null || formData.production12PM === undefined || isNaN(formData.production12PM) || formData.production12PM < 0) {
      setError("2nd Pick must be a non-negative number.")
      return
    }
    if (formData.production4PM === null || formData.production4PM === undefined || isNaN(formData.production4PM) || formData.production4PM < 0) {
      setError("3rd Pick must be a non-negative number.")
      return
    }

    setSaving(true)
    setError("")

    const result = await updateEggProduction(parseInt(productionId), {
      ...formData,
      eggCount: totalProduction,
      totalProduction,
      farmId,
      userId,
      eggGrade: eggGradeToApi((formData.eggGrade as string) ?? EGG_GRADE_SELECT_VALUE_NONE),
    })
    
    if (result.success) {
      // Sync to production records
      try {
        const prodRecordsRes = await getProductionRecords(userId, farmId)
        const flocksRes = await getFlocks(userId, farmId)
        const flock = flocksRes.success && flocksRes.data 
          ? flocksRes.data.find((f: any) => f.flockId === formData.flockId || f.batchId === formData.flockId)
          : null

        if (prodRecordsRes.success && prodRecordsRes.data) {
          const matchingRecord = prodRecordsRes.data.find(
            (pr: any) => (pr.flockId === formData.flockId || (flock && pr.flockId === flock.flockId)) &&
            new Date(pr.date).toISOString().split('T')[0] === formData.productionDate
          )

          if (matchingRecord) {
            // Update existing production record with egg production data
            const updateData: Partial<ProductionRecordInput> = {
              production9AM: formData.production9AM || 0,
              production12PM: formData.production12PM || 0,
              production4PM: formData.production4PM || 0,
              production4thPick: formData.production4thPick || 0,
              totalProduction: totalProduction,
              eggGrade: eggGradeToApi((formData.eggGrade as string) ?? EGG_GRADE_SELECT_VALUE_NONE),
            }
            await updateProductionRecord(matchingRecord.id, updateData)
          }
        }
      } catch (syncError) {
        console.error("Error syncing to production records:", syncError)
        // Don't fail the whole operation if sync fails
      }

      router.push("/egg-production")
    } else {
      setError(result.message || "An unknown error occurred")
      setSaving(false)
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

  if (loading) {
    return (
      <div className="flex min-h-screen bg-slate-50">
        <DashboardSidebar onLogout={handleLogout} />
        <div className="flex-1 flex flex-col min-w-0">
          <DashboardHeader />
          <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
            <div className="space-y-6 space-y-6">
              <div className="animate-pulse">
                <div className="h-10 w-1/2 bg-slate-200 rounded mb-6"></div>
                <div className="p-6 bg-white rounded-lg shadow-sm space-y-4">
                  <div className="h-4 bg-slate-200 rounded w-1/4 mb-4"></div>
                  <div className="grid grid-cols-2 gap-6">
                    <div className="h-11 bg-slate-200 rounded"></div>
                    <div className="h-11 bg-slate-200 rounded"></div>
                    <div className="h-11 bg-slate-200 rounded"></div>
                    <div className="h-11 bg-slate-200 rounded"></div>
                  </div>
                </div>
              </div>
            </div>
          </main>
        </div>
      </div>
    )
  }

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6 space-y-6">
            {/* Page Header */}
            <div className="flex items-center gap-3 mb-6">
              <div className="w-10 h-10 bg-yellow-100 rounded-lg flex items-center justify-center">
                <Egg className="w-5 h-5 text-yellow-600" />
              </div>
              <div>
                <h1 className="text-2xl font-bold text-slate-900">Edit Production Record</h1>
                <p className="text-slate-600">Update the egg production details below</p>
              </div>
            </div>

            {/* Error Alert */}
            {error && (
              <Alert variant="destructive">
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}

            {/* Form */}
            <form onSubmit={handleSubmit} className="space-y-6">
              <div className="space-y-4 p-6 bg-white rounded-lg shadow-sm">
                <h3 className="text-lg font-semibold text-slate-900">Production Details</h3>
                
                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div className="space-y-2">
                    <Label htmlFor="flockId">Flock *</Label>
                    <Select
                      value={formData.flockId?.toString()}
                      onValueChange={(value) => handleInputChange("flockId", parseInt(value))}
                      disabled={saving}
                    >
                      <SelectTrigger>
                        <SelectValue placeholder="Select a flock" />
                      </SelectTrigger>
                      <SelectContent>
                        {flocks.map((flock: any) => (
                          <SelectItem key={flock.flockId} value={flock.flockId.toString()}>
                            {flock.name}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="productionDate">Production Date *</Label>
                    <Input
                      id="productionDate"
                      type="date"
                      value={formData.productionDate}
                      onChange={(e) => handleInputChange("productionDate", e.target.value)}
                      required
                      disabled={saving}
                    />
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="totalProduction">Total Eggs Collected</Label>
                    <NumberInput
                      id="totalProduction"
                      
                      min="0"
                      value={totalProduction}
                      disabled
                    />
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="brokenEggs">Broken Eggs</Label>
                    <NumberInput
                      id="brokenEggs"
                      
                      min="0"
                      value={formData.brokenEggs}
                      onChange={(e) => handleInputChange("brokenEggs", parseInt(e.target.value) || 0)}
                      disabled={saving}
                    />
                  </div>

                  <div className="space-y-2 md:col-span-2">
                    <Label>Egg size (slot / sort)</Label>
                    <Select
                      value={(formData.eggGrade as string) ?? EGG_GRADE_SELECT_VALUE_NONE}
                      onValueChange={(v) => handleInputChange("eggGrade", v)}
                      disabled={saving}
                    >
                      <SelectTrigger>
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
                    <p className="text-xs text-slate-500">
                      One grade per record. For another grade the same day, add a separate production row.
                    </p>
                  </div>
                </div>

                {/* Morning (9 AM) - Crates + Loose */}
                <div className="p-3 bg-blue-50 border border-blue-200 rounded-lg space-y-2 mt-4">
                  <Label className="text-blue-800 font-semibold">{pickLabelText.first} — Crates × {EGGS_PER_CRATE} + Loose Eggs</Label>
                  <div className="grid grid-cols-3 gap-3">
                    <div className="space-y-1">
                      <Label className="text-xs">Crates</Label>
                      <NumberInput min="0" value={morningCrates} onChange={(e) => setMorningCrates(parseInt(e.target.value) || 0)} disabled={saving} />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs">Loose Eggs</Label>
                      <NumberInput min="0" max="29" value={morningLoose} onChange={(e) => setMorningLoose(parseInt(e.target.value) || 0)} disabled={saving} />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs">Total</Label>
                      <div className="h-10 px-3 py-2 bg-white border rounded-md flex items-center font-bold text-blue-700">{morningTotal.toLocaleString()}</div>
                    </div>
                  </div>
                  <p className="text-xs text-blue-600">{morningCrates} crates × {EGGS_PER_CRATE} + {morningLoose} loose = {morningTotal.toLocaleString()} eggs</p>
                </div>

                {/* Noon (12 PM) - Crates + Loose */}
                <div className="p-3 bg-orange-50 border border-orange-200 rounded-lg space-y-2">
                  <Label className="text-orange-800 font-semibold">{pickLabelText.second} — Crates × {EGGS_PER_CRATE} + Loose Eggs</Label>
                  <div className="grid grid-cols-3 gap-3">
                    <div className="space-y-1">
                      <Label className="text-xs">Crates</Label>
                      <NumberInput min="0" value={noonCrates} onChange={(e) => setNoonCrates(parseInt(e.target.value) || 0)} disabled={saving} />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs">Loose Eggs</Label>
                      <NumberInput min="0" max="29" value={noonLoose} onChange={(e) => setNoonLoose(parseInt(e.target.value) || 0)} disabled={saving} />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs">Total</Label>
                      <div className="h-10 px-3 py-2 bg-white border rounded-md flex items-center font-bold text-orange-700">{noonTotal.toLocaleString()}</div>
                    </div>
                  </div>
                  <p className="text-xs text-orange-600">{noonCrates} crates × {EGGS_PER_CRATE} + {noonLoose} loose = {noonTotal.toLocaleString()} eggs</p>
                </div>

                {/* 3rd Pick - Crates + Loose */}
                <div className="p-3 bg-purple-50 border border-purple-200 rounded-lg space-y-2">
                  <Label className="text-purple-800 font-semibold">{pickLabelText.third} — Crates × {EGGS_PER_CRATE} + Loose Eggs</Label>
                  <div className="grid grid-cols-3 gap-3">
                    <div className="space-y-1">
                      <Label className="text-xs">Crates</Label>
                      <NumberInput min="0" value={eveningCrates} onChange={(e) => setEveningCrates(parseInt(e.target.value) || 0)} disabled={saving} />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs">Loose Eggs</Label>
                      <NumberInput min="0" max="29" value={eveningLoose} onChange={(e) => setEveningLoose(parseInt(e.target.value) || 0)} disabled={saving} />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs">Total</Label>
                      <div className="h-10 px-3 py-2 bg-white border rounded-md flex items-center font-bold text-purple-700">{eveningTotal.toLocaleString()}</div>
                    </div>
                  </div>
                  <p className="text-xs text-purple-600">{eveningCrates} crates × {EGGS_PER_CRATE} + {eveningLoose} loose = {eveningTotal.toLocaleString()} eggs</p>
                </div>

                {/* 4th Pick — hidden when the farm has it disabled and there's no value yet. */}
                {(enableFourthPick || fourthTotal > 0) && (
                <div className="p-3 bg-teal-50 border border-teal-200 rounded-lg space-y-2">
                  <Label className="text-teal-800 font-semibold">{pickLabelText.fourth} — Crates × {EGGS_PER_CRATE} + Loose Eggs</Label>
                  <div className="grid grid-cols-3 gap-3">
                    <div className="space-y-1">
                      <Label className="text-xs">Crates</Label>
                      <NumberInput min="0" value={fourthCrates} onChange={(e) => setFourthCrates(parseInt(e.target.value) || 0)} disabled={saving} />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs">Loose Eggs</Label>
                      <NumberInput min="0" max="29" value={fourthLoose} onChange={(e) => setFourthLoose(parseInt(e.target.value) || 0)} disabled={saving} />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs">Total</Label>
                      <div className="h-10 px-3 py-2 bg-white border rounded-md flex items-center font-bold text-teal-700">{fourthTotal.toLocaleString()}</div>
                    </div>
                  </div>
                  <p className="text-xs text-teal-600">{fourthCrates} crates × {EGGS_PER_CRATE} + {fourthLoose} loose = {fourthTotal.toLocaleString()} eggs</p>
                </div>
                )}

                {/* Total Eggs Summary */}
                <div className="p-3 bg-emerald-50 border border-emerald-200 rounded-lg">
                  <div className="flex items-center justify-between">
                    <Label className="text-emerald-800 font-semibold">Total Eggs</Label>
                    <div className="text-right">
                      <div className="text-lg font-bold text-emerald-700">{totalProduction.toLocaleString()} eggs</div>
                      <div className="text-xs text-emerald-600">{totalCrates} crates + {totalPieces} pieces</div>
                    </div>
                  </div>
                </div>

                <div className="space-y-2 pt-4">
                    <Label htmlFor="notes">Notes</Label>
                    <Textarea id="notes" value={formData.notes} onChange={(e) => handleInputChange("notes", e.target.value)} disabled={saving} />
                </div>
              </div>

              {/* Form Actions */}
              <div className="flex gap-4">
                <Button
                  type="button"
                  className="flex-1 h-11 bg-red-600 hover:bg-red-700 text-white"
                  disabled={saving}
                  onClick={() => router.push("/egg-production")}
                >
                  Cancel
                </Button>
                <Button
                  type="submit"
                  className="flex-1 h-11 bg-blue-600 hover:bg-blue-700"
                  disabled={saving}
                >
                  {saving ? "Updating..." : "Update Record"}
                </Button>
              </div>
            </form>
          </div>
        </main>
      </div>
    </div>
  )
}