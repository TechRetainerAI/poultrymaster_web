"use client"

import { useEffect, useState } from "react"
import { useRouter, useParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Bird, ArrowLeft, Loader2, Save } from "lucide-react"
import { getFlockBatch, updateFlockBatch, type FlockBatchInput } from "@/lib/api/flock-batch"
import { getUserContext } from "@/lib/utils/user-context"

export default function EditFlockBatchPage() {
  const router = useRouter()
  const params = useParams()
  const batchId = params.id as string

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState("")

  const [formData, setFormData] = useState<FlockBatchInput>({
    farmId: "",
    userId: "",
    batchName: "",
    batchCode: "",
    startDate: "",
    breed: "",
    numberOfBirds: 0,
  })

  useEffect(() => {
    load()
  }, [batchId])

  const load = async () => {
    const { farmId, userId } = getUserContext()
    
    if (!farmId || !userId) {
      setError("Farm ID or User ID not found")
      setLoading(false)
      return
    }

    const flockBatchRes = await getFlockBatch(parseInt(batchId), userId, farmId)

    if (flockBatchRes.success && flockBatchRes.data) {
      const flockBatch = flockBatchRes.data
      setFormData({
        farmId: flockBatch.farmId,
        userId: flockBatch.userId,
        batchName: flockBatch.batchName,
        batchCode: flockBatch.batchCode,
        startDate: flockBatch.startDate.split('T')[0],
        breed: flockBatch.breed,
        numberOfBirds: flockBatch.numberOfBirds,
      })
    } else {
      setError(flockBatchRes.message)
    }
    
    setLoading(false)
  }

  const handleInputChange = (field: keyof FlockBatchInput, value: string | number) => {
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

    if (!formData.batchName.trim() || !formData.batchCode.trim() || !formData.breed.trim() || !formData.startDate) {
      setError("Please fill in all required fields")
      return
    }

    if (formData.numberOfBirds <= 0) {
      setError("Number of birds must be greater than 0")
      return
    }

    setSaving(true)
    setError("")

    const flockBatchData: Partial<FlockBatchInput> = {
      batchName: formData.batchName,
      batchCode: formData.batchCode,
      startDate: formData.startDate + 'T00:00:00Z',
      breed: formData.breed,
      numberOfBirds: formData.numberOfBirds,
      farmId, // ensure backend receives FarmId
      userId, // ensure backend receives UserId
    }

    const result = await updateFlockBatch(parseInt(batchId), flockBatchData)
    
    if (result.success) {
      router.push("/flock-batch")
    } else {
      setError(result.message)
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
        <div className="flex-1 flex flex-col">
          <DashboardHeader />
          <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
            <div className="space-y-6 max-w-3xl">
              <div className="flex items-center gap-3">
                <Button variant="ghost" size="icon" onClick={() => router.push("/flock-batch")} className="shrink-0">
                  <ArrowLeft className="w-5 h-5" />
                </Button>
                <div className="w-10 h-10 bg-green-100 rounded-lg flex items-center justify-center">
                  <Bird className="w-5 h-5 text-green-600" />
                </div>
                <div>
                  <h1 className="text-2xl font-bold text-slate-900">Edit Flock Batch</h1>
                  <p className="text-slate-600 text-sm">Loading flock batch information...</p>
                </div>
              </div>
              <div className="rounded-xl border border-slate-200 overflow-hidden">
                <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Batch Details</div>
                <div className="p-6 bg-white">
                  <div className="animate-pulse space-y-4">
                    <div className="h-4 bg-slate-200 rounded w-1/3"></div>
                    <div className="h-11 bg-slate-200 rounded"></div>
                    <div className="h-4 bg-slate-200 rounded w-1/3"></div>
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
      <div className="flex-1 flex flex-col">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6 max-w-3xl">
            {/* Page Header */}
            <div className="flex items-center gap-3">
              <Button variant="ghost" size="icon" onClick={() => router.push("/flock-batch")} className="shrink-0">
                <ArrowLeft className="w-5 h-5" />
              </Button>
              <div className="w-10 h-10 bg-green-100 rounded-lg flex items-center justify-center">
                <Bird className="w-5 h-5 text-green-600" />
              </div>
              <div>
                <h1 className="text-2xl font-bold text-slate-900">Edit Flock Batch</h1>
                <p className="text-slate-600 text-sm">Update the flock batch information below</p>
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
              {/* Section: Batch Details */}
              <div className="rounded-xl border border-slate-200 overflow-hidden">
                <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Batch Details</div>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
                  <div className="space-y-2">
                    <Label htmlFor="batchName" className="text-sm font-medium text-slate-700">
                      Batch Name *
                    </Label>
                    <Input
                      id="batchName"
                      type="text"
                      placeholder="e.g., Batch A - Rhode Island Reds"
                      value={formData.batchName}
                      onChange={(e) => handleInputChange("batchName", e.target.value)}
                      required
                      disabled={saving}
                    />
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="batchCode" className="text-sm font-medium text-slate-700">
                      Batch Code *
                    </Label>
                    <Input
                      id="batchCode"
                      type="text"
                      placeholder="e.g., B-001"
                      value={formData.batchCode}
                      onChange={(e) => handleInputChange("batchCode", e.target.value)}
                      required
                      disabled={saving}
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
                      disabled={saving}
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
                      disabled={saving}
                    />
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="numberOfBirds" className="text-sm font-medium text-slate-700">
                      Number of Birds *
                    </Label>
                    <Input
                      id="numberOfBirds"
                      type="number"
                      min="1"
                      placeholder="e.g., 100"
                      value={formData.numberOfBirds}
                      onChange={(e) => handleInputChange("numberOfBirds", parseInt(e.target.value) || 0)}
                      required
                      disabled={saving}
                    />
                  </div>
                </div>
              </div>

              {/* Form Actions */}
              <div className="flex gap-3 justify-end pt-2">
                <Button
                  type="button"
                  disabled={saving}
                  onClick={() => router.push("/flock-batch")}
                  className="min-w-[120px] bg-red-600 hover:bg-red-700 text-white"
                >
                  Cancel
                </Button>
                <Button
                  type="submit"
                  disabled={saving}
                  className="min-w-[160px]"
                >
                  {saving ? (
                    <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Updating...</>
                  ) : (
                    <><Save className="w-4 h-4 mr-2" />Update Flock Batch</>
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
