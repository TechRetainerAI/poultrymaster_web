"use client"

import type React from "react"

import { useState } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { UserPlus, ArrowLeft, Loader2 } from "lucide-react"
import { createCustomer, type CustomerInput } from "@/lib/api/customer"
import { getUserContext } from "@/lib/utils/user-context"
import { Alert, AlertDescription } from "@/components/ui/alert"

export default function NewCustomerPage() {
  const router = useRouter()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState("")
  const [formData, setFormData] = useState({
    name: "",
    contactEmail: "",
    contactPhone: "",
    address: "",
    city: "",
  })

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setFormData({ ...formData, [e.target.name]: e.target.value })
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

    const customer: CustomerInput = {
      farmId,
      userId,
      ...formData,
    }

    const result = await createCustomer(customer)

    if (result.success) {
      router.push("/customers")
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
              <Button variant="ghost" size="icon" onClick={() => router.push("/customers")} className="shrink-0">
                <ArrowLeft className="w-5 h-5" />
              </Button>
              <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center">
                <UserPlus className="w-5 h-5 text-blue-600" />
              </div>
              <div>
                <h1 className="text-2xl font-bold text-slate-900">Add New Customer</h1>
                <p className="text-slate-600 text-sm">Enter the customer information below</p>
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
                    <Label htmlFor="name" className="text-sm font-medium text-slate-700">
                      Full Name *
                    </Label>
                    <Input
                      id="name"
                      name="name"
                      type="text"
                      placeholder="John Doe"
                      value={formData.name}
                      onChange={handleChange}
                      required
                      disabled={loading}
                    />
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="contactPhone" className="text-sm font-medium text-slate-700">
                      Phone Number *
                    </Label>
                    <Input
                      id="contactPhone"
                      name="contactPhone"
                      type="tel"
                      placeholder="+1 (555) 123-4567"
                      value={formData.contactPhone}
                      onChange={handleChange}
                      required
                      disabled={loading}
                    />
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="contactEmail" className="text-sm font-medium text-slate-700">
                      Email Address
                    </Label>
                    <Input
                      id="contactEmail"
                      name="contactEmail"
                      type="text"
                      placeholder="john@example.com (optional)"
                      value={formData.contactEmail}
                      onChange={handleChange}
                      disabled={loading}
                    />
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="city" className="text-sm font-medium text-slate-700">
                      City *
                    </Label>
                    <Input
                      id="city"
                      name="city"
                      type="text"
                      placeholder="New York"
                      value={formData.city}
                      onChange={handleChange}
                      required
                      disabled={loading}
                    />
                  </div>
                </div>
              </div>

              {/* Section: Address */}
              <div className="rounded-xl border border-slate-200 overflow-hidden">
                <div className="bg-green-600 px-4 py-2 text-sm font-semibold text-white">Address</div>
                <div className="p-4 bg-white">
                  <div className="space-y-2">
                    <Label htmlFor="address" className="text-sm font-medium text-slate-700">
                      Full Address *
                    </Label>
                    <Input
                      id="address"
                      name="address"
                      type="text"
                      placeholder="123 Main Street, Apt 4B"
                      value={formData.address}
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
                  onClick={() => router.push("/customers")}
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
                    <><UserPlus className="w-4 h-4 mr-2" />Create Customer</>
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
