"use client"

// Generic Expenses (Purchasing → Expenses). Report 40.
//
// The Poultry Expenses page (app/expenses/page.tsx), the same words, layout and
// actions, on Generic's own logic:
//   * an expense is saved as a Draft and moves money only when it is Approved
//     (Approve / Reject stay, with the Approval column and filter);
//   * the payment status (Paid / Partially paid / Unpaid) and due date work as
//     on Poultry (migration 448): the part paid now leaves the chosen cash
//     account, the part still owed goes on the supplier and shows on Supplier
//     Balances, where it is paid;
//   * Drafts are edited and deleted. An APPROVED expense is final (504): no
//     Edit or Delete -- it is Reversed (reason, refund or supplier credit) and a
//     corrected one is entered. A paid expense with a supplier makes an
//     ExpenseEntry Supplier Payment on approval.
// Poultry-only parts are left out: flock / batch, feed rule, receipts, cost
// breakdown, repeat previous.

export const dynamic = "force-dynamic"

import { Suspense, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter, useSearchParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Select, SelectContent, SelectGroup, SelectItem, SelectSeparator, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription,
  AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from "@/components/ui/alert-dialog"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Sheet, SheetContent, SheetTrigger } from "@/components/ui/sheet"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { DataPagination } from "@/components/ui/data-pagination"
import { PERIOD_GROUPS, periodToRange, rangeToPeriod } from "@/lib/date-ranges"
import { DateTimeCell } from "@/components/ui/date-time-cell"
import {
  MOBILE_FILTER_SHEET_CONTENT_CLASS, MOBILE_FILTER_SELECT_CONTENT_CLASS, MOBILE_FILTERS_TOOLBAR_ROW_CLASS,
  MOBILE_FILTERS_TRIGGER_BUTTON_CLASS, MobileFilterSheetBody, MobileFilterSheetFooter, MobileFilterSheetHeader,
} from "@/components/dashboard/mobile-filters"
import { RecordPaymentDialog, type CashAccountOption } from "@/components/balances/record-payment-dialog"
import { PaymentHistoryDialog } from "@/components/balances/payment-history-dialog"
import type { OpenDocumentRow } from "@/lib/api/balances"
import {
  Banknote, Calendar, Check, ChevronDown, ChevronUp, DollarSign, Download, FileText as FileTextIcon, Filter,
  History, Loader2, Pencil, Plus, Search, Trash2, Truck, Undo2, X,
} from "lucide-react"
import { ReversePurchaseDialog } from "@/components/purchases/reverse-purchase-dialog"
import { getSelectedCurrency } from "@/lib/utils/currency"
import { useAuthStore } from "@/lib/store/auth-store"
import { useGenericModules } from "@/hooks/use-generic-modules"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useIsMobile } from "@/hooks/use-mobile"
import { usePagination } from "@/hooks/use-pagination"
import { usePermissions } from "@/hooks/use-permissions"
import { formatCurrency } from "@/lib/utils/currency"
import { formatDateShort, cn } from "@/lib/utils"
import { fmtDateTime } from "@/lib/utils/company-datetime"
import { exportTableToPdf } from "@/lib/utils/pdf-export"
import { PAYMENT_STATUS_LABELS, SELECTABLE_PAYMENT_STATUSES } from "@/lib/expenses/payment-status"
import { useBusinessDate } from "@/hooks/use-business-date"
import { PrefilledBanner, RepeatPreviousButton, ReviewMark, reviewRing } from "@/components/repeat/repeat-previous"
import { buildRepeatPrefill, latestEntry, repeatSubmitBlocker, unconfirmedFields, type RepeatPrefill } from "@/lib/repeat/repeat-previous"
import { FIELD_LABELS, genericExpensePolicy, type GenericExpenseForm } from "@/lib/repeat/policies"
import { ExpenseReceiptField } from "@/components/expense/expense-receipt-field"
import { uploadExpenseReceipt } from "@/lib/api/receipt-upload"
import { toReceiptViewUrl } from "@/lib/utils/expense-receipt"
import { getUserContext } from "@/lib/api/config"
import { ImageIcon } from "lucide-react"
import {
  approveExpense, rejectExpense, getExpenses, createExpense, updateExpense, deleteExpense,
  getCashAccounts, getExpenseCategories, getSuppliers,
  type GenericExpense, type GenericCashAccount, type GenericExpenseCategory, type GenericSupplier,
} from "@/lib/api/generic"
import { SingleProjectField, EMPTY_SINGLE_PROJECT, singleAssignment, loadSingleProject, type SingleProjectValue } from "@/components/generic/projects/form-project-field"
import { useProjectsEnabled } from "@/hooks/use-generic-projects"
import { ProjectFilter } from "@/components/generic/projects/project-filter"
import { useProjectLabels } from "@/hooks/use-project-labels"
import { ProjectCell, ProjectHead, ProjectLabels, PROJECT_COLUMN_TITLE } from "@/components/generic/projects/project-column"
import { ALL_PROJECTS, type ProjectFilterValue } from "@/lib/generic/project-math"

type PayStatus = (typeof SELECTABLE_PAYMENT_STATUSES)[number]

// Generic's methods. "Credit" is not offered: an expense with nothing paid is
// "Unpaid" (stored as Credit, owed to the supplier).
const PAY_METHODS: Array<{ value: string; label: string }> = [
  { value: "Cash", label: "Cash" },
  { value: "MoMo", label: "Mobile Money" },
  { value: "Bank", label: "Bank" },
  { value: "Card", label: "Card" },
]
const methodLabel = (m?: string | null) =>
  m === "Credit" ? "Credit" : PAY_METHODS.find((x) => x.value === m)?.label ?? (m || "N/A")

const APPROVAL_FILTERS = ["all", "Draft", "Approved", "Rejected"] as const
const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

type Row = GenericExpense & { amountPaidN: number; balance: number }

type FormState = {
  expenseDate: string
  genericExpenseCategoryId: string
  amount: string
  paymentMethod: string
  genericCashAccountId: string
  genericSupplierId: string
  paidTo: string
  paymentStatus: PayStatus
  amountPaid: string
  dueDate: string
  description: string
  notes: string
}

const today = () => new Date().toISOString().slice(0, 10)
const emptyForm = (): FormState => ({
  expenseDate: today(), genericExpenseCategoryId: "", amount: "", paymentMethod: "Cash",
  genericCashAccountId: "", genericSupplierId: "", paidTo: "", paymentStatus: "Paid",
  amountPaid: "", dueDate: "", description: "", notes: "",
})

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
  useEffect(() => {
    const emitted = choice === OTHER ? note.trim() : choice
    if (emitted === (value ?? "")) return
    setChoice(known(value) ? value : value ? OTHER : "")
    setNote(known(value) ? "" : value)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value])
  return (
    <div className="space-y-2">
      <Select value={choice} disabled={disabled}
        onValueChange={(v) => {
          setChoice(v)
          if (v === OTHER) onChange(note.trim())
          else { setNote(""); onChange(v) }
        }}>
        <SelectTrigger><SelectValue placeholder="What was this expense for?" /></SelectTrigger>
        <SelectContent>
          {options.map((o) => <SelectItem key={o} value={o}>{o}</SelectItem>)}
          <SelectItem value={OTHER}>{OTHER} (type your own)</SelectItem>
        </SelectContent>
      </Select>
      {choice === OTHER && (
        <Input autoFocus value={note} disabled={disabled}
          onChange={(e) => { setNote(e.target.value); onChange(e.target.value.trim()) }}
          placeholder="Enter your description" />
      )}
    </div>
  )
}

function approvalBadge(s: string) {
  switch (s) {
    case "Approved": return "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"
    case "Rejected": return "bg-rose-100 text-rose-800 hover:bg-rose-100"
    case "Submitted": return "bg-sky-100 text-sky-800 hover:bg-sky-100"
    default: return "bg-slate-100 text-slate-800 hover:bg-slate-100"
  }
}

