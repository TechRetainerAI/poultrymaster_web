"use client"

import type React from "react"

import { useState, useEffect } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Textarea } from "@/components/ui/textarea"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { DollarSign, Loader2, ArrowLeft } from "lucide-react"
import { createExpense, type ExpenseInput } from "@/lib/api/expense"
import { getUserContext } from "@/lib/utils/user-context"
import { getValidFlocks, getFlocksForSelect } from "@/lib/utils/flock-utils"
import { Alert, AlertDescription } from "@/components/ui/alert"

export default function NewExpensePage() {
  const router = useRouter()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState("")
  const [flocks, setFlocks] = useState<{ value: string; label: string }[]>([])
  const [flocksLoading, setFlocksLoading] = useState(true)
  
  const [formData, setFormData] = useState({
    flockId: "",
    expenseDate: new Date().toISOString().split("T")[0],
    category: "",
    description: "",
    amount: "",
    paymentMethod: "",
  })

  const expenseCategories = [
    "Feed",
    "Veterinary",
    "Equipment",
    "Labor",
    "Utilities",
    "Other"
  ]

  const paymentMethods = [
    "Cash",
    "Credit Card",
    "Bank Transfer",
    "Check",
    "Other"
  ]

  useEffect(() => {
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

  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    const { name, value } = e.target
    setFormData({ ...formData, [name]: value })
  }

  const handleSelectChange = (name: string, value: string) => {
    setFormData({ ...formData, [name]: value })
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
      setError("Choose which flock this expense belongs to.")
      setLoading(false)
      return
    }

    if (!formData.category) {
      setError("Pick an expense category.")
      setLoading(false)
      return
    }

    if (!formData.description.trim()) {
      setError("Add a short description of this expense.")
      setLoading(false)
      return
    }

    if (!formData.amount || Number(formData.amount) <= 0) {
      setError("Enter the amount as a number greater than zero.")
      setLoading(false)
      return
    }

    if (!formData.paymentMethod) {
      setError("Select how this was paid (cash, mobile money, bank, etc.).")
      setLoading(false)
      return
    }

    const expense: ExpenseInput = {
      farmId,
      userId,
      flockId: Number(formData.flockId),
      expenseDate: formData.expenseDate + "T00:00:00Z",
      category: formData.category,
      description: formData.description.trim(),
      amount: Number(formData.amount),
      paymentMethod: formData.paymentMethod,
    }

    const result = await createExpense(expense)
    
    if (result.success) {
      router.push("/expenses")
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
              <Button variant="ghost" size="icon" onClick={() => router.push("/expenses")} className="shrink-0">
                <ArrowLeft className="w-5 h-5" />
              </Button>
              <div className="w-10 h-10 bg-green-100 rounded-lg flex items-center justify-center">
                <DollarSign className="w-5 h-5 text-green-600" />
              </div>
              <div>
                <h1 className="text-2xl font-bold text-slate-900">Add Expense</h1>
                <p className="text-slate-600 text-sm">Record a new farm expense</p>
              </div>
            </div>

            {error && (
              <Alert variant="destructive">
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}

            <form onSubmit={handleSubmit} className="space-y-6">
              {/* Section: Flock & Date */}
              <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Flock &amp; Date</div>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4">
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Select Flock *</Label>
                    <Select value={formData.flockId} onValueChange={(value) => handleSelectChange("flockId", value)}>
                      <SelectTrigger>
                        <SelectValue placeholder="Choose a flock" />
                      </SelectTrigger>
                      <SelectContent>
                        {flocksLoading ? (
                          <SelectItem value="loading" disabled>Loading flocks...</SelectItem>
                        ) : flocks.length === 0 ? (
                          <SelectItem value="no-flocks" disabled>No flocks available</SelectItem>
                        ) : (
                          flocks.map((flock) => (
                            <SelectItem key={flock.value} value={flock.value}>
                              {flock.label}
                            </SelectItem>
                          ))
                        )}
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Expense Date *</Label>
                    <Input
                      name="expenseDate"
                      type="date"
                      value={formData.expenseDate}
                      onChange={handleChange}
                      required
                    />
                  </div>
                </div>
              </div>

              {/* Section: Category & Payment */}
              <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Category &amp; Payment</div>
                <div className="grid grid-cols-1 md:grid-cols-3 gap-4 p-4">
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Category *</Label>
                    <Select value={formData.category} onValueChange={(value) => handleSelectChange("category", value)}>
                      <SelectTrigger>
                        <SelectValue placeholder="Select category" />
                      </SelectTrigger>
                      <SelectContent>
                        {expenseCategories.map((category) => (
                          <SelectItem key={category} value={category}>
                            {category}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Amount *</Label>
                    <Input
                      name="amount"
                      type="number"
                      step="0.01"
                      min="0"
                      value={formData.amount}
                      onChange={handleChange}
                      placeholder="0.00"
                      required
                      className="max-w-[200px]"
                    />
                  </div>
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Payment Method *</Label>
                    <Select value={formData.paymentMethod} onValueChange={(value) => handleSelectChange("paymentMethod", value)}>
                      <SelectTrigger>
                        <SelectValue placeholder="Select payment method" />
                      </SelectTrigger>
                      <SelectContent>
                        {paymentMethods.map((method) => (
                          <SelectItem key={method} value={method}>
                            {method}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                </div>
              </div>

              {/* Section: Description */}
              <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Description</div>
                <div className="p-4">
                  <Textarea
                    name="description"
                    value={formData.description}
                    onChange={handleChange}
                    placeholder="Enter expense description..."
                    rows={3}
                    required
                  />
                </div>
              </div>

              {/* Actions */}
              <div className="flex gap-3 justify-end pt-2">
                <Button
                  type="button"
                  onClick={() => router.push("/expenses")}
                  disabled={loading}
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
                    <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Creating...</>
                  ) : (
                    <><DollarSign className="w-4 h-4 mr-2" />Create Expense</>
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
