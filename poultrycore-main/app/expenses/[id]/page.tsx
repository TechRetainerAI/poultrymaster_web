"use client"

import type React from "react"

import { useEffect, useState } from "react"
import { useRouter, useParams, useSearchParams } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Textarea } from "@/components/ui/textarea"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { DollarSign } from "lucide-react"
import { getExpense, updateExpense, type ExpenseInput } from "@/lib/api/expense"
import { listPoultryCashAccounts, type PoultryCashAccount } from "@/lib/api/poultry-finance"
import { uploadExpenseReceipt } from "@/lib/api/receipt-upload"
import {
  appendReceiptSuffix,
  extractReceiptPathFromDescription,
  stripReceiptSuffixFromDescription,
} from "@/lib/utils/expense-receipt"
import { ExpenseReceiptField } from "@/components/expense/expense-receipt-field"
import { getUserContext } from "@/lib/utils/user-context"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { useBatchFlockSelect, BATCH_ALL } from "@/hooks/use-batch-flock-select"

// Sentinel for "not tied to a single flock" — stored as a farm-level expense
// (flockId = null), which the reports treat as an unallocated / all-flock cost.
const ALL_FLOCKS = "ALL"

export default function EditExpensePage() {
  const router = useRouter()
  const params = useParams()
  const rawId = params.id as string
  const id = Number.isFinite(Number(rawId)) ? Number(rawId) : parseInt(rawId, 10)
  const searchParams = useSearchParams()
  const [loading, setLoading] = useState(false)
  const [fetchLoading, setFetchLoading] = useState(true)
  const [error, setError] = useState("")
  // Batch + Flock dropdowns (James 2026-05-27).
  const {
    batchOptions,
    selectedBatchId,
    setSelectedBatchId,
    flockOptions: flocks,
    loading: flocksLoading,
  } = useBatchFlockSelect()
  
  const [formData, setFormData] = useState({
    flockId: "",
    expenseDate: "",
    category: "",
    description: "",
    amount: "",
    paymentMethod: "",
    poultryCashAccountId: "",
  })
  const [cashAccounts, setCashAccounts] = useState<PoultryCashAccount[]>([])
  const [receiptFile, setReceiptFile] = useState<File | null>(null)
  const [savedReceiptPath, setSavedReceiptPath] = useState<string | null>(null)
  const [receiptRemoved, setReceiptRemoved] = useState(false)
  /** For receipt URL resolution + DB attachment preview after load */
  const [expenseReceiptContext, setExpenseReceiptContext] = useState<{
    farmId: string
    userId: string
    hasDbAttachment: boolean
  } | null>(null)

  const expenseCategories = [
    "Feed",
    "Veterinary",
    "Equipment",
    "Labor",
    "Utilities",
    "Other"
  ]

  // Mobile Money added 2026-05-27 (James). Match /expenses (list) and /expenses/new.
  const paymentMethods = [
    "Cash",
    "Mobile Money",
    "Credit Card",
    "Bank Transfer",
    "Check",
    "Other",
  ]

  useEffect(() => {
    loadExpense()
    loadFlocks()
    listPoultryCashAccounts().then((a) => setCashAccounts(a.filter((x) => x.isActive))).catch(() => setCashAccounts([]))
  }, [id])

  const loadExpense = async () => {
    const { userId, farmId } = getUserContext()
    const qpFarmId = searchParams.get("farmId") || undefined
    const effectiveFarmId = qpFarmId || farmId
    if (!Number.isFinite(id)) {
      setError("Invalid expense id in URL")
      setFetchLoading(false)
      setExpenseReceiptContext(null)
      return
    }
    const result = await getExpense(id, userId, effectiveFarmId)

    if (result.success && result.data) {
      const expense = result.data
      const rawDesc = expense.description || ""
      setSavedReceiptPath(extractReceiptPathFromDescription(rawDesc))
      setReceiptRemoved(false)
      setReceiptFile(null)
      setExpenseReceiptContext(
        effectiveFarmId && userId
          ? {
              farmId: effectiveFarmId,
              userId,
              hasDbAttachment: Boolean(expense.hasAttachmentImage),
            }
          : null
      )
      setFormData({
        flockId: expense.flockId ? String(expense.flockId) : ALL_FLOCKS,
        expenseDate: new Date(expense.expenseDate).toISOString().split("T")[0],
        category: expense.category,
        description: stripReceiptSuffixFromDescription(rawDesc),
        amount: String(expense.amount),
        paymentMethod: expense.paymentMethod,
        poultryCashAccountId: expense.poultryCashAccountId ? String(expense.poultryCashAccountId) : "",
      })
    } else {
      setError(result.message)
      setExpenseReceiptContext(null)
    }

    setFetchLoading(false)
  }

  // Flock+Batch loading now lives in useBatchFlockSelect. Stub kept so the
  // existing loadFlocks() call site doesn't need renaming.
  const loadFlocks = async () => { /* no-op: handled by useBatchFlockSelect */ }

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
    const qpFarmId = searchParams.get("farmId") || undefined
    const effectiveFarmId = qpFarmId || farmId

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
      const up = await uploadExpenseReceipt(receiptFile, effectiveFarmId!)
      if (!up.success) {
        setError(up.message || "Receipt upload failed")
        setLoading(false)
        return
      }
      descriptionOut = appendReceiptSuffix(descriptionOut, up.path!)
    } else if (savedReceiptPath && !receiptRemoved) {
      descriptionOut = appendReceiptSuffix(descriptionOut, savedReceiptPath)
    }

    const expense: Partial<ExpenseInput> = {
      farmId: effectiveFarmId!,
      userId,
      flockId: formData.flockId === ALL_FLOCKS ? null : Number(formData.flockId),
      poultryCashAccountId: formData.poultryCashAccountId ? Number(formData.poultryCashAccountId) : null,
      expenseDate: formData.expenseDate + "T00:00:00Z",
      category: formData.category,
      description: descriptionOut,
      amount: Number(formData.amount),
      paymentMethod: formData.paymentMethod,
    }

    const result = await updateExpense(id, expense)
    
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

  if (fetchLoading) {
    return (
      <div className="flex min-h-screen bg-slate-50">
        <DashboardSidebar onLogout={handleLogout} />
        <div className="flex-1 flex flex-col min-w-0">
          <DashboardHeader />
          <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
            <div className="space-y-6">
              <div className="flex items-center justify-center h-64">
                <div className="text-center">
                  <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-green-600 mx-auto mb-4"></div>
                  <p className="text-slate-600">Loading expense...</p>
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
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6 space-y-6">
            {/* Page Header */}
            <div className="flex items-center gap-3 mb-6">
              <div className="w-10 h-10 bg-green-100 rounded-lg flex items-center justify-center">
                <DollarSign className="w-5 h-5 text-green-600" />
              </div>
              <div>
                <h1 className="text-2xl font-bold text-slate-900">Edit Expense</h1>
                <p className="text-slate-600">Update expense information</p>
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
                <h3 className="text-lg font-semibold text-slate-900">Expense Information</h3>
                <p className="text-sm text-slate-600">
                  Update the expense details below
                </p>
                <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                  <div className="space-y-2">
                    <Label className="text-sm font-medium text-slate-700">Batch</Label>
                    <Select value={selectedBatchId} onValueChange={(v) => {
                      setSelectedBatchId(v)
                      // Clear flockId if the current selection is no longer in the filtered batch.
                      if (v !== BATCH_ALL && formData.flockId && formData.flockId !== ALL_FLOCKS && !flocks.some((f) => f.value === formData.flockId)) {
                        setFormData((prev) => ({ ...prev, flockId: "" }))
                      }
                    }}>
                      <SelectTrigger><SelectValue placeholder="All batches" /></SelectTrigger>
                      <SelectContent>
                        {batchOptions.map((b) => (
                          <SelectItem key={b.value} value={b.value}>{b.label}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <div className="text-xs text-slate-500">Filters flocks below.</div>
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="flockId" className="text-sm font-medium text-slate-700">
                      Select Flock *
                    </Label>
                    <Select value={formData.flockId} onValueChange={(value) => handleSelectChange("flockId", value)}>
                      <SelectTrigger>
                        <SelectValue placeholder="Choose a flock" />
                      </SelectTrigger>
                      <SelectContent>
                        {flocksLoading ? (
                          <SelectItem value="loading" disabled>Loading flocks...</SelectItem>
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
                    <Label htmlFor="expenseDate" className="text-sm font-medium text-slate-700">
                      Expense Date *
                    </Label>
                    <Input
                      id="expenseDate"
                      name="expenseDate"
                      type="date"
                      value={formData.expenseDate}
                      onChange={handleChange}
                      required
                      className="w-full"
                    />
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="category" className="text-sm font-medium text-slate-700">
                      Category *
                    </Label>
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
                    <Label htmlFor="paymentMethod" className="text-sm font-medium text-slate-700">
                      Payment Method *
                    </Label>
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
                    <div className="text-xs text-slate-500">Changing this re-posts the cash-out on save.</div>
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="amount" className="text-sm font-medium text-slate-700">
                      Amount ($) *
                    </Label>
                    <NumberInput
                      id="amount"
                      name="amount"
                      
                      step="0.01"
                      min="0"
                      value={formData.amount}
                      onChange={handleChange}
                      placeholder="0.00"
                      required
                      className="w-full"
                    />
                  </div>
                </div>

                <div className="space-y-2">
                  <Label htmlFor="description" className="text-sm font-medium text-slate-700">
                    Description *
                  </Label>
                  <Textarea
                    id="description"
                    name="description"
                    value={formData.description}
                    onChange={handleChange}
                    placeholder="Enter expense description..."
                    rows={3}
                    required
                    className="w-full"
                  />
                  <ExpenseReceiptField
                    existingPath={receiptRemoved ? null : savedReceiptPath}
                    resolveReceiptFarmId={expenseReceiptContext?.farmId ?? null}
                    dbAttachment={
                      expenseReceiptContext?.hasDbAttachment
                        ? {
                            expenseId: id,
                            userId: expenseReceiptContext.userId,
                            farmId: expenseReceiptContext.farmId,
                          }
                        : null
                    }
                    pendingFile={receiptFile}
                    onPendingFileChange={setReceiptFile}
                    onRemoveExisting={() => {
                      setReceiptRemoved(true)
                      setSavedReceiptPath(null)
                    }}
                    disabled={loading}
                  />
                </div>
              </div>

              {/* Action Buttons */}
              <div className="flex items-center justify-end gap-4">
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => router.push("/expenses")}
                  disabled={loading}
                >
                  Cancel
                </Button>
                <Button
                  type="submit"
                  disabled={loading || flocksLoading}
                  className="flex items-center gap-2"
                >
                  {loading ? (
                    <>
                      <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white"></div>
                      Updating...
                    </>
                  ) : (
                    <>
                      <DollarSign className="w-4 h-4" />
                      Update Expense
                    </>
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
