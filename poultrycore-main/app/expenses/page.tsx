"use client"

import { useEffect, useState, type ReactNode } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { toast } from "@/components/ui/use-toast"
import { toastFormGuide } from "@/lib/utils/validation-toast"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Plus, Pencil, Trash2, Calendar, DollarSign, Search, FileText as FileTextIcon, Download, Loader2, Filter, ChevronDown, ChevronUp, ImageIcon } from "lucide-react"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { getExpenses, getExpense, createExpense, updateExpense, deleteExpense, type Expense, type ExpenseInput } from "@/lib/api/expense"
import { listPoultryCashAccounts, type PoultryCashAccount } from "@/lib/api/poultry-finance"
import { uploadExpenseReceipt } from "@/lib/api/receipt-upload"
import {
  appendReceiptSuffix,
  extractReceiptPathFromDescription,
  stripReceiptSuffixFromDescription,
  toReceiptViewUrl,
} from "@/lib/utils/expense-receipt"
import { ExpenseReceiptField } from "@/components/expense/expense-receipt-field"
import { getFlocks, type Flock } from "@/lib/api/flock"
import { useBatchFlockSelect, BATCH_ALL } from "@/hooks/use-batch-flock-select"
import { getUserContext } from "@/lib/utils/user-context"
import { getValidFlocks, getFlocksForExpenseSelect, getFlockSelectEmptyHint } from "@/lib/utils/flock-utils"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectTrigger, SelectValue, SelectContent, SelectItem } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Pagination, PaginationContent, PaginationItem, PaginationLink, PaginationNext, PaginationPrevious, PaginationEllipsis } from "@/components/ui/pagination"
import { Badge } from "@/components/ui/badge"
import { formatCurrency as fmtCurrency } from "@/lib/utils/currency"
import { useIsMobile } from "@/hooks/use-mobile"
import { Sheet, SheetContent, SheetTrigger } from "@/components/ui/sheet"
import {
  MOBILE_FILTER_SHEET_CONTENT_CLASS,
  MOBILE_FILTER_SELECT_CONTENT_CLASS,
  MOBILE_FILTERS_TOOLBAR_ROW_CLASS,
  MOBILE_FILTERS_TRIGGER_BUTTON_CLASS,
  MobileFilterSheetBody,
  MobileFilterSheetFooter,
  MobileFilterSheetHeader,
} from "@/components/dashboard/mobile-filters"
import { toLocalDateKey } from "@/lib/utils/date-key"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { formatDateShort, cn } from "@/lib/utils"
import { exportTableToPdf } from "@/lib/utils/pdf-export"

// Sentinel for a farm-wide expense (flockId = null), matching /expenses/new.
const ALL_FLOCKS = "ALL"

/**
 * Description on the Add Expense modal: pick one you have used before, or
 * "Other" to type a new one.
 *
 * The selection is REAL STATE, not derived from `value`. Choosing "Other" before
 * typing resolves to the empty string, which is indistinguishable from "nothing
 * chosen" — so a derived version snaps the dropdown back to blank and the text
 * box never appears. That is the whole reason this is a component.
 *
 * The parent still receives one plain string, so the receipt-path suffix
 * (extract/stripReceiptSuffixFromDescription) is untouched.
 */
const OTHER = "Other"

function AddExpenseDescription({
  value, options, disabled, onChange,
}: {
  value: string
  options: string[]
  disabled?: boolean
  onChange: (description: string) => void
}) {
  const known = (v: string) => !!v && options.includes(v)
  const [choice, setChoice] = useState(() => (known(value) ? value : value ? OTHER : ""))
  const [note, setNote] = useState(() => (known(value) ? "" : value))

  // Re-seed only when the incoming value is not what this field last emitted —
  // i.e. the dialog was reset or opened afresh. Re-seeding on every change would
  // fight typing, and would undo "Other" the moment it emits an empty string.
  useEffect(() => {
    const emitted = choice === OTHER ? note.trim() : choice
    if (emitted === (value ?? "")) return
    setChoice(known(value) ? value : value ? OTHER : "")
    setNote(known(value) ? "" : value)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value])

  return (
    <div className="space-y-2">
      <Select
        value={choice}
        disabled={disabled}
        onValueChange={(v) => {
          setChoice(v)
          if (v === OTHER) onChange(note.trim())
          else { setNote(""); onChange(v) }
        }}
      >
        <SelectTrigger><SelectValue placeholder="What was this expense for?" /></SelectTrigger>
        <SelectContent>
          {options.map((o) => <SelectItem key={o} value={o}>{o}</SelectItem>)}
          <SelectItem value={OTHER}>{OTHER} (type your own)</SelectItem>
        </SelectContent>
      </Select>

      {choice === OTHER && (
        <Input
          autoFocus
          value={note}
          disabled={disabled}
          onChange={(e) => { setNote(e.target.value); onChange(e.target.value.trim()) }}
          placeholder="Enter your description"
        />
      )}
    </div>
  )
}

