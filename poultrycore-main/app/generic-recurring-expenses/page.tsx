"use client"

// Recurring Expenses — the costs that come round every month whether or not
// anyone remembers them: hosting, tools, rent, retainers.
//
// A recurring expense is a TEMPLATE, not a cost. It appears in no report and
// touches no P&L; it exists to raise a real expense when the period falls due.
// Nothing here happens on a schedule — there is no scheduler anywhere in this
// codebase — so raising them is a button, and this page is where you press it.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Badge } from "@/components/ui/badge"
import { Switch } from "@/components/ui/switch"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger,
} from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { FormSection, FormField } from "@/components/ui/form-section"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Loader2, Plus, Repeat, Pause, Play, Ban, Play as Run, RefreshCw } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  getRecurringExpenses, createRecurringExpense, setRecurringExpenseStatus,
  previewRecurring, generateRecurring,
  RECURRING_FREQUENCIES, FREQUENCY_LABELS,
  type GenericRecurringExpense, type RecurringExpensePreviewRow, type RecurringFrequency,
} from "@/lib/api/generic-money-out"
import { getExpenseCategories, getCashAccounts, getSuppliers } from "@/lib/api/generic"

const STATUS_STYLES: Record<string, string> = {
  Active: "bg-emerald-100 text-emerald-800 hover:bg-emerald-100",
  Paused: "bg-amber-100 text-amber-800 hover:bg-amber-100",
  Cancelled: "bg-slate-200 text-slate-700 hover:bg-slate-200",
  Expired: "bg-slate-200 text-slate-700 hover:bg-slate-200",
}

const today = () => new Date().toISOString().slice(0, 10)

