"use client"
import { Suspense, useEffect, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { useFmt } from "@/lib/currency"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Plus, Receipt, DollarSign, Tag, Trash2, CalendarDays, Search, Pencil } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { EmptyState } from "@/components/restaurant/empty-state"
import { PageHeader } from "@/components/restaurant/page-header"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import {
  listExpenses, createExpense, updateExpense, deleteExpense,
  listExpenseCategories, createExpenseCategory, deleteExpenseCategory,
  type RestaurantExpense, type RestaurantExpenseInput, type ExpenseCategory,
} from "@/lib/api/restaurant"
import { listCashAccounts, type CashAccount } from "@/lib/api/restaurant-finance"
import {
  listExpensePayments, listSuppliers, type RestaurantExpensePayment, type RestaurantSupplierRow,
} from "@/lib/api/restaurant-suppliers"
import {
  SELECTABLE_PAYMENT_STATUSES, PAYMENT_STATUS_LABELS, amountPaidForStatus, requiresCashAccount,
  type SelectablePaymentStatus,
} from "@/lib/expenses/payment-status"

const PAYMENT_METHODS = ["Cash", "Card", "Bank Transfer", "MobileMoney", "Cheque"]

const emptyForm: RestaurantExpenseInput = {
  expenseDate: new Date().toISOString().split("T")[0],
  categoryId: null,
  description: "",
  amount: 0,
  paymentMethod: "Cash",
  supplierName: "",
  receiptRef: "",
  cashAccountId: null,
  supplierId: null,
  amountPaid: null,
  dueDate: null,
}

// Poultry's payment-status colours (Paid emerald, part-paid amber, unpaid red).
const STATUS_BADGE: Record<string, string> = {
  Paid: "bg-emerald-50 text-emerald-700 border-emerald-200",
  PartiallyPaid: "bg-amber-50 text-amber-700 border-amber-200",
  Unpaid: "bg-red-50 text-red-700 border-red-200",
}

// useSearchParams needs a Suspense boundary for the static build.
export default function RestaurantExpensesPage() {
  return <Suspense fallback={<PageSkeleton statCards={4} listRows={6} />}><RestaurantExpensesInner /></Suspense>
}

