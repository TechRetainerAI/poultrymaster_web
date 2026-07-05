"use client"

import type React from "react"

import { useState, useEffect } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Textarea } from "@/components/ui/textarea"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { DollarSign, Loader2, ArrowLeft } from "lucide-react"
import { createExpense, type ExpenseInput } from "@/lib/api/expense"
import { listPoultryCashAccounts, type PoultryCashAccount } from "@/lib/api/poultry-finance"
import { uploadExpenseReceipt } from "@/lib/api/receipt-upload"
import { appendReceiptSuffix } from "@/lib/utils/expense-receipt"
import { ExpenseReceiptField } from "@/components/expense/expense-receipt-field"
import { getUserContext } from "@/lib/utils/user-context"
import { getFlockSelectEmptyHint } from "@/lib/utils/flock-utils"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { useBatchFlockSelect, BATCH_ALL } from "@/hooks/use-batch-flock-select"

// Sentinel for "not tied to a single flock" — stored as a farm-level expense
// (flockId = null), which the reports treat as an unallocated / all-flock cost.
const ALL_FLOCKS = "ALL"

export default function NewExpensePage() {
  const router = useRouter()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState("")
  // Batch + Flock dropdowns (James 2026-05-27).
  const {
    batchOptions,
    selectedBatchId,
    setSelectedBatchId,
    flockOptions: flocks,
    loading: flocksLoading,
    error: batchFlockError,
  } = useBatchFlockSelect()

  const [formData, setFormData] = useState({
    flockId: "",
    expenseDate: new Date().toISOString().split("T")[0],
    category: "",
    description: "",
    amount: "",
    paymentMethod: "",
    poultryCashAccountId: "",
  })
  const [receiptFile, setReceiptFile] = useState<File | null>(null)
  const [cashAccounts, setCashAccounts] = useState<PoultryCashAccount[]>([])

  // Load cash accounts so the expense can be paid from one (posts a cash-out).
  useEffect(() => {
    listPoultryCashAccounts().then((a) => setCashAccounts(a.filter((x) => x.isActive))).catch(() => setCashAccounts([]))
  }, [])

  const expenseCategories = [
    "Feed",
    "Veterinary",
    "Equipment",
    "Labor",
    "Utilities",
    "Other"
  ]

  // Mobile Money added 2026-05-27 (James). Ghana ops collect most non-cash
  // payments via MoMo; the previous list forced operators to pick "Other".
  const paymentMethods = [
    "Cash",
    "Mobile Money",
    "Credit Card",
    "Bank Transfer",
    "Check",
    "Other",
  ]

  // Surface load errors / empty-state from the hook.
  useEffect(() => {
    if (flocksLoading) return
    if (batchFlockError) { setError(batchFlockError); return }
    if (flocks.length === 0) setError(getFlockSelectEmptyHint("expense"))
    else setError("")
  }, [flocksLoading, batchFlockError, flocks.length])

  // Clear flockId if it's no longer in the filtered batch.
  useEffect(() => {
    if (selectedBatchId === BATCH_ALL) return
    if (!formData.flockId || formData.flockId === ALL_FLOCKS) return
    if (!flocks.some((o) => o.value === formData.flockId)) {
      setFormData((prev) => ({ ...prev, flockId: "" }))
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedBatchId, flocks])

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

    let descriptionOut = formData.description.trim()
    if (receiptFile) {
      const up = await uploadExpenseReceipt(receiptFile, farmId)
      if (!up.success) {
        setError(up.message || "Receipt upload failed")
        setLoading(false)
        return
      }
      descriptionOut = appendReceiptSuffix(descriptionOut, up.path!)
    }

    const expense: ExpenseInput = {
      farmId,
      userId,
      flockId: formData.flockId === ALL_FLOCKS ? null : Number(formData.flockId),
      poultryCashAccountId: formData.poultryCashAccountId ? Number(formData.poultryCashAccountId) : null,
      expenseDate: formData.expenseDate + "T00:00:00Z",
      category: formData.category,
      description: descriptionOut,
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
      <div className="flex-1 flex flex-col min-w-0">
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
                <div className="grid grid-cols-1 md:grid-cols-3 gap-4 p-4">
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Batch</Label>
                    <Select value={selectedBatchId} onValueChange={setSelectedBatchId}>
                      <SelectTrigger>
                        <SelectValue placeholder="All batches" />
                      </SelectTrigger>
                      <SelectContent>
                        {batchOptions.map((b) => (
                          <SelectItem key={b.value} value={b.value}>{b.label}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <div className="text-xs text-slate-500">Filters flocks below.</div>
                  </div>
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
                          <SelectItem value="no-flocks" disabled>{getFlockSelectEmptyHint("expense")}</SelectItem>
                        ) : (
                          <>
                            <SelectItem value={ALL_FLOCKS}>All flocks (farm-wide)</SelectItem>
                            {flocks.map((flock) => (
                              <SelectItem key={flock.value} value={flock.value}>
                                {flock.label}
                              </SelectItem>
                            ))}
                          </>
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
                    <NumberInput
                      name="amount"
                      
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
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Pay from cash account</Label>
                    <Select value={formData.poultryCashAccountId || "none"} onValueChange={(value) => handleSelectChange("poultryCashAccountId", value === "none" ? "" : value)}>
                      <SelectTrigger>
                        <SelectValue placeholder="None (no cash movement)" />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="none">None (no cash movement)</SelectItem>
                        {cashAccounts.map((a) => (
                          <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>
                            {a.accountName} ({a.currentBalance.toFixed(2)})
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <div className="text-xs text-slate-500">Posts a cash-out and reduces the account balance.</div>
                  </div>
                </div>
              </div>

              {/* Section: Description */}
              <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Description</div>
                <div className="p-4 space-y-4">
                  <Textarea
                    name="description"
                    value={formData.description}
                    onChange={handleChange}
                    placeholder="Enter expense description..."
                    rows={3}
                    required
                  />
                  <ExpenseReceiptField
                    existingPath={null}
                    resolveReceiptFarmId={getUserContext().farmId}
                    pendingFile={receiptFile}
                    onPendingFileChange={setReceiptFile}
                    disabled={loading}
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