function GenericExpensesPageInner() {
  const router = useRouter()
  const sp = useSearchParams()
  const focusExpenseId = sp.get("expenseId")
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const modules = useGenericModules()
  const logout = useLogout()
  const { toast } = useToast()
  const isMobile = useIsMobile()
  const { can } = usePermissions()
  const canCreate = can("generic.expenses.create" as any)
  const canEdit = can("generic.expenses.edit" as any)
  const canDelete = can("generic.expenses.delete" as any)
  const canApprove = can("generic.expenses.approve" as any)
  const canReverse = can("generic.expenses.reverse" as any)
  const canExport = can("generic.expenses.export" as any)
  const canPay = can("generic.supplier-payments.create")

  const [rows, setRows] = useState<GenericExpense[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [categories, setCategories] = useState<GenericExpenseCategory[]>([])
  const [suppliers, setSuppliers] = useState<GenericSupplier[]>([])
  const [cashAccounts, setCashAccounts] = useState<GenericCashAccount[]>([])

  // filters (committed + mobile drafts, as on Poultry)
  const [searchQuery, setSearchQuery] = useState("")
  const [fromDate, setFromDate] = useState("")
  const [toDate, setToDate] = useState("")
  const [selectedMonth, setSelectedMonth] = useState("all")
  const [selectedCategory, setSelectedCategory] = useState("all")
  const [cashAccountFilter, setCashAccountFilter] = useState("all")
  const [approvalFilter, setApprovalFilter] = useState<string>(sp.get("status") || "all")
  const [filtersOpen, setFiltersOpen] = useState(false)
  const [draftFromDate, setDraftFromDate] = useState("")
  const [draftToDate, setDraftToDate] = useState("")
  const [draftMonth, setDraftMonth] = useState("all")
  const [draftCategory, setDraftCategory] = useState("all")
  const [draftApproval, setDraftApproval] = useState("all")
  const [showAllColumnsMobile, setShowAllColumnsMobile] = useState(false)
  const [sortKey, setSortKey] = useState<string | null>("expenseDate")
  const [sortDir, setSortDir] = useState<SortDirection>("desc")

  // dialogs
  const [formOpen, setFormOpen] = useState(false)
  const [editing, setEditing] = useState<Row | null>(null)
  const [form, setForm] = useState<FormState>(emptyForm())
  // 483: Projects & Contracts on the expense dialog.
  const { enabled: projectsEnabled } = useProjectsEnabled()
  const [project, setProject] = useState<SingleProjectValue>(EMPTY_SINGLE_PROJECT)
  const [saving, setSaving] = useState(false)
  const [formError, setFormError] = useState<string | null>(null)
  const [pendingDelete, setPendingDelete] = useState<Row | null>(null)
  const [reverseFor, setReverseFor] = useState<Row | null>(null)
  const [rejectFor, setRejectFor] = useState<Row | null>(null)
  const [rejectReason, setRejectReason] = useState("")
  const [payFor, setPayFor] = useState<Row | null>(null)
  const [historyFor, setHistoryFor] = useState<Row | null>(null)

  const loadExpenses = async () => {
    setLoading(true)
    setError(null)
    try { setRows(await getExpenses(null)) }
    catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    loadExpenses()
    Promise.all([getExpenseCategories(), getSuppliers(), getCashAccounts()])
      .then(([cs, ss, as]) => { setCategories(cs); setSuppliers(ss); setCashAccounts(as) })
      .catch(() => { /* the form says what is missing */ })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router])

  const activeCategories = categories.filter((c: any) => c.isActive !== false)
  const activeAccounts = cashAccounts.filter((a) => a.isActive)
  const activeSuppliers = suppliers.filter((s: any) => s.isActive !== false)

  const expenses: Row[] = useMemo(() => rows.map((e) => {
    const paid = e.paymentStatus === "NonCash" ? Number(e.amount) : Number(e.amountPaid ?? e.amount)
    return { ...e, amountPaidN: paid, balance: Math.max(Number(e.amount) - paid, 0) }
  }), [rows])

  const isOverdue = (e: Row) =>
    e.status === "Approved" && !!e.dueDate && e.balance > 0 && new Date(e.dueDate) < new Date(new Date().toDateString())

  // 483: Project / Contract filter (hidden unless the module is on).
  const [projectFilter, setProjectFilter] = useState<ProjectFilterValue>(ALL_PROJECTS)
  const projectLabels = useProjectLabels("Expense", rows)
  const filteredExpenses = useMemo(() => expenses.filter((e) => {
    if (focusExpenseId) return String(e.genericExpenseId) === focusExpenseId
    const q = searchQuery.trim().toLowerCase()
    if (q && ![e.description, e.categoryName, e.supplierName, e.paidTo, e.notes, `E${e.genericExpenseId}`]
      .some((v) => (v ?? "").toString().toLowerCase().includes(q))) return false
    const d = (e.expenseDate ?? "").slice(0, 10)
    if (fromDate && d < fromDate) return false
    if (toDate && d > toDate) return false
    if (selectedMonth !== "all" && new Date(e.expenseDate).getMonth() + 1 !== Number(selectedMonth)) return false
    if (selectedCategory !== "all" && e.categoryName !== selectedCategory) return false
    if (cashAccountFilter === "none" && e.genericCashAccountId != null) return false
    if (cashAccountFilter !== "all" && cashAccountFilter !== "none" && String(e.genericCashAccountId) !== cashAccountFilter) return false
    if (approvalFilter !== "all" && e.status !== approvalFilter) return false
    if (!projectLabels.matches(e.genericExpenseId, projectFilter)) return false
    return true
  }), [expenses, focusExpenseId, searchQuery, fromDate, toDate, selectedMonth, selectedCategory, cashAccountFilter, approvalFilter, projectLabels, projectFilter])

  const sortedExpenses = useMemo(() => sortData(filteredExpenses as any[], sortKey, sortDir) as Row[], [filteredExpenses, sortKey, sortDir])
  const pg = usePagination(sortedExpenses, 10)
  useEffect(() => { pg.setPage(1) }, [searchQuery, fromDate, toDate, selectedMonth, selectedCategory, cashAccountFilter, approvalFilter]) // eslint-disable-line react-hooks/exhaustive-deps
  const handleSort = (key: string) => {
    const next = toggleSort(key, sortKey, sortDir)
    setSortKey(next.key); setSortDir(next.direction)
  }

  // Rejected expenses cost nothing, so they stay out of the totals.
  const counted = (e: Row) => e.status !== "Rejected"
  const filteredTotal = filteredExpenses.filter(counted).reduce((t, e) => t + Number(e.amount || 0), 0)
  const thisMonthTotal = useMemo(() => {
    const now = new Date()
    return expenses.filter((e) => {
      const d = new Date(e.expenseDate)
      return counted(e) && d.getMonth() === now.getMonth() && d.getFullYear() === now.getFullYear()
    }).reduce((t, e) => t + Number(e.amount || 0), 0)
  }, [expenses])

  const activeFilterCount = [searchQuery, fromDate, toDate].filter(Boolean).length
    + [selectedMonth, selectedCategory, cashAccountFilter, approvalFilter].filter((v) => v !== "all").length
  const clearAllFilters = () => {
    setSearchQuery(""); setFromDate(""); setToDate(""); setSelectedMonth("all")
    setSelectedCategory("all"); setCashAccountFilter("all"); setApprovalFilter("all")
  }
  const syncDraftFromCommitted = () => {
    setDraftFromDate(fromDate); setDraftToDate(toDate); setDraftMonth(selectedMonth)
    setDraftCategory(selectedCategory); setDraftApproval(approvalFilter)
  }
  const hasDraftChanges = draftFromDate !== fromDate || draftToDate !== toDate || draftMonth !== selectedMonth
    || draftCategory !== selectedCategory || draftApproval !== approvalFilter
  const applyMobileFilters = () => {
    setFromDate(draftFromDate); setToDate(draftToDate); setSelectedMonth(draftMonth)
    setSelectedCategory(draftCategory); setApprovalFilter(draftApproval); setFiltersOpen(false)
  }
  const categoryNames = Array.from(new Set(expenses.map((e) => e.categoryName).filter(Boolean))) as string[]

  // ------------------------------------------------------------ export -----
  const handleExportCSV = () => {
    const headers = ["ExpenseId", "ExpenseDate", "Category", "Description", "Supplier", "Amount", "Paid", "Balance", "PaymentMethod", "Approval"]
    const out = filteredExpenses.map((e) => [
      e.genericExpenseId, (e.expenseDate ?? "").slice(0, 10), e.categoryName ?? "",
      (e.description ?? "").replace(/\n|\r/g, " "), e.supplierName ?? e.paidTo ?? "",
      e.amount, e.amountPaidN, e.balance, methodLabel(e.paymentMethod), e.status,
    ])
    const csv = [headers.join(","), ...out.map((r) => r.map((cell) => {
      const s = String(cell ?? "")
      return s.includes(",") || s.includes('"') || s.includes("\n") ? '"' + s.replace(/"/g, '""') + '"' : s
    }).join(","))].join("\n")
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" })
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url; a.download = `expenses-${today()}.csv`
    document.body.appendChild(a); a.click(); document.body.removeChild(a); URL.revokeObjectURL(url)
  }
  const handleExportPDF = async () => {
    if (filteredExpenses.length === 0) {
      toast({ title: "Nothing to export", description: "No expenses match the current filters.", variant: "destructive" })
      return
    }
    const fmt = (n: number) => Number(n || 0).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
    try {
      await exportTableToPdf({
        title: "Expenses Report",
        filename: "expenses",
        columns: [{ header: "ID" }, { header: "Date" }, { header: "Category" }, { header: "Description" },
          { header: "Amount", align: "right" }, { header: "Payment" }, { header: "Approval" }],
        rows: filteredExpenses.map((e) => [e.genericExpenseId, fmtDateTime(e.expenseDate, e), e.categoryName ?? "",
          e.description ?? "", fmt(Number(e.amount)), methodLabel(e.paymentMethod), e.status]),
        totalsRow: ["", "", "", "Total (Filtered)", fmt(filteredTotal), "", ""],
        summaryLines: [`Total (Filtered): ${fmt(filteredTotal)}`],
      })
    } catch {
      toast({ title: "PDF export failed", description: "Could not generate PDF. Please try again.", variant: "destructive" })
    }
  }

  // -------------------------------------------------------------- form -----
  const defaultAccountId = () => {
    const expenseDefault = modules.businessSettings?.defaultExpenseCashAccountId
    const paymentDefault = modules.businessSettings?.defaultCashAccountForPayments
    const a = (expenseDefault ? activeAccounts.find((x) => x.genericCashAccountId === expenseDefault) : null)
      ?? (paymentDefault ? activeAccounts.find((x) => x.genericCashAccountId === paymentDefault) : null)
      ?? activeAccounts[0]
    return a ? String(a.genericCashAccountId) : ""
  }
  // --- Repeat previous, as on Poultry: copies what DESCRIBES the expense; amount,
  // cash account and paid status only when asked ("...incl. amount"), marked "check".
  const { businessDate } = useBusinessDate()
  const [prefill, setPrefill] = useState<RepeatPrefill<GenericExpenseForm> | null>(null)
  const [prefillConfirmed, setPrefillConfirmed] = useState(false)
  const [receiptFile, setReceiptFile] = useState<File | null>(null)
  const [receiptRemoved, setReceiptRemoved] = useState(false)
  const previousExpense = useMemo(
    () => latestEntry(expenses.filter((e) => !e.sourceType && e.status !== "Rejected"), (e) => e.expenseDate, (e) => e.genericExpenseId),
    [expenses],
  )
  const createUnconfirmed = editing ? [] : unconfirmedFields(prefill, form as unknown as Partial<GenericExpenseForm>)
  const usedDescriptions = Array.from(new Set(expenses.map((e) => (e.description ?? "").trim()).filter(Boolean)))
    .sort((a, b) => a.localeCompare(b))

  const repeatPrevious = (includeAmount: boolean) => {
    if (!previousExpense) return
    const today = businessDate || new Date().toISOString().split("T")[0]
    const p = buildRepeatPrefill(genericExpensePolicy({ includeAmount }), previousExpense, {
      businessDate: today,
      valid: {
        supplier: new Set(activeSuppliers.map((x) => String(x.genericSupplierId))),
        cashAccount: new Set(activeAccounts.map((a) => String(a.genericCashAccountId))),
        category: new Set(activeCategories.map((c) => String(c.genericExpenseCategoryId))),
      },
    })
    setEditing(null); setFormError(null); setReceiptFile(null); setReceiptRemoved(false)
    setForm({ ...emptyForm(), expenseDate: today, genericCashAccountId: includeAmount ? "" : defaultAccountId(),
      ...(p.values as Partial<FormState>) })
    setPrefill(p); setPrefillConfirmed(false)
    setFormOpen(true)
  }

  const openCreateDialog = () => {
    setEditing(null); setFormError(null); setPrefill(null); setPrefillConfirmed(false)
    setReceiptFile(null); setReceiptRemoved(false)
    setForm({ ...emptyForm(), genericCashAccountId: defaultAccountId() })
    setProject(EMPTY_SINGLE_PROJECT)
    setFormOpen(true)
  }
  const openEditDialog = (e: Row) => {
    setEditing(e); setFormError(null); setPrefill(null); setReceiptFile(null); setReceiptRemoved(false)
    const status: PayStatus = e.paymentMethod === "Credit" && e.amountPaidN <= 0 ? "Unpaid"
      : e.balance > 0 ? "PartiallyPaid" : "Paid"
    setForm({
      expenseDate: (e.expenseDate ?? "").slice(0, 10),
      genericExpenseCategoryId: String(e.genericExpenseCategoryId ?? ""),
      amount: String(e.amount ?? ""),
      paymentMethod: e.paymentMethod === "Credit" ? "Cash" : e.paymentMethod,
      genericCashAccountId: e.genericCashAccountId ? String(e.genericCashAccountId) : defaultAccountId(),
      genericSupplierId: e.genericSupplierId ? String(e.genericSupplierId) : "",
      paidTo: e.paidTo ?? "",
      paymentStatus: status,
      amountPaid: status === "PartiallyPaid" ? String(e.amountPaidN) : "",
      dueDate: (e.dueDate ?? "").slice(0, 10),
      description: e.description ?? "",
      notes: e.notes ?? "",
    })
    setProject(EMPTY_SINGLE_PROJECT)
    if (projectsEnabled) void loadSingleProject("Expense", e.genericExpenseId).then(setProject)
    setFormOpen(true)
  }

  // An approved expense with a supplier payment applied keeps its money as it is.
  const moneyLocked = !!editing && editing.status === "Approved" && Number(editing.paymentsApplied ?? 0) > 0
  const amountNum = Number(form.amount) || 0
  const unpaid = form.paymentStatus === "Unpaid"
  const amountPaidNow = form.paymentStatus === "Paid" ? amountNum : unpaid ? 0 : Number(form.amountPaid) || 0
  const approvalThreshold = modules.businessSettings?.requireApprovalAboveAmount ?? null
  const exceedsThreshold = approvalThreshold !== null && approvalThreshold > 0 && amountNum > approvalThreshold

  const validate = (): string | null => {
    if (!form.genericExpenseCategoryId) return "Select a category."
    if (amountNum <= 0) return "Enter an amount greater than zero."
    if (!form.description.trim()) return "Enter a description."
    if (form.paymentStatus === "PartiallyPaid" && (amountPaidNow <= 0 || amountPaidNow >= amountNum))
      return "For a part payment, the amount paid must be more than 0 and less than the amount."
    if (!unpaid && !form.genericCashAccountId) return "Select the cash account this expense is paid from."
    if (form.paymentStatus !== "Paid" && !form.genericSupplierId)
      return "Select a supplier if you want this unpaid expense to appear in Supplier Balances."
    return null
  }

  const handleSubmit = async (ev: React.FormEvent) => {
    ev.preventDefault()
    if (!editing) {
      const repeatBlock = repeatSubmitBlocker(prefill, form as unknown as Partial<GenericExpenseForm>, prefillConfirmed, FIELD_LABELS.genericExpense)
      if (repeatBlock) { setFormError(repeatBlock); return }
    }
    const problem = validate()
    if (problem) { setFormError(problem); return }
    setSaving(true); setFormError(null)
    let receiptUrl: string | null = editing && !receiptRemoved ? (editing as any).receiptUrl ?? null : null
    if (receiptFile) {
      const up = await uploadExpenseReceipt(receiptFile, getUserContext().farmId ?? "")
      if (!up.success || !up.path) { setSaving(false); setFormError(up.message ?? "Could not upload the receipt."); return }
      receiptUrl = up.path
    }
    const input = {
      expenseDate: form.expenseDate,
      genericExpenseCategoryId: Number(form.genericExpenseCategoryId),
      genericSupplierId: form.genericSupplierId ? Number(form.genericSupplierId) : null,
      description: form.description.trim(),
      amount: amountNum,
      paidTo: form.genericSupplierId ? null : (editing?.paidTo ?? null),
      paymentMethod: unpaid ? "Credit" : form.paymentMethod,
      genericCashAccountId: unpaid ? null : Number(form.genericCashAccountId),
      notes: editing?.notes ?? null,
      receiptUrl,
      amountPaid: form.paymentStatus === "Paid" ? null : amountPaidNow,
      dueDate: form.paymentStatus === "Paid" ? null : (form.dueDate || null),
      projects: projectsEnabled ? singleAssignment(project) : undefined,
    }
    try {
      if (editing) {
        await updateExpense(editing.genericExpenseId, input)
        toast({ title: "Expense updated", description: editing.status === "Approved" ? "Cash and supplier balances follow the change." : undefined })
      } else {
        const created = await createExpense(input)
        toast({
          title: `Expense #${created?.genericExpenseId ?? ""} created as Draft`,
          description: "Approve it to take the money from the cash account and put any unpaid part on the supplier.",
        })
      }
      setFormOpen(false)
      await loadExpenses()
    } catch (e: any) {
      setFormError(e?.message ?? String(e))
    } finally { setSaving(false) }
  }

  // ----------------------------------------------------------- actions -----
  const onApprove = async (e: Row) => {
    try {
      await approveExpense(e.genericExpenseId)
      toast({ title: `Expense #${e.genericExpenseId} approved.` })
      await loadExpenses()
    } catch (err: any) {
      toast({ title: "Approve failed", description: err?.message ?? String(err), variant: "destructive" })
    }
  }
  const onReject = async () => {
    if (!rejectFor || !rejectReason.trim()) return
    try {
      await rejectExpense(rejectFor.genericExpenseId, rejectReason.trim())
      toast({ title: `Expense #${rejectFor.genericExpenseId} rejected.` })
      setRejectFor(null); setRejectReason("")
      await loadExpenses()
    } catch (err: any) {
      toast({ title: "Reject failed", description: err?.message ?? String(err), variant: "destructive" })
    }
  }
  const handleDelete = async (e: Row) => {
    setPendingDelete(null)
    try {
      await deleteExpense(e.genericExpenseId)
      toast({ title: "Expense deleted", description: e.status === "Approved" ? "Its money went back to the cash account and supplier." : "Record has been removed." })
      await loadExpenses()
    } catch (err: any) {
      const msg = err?.message ?? String(err)
      setError(msg)
      toast({ title: "Delete failed", description: msg, variant: "destructive" })
    }
  }

  const ownExpense = (e: Row) => !e.sourceType
  const isPayable = (e: Row) => e.status === "Approved" && ownExpense(e) && !!e.genericSupplierId && e.balance > 0
  const asOpenDocument = (e: Row): OpenDocumentRow => ({
    documentType: "Expense",
    documentId: e.genericExpenseId,
    reference: `E${e.genericExpenseId}`,
    documentDate: e.expenseDate,
    label: e.description || e.categoryName || "Expense",
    totalAmount: Number(e.amount),
    amountPaid: e.amountPaidN,
    balance: e.balance,
    dueDate: e.dueDate ?? null,
    ageDays: Math.max(Math.floor((Date.now() - new Date(e.expenseDate).getTime()) / 86_400_000), 0),
    status: e.paymentStatus ?? "",
    isOverdue: isOverdue(e),
    cashAccountId: e.genericCashAccountId ?? null,
  })

  const renderPaymentStatus = (e: Row) => {
    if (e.paymentStatus === "NonCash") return <Badge variant="outline" className="border-slate-300 text-slate-600">Non-cash</Badge>
    if (e.balance <= 0) return <Badge className="bg-emerald-100 text-emerald-800 hover:bg-emerald-100">Paid</Badge>
    if (isOverdue(e)) return <Badge className="bg-red-100 text-red-800 hover:bg-red-100">Overdue</Badge>
    if (e.amountPaidN > 0) return <Badge className="bg-amber-100 text-amber-800 hover:bg-amber-100">Partially paid</Badge>
    return <Badge className="bg-slate-100 text-slate-700 hover:bg-slate-100">Unpaid</Badge>
  }

  const rowActions = (e: Row, mobile = false) => {
    const draft = e.status === "Draft" || e.status === "Submitted"
    const own = ownExpense(e)
    // 504: an approved expense is final -- no Edit or Delete; it is reversed.
    const editable = own && (draft || e.status === "Rejected")
    const btn = mobile ? "flex-1 h-10" : "h-8 w-8 p-0"
    return (
      <>
        {canApprove && draft && (
          <Button variant={mobile ? "outline" : "ghost"} size="sm" className={cn(btn, "text-emerald-700 hover:bg-emerald-50")}
            title="Approve: take the money from the cash account and put any unpaid part on the supplier" onClick={() => onApprove(e)}>
            <Check className="w-4 h-4" />{mobile && <span className="ml-2">Approve</span>}
          </Button>
        )}
        {canApprove && draft && (
          <Button variant={mobile ? "outline" : "ghost"} size="sm" className={cn(btn, "text-rose-700 hover:bg-rose-50")}
            title="Reject this expense" onClick={() => { setRejectFor(e); setRejectReason("") }}>
            <X className="w-4 h-4" />{mobile && <span className="ml-2">Reject</span>}
          </Button>
        )}
        {canEdit && editable && (
          <Button variant={mobile ? "outline" : "ghost"} size="sm" className={btn} title="Edit" onClick={() => openEditDialog(e)}>
            <Pencil className="w-4 h-4" />{mobile && <span className="ml-2">Edit</span>}
          </Button>
        )}
        {canPay && isPayable(e) && (
          <Button variant={mobile ? "outline" : "ghost"} size="sm" className={cn(btn, "text-emerald-700 hover:bg-emerald-50")}
            title="Record a payment against this expense" onClick={() => setPayFor(e)}>
            <Banknote className="w-4 h-4" />{mobile && <span className="ml-2">Pay</span>}
          </Button>
        )}
        {Number(e.paymentsApplied ?? 0) > 0 && (
          <Button variant={mobile ? "outline" : "ghost"} size="sm" className={btn}
            title="Payments applied to this expense" onClick={() => setHistoryFor(e)}>
            <History className="w-4 h-4" />{mobile && <span className="ml-2">Payments</span>}
          </Button>
        )}
        {e.genericSupplierId && (
          <Button variant={mobile ? "outline" : "ghost"} size="sm" className={btn}
            title="Open this supplier's balance" onClick={() => router.push("/generic-supplier-balances")}>
            <Truck className="w-4 h-4" />{mobile && <span className="ml-2">Supplier</span>}
          </Button>
        )}
        {canReverse && own && e.status === "Approved" && (
          <Button variant={mobile ? "outline" : "ghost"} size="sm" className={cn(btn, "text-red-600 hover:text-red-700 hover:bg-red-50")}
            title="Reverse: undo this approved expense (with a reason)" onClick={() => setReverseFor(e)}>
            <Undo2 className="w-4 h-4" />{mobile && <span className="ml-2">Reverse</span>}
          </Button>
        )}
        {canDelete && editable && (
          <Button variant={mobile ? "outline" : "ghost"} size="sm" className={cn(btn, "text-red-600 hover:text-red-700 hover:bg-red-50")}
            title="Delete" onClick={() => setPendingDelete(e)}>
            <Trash2 className="w-4 h-4" />{mobile && <span className="ml-2">Delete</span>}
          </Button>
        )}
      </>
    )
  }

  // ---------------------------------------------------------- form body -----
  const formFields = (
    <>
      <div className="rounded-xl border border-slate-200 overflow-hidden">
        <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Date</div>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 p-4 bg-white">
          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">Expense Date *</Label>
            <Input type="date" value={form.expenseDate} onChange={(e) => setForm({ ...form, expenseDate: e.target.value })} required disabled={saving} />
          </div>
        </div>
      </div>
      <div className="rounded-xl border border-slate-200 overflow-hidden">
        <div className="bg-green-600 px-4 py-2 text-sm font-semibold text-white">Category &amp; Payment</div>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 p-4 bg-white">
          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">Category *</Label>
            <Select value={form.genericExpenseCategoryId} onValueChange={(v) => setForm({ ...form, genericExpenseCategoryId: v })}>
              <SelectTrigger><SelectValue placeholder="Select category" /></SelectTrigger>
              <SelectContent>
                {activeCategories.length === 0 && <SelectItem value="none" disabled>No categories yet (Setup → Expense categories)</SelectItem>}
                {activeCategories.map((c) => <SelectItem key={c.genericExpenseCategoryId} value={String(c.genericExpenseCategoryId)}>{c.name}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">Amount *<ReviewMark show={createUnconfirmed.includes("amount")} /></Label>
            <NumberInput step="0.01" min="0" value={form.amount} onChange={(e) => setForm({ ...form, amount: e.target.value })}
              placeholder="0.00" required disabled={saving || moneyLocked} className="max-w-[200px]" />
            {exceedsThreshold && (
              <div className="text-xs text-amber-700">Exceeds approval threshold of {approvalThreshold!.toFixed(2)} — will require manager approval.</div>
            )}
          </div>
          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">Payment Method *</Label>
            <Select value={form.paymentMethod} onValueChange={(v) => setForm({ ...form, paymentMethod: v })} disabled={saving || unpaid || moneyLocked}>
              <SelectTrigger><SelectValue placeholder="Select payment method" /></SelectTrigger>
              <SelectContent>
                {PAY_METHODS.map((m) => <SelectItem key={m.value} value={m.value}>{m.label}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">Pay from cash account{unpaid ? "" : " *"}<ReviewMark show={createUnconfirmed.includes("genericCashAccountId")} /></Label>
            <Select value={unpaid ? "none" : (form.genericCashAccountId || "none")} disabled={saving || unpaid || moneyLocked}
              onValueChange={(v) => setForm({ ...form, genericCashAccountId: v === "none" ? "" : v })}>
              <SelectTrigger><SelectValue placeholder="Select cash account" /></SelectTrigger>
              <SelectContent>
                {unpaid && <SelectItem value="none">None (no cash movement)</SelectItem>}
                {!unpaid && <SelectItem value="none" disabled>Select cash account</SelectItem>}
                {activeAccounts.map((a) => (
                  <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>
                    {a.accountName} ({formatCurrency(Number(a.currentBalance ?? 0))})
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <div className="text-xs text-slate-500">
              {unpaid ? "Nothing is paid now: the whole amount is owed to the supplier." : "Posts a cash-out and reduces the account balance when the expense is approved."}
            </div>
          </div>
        </div>
      </div>
      <div className="rounded-xl border border-slate-200 overflow-hidden">
        <div className="bg-sky-600 px-4 py-2 text-sm font-semibold text-white">Supplier &amp; Payment Status</div>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 p-4 bg-white">
          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">Supplier / Paid To</Label>
            <Select value={form.genericSupplierId || "none"} disabled={saving || moneyLocked}
              onValueChange={(v) => setForm({ ...form, genericSupplierId: v === "none" ? "" : v })}>
              <SelectTrigger><SelectValue placeholder="Not linked to a supplier" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="none">Not linked to a supplier</SelectItem>
                {activeSuppliers.map((s) => <SelectItem key={s.genericSupplierId} value={String(s.genericSupplierId)}>{s.supplierName}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">Payment Status *<ReviewMark show={createUnconfirmed.includes("paymentStatus")} /></Label>
            <Select value={form.paymentStatus} disabled={saving || moneyLocked}
              onValueChange={(v) => setForm({ ...form, paymentStatus: v as PayStatus })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {SELECTABLE_PAYMENT_STATUSES.map((st) => <SelectItem key={st} value={st}>{PAYMENT_STATUS_LABELS[st]}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">Amount Paid {form.paymentStatus === "PartiallyPaid" ? "*" : ""}</Label>
            <NumberInput step="0.01" min="0"
              value={form.paymentStatus === "PartiallyPaid" ? form.amountPaid : (form.paymentStatus === "Paid" ? form.amount : "0")}
              onChange={(e) => setForm({ ...form, amountPaid: e.target.value })}
              placeholder="0.00" disabled={saving || moneyLocked || form.paymentStatus !== "PartiallyPaid"} className="max-w-[200px]" />
            <div className="text-xs text-slate-500">Balance: {formatCurrency(Math.max(amountNum - amountPaidNow, 0))}</div>
          </div>
          <div className="space-y-2">
            <Label className="text-sm font-medium text-slate-700">Due Date</Label>
            <Input type="date" value={form.dueDate} onChange={(e) => setForm({ ...form, dueDate: e.target.value })}
              disabled={saving || form.paymentStatus === "Paid"} />
            <div className="text-xs text-slate-500">Overrides the supplier&apos;s payment terms.</div>
          </div>
          {form.paymentStatus !== "Paid" && !form.genericSupplierId && (
            <div className="md:col-span-2 self-end">
              <Alert>
                <AlertDescription className="text-sm">
                  Select a supplier if you want this unpaid expense to appear in Supplier Balances.
                </AlertDescription>
              </Alert>
            </div>
          )}
          {moneyLocked && (
            <div className="md:col-span-3">
              <Alert>
                <AlertDescription className="text-sm">
                  A supplier payment is applied to this expense, so its amount, payment and supplier are locked.
                  Reverse that payment on Supplier Payments to change them.
                </AlertDescription>
              </Alert>
            </div>
          )}
        </div>
      </div>
      {projectsEnabled && (
        <div className="rounded-xl border border-slate-200 overflow-hidden">
          <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Project / Contract</div>
          <div className="p-4 bg-white">
            <SingleProjectField value={project} onChange={setProject} amount={amountNum} label="Related project / contract"
              hint="Recorded once, for the company. This only says which project the cost belongs to; share it to split one bill between projects." />
          </div>
        </div>
      )}
      <div className="rounded-xl border border-slate-200 overflow-hidden">
        <div className="bg-amber-600 px-4 py-2 text-sm font-semibold text-white">Description</div>
        <div className="p-4 bg-white space-y-4">
          {!editing ? (
            <AddExpenseDescription value={form.description} options={usedDescriptions} disabled={saving}
              onChange={(description) => setForm({ ...form, description })} />
          ) : (
            <Textarea value={form.description} maxLength={500} onChange={(e) => setForm({ ...form, description: e.target.value })}
              placeholder="Enter expense description..." rows={3} required disabled={saving} />
          )}
          <ExpenseReceiptField
            existingPath={editing && !receiptRemoved ? ((editing as any).receiptUrl ?? null) : null}
            resolveReceiptFarmId={getUserContext().farmId ?? ""}
            pendingFile={receiptFile}
            onPendingFileChange={setReceiptFile}
            onRemoveExisting={() => setReceiptRemoved(true)}
            disabled={saving}
          />
        </div>
      </div>
    </>
  )

  const approvalSelect = (value: string, onChange: (v: string) => void, cls?: string, contentCls?: string) => (
    <Select value={value} onValueChange={onChange}>
      <SelectTrigger className={cls}><SelectValue placeholder="Approval" /></SelectTrigger>
      <SelectContent className={contentCls}>
        {APPROVAL_FILTERS.map((s) => (
          <SelectItem key={s} value={s}>
            {s === "all" ? "All approvals" : `${s} (${expenses.filter((e) => e.status === s).length})`}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  )

  if (loading && rows.length === 0) {
    return (
      <div className="flex h-screen bg-slate-50">
        <DashboardSidebar onLogout={logout} />
        <div className="flex-1 flex flex-col min-w-0">
          <DashboardHeader />
          <main className="flex-1 overflow-y-auto overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-6 min-w-0">
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
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-6 min-w-0">
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
              <div className="flex flex-wrap gap-2 w-full sm:w-auto shrink-0">
                <RepeatPreviousButton available={!!previousExpense} className="h-11 sm:h-10"
                  label={previousExpense ? genericExpensePolicy({ includeAmount: false }).describe(previousExpense) : null}
                  onClick={() => repeatPrevious(false)} />
                {previousExpense && (
                  <Button type="button" variant="ghost" className="h-11 sm:h-10 text-xs text-slate-600" onClick={() => repeatPrevious(true)}
                    title="Also copy the amount, cash account and paid status — each marked for you to check.">
                    …incl. amount
                  </Button>
                )}
                {canCreate && (
                  <Button className="gap-2 flex-1 sm:flex-none h-11 sm:h-10 bg-blue-600 hover:bg-blue-700" onClick={openCreateDialog}>
                    <Plus className="w-4 h-4" /> Add Expense
                  </Button>
                )}
              </div>
            </div>
            {focusExpenseId && (
              <div className="mb-4 flex flex-wrap items-center gap-3 rounded-lg border border-sky-200 bg-sky-50 px-4 py-2 text-sm text-sky-900">
                <span>Showing expense #{focusExpenseId} only.</span>
                <Button variant="outline" size="sm" className="h-8" onClick={() => router.push("/generic-expenses")}>
                  Show all expenses
                </Button>
              </div>
            )}

            {error && <Alert variant="destructive"><AlertDescription>{error}</AlertDescription></Alert>}

            {/* Filters */}
            {isMobile ? (
              <div className="space-y-3 w-full min-w-0">
                <div className="relative">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                  <Input placeholder="Search expenses..." value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)} className="pl-10 h-11" />
                </div>
                <div className={MOBILE_FILTERS_TOOLBAR_ROW_CLASS}>
                  <Sheet open={filtersOpen} onOpenChange={(open) => { setFiltersOpen(open); syncDraftFromCommitted() }}>
                    <SheetTrigger asChild>
                      <Button variant="outline" className={MOBILE_FILTERS_TRIGGER_BUTTON_CLASS}>
                        <Filter className="h-4 w-4" />
                        <span className="truncate">Filters</span>
                        {activeFilterCount > 0 && (
                          <span className="ml-1 h-5 min-w-[20px] px-1.5 rounded-full bg-orange-500 text-white text-xs flex items-center justify-center">{activeFilterCount}</span>
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
                              <label htmlFor="gexp-filter-from" className="text-xs font-medium text-slate-500">Start date</label>
                              <Input id="gexp-filter-from" type="date" value={draftFromDate} onChange={(e) => setDraftFromDate(e.target.value)} className="h-12 min-w-0 w-full text-base" />
                            </div>
                            <div className="min-w-0 space-y-2">
                              <label htmlFor="gexp-filter-to" className="text-xs font-medium text-slate-500">End date</label>
                              <Input id="gexp-filter-to" type="date" value={draftToDate} onChange={(e) => setDraftToDate(e.target.value)} className="h-12 min-w-0 w-full text-base" />
                            </div>
                          </div>
                        </div>
                        <div className="space-y-2">
                          <label className="text-sm font-medium text-slate-700">Month</label>
                          <Select value={draftMonth} onValueChange={setDraftMonth}>
                            <SelectTrigger className="h-12 text-base"><SelectValue placeholder="Month" /></SelectTrigger>
                            <SelectContent className={MOBILE_FILTER_SELECT_CONTENT_CLASS}>
                              <SelectItem value="all">All Months</SelectItem>
                              {MONTHS.map((m, i) => <SelectItem key={i + 1} value={String(i + 1)}>{m}</SelectItem>)}
                            </SelectContent>
                          </Select>
                        </div>
                        <div className="space-y-2">
                          <label className="text-sm font-medium text-slate-700">Category</label>
                          <Select value={draftCategory} onValueChange={setDraftCategory}>
                            <SelectTrigger className="h-12 text-base"><SelectValue placeholder="Category" /></SelectTrigger>
                            <SelectContent className={MOBILE_FILTER_SELECT_CONTENT_CLASS}>
                              <SelectItem value="all">All Category</SelectItem>
                              {categoryNames.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}
                            </SelectContent>
                          </Select>
                        </div>
                        <div className="space-y-2">
                          <label className="text-sm font-medium text-slate-700">Approval</label>
                          {approvalSelect(draftApproval, setDraftApproval, "h-12 text-base", MOBILE_FILTER_SELECT_CONTENT_CLASS)}
                        </div>
                      </MobileFilterSheetBody>
                      <MobileFilterSheetFooter>
                        <div className="flex flex-col gap-3">
                          {canExport && (
                            <div className="flex gap-2">
                              <Button variant="outline" className="h-11 flex-1" onClick={handleExportPDF}><FileTextIcon className="w-4 h-4 mr-2" />PDF</Button>
                              <Button variant="outline" className="h-11 flex-1" onClick={handleExportCSV}><Download className="w-4 h-4 mr-2" />CSV</Button>
                            </div>
                          )}
                          <div className="flex gap-3">
                            <Button type="button" variant="outline" className="h-12 flex-1"
                              onClick={() => { clearAllFilters(); setFiltersOpen(false); toast({ title: "Filters cleared" }) }}>
                              Clear all
                            </Button>
                            <Button type="button" className="h-12 flex-1" onClick={applyMobileFilters} disabled={!hasDraftChanges}>Apply</Button>
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
                <Select
                  value={fromDate && toDate ? rangeToPeriod(fromDate, toDate) : "custom"}
                  onValueChange={(v) => { const r = periodToRange(v as never); if (r) { setFromDate(r.from); setToDate(r.to) } }}
                >
                  <SelectTrigger className="w-[160px]"><SelectValue placeholder="Period" /></SelectTrigger>
                  <SelectContent>
                    {PERIOD_GROUPS.map((g, gi) => (
                      <SelectGroup key={g.label}>
                        {gi > 0 && <SelectSeparator />}
                        {g.options.map((o) => <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>)}
                      </SelectGroup>
                    ))}
                  </SelectContent>
                </Select>
                <div className="relative w-full sm:w-[140px]">
                  <Calendar className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                  <Input type="date" placeholder="From" value={fromDate} onChange={(e) => setFromDate(e.target.value)} className="pl-9" />
                </div>
                <div className="relative w-full sm:w-[140px]">
                  <Calendar className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                  <Input type="date" placeholder="To" value={toDate} onChange={(e) => setToDate(e.target.value)} className="pl-9" />
                </div>
                <Select value={selectedMonth} onValueChange={setSelectedMonth}>
                  <SelectTrigger className="w-[140px]"><SelectValue placeholder="Month" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">All Months</SelectItem>
                    {MONTHS.map((m, i) => <SelectItem key={i + 1} value={String(i + 1)}>{m}</SelectItem>)}
                  </SelectContent>
                </Select>
                <Select value={selectedCategory} onValueChange={setSelectedCategory}>
                  <SelectTrigger className="w-[180px]"><SelectValue placeholder="Category" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">All Category</SelectItem>
                    {categoryNames.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}
                  </SelectContent>
                </Select>
                <Select value={cashAccountFilter} onValueChange={setCashAccountFilter}>
                  <SelectTrigger className="w-[200px]"><SelectValue placeholder="Cash account" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">All cash accounts</SelectItem>
                    <SelectItem value="none">No cash account ({expenses.filter((e) => e.genericCashAccountId == null).length})</SelectItem>
                    {cashAccounts.map((a) => <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>{a.accountName}</SelectItem>)}
                  </SelectContent>
                </Select>
                {approvalSelect(approvalFilter, setApprovalFilter, "w-[170px]")}
                <ProjectFilter value={projectFilter} onChange={setProjectFilter} />
                {activeFilterCount > 0 && (
                  <Button variant="ghost" size="sm" onClick={clearAllFilters}>Clear ({activeFilterCount})</Button>
                )}
                {canExport && (
                  <div className="ml-auto flex items-center gap-2">
                    <Button variant="outline" size="sm" className="flex items-center gap-2" onClick={handleExportPDF}><FileTextIcon className="w-4 h-4" />PDF</Button>
                    <Button variant="outline" size="sm" className="flex items-center gap-2" onClick={handleExportCSV}><Download className="w-4 h-4" />CSV</Button>
                  </div>
                )}
              </div>
            )}

            {/* Summary Cards */}
            <div className={cn("grid gap-4", isMobile ? "grid-cols-1" : "grid-cols-1 md:grid-cols-2")}>
              <Card className="bg-white">
                <CardHeader className="pb-2"><CardDescription>This Month</CardDescription></CardHeader>
                <CardContent className="min-w-0">
                  <div className={cn("font-bold text-slate-900 leading-tight whitespace-nowrap", isMobile ? "text-3xl" : "text-2xl")}>{formatCurrency(thisMonthTotal)}</div>
                </CardContent>
              </Card>
              <Card className="bg-white">
                <CardHeader className="pb-2"><CardDescription>Total (Filtered)</CardDescription></CardHeader>
                <CardContent className="min-w-0">
                  <div className={cn("font-bold text-slate-900 leading-tight whitespace-nowrap", isMobile ? "text-3xl" : "text-2xl")}>{formatCurrency(filteredTotal)}</div>
                </CardContent>
              </Card>
            </div>

            {/* Table */}
            {filteredExpenses.length === 0 ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center">
                  <DollarSign className="w-12 h-12 text-slate-400 mx-auto mb-4" />
                  <h3 className="text-lg font-semibold text-slate-900 mb-2">No expenses found</h3>
                  <p className="text-slate-600 mb-6">{activeFilterCount > 0 ? "No expenses match your search criteria." : "Start tracking your business expenses."}</p>
                  {canCreate && <Button className="gap-2 bg-blue-600 hover:bg-blue-700" onClick={openCreateDialog}><Plus className="w-4 h-4" />Add First Expense</Button>}
                </CardContent>
              </Card>
            ) : (
              <Card className="bg-white overflow-hidden">
                <CardHeader><CardTitle>Expenses</CardTitle><CardDescription>Manage your business expenses</CardDescription></CardHeader>
                <CardContent className="p-0">
                  {isMobile && !showAllColumnsMobile ? (
                    <div className="space-y-3">
                      {pg.pageItems.map((expense, idx) => (
                        <Collapsible key={expense.genericExpenseId} defaultOpen className={cn("group rounded-xl border shadow-sm overflow-hidden", idx % 2 === 0 ? "bg-amber-100 border-amber-300" : "bg-white border-slate-200")}>
                          <div className="p-4">
                            <CollapsibleTrigger asChild>
                              <div className="flex items-start justify-between gap-3 cursor-pointer">
                                <div className="min-w-0 flex-1">
                                  <div className="flex items-center gap-2 flex-wrap">
                                    <span className="font-semibold text-slate-900 shrink-0">{formatDateShort(expense.expenseDate)}</span>
                                    <Badge className="whitespace-normal break-words shrink min-w-0 text-left bg-gray-100 text-gray-800">{expense.categoryName}</Badge>
                                    {expense.expenseReversalId
                                      ? <Badge variant="outline" className="border-slate-300 bg-slate-100 text-slate-600">Reversed</Badge>
                                      : <Badge className={approvalBadge(expense.status)}>{expense.status}</Badge>}
                                  </div>
                                  <div className="mt-1 flex items-baseline gap-3">
                                    <span className="text-lg font-bold text-red-600">{formatCurrency(Number(expense.amount))}</span>
                                    <span className="text-sm text-slate-600 truncate">{expense.description}</span>
                                  </div>
                                </div>
                                <ChevronDown className="h-5 w-5 text-slate-400 shrink-0 transition-transform group-data-[state=open]:rotate-180" />
                              </div>
                            </CollapsibleTrigger>
                            <CollapsibleContent>
                              <div className="mt-4 pt-4 border-t border-slate-100 space-y-2 text-sm">
                                <div className="grid grid-cols-2 gap-2">
                                  <div><span className="text-slate-500">Payment</span> <span className="font-medium">{methodLabel(expense.paymentMethod)}</span></div>
                                  <div><span className="text-slate-500">Paid to</span> <span className="font-medium">{expense.supplierName || expense.paidTo || "N/A"}</span></div>
                                  <div><span className="text-slate-500">Paid</span> <span className="font-medium">{formatCurrency(expense.amountPaidN)}</span></div>
                                  <div><span className="text-slate-500">Balance</span> <span className="font-medium">{formatCurrency(expense.balance)}</span></div>
                                  {projectLabels.enabled && (
                                    <div className="col-span-2"><span className="text-slate-500">{PROJECT_COLUMN_TITLE}</span> <ProjectLabels labels={projectLabels.labelsOf(expense.genericExpenseId)} /></div>
                                  )}
                                </div>
                                <div>{renderPaymentStatus(expense)}</div>
                                {expense.sourceType === "GenericPayrollRun" ? (
                                  <div className="text-xs text-slate-500">From <Link href="/generic-payroll" className="text-blue-600 hover:underline">Payroll</Link> (change it there)</div>
                                ) : expense.sourceType && <div className="text-xs text-slate-500">Made by {expense.sourceType}</div>}
                                <div className="flex flex-wrap gap-2 pt-2">{rowActions(expense, true)}</div>
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
                          <Button variant="ghost" size="sm" onClick={() => setShowAllColumnsMobile(false)}><ChevronUp className="h-4 w-4 mr-1" /> Cards</Button>
                        </div>
                      )}
                      {/* Date 100 + Category 150 + Supplier 140 + Total 110 + Paid 110 + Balance 110
                          + Status 120 + Method 120 + Approval 110 + Actions 180 = 1250, + 250 Description = 1500. */}
                      <Table className={cn("table-fixed w-full", projectLabels.enabled ? "min-w-[1660px]" : "min-w-[1500px]")}>
                        <TableHeader>
                          <TableRow>
                            <SortableHeader label="Date" sortKey="expenseDate" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="w-[100px]" />
                            <SortableHeader label="Description" sortKey="description" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="w-auto min-w-0" />
                            <SortableHeader label="Category" sortKey="categoryName" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="w-[150px]" />
                            <SortableHeader label="Supplier / Paid To" sortKey="supplierName" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="w-[140px] min-w-0" />
                            {projectLabels.enabled && <ProjectHead className="w-[160px]" />}
                            <SortableHeader label="Total" sortKey="amount" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="w-[110px] text-right whitespace-nowrap" />
                            <SortableHeader label="Paid" sortKey="amountPaidN" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="w-[110px] text-right whitespace-nowrap" />
                            <SortableHeader label="Balance" sortKey="balance" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="w-[110px] text-right whitespace-nowrap" />
                            <SortableHeader label="Status" sortKey="paymentStatus" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="w-[120px]" />
                            <SortableHeader label="Method" sortKey="paymentMethod" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="w-[120px]" />
                            <SortableHeader label="Approval" sortKey="status" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="w-[110px]" />
                            <TableHead className="text-right w-[180px] min-w-[180px] whitespace-nowrap">Actions</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {pg.pageItems.map((expense) => (
                            <TableRow key={expense.genericExpenseId}>
                              <TableCell className="font-medium bg-white align-top"><DateTimeCell value={expense.expenseDate} row={expense} /></TableCell>
                              <TableCell className="min-w-0 align-top overflow-hidden whitespace-normal">
                                <div className="font-medium flex items-start gap-2 min-w-0">
                                  <span className="min-w-0 wrap-anywhere">{expense.description}</span>
                                  {toReceiptViewUrl((expense as any).receiptUrl, getUserContext().farmId) && (
                                    <a href={toReceiptViewUrl((expense as any).receiptUrl, getUserContext().farmId)!} target="_blank" rel="noopener noreferrer"
                                       className="inline-flex shrink-0 text-blue-600 hover:text-blue-800" title="View receipt">
                                      <ImageIcon className="h-4 w-4" />
                                    </a>
                                  )}
                                </div>
                                {expense.notes && <div className="text-sm text-slate-500">{expense.notes}</div>}
                                {expense.sourceType === "GenericPayrollRun" ? (
                                  <div className="text-[10px] text-slate-500 mt-0.5">From <Link href="/generic-payroll" className="text-blue-600 hover:underline">Payroll</Link> (change it there)</div>
                                ) : expense.sourceType && <div className="text-[10px] text-slate-500 mt-0.5">Made by {expense.sourceType}</div>}
                                {expense.status === "Rejected" && expense.rejectionReason && (
                                  <div className="text-[10px] text-rose-600 mt-0.5">Rejected: {expense.rejectionReason}</div>
                                )}
                              </TableCell>
                              <TableCell className="align-top min-w-0"><Badge className="whitespace-normal break-words shrink max-w-full text-left bg-gray-100 text-gray-800">{expense.categoryName}</Badge></TableCell>
                              <TableCell className="text-slate-600 min-w-0 wrap-anywhere whitespace-normal align-top overflow-hidden">{expense.supplierName || expense.paidTo || "N/A"}</TableCell>
                              {projectLabels.enabled && <ProjectCell className="align-top min-w-0" labels={projectLabels.labelsOf(expense.genericExpenseId)} />}
                              <TableCell className="text-right font-medium whitespace-nowrap align-top">{formatCurrency(Number(expense.amount))}</TableCell>
                              <TableCell className="text-right whitespace-nowrap align-top text-slate-600">{formatCurrency(expense.amountPaidN)}</TableCell>
                              <TableCell className={cn("text-right whitespace-nowrap align-top font-medium", expense.balance > 0 ? "text-amber-700" : "text-slate-400")}>{formatCurrency(expense.balance)}</TableCell>
                              <TableCell className="align-top">{renderPaymentStatus(expense)}</TableCell>
                              <TableCell className="align-top"><Badge variant="outline">{methodLabel(expense.paymentMethod)}</Badge></TableCell>
                              <TableCell className="align-top">{expense.expenseReversalId
                                      ? <Badge variant="outline" className="border-slate-300 bg-slate-100 text-slate-600">Reversed</Badge>
                                      : <Badge className={approvalBadge(expense.status)}>{expense.status}</Badge>}</TableCell>
                              <TableCell className="text-right whitespace-nowrap bg-white">
                                <div className="flex flex-wrap items-center justify-end gap-2 min-w-[80px]">{rowActions(expense)}</div>
                              </TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    </div>
                  )}
                  <DataPagination variant="records" page={pg.page} pageSize={pg.pageSize} total={pg.total}
                    onPageChange={pg.setPage} onPageSizeChange={(n) => { pg.setPageSize(n); pg.setPage(1) }}
                    pageSizeOptions={[5, 10, 15, 25, 50, 100]} className="px-4 py-3 border-t bg-slate-50" />
                </CardContent>
              </Card>
            )}
          </div>
        </main>
      </div>

      {/* Add / Edit Expense Dialog */}
      <Dialog open={formOpen} onOpenChange={setFormOpen}>
        <DialogContent className="w-[95vw] max-w-[1600px] max-h-[90vh] flex flex-col gap-4 overflow-hidden p-6">
          <DialogHeader className="shrink-0">
            <DialogTitle className="flex items-center gap-2">
              {editing ? <><Pencil className="w-5 h-5 text-blue-600" /> Edit Expense</> : <><DollarSign className="w-5 h-5 text-green-600" /> Add Expense</>}
            </DialogTitle>
            <DialogDescription>
              {editing ? "Update expense information" : "Record a new business expense. It is saved as a Draft; approving it moves the money."}
            </DialogDescription>
          </DialogHeader>
          {formError && <Alert variant="destructive" className="shrink-0"><AlertDescription>{formError}</AlertDescription></Alert>}
          {prefill && !editing && (
            <div className="shrink-0">
              <PrefilledBanner prefill={prefill} fieldLabels={FIELD_LABELS.genericExpense}
                unconfirmed={createUnconfirmed} confirmed={prefillConfirmed} onConfirmedChange={setPrefillConfirmed}
                onClear={openCreateDialog} />
            </div>
          )}
          <form onSubmit={handleSubmit} className="flex min-h-0 flex-1 flex-col gap-0">
            <div className="min-h-0 flex-1 overflow-y-auto space-y-4 pr-2">{formFields}</div>
            <div className="shrink-0 flex gap-3 justify-end border-t pt-3 mt-2">
              <Button type="button" onClick={() => setFormOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
              <Button type="submit" disabled={saving}>
                {saving
                  ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />{editing ? "Saving..." : "Creating..."}</>
                  : editing ? <><Pencil className="w-4 h-4 mr-2" />Save Changes</> : <><DollarSign className="w-4 h-4 mr-2" />Create Expense</>}
              </Button>
            </div>
          </form>
        </DialogContent>
      </Dialog>

      {/* Delete confirmation */}
      <AlertDialog open={!!pendingDelete} onOpenChange={(o) => { if (!o) setPendingDelete(null) }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete expense?</AlertDialogTitle>
            <AlertDialogDescription>
              {pendingDelete?.description ? <>This will permanently remove &ldquo;{pendingDelete.description}&rdquo;.</> : <>This action cannot be undone.</>}
              {pendingDelete?.status === "Approved" && <> Its money goes back to the cash account, and what was owed comes off the supplier.</>}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={() => { if (pendingDelete) handleDelete(pendingDelete) }} className="bg-red-600 hover:bg-red-700">Delete</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Reject (Generic's approval step) */}
      <Dialog open={!!rejectFor} onOpenChange={(o) => { if (!o) setRejectFor(null) }}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Reject expense?</DialogTitle>
            <DialogDescription>A rejected expense moves no money. You can edit it later and it goes back to Draft.</DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            <Label>Reason *</Label>
            <Textarea value={rejectReason} maxLength={500} rows={3} onChange={(e) => setRejectReason(e.target.value)} placeholder="Why is it rejected?" />
          </div>
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setRejectFor(null)}>Cancel</Button>
            <Button className="bg-rose-600 hover:bg-rose-700" disabled={!rejectReason.trim()} onClick={onReject}>Reject</Button>
          </div>
        </DialogContent>
      </Dialog>

      {payFor && (
        <RecordPaymentDialog
          open={!!payFor}
          onOpenChange={(open) => { if (!open) setPayFor(null) }}
          module="generic"
          side="supplier"
          party={{
            partyId: payFor.genericSupplierId!,
            partyName: payFor.supplierName ?? payFor.paidTo ?? "Supplier",
            paymentTermsDays: 0,
            totalBalance: payFor.balance,
            openDocumentCount: 1,
            overdueAmount: isOverdue(payFor) ? payFor.balance : 0,
            totalInvoiced: Number(payFor.amount),
            totalPaid: payFor.amountPaidN,
          }}
          singleDocument={asOpenDocument(payFor)}
          cashAccounts={activeAccounts.map<CashAccountOption>((a) => ({
            id: a.genericCashAccountId,
            name: a.accountName,
            currentBalance: Number(a.currentBalance ?? 0),
            allowNegativeBalance: !!a.allowNegativeBalance,
          }))}
          sourceType="ExpenseEntry"
          onPosted={() => { setPayFor(null); loadExpenses() }}
        />
      )}

      {historyFor && (
        <PaymentHistoryDialog
          open={!!historyFor}
          onOpenChange={(open) => { if (!open) setHistoryFor(null) }}
          module="generic"
          side="supplier"
          partyId={historyFor.genericSupplierId ?? null}
          partyName={historyFor.supplierName ?? historyFor.paidTo ?? null}
          documentType="Expense"
          documentId={historyFor.genericExpenseId}
          canReverse={canReverse}
          onReversed={() => loadExpenses()}
        />
      )}

      {/* 504: reverse an approved expense (the shared reverse dialog) */}
      <ReversePurchaseDialog
        open={!!reverseFor}
        module="generic-expense"
        purchaseId={reverseFor?.genericExpenseId ?? null}
        purchaseLabel={reverseFor ? `#${reverseFor.genericExpenseId}` : ""}
        farmId={getUserContext().farmId ?? ""}
        userId={getUserContext().userId ?? undefined}
        currencyCode={getSelectedCurrency()}
        onOpenChange={(o) => { if (!o) setReverseFor(null) }}
        onReversed={async ({ reversal }) => {
          setReverseFor(null)
          toast({
            title: `Expense reversed${reversal?.reversalNumber ? ` (${reversal.reversalNumber})` : ""}`,
            description: reversal
              ? [reversal.refunded > 0 ? `${formatCurrency(reversal.refunded, getSelectedCurrency())} refunded` : "",
                 reversal.creditCreated > 0 ? `${formatCurrency(reversal.creditCreated, getSelectedCurrency())} kept as supplier credit` : ""]
                  .filter(Boolean).join(" · ") || "Its cost is off Profit & Loss; nothing was paid."
              : undefined,
          })
          await loadExpenses()
        }}
      />
    </div>
  )
}

export default function GenericExpensesPage() {
  return (
    <Suspense fallback={null}>
      <GenericExpensesPageInner />
    </Suspense>
  )
}
