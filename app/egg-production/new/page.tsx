"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Textarea } from "@/components/ui/textarea"
import { Egg } from "lucide-react"
import { createEggProduction, type EggProductionInput } from "@/lib/api/egg-production"
import { getFlockBatches, type FlockBatch } from "@/lib/api/flock-batch"
import { getUserContext } from "@/lib/utils/user-context"
import { getProductionRecords, createProductionRecord, updateProductionRecord, type ProductionRecordInput } from "@/lib/api/production-record"
import { getFlocks } from "@/lib/api/flock"

export default function NewEggProductionPage() {
  const router = useRouter()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState("")
  const [flockBatches, setFlockBatches] = useState<FlockBatch[]>([])
  const [flocks, setFlocks] = useState<any[]>([])

  const [formData, setFormData] = useState<Omit<EggProductionInput, 'farmId' | 'userId' | 'totalProduction'>>({
    flockId: 0,
    productionDate: new Date().toISOString().split('T')[0],
    eggCount: 0,
    production9AM: 0,
    production12PM: 0,
    production4PM: 0,
    brokenEggs: 0,
    notes: "",
  })

  // Crate-based egg entry state for each time slot
  const EGGS_PER_CRATE = 30
  const [morningCrates, setMorningCrates] = useState(0)
  const [morningLoose, setMorningLoose] = useState(0)
  const [noonCrates, setNoonCrates] = useState(0)
  const [noonLoose, setNoonLoose] = useState(0)
  const [eveningCrates, setEveningCrates] = useState(0)
  const [eveningLoose, setEveningLoose] = useState(0)

  const morningTotal = (morningCrates * EGGS_PER_CRATE) + morningLoose
  const noonTotal = (noonCrates * EGGS_PER_CRATE) + noonLoose
  const eveningTotal = (eveningCrates * EGGS_PER_CRATE) + eveningLoose

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

  const totalProduction = useMemo(() => {
    return formData.production9AM + formData.production12PM + formData.production4PM;
  }, [formData.production9AM, formData.production12PM, formData.production4PM]);
  const totalCrates = Math.floor(totalProduction / EGGS_PER_CRATE)
  const totalPieces = totalProduction % EGGS_PER_CRATE


  useEffect(() => {
    loadFlocksData()
  }, [])

  const loadFlocksData = async () => {
    const { farmId, userId } = getUserContext()
    if (!farmId || !userId) return
    const [batchesRes, flocksRes] = await Promise.all([
      getFlockBatches(userId, farmId),
      getFlocks(userId, farmId)
    ])
    if (batchesRes.success && batchesRes.data) {
      setFlockBatches(batchesRes.data)
    }
    if (flocksRes.success && flocksRes.data) {
      setFlocks(flocksRes.data)
    }
  }

  const handleInputChange = (field: keyof typeof formData, value: string | number) => {
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

    if (formData.flockId <= 0) {
      setError("Please select a flock")
      return
    }

    setLoading(true)
    setError("")

    const eggProductionData: EggProductionInput = {
      ...formData,
      eggCount: totalProduction,
      totalProduction,
      farmId,
      userId,
    }

    const result = await createEggProduction(eggProductionData)
    
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
              production9AM: formData.production9AM,
              production12PM: formData.production12PM,
              production4PM: formData.production4PM,
              totalProduction: totalProduction,
            }
            await updateProductionRecord(matchingRecord.id, updateData)
          } else {
            // Create a production record with egg production data
            if (flock) {
              // Normalize both dates to UTC date-only to avoid timezone off-by-one
              const startStr = (flock.startDate || "").split("T")[0]
              const prodStr = (formData.productionDate || "").split("T")[0]
              const [sy, sm, sd] = startStr.split("-").map(Number)
              const [py, pm, pd] = prodStr.split("-").map(Number)
              const startUtc = Date.UTC(sy, sm - 1, sd)
              const prodUtc = Date.UTC(py, pm - 1, pd)
              const ageDays = Math.floor(Math.max(0, prodUtc - startUtc) / (1000 * 60 * 60 * 24))
              const ageWeeks = Math.floor(ageDays / 7)

              const prodInput: ProductionRecordInput = {
                farmId,
                userId,
                createdBy: userId,
                updatedBy: userId,
                ageInWeeks: ageWeeks,
                ageInDays: ageDays,
                date: formData.productionDate + 'T00:00:00Z',
                noOfBirds: flock.quantity || 0,
                mortality: 0,
                noOfBirdsLeft: flock.quantity || 0,
                feedKg: 0,
                medication: "None",
                production9AM: formData.production9AM,
                production12PM: formData.production12PM,
                production4PM: formData.production4PM,
                totalProduction: totalProduction,
                flockId: flock.flockId || formData.flockId,
              }
              await createProductionRecord(prodInput)
            }
          }
        }
      } catch (syncError) {
        console.error("Error syncing to production records:", syncError)
        // Don't fail the whole operation if sync fails
      }

      router.push("/egg-production")
    } else {
      setError(result.message || "An unknown error occurred")
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

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6 space-y-6">
            {/* Page Header */}
            <div className="flex items-center gap-3 mb-6">
              <div className="w-10 h-10 bg-yellow-100 rounded-lg flex items-center justify-center">
                <Egg className="w-5 h-5 text-yellow-600" />
              </div>
              <div>
                <h1 className="text-2xl font-bold text-slate-900">Add New Production Record</h1>
                <p className="text-slate-600">Enter the egg production details below</p>
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
                      onValueChange={(value) => handleInputChange("flockId", parseInt(value))}
                      disabled={loading}
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
                      disabled={loading}
                    />
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="totalProduction">Total Eggs Collected</Label>
                    <Input
                      id="totalProduction"
                      type="number"
                      min="0"
                      value={totalProduction}
                      disabled
                    />
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="brokenEggs">Broken Eggs</Label>
                    <Input
                      id="brokenEggs"
                      type="number"
                      min="0"
                      value={formData.brokenEggs}
                      onChange={(e) => handleInputChange("brokenEggs", parseInt(e.target.value) || 0)}
                      disabled={loading}
                    />
                  </div>
                </div>

                {/* Morning (9 AM) - Crates + Loose */}
                <div className="p-3 bg-blue-50 border border-blue-200 rounded-lg space-y-2 mt-4">
                  <Label className="text-blue-800 font-semibold">Production at 9 AM — Crates × {EGGS_PER_CRATE} + Loose Eggs</Label>
                  <div className="grid grid-cols-3 gap-3">
                    <div className="space-y-1">
                      <Label className="text-xs">Crates</Label>
                      <Input type="number" min="0" value={morningCrates} onChange={(e) => setMorningCrates(parseInt(e.target.value) || 0)} disabled={loading} />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs">Loose Eggs</Label>
                      <Input type="number" min="0" max="29" value={morningLoose} onChange={(e) => setMorningLoose(parseInt(e.target.value) || 0)} disabled={loading} />
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
                  <Label className="text-orange-800 font-semibold">Production at 12 PM — Crates × {EGGS_PER_CRATE} + Loose Eggs</Label>
                  <div className="grid grid-cols-3 gap-3">
                    <div className="space-y-1">
                      <Label className="text-xs">Crates</Label>
                      <Input type="number" min="0" value={noonCrates} onChange={(e) => setNoonCrates(parseInt(e.target.value) || 0)} disabled={loading} />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs">Loose Eggs</Label>
                      <Input type="number" min="0" max="29" value={noonLoose} onChange={(e) => setNoonLoose(parseInt(e.target.value) || 0)} disabled={loading} />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs">Total</Label>
                      <div className="h-10 px-3 py-2 bg-white border rounded-md flex items-center font-bold text-orange-700">{noonTotal.toLocaleString()}</div>
                    </div>
                  </div>
                  <p className="text-xs text-orange-600">{noonCrates} crates × {EGGS_PER_CRATE} + {noonLoose} loose = {noonTotal.toLocaleString()} eggs</p>
                </div>

                {/* Evening (4 PM) - Crates + Loose */}
                <div className="p-3 bg-purple-50 border border-purple-200 rounded-lg space-y-2">
                  <Label className="text-purple-800 font-semibold">Production at 4 PM — Crates × {EGGS_PER_CRATE} + Loose Eggs</Label>
                  <div className="grid grid-cols-3 gap-3">
                    <div className="space-y-1">
                      <Label className="text-xs">Crates</Label>
                      <Input type="number" min="0" value={eveningCrates} onChange={(e) => setEveningCrates(parseInt(e.target.value) || 0)} disabled={loading} />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs">Loose Eggs</Label>
                      <Input type="number" min="0" max="29" value={eveningLoose} onChange={(e) => setEveningLoose(parseInt(e.target.value) || 0)} disabled={loading} />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-xs">Total</Label>
                      <div className="h-10 px-3 py-2 bg-white border rounded-md flex items-center font-bold text-purple-700">{eveningTotal.toLocaleString()}</div>
                    </div>
                  </div>
                  <p className="text-xs text-purple-600">{eveningCrates} crates × {EGGS_PER_CRATE} + {eveningLoose} loose = {eveningTotal.toLocaleString()} eggs</p>
                </div>

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
                    <Textarea id="notes" value={formData.notes} onChange={(e) => handleInputChange("notes", e.target.value)} disabled={loading} />
                </div>
              </div>

              {/* Form Actions */}
              <div className="flex gap-4">
                <Button
                  type="button"
                  className="flex-1 h-11 bg-red-600 hover:bg-red-700 text-white"
                  disabled={loading}
                  onClick={() => router.push("/egg-production")}
                >
                  Cancel
                </Button>
                <Button
                  type="submit"
                  className="flex-1 h-11 bg-blue-600 hover:bg-blue-700"
                  disabled={loading}
                >
                  {loading ? "Creating..." : "Create Record"}
                </Button>
              </div>
            </form>
          </div>
        </main>
      </div>
    </div>
  )
}