"use client"

import type React from "react"

import { useState, useEffect } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Package, ArrowLeft, Loader2 } from "lucide-react"
import { createFeedUsage, type FeedUsageInput } from "@/lib/api/feed-usage"
import { getUserContext } from "@/lib/utils/user-context"
import { getValidFlocks, getFlocksForSelect } from "@/lib/utils/flock-utils"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { getProductionRecords, createProductionRecord, updateProductionRecord, type ProductionRecordInput } from "@/lib/api/production-record"

export default function NewFeedUsagePage() {
  const router = useRouter()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState("")
  const [flocks, setFlocks] = useState<{ value: string; label: string }[]>([])
  const [flocksLoading, setFlocksLoading] = useState(true)
  
  const [formData, setFormData] = useState({
    flockId: "",
    usageDate: new Date().toISOString().split("T")[0],
    feedType: "",
    quantityKg: "",
  })

  const feedTypes = [
    "Starter Feed",
    "Grower Feed", 
    "Layer Feed",
    "Broiler Feed",
    "Organic Feed",
    "Custom Mix"
  ]

  useEffect(() => {
    // Check if user is logged in
    const { userId, farmId } = getUserContext()
    console.log("[v0] Feed Usage New Page - User Context:", { userId, farmId })
    
    if (!userId || !farmId) {
      console.error("[v0] No user context found, redirecting to login")
      setError("Please log in to continue")
      router.push("/login")
      return
    }
    
    loadFlocks()
  }, [])

  const loadFlocks = async () => {
    try {
      setFlocksLoading(true)
      await getValidFlocks()
      const flocksForSelect = getFlocksForSelect()
      setFlocks(flocksForSelect)
      
      if (flocksForSelect.length === 0) {
        setError("No active flocks found. Please create a flock first.")
      }
    } catch (error) {
      console.error("[v0] Error loading flocks:", error)
      setError("Failed to load flocks. Please try again.")
    } finally {
      setFlocksLoading(false)
    }
  }

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setFormData({ ...formData, [e.target.name]: e.target.value })
  }

  const handleFlockChange = (value: string) => {
    setFormData({ ...formData, flockId: value })
  }

  const handleFeedTypeChange = (value: string) => {
    setFormData({ ...formData, feedType: value })
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setError("")

    const { userId, farmId } = getUserContext()
    
    console.log("[v0] Form submit - getUserContext result:", { userId, farmId })

    if (!userId || !farmId) {
      console.error("[v0] Missing user context - userId:", userId, "farmId:", farmId)
      setError("User context not found. Please log in again.")
      setLoading(false)
      return
    }

    if (!formData.flockId) {
      setError("Choose which flock this feed was used for.")
      setLoading(false)
      return
    }

    if (!formData.feedType) {
      setError("Pick a feed type so usage stays organized in reports.")
      setLoading(false)
      return
    }

    if (!formData.quantityKg || Number(formData.quantityKg) <= 0) {
      setError("Enter kilograms used as a number greater than zero.")
      setLoading(false)
      return
    }

    const usage: FeedUsageInput = {
      farmId,
      userId,
      flockId: Number(formData.flockId),
      usageDate: formData.usageDate + "T00:00:00Z",
      feedType: formData.feedType,
      quantityKg: Number(formData.quantityKg),
    }

    console.log("[v0] Form submit - final usage object:", usage)

    const result = await createFeedUsage(usage)
    
    if (result.success) {
      // Sync to production records if a record exists for this date and flock
      try {
        const prodRecordsRes = await getProductionRecords(userId, farmId)
        if (prodRecordsRes.success && prodRecordsRes.data) {
          const matchingRecord = prodRecordsRes.data.find(
            (pr: any) => pr.flockId === Number(formData.flockId) &&
            new Date(pr.date).toISOString().split('T')[0] === formData.usageDate
          )

          if (matchingRecord) {
            // Update existing production record with feed data
            const updateData: Partial<ProductionRecordInput> = {
              feedKg: Number(formData.quantityKg),
            }
            await updateProductionRecord(matchingRecord.id, updateData)
          } else {
            // Create a minimal production record with feed data
            // Get flock info for age calculation
            const flocksRes = await getValidFlocks()
            const flock = flocksRes.find((f: any) => f.flockId === Number(formData.flockId))
            
            if (flock) {
              // Normalize both dates to UTC date-only to avoid timezone off-by-one
              const startStr = (flock.startDate || "").split("T")[0]
              const usageStr = (formData.usageDate || "").split("T")[0]
              const [sy, sm, sd] = startStr.split("-").map(Number)
              const [uy, um, ud] = usageStr.split("-").map(Number)
              const startUtc = Date.UTC(sy, sm - 1, sd)
              const usageUtc = Date.UTC(uy, um - 1, ud)
              const ageDays = Math.floor(Math.max(0, usageUtc - startUtc) / (1000 * 60 * 60 * 24))
              const ageWeeks = Math.floor(ageDays / 7)

              const prodInput: ProductionRecordInput = {
                farmId,
                userId,
                createdBy: userId,
                updatedBy: userId,
                ageInWeeks: ageWeeks,
                ageInDays: ageDays,
                date: formData.usageDate + 'T00:00:00Z',
                noOfBirds: flock.quantity || 0,
                mortality: 0,
                noOfBirdsLeft: flock.quantity || 0,
                feedKg: Number(formData.quantityKg),
                medication: "None",
                production9AM: 0,
                production12PM: 0,
                production4PM: 0,
                totalProduction: 0,
                flockId: Number(formData.flockId),
              }
              await createProductionRecord(prodInput)
            }
          }
        }
      } catch (syncError) {
        console.error("Error syncing to production records:", syncError)
        // Don't fail the whole operation if sync fails
      }

      router.push("/feed-usage")
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

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6 max-w-3xl">
            {/* Page Header */}
            <div className="flex items-center gap-3">
              <Button variant="ghost" size="icon" onClick={() => router.push("/feed-usage")} className="shrink-0">
                <ArrowLeft className="w-5 h-5" />
              </Button>
              <div className="w-10 h-10 bg-amber-100 rounded-lg flex items-center justify-center">
                <Package className="w-5 h-5 text-amber-600" />
              </div>
              <div>
                <h1 className="text-2xl font-bold text-slate-900">Add Feed Usage</h1>
                <p className="text-slate-600 text-sm">Record feed consumption for a flock</p>
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
              {/* Section: Flock & Date */}
              <div className="rounded-xl border border-slate-200 overflow-hidden">
                <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Flock &amp; Date</div>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
                  <div className="space-y-2">
                    <Label htmlFor="flockId" className="text-sm font-medium text-slate-700">
                      Select Flock *
                    </Label>
                    <Select value={formData.flockId} onValueChange={handleFlockChange} disabled={flocksLoading || loading}>
                      <SelectTrigger>
                        <SelectValue placeholder={flocksLoading ? "Loading flocks..." : "Select a flock"} />
                      </SelectTrigger>
                      <SelectContent>
                        {flocks.map((flock) => (
                          <SelectItem key={flock.value} value={flock.value}>
                            {flock.label}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="usageDate" className="text-sm font-medium text-slate-700">
                      Usage Date *
                    </Label>
                    <Input
                      id="usageDate"
                      name="usageDate"
                      type="date"
                      value={formData.usageDate}
                      onChange={handleChange}
                      required
                      disabled={loading}
                    />
                  </div>
                </div>
              </div>

              {/* Section: Feed Details */}
              <div className="rounded-xl border border-slate-200 overflow-hidden">
                <div className="bg-amber-500 px-4 py-2 text-sm font-semibold text-white">Feed Details</div>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
                  <div className="space-y-2">
                    <Label htmlFor="feedType" className="text-sm font-medium text-slate-700">
                      Feed Type *
                    </Label>
                    <Select value={formData.feedType} onValueChange={handleFeedTypeChange} disabled={loading}>
                      <SelectTrigger>
                        <SelectValue placeholder="Select feed type" />
                      </SelectTrigger>
                      <SelectContent>
                        {feedTypes.map((type) => (
                          <SelectItem key={type} value={type}>
                            {type}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="quantityKg" className="text-sm font-medium text-slate-700">
                      Quantity (kg) *
                    </Label>
                    <Input
                      id="quantityKg"
                      name="quantityKg"
                      type="number"
                      step="0.1"
                      min="0"
                      placeholder="e.g., 25.5"
                      value={formData.quantityKg}
                      onChange={handleChange}
                      required
                      disabled={loading}
                    />
                  </div>
                </div>
              </div>

              {/* Form Actions */}
              <div className="flex gap-3 justify-end pt-2">
                <Button
                  type="button"
                  disabled={loading}
                  onClick={() => router.push("/feed-usage")}
                  className="min-w-[120px] bg-red-600 hover:bg-red-700 text-white"
                >
                  Cancel
                </Button>
                <Button
                  type="submit"
                  disabled={loading || flocksLoading || flocks.length === 0}
                  className="min-w-[160px]"
                >
                  {loading ? (
                    <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Recording...</>
                  ) : (
                    <><Package className="w-4 h-4 mr-2" />Record Usage</>
                  )}
                </Button>
              </div>
            </form>
          </div>
        </main>
      </div>
    </div>
  )
}
