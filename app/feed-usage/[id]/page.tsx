"use client"

import type React from "react"

import { useState, useEffect } from "react"
import { useRouter, useParams } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Package } from "lucide-react"
import { getFeedUsage, updateFeedUsage, type FeedUsageInput } from "@/lib/api/feed-usage"
import { getUserContext } from "@/lib/utils/user-context"
import { getValidFlocks, getFlocksForSelect } from "@/lib/utils/flock-utils"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { getProductionRecords, createProductionRecord, updateProductionRecord, type ProductionRecordInput } from "@/lib/api/production-record"

export default function EditFeedUsagePage() {
  const router = useRouter()
  const params = useParams()
  const id = Number(params.id)
  
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState("")
  const [flocks, setFlocks] = useState<{ value: string; label: string }[]>([])
  const [flocksLoading, setFlocksLoading] = useState(true)
  const [pageLoading, setPageLoading] = useState(true)
  
  const [formData, setFormData] = useState({
    flockId: "",
    usageDate: "",
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
    loadFlocks()
    loadFeedUsage()
  }, [])

  const loadFlocks = async () => {
    try {
      setFlocksLoading(true)
      await getValidFlocks()
      const flocksForSelect = getFlocksForSelect()
      setFlocks(flocksForSelect)
    } catch (error) {
      console.error("[v0] Error loading flocks:", error)
    } finally {
      setFlocksLoading(false)
    }
  }

  const loadFeedUsage = async () => {
    const { userId, farmId } = getUserContext()

    if (!userId || !farmId) {
      setError("User context not found. Please log in again.")
      setPageLoading(false)
      return
    }

    const result = await getFeedUsage(id, userId, farmId)

    if (result.success && result.data) {
      const usage = result.data
      setFormData({
        flockId: usage.flockId.toString(),
        usageDate: usage.usageDate.split("T")[0],
        feedType: usage.feedType,
        quantityKg: usage.quantityKg.toString(),
      })
    } else {
      setError(result.message)
    }

    setPageLoading(false)
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

    if (!userId || !farmId) {
      setError("User context not found. Please log in again.")
      setLoading(false)
      return
    }

    if (!formData.flockId) {
      setError("Please select a flock")
      setLoading(false)
      return
    }

    if (!formData.feedType) {
      setError("Please select a feed type")
      setLoading(false)
      return
    }

    if (!formData.quantityKg || Number(formData.quantityKg) <= 0) {
      setError("Please enter a valid quantity")
      setLoading(false)
      return
    }

    const usage: Partial<FeedUsageInput> = {
      farmId,
      userId,
      flockId: Number(formData.flockId),
      usageDate: formData.usageDate + "T00:00:00Z",
      feedType: formData.feedType,
      quantityKg: Number(formData.quantityKg),
    }

    const result = await updateFeedUsage(id, usage)
    
    if (result.success) {
      // Sync to production records
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

  if (pageLoading) {
    return (
      <div className="flex min-h-screen bg-slate-50">
        <DashboardSidebar onLogout={handleLogout} />
        <div className="flex-1 flex flex-col">
          <DashboardHeader />
          <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
            <div className="space-y-6">
              <div className="bg-white rounded-lg shadow-sm p-12 text-center">
                <p className="text-slate-600">Loading feed usage record...</p>
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
      <div className="flex-1 flex flex-col">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6 space-y-6">
            {/* Page Header */}
            <div className="flex items-center gap-3 mb-6">
              <div className="w-10 h-10 bg-amber-100 rounded-lg flex items-center justify-center">
                <Package className="w-5 h-5 text-amber-600" />
              </div>
              <div>
                <h1 className="text-2xl font-bold text-slate-900">Edit Feed Usage</h1>
                <p className="text-slate-600">Update feed consumption record</p>
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
                <h3 className="text-lg font-semibold text-slate-900">Feed Usage Information</h3>
                <p className="text-sm text-slate-600">
                  Update the feed consumption details
                </p>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div className="space-y-2">
                    <Label htmlFor="flockId" className="text-sm font-medium text-slate-700">
                      Select Flock *
                    </Label>
                    <Select value={formData.flockId} onValueChange={handleFlockChange} disabled={flocksLoading || loading}>
                      <SelectTrigger className="h-11 border-slate-200 focus:border-blue-500 focus:ring-blue-500">
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
                      className="h-11 border-slate-200 focus:border-blue-500 focus:ring-blue-500"
                      required
                      disabled={loading}
                    />
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="feedType" className="text-sm font-medium text-slate-700">
                      Feed Type *
                    </Label>
                    <Select value={formData.feedType} onValueChange={handleFeedTypeChange} disabled={loading}>
                      <SelectTrigger className="h-11 border-slate-200 focus:border-blue-500 focus:ring-blue-500">
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
                      className="h-11 border-slate-200 focus:border-blue-500 focus:ring-blue-500"
                      required
                      disabled={loading}
                    />
                  </div>
                </div>
              </div>

              {/* Form Actions */}
              <div className="flex gap-4">
                <Button
                  type="button"
                  variant="outline"
                  className="flex-1 h-11 border-slate-200"
                  disabled={loading}
                  onClick={() => router.push("/feed-usage")}
                >
                  Cancel
                </Button>
                <Button
                  type="submit"
                  className="flex-1 h-11 bg-blue-600 hover:bg-blue-700"
                  disabled={loading || flocksLoading}
                >
                  {loading ? "Updating..." : "Update Usage"}
                </Button>
              </div>
            </form>
          </div>
        </main>
      </div>
    </div>
  )
}

