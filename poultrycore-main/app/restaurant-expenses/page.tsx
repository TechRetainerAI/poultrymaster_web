"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Plus, Receipt, DollarSign, TrendingDown, Tag, Trash2, CalendarDays } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { StatCard } from "@/components/restaurant/stat-card"
import { EmptyState } from "@/components/restaurant/empty-state"
import { PageHeader } from "@/components/restaurant/page-header"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import {
  listExpenses, createExpense, deleteExpense,
  listExpenseCategories, createExpenseCategory, deleteExpenseCategory,
  type RestaurantExpense, type RestaurantExpenseInput, type ExpenseCategory,
} from "@/lib/api/restaurant"

const PAYMENT_METHODS = ["Cash", "Card", "Bank Transfer", "MobileMoney", "Cheque"]

const emptyForm: RestaurantExpenseInput = {
  expenseDate: new Date().toISOString().split("T")[0],
  categoryId: null,
  description: "",
  amount: 0,
  paymentMethod: "Cash",
  supplierName: "",
  receiptRef: "",
}

export default function RestaurantExpensesPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [loading, setLoading] = useState(true)
  const [expenses, setExpenses] = useState<RestaurantExpense[]>([])
  const [categories, setCategories] = useState<ExpenseCategory[]>([])
  const [activeTab, setActiveTab] = useState<"expenses" | "categories">("expenses")
  const [dialogOpen, setDialogOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [expenseForm, setExpenseForm] = useState<RestaurantExpenseInput>({ ...emptyForm })
  const [newCategoryName, setNewCategoryName] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
  }, [activeFarmType, router])

  const fetchData = async () => {
    try {
      setLoading(true)
      const [exp, cats] = await Promise.all([
        listExpenses(dateFrom || undefined, dateTo || undefined),
        listExpenseCategories(),
      ])
      setExpenses(exp ?? [])
      setCategories(cats ?? [])
    } catch (e: any) {
      toast({ title: "Error loading data", description: e?.message ?? "Unknown error", variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { fetchData() }, [])// eslint-disable-line react-hooks/exhaustive-deps

  const handleFilter = () => { fetchData() }

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
    try {
      setSaving(true)
      await createExpense(expenseForm)
      toast({ title: "Success", description: "Expense recorded." })
      setExpenseForm({ ...emptyForm })
      setDialogOpen(false)
      await fetchData()
    } catch (e: any) {
      toast({ title: "Error", description: e?.message ?? "Failed to create expense.", variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  /* ---------- delete expense ---------- */
  const handleDeleteExpense = async (id: number) => {
    try {
      await deleteExpense(id)
      toast({ title: "Deleted", description: "Expense removed." })
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
            <PageHeader icon={Receipt} title="Expenses & Accounting" subtitle="Track expenses, categories, and financial overview">
              <Button className="bg-rose-600 hover:bg-rose-700" onClick={() => { setExpenseForm({ ...emptyForm }); setDialogOpen(true) }}>
                <Plus className="h-4 w-4 mr-2" /> Record Expense
              </Button>
            </PageHeader>

            {/* Stats Row */}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <StatCard label="Today's Total" value={`${todayTotal.toFixed(2)}`} icon={TrendingDown} color="red" />
              <StatCard label="This Month" value={`${monthTotal.toFixed(2)}`} icon={DollarSign} color="amber" />
              <StatCard label="Total Records" value={expenses.length} icon={Receipt} color="blue" />
              <StatCard label="Top Category" value={topCategory} icon={Tag} color="purple" />
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
                ) : (
                  <Card>
                    <CardContent className="p-0">
                      <table className="w-full text-sm">
                        <thead className="bg-gray-50 border-b">
                          <tr>
                            <th className="text-left p-3">Date</th>
                            <th className="text-left p-3">Description</th>
                            <th className="text-left p-3">Category</th>
                            <th className="text-left p-3">Supplier</th>
                            <th className="text-left p-3">Payment</th>
                            <th className="text-right p-3">Amount</th>
                            <th className="text-right p-3">Actions</th>
                          </tr>
                        </thead>
                        <tbody>
                          {expenses.map((exp) => (
                            <tr key={exp.expenseId} className="border-b hover:bg-rose-50 transition-colors">
                              <td className="p-3 text-xs text-muted-foreground">{exp.expenseDate?.split("T")[0]}</td>
                              <td className="p-3 font-medium text-gray-900">{exp.description}</td>
                              <td className="p-3">{exp.categoryName ? <Badge variant="secondary" className="text-xs bg-rose-50 text-rose-700 border-rose-200">{exp.categoryName}</Badge> : "—"}</td>
                              <td className="p-3 text-xs">{exp.supplierName || "—"}</td>
                              <td className="p-3">{exp.paymentMethod ? <Badge variant="outline" className="text-xs">{exp.paymentMethod}</Badge> : "—"}</td>
                              <td className="p-3 text-right font-bold text-red-600">{(exp.amount ?? 0).toFixed(2)}</td>
                              <td className="p-3 text-right">
                                <Button variant="ghost" size="icon" className="text-gray-400 hover:text-red-600" onClick={() => handleDeleteExpense(exp.expenseId)}>
                                  <Trash2 className="h-4 w-4" />
                                </Button>
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </CardContent>
                  </Card>
                )}
              </>
            )}

            {/* Categories Tab */}
            {activeTab === "categories" && (
              <div className="space-y-4">
                <div className="flex gap-2">
                  <Input
                    placeholder="New category name"
                    className="max-w-xs h-9"
                    value={newCategoryName}
                    onChange={(e) => setNewCategoryName(e.target.value)}
                    onKeyDown={(e) => { if (e.key === "Enter") handleAddCategory() }}
                  />
                  <Button className="bg-rose-600 hover:bg-rose-700 h-9" onClick={handleAddCategory}>
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
      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Record Expense</DialogTitle>
            <DialogDescription>Log a business expense</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-3">
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
            <div className="grid grid-cols-2 gap-3">
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
            <div className="space-y-1.5">
              <Label>Supplier</Label>
              <Input
                className="h-10"
                placeholder="Supplier name (optional)"
                value={expenseForm.supplierName ?? ""}
                onChange={(e) => setExpenseForm((f) => ({ ...f, supplierName: e.target.value }))}
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDialogOpen(false)}>Cancel</Button>
            <Button className="bg-rose-600 hover:bg-rose-700" onClick={handleCreateExpense} disabled={saving}>
              {saving ? "Saving..." : "Record Expense"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
