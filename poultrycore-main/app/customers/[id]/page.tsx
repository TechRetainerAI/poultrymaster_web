"use client"

import type React from "react"

import { useEffect, useState } from "react"
import { useRouter, useParams } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Pencil } from "lucide-react"
import { getCustomer, updateCustomer, type CustomerInput } from "@/lib/api/customer"
import { getUserContext } from "@/lib/utils/user-context"
import { Alert, AlertDescription } from "@/components/ui/alert"

export default function EditCustomerPage() {
  const router = useRouter()
  const params = useParams()
  const id = Number(params.id)
  const [loading, setLoading] = useState(false)
  const [fetchLoading, setFetchLoading] = useState(true)
  const [error, setError] = useState("")
  const [formData, setFormData] = useState({
    name: "",
    contactEmail: "",
    contactPhone: "",
    address: "",
    city: "",
  })

  useEffect(() => {
    loadCustomer()
  }, [])

  const loadCustomer = async () => {
    const { userId, farmId } = getUserContext()
    const result = await getCustomer(id, userId, farmId)

    if (result.success && result.data) {
      const customer = result.data
      setFormData({
        name: customer.name,
        contactEmail: customer.contactEmail,
        contactPhone: customer.contactPhone,
        address: customer.address,
        city: customer.city,
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

    const customer: CustomerInput = {
      farmId,
      userId,
      ...formData,
    }

    const result = await updateCustomer(id, customer)

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
          <main className="overflow-y-visible p-6">
            <div className="flex items-center justify-center h-full">
              <div className="text-center">
                <div className="w-8 h-8 border-4 border-blue-600 border-t-transparent rounded-full animate-spin mx-auto mb-4"></div>
                <p className="text-slate-600">Loading customer...</p>
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
        <main className="overflow-y-visible p-6">
          <div className="space-y-6 space-y-6">
            {/* Page Header */}
            <div className="flex items-center gap-3 mb-6">
              <div className="w-10 h-10 bg-green-100 rounded-lg flex items-center justify-center">
                <Pencil className="w-5 h-5 text-green-600" />
              </div>
              <div>
                <h1 className="text-2xl font-bold text-slate-900">Edit Customer</h1>
                <p className="text-slate-600">Update customer information</p>
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
              {/* Form Fields */}
              <div className="space-y-6">
                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
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
                      className="h-11 border-slate-200 focus:border-blue-500 focus:ring-blue-500"
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
                      className="h-11 border-slate-200 focus:border-blue-500 focus:ring-blue-500"
                    />
                  </div>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
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
                      className="h-11 border-slate-200 focus:border-blue-500 focus:ring-blue-500"
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
                      className="h-11 border-slate-200 focus:border-blue-500 focus:ring-blue-500"
                    />
                  </div>
                </div>

                <div className="space-y-2">
                  <Label htmlFor="address" className="text-sm font-medium text-slate-700">
                    Address *
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
                    className="h-11 border-slate-200 focus:border-blue-500 focus:ring-blue-500"
                  />
                </div>
              </div>

              {/* Form Actions */}
              <div className="flex gap-4">
                <Button
                  type="button"
                  variant="outline"
                  className="flex-1 h-11 border-slate-200"
                  disabled={loading}
                  onClick={() => router.push("/customers")}
                >
                  Cancel
                </Button>
                <Button
                  type="submit"
                  className="flex-1 h-11 bg-blue-600 hover:bg-blue-700"
                  disabled={loading}
                >
                  {loading ? "Updating..." : "Update Customer"}
                </Button>
              </div>
            </form>
          </div>
        </main>
      </div>
    </div>
  )
}