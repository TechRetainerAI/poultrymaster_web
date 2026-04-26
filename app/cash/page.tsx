"use client"

import { useEffect, useState, useRef, useMemo } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Wallet, Copy, ChevronDown, ChevronUp, Mic, MicOff, Send, Plus, Pencil, Trash2 } from "lucide-react"
import { getUserContext } from "@/lib/utils/user-context"
import {
  getCashSummary,
  createCashAdjustment,
  updateCashAdjustment,
  deleteCashAdjustment,
  type CashAdjustmentInput,
  type CashSummary,
  type CashTransaction,
} from "@/lib/api/cash"
import { formatCurrency, getSelectedCurrency } from "@/lib/utils/currency"
import { useIsMobile } from "@/hooks/use-mobile"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { formatDateShort, cn } from "@/lib/utils"
import { useToast } from "@/hooks/use-toast"
import { toastFormGuide } from "@/lib/utils/validation-toast"
import { SortableHeader, type SortDirection, sortData } from "@/components/ui/sortable-header"

const ADJUSTMENT_TYPES = [
  { value: "OpeningBalance", label: "Opening Balance" },
  { value: "OwnerInjection", label: "Owner injection" },
  { value: "LoanReceived", label: "Loan received" },
  { value: "Withdrawal", label: "Withdrawal" },
  { value: "Correction", label: "Correction" },
] as const
type AdjustmentType = (typeof ADJUSTMENT_TYPES)[number]["value"]
const ADJUSTMENT_TYPE_BY_LABEL: Record<string, AdjustmentType> = {
  "opening balance": "OpeningBalance",
  "owner injection": "OwnerInjection",
  "loan received": "LoanReceived",
  withdrawal: "Withdrawal",
  correction: "Correction",
}

