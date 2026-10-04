"use client"
import { useEffect, useState, useMemo } from "react"
import { useRouter } from "next/navigation"
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
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { listHotelSuppliers, type HotelSupplier } from "@/lib/api/hotel-suppliers"
import { Loader2, Wallet, Plus, Tag, Pencil, Trash2, Receipt, DollarSign, Search, Filter, Calendar } from "lucide-react"
import { useIsMobile } from "@/hooks/use-mobile"
import { Sheet, SheetContent, SheetTrigger } from "@/components/ui/sheet"
import {
  MOBILE_FILTER_SHEET_CONTENT_CLASS, MOBILE_FILTER_SELECT_CONTENT_CLASS, MOBILE_FILTERS_TOOLBAR_ROW_CLASS,
  MOBILE_FILTERS_TRIGGER_BUTTON_CLASS, MobileFilterSheetBody, MobileFilterSheetFooter, MobileFilterSheetHeader,
} from "@/components/dashboard/mobile-filters"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listHotelExpenses, createHotelExpense, updateHotelExpense, cancelHotelExpense,
  listHotelExpenseCategories, createHotelExpenseCategory,
  listHotelCashAccounts,
  type HotelExpense, type HotelExpenseCategory, type HotelCashAccount,
} from "@/lib/api/hotel"

function todayLocal(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
}

