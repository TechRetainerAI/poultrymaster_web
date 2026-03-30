"use client"

import type React from "react"

import { useState, useEffect } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { UserCog, ArrowLeft, Loader2 } from "lucide-react"
import { createEmployee, type CreateEmployeeData } from "@/lib/api"
import { getUserContext } from "@/lib/utils/user-context"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { usePermissions } from "@/hooks/use-permissions"

export default function NewEmployeePage() {
  const router = useRouter()
  const permissions = usePermissions()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState("")
  
  const [formData, setFormData] = useState({
    userName: "",
    email: "",
    password: "",
    confirmPassword: "",
    firstName: "",
    lastName: "",
    phoneNumber: "",
  })

  useEffect(() => {
    if (permissions.isLoading) {
      return
    }
    
    if (!permissions.isAdmin) {
      router.push("/dashboard")
    }
  }, [permissions.isAdmin, permissions.isLoading, router])

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setFormData({ ...formData, [e.target.name]: e.target.value })
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setError("")

    const { userId, farmId } = getUserContext()
    const farmName = localStorage.getItem("farmName") || "My Farm"

    if (!farmId) {
      setError("Farm information not found. Please log in again.")
      setLoading(false)
      return
    }

    if (formData.password !== formData.confirmPassword) {
      setError("Passwords do not match")
      setLoading(false)
      return
    }

    // Simple password requirements to match backend Identity (min 4 chars)
    const passwordErrors: string[] = []
    
    if (formData.password.length < 4) {
      passwordErrors.push("Password must be at least 4 characters long")
    }
    
    if (passwordErrors.length > 0) {
      setError(passwordErrors.join(", "))
      setLoading(false)
      return
    }

    if (!/^[a-zA-Z0-9_]+$/.test(formData.userName)) {
      setError("Username can only contain letters, digits, and underscores (no spaces or other special characters)")
      setLoading(false)
      return
    }

    const employeeData: CreateEmployeeData = {
      userName: formData.userName,
      email: formData.email,
      password: formData.password,
      firstName: formData.firstName,
      lastName: formData.lastName,
      phoneNumber: formData.phoneNumber,
      farmId: farmId,
      farmName: farmName,
    }

    const result = await createEmployee(employeeData)
    
    if (result.success) {
      setLoading(false)
      router.push("/employees")
    } else {
      const errorMessage = result.message || "Failed to create employee"
      setError(errorMessage)
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

  if (permissions.isLoading) {
    return (
      <div className="flex min-h-screen bg-slate-50">
        <DashboardSidebar onLogout={handleLogout} />
        <div className="flex-1 flex flex-col">
          <DashboardHeader />
          <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0 flex items-center justify-center">
            <p className="text-slate-600">Loading...</p>
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
                <h1 className="text-2xl font-bold text-slate-900">Add New Employee</h1>
                <p className="text-slate-600 text-sm">Create a new staff member with limited access</p>
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
              {/* Section: Personal Information */}
              <div className="rounded-xl border border-slate-200 overflow-hidden">
                <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Personal Information</div>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
                  <div className="space-y-2">
                    <Label htmlFor="firstName" className="text-sm font-medium text-slate-700">
                      First Name *
                    </Label>
                    <Input
                      id="firstName"
                      name="firstName"
                      type="text"
                      value={formData.firstName}
                      onChange={handleChange}
                      required
                      disabled={loading}
                      placeholder="John"
                    />
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="lastName" className="text-sm font-medium text-slate-700">
                      Last Name *
                    </Label>
                    <Input
                      id="lastName"
                      name="lastName"
                      type="text"
                      value={formData.lastName}
                      onChange={handleChange}
                      required
                      disabled={loading}
                      placeholder="Doe"
                    />
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="phoneNumber" className="text-sm font-medium text-slate-700">
                      Phone Number *
                    </Label>
                    <Input
                      id="phoneNumber"
                      name="phoneNumber"
                      type="tel"
                      value={formData.phoneNumber}
                      onChange={handleChange}
                      required
                      disabled={loading}
                      placeholder="+233 533431086"
                    />
                  </div>
                </div>
              </div>

              {/* Section: Account Information */}
              <div className="rounded-xl border border-slate-200 overflow-hidden">
                <div className="bg-green-600 px-4 py-2 text-sm font-semibold text-white">Account Information</div>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
                  <div className="space-y-2">
                    <Label htmlFor="userName" className="text-sm font-medium text-slate-700">
                      Username * <span className="text-xs text-slate-500 font-normal">(letters, digits, underscores only)</span>
                    </Label>
                    <Input
                      id="userName"
                      name="userName"
                      type="text"
                      value={formData.userName}
                      onChange={handleChange}
                      required
                      disabled={loading}
                      placeholder="james_quayson"
                      pattern="[a-zA-Z0-9_]+"
                    />
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="email" className="text-sm font-medium text-slate-700">
                      Email *
                    </Label>
                    <Input
                      id="email"
                      name="email"
                      type="email"
                      value={formData.email}
                      onChange={handleChange}
                      required
                      disabled={loading}
                      placeholder="employee@example.com"
                    />
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="password" className="text-sm font-medium text-slate-700">
                      Password *
                    </Label>
                    <Input
                      id="password"
                      name="password"
                      type="password"
                      value={formData.password}
                      onChange={handleChange}
                      required
                      disabled={loading}
                      placeholder="At least 4 characters"
                    />
                    <p className="text-xs text-slate-500">
                      Password must be at least 4 characters long.
                    </p>
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="confirmPassword" className="text-sm font-medium text-slate-700">
                      Confirm Password *
                    </Label>
                    <Input
                      id="confirmPassword"
                      name="confirmPassword"
                      type="password"
                      value={formData.confirmPassword}
                      onChange={handleChange}
                      required
                      disabled={loading}
                      placeholder="Re-enter password"
                    />
                  </div>
                </div>
              </div>

              {/* Form Actions */}
              <div className="flex gap-3 justify-end pt-2">
                <Button
                  type="button"
                  disabled={loading}
                  onClick={() => router.push("/employees")}
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
                    <><UserCog className="w-4 h-4 mr-2" />Create Employee</>
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
