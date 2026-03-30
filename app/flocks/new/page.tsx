"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Bird, ArrowLeft, Loader2, Users, Home } from "lucide-react"
import { createFlock, type FlockInput } from "@/lib/api/flock"
import { getHouses, type House } from "@/lib/api/house"
import { getFlockBatches, type FlockBatch } from "@/lib/api/flock-batch"
import { getUserContext } from "@/lib/utils/user-context"

export default function NewFlockPage() {
  const router = useRouter()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState("")

  const [formData, setFormData] = useState<FlockInput>({
    farmId: "",
    userId: "",
    name: "",
    startDate: "",
    breed: "",
    quantity: 0,
    active: true,
    houseId: null,
    batchId: 0,
    inactivationReason: "",
    otherReason: "",
    notes: "",
  })

  const [houses, setHouses] = useState<House[]>([])
  const [housesLoading, setHousesLoading] = useState(true)
  const [flockBatches, setFlockBatches] = useState<FlockBatch[]>([])
  const [flockBatchesLoading, setFlockBatchesLoading] = useState(true)
  const [selectedFlockBatch, setSelectedFlockBatch] = useState<FlockBatch | null>(null)
  const [remainingBirds, setRemainingBirds] = useState<number | null>(null)

  useEffect(() => {
    const loadData = async () => {
      const { userId, farmId } = getUserContext()
      if (!userId || !farmId) {
        setHousesLoading(false)
        setFlockBatchesLoading(false)
        return
      }

      setHousesLoading(true)
      const housesRes = await getHouses(userId, farmId)
      if (housesRes.success && Array.isArray(housesRes.data)) {
        setHouses(housesRes.data as House[])
      }
      setHousesLoading(false)

      setFlockBatchesLoading(true)
      const flockBatchesRes = await getFlockBatches(userId, farmId)
      if (flockBatchesRes.success && Array.isArray(flockBatchesRes.data)) {
        setFlockBatches(flockBatchesRes.data as FlockBatch[])
      }
      setFlockBatchesLoading(false)
    }
    loadData()
  }, [])

  useEffect(() => {
    if (selectedFlockBatch) {
      setRemainingBirds(selectedFlockBatch.numberOfBirds - formData.quantity)
    } else {
      setRemainingBirds(null)
    }
  }, [formData.quantity, selectedFlockBatch])

  const handleInputChange = (field: keyof FlockInput, value: string | number | boolean | null) => {
    setFormData(prev => ({
      ...prev,
      [field]: value as any,
    }))
  }

  const handleFlockBatchChange = (batchId: number) => {
    if (batchId === 0 || !batchId) {
      setSelectedFlockBatch(null)
      handleInputChange("batchId", 0)
    } else {
      const selected = flockBatches.find(batch => batch.batchId === batchId) || null
      setSelectedFlockBatch(selected)
      handleInputChange("batchId", batchId)
    }
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    const { farmId, userId } = getUserContext()
    if (!farmId || !userId) {
      setError("Farm ID or User ID not found")
      return
    }

    if (!formData.name.trim() || !formData.breed.trim() || !formData.startDate) {
      setError("Please fill in all required fields")
      return
    }

    if (formData.quantity <= 0) {
      setError("Quantity must be greater than 0")
      return
    }

    if (!formData.batchId || formData.batchId === 0) {
      setError("Please select a batch")
      return
    }

    if (selectedFlockBatch && formData.quantity > selectedFlockBatch.numberOfBirds) {
      setError("Quantity cannot be greater than the available birds in the selected batch")
      return
    }

    // Validate that the selected batch still exists and has enough birds
    if (selectedFlockBatch) {
      const remainingBirds = selectedFlockBatch.numberOfBirds - formData.quantity
      if (remainingBirds < 0) {
        setError("Quantity exceeds available birds in the selected batch. Please select a different batch or reduce the quantity.")
        return
      }
    }

    setLoading(true)
    setError("")

    const flockData: FlockInput = {
      ...formData,
      farmId,
      userId,
      otherReason: formData.inactivationReason === 'other' ? formData.otherReason : '',
    }

    console.log("[NewFlockPage] Creating flock with data:", flockData)
    console.log("[NewFlockPage] Selected batch:", selectedFlockBatch)

    const result = await createFlock(flockData)

    if (result.success) {
      router.push("/flocks")
    } else {
      setError(result.message || "Failed to create flock")
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
              <Button variant="ghost" size="icon" onClick={() => router.push("/flocks")} className="shrink-0">
                <ArrowLeft className="w-5 h-5" />
              </Button>
              <div className="w-10 h-10 bg-green-100 rounded-lg flex items-center justify-center">
                <Bird className="w-5 h-5 text-green-600" />
              </div>
              <div>
                <h1 className="text-2xl font-bold text-slate-900">Add New Flock</h1>
                <p className="text-slate-600 text-sm">Enter the flock information below</p>
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
              {/* Section: Flock Information */}
              <div className="rounded-xl border border-slate-200 overflow-hidden">
                <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Flock Information</div>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
                  <div className="space-y-2">
                    <Label htmlFor="flockBatchId" className="text-sm font-medium text-slate-700">
                      Assign to Flock Batch *
                    </Label>
                    <div className="relative">
                      <select
                        id="flockBatchId"
                        className="w-full h-10 rounded-md border border-slate-200 bg-white px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                        value={formData.batchId || ''}
                        onChange={(e) => {
                          const value = e.target.value ? parseInt(e.target.value) : 0
                          handleFlockBatchChange(value)
                        }}
                        disabled={loading || flockBatchesLoading}
                        required
                      >
                        <option value="">Please select a batch</option>
                        {flockBatches.map(batch => (
                          <option key={batch.batchId} value={batch.batchId}>{batch.batchName}</option>
                        ))}
                      </select>
                      <Users className="w-4 h-4 text-slate-400 absolute right-3 top-3 pointer-events-none" />
                    </div>
                    {selectedFlockBatch && (
                      <p className="text-xs text-slate-500">
                        Available: {selectedFlockBatch.numberOfBirds} birds
                      </p>
                    )}
                  </div>
                  
                  <div className="space-y-2">
                    <Label htmlFor="name" className="text-sm font-medium text-slate-700">
                      Name *
                    </Label>
                    <Input
                      id="name"
                      type="text"
                      placeholder="e.g., Flock A - Rhode Island Reds"
                      value={formData.name}
                      onChange={(e) => handleInputChange("name", e.target.value)}
                      required
                      disabled={loading}
                    />
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="breed" className="text-sm font-medium text-slate-700">
                      Breed *
                    </Label>
                    <Input
                      id="breed"
                      type="text"
                      placeholder="e.g., Rhode Island Red"
                      value={formData.breed}
                      onChange={(e) => handleInputChange("breed", e.target.value)}
                      required
                      disabled={loading}
                    />
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="startDate" className="text-sm font-medium text-slate-700">
                      Start Date *
                    </Label>
                    <Input
                      id="startDate"
                      type="date"
                      value={formData.startDate}
                      onChange={(e) => handleInputChange("startDate", e.target.value)}
                      required
                      disabled={loading}
                    />
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="quantity" className="text-sm font-medium text-slate-700">
                      Number of Birds *
                    </Label>
                    <Input
                      id="quantity"
                      type="number"
                      min="1"
                      placeholder="e.g., 100"
                      value={formData.quantity}
                      onChange={(e) => handleInputChange("quantity", parseInt(e.target.value) || 0)}
                      required
                      disabled={loading}
                    />
                    {selectedFlockBatch && (
                      <p className="text-xs text-slate-500">
                        Remaining: {remainingBirds} birds
                      </p>
                    )}
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="houseId" className="text-sm font-medium text-slate-700">
                      Assign to House
                    </Label>
                    <div className="relative">
                      <select
                        id="houseId"
                        className="w-full h-10 rounded-md border border-slate-200 bg-white px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                        value={formData.houseId ?? ''}
                        onChange={(e) => handleInputChange("houseId", e.target.value ? parseInt(e.target.value) : null)}
                        disabled={loading || housesLoading}
                      >
                        <option value="">No house</option>
                        {houses.map(h => (
                          <option key={h.houseId} value={h.houseId}>{(h as any).houseName || (h as any).name || `House ${h.houseId}`}</option>
                        ))}
                      </select>
                      <Home className="w-4 h-4 text-slate-400 absolute right-3 top-3" />
                    </div>
                  </div>
                </div>
              </div>

              {/* Section: Status & Notes */}
              <div className="rounded-xl border border-slate-200 overflow-hidden">
                <div className="bg-green-600 px-4 py-2 text-sm font-semibold text-white">Status &amp; Notes</div>
                <div className="p-4 bg-white space-y-4">
                  <div className="flex items-center space-x-2">
                    <Switch
                      id="active"
                      checked={formData.active}
                      onCheckedChange={(checked) => handleInputChange("active", checked)}
                      disabled={loading}
                    />
                    <Label htmlFor="active" className="text-sm font-medium text-slate-700">
                      Active Flock
                    </Label>
                    <p className="text-xs text-slate-500 ml-2">
                      (Uncheck if this flock is no longer active)
                    </p>
                  </div>

                  {!formData.active && (
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                      <div className="space-y-2">
                        <Label htmlFor="inactivationReason" className="text-sm font-medium text-slate-700">
                          Inactivation Reason
                        </Label>
                        <select
                          id="inactivationReason"
                          className="w-full h-10 rounded-md border border-slate-200 bg-white px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                          value={formData.inactivationReason || ''}
                          onChange={(e) => handleInputChange("inactivationReason", e.target.value)}
                          disabled={loading}
                        >
                          <option value="">Select a reason</option>
                          <option value="all flock sold">All flock sold</option>
                          <option value="all flocks on the market">All flocks on the market</option>
                          <option value="disease outbreak">Disease outbreak</option>
                          <option value="end of production cycle">End of production cycle</option>
                          <option value="relocation">Relocation</option>
                          <option value="other">Other</option>
                        </select>
                      </div>

                      {formData.inactivationReason === 'other' && (
                        <div className="space-y-2">
                          <Label htmlFor="otherReason" className="text-sm font-medium text-slate-700">
                            Other Reason
                          </Label>
                          <Input
                            id="otherReason"
                            type="text"
                            placeholder="Please specify the reason"
                            value={formData.otherReason || ''}
                            onChange={(e) => handleInputChange("otherReason", e.target.value)}
                            disabled={loading}
                          />
                        </div>
                      )}
                    </div>
                  )}

                  <div className="space-y-2">
                    <Label htmlFor="notes" className="text-sm font-medium text-slate-700">
                      Notes (Optional)
                    </Label>
                    <textarea
                      id="notes"
                      placeholder="Add any additional notes about the flock"
                      value={formData.notes || ''}
                      onChange={(e) => handleInputChange("notes", e.target.value)}
                      className="w-full rounded-md border border-slate-200 bg-white px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 min-h-[80px]"
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
                  onClick={() => router.push("/flocks")}
                  className="min-w-[120px] bg-red-600 hover:bg-red-700 text-white"
                >
                  Cancel
                </Button>
                <Button
                  type="submit"
                  disabled={loading}
                  className="min-w-[160px]"
                >
                  {loading ? (
                    <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Creating...</>
                  ) : (
                    <><Bird className="w-4 h-4 mr-2" />Create Flock</>
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
