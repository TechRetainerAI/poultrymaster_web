"use client"

import type React from "react"

import { useEffect, useState } from "react"
import { useRouter, useParams } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { EGG_GRADE_OPTIONS, eggGradeFromApi, eggGradeToApi } from "@/lib/constants/egg-grade"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { FileText, X } from "lucide-react"
import { getProductionRecord, updateProductionRecord, type ProductionRecordInput } from "@/lib/api/production-record"
import { getUserContext } from "@/lib/utils/user-context"
import { Alert, AlertDescription } from "@/components/ui/alert"

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
    eggGrade: "",
  })

  useEffect(() => {
    loadRecord()
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
        eggGrade: eggGradeFromApi((record as any).eggGrade),
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
      totalProduction,
      eggGrade: eggGradeToApi(formData.eggGrade),
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
        <div className="flex-1 flex flex-col">
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
      <div className="flex-1 flex flex-col">
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
                      <Input
                        id="ageInWeeks"
                        name="ageInWeeks"
                        type="number"
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
                      <Input
                        id="ageInDays"
                        name="ageInDays"
                        type="number"
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
                      <Input
                        id="production9AM"
                        name="production9AM"
                        type="number"
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
                      <Input
                        id="production12PM"
                        name="production12PM"
                        type="number"
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
                      <Input
                        id="production4PM"
                        name="production4PM"
                        type="number"
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
                      <Input
                        id="brokenEggs"
                        name="brokenEggs"
                        type="number"
                        value={formData.brokenEggs}
                        onChange={handleChange}
                        min="0"
                        disabled={loading}
                        className="h-11 border-red-200 focus:border-red-500 focus:ring-red-500"
                      />
                    </div>
                    <div className="space-y-2 md:col-span-3">
                      <Label className="text-sm font-medium text-slate-700">Egg grade</Label>
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
                      <Input
                        id="noOfBirds"
                        name="noOfBirds"
                        type="number"
                        value={formData.noOfBirds}
                        onChange={handleChange}
                        required
                        min="0"
                        disabled={loading}
                        className="h-11 border-slate-200 focus:border-blue-500 focus:ring-blue-500"
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="mortality" className="text-sm font-medium text-slate-700">Mortality *</Label>
                      <Input
                        id="mortality"
                        name="mortality"
                        type="number"
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
                      <Input
                        id="feedKg"
                        name="feedKg"
                        type="number"
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