function RestaurantExpensesInner() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [loading, setLoading] = useState(true)
  const [expenses, setExpenses] = useState<RestaurantExpense[]>([])
  const [categories, setCategories] = useState<ExpenseCategory[]>([])
  // Where the money came from. Optional: left empty, the server uses the default
  // account for the payment method (cash box, bank, mobile money).
  const [accounts, setAccounts] = useState<CashAccount[]>([])
  const [activeTab, setActiveTab] = useState<"expenses" | "categories">("expenses")
  // The Expenses menu links straight to the categories tab (?tab=categories).
  useEffect(() => {
    setActiveTab(searchParams.get("tab") === "categories" ? "categories" : "expenses")
  }, [searchParams])
  const [dialogOpen, setDialogOpen] = useState(false)
  // Migration 337: the expense being edited, or null when recording a new one.
  const [editingId, setEditingId] = useState<number | null>(null)
  const [saving, setSaving] = useState(false)
  const [expenseForm, setExpenseForm] = useState<RestaurantExpenseInput>({ ...emptyForm })
  const [newCategoryName, setNewCategoryName] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  // Migration 329: who each expense is owed to and what is still unpaid, read
  // next to the list (the list's own shape cannot change), plus the suppliers.
  const [payments, setPayments] = useState<Record<number, RestaurantExpensePayment>>({})
  const [supplierRows, setSupplierRows] = useState<RestaurantSupplierRow[]>([])
  const [paymentStatus, setPaymentStatus] = useState<SelectablePaymentStatus>("Paid")
  const [partPaid, setPartPaid] = useState("")
  // ?expenseId= (from Supplier Balances / Payments) narrows the list to one bill.
  const focusId = searchParams.get("expenseId") ? Number(searchParams.get("expenseId")) : null

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
  }, [activeFarmType, router])

  const fetchData = async () => {
    try {
      setLoading(true)
      const [exp, cats, accts, pays, sups] = await Promise.all([
        listExpenses(dateFrom || undefined, dateTo || undefined),
        listExpenseCategories(),
        listCashAccounts().catch(() => [] as CashAccount[]),
        listExpensePayments(dateFrom || undefined, dateTo || undefined).catch(() => [] as RestaurantExpensePayment[]),
        listSuppliers().catch(() => [] as RestaurantSupplierRow[]),
      ])
      setExpenses(exp ?? [])
      setPayments(Object.fromEntries((pays ?? []).map((p) => [p.expenseId, p])))
      setSupplierRows((sups ?? []).filter((s) => s.isactive !== false))
      setCategories(cats ?? [])
      setAccounts((accts ?? []).filter((a) => a.isActive))
    } catch (e: any) {
      toast({ title: "Error loading data", description: e?.message ?? "Unknown error", variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { fetchData() }, [])// eslint-disable-line react-hooks/exhaustive-deps

  const handleFilter = () => { fetchData() }

  // Poultry's list filters (app/expenses): a search box and a category, applied
  // in the browser on top of the date range the server already narrowed.
  const gh = useFmt()
  const [search, setSearch] = useState("")
  const [categoryFilter, setCategoryFilter] = useState("all")
  const q = search.trim().toLowerCase()
  const filteredExpenses = expenses.filter((e) =>
    (focusId == null || e.expenseId === focusId)
    && (categoryFilter === "all" || (e.categoryName ?? "Uncategorized") === categoryFilter)
    && (!q || [e.description, e.categoryName, e.supplierName, payments[e.expenseId]?.supplierName, e.receiptRef]
      .join(" ").toLowerCase().includes(q)))
  const filteredTotal = filteredExpenses.reduce((s, e) => s + (e.amount ?? 0), 0)
  const pg = usePagination(filteredExpenses, 25)

  /* ---------- stats ---------- */
  const today = new Date().toISOString().split("T")[0]
  const todayTotal = expenses.filter((e) => e.expenseDate?.startsWith(today)).reduce((s, e) => s + (e.amount ?? 0), 0)
  const monthStr = today.slice(0, 7)
  const monthTotal = expenses.filter((e) => e.expenseDate?.startsWith(monthStr)).reduce((s, e) => s + (e.amount ?? 0), 0)

  const categoryTotals: Record<string, number> = {}
  expenses.forEach((e) => {
    const cat = e.categoryName ?? "Uncategorized"
    categoryTotals[cat] = (categoryTotals[cat] ?? 0) + (e.amount ?? 0)
  })
  const topCategory = Object.entries(categoryTotals).sort((a, b) => b[1] - a[1])[0]?.[0] ?? "-"

  /* ---------- create expense ---------- */
  const handleCreateExpense = async () => {
    if (!expenseForm.description.trim() || !expenseForm.amount) {
      toast({ title: "Validation", description: "Description and amount are required.", variant: "destructive" })
      return
    }
    const paid = amountPaidForStatus(paymentStatus, expenseForm.amount, Number(partPaid || 0))
    if (paymentStatus === "PartiallyPaid" && (!paid || paid <= 0 || paid >= expenseForm.amount)) {
      toast({ title: "Validation", description: "A partially paid expense must have something paid against it, and less than the total.", variant: "destructive" })
      return
    }
    try {
      setSaving(true)
      const input = {
        ...expenseForm,
        amountPaid: paid,
        dueDate: paymentStatus === "Paid" ? null : (expenseForm.dueDate || null),
        cashAccountId: requiresCashAccount(paymentStatus) ? expenseForm.cashAccountId : null,
      }
      if (editingId != null) {
        await updateExpense(editingId, input)
        toast({ title: "Success", description: "Expense updated." })
      } else {
        await createExpense(input)
        toast({ title: "Success", description: "Expense recorded." })
      }
      setEditingId(null)
      setExpenseForm({ ...emptyForm })
      setPaymentStatus("Paid"); setPartPaid("")
      setDialogOpen(false)
      await fetchData()
    } catch (e: any) {
      toast({ title: "Error", description: e?.message ?? (editingId != null ? "Failed to update expense." : "Failed to create expense."), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  /* ---------- edit expense (migration 337) ---------- */
  // Opens the same dialog pre-filled. "Amount paid" is what was paid when the
  // expense was recorded -- supplier payments applied since are separate and
  // are not re-entered here.
  const openEditExpense = (exp: RestaurantExpense) => {
    const p = payments[exp.expenseId]
    const paidAtEntry = p?.paidAtEntry ?? exp.amount
    setExpenseForm({
      expenseDate: (exp.expenseDate ?? "").split("T")[0],
      categoryId: exp.categoryId ?? null,
      description: exp.description ?? "",
      amount: exp.amount ?? 0,
      paymentMethod: exp.paymentMethod || "Cash",
      supplierName: exp.supplierName ?? "",
      receiptRef: exp.receiptRef ?? "",
      cashAccountId: p?.cashAccountId ?? null,
      supplierId: p?.supplierId ?? null,
      amountPaid: paidAtEntry,
      dueDate: p?.dueDate ? String(p.dueDate).split("T")[0] : null,
    })
    const status: SelectablePaymentStatus = paidAtEntry >= (exp.amount ?? 0) ? "Paid" : paidAtEntry > 0 ? "PartiallyPaid" : "Unpaid"
    setPaymentStatus(status); setPartPaid(status === "PartiallyPaid" ? String(paidAtEntry) : "")
    setEditingId(exp.expenseId)
    setDialogOpen(true)
  }

  /* ---------- delete expense ---------- */
  const handleDeleteExpense = async (id: number) => {
    if (!window.confirm("Delete this expense? The money is put back into the account it was paid from.")) return
    try {
      await deleteExpense(id)
      toast({ title: "Deleted", description: "Expense removed and its money returned to the account." })
      await fetchData()
    } catch (e: any) {
      toast({ title: "Error", description: e?.message ?? "Failed to delete.", variant: "destructive" })
    }
  }

  /* ---------- category CRUD ---------- */
  const handleAddCategory = async () => {
    if (!newCategoryName.trim()) return
    try {
      await createExpenseCategory(newCategoryName.trim())
      toast({ title: "Success", description: "Category added." })
      setNewCategoryName("")
      await fetchData()
    } catch (e: any) {
      toast({ title: "Error", description: e?.message ?? "Failed to add category.", variant: "destructive" })
    }
  }

  const handleDeleteCategory = async (id: number) => {
    try {
      await deleteExpenseCategory(id)
      toast({ title: "Deleted", description: "Category removed." })
      await fetchData()
    } catch (e: any) {
      toast({ title: "Error", description: e?.message ?? "Failed to delete category.", variant: "destructive" })
    }
  }

  /* ---------- loading ---------- */
  if (loading) return <PageSkeleton statCards={4} listRows={6} />

  /* ---------- render ---------- */
  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 md:p-6">
          <div className="max-w-7xl mx-auto space-y-6">
            {/* Header */}
            <PageHeader icon={Receipt} title="Expenses" subtitle="Track expenses, categories, and financial overview">
              <Button className="bg-rose-600 hover:bg-rose-700" onClick={() => { setEditingId(null); setExpenseForm({ ...emptyForm }); setPaymentStatus("Paid"); setPartPaid(""); setDialogOpen(true) }}>
                <Plus className="h-4 w-4 mr-2" /> Record Expense
              </Button>
            </PageHeader>

            {/* Summary Cards -- Poultry's (app/expenses): This Month and the
                total of whatever the filters leave. */}
            <div className="grid gap-4 grid-cols-1 md:grid-cols-2">
              <Card className="bg-white">
                <CardHeader className="pb-2"><CardDescription>This Month</CardDescription></CardHeader>
                <CardContent className="min-w-0">
                  <div className="font-bold text-slate-900 leading-tight whitespace-nowrap text-3xl md:text-2xl">{gh(monthTotal)}</div>
                  <p className="mt-1 text-xs text-slate-500">Today {gh(todayTotal)} · Top category {topCategory}</p>
                </CardContent>
              </Card>
              <Card className="bg-white">
                <CardHeader className="pb-2"><CardDescription>Total (Filtered)</CardDescription></CardHeader>
                <CardContent className="min-w-0">
                  <div className="font-bold text-slate-900 leading-tight whitespace-nowrap text-3xl md:text-2xl">{gh(filteredTotal)}</div>
                  <p className="mt-1 text-xs text-slate-500">{filteredExpenses.length} {filteredExpenses.length === 1 ? "expense" : "expenses"}</p>
                </CardContent>
              </Card>
            </div>

            {/* Tabs */}
            <div className="flex gap-2 border-b pb-1">
              {(["expenses", "categories"] as const).map((tab) => (
                <button
                  key={tab}
                  onClick={() => setActiveTab(tab)}
                  className={`px-4 py-2 text-sm font-medium rounded-t-lg transition-colors ${
                    activeTab === tab ? "bg-white border border-b-white -mb-px text-rose-600" : "text-gray-500 hover:text-gray-700"
                  }`}
                >
                  {tab === "expenses" ? "Expenses" : "Categories"}
                </button>
              ))}
            </div>

            {/* Expenses Tab */}
            {activeTab === "expenses" && (
              <>
                {/* Date range filter */}
                <div className="flex flex-wrap items-end gap-3">
                  <div className="space-y-1">
                    <Label className="text-xs text-muted-foreground">From</Label>
                    <Input type="date" className="h-9 w-40" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
                  </div>
                  <div className="space-y-1">
                    <Label className="text-xs text-muted-foreground">To</Label>
                    <Input type="date" className="h-9 w-40" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
                  </div>
                  <Button variant="outline" size="sm" className="h-9" onClick={handleFilter}>
                    <CalendarDays className="h-4 w-4 mr-1" /> Filter
                  </Button>
                  <div className="relative w-full sm:w-64">
                    <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-slate-400" />
                    <Input className="h-9 pl-8" placeholder="Search expenses..." value={search} onChange={(e) => setSearch(e.target.value)} />
                  </div>
                  <Select value={categoryFilter} onValueChange={setCategoryFilter}>
                    <SelectTrigger className="h-9 w-full sm:w-[180px]"><SelectValue placeholder="Category" /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">All categories</SelectItem>
                      {Array.from(new Set(expenses.map((e) => e.categoryName ?? "Uncategorized"))).sort().map((c) => (
                        <SelectItem key={c} value={c}>{c}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  {(search || categoryFilter !== "all") && (
                    <Button variant="ghost" size="sm" className="h-9" onClick={() => { setSearch(""); setCategoryFilter("all") }}>Clear</Button>
                  )}
                </div>

                {expenses.length === 0 ? (
                  <Card>
                    <CardContent className="pt-6">
                      <EmptyState
                        icon={Receipt}
                        title="No expenses recorded yet"
                        description="Track your restaurant's daily expenses and costs"
                        actionLabel="Record First Expense"
                        onAction={() => { setExpenseForm({ ...emptyForm }); setDialogOpen(true) }}
                      />
                    </CardContent>
                  </Card>
                ) : filteredExpenses.length === 0 ? (
                  <Card className="bg-white">
                    <CardContent className="py-12 text-center">
                      <DollarSign className="w-12 h-12 text-slate-400 mx-auto mb-4" />
                      <h3 className="text-lg font-semibold text-slate-900 mb-2">No expenses found</h3>
                      <p className="text-slate-600">No expenses match your search criteria.</p>
                    </CardContent>
                  </Card>
                ) : (
                  <Card className="bg-white overflow-hidden">
                    <CardHeader><CardTitle>Expenses</CardTitle><CardDescription>Manage your restaurant expenses</CardDescription></CardHeader>
                    <CardContent className="p-0">
                      {/* Poultry's phone layout (app/expenses): one expandable card
                          per expense -- date, category chip, amount in red,
                          description; then Payment / Paid to and the actions --
                          with "View table format" for the columns. Desktop keeps
                          the table. */}
                      <MobileCardList
                        items={pg.pageItems}
                        pagination={pg.paginationProps}
                        striped
                        getKey={(e) => e.expenseId}
                        primary={(exp) => (
                          <span className="flex items-center gap-2">
                            <span className="shrink-0">{fmtShortDate(exp.expenseDate)}</span>
                            {exp.categoryName && <Badge className="bg-rose-100 text-rose-700 border-rose-200 hover:bg-rose-100">{exp.categoryName}</Badge>}
                          </span>
                        )}
                        secondary={(exp) => (
                          <span className="flex items-baseline gap-3 min-w-0">
                            <span className="text-lg font-bold text-red-600 shrink-0">{gh(exp.amount ?? 0)}</span>
                            <span className="truncate">{exp.description}</span>
                          </span>
                        )}
                        details={(exp) => {
                          const p = payments[exp.expenseId]
                          return [
                            { label: "Payment", value: exp.paymentMethod || "N/A" },
                            { label: "Paid to", value: p?.supplierName || exp.supplierName || "N/A" },
                            { label: "Status", value: p ? (PAYMENT_STATUS_LABELS[p.paymentStatus as SelectablePaymentStatus] ?? p.paymentStatus) : "—" },
                            { label: "Still owed", value: p && p.balance > 0 ? gh(p.balance) : "—" },
                            ...(exp.receiptRef ? [{ label: "Reference", value: exp.receiptRef }] : []),
                          ]
                        }}
                        actions={(exp) => (
                          <>
                            <Button variant="outline" size="sm" className="flex-1 h-10 bg-white" onClick={() => openEditExpense(exp)}>
                              <Pencil className="h-4 w-4 mr-2" /> Edit
                            </Button>
                            <Button variant="outline" size="sm" className="flex-1 h-10 bg-white text-red-600 border-red-200 hover:bg-red-50"
                                    onClick={() => handleDeleteExpense(exp.expenseId)}>
                              <Trash2 className="h-4 w-4 mr-2" /> Delete
                            </Button>
                          </>
                        )}
                        desktopTable={(
                      <div className="overflow-x-auto">
                        <table className="w-full text-sm min-w-[640px]">
                        <thead className="bg-gray-50 border-b">
                          <tr>
                            <th className="text-left p-3">Date</th>
                            <th className="text-left p-3">Description</th>
                            <th className="text-left p-3">Category</th>
                            <th className="text-left p-3">Supplier / Paid To</th>
                            <th className="text-left p-3">Method</th>
                            <th className="text-left p-3">Status</th>
                            <th className="text-right p-3">Total</th>
                            <th className="text-right p-3">Actions</th>
                          </tr>
                        </thead>
                        <tbody>
                          {pg.pageItems.map((exp) => (
                            <tr key={exp.expenseId} className="border-b hover:bg-rose-50 transition-colors">
                              <td className="p-3 text-xs text-muted-foreground">{exp.expenseDate?.split("T")[0]}</td>
                              <td className="p-3 font-medium text-gray-900">{exp.description}
                                {exp.receiptRef && <div className="text-xs font-normal text-muted-foreground">Ref: {exp.receiptRef}</div>}</td>
                              <td className="p-3">{exp.categoryName ? <Badge variant="secondary" className="text-xs bg-rose-50 text-rose-700 border-rose-200">{exp.categoryName}</Badge> : "—"}</td>
                              <td className="p-3 text-xs">{payments[exp.expenseId]?.supplierName || exp.supplierName || "—"}</td>
                              <td className="p-3">{exp.paymentMethod ? <Badge variant="outline" className="text-xs">{exp.paymentMethod}</Badge> : "—"}</td>
                              <td className="p-3">
                                {payments[exp.expenseId] ? (
                                  <>
                                    <Badge variant="outline" className={`text-xs ${STATUS_BADGE[payments[exp.expenseId].paymentStatus] ?? ""}`}>
                                      {PAYMENT_STATUS_LABELS[payments[exp.expenseId].paymentStatus as SelectablePaymentStatus] ?? payments[exp.expenseId].paymentStatus}
                                    </Badge>
                                    {payments[exp.expenseId].balance > 0 && (
                                      <div className="text-[11px] text-muted-foreground mt-0.5">owed {payments[exp.expenseId].balance.toFixed(2)}</div>
                                    )}
                                  </>
                                ) : "—"}
                              </td>
                              <td className="p-3 text-right font-bold text-red-600">{gh(exp.amount ?? 0)}</td>
                              <td className="p-3 text-right">
                                <Button variant="ghost" size="icon" className="text-gray-400 hover:text-blue-600" title="Edit" onClick={() => openEditExpense(exp)}>
                                  <Pencil className="h-4 w-4" />
                                </Button>
                                <Button variant="ghost" size="icon" className="text-gray-400 hover:text-red-600" title="Delete" onClick={() => handleDeleteExpense(exp.expenseId)}>
                                  <Trash2 className="h-4 w-4" />
                                </Button>
                              </td>
                            </tr>
                          ))}
                        </tbody>
                        </table>
                      </div>
                        )}
                      />
                    </CardContent>
                  </Card>
                )}
              </>
            )}

            {/* Categories Tab */}
            {activeTab === "categories" && (
              <div className="space-y-4">
                {/* Stacks on a phone. The old single flex row put a 320px
                    input next to a ~150px button, so on a 360px screen the
                    button sat off-screen and the input was cut in half --
                    it looked like the form was missing rather than cramped. */}
                <div className="flex flex-col sm:flex-row gap-2">
                  <Input
                    placeholder="New category name"
                    className="w-full sm:max-w-xs h-10"
                    value={newCategoryName}
                    onChange={(e) => setNewCategoryName(e.target.value)}
                    onKeyDown={(e) => { if (e.key === "Enter") handleAddCategory() }}
                  />
                  <Button
                    className="bg-rose-600 hover:bg-rose-700 h-10 w-full sm:w-auto"
                    onClick={handleAddCategory}
                    disabled={!newCategoryName.trim()}
                  >
                    <Plus className="h-4 w-4 mr-1" /> Add Category
                  </Button>
                </div>

                {categories.length === 0 ? (
                  <Card>
                    <CardContent className="pt-6">
                      <EmptyState icon={Tag} title="No categories yet" description="Add expense categories to organise your spending" />
                    </CardContent>
                  </Card>
                ) : (
                  <Card>
                    <CardContent className="p-0 divide-y">
                      {categories.map((cat) => (
                        <div key={cat.expenseCategoryId} className="flex items-center justify-between px-4 py-3 hover:bg-gray-50">
                          <div className="flex items-center gap-2">
                            <Tag className="h-4 w-4 text-rose-500" />
                            <span className="font-medium text-gray-900">{cat.name}</span>
                            {!cat.isActive && <Badge variant="outline" className="text-xs text-gray-400">Inactive</Badge>}
                          </div>
                          <Button variant="ghost" size="icon" className="text-gray-400 hover:text-red-600" onClick={() => handleDeleteCategory(cat.expenseCategoryId)}>
                            <Trash2 className="h-4 w-4" />
                          </Button>
                        </div>
                      ))}
                    </CardContent>
                  </Card>
                )}
              </div>
            )}
          </div>
        </main>
      </div>

      {/* Create Expense Dialog */}
      <Dialog open={dialogOpen} onOpenChange={(o) => { setDialogOpen(o); if (!o) setEditingId(null) }}>
        <DialogContent className="sm:max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{editingId != null ? "Edit Expense" : "Record Expense"}</DialogTitle>
            <DialogDescription>{editingId != null ? "Update expense information" : "Log a business expense"}</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label>Date</Label>
                <Input
                  type="date"
                  className="h-10"
                  value={expenseForm.expenseDate}
                  onChange={(e) => setExpenseForm((f) => ({ ...f, expenseDate: e.target.value }))}
                />
              </div>
              <div className="space-y-1.5">
                <Label>Category</Label>
                <Select
                  value={expenseForm.categoryId?.toString() ?? ""}
                  onValueChange={(v) => setExpenseForm((f) => ({ ...f, categoryId: v ? Number(v) : null }))}
                >
                  <SelectTrigger className="h-10"><SelectValue placeholder="Select category" /></SelectTrigger>
                  <SelectContent>
                    {categories.map((c) => (
                      <SelectItem key={c.expenseCategoryId} value={c.expenseCategoryId.toString()}>
                        {c.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            </div>
            <div className="space-y-1.5">
              <Label>Description <span className="text-rose-500">*</span></Label>
              <Input
                className="h-10"
                placeholder="e.g. Weekly produce from supplier"
                value={expenseForm.description}
                onChange={(e) => setExpenseForm((f) => ({ ...f, description: e.target.value }))}
              />
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label>Amount <span className="text-rose-500">*</span></Label>
                <Input
                  type="number"
                  step="0.01"
                  className="h-10"
                  value={expenseForm.amount || ""}
                  onChange={(e) => setExpenseForm((f) => ({ ...f, amount: parseFloat(e.target.value) || 0 }))}
                />
              </div>
              <div className="space-y-1.5">
                <Label>Payment Method</Label>
                <Select
                  value={expenseForm.paymentMethod ?? "Cash"}
                  onValueChange={(v) => setExpenseForm((f) => ({ ...f, paymentMethod: v }))}
                >
                  <SelectTrigger className="h-10"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {PAYMENT_METHODS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
            </div>
            {requiresCashAccount(paymentStatus) && (
            <div className="space-y-1.5">
              <Label>Paid from</Label>
              <Select
                value={expenseForm.cashAccountId ? String(expenseForm.cashAccountId) : "default"}
                onValueChange={(v) => setExpenseForm((f) => ({ ...f, cashAccountId: v === "default" ? null : Number(v) }))}
              >
                <SelectTrigger className="h-10"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="default">Default account for {expenseForm.paymentMethod ?? "Cash"}</SelectItem>
                  {accounts.map((a) => (
                    <SelectItem key={a.cashAccountId} value={String(a.cashAccountId)}>
                      {a.name} — {a.currentBalance.toFixed(2)}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            )}
            {/* Supplier & Payment Status -- Poultry's band (app/expenses): who
                this is owed to, and how much of it has actually been paid. It
                decides whether the expense shows up on Supplier Balances. */}
            <div className="rounded-xl border border-slate-200 overflow-hidden">
              <div className="bg-sky-600 px-4 py-2 text-sm font-semibold text-white">Supplier &amp; Payment Status</div>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 p-3 bg-white">
                <div className="space-y-1.5 sm:col-span-2">
                  <Label>Supplier / Paid To</Label>
                  <Select
                    value={expenseForm.supplierId ? String(expenseForm.supplierId) : "none"}
                    onValueChange={(v) => {
                      const s = supplierRows.find((x) => String(x.restaurantsupplierid) === v)
                      setExpenseForm((f) => ({ ...f, supplierId: s ? s.restaurantsupplierid : null, supplierName: s ? s.name : f.supplierName }))
                    }}
                  >
                    <SelectTrigger className="h-10"><SelectValue placeholder="Not linked to a supplier" /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="none">Not linked to a supplier</SelectItem>
                      {supplierRows.map((s) => (
                        <SelectItem key={s.restaurantsupplierid} value={String(s.restaurantsupplierid)}>{s.name}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-1.5">
                  <Label>Payment Status *</Label>
                  <Select value={paymentStatus} onValueChange={(v) => setPaymentStatus(v as SelectablePaymentStatus)}>
                    <SelectTrigger className="h-10"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {SELECTABLE_PAYMENT_STATUSES.map((st) => (
                        <SelectItem key={st} value={st}>{PAYMENT_STATUS_LABELS[st]}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-1.5">
                  <Label>Amount Paid {paymentStatus === "PartiallyPaid" ? "*" : ""}</Label>
                  <Input
                    type="number" step="0.01" min="0" className="h-10"
                    value={paymentStatus === "PartiallyPaid" ? partPaid : (paymentStatus === "Paid" ? String(expenseForm.amount || "") : "0")}
                    onChange={(e) => setPartPaid(e.target.value)}
                    disabled={paymentStatus !== "PartiallyPaid"}
                  />
                </div>
                <div className="space-y-1.5">
                  <Label>Due Date</Label>
                  <Input
                    type="date" className="h-10"
                    value={expenseForm.dueDate ?? ""}
                    onChange={(e) => setExpenseForm((f) => ({ ...f, dueDate: e.target.value || null }))}
                    disabled={paymentStatus === "Paid"}
                  />
                </div>
                {paymentStatus !== "Paid" && !expenseForm.supplierId && (
                  <p className="sm:col-span-2 text-xs text-amber-700">
                    Select a supplier if you want this unpaid expense to appear in Supplier Balances.
                  </p>
                )}
              </div>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label>Supplier (name only)</Label>
                <Input
                  className="h-10"
                  placeholder="If not in the supplier list (optional)"
                  value={expenseForm.supplierName ?? ""}
                  disabled={!!expenseForm.supplierId}
                  onChange={(e) => setExpenseForm((f) => ({ ...f, supplierName: e.target.value }))}
                />
              </div>
              <div className="space-y-1.5">
                <Label>Receipt / reference</Label>
                <Input
                  className="h-10"
                  placeholder="Receipt or invoice no. (optional)"
                  value={expenseForm.receiptRef ?? ""}
                  onChange={(e) => setExpenseForm((f) => ({ ...f, receiptRef: e.target.value }))}
                />
              </div>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialogOpen(false)}>Cancel</Button>
            <Button className="bg-rose-600 hover:bg-rose-700" onClick={handleCreateExpense} disabled={saving}>
              {saving ? "Saving..." : editingId != null ? "Save Changes" : "Record Expense"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

/** "Sep 28, 26" -- Poultry's short card date, read off the yyyy-mm-dd string so no time zone can move it. */
function fmtShortDate(d?: string | null): string {
  const [y, m, day] = (d ?? "").split("T")[0].split("-")
  if (!y || !m || !day) return d ?? "—"
  const mon = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][Number(m) - 1] ?? m
  return `${mon} ${Number(day)}, ${y.slice(2)}`
}