export default function HotelExpensesPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [expenses, setExpenses] = useState<HotelExpense[]>([])
  const [categories, setCategories] = useState<HotelExpenseCategory[]>([])
  const [accounts, setAccounts] = useState<HotelCashAccount[]>([])
  const [suppliers, setSuppliers] = useState<HotelSupplier[]>([])
  const [loading, setLoading] = useState(true)

  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const isMobile = useIsMobile()
  const [filtersOpen, setFiltersOpen] = useState(false)
  const [draft, setDraft] = useState({ from: "", to: "", category: "all" })

  const [open, setOpen] = useState(false); const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({ category: "", description: "", amount: 0, expenseDate: "", vendor: "", notes: "", paymentMethod: "Cash", hotelCashAccountId: null as number | null, paidTo: "", hotelExpenseCategoryId: null as number | null, hotelSupplierId: null as number | null })

  const [catDlg, setCatDlg] = useState(false); const [newCatName, setNewCatName] = useState("")
  const [editingId, setEditingId] = useState<number | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<any>(null)

  useEffect(() => {
    if (!activeFarmType) return
    if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    load()
  }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try {
      const [es, cs, accs] = await Promise.all([listHotelExpenses(), listHotelExpenseCategories(), listHotelCashAccounts()])
      setExpenses(es); setCategories(cs); setAccounts(accs)
      listHotelSuppliers().then((s) => setSuppliers(s.filter((x: any) => x.isActive !== false))).catch(() => setSuppliers([]))
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openNew() {
    const firstCat = categories.find((c: any) => c.isActive ?? c.isactive ?? true) as any
    setForm({
      category: firstCat?.name ?? "", description: "", amount: 0, expenseDate: todayLocal(),
      vendor: "", notes: "", paymentMethod: "Cash", hotelCashAccountId: null, paidTo: "",
      hotelExpenseCategoryId: firstCat?.hotelExpenseCategoryId ?? firstCat?.hotelexpensecategoryid ?? null,
      hotelSupplierId: null,
    })
    setEditingId(null)
    setOpen(true)
  }

  // Poultry's Edit Expense: the same dialog, filled from the row.
  function openEdit(e: any) {
    setForm({
      category: e.category ?? "", description: e.description ?? "", amount: Number(e.amount ?? 0),
      expenseDate: String(e.expenseDate ?? e.expensedate ?? "").slice(0, 10), vendor: e.vendor ?? "", notes: e.notes ?? "",
      paymentMethod: e.paymentMethod ?? e.paymentmethod ?? "Cash", hotelCashAccountId: e.hotelCashAccountId ?? e.hotelcashaccountid ?? null,
      paidTo: e.paidTo ?? e.paidto ?? "", hotelExpenseCategoryId: e.hotelExpenseCategoryId ?? e.hotelexpensecategoryid ?? null,
      hotelSupplierId: e.hotelSupplierId ?? e.hotelsupplierid ?? null,
    })
    setEditingId(e.hotelExpenseId ?? e.hotelexpenseid)
    setOpen(true)
  }

  async function save() {
    if (!form.description.trim()) { toast({ title: "Description required", variant: "destructive" }); return }
    if (form.amount <= 0) { toast({ title: "Amount must be > 0", variant: "destructive" }); return }
    if (form.paymentMethod !== "Credit" && !form.hotelCashAccountId) { toast({ title: "Select a cash account", variant: "destructive" }); return }
    // Poultry: an expense not paid now is owed to someone -- it needs a supplier
    // to appear on Supplier Balances (migration 332).
    if (form.paymentMethod === "Credit" && !form.hotelSupplierId) { toast({ title: "Choose the supplier this expense is owed to", variant: "destructive" }); return }
    setSaving(true)
    try {
      // Like Poultry, the money moves when the expense is saved.
      if (editingId != null) await updateHotelExpense(editingId, form)
      else await createHotelExpense({ ...form, postNow: true })
      toast({ title: editingId != null ? "Expense updated" : "Expense recorded" })
      setOpen(false); await load()
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  // Poultry's Delete. The row is cancelled rather than erased, so an expense
  // that was paid gives its money back to the account as a reversal.
  async function confirmDelete() {
    if (!deleteTarget) return
    const id = deleteTarget.hotelExpenseId ?? deleteTarget.hotelexpenseid
    try {
      await cancelHotelExpense(id, "Deleted")
      toast({ title: "Expense deleted" })
      setDeleteTarget(null); await load()
    } catch (e: any) { toast({ title: "Delete failed", description: e?.message, variant: "destructive" }) }
  }

  async function addCategory() {
    if (!newCatName.trim()) return
    try {
      await createHotelExpenseCategory({ name: newCatName.trim() })
      setNewCatName(""); setCatDlg(false); await load()
      toast({ title: "Category added" })
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  // ?expenseId= (from Supplier Balances / Payments) narrows the list to one bill.
  const [focusId, setFocusId] = useState<number | null>(null)
  useEffect(() => {
    if (typeof window === "undefined") return
    const v = new URLSearchParams(window.location.search).get("expenseId")
    if (v) setFocusId(Number(v) || null)
  }, [])

  // Poultry's list filters (app/expenses): search and category, plus the Hotel's
  // approval status and dates, applied in the browser.
  const [categoryFilter, setCategoryFilter] = useState("all")
  const filtered = useMemo(() => {
    return expenses.filter((e: any) => {
      const id = e.hotelExpenseId ?? e.hotelexpenseid
      if (focusId != null && id !== focusId) return false
      // Deleted (and edited-away) expenses are kept as Cancelled rows; Poultry's list doesn't show them.
      if ((e.status ?? e.Status) === "Cancelled") return false
      if (categoryFilter !== "all" && (e.category || "Uncategorized") !== categoryFilter) return false
      const d = (e.expenseDate ?? e.expensedate ?? "").slice(0, 10)
      if (dateFrom && d < dateFrom) return false
      if (dateTo && d > dateTo) return false
      if (search) {
        const q = search.toLowerCase()
        const hay = [e.category, e.description, e.vendor, e.paidTo ?? e.paidto, e.notes].filter(Boolean).join(" ").toLowerCase()
        if (!hay.includes(q)) return false
      }
      return true
    })
  }, [expenses, categoryFilter, dateFrom, dateTo, search, focusId])

  const fmt = useFmt()
  const pg = usePagination(filtered, 25)
  // Poultry's two cards (app/expenses): This Month and the total of whatever the
  // filters leave. A cancelled expense is not spending, so it is left out.
  const live = (e: any) => (e.status ?? "Draft") !== "Cancelled"
  const todayStr = todayLocal()
  const monthStr = todayStr.slice(0, 7)
  const dateOf = (e: any) => String(e.expenseDate ?? e.expensedate ?? "").slice(0, 10)
  const monthTotal = expenses.filter((e: any) => live(e) && dateOf(e).startsWith(monthStr)).reduce((s: number, e: any) => s + Number(e.amount ?? 0), 0)
  const filteredTotal = filtered.filter(live).reduce((s: number, e: any) => s + Number(e.amount ?? 0), 0)
  const categoryOptions = Array.from(new Set(expenses.filter(live).map((e: any) => e.category || "Uncategorized"))).sort() as string[]
  const activeFilterCount = [dateFrom, dateTo, categoryFilter !== "all" ? "x" : ""].filter(Boolean).length
  const clearFilters = () => { setSearch(""); setCategoryFilter("all"); setDateFrom(""); setDateTo(""); setFocusId(null) }

  // Poultry's buttons (app/expenses): Edit and Delete, on phone cards and desktop rows.
  const rowButtons = (e: any, compact: boolean) => compact ? (
    <>
      <Button variant="ghost" size="sm" className="h-8 w-8 p-0" onClick={() => openEdit(e)} title="Edit"><Pencil className="w-4 h-4" /></Button>
      <Button variant="ghost" size="sm" className="h-8 w-8 p-0 text-red-600 hover:text-red-700 hover:bg-red-50" onClick={() => setDeleteTarget(e)} title="Delete"><Trash2 className="w-4 h-4" /></Button>
    </>
  ) : (
    <>
      <Button variant="outline" size="sm" className="flex-1 h-10" onClick={() => openEdit(e)}><Pencil className="h-4 w-4 mr-2" /> Edit</Button>
      <Button variant="outline" size="sm" className="flex-1 h-10 text-red-600 border-red-200 hover:bg-red-50" onClick={() => setDeleteTarget(e)}><Trash2 className="h-4 w-4 mr-2" /> Delete</Button>
    </>
  )

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-y-auto p-4 md:p-6">
        <div className="max-w-7xl mx-auto space-y-6">
          {/* Header -- Poultry's (app/expenses): title left, Add Expense right. */}
          <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
            <div className="flex items-start gap-3 min-w-0">
              <div className="w-10 h-10 shrink-0 bg-violet-100 rounded-lg flex items-center justify-center">
                <DollarSign className="w-5 h-5 text-violet-600" />
              </div>
              <div className="min-w-0">
                <h1 className="text-xl sm:text-2xl font-bold text-slate-900 truncate">Expenses</h1>
                <p className="text-sm text-slate-600">Track operational costs and financial records</p>
              </div>
            </div>
            <div className="flex gap-2 w-full sm:w-auto shrink-0">
              <Button variant="outline" className="h-11 sm:h-10 flex-1 sm:flex-none" onClick={() => setCatDlg(true)}><Tag className="h-4 w-4 mr-2" /> Categories</Button>
              <Button className="gap-2 h-11 sm:h-10 flex-1 sm:flex-none bg-violet-600 hover:bg-violet-700" onClick={openNew}>
                <Plus className="w-4 h-4" /> Add Expense
              </Button>
            </div>
          </div>

          {focusId != null && (
            <div className="flex flex-wrap items-center gap-3 rounded-lg border border-violet-200 bg-violet-50 px-4 py-2 text-sm text-violet-900">
              <span>Showing expense #{focusId} only.</span>
              <Button variant="outline" size="sm" className="h-8" onClick={() => setFocusId(null)}>Show all expenses</Button>
            </div>
          )}

          {/* Filters -- Poultry's: search, then a Filters sheet on phones; one bar on desktop.
              The Hotel's approval status lives here too. */}
          {isMobile ? (
            <div className="space-y-3 w-full min-w-0">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                <Input placeholder="Search expenses..." value={search} onChange={(e) => setSearch(e.target.value)} className="pl-10 h-11" />
              </div>
              <div className={MOBILE_FILTERS_TOOLBAR_ROW_CLASS}>
                <Sheet open={filtersOpen} onOpenChange={(o) => { setFiltersOpen(o); setDraft({ from: dateFrom, to: dateTo, category: categoryFilter }) }}>
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
                            <label htmlFor="hexp-from" className="text-xs font-medium text-slate-500">Start date</label>
                            <Input id="hexp-from" type="date" value={draft.from} onChange={(e) => setDraft({ ...draft, from: e.target.value })} className="h-12 w-full min-w-0 text-base" />
                          </div>
                          <div className="min-w-0 space-y-2">
                            <label htmlFor="hexp-to" className="text-xs font-medium text-slate-500">End date</label>
                            <Input id="hexp-to" type="date" value={draft.to} onChange={(e) => setDraft({ ...draft, to: e.target.value })} className="h-12 w-full min-w-0 text-base" />
                          </div>
                        </div>
                      </div>
                      <div className="space-y-2">
                        <label className="text-sm font-medium text-slate-700">Category</label>
                        <Select value={draft.category} onValueChange={(v) => setDraft({ ...draft, category: v })}>
                          <SelectTrigger className="h-12 text-base"><SelectValue /></SelectTrigger>
                          <SelectContent className={MOBILE_FILTER_SELECT_CONTENT_CLASS}>
                            <SelectItem value="all">All categories</SelectItem>
                            {categoryOptions.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}
                          </SelectContent>
                        </Select>
                      </div>
                    </MobileFilterSheetBody>
                    <MobileFilterSheetFooter>
                      <div className="flex gap-3">
                        <Button type="button" variant="outline" className="h-12 flex-1" onClick={() => { clearFilters(); setFiltersOpen(false); toast({ title: "Filters cleared" }) }}>Clear all</Button>
                        <Button type="button" className="h-12 flex-1" onClick={() => { setDateFrom(draft.from); setDateTo(draft.to); setCategoryFilter(draft.category); setFiltersOpen(false) }}>Apply</Button>
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
                <Input placeholder="Search..." value={search} onChange={(e) => setSearch(e.target.value)} className="pl-9" />
              </div>
              <div className="relative w-full sm:w-[140px]">
                <Calendar className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                <Input type="date" aria-label="From" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} className="pl-9" />
              </div>
              <div className="relative w-full sm:w-[140px]">
                <Calendar className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                <Input type="date" aria-label="To" value={dateTo} onChange={(e) => setDateTo(e.target.value)} className="pl-9" />
              </div>
              <Select value={categoryFilter} onValueChange={setCategoryFilter}>
                <SelectTrigger className="w-[180px]"><SelectValue placeholder="Category" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All Category</SelectItem>
                  {categoryOptions.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}
                </SelectContent>
              </Select>
              {activeFilterCount > 0 && (
                <Button variant="ghost" size="sm" onClick={clearFilters}>Clear ({activeFilterCount})</Button>
              )}
            </div>
          )}

          {/* Summary Cards -- Poultry's (app/expenses). */}
          <div className="grid gap-4 grid-cols-1 md:grid-cols-2">
            <Card className="bg-white">
              <CardHeader className="pb-2"><CardDescription>This Month</CardDescription></CardHeader>
              <CardContent className="min-w-0">
                <div className="font-bold text-slate-900 leading-tight whitespace-nowrap text-3xl md:text-2xl">{fmt(monthTotal)}</div>
              </CardContent>
            </Card>
            <Card className="bg-white">
              <CardHeader className="pb-2"><CardDescription>Total (Filtered)</CardDescription></CardHeader>
              <CardContent className="min-w-0">
                <div className="font-bold text-slate-900 leading-tight whitespace-nowrap text-3xl md:text-2xl">{fmt(filteredTotal)}</div>
              </CardContent>
            </Card>
          </div>

          {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div>
          : !expenses.some(live) ? (
            <Card className="bg-white">
              <CardContent className="py-12 text-center">
                <Receipt className="w-12 h-12 text-slate-400 mx-auto mb-4" />
                <h3 className="text-lg font-semibold text-slate-900 mb-2">No expenses recorded yet</h3>
                <p className="text-slate-600 mb-4">Track your hotel's daily expenses and costs</p>
                <Button onClick={openNew} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-2" /> Record First Expense</Button>
              </CardContent>
            </Card>
          ) : filtered.length === 0 ? (
            <Card className="bg-white">
              <CardContent className="py-12 text-center">
                <DollarSign className="w-12 h-12 text-slate-400 mx-auto mb-4" />
                <h3 className="text-lg font-semibold text-slate-900 mb-2">No expenses found</h3>
                <p className="text-slate-600">No expenses match your search criteria.</p>
              </CardContent>
            </Card>
          ) : (
            <Card className="bg-white overflow-hidden">
              <CardHeader><CardTitle>Expenses</CardTitle><CardDescription>Manage your hotel expenses</CardDescription></CardHeader>
              <CardContent className="p-0">
                {/* Poultry's phone layout (app/expenses): one expandable card per
                    expense, with "View table format" for the columns. */}
                <MobileCardList
                  items={pg.pageItems}
                  pagination={{ ...pg.paginationProps, variant: "records" }}
                  striped
                  getKey={(e: any) => e.hotelExpenseId ?? e.hotelexpenseid}
                  primary={(e: any) => (
                    <span className="flex items-center gap-2">
                      <span className="shrink-0">{fmtShortDate(dateOf(e))}</span>
                      {e.category && <Badge className="bg-violet-100 text-violet-700 border-violet-200 hover:bg-violet-100">{e.category}</Badge>}
                    </span>
                  )}
                  secondary={(e: any) => (
                    <span className="flex items-baseline gap-3 min-w-0">
                      <span className="text-lg font-bold text-red-600 shrink-0">{fmt(Number(e.amount ?? 0))}</span>
                      <span className="truncate">{e.description}</span>
                    </span>
                  )}
                  details={(e: any) => {
                    const acct = accounts.find((a: any) => (a.hotelCashAccountId ?? a.hotelcashaccountid) === (e.hotelCashAccountId ?? e.hotelcashaccountid))
                    return [
                      { label: "Payment", value: e.paymentMethod ?? e.paymentmethod ?? "Cash" },
                      { label: "Paid to", value: e.paidTo ?? e.paidto ?? e.vendor ?? "N/A" },
                      // Drafts from before saving posted straight away: Edit posts them.
                      ...((e.status ?? "Draft") !== "Approved" ? [{ label: "Status", value: "Not posted (Edit to post)" }] : []),
                      { label: "Account", value: (acct as any)?.accountName ?? (acct as any)?.accountname ?? "—" },
                      ...(e.notes ? [{ label: "Notes", value: e.notes }] : []),
                    ]
                  }}
                  actions={(e: any) => rowButtons(e, false)}
                  desktopTable={(
                    <div className="overflow-x-auto">
                      <table className="w-full text-sm min-w-[760px]">
                        <thead className="bg-slate-50 border-b"><tr>
                          <th className="text-left p-3">Date</th>
                          <th className="text-left p-3">Description</th>
                          <th className="text-left p-3">Category</th>
                          <th className="text-left p-3">Supplier / Paid To</th>
                          <th className="text-left p-3">Method</th>
                          <th className="text-left p-3">Account</th>
                          <th className="text-right p-3">Total</th>
                          <th className="text-right p-3">Actions</th>
                        </tr></thead>
                        <tbody>
                          {pg.pageItems.map((e: any) => {
                            const id = e.hotelExpenseId ?? e.hotelexpenseid
                            const acct = accounts.find((a: any) => (a.hotelCashAccountId ?? a.hotelcashaccountid) === (e.hotelCashAccountId ?? e.hotelcashaccountid))
                            return (
                              <tr key={id} className="border-b hover:bg-violet-50 transition-colors">
                                <td className="p-3 text-xs text-muted-foreground whitespace-nowrap">{dateOf(e)}</td>
                                <td className="p-3 font-medium text-gray-900 max-w-[220px] truncate">{e.description}</td>
                                <td className="p-3">{e.category ? <Badge variant="secondary" className="text-xs bg-violet-50 text-violet-700 border-violet-200">{e.category}</Badge> : "—"}</td>
                                <td className="p-3 text-xs">{e.paidTo ?? e.paidto ?? e.vendor ?? "—"}</td>
                                <td className="p-3"><Badge variant="outline" className="text-xs">{e.paymentMethod ?? e.paymentmethod ?? "Cash"}</Badge></td>
                                <td className="p-3 text-xs">{(acct as any)?.accountName ?? (acct as any)?.accountname ?? "—"}</td>
                                <td className="p-3 text-right font-bold text-red-600">{fmt(Number(e.amount ?? 0))}</td>
                                <td className="p-3 text-right whitespace-nowrap">{rowButtons(e, true)}</td>
                              </tr>
                            )
                          })}
                        </tbody>
                      </table>
                    </div>
                  )}
                />
              </CardContent>
            </Card>
          )}
        </div>

        {/* Create Expense Dialog */}
        <Dialog open={open} onOpenChange={setOpen}>
          <DialogContent className="sm:max-w-lg max-h-[90vh] overflow-y-auto">
            <DialogHeader>
              <DialogTitle className="flex items-center gap-2">{editingId != null ? <Pencil className="h-5 w-5 text-violet-600" /> : <Wallet className="h-5 w-5 text-violet-600" />} {editingId != null ? "Edit Expense" : "Add Expense"}</DialogTitle>
              <DialogDescription>{editingId != null ? "Update the expense. The money moves to match." : "The money leaves the chosen account when you save."}</DialogDescription>
            </DialogHeader>
            <div className="space-y-4">
              <FormSection title="Expense Details" color="indigo" columns={1}>
                <FormField label="Expense date *">
                  <Input type="date" value={form.expenseDate} max={todayLocal()} onChange={(e) => setForm({ ...form, expenseDate: e.target.value })} />
                </FormField>
                <FormField label="Category *">
                  <Select value={form.hotelExpenseCategoryId ? String(form.hotelExpenseCategoryId) : undefined} onValueChange={(v) => {
                    const cat = categories.find((c: any) => (c.hotelExpenseCategoryId ?? c.hotelexpensecategoryid) === Number(v))
                    setForm({ ...form, hotelExpenseCategoryId: Number(v), category: (cat as any)?.name ?? "" })
                  }}>
                    <SelectTrigger><SelectValue placeholder="Pick category" /></SelectTrigger>
                    <SelectContent>
                      {categories.filter((c: any) => c.isActive ?? c.isactive ?? true).map((c: any) => <SelectItem key={c.hotelExpenseCategoryId ?? c.hotelexpensecategoryid} value={String(c.hotelExpenseCategoryId ?? c.hotelexpensecategoryid)}>{c.name}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </FormField>
                <FormField label="Description *">
                  <Input value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} placeholder="e.g. Laundry detergent" />
                </FormField>
              </FormSection>

              <FormSection title="Payment" color="amber">
                <FormField label="Amount *">
                  <Input type="number" min={0} step="0.01" value={form.amount || ""} onChange={(e) => setForm({ ...form, amount: Number(e.target.value) || 0 })} />
                </FormField>
                <FormField label="Payment method">
                  <Select value={form.paymentMethod} onValueChange={(v) => setForm({ ...form, paymentMethod: v })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="Cash">Cash</SelectItem>
                      <SelectItem value="MobileMoney">Mobile Money</SelectItem>
                      <SelectItem value="Bank">Bank Transfer</SelectItem>
                      <SelectItem value="Card">Card</SelectItem>
                      <SelectItem value="Credit">Credit (no cash account)</SelectItem>
                    </SelectContent>
                  </Select>
                </FormField>
                {form.paymentMethod !== "Credit" && (
                  <FormField label="Cash account (debit from) *" full>
                    <Select value={form.hotelCashAccountId ? String(form.hotelCashAccountId) : undefined} onValueChange={(v) => setForm({ ...form, hotelCashAccountId: Number(v) })}>
                      <SelectTrigger><SelectValue placeholder="Pick account to debit" /></SelectTrigger>
                      <SelectContent>
                        {accounts.filter((a: any) => a.isActive ?? a.isactive ?? true).map((a: any) => {
                          const purpose = a.purpose ?? null
                          const purposeLabel = purpose === "FrontDesk" ? " [Front Desk]" : purpose === "Expenses" ? " [Expenses]" : purpose === "POS" ? " [POS]" : purpose === "Payroll" ? " [Payroll]" : ""
                          return (
                            <SelectItem key={a.hotelCashAccountId ?? a.hotelcashaccountid} value={String(a.hotelCashAccountId ?? a.hotelcashaccountid)}>
                              {a.accountName ?? a.accountname}{purposeLabel} — Bal: {Number(a.currentBalance ?? a.currentbalance ?? 0).toFixed(2)}
                            </SelectItem>
                          )
                        })}
                      </SelectContent>
                    </Select>
                  </FormField>
                )}
              </FormSection>

              <FormSection title="Details" color="slate" columns={1}>
                <FormField label={form.paymentMethod === "Credit" ? "Supplier *" : "Supplier"}>
                  <Select
                    value={form.hotelSupplierId ? String(form.hotelSupplierId) : "none"}
                    onValueChange={(v) => {
                      const s = suppliers.find((x) => String(x.hotelSupplierId) === v)
                      setForm({ ...form, hotelSupplierId: s ? s.hotelSupplierId : null, paidTo: s ? s.supplierName : form.paidTo })
                    }}
                  >
                    <SelectTrigger><SelectValue placeholder="Select a supplier" /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="none">None</SelectItem>
                      {suppliers.map((s) => <SelectItem key={s.hotelSupplierId} value={String(s.hotelSupplierId)}>{s.supplierName}</SelectItem>)}
                    </SelectContent>
                  </Select>
                  {form.paymentMethod === "Credit" && <p className="mt-1 text-xs text-slate-500">This bill appears on Supplier Balances.</p>}
                </FormField>
                <FormField label="Paid to / Vendor">
                  <Input value={form.paidTo} onChange={(e) => setForm({ ...form, paidTo: e.target.value })} placeholder="Supplier name" />
                </FormField>
                <FormField label="Notes">
                  <Textarea value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} />
                </FormField>
              </FormSection>

              <div className="flex gap-3 justify-end pt-2">
                <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
                <Button onClick={save} disabled={saving} className="bg-violet-600 hover:bg-violet-700">
                  {saving ? <><Loader2 className="h-4 w-4 mr-1 animate-spin" />Saving...</> : editingId != null ? "Save changes" : "Save Expense"}
                </Button>
              </div>
            </div>
          </DialogContent>
        </Dialog>

        {/* Categories Dialog */}
        <Dialog open={catDlg} onOpenChange={setCatDlg}>
          <DialogContent className="sm:max-w-lg max-h-[90vh] overflow-y-auto">
            <DialogHeader>
              <DialogTitle className="flex items-center gap-2"><Tag className="h-5 w-5 text-violet-600" /> Expense Categories</DialogTitle>
              <DialogDescription>Manage categories for hotel expenses</DialogDescription>
            </DialogHeader>
            <div className="space-y-4">
              <div className="space-y-2 max-h-64 overflow-auto">
                {categories.map((c: any) => (
                  <div key={c.hotelExpenseCategoryId ?? c.hotelexpensecategoryid} className="flex items-center justify-between rounded border p-2">
                    <span>{c.name}</span>
                    {!(c.isActive ?? c.isactive ?? true) && <Badge variant="outline">inactive</Badge>}
                  </div>
                ))}
                {categories.length === 0 && <div className="text-center text-slate-400 py-4">No categories yet</div>}
              </div>
              <div className="flex gap-2">
                <Input value={newCatName} onChange={(e) => setNewCatName(e.target.value)} placeholder="New category name" onKeyDown={(e) => e.key === "Enter" && addCategory()} />
                <Button onClick={addCategory} className="bg-violet-600 hover:bg-violet-700">Add</Button>
              </div>
            </div>
          </DialogContent>
        </Dialog>

        {/* Delete Dialog -- Poultry's confirm. */}
        <Dialog open={!!deleteTarget} onOpenChange={(v) => { if (!v) setDeleteTarget(null) }}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Delete expense?</DialogTitle>
              <DialogDescription>
                {deleteTarget?.description ? `"${deleteTarget.description}" will be removed.` : "This expense will be removed."} If it was paid, the money goes back to its account.
              </DialogDescription>
            </DialogHeader>
            <DialogFooter>
              <Button variant="outline" onClick={() => setDeleteTarget(null)}>Cancel</Button>
              <Button variant="destructive" onClick={confirmDelete}>Delete</Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </main></div></div>
  )
}

/** "Sep 28, 26" -- Poultry's short card date, read off the yyyy-mm-dd string so no time zone can move it. */
function fmtShortDate(d?: string | null): string {
  const [y, m, day] = (d ?? "").split("T")[0].split("-")
  if (!y || !m || !day) return d ?? "—"
  const mon = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][Number(m) - 1] ?? m
  return `${mon} ${Number(day)}, ${y.slice(2)}`
}