export default function ExpensesPage() {
  const router = useRouter()
  const [expenses, setExpenses] = useState<Expense[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [searchQuery, setSearchQuery] = useState("")
  const [fromDate, setFromDate] = useState("")
  const [toDate, setToDate] = useState("")
  const [confirmOpen, setConfirmOpen] = useState(false)
  const [pendingDelete, setPendingDelete] = useState<{ id: number; farmId?: string; description?: string } | null>(null)
  const [selectedFlock, setSelectedFlock] = useState<string>("all")
  const [selectedMonth, setSelectedMonth] = useState<string>("all")
  const [selectedCategory, setSelectedCategory] = useState<string>("all")
  /**
   * "Expenses with no cash account" — the ones Cash Flow cannot see.
   *
   * An expense saved with "None (no cash movement)" never reaches
   * poultrycashtransactions, so it is missing from Money Out. Cash Flow counts
   * them and links here; without a way to find them that link was a dead end.
   */
  const [cashAccountFilter, setCashAccountFilter] = useState<string>("all")
  const [filtersOpen, setFiltersOpen] = useState(false)
  const [draftFromDate, setDraftFromDate] = useState("")
  const [draftToDate, setDraftToDate] = useState("")
  const [draftFlock, setDraftFlock] = useState<string>("all")
  const [draftMonth, setDraftMonth] = useState<string>("all")
  const [draftCategory, setDraftCategory] = useState<string>("all")
  const hasDraftChanges =
    draftFromDate !== fromDate ||
    draftToDate !== toDate ||
    draftFlock !== selectedFlock ||
    draftMonth !== selectedMonth ||
    draftCategory !== selectedCategory
  const [showAllColumnsMobile, setShowAllColumnsMobile] = useState(false)
  const isMobile = useIsMobile()
  const [allFlocks, setAllFlocks] = useState<Flock[]>([])
  const [sortKey, setSortKey] = useState<string | null>(null)
  const [sortDir, setSortDir] = useState<SortDirection>(null)
  const [currentPage, setCurrentPage] = useState(1)
  const [itemsPerPage, setItemsPerPage] = useState(10)
  const handleSort = (key: string) => { const r = toggleSort(key, sortKey, sortDir); setSortKey(r.key); setSortDir(r.direction) }

  // Create dialog state
  const [isCreateDialogOpen, setIsCreateDialogOpen] = useState(false)
  const [createLoading, setCreateLoading] = useState(false)
  const [createError, setCreateError] = useState("")
  // Batch + Flock dropdowns (James 2026-05-27, repeated request on /expenses).
  // The hook owns the valid-flock list + batch list + filter logic; we render
  // the two <Select>s inside renderForm() below and pass the same hook state to
  // both create and edit forms (one filter affects both since renderForm is shared).
  const {
    batchOptions,
    selectedBatchId,
    setSelectedBatchId,
    flockOptions: flocksForSelect,
    loading: flocksSelectLoading,
  } = useBatchFlockSelect()
  const [createForm, setCreateForm] = useState({
    flockId: "", expenseDate: new Date().toISOString().split("T")[0], category: "", description: "", amount: "", paymentMethod: "", poultryCashAccountId: "",
  })
  const [cashAccounts, setCashAccounts] = useState<PoultryCashAccount[]>([])

  // Edit dialog state
  const [isEditDialogOpen, setIsEditDialogOpen] = useState(false)
  const [editLoading, setEditLoading] = useState(false)
  const [editError, setEditError] = useState("")
  const [editFetching, setEditFetching] = useState(false)
  const [editingExpenseId, setEditingExpenseId] = useState<number | null>(null)
  const [editFarmId, setEditFarmId] = useState<string | undefined>(undefined)
  const [editForm, setEditForm] = useState({
    flockId: "", expenseDate: "", category: "", description: "", amount: "", paymentMethod: "", poultryCashAccountId: "",
  })
  const [createReceiptFile, setCreateReceiptFile] = useState<File | null>(null)
  const [editReceiptFile, setEditReceiptFile] = useState<File | null>(null)
  const [editSavedReceiptPath, setEditSavedReceiptPath] = useState<string | null>(null)
  const [editReceiptRemoved, setEditReceiptRemoved] = useState(false)
  const [editHasDbAttachment, setEditHasDbAttachment] = useState(false)

  const expenseCategories = ["Feed", "Veterinary", "Equipment", "Labor", "Utilities", "Other"]
  // Mobile Money added 2026-05-27 (James). Match /expenses/new and /expenses/[id].
  const paymentMethods = ["Cash", "Mobile Money", "Credit Card", "Bank Transfer", "Check", "Other"]

  useEffect(() => {
    loadExpenses()
    loadFlocks()
    listPoultryCashAccounts().then((a) => setCashAccounts(a.filter((x) => x.isActive))).catch(() => setCashAccounts([]))

    if (typeof window !== 'undefined') {
      const globalSearch = sessionStorage.getItem('globalSearchQuery')
      if (globalSearch) {
        setSearchQuery(globalSearch)
        sessionStorage.removeItem('globalSearchQuery')
      }
      const handleGlobalSearch = (e: CustomEvent) => { setSearchQuery(e.detail.query) }
      window.addEventListener('globalSearch', handleGlobalSearch as EventListener)
      return () => { window.removeEventListener('globalSearch', handleGlobalSearch as EventListener) }
    }
  }, [])

  const loadFlocks = async () => {
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) return
    const res = await getFlocks(userId, farmId)
    if (res.success && res.data) setAllFlocks(res.data)
  }

  // Flock+Batch loading now lives in useBatchFlockSelect (hook above). Stub kept
  // so existing call sites compile without renaming everywhere — it's a no-op
  // because the hook auto-loads on mount and refreshes via its own state.
  const loadFlocksForSelect = async () => { /* no-op: handled by useBatchFlockSelect */ }

  const loadExpenses = async () => {
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      setError("User context not found. Please log in again.")
      setLoading(false)
      return
    }
    const result = await getExpenses(userId, farmId)
    if (result.success && result.data) {
      setExpenses(result.data)
    } else {
      setError(result.message ?? "Failed to load expenses")
    }
    setLoading(false)
  }

  // Create handlers
  const openCreateDialog = () => {
    setCreateForm({ flockId: "", expenseDate: new Date().toISOString().split("T")[0], category: "", description: "", amount: "", paymentMethod: "", poultryCashAccountId: "" })
    setCreateReceiptFile(null)
    setCreateError("")
    loadFlocksForSelect()
    setIsCreateDialogOpen(true)
  }

  const handleCreateSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setCreateLoading(true)
    setCreateError("")
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) { setCreateError("User context not found."); toast({ title: "Session issue", description: "We could not confirm your farm or user. Please sign in again.", variant: "destructive" }); setCreateLoading(false); return }
    if (!createForm.flockId) { setCreateError("Choose a flock"); toastFormGuide(toast, "Select which flock this expense belongs to (or the closest match from the list)."); setCreateLoading(false); return }
    if (!createForm.category) { setCreateError("Choose a category"); toastFormGuide(toast, "Pick an expense category so reports and cash stay organized."); setCreateLoading(false); return }
    if (!createForm.description.trim()) { setCreateError("Add a short description"); toastFormGuide(toast, "Add a few words describing what this expense was for — it helps later when you search."); setCreateLoading(false); return }
    if (!createForm.amount || Number(createForm.amount) <= 0) { setCreateError("Enter amount"); toastFormGuide(toast, "Enter the amount spent as a number greater than zero."); setCreateLoading(false); return }
    if (!createForm.paymentMethod) { setCreateError("Choose payment method"); toastFormGuide(toast, "Select how this was paid (cash, mobile money, bank, etc.)."); setCreateLoading(false); return }

    let descriptionOut = createForm.description.trim()
    if (createReceiptFile) {
      const up = await uploadExpenseReceipt(createReceiptFile, farmId)
      if (!up.success) {
        setCreateError(up.message || "Receipt upload failed")
        setCreateLoading(false)
        return
      }
      descriptionOut = appendReceiptSuffix(descriptionOut, up.path!)
    }

    const expense: ExpenseInput = {
      farmId, userId, flockId: createForm.flockId === ALL_FLOCKS ? null : Number(createForm.flockId),
      expenseDate: createForm.expenseDate + "T00:00:00Z",
      category: createForm.category, description: descriptionOut,
      amount: Number(createForm.amount), paymentMethod: createForm.paymentMethod,
      poultryCashAccountId: createForm.poultryCashAccountId ? Number(createForm.poultryCashAccountId) : null,
    }
    const result = await createExpense(expense)
    if (result.success) {
      toast({ title: "Success!", description: "Expense created successfully." })
      setCreateReceiptFile(null)
      setIsCreateDialogOpen(false)
      loadExpenses()
    } else {
      setCreateError(result.message)
    }
    setCreateLoading(false)
  }

  // Edit handlers
  const openEditDialog = async (expenseId: number, recordFarmId?: string) => {
    setEditingExpenseId(expenseId)
    setEditFarmId(recordFarmId)
    setEditError("")
    setEditReceiptFile(null)
    setEditReceiptRemoved(false)
    setEditSavedReceiptPath(null)
    setEditHasDbAttachment(false)
    setEditFetching(true)
    setIsEditDialogOpen(true)
    loadFlocksForSelect()

    const { userId, farmId } = getUserContext()
    const effectiveFarmId = recordFarmId || farmId
    const result = await getExpense(expenseId, userId, effectiveFarmId)
    if (result.success && result.data) {
      const e = result.data
      const rawDesc = e.description || ""
      setEditSavedReceiptPath(extractReceiptPathFromDescription(rawDesc))
      setEditForm({
        flockId: e.flockId ? String(e.flockId) : ALL_FLOCKS,
        expenseDate: new Date(e.expenseDate).toISOString().split("T")[0],
        category: e.category,
        description: stripReceiptSuffixFromDescription(rawDesc),
        amount: String(e.amount), paymentMethod: e.paymentMethod,
        poultryCashAccountId: e.poultryCashAccountId ? String(e.poultryCashAccountId) : "",
      })
      setEditHasDbAttachment(Boolean(e.hasAttachmentImage))
    } else {
      setEditError(result.message || "Failed to load expense")
      setEditHasDbAttachment(false)
    }
    setEditFetching(false)
  }

  const handleEditSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!editingExpenseId) return
    setEditLoading(true)
    setEditError("")
    const { userId, farmId } = getUserContext()
    const effectiveFarmId = editFarmId || farmId
    if (!userId || !farmId) { setEditError("User context not found."); toast({ title: "Session issue", description: "We could not confirm your farm or user. Please sign in again.", variant: "destructive" }); setEditLoading(false); return }
    if (!editForm.flockId) { setEditError("Choose a flock"); toastFormGuide(toast, "Select which flock this expense belongs to (or the closest match from the list)."); setEditLoading(false); return }
    if (!editForm.category) { setEditError("Choose a category"); toastFormGuide(toast, "Pick an expense category so reports and cash stay organized."); setEditLoading(false); return }
    if (!editForm.description.trim()) { setEditError("Add a short description"); toastFormGuide(toast, "Add a few words describing what this expense was for — it helps later when you search."); setEditLoading(false); return }
    if (!editForm.amount || Number(editForm.amount) <= 0) { setEditError("Enter amount"); toastFormGuide(toast, "Enter the amount spent as a number greater than zero."); setEditLoading(false); return }
    if (!editForm.paymentMethod) { setEditError("Choose payment method"); toastFormGuide(toast, "Select how this was paid (cash, mobile money, bank, etc.)."); setEditLoading(false); return }

    let descriptionOut = editForm.description.trim()
    if (editReceiptFile) {
      const up = await uploadExpenseReceipt(editReceiptFile, effectiveFarmId!)
      if (!up.success) {
        setEditError(up.message || "Receipt upload failed")
        setEditLoading(false)
        return
      }
      descriptionOut = appendReceiptSuffix(descriptionOut, up.path!)
    } else if (editSavedReceiptPath && !editReceiptRemoved) {
      descriptionOut = appendReceiptSuffix(descriptionOut, editSavedReceiptPath)
    }

    const expense: Partial<ExpenseInput> = {
      farmId: effectiveFarmId!, userId, flockId: editForm.flockId === ALL_FLOCKS ? null : Number(editForm.flockId),
      expenseDate: editForm.expenseDate + "T00:00:00Z",
      category: editForm.category, description: descriptionOut,
      amount: Number(editForm.amount), paymentMethod: editForm.paymentMethod,
      poultryCashAccountId: editForm.poultryCashAccountId ? Number(editForm.poultryCashAccountId) : null,
    }
    const result = await updateExpense(editingExpenseId, expense)
    if (result.success) {
      toast({ title: "Success!", description: "Expense updated successfully." })
      setEditReceiptFile(null)
      setIsEditDialogOpen(false)
      loadExpenses()
    } else {
      setEditError(result.message)
    }
    setEditLoading(false)
  }

  // Delete handlers
  const handleDelete = async (id: number, recordFarmId?: string) => {
    const { userId, farmId } = getUserContext()
    const effectiveFarmId = recordFarmId || farmId
    const deletedExpense = expenses.find((e) => (e as any).expenseId === id || (e as any).ExpenseId === id || (e as any).id === id)
    setPendingDelete(null)
    setConfirmOpen(false)

    const result = await deleteExpense(id, userId, effectiveFarmId)
    if (result.success) {
      setExpenses((prev) => prev.filter((e) => {
        const eid = (e as any).expenseId ?? (e as any).ExpenseId ?? (e as any).id
        return eid !== id
      }))
      toast({ title: "Expense deleted", description: `Record has been removed.` })
    } else {
      if (deletedExpense) setExpenses((prev) => [...prev, deletedExpense])
      const msg = result.message ?? "Failed to delete expense"
      setError(msg)
      toast({ title: "Delete failed", description: msg })
    }
  }

  const openConfirmDelete = (id: number | string, farmId?: string, description?: string) => {
    const numericId = typeof id === 'string' ? Number(id) : id
    setPendingDelete({ id: Number.isFinite(numericId) ? (numericId as number) : 0, farmId, description })
    setConfirmOpen(true)
  }

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('en-US', { month: '2-digit', day: '2-digit', year: '2-digit' })
  }

  const formatCurrency = (amount: number) => fmtCurrency(amount)

  const getCategoryColor = (category: string) => {
    const colors: { [key: string]: string } = {
      'Feed': 'bg-green-100 text-green-800', 'Veterinary': 'bg-red-100 text-red-800',
      'Equipment': 'bg-blue-100 text-blue-800', 'Labor': 'bg-yellow-100 text-yellow-800',
      'Utilities': 'bg-purple-100 text-purple-800', 'Other': 'bg-gray-100 text-gray-800',
    }
    return colors[category] || 'bg-gray-100 text-gray-800'
  }

  const handleLogout = () => {
    localStorage.removeItem("auth_token"); localStorage.removeItem("refresh_token")
    localStorage.removeItem("username"); localStorage.removeItem("userId")
    localStorage.removeItem("farmId"); localStorage.removeItem("farmName")
    localStorage.removeItem("isStaff"); localStorage.removeItem("isSubscriber")
    router.push("/login")
  }

  const syncDraftFromCommitted = () => {
    setDraftFromDate(fromDate)
    setDraftToDate(toDate)
    setDraftFlock(selectedFlock)
    setDraftMonth(selectedMonth)
    setDraftCategory(selectedCategory)
  }

  const applyMobileFilters = () => {
    setFromDate(draftFromDate)
    setToDate(draftToDate)
    setSelectedFlock(draftFlock)
    setSelectedMonth(draftMonth)
    setSelectedCategory(draftCategory)
    setFiltersOpen(false)
    toast({ title: "Filters applied", description: "Expense list updated." })
  }

  // ?cashAccount=none arrives from Cash Flow's "expenses with no cash account"
  // warning. Read off window rather than useSearchParams: that hook forces the
  // whole page into a Suspense boundary to prerender, and this is one large
  // client component. Reading after mount costs a render and restructures nothing.
  useEffect(() => {
    if (typeof window === "undefined") return
    const v = new URLSearchParams(window.location.search).get("cashAccount")
    if (v) setCashAccountFilter(v === "none" ? "none" : v)
  }, [])

  // Descriptions already used on this farm. Derived from the data rather than a
  // list invented here, so it needs no vocabulary decision and gets better as
  // the farm uses it — the same approach the Category filter above already takes.
  // The receipt suffix is stripped, or the same description would appear once
  // per receipt path attached to it.
  const usedDescriptions = Array.from(new Set(
    expenses
      .map((e) => stripReceiptSuffixFromDescription(e.description || "").trim())
      .filter(Boolean),
  )).sort((a, b) => a.localeCompare(b))

  const activeFilterCount = [
    !!searchQuery, !!fromDate, !!toDate,
    selectedFlock !== "all", selectedMonth !== "all", selectedCategory !== "all",
    cashAccountFilter !== "all",
  ].filter(Boolean).length

  function clearAllFilters() {
    setSearchQuery(""); setFromDate(""); setToDate("")
    setSelectedFlock("all"); setSelectedMonth("all"); setSelectedCategory("all")
    setCashAccountFilter("all")
  }

  const filteredExpenses = expenses.filter(expense => {
    const q = searchQuery.trim().toLowerCase()
    const matchesSearch = q === "" || (() => {
      const flockStr = String(expense.flockId ?? "")
      const expIdStr = String((expense as any).expenseId ?? (expense as any).ExpenseId ?? (expense as any).id ?? (expense as any).Id ?? "")
      const paidTo = ((expense as any).paidTo ?? (expense as any).PaidTo ?? (expense as any).supplier ?? (expense as any).Supplier ?? "").toString().toLowerCase()
      const cat = (expense.category || "").toLowerCase()
      const pay = (expense.paymentMethod || "").toLowerCase()
      const desc = stripReceiptSuffixFromDescription(expense.description || "").toLowerCase()
      const qNum = Number(q.replace(/[^0-9]/g, ''))
      const hitsNumeric = Number.isFinite(qNum) && qNum > 0 && (flockStr === String(qNum) || expIdStr === String(qNum))
      return desc.includes(q) || cat.includes(q) || pay.includes(q) || paidTo.includes(q) || flockStr.includes(q) || expIdStr.includes(q) || hitsNumeric
    })()
    const matchesFromDate = fromDate === "" || toLocalDateKey(expense.expenseDate) >= fromDate
    const matchesToDate = toDate === "" || toLocalDateKey(expense.expenseDate) <= toDate
    const d = new Date(expense.expenseDate)
    const flockOk = selectedFlock === "all" || String(expense.flockId || "") === selectedFlock
    const monthOk = selectedMonth === "all" || (d.getMonth() + 1) === Number(selectedMonth)
    const catOk = selectedCategory === "all" || (expense.category || "").toLowerCase() === selectedCategory.toLowerCase()
    // == null catches both null and undefined; an expense that predates the
    // column has neither, and it is just as invisible to Cash Flow.
    const linkOk =
      cashAccountFilter === "all" ? true
      : cashAccountFilter === "none" ? expense.poultryCashAccountId == null
      : String(expense.poultryCashAccountId ?? "") === cashAccountFilter
    return matchesSearch && matchesFromDate && matchesToDate && flockOk && monthOk && catOk && linkOk
  })

  const thisMonthTotal = expenses
    .filter(expense => {
      const expenseDate = new Date(expense.expenseDate)
      const now = new Date()
      return expenseDate.getMonth() === now.getMonth() && expenseDate.getFullYear() === now.getFullYear()
    })
    .reduce((sum, expense) => sum + expense.amount, 0)

  const filteredTotal = filteredExpenses.reduce((sum, expense) => sum + expense.amount, 0)
  const sortedExpenses = sortData(filteredExpenses, sortKey, sortDir, (item: any, key: string) => {
    if (key === "expenseDate") return new Date(item.expenseDate)
    if (key === "amount") return Number(item.amount) || 0
    if (key === "description") return stripReceiptSuffixFromDescription(item.description || "")
    return (item as any)[key]
  })
  // Pagination logic
  const totalPages = Math.max(1, Math.ceil(sortedExpenses.length / itemsPerPage))
  const safePage = Math.min(currentPage, totalPages)
  const startIndex = (safePage - 1) * itemsPerPage
  const endIndex = startIndex + itemsPerPage
  const paginatedExpenses = sortedExpenses.slice(startIndex, endIndex)

  // Reset to page 1 when filters change
  useEffect(() => {
    setCurrentPage(1)
  }, [searchQuery, fromDate, toDate, selectedFlock, selectedMonth, selectedCategory, cashAccountFilter])

  const handlePageChange = (page: number) => setCurrentPage(page)
  const handlePreviousPage = () => { if (safePage > 1) setCurrentPage(safePage - 1) }
  const handleNextPage = () => { if (safePage < totalPages) setCurrentPage(safePage + 1) }

  const getPageNumbers = () => {
    const pages: (number | string)[] = []
    if (totalPages <= 7) {
      for (let i = 1; i <= totalPages; i++) pages.push(i)
    } else {
      if (safePage <= 3) {
        for (let i = 1; i <= 4; i++) pages.push(i)
        pages.push("ellipsis")
        pages.push(totalPages)
      } else if (safePage >= totalPages - 2) {
        pages.push(1)
        pages.push("ellipsis")
        for (let i = totalPages - 3; i <= totalPages; i++) pages.push(i)
      } else {
        pages.push(1)
        pages.push("ellipsis")
        for (let i = safePage - 1; i <= safePage + 1; i++) pages.push(i)
        pages.push("ellipsis")
        pages.push(totalPages)
      }
    }
    return pages
  }

  useEffect(() => {
    setCurrentPage(1)
  }, [searchQuery, fromDate, toDate, selectedFlock, selectedMonth, selectedCategory, cashAccountFilter])

  const handleExportCSV = () => {
    const headers = ['ExpenseId','ExpenseDate','Category','Description','Amount','PaymentMethod','PaidTo','FlockId']
    const rows = filteredExpenses.map((e: any) => [
      e.expenseId ?? e.ExpenseId ?? e.id ?? e.Id ?? '',
      new Date(e.expenseDate).toISOString().split('T')[0], e.category,
      stripReceiptSuffixFromDescription(e.description || '').replace(/\n|\r/g, ' '), e.amount, e.paymentMethod,
      e.paidTo ?? e.PaidTo ?? e.supplier ?? e.Supplier ?? '', e.flockId ?? '',
    ])
    const csv = [headers.join(','), ...rows.map(r => r.map((cell) => {
      const s = String(cell ?? '')
      if (s.includes(',') || s.includes('"') || s.includes('\n')) return '"' + s.replace(/"/g, '""') + '"'
      return s
    }).join(','))].join('\n')
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = `expenses-${new Date().toISOString().slice(0,10)}.csv`
    document.body.appendChild(a); a.click(); document.body.removeChild(a); URL.revokeObjectURL(url)
  }

  const handleExportPDF = async () => {
    if (filteredExpenses.length === 0) {
      toast({ title: "Nothing to export", description: "No expenses match the current filters.", variant: "destructive" })
      return
    }
    const fmt = (n: number) => Number(n || 0).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
    const rows = filteredExpenses.map((e: any) => [
      e.expenseId ?? e.ExpenseId ?? e.id ?? e.Id ?? '',
      new Date(e.expenseDate).toLocaleDateString(),
      e.category ?? '',
      stripReceiptSuffixFromDescription((e.description ?? '').toString()),
      fmt(Number(e.amount ?? 0)),
      e.paymentMethod ?? '',
    ])
    try {
      await exportTableToPdf({
        title: "Expenses Report",
        filename: "expenses",
        columns: [
          { header: "ID" },
          { header: "Date" },
          { header: "Category" },
          { header: "Description" },
          { header: "Amount", align: "right" },
          { header: "Payment" },
        ],
        rows,
        totalsRow: ["", "", "", "Total (Filtered)", fmt(filteredTotal), ""],
        summaryLines: [`Total (Filtered): ${fmt(filteredTotal)}`],
      })
    } catch (err) {
      toast({ title: "PDF export failed", description: "Could not generate PDF. Please try again.", variant: "destructive" })
    }
  }

  // Expense form fields component (reused for create and edit)
  const renderExpenseFormFields = (
    form: typeof createForm,
    setForm: (f: typeof createForm) => void,
    isLoading: boolean,
    receiptSlot?: ReactNode,
    // Only the Add modal passes this. Edit keeps the free-text box: an existing
    // description is often a one-off that is not in the list, and forcing it
    // through "Other" on every edit would be friction for no gain.
    descriptionOptions?: string[],
  ) => (
    <>
      <div className="rounded-xl border border-slate-200 overflow-hidden">
        <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Flock &amp; Date</div>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 p-4 bg-white">
          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">Batch</Label>
            <Select value={selectedBatchId} onValueChange={(v) => {
              setSelectedBatchId(v)
              // If the form's currently-selected flock isn't in the new batch's flocks,
              // clear it so the user doesn't save against a now-hidden flock.
              if (v !== BATCH_ALL && form.flockId && form.flockId !== ALL_FLOCKS && !flocksForSelect.some((f) => f.value === form.flockId)) {
                setForm({ ...form, flockId: "" })
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
            <Label className="text-sm font-medium text-slate-700">Select Flock *</Label>
            <Select value={form.flockId} onValueChange={(v) => setForm({ ...form, flockId: v })}>
              <SelectTrigger><SelectValue placeholder="Choose a flock" /></SelectTrigger>
              <SelectContent>
                <SelectItem value={ALL_FLOCKS}>All flocks (farm-wide)</SelectItem>
                {flocksSelectLoading ? (
                  <SelectItem value="loading" disabled>Loading flocks...</SelectItem>
                ) : flocksForSelect.length === 0 ? (
                  <SelectItem value="none" disabled>{getFlockSelectEmptyHint("expense")}</SelectItem>
                ) : (
                  flocksForSelect.map((f) => (
                    <SelectItem key={f.value} value={f.value}>{f.label}</SelectItem>
                  ))
                )}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">Expense Date *</Label>
            <Input name="expenseDate" type="date" value={form.expenseDate} onChange={(e) => setForm({ ...form, expenseDate: e.target.value })} required disabled={isLoading} />
          </div>
        </div>
      </div>
      <div className="rounded-xl border border-slate-200 overflow-hidden">
        <div className="bg-green-600 px-4 py-2 text-sm font-semibold text-white">Category &amp; Payment</div>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 p-4 bg-white">
          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">Category *</Label>
            <Select value={form.category} onValueChange={(v) => setForm({ ...form, category: v })}>
              <SelectTrigger><SelectValue placeholder="Select category" /></SelectTrigger>
              <SelectContent>
                {expenseCategories.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">Amount *</Label>
            <NumberInput name="amount"  step="0.01" min="0" value={form.amount} onChange={(e) => setForm({ ...form, amount: e.target.value })} placeholder="0.00" required disabled={isLoading} className="max-w-[200px]" />
          </div>
          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">Payment Method *</Label>
            <Select value={form.paymentMethod} onValueChange={(v) => setForm({ ...form, paymentMethod: v })}>
              <SelectTrigger><SelectValue placeholder="Select payment method" /></SelectTrigger>
              <SelectContent>
                {paymentMethods.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">Pay from cash account</Label>
            <Select value={form.poultryCashAccountId || "none"} onValueChange={(v) => setForm({ ...form, poultryCashAccountId: v === "none" ? "" : v })} disabled={isLoading}>
              <SelectTrigger><SelectValue placeholder="None (no cash movement)" /></SelectTrigger>
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
      <div className="rounded-xl border border-slate-200 overflow-hidden">
        <div className="bg-amber-600 px-4 py-2 text-sm font-semibold text-white">Description</div>
        <div className="p-4 bg-white space-y-4">
          {descriptionOptions ? (
            <AddExpenseDescription
              value={form.description}
              options={descriptionOptions}
              disabled={isLoading}
              onChange={(description) => setForm({ ...form, description })}
            />
          ) : (
            <Textarea name="description" value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} placeholder="Enter expense description..." rows={3} required disabled={isLoading} />
          )}
          {receiptSlot}
        </div>
      </div>
    </>
  )

  const { userId: sessionUserId, farmId: sessionFarmId } = getUserContext()
  const editResolveReceiptFarmId = editFarmId || sessionFarmId
  const editReceiptDbAttachment =
    editHasDbAttachment && editingExpenseId && sessionUserId && editResolveReceiptFarmId
      ? { expenseId: editingExpenseId, userId: sessionUserId, farmId: editResolveReceiptFarmId }
      : null

  if (loading) {
    return (
        <div className="flex min-h-screen bg-slate-50">
        <DashboardSidebar onLogout={handleLogout} />
        <div className="flex-1 flex flex-col min-w-0">
          <DashboardHeader />
          <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-6 min-w-0">
            <div className="flex items-center justify-center h-64">
              <div className="text-center">
                <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600 mx-auto mb-4"></div>
                <p className="text-slate-600">Loading expenses...</p>
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
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-6 min-w-0">
          <div className="space-y-6">
            {/* Page Header */}
            <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
              <div className="flex items-start gap-3 min-w-0">
                <div className="w-10 h-10 shrink-0 bg-red-100 rounded-lg flex items-center justify-center">
                  <DollarSign className="w-5 h-5 text-red-600" />
                </div>
                <div className="min-w-0">
                  <h1 className="text-xl sm:text-2xl font-bold text-slate-900 truncate">Expenses</h1>
                  <p className="text-sm text-slate-600">Track operational costs and financial records</p>
                </div>
              </div>
              <Button className="gap-2 w-full sm:w-auto h-11 sm:h-10 bg-blue-600 hover:bg-blue-700 shrink-0" onClick={openCreateDialog}>
                <Plus className="w-4 h-4" /> Add Expense
              </Button>
            </div>

            {error && <Alert variant="destructive"><AlertDescription>{error}</AlertDescription></Alert>}

            {/* Filters */}
            {isMobile ? (
              <div className="space-y-3 w-full min-w-0">
                <div className="relative">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                  <Input placeholder="Search expenses..." value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)} className="pl-10 h-11" />
                </div>
                <div className={MOBILE_FILTERS_TOOLBAR_ROW_CLASS}>
                  <Sheet
                    open={filtersOpen}
                    onOpenChange={(open) => {
                      setFiltersOpen(open)
                      syncDraftFromCommitted()
                    }}
                  >
                    <SheetTrigger asChild>
                      <Button variant="outline" className={MOBILE_FILTERS_TRIGGER_BUTTON_CLASS}>
                        <Filter className="h-4 w-4" />
                        <span className="truncate">Filters</span>
                        {activeFilterCount > 0 && (
                          <span className="ml-1 h-5 min-w-[20px] px-1.5 rounded-full bg-orange-500 text-white text-xs flex items-center justify-center">
                            {activeFilterCount}
                          </span>
                        )}
                      </Button>
                    </SheetTrigger>
                    <SheetContent side="bottom" className={MOBILE_FILTER_SHEET_CONTENT_CLASS}>
                      <MobileFilterSheetHeader />
                      <MobileFilterSheetBody>
                        <div className="space-y-3">
                          <p className="text-sm font-medium text-slate-700">Date range</p>
                          <div className="flex flex-col gap-4">
                            <div className="min-w-0 space-y-2">
                              <label htmlFor="exp-filter-from" className="text-xs font-medium text-slate-500">
                                Start date
                              </label>
                              <Input
                                id="exp-filter-from"
                                type="date"
                                value={draftFromDate}
                                onChange={(e) => setDraftFromDate(e.target.value)}
                                className="h-12 min-w-0 w-full text-base"
                              />
                            </div>
                            <div className="min-w-0 space-y-2">
                              <label htmlFor="exp-filter-to" className="text-xs font-medium text-slate-500">
                                End date
                              </label>
                              <Input
                                id="exp-filter-to"
                                type="date"
                                value={draftToDate}
                                onChange={(e) => setDraftToDate(e.target.value)}
                                className="h-12 min-w-0 w-full text-base"
                              />
                            </div>
                          </div>
                        </div>
                        <div className="space-y-2">
                          <label className="text-sm font-medium text-slate-700">Flock</label>
                          <Select value={draftFlock} onValueChange={setDraftFlock}>
                            <SelectTrigger className="h-12 text-base">
                              <SelectValue placeholder="Flock" />
                            </SelectTrigger>
                            <SelectContent className={MOBILE_FILTER_SELECT_CONTENT_CLASS}>
                              <SelectItem value="all">All Flocks</SelectItem>
                              {allFlocks.map((f) => (
                                <SelectItem key={f.flockId} value={String(f.flockId)}>
                                  {f.name}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                        <div className="space-y-2">
                          <label className="text-sm font-medium text-slate-700">Month</label>
                          <Select value={draftMonth} onValueChange={setDraftMonth}>
                            <SelectTrigger className="h-12 text-base">
                              <SelectValue placeholder="Month" />
                            </SelectTrigger>
                            <SelectContent className={MOBILE_FILTER_SELECT_CONTENT_CLASS}>
                              <SelectItem value="all">All Months</SelectItem>
                              {["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"].map((m, i) => (
                                <SelectItem key={i + 1} value={String(i + 1)}>
                                  {m}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                        <div className="space-y-2">
                          <label className="text-sm font-medium text-slate-700">Category</label>
                          <Select value={draftCategory} onValueChange={setDraftCategory}>
                            <SelectTrigger className="h-12 text-base">
                              <SelectValue placeholder="Category" />
                            </SelectTrigger>
                            <SelectContent className={MOBILE_FILTER_SELECT_CONTENT_CLASS}>
                              <SelectItem value="all">All Category</SelectItem>
                              {Array.from(new Set(expenses.map((e) => e.category)))
                                .filter(Boolean)
                                .map((c) => (
                                  <SelectItem key={c} value={c}>
                                    {c}
                                  </SelectItem>
                                ))}
                            </SelectContent>
                          </Select>
                        </div>
                      </MobileFilterSheetBody>
                      <MobileFilterSheetFooter>
                        <div className="flex flex-col gap-3">
                          <div className="flex gap-2">
                            <Button variant="outline" className="h-11 flex-1" onClick={handleExportPDF}>
                              <FileTextIcon className="w-4 h-4 mr-2" />
                              PDF
                            </Button>
                            <Button variant="outline" className="h-11 flex-1" onClick={handleExportCSV}>
                              <Download className="w-4 h-4 mr-2" />
                              CSV
                            </Button>
                          </div>
                          <div className="flex gap-3">
                            <Button
                              type="button"
                              variant="outline"
                              className="h-12 flex-1"
                              onClick={() => {
                                setSearchQuery("")
                                setFromDate("")
                                setToDate("")
                                setSelectedFlock("all")
                                setSelectedMonth("all")
                                setSelectedCategory("all")
                                setDraftFromDate("")
                                setDraftToDate("")
                                setDraftFlock("all")
                                setDraftMonth("all")
                                setDraftCategory("all")
                                setFiltersOpen(false)
                                toast({ title: "Filters cleared" })
                              }}
                            >
                              Clear all
                            </Button>
                            <Button type="button" className="h-12 flex-1" onClick={applyMobileFilters} disabled={!hasDraftChanges}>
                              Apply
                            </Button>
                          </div>
                        </div>
                      </MobileFilterSheetFooter>
                    </SheetContent>
                  </Sheet>
                </div>
              </div>
            ) : (
            <div className="flex flex-wrap items-center gap-2 p-2 bg-white rounded border">
              <div className="relative w-full sm:w-[240px]">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                <Input placeholder="Search..." value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)} className="pl-9" />
              </div>
              <div className="relative w-full sm:w-[140px]">
                <Calendar className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                <Input type="date" placeholder="From" value={fromDate} onChange={(e) => setFromDate(e.target.value)} className="pl-9" />
              </div>
              <div className="relative w-full sm:w-[140px]">
                <Calendar className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                <Input type="date" placeholder="To" value={toDate} onChange={(e) => setToDate(e.target.value)} className="pl-9" />
              </div>
              <Select value={selectedFlock} onValueChange={setSelectedFlock}>
                <SelectTrigger className="w-[180px]"><SelectValue placeholder="Flock" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All Flocks</SelectItem>
                  {allFlocks.map(f => <SelectItem key={f.flockId} value={String(f.flockId)}>{f.name} ({f.quantity} birds)</SelectItem>)}
                </SelectContent>
              </Select>
              <Select value={selectedMonth} onValueChange={setSelectedMonth}>
                <SelectTrigger className="w-[140px]"><SelectValue placeholder="Month" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All Months</SelectItem>
                  {["January","February","March","April","May","June","July","August","September","October","November","December"].map((m,i) => <SelectItem key={i+1} value={String(i+1)}>{m}</SelectItem>)}
                </SelectContent>
              </Select>
              <Select value={selectedCategory} onValueChange={setSelectedCategory}>
                <SelectTrigger className="w-[180px]"><SelectValue placeholder="Category" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All Category</SelectItem>
                  {Array.from(new Set(expenses.map(e => e.category))).filter(Boolean).map(c => <SelectItem key={c} value={c}>{c}</SelectItem>)}
                </SelectContent>
              </Select>
              {/* "No cash account" first, with its count, because that is the one
                  people arrive here looking for. Filtering by a specific account
                  comes free once the field is a Select rather than a toggle. */}
              <Select value={cashAccountFilter} onValueChange={setCashAccountFilter}>
                <SelectTrigger className="w-[200px]"><SelectValue placeholder="Cash account" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All cash accounts</SelectItem>
                  <SelectItem value="none">
                    No cash account ({expenses.filter((e) => e.poultryCashAccountId == null).length})
                  </SelectItem>
                  {cashAccounts.map((a) => (
                    <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>
                      {a.accountName}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {/* Desktop had no way to clear filters — only the mobile sheet did. */}
              {activeFilterCount > 0 && (
                <Button variant="ghost" size="sm" onClick={clearAllFilters}>
                  Clear ({activeFilterCount})
                </Button>
              )}
              <div className="ml-auto flex items-center gap-2">
                <Button variant="outline" size="sm" className="flex items-center gap-2" onClick={handleExportPDF}><FileTextIcon className="w-4 h-4" />PDF</Button>
                <Button variant="outline" size="sm" className="flex items-center gap-2" onClick={handleExportCSV}><Download className="w-4 h-4" />CSV</Button>
              </div>
            </div>
            )}

            {/* Summary Cards */}
            <div className={cn("grid gap-4", isMobile ? "grid-cols-1" : "grid-cols-1 md:grid-cols-2")}>
              <Card className="bg-white">
                <CardHeader className="pb-2"><CardDescription>This Month</CardDescription></CardHeader>
                <CardContent className="min-w-0">
                  <div
                    className={cn(
                      "font-bold text-slate-900 leading-tight whitespace-nowrap",
                      isMobile ? "text-3xl" : "text-2xl"
                    )}
                  >
                    {formatCurrency(thisMonthTotal)}
                  </div>
                </CardContent>
              </Card>
              <Card className="bg-white">
                <CardHeader className="pb-2"><CardDescription>Total (Filtered)</CardDescription></CardHeader>
                <CardContent className="min-w-0">
                  <div
                    className={cn(
                      "font-bold text-slate-900 leading-tight whitespace-nowrap",
                      isMobile ? "text-3xl" : "text-2xl"
                    )}
                  >
                    {formatCurrency(filteredTotal)}
                  </div>
                </CardContent>
              </Card>
            </div>

            {/* Table */}
            {filteredExpenses.length === 0 ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center">
                  <DollarSign className="w-12 h-12 text-slate-400 mx-auto mb-4" />
                  <h3 className="text-lg font-semibold text-slate-900 mb-2">No expenses found</h3>
                  <p className="text-slate-600 mb-6">{searchQuery || fromDate || toDate ? "No expenses match your search criteria." : "Start tracking your farm expenses."}</p>
                  <Button className="gap-2 bg-blue-600 hover:bg-blue-700" onClick={openCreateDialog}><Plus className="w-4 h-4" />Add First Expense</Button>
                </CardContent>
              </Card>
            ) : (
              <Card className="bg-white overflow-hidden">
                <CardHeader><CardTitle>Expenses</CardTitle><CardDescription>Manage your farm expenses</CardDescription></CardHeader>
                <CardContent className="p-0">
                  {isMobile && !showAllColumnsMobile ? (
                    <div className="space-y-3">
                      {paginatedExpenses.map((expense, idx) => {
                        const eid = (expense as any).expenseId ?? (expense as any).ExpenseId ?? (expense as any).id ?? (expense as any).Id
                        const idNum = Number(eid)
                        const validId = Number.isFinite(idNum) && idNum > 0
                        const fId = expense.farmId ?? (expense as any).FarmId ?? ""
                        const receiptPath = extractReceiptPathFromDescription(expense.description || "")
                        const receiptHref = toReceiptViewUrl(receiptPath, fId)
                        return (
                        <Collapsible key={`${eid}-${idx}`} defaultOpen className={cn("group rounded-xl border shadow-sm overflow-hidden", idx % 2 === 0 ? "bg-amber-100 border-amber-300" : "bg-white border-slate-200")}>
                          <div className={cn("p-4 active:bg-slate-50/80 transition-colors", idx % 2 === 1 && "bg-slate-50/20")}>
                            <CollapsibleTrigger asChild>
                              <div className="flex items-start justify-between gap-3 cursor-pointer">
                                <div className="min-w-0 flex-1">
                                  <div className="flex items-center gap-2">
                                    <span className="font-semibold text-slate-900 shrink-0">{formatDateShort(expense.expenseDate)}</span>
                                    <Badge className={cn("whitespace-normal break-words shrink min-w-0 text-left", getCategoryColor(expense.category))}>{expense.category}</Badge>
                                  </div>
                                  <div className="mt-1 flex items-baseline gap-3">
                                    <span className="text-lg font-bold text-red-600">{formatCurrency(expense.amount)}</span>
                                    <span className="text-sm text-slate-600 truncate">
                                      {stripReceiptSuffixFromDescription(expense.description || "")}
                                      {receiptHref && receiptPath && (
                                        <a
                                          href={receiptHref}
                                          target="_blank"
                                          rel="noopener noreferrer"
                                          className="ml-2 inline-flex shrink-0 text-blue-600 hover:text-blue-800"
                                          title="View receipt"
                                          onClick={(ev) => ev.stopPropagation()}
                                        >
                                          <ImageIcon className="h-4 w-4" />
                                        </a>
                                      )}
                                    </span>
                                  </div>
                                </div>
                                <ChevronDown className="h-5 w-5 text-slate-400 shrink-0 transition-transform group-data-[state=open]:rotate-180" />
                              </div>
                            </CollapsibleTrigger>
                            <CollapsibleContent>
                              <div className="mt-4 pt-4 border-t border-slate-100 space-y-2 text-sm">
                                <div className="grid grid-cols-2 gap-2">
                                  <div><span className="text-slate-500">Payment</span> <span className="font-medium">{expense.paymentMethod || "N/A"}</span></div>
                                  <div><span className="text-slate-500">Paid to</span> <span className="font-medium">{expense.paidTo || "N/A"}</span></div>
                                </div>
                                <div className="flex gap-2 pt-2">
                                  <Button variant="outline" size="sm" className="flex-1 h-10" disabled={!validId} onClick={() => validId && openEditDialog(idNum, fId)}>
                                    <Pencil className="h-4 w-4 mr-2" /> Edit
                                  </Button>
                                  <Button variant="outline" size="sm" className="flex-1 h-10 text-red-600 border-red-200 hover:bg-red-50" onClick={() => openConfirmDelete(eid, expense.farmId, stripReceiptSuffixFromDescription(expense.description || ""))}>
                                    <Trash2 className="h-4 w-4 mr-2" /> Delete
                                  </Button>
                                </div>
                              </div>
                            </CollapsibleContent>
                          </div>
                        </Collapsible>
                        )
                      })}
                      {paginatedExpenses.length > 0 && (
                        <div className="px-4 py-3 bg-slate-50/50 border-t">
                          <Button variant="ghost" size="sm" className="w-full text-slate-600" onClick={() => setShowAllColumnsMobile(true)}>
                            View table format <ChevronDown className="h-4 w-4 ml-1" />
                          </Button>
                        </div>
                      )}
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
                  {/* Fixed columns total 720px; Description is the one auto column
                      and absorbs whatever is left, so the widths can never add up
                      to more than the table and squeeze cells into each other.
                      Below the min width the wrapper scrolls instead. */}
                  <Table className="table-fixed w-full min-w-[900px]">
                    <TableHeader>
                      <TableRow>
                        <SortableHeader label="Date" sortKey="expenseDate" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className={cn("w-[100px]", isMobile && "sticky-col-date bg-slate-50")} />
                        <SortableHeader label="Description" sortKey="description" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="w-auto min-w-0" />
                        <SortableHeader label="Category" sortKey="category" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="w-[150px]" />
                        <SortableHeader label="Amount" sortKey="amount" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="w-[130px] text-right whitespace-nowrap" />
                        <SortableHeader label="Payment Method" sortKey="paymentMethod" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="w-[130px]" />
                        <SortableHeader label="Paid To" sortKey="paidTo" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="w-[110px] min-w-0" />
                        <TableHead className={cn("text-right w-[100px] min-w-[100px] whitespace-nowrap", isMobile && "sticky-col-actions bg-slate-50")}>Actions</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {paginatedExpenses.map((expense, idx) => {
                        const rowReceiptPath = extractReceiptPathFromDescription(expense.description || "")
                        const rowReceiptUrl = toReceiptViewUrl(rowReceiptPath, expense.farmId)
                        return (
                        <TableRow key={`${expense.expenseId || 'tmp'}-${idx}`}>
                          <TableCell className={cn("font-medium bg-white", isMobile && "sticky-col-date")}>{isMobile ? formatDateShort(expense.expenseDate) : formatDate(expense.expenseDate)}</TableCell>
                          {/* overflow-hidden clips anything that still escapes, and
                              wrap-anywhere lets a long unbroken run break mid-word —
                              break-words alone leaves the intrinsic min-width intact,
                              which is what let long text reach into Category. */}
                          <TableCell className="min-w-0 align-top overflow-hidden">
                            <div className="min-w-0">
                              <div className="font-medium flex items-start gap-2 min-w-0">
                                <span className="min-w-0 wrap-anywhere">{stripReceiptSuffixFromDescription(expense.description || "")}</span>
                                {rowReceiptUrl && rowReceiptPath && (
                                  <a
                                    href={rowReceiptUrl}
                                    target="_blank"
                                    rel="noopener noreferrer"
                                    className="inline-flex shrink-0 text-blue-600 hover:text-blue-800"
                                    title="View receipt"
                                  >
                                    <ImageIcon className="h-4 w-4" />
                                  </a>
                                )}
                              </div>
                              {expense.notes && <div className="text-sm text-slate-500">{expense.notes}</div>}
                            </div>
                          </TableCell>
                          {/* Badge is nowrap/shrink-0 by default, so a long category
                              ("Raw Materials / Inventory Purchase") renders past this
                              fixed-width cell and over the Amount column. Let it wrap. */}
                          <TableCell className="align-top min-w-0"><Badge className={cn("whitespace-normal break-words shrink max-w-full text-left", getCategoryColor(expense.category))}>{expense.category}</Badge></TableCell>
                          <TableCell className="text-right font-medium whitespace-nowrap align-top">{formatCurrency(expense.amount)}</TableCell>
                          <TableCell className="align-top"><Badge variant="outline">{expense.paymentMethod || "N/A"}</Badge></TableCell>
                          <TableCell className="text-slate-600 min-w-0 wrap-anywhere align-top overflow-hidden">{expense.paidTo || "N/A"}</TableCell>
                          <TableCell className={cn("text-right whitespace-nowrap bg-white", isMobile && "sticky-col-actions")}>
                            <div className="flex items-center justify-end gap-2 min-w-[80px]">
                              {(() => {
                                const eid = (expense as any).expenseId ?? (expense as any).ExpenseId ?? (expense as any).id ?? (expense as any).Id
                                const idNum = Number(eid)
                                const validId = Number.isFinite(idNum) && idNum > 0
                                const fId = expense.farmId ?? (expense as any).FarmId ?? ""
                                return (
                                  <Button variant="ghost" size="sm" className="h-8 w-8 p-0" disabled={!validId}
                                    onClick={() => validId && openEditDialog(idNum, fId)}>
                                    <Pencil className="w-4 h-4" />
                                  </Button>
                                )
                              })()}
                              <Button variant="ghost" size="sm"
                                onClick={() => openConfirmDelete((expense as any).expenseId ?? (expense as any).ExpenseId ?? (expense as any).id ?? (expense as any).Id, expense.farmId, stripReceiptSuffixFromDescription(expense.description || ""))}
                                className="h-8 w-8 p-0 text-red-600 hover:text-red-700 hover:bg-red-50">
                                <Trash2 className="w-4 h-4" />
                              </Button>
                            </div>
                          </TableCell>
                        </TableRow>
                      )})}
                    </TableBody>
                  </Table>
                  </div>
                  )}
                {/* Pagination */}
                {!loading && filteredExpenses.length > 0 && (
                  <div className="flex flex-col sm:flex-row items-center justify-between gap-4 px-4 py-3 border-t bg-slate-50">
                    <div className="flex items-center gap-4">
                      <span className="text-sm text-slate-600">
                        Showing {startIndex + 1} to {Math.min(endIndex, sortedExpenses.length)} of {sortedExpenses.length} records
                      </span>
                      <Select value={String(itemsPerPage)} onValueChange={(v) => { setItemsPerPage(Number(v)); setCurrentPage(1) }}>
                        <SelectTrigger className="w-[100px] h-8"><SelectValue /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="5">5 / page</SelectItem>
                          <SelectItem value="10">10 / page</SelectItem>
                          <SelectItem value="15">15 / page</SelectItem>
                          <SelectItem value="25">25 / page</SelectItem>
                          <SelectItem value="50">50 / page</SelectItem>
                          <SelectItem value="100">100 / page</SelectItem>
                        </SelectContent>
                      </Select>
                    </div>
                    <Pagination>
                      <PaginationContent>
                        <PaginationItem>
                          <PaginationPrevious onClick={handlePreviousPage} className={safePage === 1 ? "pointer-events-none opacity-50" : "cursor-pointer"} />
                        </PaginationItem>
                        {getPageNumbers().map((page, index) => (
                          <PaginationItem key={index}>
                            {page === "ellipsis" ? (
                              <PaginationEllipsis />
                            ) : (
                              <PaginationLink onClick={() => handlePageChange(page as number)} isActive={safePage === page} className="cursor-pointer">{page}</PaginationLink>
                            )}
                          </PaginationItem>
                        ))}
                        <PaginationItem>
                          <PaginationNext onClick={handleNextPage} className={safePage === totalPages ? "pointer-events-none opacity-50" : "cursor-pointer"} />
                        </PaginationItem>
                      </PaginationContent>
                    </Pagination>
                  </div>
                )}
                </CardContent>
              </Card>
            )}
          </div>
        </main>
      </div>

      {/* Create Expense Dialog */}
      <Dialog open={isCreateDialogOpen} onOpenChange={setIsCreateDialogOpen}>
        <DialogContent className="w-[95vw] max-w-[1600px] max-h-[90vh] flex flex-col gap-4 overflow-hidden p-6">
          <DialogHeader className="shrink-0">
            <DialogTitle className="flex items-center gap-2"><DollarSign className="w-5 h-5 text-green-600" /> Add Expense</DialogTitle>
            <DialogDescription>Record a new farm expense</DialogDescription>
          </DialogHeader>
          {createError && <Alert variant="destructive" className="shrink-0"><AlertDescription>{createError}</AlertDescription></Alert>}
          <form onSubmit={handleCreateSubmit} className="flex min-h-0 flex-1 flex-col gap-0">
            <div className="min-h-0 flex-1 overflow-y-auto space-y-4 pr-2">
              {renderExpenseFormFields(
                createForm,
                setCreateForm,
                createLoading,
                  <ExpenseReceiptField
                    existingPath={null}
                    resolveReceiptFarmId={getUserContext().farmId}
                    pendingFile={createReceiptFile}
                  onPendingFileChange={setCreateReceiptFile}
                  disabled={createLoading}
                />,
                usedDescriptions,
              )}
            </div>
            <div className="shrink-0 flex gap-3 justify-end border-t pt-3 mt-2">
              <Button type="button" onClick={() => setIsCreateDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
              <Button type="submit" disabled={createLoading || flocksSelectLoading}>
                {createLoading ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Creating...</> : <><DollarSign className="w-4 h-4 mr-2" />Create Expense</>}
              </Button>
            </div>
          </form>
        </DialogContent>
      </Dialog>

      {/* Edit Expense Dialog */}
      <Dialog open={isEditDialogOpen} onOpenChange={setIsEditDialogOpen}>
        <DialogContent className="w-[95vw] max-w-[1600px] max-h-[90vh] flex flex-col gap-4 overflow-hidden p-6">
          <DialogHeader className="shrink-0">
            <DialogTitle className="flex items-center gap-2"><Pencil className="w-5 h-5 text-blue-600" /> Edit Expense</DialogTitle>
            <DialogDescription>Update expense information</DialogDescription>
          </DialogHeader>
          {editError && <Alert variant="destructive" className="shrink-0"><AlertDescription>{editError}</AlertDescription></Alert>}
          {editFetching ? (
            <div className="py-8 text-center">
              <Loader2 className="w-8 h-8 animate-spin mx-auto mb-2 text-blue-600" />
              <p className="text-slate-600">Loading expense...</p>
            </div>
          ) : (
            <form onSubmit={handleEditSubmit} className="flex min-h-0 flex-1 flex-col gap-0">
              <div className="min-h-0 flex-1 overflow-y-auto space-y-4 pr-2">
                {renderExpenseFormFields(
                  editForm,
                  setEditForm,
                  editLoading,
                  <ExpenseReceiptField
                    existingPath={editReceiptRemoved ? null : editSavedReceiptPath}
                    resolveReceiptFarmId={editResolveReceiptFarmId}
                    dbAttachment={editReceiptDbAttachment}
                    pendingFile={editReceiptFile}
                    onPendingFileChange={setEditReceiptFile}
                    onRemoveExisting={() => {
                      setEditReceiptRemoved(true)
                      setEditSavedReceiptPath(null)
                    }}
                    disabled={editLoading}
                  />
                )}
              </div>
              <div className="shrink-0 flex gap-3 justify-end border-t pt-3 mt-2">
                <Button type="button" onClick={() => setIsEditDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
                <Button type="submit" disabled={editLoading || flocksSelectLoading}>
                  {editLoading ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving...</> : <><Pencil className="w-4 h-4 mr-2" />Save Changes</>}
                </Button>
              </div>
            </form>
          )}
        </DialogContent>
      </Dialog>

      {/* Delete confirmation dialog */}
      <AlertDialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete expense?</AlertDialogTitle>
            <AlertDialogDescription>
              {pendingDelete?.description ? <>This will permanently remove &ldquo;{pendingDelete.description}&rdquo;.</> : <>This action cannot be undone.</>}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={() => { if (pendingDelete) handleDelete(pendingDelete.id, pendingDelete.farmId) }} className="bg-red-600 hover:bg-red-700">Delete</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}