export default function CashPage() {
  const router = useRouter()
  const { toast } = useToast()
  const [loading, setLoading] = useState(true)
  const [summary, setSummary] = useState<CashSummary | null>(null)
  const [error, setError] = useState("")
  const [askInput, setAskInput] = useState("")
  const [adjustmentDialogOpen, setAdjustmentDialogOpen] = useState(false)
  const [adjustmentForm, setAdjustmentForm] = useState({
    adjustmentType: "OpeningBalance" as AdjustmentType,
    amount: "",
    description: "",
    adjustmentDate: new Date().toISOString().split("T")[0],
  })
  const [isListening, setIsListening] = useState(false)
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [editingAdjustmentId, setEditingAdjustmentId] = useState<number | null>(null)
  const [showAllColumnsMobile, setShowAllColumnsMobile] = useState(false)
  const [typeFilter, setTypeFilter] = useState("ALL")
  const [descriptionFilter, setDescriptionFilter] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [inFilter, setInFilter] = useState("")
  const [outFilter, setOutFilter] = useState("")
  const [sortKey, setSortKey] = useState<string | null>("date")
  const [sortDirection, setSortDirection] = useState<SortDirection>("desc")
  const isMobile = useIsMobile()
  const recognitionRef = useRef<any>(null)

  const { userId, farmId } = getUserContext()

  useEffect(() => {
    if (!userId || !farmId) {
      router.push("/login")
      return
    }
    loadData()
  }, [userId, farmId])

  const loadData = async () => {
    setLoading(true)
    setError("")
    try {
      const res = await getCashSummary(userId!, farmId!)
      if (res.success && res.data) {
        setSummary(res.data)
      } else {
        setError(res.message || "Failed to load cash summary")
      }
    } catch (err) {
      console.error("Failed to load cash data:", err)
      setError("Failed to load cash data")
    } finally {
      setLoading(false)
    }
  }

  const handleCopyBalance = () => {
    const balance = summary?.currentCash ?? 0
    navigator.clipboard.writeText(String(balance.toFixed(2)))
    toast({ title: "Copied", description: "Cash balance copied to clipboard" })
  }

  const handleSaveAdjustment = async () => {
    const amount = parseFloat(adjustmentForm.amount)
    if (!Number.isFinite(amount) || amount === 0) {
      toastFormGuide(toast, "Enter the adjustment amount as a number — any value except zero is fine.")
      return
    }
    if (!userId || !farmId) {
      toast({ title: "Session issue", description: "We could not confirm your farm or user. Please sign in again.", variant: "destructive" })
      return
    }

    const inputBase = {
      adjustmentDate: adjustmentForm.adjustmentDate || new Date().toISOString().split("T")[0],
      adjustmentType: adjustmentForm.adjustmentType,
      amount: adjustmentForm.adjustmentType === "Withdrawal" ? -Math.abs(amount) : Math.abs(amount),
      description: adjustmentForm.description || undefined,
    }

    if (editingAdjustmentId !== null) {
      const res = await updateCashAdjustment(editingAdjustmentId, {
        farmId,
        ...inputBase,
      })
      if (!res.success) {
        toast({ title: "Failed", description: res.message || "Failed to update adjustment", variant: "destructive" })
        return
      }
      toast({ title: "Adjustment updated", description: `${adjustmentForm.adjustmentType} updated` })
    } else {
      const input: CashAdjustmentInput = {
        userId,
        farmId,
        ...inputBase,
      }
      const res = await createCashAdjustment(input)
      if (!res.success) {
        toast({ title: "Failed", description: res.message || "Failed to add adjustment", variant: "destructive" })
        return
      }
      toast({ title: "Adjustment added", description: `${adjustmentForm.adjustmentType} recorded` })
    }

    setAdjustmentDialogOpen(false)
    setEditingAdjustmentId(null)
    setAdjustmentForm({
      adjustmentType: "OpeningBalance",
      amount: "",
      description: "",
      adjustmentDate: new Date().toISOString().split("T")[0],
    })
    loadData()
  }

  const getAdjustmentIdFromSortKey = (sortKey?: string) => {
    if (!sortKey) return null
    const suffix = sortKey.split("_").pop() || ""
    if (!/^\d+$/.test(suffix)) return null
    const id = Number(suffix)
    return Number.isFinite(id) ? id : null
  }

  const isSystemTransaction = (transaction: CashTransaction) => {
    const type = (transaction.type || "").trim().toLowerCase()
    return type === "sale" || type === "sales" || type === "expense" || type === "expenses"
  }

  const canManageTransaction = (transaction: CashTransaction) => {
    return !isSystemTransaction(transaction) && getAdjustmentIdFromSortKey(transaction.sortKey) !== null
  }

  const openCreateAdjustmentDialog = () => {
    setEditingAdjustmentId(null)
    setAdjustmentForm({
      adjustmentType: "OpeningBalance",
      amount: "",
      description: "",
      adjustmentDate: new Date().toISOString().split("T")[0],
    })
    setAdjustmentDialogOpen(true)
  }

  const handleEditTransaction = (transaction: CashTransaction) => {
    if (isSystemTransaction(transaction)) {
      toast({
        title: "Cannot edit this row",
        description: "Sales and Expense transactions must be edited from their own pages.",
        variant: "destructive",
      })
      return
    }

    const adjustmentId = getAdjustmentIdFromSortKey(transaction.sortKey)
    if (adjustmentId === null) {
      toast({
        title: "Cannot edit this row",
        description: "Only cash adjustments can be edited here.",
        variant: "destructive",
      })
      return
    }

    const normalizedType = (transaction.type || "").trim().toLowerCase()
    const mappedType = ADJUSTMENT_TYPE_BY_LABEL[normalizedType] || "Correction"
    const amountValue = transaction.in > 0 ? transaction.in : transaction.out

    setEditingAdjustmentId(adjustmentId)
    setAdjustmentForm({
      adjustmentType: mappedType,
      amount: String(amountValue || ""),
      description: transaction.description || "",
      adjustmentDate: (transaction.date || new Date().toISOString()).split("T")[0],
    })
    setAdjustmentDialogOpen(true)
  }

  const handleDeleteTransaction = async (transaction: CashTransaction) => {
    if (!farmId) {
      toast({ title: "Session issue", description: "We could not confirm your farm or user. Please sign in again.", variant: "destructive" })
      return
    }
    if (isSystemTransaction(transaction)) {
      toast({
        title: "Cannot delete this row",
        description: "Sales and Expense transactions must be deleted from their own pages.",
        variant: "destructive",
      })
      return
    }

    const adjustmentId = getAdjustmentIdFromSortKey(transaction.sortKey)
    if (adjustmentId === null) {
      toast({
        title: "Cannot delete this row",
        description: "Only cash adjustments can be deleted here.",
        variant: "destructive",
      })
      return
    }

    const confirmed = window.confirm("Delete this cash adjustment?")
    if (!confirmed) return

    const res = await deleteCashAdjustment(adjustmentId, farmId)
    if (!res.success) {
      toast({ title: "Failed", description: res.message || "Failed to delete adjustment", variant: "destructive" })
      return
    }

    toast({ title: "Deleted", description: "Cash adjustment deleted successfully." })
    loadData()
  }

  // Voice input (Web Speech API)
  const startListening = () => {
    if (typeof window === "undefined") return
    const SpeechRecognition = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition
    if (!SpeechRecognition) {
      toast({ title: "Not supported", description: "Voice input is not supported in this browser.", variant: "destructive" })
      return
    }
    const recognition = new SpeechRecognition()
    recognition.continuous = false
    recognition.interimResults = false
    recognition.lang = "en-US"
    recognition.onresult = (e: any) => {
      const transcript = Array.from(e.results)
        .map((r: any) => r[0].transcript)
        .join("")
      setAskInput((prev) => (prev ? `${prev} ${transcript}` : transcript))
    }
    recognition.onend = () => setIsListening(false)
    recognition.onerror = () => setIsListening(false)
    recognitionRef.current = recognition
    recognition.start()
    setIsListening(true)
  }

  const stopListening = () => {
    recognitionRef.current?.stop()
    setIsListening(false)
  }

  // Parse natural language and create adjustment, or open dialog
  const parseAndSubmit = (text: string): { type: string; amount: number } | null => {
    const t = text.toLowerCase().trim()
    const numMatch = t.match(/(\d+(?:\.\d+)?)/)
    const amount = numMatch ? parseFloat(numMatch[1]) : 0
    if (!Number.isFinite(amount) || amount <= 0) return null

    if (/\b(opening|opening balance|start)\b/.test(t)) return { type: "OpeningBalance", amount }
    if (/\b(owner injection|injection|inject)\b/.test(t)) return { type: "OwnerInjection", amount }
    if (/\b(loan|loan received)\b/.test(t)) return { type: "LoanReceived", amount }
    if (/\b(withdrawal|withdraw|take out)\b/.test(t)) return { type: "Withdrawal", amount }
    if (/\b(correction|correct|fix)\b/.test(t)) return { type: "Correction", amount }
    if (/\b(add|add)\s+\d+/.test(t) && amount > 0) return { type: "OwnerInjection", amount }
    return null
  }

  const handleAskSubmit = async () => {
    const text = askInput.trim()
    if (!text) return
    if (!userId || !farmId) {
      toast({ title: "Session issue", description: "We could not confirm your farm or user. Please sign in again.", variant: "destructive" })
      return
    }

    setIsSubmitting(true)
    const parsed = parseAndSubmit(text)

    if (parsed) {
      const input: CashAdjustmentInput = {
        userId,
        farmId,
        adjustmentDate: new Date().toISOString().split("T")[0],
        adjustmentType: parsed.type as any,
        amount: parsed.type === "Withdrawal" ? -parsed.amount : parsed.amount,
        description: text,
      }
      const res = await createCashAdjustment(input)
      if (res.success) {
        toast({ title: "Done", description: `${parsed.type} of ${formatCurrency(Math.abs(parsed.amount), currency)} added` })
        setAskInput("")
        loadData()
      } else {
        toast({ title: "Failed", description: res.message, variant: "destructive" })
      }
    } else {
      setAdjustmentForm((prev) => ({ ...prev, description: text }))
      setAdjustmentDialogOpen(true)
      setAskInput("")
      toast({ title: "Add details", description: "Enter amount and type in the dialog" })
    }
    setIsSubmitting(false)
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

  const currency = getSelectedCurrency()
  const transactions = summary?.transactions ?? []
  const totalOwed = useMemo(
    () => transactions.reduce((sum, t) => sum + Math.max(0, Number(t.owed) || 0), 0),
    [transactions],
  )
  const distinctTypes = useMemo(
    () => Array.from(new Set(transactions.map((t) => t.type).filter(Boolean))).sort(),
    [transactions]
  )

  const filteredTransactions = useMemo(() => {
    let list = transactions.slice()

    if (typeFilter !== "ALL") list = list.filter((t) => t.type === typeFilter)

    if (descriptionFilter.trim()) {
      const q = descriptionFilter.toLowerCase()
      list = list.filter((t) => (t.description || "").toLowerCase().includes(q))
    }

    if (dateFrom) list = list.filter((t) => (t.date || "").split("T")[0] >= dateFrom)
    if (dateTo) list = list.filter((t) => (t.date || "").split("T")[0] <= dateTo)

    if (inFilter.trim()) {
      const minIn = Number(inFilter)
      if (!Number.isNaN(minIn)) list = list.filter((t) => Number(t.in || 0) >= minIn)
    }

    if (outFilter.trim()) {
      const minOut = Number(outFilter)
      if (!Number.isNaN(minOut)) list = list.filter((t) => Number(t.out || 0) >= minOut)
    }

    return list
  }, [transactions, typeFilter, descriptionFilter, dateFrom, dateTo, inFilter, outFilter])

  const sortedTransactions = useMemo(
    () =>
      sortData(filteredTransactions, sortKey, sortDirection, (item, key) => {
        switch (key) {
          case "date":
            return new Date(item.date)
          case "type":
            return item.type || ""
          case "description":
            return item.description || ""
          case "in":
            return Number(item.in) || 0
          case "owed":
            return Number(item.owed) || 0
          case "out":
            return Number(item.out) || 0
          case "balance":
            return Number(item.balance) || 0
          default:
            return (item as any)[key]
        }
      }),
    [filteredTransactions, sortKey, sortDirection]
  )

  const handleSort = (key: string) => {
    if (sortKey !== key) {
      setSortKey(key)
      setSortDirection(key === "date" ? "desc" : "asc")
      return
    }
    setSortDirection(sortDirection === "asc" ? "desc" : "asc")
  }

  const clearFilters = () => {
    setTypeFilter("ALL")
    setDescriptionFilter("")
    setDateFrom("")
    setDateTo("")
    setInFilter("")
    setOutFilter("")
    setSortKey("date")
    setSortDirection("desc")
  }

  const lastUpdated = summary?.lastUpdated ? new Date(summary.lastUpdated) : null

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6">
            {/* Page Header */}
            <div className={cn("flex gap-4", isMobile ? "flex-col" : "items-start")}>
              <div>
                <div className="flex items-center gap-3 mb-2">
                  <div className="w-10 h-10 bg-emerald-100 rounded-lg flex items-center justify-center">
                    <Wallet className="w-5 h-5 text-emerald-600" />
                  </div>
                  <h1 className={cn("font-bold text-slate-900", isMobile ? "text-xl" : "text-2xl")}>Financial → Cash</h1>
                </div>
                <p className="text-sm text-slate-600">Cash at hand and transaction history</p>
              </div>
            </div>

            {error && (
              <div className="rounded-md bg-red-50 border border-red-200 px-4 py-3 text-sm text-red-700">
                {error}
              </div>
            )}

            {/* Top Summary Card */}
            <Card className="border-emerald-200 bg-emerald-50/50">
              <CardHeader className="pb-2">
                <div className={cn("flex justify-between gap-4", isMobile && "flex-col")}>
                  <CardDescription>Current Cash at Hand</CardDescription>
                  <Dialog
                    open={adjustmentDialogOpen}
                    onOpenChange={(open) => {
                      setAdjustmentDialogOpen(open)
                      if (!open) setEditingAdjustmentId(null)
                    }}
                  >
                    <DialogTrigger asChild>
                      <Button variant="outline" size="sm" className="gap-1.5" onClick={openCreateAdjustmentDialog}>
                        <Plus className="h-4 w-4" />
                        Add Adjustment
                      </Button>
                    </DialogTrigger>
                    <DialogContent>
                      <DialogHeader>
                        <DialogTitle>{editingAdjustmentId !== null ? "Edit Cash Adjustment" : "Cash Adjustment"}</DialogTitle>
                        <DialogDescription>
                          {editingAdjustmentId !== null
                            ? "Update opening balance, owner injection, loan received, withdrawal, or correction."
                            : "Add opening balance, owner injection, loan received, withdrawal, or correction."}
                        </DialogDescription>
                      </DialogHeader>
                      <div className="space-y-4 py-4">
                        <div className="space-y-2">
                          <Label>Type</Label>
                          <Select
                            value={adjustmentForm.adjustmentType}
                            onValueChange={(v) => setAdjustmentForm((prev) => ({ ...prev, adjustmentType: v as typeof prev.adjustmentType }))}
                          >
                            <SelectTrigger>
                              <SelectValue />
                            </SelectTrigger>
                            <SelectContent>
                              {ADJUSTMENT_TYPES.map((t) => (
                                <SelectItem key={t.value} value={t.value}>
                                  {t.label}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                        <div className="space-y-2">
                          <Label>Date</Label>
                          <Input
                            type="date"
                            value={adjustmentForm.adjustmentDate}
                            onChange={(e) => setAdjustmentForm((prev) => ({ ...prev, adjustmentDate: e.target.value }))}
                          />
                        </div>
                        <div className="space-y-2">
                          <Label>Amount ({currency})</Label>
                          <Input
                            type="number"
                            step="0.01"
                            placeholder="0.00"
                            value={adjustmentForm.amount}
                            onChange={(e) => setAdjustmentForm((prev) => ({ ...prev, amount: e.target.value }))}
                          />
                        </div>
                        <div className="space-y-2">
                          <Label>Description (optional)</Label>
                          <Input
                            placeholder="e.g. Start of cycle"
                            value={adjustmentForm.description}
                            onChange={(e) => setAdjustmentForm((prev) => ({ ...prev, description: e.target.value }))}
                          />
                        </div>
                        <Button onClick={handleSaveAdjustment}>{editingAdjustmentId !== null ? "Update" : "Save"}</Button>
                      </div>
                    </DialogContent>
                  </Dialog>
                </div>
              </CardHeader>
              <CardContent>
                <div className={cn("flex gap-4", isMobile ? "flex-col" : "items-start justify-between")}>
                  <div className={cn("grid gap-4", isMobile ? "grid-cols-1" : "grid-cols-2")}>
                    <div>
                      <div className="text-xs font-medium uppercase tracking-wide text-slate-500">Cash at hand</div>
                      <div className="mt-1 flex items-center gap-2">
                        <span className="text-2xl font-bold text-slate-900">
                          {formatCurrency(summary?.currentCash ?? 0, currency)}
                        </span>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-8 w-8 text-slate-500 hover:text-slate-700"
                          onClick={handleCopyBalance}
                          aria-label="Copy balance"
                        >
                          <Copy className="h-4 w-4" />
                        </Button>
                      </div>
                    </div>
                    <div>
                      <div className="text-xs font-medium uppercase tracking-wide text-slate-500">Total owed</div>
                      <div className="mt-1 text-2xl font-bold text-amber-700">
                        {formatCurrency(totalOwed, currency)}
                      </div>
                    </div>
                  </div>
                  <div className="text-sm text-slate-500">
                    Last Updated: {lastUpdated ? lastUpdated.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" }) : "—"}
                  </div>
                </div>
                <p className="text-xs text-slate-500 mt-2">
                  Computed: Opening Balance + Paid Sales + Other Income − Expenses
                </p>
              </CardContent>
            </Card>

            {/* Transaction Table */}
            <Card>
              <CardHeader>
                <CardTitle>Transaction History</CardTitle>
                <CardDescription>Balance is always auto-calculated</CardDescription>
                <div className={cn("grid gap-2 pt-3", isMobile ? "grid-cols-2" : "grid-cols-7")}>
                  <Select value={typeFilter} onValueChange={setTypeFilter}>
                    <SelectTrigger className={cn(isMobile ? "col-span-2" : "col-span-1")}>
                      <SelectValue placeholder="Type" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="ALL">All Types</SelectItem>
                      {distinctTypes.map((type) => (
                        <SelectItem key={type} value={type}>{type}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <Input
                    placeholder="Description..."
                    value={descriptionFilter}
                    onChange={(e) => setDescriptionFilter(e.target.value)}
                    className={cn(isMobile ? "col-span-2" : "col-span-2")}
                  />
                  <Input type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
                  <Input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
                  <Input type="number" step="0.01" placeholder="In >=" value={inFilter} onChange={(e) => setInFilter(e.target.value)} />
                  <Input type="number" step="0.01" placeholder="Out >=" value={outFilter} onChange={(e) => setOutFilter(e.target.value)} />
                </div>
                <div className="pt-2">
                  <Button variant="outline" size="sm" onClick={clearFilters}>Reset Filters</Button>
                </div>
              </CardHeader>
              <CardContent>
                {loading ? (
                  <p className="text-slate-600 py-8 text-center">Loading...</p>
                ) : sortedTransactions.length === 0 ? (
                  <p className="text-slate-600 py-8 text-center">No transactions yet. Add sales, expenses, or cash adjustments to see cash flow.</p>
                ) : isMobile && !showAllColumnsMobile ? (
                  <div className="divide-y divide-slate-100 -mx-6 -mb-6">
                    {sortedTransactions.map((t, idx) => (
                      <Collapsible key={idx} className={cn("group rounded-xl border shadow-sm overflow-hidden", idx % 2 === 0 ? "bg-amber-100 border-amber-300" : "bg-white border-slate-200")}>
                        <div className={cn("p-4 active:bg-slate-50/80 transition-colors", idx % 2 === 1 && "bg-slate-50/20")}>
                          <CollapsibleTrigger asChild>
                            <div className="flex items-start justify-between gap-3 cursor-pointer">
                              <div className="min-w-0 flex-1">
                                <div className="font-semibold text-slate-900">{t.date ? formatDateShort(t.date) : "—"}</div>
                                <div className="mt-1 flex items-baseline gap-2">
                                  <span className="text-slate-600">{t.type}</span>
                                  <span className={cn("font-bold", t.in > 0 ? "text-emerald-600" : "text-red-600")}>
                                    {t.in > 0 ? `+${formatCurrency(t.in, currency)}` : t.out > 0 ? `-${formatCurrency(t.out, currency)}` : "—"}
                                  </span>
                                  {(Number(t.owed) || 0) > 0 && (
                                    <span className="font-bold text-amber-700">
                                      Owed: {formatCurrency(Number(t.owed), currency)}
                                    </span>
                                  )}
                                </div>
                              </div>
                              <div className="font-medium shrink-0">{formatCurrency(t.balance, currency)}</div>
                              <ChevronDown className="h-5 w-5 text-slate-400 shrink-0 transition-transform group-data-[state=open]:rotate-180" />
                            </div>
                          </CollapsibleTrigger>
                          <CollapsibleContent>
                            <div className="mt-4 pt-4 border-t border-slate-100 space-y-2 text-sm">
                              {t.description && <div><span className="text-slate-500">Description</span> <span className="font-medium block">{t.description}</span></div>}
                              <div className="flex items-center gap-2 pt-2">
                                <Button variant="outline" size="sm" onClick={() => handleEditTransaction(t)} disabled={!canManageTransaction(t)}>
                                  <Pencil className="h-3.5 w-3.5 mr-1" />
                                  Edit
                                </Button>
                                <Button variant="outline" size="sm" onClick={() => handleDeleteTransaction(t)} disabled={!canManageTransaction(t)}>
                                  <Trash2 className="h-3.5 w-3.5 mr-1" />
                                  Delete
                                </Button>
                              </div>
                              {!canManageTransaction(t) && (
                                <p className="text-xs text-slate-500">Sales/Expense entries are managed from their own pages.</p>
                              )}
                            </div>
                          </CollapsibleContent>
                        </div>
                      </Collapsible>
                    ))}
                    <div className="px-4 py-3 bg-slate-50/50 border-t">
                      <Button variant="ghost" size="sm" className="w-full text-slate-600" onClick={() => setShowAllColumnsMobile(true)}>
                        View table format <ChevronDown className="h-4 w-4 ml-1" />
                      </Button>
                    </div>
                  </div>
                ) : (
                  <div className={cn("overflow-x-auto table-scroll-wrapper", isMobile && "pb-2")} style={{ WebkitOverflowScrolling: "touch" }}>
                    {isMobile && (
                      <div className="px-4 py-2 border-b bg-slate-50 flex items-center justify-between gap-2 sticky top-0 z-10">
                        <span className="text-xs text-slate-600">Table • Scroll → for more</span>
                        <Button variant="ghost" size="sm" onClick={() => setShowAllColumnsMobile(false)}>
                          <ChevronUp className="h-4 w-4 mr-1" /> Cards
                        </Button>
                      </div>
                    )}
                  <Table className={cn("w-full", !isMobile && "min-w-[500px]")}>
                    <TableHeader>
                      <TableRow>
                        <SortableHeader label="Date" sortKey="date" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className={cn(isMobile && "sticky-col-date bg-slate-50")} />
                        <SortableHeader label="Type" sortKey="type" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} />
                        <SortableHeader label="Description" sortKey="description" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} />
                        <SortableHeader label="In" sortKey="in" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="text-right" />
                        <SortableHeader label="Owed" sortKey="owed" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="text-right" />
                        <SortableHeader label="Out" sortKey="out" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className="text-right" />
                        <SortableHeader label="Balance" sortKey="balance" currentSort={sortKey} currentDirection={sortDirection} onSort={handleSort} className={cn("text-right", isMobile && "sticky-col-actions bg-slate-50")} />
                        <TableHead className="text-right">Actions</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {sortedTransactions.map((t, i) => (
                        <TableRow key={i}>
                          <TableCell className={cn("font-medium bg-white", isMobile && "sticky-col-date")}>
                            {t.date ? (isMobile ? formatDateShort(t.date) : new Date(t.date).toLocaleDateString()) : "-"}
                          </TableCell>
                          <TableCell>{t.type}</TableCell>
                          <TableCell>{t.description}</TableCell>
                          <TableCell className="text-right text-emerald-600">
                            {t.in > 0 ? t.in.toLocaleString(undefined, { minimumFractionDigits: 2 }) : "-"}
                          </TableCell>
                          <TableCell className="text-right text-amber-600">
                            {(Number(t.owed) || 0) > 0 ? Number(t.owed).toLocaleString(undefined, { minimumFractionDigits: 2 }) : "-"}
                          </TableCell>
                          <TableCell className="text-right text-red-600">
                            {t.out > 0 ? t.out.toLocaleString(undefined, { minimumFractionDigits: 2 }) : "-"}
                          </TableCell>
                          <TableCell className={cn("text-right font-medium bg-white", isMobile && "sticky-col-actions")}>
                            {formatCurrency(t.balance, currency)}
                          </TableCell>
                          <TableCell className="text-right">
                            <div className="inline-flex items-center gap-1">
                              <Button variant="ghost" size="icon" onClick={() => handleEditTransaction(t)} disabled={!canManageTransaction(t)} aria-label="Edit transaction">
                                <Pencil className="h-4 w-4" />
                              </Button>
                              <Button variant="ghost" size="icon" onClick={() => handleDeleteTransaction(t)} disabled={!canManageTransaction(t)} aria-label="Delete transaction">
                                <Trash2 className="h-4 w-4 text-red-600" />
                              </Button>
                            </div>
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                  </div>
                )}
                <div className="flex justify-center mt-4">
                  <ChevronDown className="h-5 w-5 text-slate-400" />
                </div>
              </CardContent>
            </Card>

            {/* Ask anything */}
            <div className="flex gap-2 items-center">
              <Input
                placeholder="+ Ask anything (e.g. add 5000 owner injection, withdrawal 3000)"
                value={askInput}
                onChange={(e) => setAskInput(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && handleAskSubmit()}
                className="max-w-md"
              />
              <Button
                variant="outline"
                size="icon"
                aria-label="Voice input"
                onClick={isListening ? stopListening : startListening}
                className={isListening ? "bg-red-100" : ""}
              >
                {isListening ? <MicOff className="h-4 w-4" /> : <Mic className="h-4 w-4" />}
              </Button>
              <Button size="icon" onClick={handleAskSubmit} disabled={!askInput.trim() || isSubmitting}>
                <Send className="h-4 w-4" />
              </Button>
            </div>
          </div>
        </main>
      </div>
    </div>
  )
}
