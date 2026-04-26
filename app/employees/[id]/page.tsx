"use client"

import type React from "react"
import { useState, useEffect } from "react"
import { useRouter, useParams } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { UserCog, ArrowLeft, Save, Loader2, User } from "lucide-react"
import { getEmployee, updateEmployee, type UpdateEmployeeData } from "@/lib/api"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { usePermissions } from "@/hooks/use-permissions"

export default function EditEmployeePage() {
  const router = useRouter()
  const params = useParams()
  const permissions = usePermissions()
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState("")
  
  const [formData, setFormData] = useState({
    firstName: "",
    lastName: "",
    phoneNumber: "",
    email: "",
    userName: "",
    createdDate: "",
  })

  const employeeId = params.id as string

  useEffect(() => {
    if (permissions.isLoading) {
      return
    }
    
    if (!permissions.isAdmin) {
      router.push("/dashboard")
      return
    }

    if (employeeId) {
      loadEmployee()
    }
  }, [permissions.isAdmin, permissions.isLoading, employeeId])

  const loadEmployee = async () => {
    try {
      const result = await getEmployee(employeeId)

      if (result.success && result.data) {
        setFormData({
          firstName: result.data.firstName,
          lastName: result.data.lastName,
          phoneNumber: result.data.phoneNumber,
          email: result.data.email,
          userName: result.data.userName || "",
          createdDate: result.data.createdDate || "",
        })
      } else {
        setError(result.message || "Failed to load employee")
      }
    } catch (error) {
      console.error("[v0] Error loading employee:", error)
      setError("Unable to load employee. API may be unavailable.")
    } finally {
      setLoading(false)
    }
  }

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setFormData({ ...formData, [e.target.name]: e.target.value })
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setSaving(true)
    setError("")

    const employeeData: UpdateEmployeeData = {
      id: employeeId,
      firstName: formData.firstName,
      lastName: formData.lastName,
      phoneNumber: formData.phoneNumber,
      email: formData.email,
    }

    const result = await updateEmployee(employeeId, employeeData)
    
    if (result.success) {
      router.push("/employees")
    } else {
      setError(result.message || "Failed to update employee")
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

  if (permissions.isLoading) {
    return (
      <div className="flex min-h-screen bg-slate-50">
        <DashboardSidebar onLogout={handleLogout} />
        <div className="flex-1 flex flex-col">
          <DashboardHeader />
          <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0 flex items-center justify-center">
            <div className="text-center">
              <div className="w-8 h-8 border-4 border-blue-600 border-t-transparent rounded-full animate-spin mx-auto mb-4"></div>
              <p className="text-slate-600">Loading...</p>
            </div>
          </main>
        </div>
      </div>
    )
  }

  if (!permissions.isAdmin) {
    return null
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
              <Button variant="ghost" size="icon" onClick={() => router.push("/employees")} className="shrink-0">
                <ArrowLeft className="w-5 h-5" />
              </Button>
              <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center">
                <UserCog className="w-5 h-5 text-blue-600" />
              </div>
              <div>
                <h1 className="text-2xl font-bold text-slate-900">Edit Employee</h1>
                <p className="text-slate-600 text-sm">Update employee information and contact details</p>
              </div>
            </div>

            {/* Error Alert */}
            {error && (
              <Alert variant="destructive">
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}

            {loading ? (
              <div className="rounded-xl border border-slate-200 overflow-hidden">
                <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Personal Information</div>
                <div className="p-6 bg-white">
                  <div className="animate-pulse space-y-4">
                    <div className="h-4 bg-slate-200 rounded w-1/3"></div>
                    <div className="h-11 bg-slate-200 rounded"></div>
                    <div className="h-4 bg-slate-200 rounded w-1/3"></div>
                    <div className="h-11 bg-slate-200 rounded"></div>
                  </div>
                </div>
              </div>
            ) : (
              <form onSubmit={handleSubmit} className="space-y-6">
                {/* Section: Personal Information */}
                <div className="rounded-xl border border-slate-200 overflow-hidden">
                  <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Personal Information</div>
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
                    <div className="space-y-2">
                      <Label className="text-sm font-medium text-slate-700">First Name *</Label>
                      <Input
                        name="firstName"
                        value={formData.firstName}
                        onChange={handleChange}
                        placeholder="John"
                        required
                        disabled={saving}
                      />
                    </div>
                    <div className="space-y-2">
                      <Label className="text-sm font-medium text-slate-700">Last Name *</Label>
                      <Input
                        name="lastName"
                        value={formData.lastName}
                        onChange={handleChange}
                        placeholder="Doe"
                        required
                        disabled={saving}
                      />
                    </div>
                  </div>
                </div>

                {/* Section: Contact Information */}
                <div className="rounded-xl border border-slate-200 overflow-hidden">
                  <div className="bg-green-600 px-4 py-2 text-sm font-semibold text-white">Contact Information</div>
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
                    <div className="space-y-2">
                      <Label className="text-sm font-medium text-slate-700">Email Address *</Label>
                      <Input
                        name="email"
                        type="email"
                        value={formData.email}
                        onChange={handleChange}
                        placeholder="john@example.com"
                        required
                        disabled={saving}
                      />
                    </div>
                    <div className="space-y-2">
                      <Label className="text-sm font-medium text-slate-700">Phone Number *</Label>
                      <Input
                        name="phoneNumber"
                        type="tel"
                        value={formData.phoneNumber}
                        onChange={handleChange}
                        placeholder="+1 (555) 123-4567"
                        required
                        disabled={saving}
                      />
                    </div>
                  </div>
                </div>

                {/* Section: Account Information (Read-only) */}
                <div className="rounded-xl border border-slate-200 overflow-hidden">
                  <div className="bg-slate-600 px-4 py-2 text-sm font-semibold text-white">Account Information</div>
                  <div className="p-4 bg-white space-y-3">
                    <div className="flex items-center gap-3 text-sm">
                      <User className="w-4 h-4 text-slate-400" />
                      <span className="text-slate-500 w-24">Username:</span>
                      <span className="font-medium text-slate-800">
                        {formData.userName ? `@${formData.userName}` : "Not set"}
                      </span>
                    </div>
                    <div className="flex items-center gap-3 text-sm">
                      <User className="w-4 h-4 text-slate-400" />
                      <span className="text-slate-500 w-24">Employee ID:</span>
                      <span className="font-mono text-xs text-slate-800">{employeeId}</span>
                    </div>
                    {formData.createdDate && (
                      <div className="flex items-center gap-3 text-sm">
                        <User className="w-4 h-4 text-slate-400" />
                        <span className="text-slate-500 w-24">Created:</span>
                        <span className="text-slate-800">{new Date(formData.createdDate).toLocaleDateString()}</span>
                      </div>
                    )}
                  </div>
                </div>

                {/* Form Actions */}
                <div className="flex gap-3 justify-end pt-2">
                  <Button
                    type="button"
                    disabled={saving}
                    onClick={() => router.push("/employees")}
                    className="min-w-[120px] bg-red-600 hover:bg-red-700 text-white"
                  >
                    Cancel
                  </Button>
                  <Button
                    type="submit"
                    disabled={saving || loading}
                    className="min-w-[160px]"
                  >
                    {saving ? (
                      <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving...</>
                    ) : (
                      <><Save className="w-4 h-4 mr-2" />Save Changes</>
                    )}
                  </Button>
                </div>
              </form>
            )}
          </div>
        </main>
      </div>
    </div>
  )
}
