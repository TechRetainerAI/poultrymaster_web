"use client"

/**
 * Generic Loans — deep copy of Poultry Loans, adapted for Generic APIs.
 *
 * Who lent the business money, how much is still owed, and what each
 * repayment was actually made of (principal / interest / fees).
 */

import { Fragment, useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Textarea } from "@/components/ui/textarea"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { usePagination } from "@/hooks/use-pagination"
import {
  Banknote, ChevronDown, ChevronRight, HandCoins, Info,
  Loader2, Plus, TrendingDown,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import { defaultReportRange } from "@/lib/date-ranges"
import {
  getLoans, createLoan, getLoanPayments, repayLoan, getCashAccounts,
  type GenericLoan, type GenericLoanPayment, type GenericCashAccount,
} from "@/lib/api/generic"
import { fmtDateTime } from "@/lib/utils/company-datetime"

const STATUS_FILTERS = ["All", "Active", "Paid"] as const
const STATUS_COLORS: Record<string, string> = {
  Active: "bg-blue-100 text-blue-700",
  Paid: "bg-emerald-100 text-emerald-700",
  PaidOff: "bg-emerald-100 text-emerald-700",
  Defaulted: "bg-rose-100 text-rose-700",
  Cancelled: "bg-slate-100 text-slate-700",
}

const LENDER_TYPES = ["Bank", "FinancialInstitution", "Individual", "Owner", "FamilyFriend", "Supplier", "Other"]
const INTEREST_TYPES = ["Simple", "ReducingBalance", "Flat", "Unknown"]
const FREQUENCIES = ["Weekly", "BiWeekly", "Monthly", "Quarterly", "Custom"]

function today() { return new Date().toISOString().slice(0, 10) }

export default function GenericLoansPage() {
  const router = useRouter()
  const logout = useLogout()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const gh = useFmt()

  const [rows, setRows] = useState<GenericLoan[]>([])
  const [accounts, setAccounts] = useState<GenericCashAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)

  const [statusFilter, setStatusFilter] = useState<string>("All")
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")

  const [createOpen, setCreateOpen] = useState(false)
  const [repayTarget, setRepayTarget] = useState<GenericLoan | null>(null)
  const [expanded, setExpanded] = useState<Set<number>>(new Set())
  const [paymentsCache, setPaymentsCache] = useState<Record<number, GenericLoanPayment[]>>({})

  const toggle = (id: number) =>
    setExpanded((prev) => {
      const next = new Set(prev)
      if (!next.delete(id)) next.add(id)
      return next
    })

  const [form, setForm] = useState({
    lenderName: "", lenderType: "", originalPrincipal: 0, amountReceived: 0,
    interestRate: 0, interestType: "", frequency: "",
    loanDate: today(), startDate: "", dueDate: "",
    cashAccountId: null as number | null, notes: "",
  })
  const [repayForm, setRepayForm] = useState({
    principalAmount: 0, interestAmount: 0, feeAmount: 0,
    paymentDate: today(), cashAccountId: null as number | null, notes: "",
  })

  const load = useCallback(async () => {
    const [loans, accts] = await Promise.allSettled([getLoans(), getCashAccounts()])
    if (loans.status === "fulfilled") setRows(loans.value)
    if (accts.status === "fulfilled") setAccounts(accts.value)
    setLoading(false)
  }, [])

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    if (!activeFarmId) return
    setLoading(true)
    void load()
  }, [activeFarmType, activeFarmId, router, load])

  const filtered = useMemo(() => {
    let list = rows
    if (statusFilter !== "All") {
      list = list.filter((l) => l.status === statusFilter || (statusFilter === "Paid" && l.status === "PaidOff"))
    }
    return filterByDateAndSearch(list, {
      search, searchKeys: ["lenderName", "notes", "status"],
      dateFrom, dateTo, dateKey: "loanDate",
    })
  }, [rows, statusFilter, search, dateFrom, dateTo])

  const pg = usePagination(filtered)

  const totals = useMemo(() => {
    let borrowed = 0, outstanding = 0, repaid = 0, interest = 0, fees = 0
    for (const l of rows) {
      borrowed += l.originalPrincipal
      outstanding += l.outstandingBalance
      repaid += l.totalPrincipalPaid
      interest += l.totalInterestPaid
      fees += l.totalFeesPaid
    }
    return { borrowed, outstanding, repaid, interest, fees, active: rows.filter((l) => l.status === "Active").length }
  }, [rows])

  async function doCreate() {
    if (!form.lenderName.trim()) { toast({ title: "Lender name is required", variant: "destructive" }); return }
    if (form.originalPrincipal <= 0) { toast({ title: "Amount must be > 0", variant: "destructive" }); return }
    setSaving(true)
    try {
      const desc = [
        form.lenderType && `Lender type: ${form.lenderType}`,
        form.interestType && `Interest: ${form.interestType}`,
        form.frequency && `Frequency: ${form.frequency}`,
        form.notes,
      ].filter(Boolean).join(". ")

      await createLoan({
        lenderName: form.lenderName.trim(),
        originalPrincipal: form.originalPrincipal,
        amountReceived: form.amountReceived || form.originalPrincipal,
        interestRate: form.interestRate,
        loanDate: form.loanDate,
        startDate: form.startDate || undefined,
        dueDate: form.dueDate || undefined,
        genericCashAccountId: form.cashAccountId,
        notes: desc || undefined,
      })
      toast({ title: "Loan recorded" })
      setCreateOpen(false)
      setForm({ lenderName: "", lenderType: "", originalPrincipal: 0, amountReceived: 0, interestRate: 0, interestType: "", frequency: "", loanDate: today(), startDate: "", dueDate: "", cashAccountId: null, notes: "" })
      await load()
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function doRepay() {
    if (!repayTarget) return
    const total = repayForm.principalAmount + repayForm.interestAmount + repayForm.feeAmount
    if (total <= 0) { toast({ title: "Payment must be > 0", variant: "destructive" }); return }
    setSaving(true)
    try {
      await repayLoan(repayTarget.genericLoanId, {
        ...repayForm,
        genericCashAccountId: repayForm.cashAccountId,
      })
      toast({ title: "Repayment recorded" })
      setRepayTarget(null)
      // Refresh payments cache
      const payments = await getLoanPayments(repayTarget.genericLoanId)
      setPaymentsCache((c) => ({ ...c, [repayTarget.genericLoanId]: payments }))
      await load()
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function loadPayments(loanId: number) {
    if (paymentsCache[loanId]) return
    try {
      const payments = await getLoanPayments(loanId)
      setPaymentsCache((c) => ({ ...c, [loanId]: payments }))
    } catch { /* silently fail */ }
  }

  function handleExpand(l: GenericLoan) {
    toggle(l.genericLoanId)
    void loadPayments(l.genericLoanId)
  }

  const activeAccounts = accounts.filter((a) => a.isActive)

  return (
    <TooltipProvider delayDuration={200}>
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-3 md:p-4 space-y-3">

          <div className="flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <Banknote className="h-6 w-6 text-violet-600" /> Loans (Financing)
              </h1>
              <p className="text-sm text-slate-500">Borrowing is not income. Repaying principal is not an expense. Only the interest and fees reach the P&amp;L.</p>
            </div>
            <Button onClick={() => setCreateOpen(true)}><Plus className="h-4 w-4 mr-1" /> New Loan</Button>
          </div>

          {/* KPI tiles */}
          <div className="grid grid-cols-2 md:grid-cols-5 gap-2">
            <Tile label="Total Borrowed" value={gh(totals.borrowed)}
                  tip="Total principal borrowed across all loans." />
            <Tile label="Still Owed" value={gh(totals.outstanding)} tone="text-violet-700"
                  tip="Total outstanding principal across all active loans." />
            <Tile label="Principal Repaid" value={gh(totals.repaid)} tone="text-emerald-700"
                  tip="Total principal repaid across all loans." />
            <Tile label="Interest Paid" value={gh(totals.interest)} tone="text-amber-700"
                  tip="Total interest paid. This is a cost on the P&L." />
            <Tile label="Active Loans" value={String(totals.active)}
                  tip="Number of loans with status Active." />
          </div>

          {/* Filters */}
          <div className="flex flex-wrap items-center gap-2">
            {STATUS_FILTERS.map((s) => (
              <Button key={s} size="sm" variant={statusFilter === s ? "default" : "outline"}
                      onClick={() => setStatusFilter(s)}>
                {s === "All" ? "All" : s}
              </Button>
            ))}
          </div>

          <ListFilters
            search={search} setSearch={setSearch}
            searchPlaceholder="Search lender, notes..."
            dateFrom={dateFrom} setDateFrom={setDateFrom}
            dateTo={dateTo} setDateTo={setDateTo}
          />

          {loading ? (
            <Card><CardContent className="py-12 text-center text-slate-600">
              <Loader2 className="h-4 w-4 animate-spin inline mr-2" />Loading loans...
            </CardContent></Card>
          ) : (
            <Card>
              <CardContent className="p-0 md:p-2">
                {filtered.length === 0 ? (
                  <p className="px-4 py-8 text-center text-sm text-slate-500">
                    No loans match the current filters. Record a new loan to get started.
                  </p>
                ) : (
                  <MobileCardList
                    defaultOpen striped stripeAccent="blue"
                    items={pg.pageItems} pagination={pg.paginationProps}
                    getKey={(l: any) => l.genericLoanId}
                    primary={(l: any) => l.lenderName || "Lender not recorded"}
                    secondary={(l: any) => fmtDateTime(l.loanDate, l)}
                    trailing={(l: any) => <Badge className={STATUS_COLORS[l.status] ?? "bg-slate-100"}>{l.status}</Badge>}
                    highlights={(l: any) => [
                      { label: "Borrowed", value: gh(l.originalPrincipal), accent: "blue" },
                      { label: "Received", value: gh(l.amountReceived), accent: "blue" },
                      { label: "Still owed", value: gh(l.outstandingBalance), accent: l.outstandingBalance > 0 ? "rose" : "emerald" },
                    ]}
                    details={(l: any) => [
                      { label: "Interest rate", value: `${l.interestRate}%` },
                      { label: "Principal paid", value: gh(l.totalPrincipalPaid) },
                      { label: "Interest paid", value: gh(l.totalInterestPaid) },
                      { label: "Fees paid", value: gh(l.totalFeesPaid) },
                      { label: "Due date", value: l.dueDate ? fmtDateTime(l.dueDate, l) : "\u2014" },
                      { label: "Notes", value: l.notes ?? "\u2014" },
                    ]}
                    actions={(l: any) => (
                      <>
                        {l.status === "Active" && (
                          <Button size="sm" variant="outline" className="flex-1 h-10 text-emerald-700 border-emerald-200"
                            onClick={() => {
                              setRepayTarget(l)
                              setRepayForm({ principalAmount: 0, interestAmount: 0, feeAmount: 0, paymentDate: today(), cashAccountId: null, notes: "" })
                            }}>
                            <HandCoins className="h-4 w-4 mr-1" /> Repay
                          </Button>
                        )}
                        <Button size="sm" variant="outline" className="flex-1 h-10"
                          onClick={() => handleExpand(l)}>
                          <TrendingDown className="h-4 w-4 mr-1" /> Payments
                        </Button>
                      </>
                    )}
                    desktopTable={
                      <div className="overflow-x-auto">
                        <Table>
                          <TableHeader><TableRow>
                            <TableHead className="w-8" />
                            <TableHead>Date</TableHead>
                            <TableHead>Lender</TableHead>
                            <TableHead className="text-right">Borrowed</TableHead>
                            <TableHead className="text-right">Received</TableHead>
                            <TableHead className="text-right">Repaid</TableHead>
                            <TableHead className="text-right">Still Owed</TableHead>
                            <TableHead className="text-right">Interest</TableHead>
                            <TableHead className="text-right">Fees</TableHead>
                            <TableHead>Status</TableHead>
                            <TableHead className="text-right">Actions</TableHead>
                          </TableRow></TableHeader>
                          <TableBody>
                            {pg.pageItems.map((l: any) => {
                              const open = expanded.has(l.genericLoanId)
                              const payments = paymentsCache[l.genericLoanId] ?? []
                              return (
                                <Fragment key={l.genericLoanId}>
                                  <TableRow className="cursor-pointer" onClick={() => handleExpand(l)}>
                                    <TableCell className="px-1">
                                      {open ? <ChevronDown className="w-4 h-4 text-slate-400" />
                                            : <ChevronRight className="w-4 h-4 text-slate-400" />}
                                    </TableCell>
                                    <TableCell className="whitespace-nowrap">{fmtDateTime(l.loanDate, l)}</TableCell>
                                    <TableCell className="font-medium">{l.lenderName || <span className="italic text-slate-400">Not recorded</span>}</TableCell>
                                    <TableCell className="text-right tabular-nums">{gh(l.originalPrincipal)}</TableCell>
                                    <TableCell className="text-right tabular-nums">{gh(l.amountReceived)}</TableCell>
                                    <TableCell className="text-right tabular-nums text-emerald-700">{gh(l.totalPrincipalPaid)}</TableCell>
                                    <TableCell className={cn("text-right tabular-nums font-medium", l.outstandingBalance > 0 ? "text-violet-700" : "text-emerald-700")}>
                                      {gh(l.outstandingBalance)}
                                    </TableCell>
                                    <TableCell className="text-right tabular-nums text-amber-700">{gh(l.totalInterestPaid)}</TableCell>
                                    <TableCell className="text-right tabular-nums text-amber-700">{gh(l.totalFeesPaid)}</TableCell>
                                    <TableCell><Badge className={STATUS_COLORS[l.status] ?? "bg-slate-100"}>{l.status}</Badge></TableCell>
                                    <TableCell className="text-right whitespace-nowrap" onClick={(e) => e.stopPropagation()}>
                                      {l.status === "Active" && (
                                        <Button size="sm" variant="ghost"
                                          onClick={() => {
                                            setRepayTarget(l)
                                            setRepayForm({ principalAmount: 0, interestAmount: 0, feeAmount: 0, paymentDate: today(), cashAccountId: null, notes: "" })
                                          }}>
                                          <HandCoins className="h-4 w-4 text-emerald-600" />
                                        </Button>
                                      )}
                                    </TableCell>
                                  </TableRow>
                                  {open && (
                                    <TableRow>
                                      <TableCell colSpan={11} className="bg-slate-50 p-0">
                                        <div className="px-4 py-3">
                                          <div className="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-500">
                                            Repayment History
                                          </div>
                                          {payments.length === 0 ? (
                                            <p className="text-sm text-slate-500">No payments recorded for this loan.</p>
                                          ) : (
                                            <Table>
                                              <TableHeader><TableRow>
                                                <TableHead>Date</TableHead>
                                                <TableHead className="text-right">Principal</TableHead>
                                                <TableHead className="text-right">Interest</TableHead>
                                                <TableHead className="text-right">Fees</TableHead>
                                                <TableHead className="text-right">Total Paid</TableHead>
                                                <TableHead>Status</TableHead>
                                                <TableHead>Notes</TableHead>
                                              </TableRow></TableHeader>
                                              <TableBody>
                                                {payments.map((p) => (
                                                  <TableRow key={p.genericLoanPaymentId}
                                                    className={p.isReversed ? "line-through text-slate-400" : ""}>
                                                    <TableCell className="whitespace-nowrap">{fmtDateTime(p.paymentDate, p)}</TableCell>
                                                    <TableCell className="text-right tabular-nums">{gh(p.principalAmount)}</TableCell>
                                                    <TableCell className="text-right tabular-nums text-amber-700">{gh(p.interestAmount)}</TableCell>
                                                    <TableCell className="text-right tabular-nums text-amber-700">{gh(p.feeAmount)}</TableCell>
                                                    <TableCell className="text-right tabular-nums font-semibold">{gh(p.totalPayment)}</TableCell>
                                                    <TableCell>
                                                      <Badge className={p.isReversed ? "bg-slate-100 text-slate-700" : "bg-sky-100 text-sky-800"}>
                                                        {p.isReversed ? "Reversed" : "Posted"}
                                                      </Badge>
                                                    </TableCell>
                                                    <TableCell className="text-sm text-slate-600">{p.notes ?? "\u2014"}</TableCell>
                                                  </TableRow>
                                                ))}
                                              </TableBody>
                                            </Table>
                                          )}
                                          {l.notes && (
                                            <div className="mt-2 text-xs text-slate-500">
                                              <span className="font-medium">Loan notes:</span> {l.notes}
                                            </div>
                                          )}
                                        </div>
                                      </TableCell>
                                    </TableRow>
                                  )}
                                </Fragment>
                              )
                            })}
                          </TableBody>
                        </Table>
                      </div>
                    }
                  />
                )}
              </CardContent>
            </Card>
          )}

          <p className="text-[11px] leading-relaxed text-slate-500">
            Loan totals are as they stand today, not sliced by the period &mdash; an outstanding
            balance is a position, not a flow. A repayment is not one number: the principal
            portion reduces the debt without being a cost, while interest and fees are the
            cost of borrowing.
          </p>
        </main>
      </div>

      {/* Create loan dialog */}
      <Dialog open={createOpen} onOpenChange={setCreateOpen}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Record a new loan</DialogTitle>
            <DialogDescription>Money borrowed from a lender. Not revenue.</DialogDescription>
          </DialogHeader>
          <FormSection title="Lender" color="indigo">
            <FormField label="Lender name *">
              <Input value={form.lenderName} onChange={(e) => setForm((f) => ({ ...f, lenderName: e.target.value }))} placeholder="Bank, person, or institution" />
            </FormField>
            <FormField label="Lender type">
              <Select value={form.lenderType} onValueChange={(v) => setForm((f) => ({ ...f, lenderType: v }))}>
                <SelectTrigger><SelectValue placeholder="Select type" /></SelectTrigger>
                <SelectContent>
                  {LENDER_TYPES.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}
                </SelectContent>
              </Select>
            </FormField>
          </FormSection>
          <FormSection title="Amounts" color="emerald">
            <FormField label="Amount borrowed *">
              <NumberInput min={0} step="0.01" value={form.originalPrincipal}
                onChange={(e) => setForm((f) => ({ ...f, originalPrincipal: Number(e.target.value) || 0 }))} />
            </FormField>
            <FormField label="Amount received">
              <NumberInput min={0} step="0.01" value={form.amountReceived}
                onChange={(e) => setForm((f) => ({ ...f, amountReceived: Number(e.target.value) || 0 }))}
                placeholder="Same as borrowed if left blank" />
            </FormField>
            <FormField label="Cash account">
              <Select value={form.cashAccountId?.toString() ?? ""} onValueChange={(v) => setForm((f) => ({ ...f, cashAccountId: v ? Number(v) : null }))}>
                <SelectTrigger><SelectValue placeholder="Where the money arrived" /></SelectTrigger>
                <SelectContent>
                  {activeAccounts.map((a) => (
                    <SelectItem key={a.genericCashAccountId} value={a.genericCashAccountId.toString()}>
                      {a.accountName} ({gh(a.currentBalance)})
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </FormField>
          </FormSection>
          <FormSection title="Terms" color="slate">
            <FormField label="Interest rate %">
              <NumberInput min={0} step="0.01" value={form.interestRate}
                onChange={(e) => setForm((f) => ({ ...f, interestRate: Number(e.target.value) || 0 }))} />
            </FormField>
            <FormField label="Interest type">
              <Select value={form.interestType} onValueChange={(v) => setForm((f) => ({ ...f, interestType: v }))}>
                <SelectTrigger><SelectValue placeholder="Select type" /></SelectTrigger>
                <SelectContent>
                  {INTEREST_TYPES.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}
                </SelectContent>
              </Select>
            </FormField>
            <FormField label="Payment frequency">
              <Select value={form.frequency} onValueChange={(v) => setForm((f) => ({ ...f, frequency: v }))}>
                <SelectTrigger><SelectValue placeholder="How often" /></SelectTrigger>
                <SelectContent>
                  {FREQUENCIES.map((f) => <SelectItem key={f} value={f}>{f}</SelectItem>)}
                </SelectContent>
              </Select>
            </FormField>
          </FormSection>
          <FormSection title="Dates" color="slate">
            <FormField label="Loan date"><Input type="date" value={form.loanDate} onChange={(e) => setForm((f) => ({ ...f, loanDate: e.target.value }))} /></FormField>
            <FormField label="Start date"><Input type="date" value={form.startDate} onChange={(e) => setForm((f) => ({ ...f, startDate: e.target.value }))} /></FormField>
            <FormField label="Due date"><Input type="date" value={form.dueDate} onChange={(e) => setForm((f) => ({ ...f, dueDate: e.target.value }))} /></FormField>
          </FormSection>
          <FormSection title="Notes" color="slate">
            <FormField label="Notes" full>
              <Textarea value={form.notes} onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} rows={2} />
            </FormField>
          </FormSection>
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setCreateOpen(false)}>Cancel</Button>
            <Button onClick={doCreate} disabled={saving}>
              {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : "Record Loan"}
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Repay dialog */}
      <Dialog open={!!repayTarget} onOpenChange={(o) => !o && setRepayTarget(null)}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle>Repay &mdash; {repayTarget?.lenderName}</DialogTitle>
            <DialogDescription>
              Outstanding: <strong className="text-violet-700">{repayTarget ? gh(repayTarget.outstandingBalance) : ""}</strong>
            </DialogDescription>
          </DialogHeader>
          {repayTarget && (
            <>
              <FormSection title="Payment breakdown" color="emerald">
                <FormField label="Principal">
                  <NumberInput min={0} step="0.01" value={repayForm.principalAmount}
                    onChange={(e) => setRepayForm((f) => ({ ...f, principalAmount: Number(e.target.value) || 0 }))} />
                  <p className="text-[11px] text-slate-500 mt-0.5">Reduces the debt. Not a cost.</p>
                </FormField>
                <FormField label="Interest">
                  <NumberInput min={0} step="0.01" value={repayForm.interestAmount}
                    onChange={(e) => setRepayForm((f) => ({ ...f, interestAmount: Number(e.target.value) || 0 }))} />
                  <p className="text-[11px] text-amber-700 mt-0.5">This IS a cost on the P&L.</p>
                </FormField>
                <FormField label="Fees">
                  <NumberInput min={0} step="0.01" value={repayForm.feeAmount}
                    onChange={(e) => setRepayForm((f) => ({ ...f, feeAmount: Number(e.target.value) || 0 }))} />
                  <p className="text-[11px] text-amber-700 mt-0.5">This IS a cost on the P&L.</p>
                </FormField>
                <FormField label="Total" full>
                  <p className="text-lg font-semibold tabular-nums">{gh(repayForm.principalAmount + repayForm.interestAmount + repayForm.feeAmount)}</p>
                </FormField>
              </FormSection>
              <FormSection title="Details" color="slate">
                <FormField label="Cash account">
                  <Select value={repayForm.cashAccountId?.toString() ?? ""} onValueChange={(v) => setRepayForm((f) => ({ ...f, cashAccountId: v ? Number(v) : null }))}>
                    <SelectTrigger><SelectValue placeholder="Paid from" /></SelectTrigger>
                    <SelectContent>
                      {activeAccounts.map((a) => (
                        <SelectItem key={a.genericCashAccountId} value={a.genericCashAccountId.toString()}>
                          {a.accountName} ({gh(a.currentBalance)})
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </FormField>
                <FormField label="Payment date">
                  <Input type="date" value={repayForm.paymentDate}
                    onChange={(e) => setRepayForm((f) => ({ ...f, paymentDate: e.target.value }))} />
                </FormField>
                <FormField label="Notes" full>
                  <Input value={repayForm.notes}
                    onChange={(e) => setRepayForm((f) => ({ ...f, notes: e.target.value }))} />
                </FormField>
              </FormSection>
              {repayForm.principalAmount > repayTarget.outstandingBalance && (
                <div className="rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-900">
                  Principal ({gh(repayForm.principalAmount)}) exceeds outstanding balance ({gh(repayTarget.outstandingBalance)}).
                </div>
              )}
              <div className="flex justify-end gap-2">
                <Button variant="outline" onClick={() => setRepayTarget(null)}>Cancel</Button>
                <Button onClick={doRepay} disabled={saving}>
                  {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : "Record Payment"}
                </Button>
              </div>
            </>
          )}
        </DialogContent>
      </Dialog>
    </div>
    </TooltipProvider>
  )
}

function Tile({ label, value, tone, tip }: {
  label: string; value: string; tone?: string; tip: string
}) {
  return (
    <Card>
      <CardContent className="p-3">
        <div className="flex items-center gap-1 text-[11px] uppercase tracking-wide text-slate-500">
          <span className="truncate">{label}</span>
          <Tooltip>
            <TooltipTrigger asChild>
              <button type="button" className="ml-auto shrink-0 text-slate-400 hover:text-slate-600">
                <Info className="h-3.5 w-3.5" />
              </button>
            </TooltipTrigger>
            <TooltipContent className="max-w-xs text-xs leading-snug">{tip}</TooltipContent>
          </Tooltip>
        </div>
        <div className={cn("mt-1 text-lg font-semibold tabular-nums", tone ?? "text-slate-900")}>
          {value}
        </div>
      </CardContent>
    </Card>
  )
}