export default function GenericRecurringExpensesPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  const [rows, setRows] = useState<GenericRecurringExpense[]>([])
  const [categories, setCategories] = useState<{ genericExpenseCategoryId: number; name: string }[]>([])
  const [accounts, setAccounts] = useState<{ genericCashAccountId: number; accountName: string; isActive: boolean }[]>([])
  const [suppliers, setSuppliers] = useState<{ genericSupplierId: number; supplierName: string }[]>([])
  const [preview, setPreview] = useState<RecurringExpensePreviewRow[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [generating, setGenerating] = useState(false)
  const [search, setSearch] = useState("")
  const [open, setOpen] = useState(false)
  const [confirmOpen, setConfirmOpen] = useState(false)
  const [cancelling, setCancelling] = useState<GenericRecurringExpense | null>(null)
  const [cancelReason, setCancelReason] = useState("")

  const EMPTY = {
    expenseName: "",
    genericExpenseCategoryId: "",
    genericSupplierId: "",
    amount: "0",
    frequency: "Monthly" as RecurringFrequency | string,
    startDate: today(),
    endDate: "",
    paymentMethod: "Bank",
    defaultCashAccountId: "",
    autoPayOnGenerate: true,
    notes: "",
  }
  const [form, setForm] = useState(EMPTY)

  const load = async () => {
    setLoading(true)
    try {
      const [recs, cats, accts, sups, prev] = await Promise.all([
        getRecurringExpenses(),
        getExpenseCategories().catch(() => []),
        getCashAccounts().catch(() => []),
        getSuppliers().catch(() => []),
        previewRecurring().catch(() => [] as RecurringExpensePreviewRow[]),
      ])
      setRows(recs)
      setCategories(cats as any)
      setAccounts(accts as any)
      setSuppliers(sups as any)
      setPreview(prev)
    } catch (e: any) {
      toast({
        title: "Could not load recurring expenses",
        description: e?.message ?? String(e),
        variant: "destructive",
      })
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (!activeFarmType) return
    if (activeFarmType !== "Generic") {
      router.replace("/dashboard")
      return
    }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router])

  const visible = useMemo(
    () =>
      filterByDateAndSearch(rows, {
        search,
        searchKeys: ["expenseName", "categoryName", "supplierName", "frequency"],
      }),
    [rows, search],
  )
  const pg = usePagination(visible)

  // Already-generated periods are shown greyed rather than hidden: "why is my
  // hosting bill not in the list" is a worse question than seeing it marked done.
  const toRaise = useMemo(() => preview.filter((p) => !p.alreadyGenerated), [preview])
  const totalToRaise = useMemo(() => toRaise.reduce((s, p) => s + p.amount, 0), [toRaise])

  const monthlyBurn = useMemo(() => {
    // Everything normalised to a month, so one number answers "what leaves
    // every month". Weekly is 52/12 weeks, not 4.
    const perMonth: Record<string, number> = {
      Weekly: 52 / 12, Monthly: 1, Quarterly: 1 / 3, SemiAnnual: 1 / 6, Annual: 1 / 12,
    }
    return rows
      .filter((r) => r.status === "Active")
      .reduce((sum, r) => sum + r.amount * (perMonth[r.frequency] ?? 0), 0)
  }, [rows])

  const onSave = async () => {
    if (!form.expenseName.trim()) {
      toast({ title: "A name is required", variant: "destructive" })
      return
    }
    if (!form.genericExpenseCategoryId) {
      toast({ title: "Pick an expense category", variant: "destructive" })
      return
    }
    if (Number(form.amount) <= 0) {
      toast({ title: "The amount must be more than zero", variant: "destructive" })
      return
    }
    setSaving(true)
    try {
      await createRecurringExpense({
        expenseName: form.expenseName.trim(),
        genericExpenseCategoryId: Number(form.genericExpenseCategoryId),
        genericSupplierId: form.genericSupplierId ? Number(form.genericSupplierId) : null,
        amount: Number(form.amount),
        frequency: form.frequency,
        startDate: form.startDate,
        endDate: form.endDate || null,
        paymentMethod: form.paymentMethod || null,
        defaultCashAccountId: form.defaultCashAccountId ? Number(form.defaultCashAccountId) : null,
        autoPayOnGenerate: form.autoPayOnGenerate,
        notes: form.notes || null,
      })
      toast({ title: `"${form.expenseName.trim()}" will now repeat.` })
      setOpen(false)
      setForm(EMPTY)
      await load()
    } catch (e: any) {
      toast({ title: "Could not save", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  const changeStatus = async (r: GenericRecurringExpense, status: string, reason?: string) => {
    try {
      await setRecurringExpenseStatus(r.genericRecurringExpenseId, { status, reason: reason ?? null })
      toast({ title: `${r.expenseName} is now ${status}.` })
      await load()
    } catch (e: any) {
      toast({ title: "Could not change the status", description: e?.message ?? String(e), variant: "destructive" })
    }
  }

  const onGenerate = async () => {
    setConfirmOpen(false)
    setGenerating(true)
    try {
      const n = await generateRecurring()
      toast({
        title: n === 0 ? "Nothing new to raise." : `${n} expense${n === 1 ? "" : "s"} raised.`,
        description: n > 0 ? "Paid ones moved cash; the rest are bills on Supplier Balances." : undefined,
      })
      await load()
    } catch (e: any) {
      toast({ title: "Could not raise them", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setGenerating(false)
    }
  }

  const rowActions = (r: GenericRecurringExpense) => {
    const finished = r.status === "Cancelled" || r.status === "Expired"
    return (
      <>
        {r.status === "Active" && (
          <Button size="sm" variant="outline" className="flex-1 h-10"
            onClick={() => changeStatus(r, "Paused")}>
            <Pause className="h-4 w-4 mr-1" /> Pause
          </Button>
        )}
        {r.status === "Paused" && (
          <Button size="sm" variant="outline" className="flex-1 h-10"
            onClick={() => changeStatus(r, "Active")}>
            <Play className="h-4 w-4 mr-1" /> Resume
          </Button>
        )}
        {!finished && (
          <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200"
            onClick={() => { setCancelling(r); setCancelReason("") }}>
            <Ban className="h-4 w-4 mr-1" /> Cancel
          </Button>
        )}
      </>
    )
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6 space-y-4">
          <div className="flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <Repeat className="h-6 w-6 text-indigo-600" /> Recurring expenses
              </h1>
              <p className="text-sm text-slate-500">
                {rows.filter((r) => r.status === "Active").length} active ·{" "}
                <strong>{fmt(monthlyBurn)}</strong> a month
              </p>
            </div>
            <Dialog open={open} onOpenChange={setOpen}>
              <DialogTrigger asChild>
                <Button className="h-11 sm:h-10"><Plus className="h-4 w-4 mr-1" /> New recurring expense</Button>
              </DialogTrigger>
              <DialogContent className="w-[95vw] max-w-[900px] max-h-[90vh] overflow-y-auto">
                <DialogHeader>
                  <DialogTitle className="flex items-center gap-2">
                    <Repeat className="w-5 h-5 text-blue-600" /> New recurring expense
                  </DialogTitle>
                  <DialogDescription>
                    This is a template. It costs nothing until you raise it — nothing here
                    runs on a schedule.
                  </DialogDescription>
                </DialogHeader>

                <div className="space-y-4">
                  <FormSection title="What repeats" color="indigo">
                    <FormField label="Name *" full>
                      <Input value={form.expenseName} maxLength={200}
                        placeholder="e.g. Google Cloud hosting"
                        onChange={(e) => setForm((f) => ({ ...f, expenseName: e.target.value }))} />
                    </FormField>
                    <FormField label="Expense category *">
                      <Select value={form.genericExpenseCategoryId}
                        onValueChange={(v) => setForm((f) => ({ ...f, genericExpenseCategoryId: v }))}>
                        <SelectTrigger><SelectValue placeholder="Pick one" /></SelectTrigger>
                        <SelectContent>
                          {categories.map((c) => (
                            <SelectItem key={c.genericExpenseCategoryId} value={String(c.genericExpenseCategoryId)}>
                              {c.name}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </FormField>
                    <FormField label="Supplier (optional)">
                      <Select value={form.genericSupplierId}
                        onValueChange={(v) => setForm((f) => ({ ...f, genericSupplierId: v }))}>
                        <SelectTrigger><SelectValue placeholder="Nobody in particular" /></SelectTrigger>
                        <SelectContent>
                          {suppliers.map((s) => (
                            <SelectItem key={s.genericSupplierId} value={String(s.genericSupplierId)}>
                              {s.supplierName}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </FormField>
                    <FormField label="Amount *">
                      <NumberInput step="0.01" value={form.amount}
                        onChange={(e) => setForm((f) => ({ ...f, amount: e.target.value }))} />
                    </FormField>
                  </FormSection>

                  <FormSection title="How often" color="emerald">
                    <FormField label="Frequency">
                      <Select value={String(form.frequency)}
                        onValueChange={(v) => setForm((f) => ({ ...f, frequency: v }))}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>
                          {RECURRING_FREQUENCIES.map((f) => (
                            <SelectItem key={f} value={f}>{FREQUENCY_LABELS[f]}</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </FormField>
                    <FormField label="First due *">
                      <Input type="date" value={form.startDate}
                        onChange={(e) => setForm((f) => ({ ...f, startDate: e.target.value }))} />
                    </FormField>
                    <FormField label="Stops after (optional)">
                      <Input type="date" value={form.endDate}
                        onChange={(e) => setForm((f) => ({ ...f, endDate: e.target.value }))} />
                    </FormField>
                  </FormSection>

                  <FormSection title="How it is paid" color="amber">
                    <FormField label="Method">
                      <Select value={form.paymentMethod}
                        onValueChange={(v) => setForm((f) => ({ ...f, paymentMethod: v }))}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>
                          {["Cash", "Bank", "Mobile Money", "Card", "Other"].map((m) => (
                            <SelectItem key={m} value={m}>{m}</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </FormField>
                    <FormField label="Cash account">
                      <Select value={form.defaultCashAccountId}
                        onValueChange={(v) => setForm((f) => ({ ...f, defaultCashAccountId: v }))}>
                        <SelectTrigger><SelectValue placeholder="Pick one" /></SelectTrigger>
                        <SelectContent>
                          {accounts.filter((a) => a.isActive).map((a) => (
                            <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>
                              {a.accountName}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </FormField>
                    <FormField label="Already paid when raised" full>
                      <div className="flex items-center gap-3">
                        <Switch checked={form.autoPayOnGenerate}
                          onCheckedChange={(v) => setForm((f) => ({ ...f, autoPayOnGenerate: v }))} />
                        <span className="text-sm text-slate-600">
                          {form.autoPayOnGenerate
                            ? "Money leaves the account the moment it is raised."
                            : "Raised as a bill — settle it later on Supplier Balances."}
                        </span>
                      </div>
                    </FormField>
                  </FormSection>

                  <FormSection title="Notes" color="slate" columns={1}>
                    <FormField label="Notes">
                      <Textarea rows={2} value={form.notes}
                        onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} />
                    </FormField>
                  </FormSection>

                  <div className="flex gap-3 justify-end pt-2">
                    <Button type="button" onClick={() => setOpen(false)}
                      className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
                    <Button onClick={onSave} disabled={saving}>
                      {saving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : "Create"}
                    </Button>
                  </div>
                </div>
              </DialogContent>
            </Dialog>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500">
              <Loader2 className="h-4 w-4 animate-spin" /> Loading…
            </div>
          ) : (
            <>
              {/* ---------- what is due ---------- */}
              <Card>
                <CardHeader className="pb-3">
                  <CardTitle className="text-base">What is due</CardTitle>
                </CardHeader>
                <CardContent className="space-y-3">
                  {preview.length === 0 ? (
                    <p className="text-sm text-slate-500">Nothing is due today.</p>
                  ) : (
                    <>
                      <div className="overflow-x-auto">
                        <Table>
                          <TableHeader>
                            <TableRow>
                              <TableHead>Expense</TableHead>
                              <TableHead>Category</TableHead>
                              <TableHead>Period</TableHead>
                              <TableHead className="text-right">Amount</TableHead>
                              <TableHead />
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {preview.map((p) => (
                              <TableRow key={`${p.genericRecurringExpenseId}-${p.periodStart}`}
                                className={p.alreadyGenerated ? "opacity-50" : ""}>
                                <TableCell className="font-medium">{p.expenseName}</TableCell>
                                <TableCell>{p.categoryName ?? "—"}</TableCell>
                                <TableCell className="whitespace-nowrap">
                                  {p.periodStart} → {p.periodEnd}
                                </TableCell>
                                <TableCell className="text-right">{fmt(p.amount)}</TableCell>
                                <TableCell className="text-right">
                                  {p.alreadyGenerated
                                    ? <Badge variant="outline">Already raised</Badge>
                                    : <Badge className="bg-emerald-100 text-emerald-800 hover:bg-emerald-100">Will be raised</Badge>}
                                </TableCell>
                              </TableRow>
                            ))}
                          </TableBody>
                        </Table>
                      </div>
                      <div className="flex items-center justify-between flex-wrap gap-2">
                        <p className="text-sm text-slate-600">
                          {toRaise.length} to raise, {fmt(totalToRaise)} in total.
                        </p>
                        <div className="flex gap-2">
                          <Button variant="outline" className="h-10" onClick={load}>
                            <RefreshCw className="h-4 w-4 mr-1" /> Refresh
                          </Button>
                          <Button className="h-10" disabled={generating || toRaise.length === 0}
                            onClick={() => setConfirmOpen(true)}>
                            {generating
                              ? (<><Loader2 className="h-4 w-4 mr-1 animate-spin" /> Raising…</>)
                              : (<><Run className="h-4 w-4 mr-1" /> Raise {toRaise.length}</>)}
                          </Button>
                        </div>
                      </div>
                    </>
                  )}
                </CardContent>
              </Card>

              {/* ---------- the templates ---------- */}
              {rows.length === 0 ? (
                <Card>
                  <CardContent className="py-8 text-center text-slate-500">
                    Nothing repeats yet. Add hosting, tools or rent so they stop being a surprise.
                  </CardContent>
                </Card>
              ) : (
                <>
                  <ListFilters search={search} setSearch={setSearch} searchOnly
                    searchPlaceholder="Search name, category or supplier" />
                  <Card>
                    <CardContent className="p-0">
                      <MobileCardList
                        items={pg.pageItems}
                        getKey={(r) => r.genericRecurringExpenseId}
                        primary={(r) => r.expenseName}
                        secondary={(r) => (
                          <>
                            <span>{fmt(r.amount)}</span>
                            <span> · {FREQUENCY_LABELS[r.frequency as RecurringFrequency] ?? r.frequency}</span>
                          </>
                        )}
                        trailing={(r) => (
                          <Badge className={STATUS_STYLES[r.status] ?? "bg-slate-100 text-slate-600"}>
                            {r.status}
                          </Badge>
                        )}
                        details={(r) => [
                          { label: "Category", value: r.categoryName ?? "—" },
                          { label: "Supplier", value: r.supplierName ?? "—" },
                          { label: "Next due", value: r.nextDueDate ?? "—" },
                          { label: "Raised so far", value: r.generatedCount },
                          { label: "On raise", value: r.autoPayOnGenerate ? "Paid" : "Left as a bill" },
                        ]}
                        actions={rowActions}
                        pagination={pg.paginationProps}
                        desktopTable={
                          <div className="overflow-x-auto">
                            <Table>
                              <TableHeader>
                                <TableRow>
                                  <TableHead>Expense</TableHead>
                                  <TableHead>Category</TableHead>
                                  <TableHead>Supplier</TableHead>
                                  <TableHead className="text-right">Amount</TableHead>
                                  <TableHead>Repeats</TableHead>
                                  <TableHead>Next due</TableHead>
                                  <TableHead className="text-right">Raised</TableHead>
                                  <TableHead>Status</TableHead>
                                  <TableHead />
                                </TableRow>
                              </TableHeader>
                              <TableBody>
                                {pg.pageItems.map((r) => (
                                  <TableRow key={r.genericRecurringExpenseId}>
                                    <TableCell className="font-medium">{r.expenseName}</TableCell>
                                    <TableCell>{r.categoryName ?? "—"}</TableCell>
                                    <TableCell>{r.supplierName ?? "—"}</TableCell>
                                    <TableCell className="text-right">{fmt(r.amount)}</TableCell>
                                    <TableCell>{FREQUENCY_LABELS[r.frequency as RecurringFrequency] ?? r.frequency}</TableCell>
                                    <TableCell className={r.isDue ? "text-amber-700 font-medium" : ""}>
                                      {r.nextDueDate ?? "—"}
                                    </TableCell>
                                    <TableCell className="text-right">{r.generatedCount}</TableCell>
                                    <TableCell>
                                      <Badge className={STATUS_STYLES[r.status] ?? "bg-slate-100 text-slate-600"}>
                                        {r.status}
                                      </Badge>
                                    </TableCell>
                                    <TableCell className="text-right whitespace-nowrap">
                                      <div className="inline-flex gap-1">{rowActions(r)}</div>
                                    </TableCell>
                                  </TableRow>
                                ))}
                              </TableBody>
                            </Table>
                            <DataPagination {...pg.paginationProps} />
                          </div>
                        }
                      />
                    </CardContent>
                  </Card>
                </>
              )}
            </>
          )}
        </main>
      </div>

      <Dialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Raise {toRaise.length} expense{toRaise.length === 1 ? "" : "s"}?</DialogTitle>
            <DialogDescription>
              {fmt(totalToRaise)} in total. Ones set to pay on raise will move money out of their
              cash account now; the rest become bills you settle later. Running this again will not
              raise the same period twice.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setConfirmOpen(false)}>Not now</Button>
            <Button onClick={onGenerate}><Run className="h-4 w-4 mr-1" /> Raise them</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={cancelling !== null} onOpenChange={(o) => !o && setCancelling(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Cancel {cancelling?.expenseName}?</DialogTitle>
            <DialogDescription>
              Expenses already raised stay exactly as they are. This only stops future ones.
            </DialogDescription>
          </DialogHeader>
          <Textarea rows={3} placeholder="Why is it being cancelled?"
            value={cancelReason} onChange={(e) => setCancelReason(e.target.value)} />
          <DialogFooter>
            <Button variant="ghost" onClick={() => setCancelling(null)}>Keep it</Button>
            <Button className="bg-red-600 hover:bg-red-700 text-white"
              onClick={async () => {
                if (!cancelReason.trim()) {
                  toast({ title: "A reason is required to cancel", variant: "destructive" })
                  return
                }
                await changeStatus(cancelling!, "Cancelled", cancelReason.trim())
                setCancelling(null)
              }}>
              Cancel it
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
