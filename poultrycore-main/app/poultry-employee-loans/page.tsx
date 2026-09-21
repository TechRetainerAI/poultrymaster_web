"use client"

// Employee Loans & Advances.
//
// Money the farm has LENT TO ITS STAFF: what went out, what has come back, and
// how each repayment was made.
//
// THE TWO THINGS THIS PAGE MUST TEACH
// -----------------------------------
// 1. AN ADVANCE IS NOT A COST. Handing a worker 2,000 does not make the farm
//    2,000 poorer -- it swaps cash for a claim on that worker. It never reaches
//    the Profit & Loss, and a salary advance is not payroll expense until it is
//    earned. The page says so under the heading, because "where did my profit
//    go" is the question an advance provokes.
//
// 2. A PAYROLL DEDUCTION IS NOT A RECEIPT. When 100 is withheld from a 2,200
//    wage, the farm pays out 2,100. No money arrives, so no cash account moves
//    and Cash Flow shows nothing -- the receivable simply comes down. The
//    repayment history labels those rows "Payroll" with no account, and the
//    reverse button is deliberately absent on them: undoing one means reopening
//    the payroll that created it, which is the only thing that can put the
//    payslip and the advance back in step (spec section 60).
//
// WHY THE LIST IS SERVER-PAGED
// ----------------------------
// A farm that has been running for years has more advances than a browser
// should hold, and every filter here is applied in SQL rather than over a list
// pulled down whole (sections 70-72). That is also why the count under the
// table is the SERVER's count, not `rows.length`.

import { Fragment, useCallback, useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { NumberInput } from "@/components/ui/number-input"
import { Switch } from "@/components/ui/switch"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import {
  HandCoins, Loader2, Plus, Undo2, Wallet, Users, AlertTriangle, Info,
  ChevronDown, ChevronRight,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import {
  listPoultryCashAccounts, listPoultryStaff,
  listPoultryEmployeeLoans, getPoultryEmployeeLoanSummary,
  listPoultryEmployeeLoanRepayments,
  createPoultryEmployeeLoan, disbursePoultryEmployeeLoan,
  cancelPoultryEmployeeLoan, reversePoultryEmployeeLoan,
  recordPoultryEmployeeLoanRepayment, reversePoultryEmployeeLoanRepayment,
  EMPLOYEE_LOAN_TYPES, EMPLOYEE_LOAN_TYPE_LABELS,
  EMPLOYEE_LOAN_REPAYMENT_METHODS, EMPLOYEE_LOAN_REPAYMENT_METHOD_LABELS,
  EMPLOYEE_LOAN_REPAYMENT_SOURCES, EMPLOYEE_LOAN_SOURCE_LABELS,
  EMPLOYEE_LOAN_STATUS_LABELS,
  type PoultryEmployeeLoan, type PoultryEmployeeLoanRepayment,
  type PoultryEmployeeLoanSummary, type PoultryCashAccount, type PoultryStaff,
} from "@/lib/api/poultry-finance"

const PAGE_SIZE = 25
const today = () => new Date().toISOString().slice(0, 10)
const fmtDate = (d?: string | null) => (d ? String(d).slice(0, 10) : "—")

/** Active / Paid / All — the three a farm actually asks for (section 70). */
const QUICK_FILTERS = [
  { key: "Active", label: "Active" },
  { key: "Paid", label: "Paid" },
  { key: "", label: "All" },
] as const

function statusClass(status: string) {
  switch (status) {
    case "Active": return "bg-amber-100 text-amber-800"
    case "Paid": return "bg-emerald-100 text-emerald-700"
    case "Draft": return "bg-slate-100 text-slate-600"
    case "Reversed":
    case "Cancelled": return "bg-slate-200 text-slate-500"
    case "WrittenOff": return "bg-rose-100 text-rose-700"
    default: return "bg-slate-100 text-slate-600"
  }
}

// ---------------------------------------------------------------------------
// Repayment history — the statement behind the balance.
//
// Reversed rows stay, struck through and labelled. A balance whose corrections
// are hidden cannot be reconciled, which is the whole reason the repayments
// table is append-only.
// ---------------------------------------------------------------------------
function RepaymentHistory({
  rows, loading, fmt, onReverse,
}: {
  rows: PoultryEmployeeLoanRepayment[]
  loading: boolean
  fmt: (n: number) => string
  onReverse: (r: PoultryEmployeeLoanRepayment) => void
}) {
  if (loading) {
    return (
      <div className="flex items-center gap-2 py-3 text-sm text-slate-500">
        <Loader2 className="h-4 w-4 animate-spin" /> Loading repayments…
      </div>
    )
  }
  if (rows.length === 0) {
    return <p className="py-3 text-sm text-slate-500">Nothing repaid yet.</p>
  }
  return (
    // The same bordered white panel the overview above it sits in, so the
    // expanded area reads as two tables rather than one table and a loose grid.
    <div className="overflow-hidden rounded-md border border-slate-200 bg-white">
      <Table>
        <TableHeader>
          <TableRow className="hover:bg-transparent">
            <TableHead>Date</TableHead>
            <TableHead>How</TableHead>
            <TableHead>Reference</TableHead>
            <TableHead className="text-right">Amount</TableHead>
            <TableHead className="text-right">Balance before</TableHead>
            <TableHead className="text-right">Balance after</TableHead>
            <TableHead>Status</TableHead>
            <TableHead className="w-24" />
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((r) => {
            const reversed = r.status === "Reversed"
            const fromPayroll = r.sourceType === "Payroll"
            return (
              <TableRow key={r.poultryEmployeeLoanRepaymentId}
                        className={cn(reversed && "text-slate-400")}>
                <TableCell className="whitespace-nowrap">{fmtDate(r.repaymentDate)}</TableCell>
                <TableCell>
                  {EMPLOYEE_LOAN_SOURCE_LABELS[r.sourceType] ?? r.sourceType}
                  {fromPayroll && (
                    <span className="block text-[11px] text-slate-400">no cash moved</span>
                  )}
                </TableCell>
                <TableCell className="text-xs">
                  {fromPayroll
                    ? (r.payrollPeriodStart
                        ? `Payroll ${fmtDate(r.payrollPeriodStart)} – ${fmtDate(r.payrollPeriodEnd)}`
                        : `Payroll run ${r.poultryPayrollRunId ?? "—"}`)
                    : (r.referenceNumber || r.cashAccountName || "—")}
                </TableCell>
                <TableCell className={cn("text-right tabular-nums", reversed && "line-through")}>
                  {fmt(r.amount)}
                </TableCell>
                <TableCell className="text-right tabular-nums">{fmt(r.balanceBefore)}</TableCell>
                <TableCell className="text-right tabular-nums">{fmt(r.balanceAfter)}</TableCell>
                <TableCell>
                  {reversed
                    ? <Badge variant="secondary" title={r.reversalReason ?? undefined}>Reversed</Badge>
                    : <Badge className="bg-emerald-100 text-emerald-700">Posted</Badge>}
                </TableCell>
                <TableCell className="text-right">
                  {/* Section 60. A payroll repayment is undone by reopening its
                      payroll, so there is no button here -- offering one that
                      always failed would be worse than explaining why. */}
                  {!reversed && !fromPayroll && (
                    <Button size="sm" variant="ghost" onClick={() => onReverse(r)}>
                      <Undo2 className="h-4 w-4 mr-1" /> Reverse
                    </Button>
                  )}
                  {!reversed && fromPayroll && (
                    <span className="text-[11px] text-slate-400"
                          title="Reopen the payroll run to reverse this repayment.">
                      via payroll
                    </span>
                  )}
                </TableCell>
              </TableRow>
            )
          })}
        </TableBody>
      </Table>
    </div>
  )
}

// ---------------------------------------------------------------------------
export default function PoultryEmployeeLoansPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") router.replace("/dashboard")
  }, [activeFarmType, router])

  const [rows, setRows] = useState<PoultryEmployeeLoan[]>([])
  const [total, setTotal] = useState(0)
  const [summary, setSummary] = useState<PoultryEmployeeLoanSummary | null>(null)
  const [staff, setStaff] = useState<PoultryStaff[]>([])
  const [accounts, setAccounts] = useState<PoultryCashAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")

  // Filters. All applied server-side.
  const [status, setStatus] = useState<string>("Active")
  const [search, setSearch] = useState("")
  const [staffId, setStaffId] = useState<string>("ALL")
  const [loanType, setLoanType] = useState<string>("ALL")
  const [offset, setOffset] = useState(0)

  // Repayment history for the CURRENT PAGE only, fetched once after the rows
  // land. Per-row fetching would be tidier still, but MobileCardList does not
  // report when a card is expanded, and a page is 25 advances -- bounded, and
  // the same bound the list itself already is.
  const [historyByLoan, setHistoryByLoan] =
    useState<Map<number, PoultryEmployeeLoanRepayment[]>>(new Map())
  const [historyLoading, setHistoryLoading] = useState(false)
  /** Desktop rows expand independently; the cards manage their own. */
  const [expanded, setExpanded] = useState<Set<number>>(new Set())

  const load = useCallback(async () => {
    setError("")
    try {
      const [page, sum] = await Promise.all([
        listPoultryEmployeeLoans({
          status: status || null,
          search: search || null,
          staffId: staffId === "ALL" ? null : Number(staffId),
          loanType: loanType === "ALL" ? null : loanType,
          limit: PAGE_SIZE,
          offset,
        }),
        getPoultryEmployeeLoanSummary(),
      ])
      setRows(page.items)
      setTotal(page.totalCount)
      setSummary(sum)
    } catch (e: any) {
      setError(e?.message ?? String(e))
    } finally {
      setLoading(false)
    }
  }, [status, search, staffId, loanType, offset])

  useEffect(() => { void load() }, [load])

  useEffect(() => {
    void (async () => {
      try {
        const [s, a] = await Promise.all([listPoultryStaff(), listPoultryCashAccounts()])
        setStaff(s.filter((x) => x.isActive && !x.isDeleted))
        setAccounts(a)
      } catch { /* the page still works without the pickers pre-filled */ }
    })()
  }, [])

  const loadHistories = useCallback(async (list: PoultryEmployeeLoan[]) => {
    if (list.length === 0) { setHistoryByLoan(new Map()); return }
    setHistoryLoading(true)
    try {
      const pairs = await Promise.all(list.map(async (l) => {
        // One advance failing to load its statement must not blank the other
        // twenty-four, so each settles on its own.
        try {
          return [l.poultryEmployeeLoanId,
                  await listPoultryEmployeeLoanRepayments(l.poultryEmployeeLoanId)] as const
        } catch {
          return [l.poultryEmployeeLoanId, [] as PoultryEmployeeLoanRepayment[]] as const
        }
      }))
      setHistoryByLoan(new Map(pairs))
    } finally {
      setHistoryLoading(false)
    }
  }, [])

  useEffect(() => { void loadHistories(rows) }, [rows, loadHistories])

  const refreshAll = useCallback(async () => { await load() }, [load])

  // ---- dialogs ----
  const [newOpen, setNewOpen] = useState(false)
  const [repayFor, setRepayFor] = useState<PoultryEmployeeLoan | null>(null)
  const [disburseFor, setDisburseFor] = useState<PoultryEmployeeLoan | null>(null)
  const [reversingLoan, setReversingLoan] = useState<PoultryEmployeeLoan | null>(null)
  const [reversingRepayment, setReversingRepayment] =
    useState<PoultryEmployeeLoanRepayment | null>(null)
  const [reason, setReason] = useState("")
  const [busy, setBusy] = useState(false)

  const run = async (fn: () => Promise<void>, ok: string) => {
    setBusy(true)
    try {
      await fn()
      toast({ title: ok })
      await refreshAll()
      return true
    } catch (e: any) {
      toast({ title: "That did not work", description: e?.message, variant: "destructive" })
      return false
    } finally {
      setBusy(false)
    }
  }

  const from = total === 0 ? 0 : offset + 1
  const to = Math.min(offset + PAGE_SIZE, total)

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 min-w-0 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-end justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <Users className="h-6 w-6 text-indigo-600" /> Employee Loans &amp; Advances
              </h1>
              <p className="text-sm text-slate-500 max-w-2xl">
                Money advanced to staff, and repayments made through payroll or direct payment.
                An advance is <strong>not an expense</strong> — it is money the worker owes you —
                and getting it back is <strong>not income</strong>.
              </p>
            </div>
            <div className="flex gap-2">
              <Button variant="outline" asChild className="h-11 sm:h-10">
                <Link href="/poultry-payroll">Payroll</Link>
              </Button>
              <Button onClick={() => setNewOpen(true)} className="h-11 sm:h-10">
                <Plus className="h-4 w-4 mr-1" /> New loan / advance
              </Button>
            </div>
          </div>

          {/* Section 13. Four cards, not six: the balance, the two flows for the
              period, and how many are live. */}
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
            <Stat label="Outstanding" value={fmt(summary?.outstandingTotal ?? 0)}
                  hint="What staff still owe the farm" accent="indigo" />
            <Stat label="Advanced" value={fmt(summary?.disbursedInPeriod ?? 0)} accent="rose" />
            <Stat label="Repaid" value={fmt(summary?.repaidInPeriod ?? 0)} accent="emerald" />
            <Stat label="Active advances" value={String(summary?.activeLoans ?? 0)}
                  hint={`${summary?.staffWithActiveLoans ?? 0} member(s) of staff`} />
          </div>

          <div className="flex flex-wrap items-center gap-2 mb-4">
            {QUICK_FILTERS.map((f) => (
              <Button key={f.label} size="sm"
                      variant={status === f.key ? "default" : "outline"}
                      onClick={() => { setStatus(f.key); setOffset(0) }}>
                {f.label}
              </Button>
            ))}
            <Input
              value={search}
              onChange={(e) => { setSearch(e.target.value); setOffset(0) }}
              placeholder="Search number, name, purpose, reference"
              className="h-9 w-full sm:w-72"
            />
            <Select value={staffId} onValueChange={(v) => { setStaffId(v); setOffset(0) }}>
              <SelectTrigger className="h-9 w-full sm:w-52"><SelectValue placeholder="All staff" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="ALL">All staff</SelectItem>
                {staff.map((s) => (
                  <SelectItem key={s.poultryStaffId} value={String(s.poultryStaffId)}>
                    {s.firstName} {s.lastName}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Select value={loanType} onValueChange={(v) => { setLoanType(v); setOffset(0) }}>
              <SelectTrigger className="h-9 w-full sm:w-44"><SelectValue placeholder="All types" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="ALL">All types</SelectItem>
                {EMPLOYEE_LOAN_TYPES.map((t) => (
                  <SelectItem key={t} value={t}>{EMPLOYEE_LOAN_TYPE_LABELS[t]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {error && (
            <Card className="border-red-200 bg-red-50 mb-4">
              <CardContent className="p-4 text-sm text-red-800">{error}</CardContent>
            </Card>
          )}

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500">
              <Loader2 className="h-4 w-4 animate-spin" /> Loading…
            </div>
          ) : rows.length === 0 ? (
            <Card><CardContent className="py-8 text-center text-slate-500">
              {status || search || staffId !== "ALL" || loanType !== "ALL"
                ? "No advances match this filter."
                : "No advances recorded yet."}
            </CardContent></Card>
          ) : (
            <>
              <MobileCardList
                striped
                items={rows}
                getKey={(l: PoultryEmployeeLoan) => l.poultryEmployeeLoanId}
                primary={(l: PoultryEmployeeLoan) => (
                  <>{l.loanNumber ?? `#${l.poultryEmployeeLoanId}`} · {l.staffName}</>
                )}
                secondary={(l: PoultryEmployeeLoan) => (
                  <>
                    <span>{fmtDate(l.disbursementDate)}</span>
                    <span>·</span>
                    <span className="text-xs">{EMPLOYEE_LOAN_TYPE_LABELS[l.loanType] ?? l.loanType}</span>
                  </>
                )}
                trailing={(l: PoultryEmployeeLoan) => (
                  <Badge className={statusClass(l.status)}>
                    {EMPLOYEE_LOAN_STATUS_LABELS[l.status] ?? l.status}
                  </Badge>
                )}
                highlights={(l: PoultryEmployeeLoan) => [
                  { label: "Outstanding", value: fmt(l.outstandingBalance) },
                  { label: "Advanced", value: fmt(l.principalAmount) },
                ]}
                details={(l: PoultryEmployeeLoan) => [
                  { label: "Total repayable", value: fmt(l.totalRepayable) },
                  { label: "Repaid", value: fmt(l.totalRepaid) },
                  { label: "Repayment", value: EMPLOYEE_LOAN_REPAYMENT_METHOD_LABELS[l.repaymentMethod] ?? l.repaymentMethod },
                  { label: "Suggested per payroll", value: l.defaultPayrollDeduction ? fmt(l.defaultPayrollDeduction) : "—" },
                  { label: "Paid from", value: l.cashAccountName ?? "—" },
                  { label: "Reference", value: l.referenceNumber ?? "—" },
                  { label: "Purpose", value: l.purpose ?? l.description ?? "—" },
                  { label: "Repayments", value: String(l.repaymentCount) },
                ]}
                extra={(l: PoultryEmployeeLoan) => (
                  <div className="space-y-2">
                    <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                      Repayment history
                    </div>
                    <RepaymentHistory
                      rows={historyByLoan.get(l.poultryEmployeeLoanId) ?? []}
                      loading={historyLoading}
                      fmt={fmt}
                      onReverse={(r) => { setReversingRepayment(r); setReason("") }}
                    />
                  </div>
                )}
                actions={(l: PoultryEmployeeLoan) => (
                  <>
                    {l.status === "Draft" && (
                      <Button size="sm" variant="outline" className="flex-1 h-10"
                              onClick={() => setDisburseFor(l)}>
                        <Wallet className="h-4 w-4 mr-1" /> Hand over
                      </Button>
                    )}
                    {l.status === "Active" && (
                      <Button size="sm" variant="outline" className="flex-1 h-10"
                              onClick={() => setRepayFor(l)}>
                        <HandCoins className="h-4 w-4 mr-1" /> Record repayment
                      </Button>
                    )}
                    {l.status === "Draft" && (
                      <Button size="sm" variant="ghost" className="h-10"
                              onClick={() => { setReversingLoan(l); setReason("") }}>
                        Cancel
                      </Button>
                    )}
                    {(l.status === "Active" || l.status === "Paid") && (
                      <Button size="sm" variant="ghost" className="h-10"
                              onClick={() => { setReversingLoan(l); setReason("") }}>
                        <Undo2 className="h-4 w-4 mr-1" /> Reverse
                      </Button>
                    )}
                  </>
                )}
                desktopTable={
                  <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead className="w-8" />
                          <TableHead>Loan #</TableHead>
                          <TableHead>Employee</TableHead>
                          <TableHead>Type</TableHead>
                          <TableHead>Issued</TableHead>
                          <TableHead className="text-right">Advanced</TableHead>
                          <TableHead className="text-right">Repayable</TableHead>
                          <TableHead className="text-right">Repaid</TableHead>
                          <TableHead className="text-right">Outstanding</TableHead>
                          <TableHead>Repayment</TableHead>
                          <TableHead>Status</TableHead>
                          <TableHead className="w-44" />
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {rows.map((l) => {
                          const open = expanded.has(l.poultryEmployeeLoanId)
                          return (
                            <Fragment key={l.poultryEmployeeLoanId}>
                              <TableRow className="cursor-pointer"
                                        onClick={() => setExpanded((prev) => {
                                          const next = new Set(prev)
                                          if (next.has(l.poultryEmployeeLoanId)) next.delete(l.poultryEmployeeLoanId)
                                          else next.add(l.poultryEmployeeLoanId)
                                          return next
                                        })}>
                                <TableCell className="text-slate-400">
                                  {open ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
                                </TableCell>
                                <TableCell className="font-medium whitespace-nowrap">
                                  {l.loanNumber ?? `#${l.poultryEmployeeLoanId}`}
                                </TableCell>
                                <TableCell>{l.staffName}</TableCell>
                                <TableCell className="text-xs">
                                  {EMPLOYEE_LOAN_TYPE_LABELS[l.loanType] ?? l.loanType}
                                </TableCell>
                                <TableCell className="whitespace-nowrap">{fmtDate(l.disbursementDate)}</TableCell>
                                <TableCell className="text-right tabular-nums">{fmt(l.principalAmount)}</TableCell>
                                <TableCell className="text-right tabular-nums">{fmt(l.totalRepayable)}</TableCell>
                                <TableCell className="text-right tabular-nums">{fmt(l.totalRepaid)}</TableCell>
                                <TableCell className="text-right tabular-nums font-semibold">
                                  {fmt(l.outstandingBalance)}
                                </TableCell>
                                <TableCell className="text-xs">
                                  {EMPLOYEE_LOAN_REPAYMENT_METHOD_LABELS[l.repaymentMethod] ?? l.repaymentMethod}
                                </TableCell>
                                <TableCell>
                                  <Badge className={statusClass(l.status)}>
                                    {EMPLOYEE_LOAN_STATUS_LABELS[l.status] ?? l.status}
                                  </Badge>
                                </TableCell>
                                <TableCell onClick={(e) => e.stopPropagation()}>
                                  <div className="flex gap-1 justify-end">
                                    {l.status === "Draft" && (
                                      <Button size="sm" variant="outline" onClick={() => setDisburseFor(l)}>
                                        Hand over
                                      </Button>
                                    )}
                                    {l.status === "Active" && (
                                      <Button size="sm" variant="outline" onClick={() => setRepayFor(l)}>
                                        Repay
                                      </Button>
                                    )}
                                    {l.status !== "Reversed" && l.status !== "Cancelled" && (
                                      <Button size="sm" variant="ghost"
                                              onClick={() => { setReversingLoan(l); setReason("") }}>
                                        <Undo2 className="h-4 w-4" />
                                      </Button>
                                    )}
                                  </div>
                                </TableCell>
                              </TableRow>
                              {open && (
                                <TableRow className="bg-slate-50/60 hover:bg-slate-50/60">
                                  <TableCell colSpan={12} className="p-4">
                                    {/* Section 17: the overview, then the
                                        statement that explains the balance. */}
                                    <OverviewTable loan={l} fmt={fmt} />
                                    <div className="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-1">
                                      Repayment history
                                    </div>
                                    <RepaymentHistory
                                      rows={historyByLoan.get(l.poultryEmployeeLoanId) ?? []}
                                      loading={historyLoading}
                                      fmt={fmt}
                                      onReverse={(r) => { setReversingRepayment(r); setReason("") }}
                                    />
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

              {/* The SERVER's count, not rows.length -- this list is one page. */}
              <div className="mt-3 flex items-center justify-between text-sm text-slate-500">
                <span>Showing {from}–{to} of {total}</span>
                <div className="flex gap-2">
                  <Button size="sm" variant="outline" disabled={offset === 0}
                          onClick={() => setOffset(Math.max(0, offset - PAGE_SIZE))}>
                    Previous
                  </Button>
                  <Button size="sm" variant="outline" disabled={to >= total}
                          onClick={() => setOffset(offset + PAGE_SIZE)}>
                    Next
                  </Button>
                </div>
              </div>
            </>
          )}

          {/* The thing an owner will otherwise work out the hard way. */}
          <Card className="border-sky-200 bg-sky-50 mt-4">
            <CardContent className="p-4 flex items-start gap-2">
              <Info className="h-4 w-4 text-sky-700 mt-0.5 shrink-0" />
              <p className="text-xs text-sky-900">
                Repayments taken from a wage do not show as money coming in, because none did —
                the farm simply paid out less that month. They still reduce what the worker owes.
                To undo one, reopen the payroll run that created it.
              </p>
            </CardContent>
          </Card>
        </main>
      </div>

      <NewLoanDialog
        open={newOpen} onOpenChange={setNewOpen} staff={staff} accounts={accounts}
        busy={busy} fmt={fmt}
        onSave={(input) => run(async () => { await createPoultryEmployeeLoan(input); setNewOpen(false) },
                               "Advance recorded")}
      />

      <DisburseDialog
        loan={disburseFor} onClose={() => setDisburseFor(null)} accounts={accounts} busy={busy} fmt={fmt}
        onSave={(id, input) => run(async () => {
          await disbursePoultryEmployeeLoan(id, input); setDisburseFor(null)
        }, "Advance handed over")}
      />

      <RepayDialog
        loan={repayFor} onClose={() => setRepayFor(null)} accounts={accounts} busy={busy} fmt={fmt}
        onSave={(input) => run(async () => {
          await recordPoultryEmployeeLoanRepayment(input); setRepayFor(null)
        }, "Repayment recorded")}
      />

      {/* One reason dialog for both kinds of undo. */}
      <Dialog open={!!reversingLoan || !!reversingRepayment}
              onOpenChange={(o) => { if (!o) { setReversingLoan(null); setReversingRepayment(null); setReason("") } }}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <AlertTriangle className="h-5 w-5 text-amber-600" />
              {reversingRepayment ? "Reverse this repayment" :
                reversingLoan?.status === "Draft" ? "Cancel this advance" : "Reverse this advance"}
            </DialogTitle>
            <DialogDescription>
              {reversingRepayment
                ? "The repayment stays on the record, marked reversed, and what the worker owes goes back up. Any cash that came in goes back out."
                : reversingLoan?.status === "Draft"
                  ? "Nothing has been handed over, so there is nothing to undo financially."
                  : "The money goes back to the cash account and the claim on the worker disappears. Refused if any repayment is still posted — reverse those first."}
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            <Label>Reason</Label>
            <Textarea value={reason} onChange={(e) => setReason(e.target.value)}
                      placeholder="Why is this being undone?" />
          </div>
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline"
                    onClick={() => { setReversingLoan(null); setReversingRepayment(null); setReason("") }}>
              Keep it
            </Button>
            <Button
              disabled={busy}
              onClick={() => {
                const rep = reversingRepayment
                const loan = reversingLoan
                void run(async () => {
                  if (rep) {
                    await reversePoultryEmployeeLoanRepayment(rep.poultryEmployeeLoanRepaymentId, reason || null)
                  } else if (loan) {
                    if (loan.status === "Draft") await cancelPoultryEmployeeLoan(loan.poultryEmployeeLoanId, reason || null)
                    else await reversePoultryEmployeeLoan(loan.poultryEmployeeLoanId, reason || null)
                  }
                  setReversingLoan(null); setReversingRepayment(null); setReason("")
                }, "Done")
              }}>
              {busy && <Loader2 className="h-4 w-4 mr-1 animate-spin" />} Undo it
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}

// ---------------------------------------------------------------------------
function NewLoanDialog({
  open, onOpenChange, staff, accounts, busy, fmt, onSave,
}: {
  open: boolean
  onOpenChange: (o: boolean) => void
  staff: PoultryStaff[]
  accounts: PoultryCashAccount[]
  busy: boolean
  fmt: (n: number) => string
  onSave: (input: any) => Promise<boolean>
}) {
  const [f, setF] = useState({
    poultryStaffId: 0, loanType: "EmployeeLoan", principalAmount: 0,
    disbursementDate: today(), purpose: "", notes: "",
    repaymentMethod: "PayrollDeduction", defaultPayrollDeduction: 0,
    interestEnabled: false, interestAmount: 0,
    disburseNow: true, poultryCashAccountId: 0, paymentMethod: "Cash", referenceNumber: "",
  })
  useEffect(() => {
    if (open) setF((p) => ({ ...p, poultryStaffId: 0, principalAmount: 0, purpose: "", notes: "", referenceNumber: "" }))
  }, [open])

  const totalRepayable = f.principalAmount + (f.interestEnabled ? f.interestAmount : 0)
  const canSave = f.poultryStaffId > 0 && f.principalAmount > 0 &&
                  (!f.disburseNow || f.poultryCashAccountId > 0)

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <HandCoins className="h-5 w-5 text-indigo-600" /> New loan or advance
          </DialogTitle>
          <DialogDescription>
            This is money the worker will owe you. It is not a cost, and it does not touch
            Profit &amp; Loss.
          </DialogDescription>
        </DialogHeader>

        <div className="grid gap-3 sm:grid-cols-2">
          <div className="space-y-1">
            <Label>Employee *</Label>
            <Select value={f.poultryStaffId ? String(f.poultryStaffId) : ""}
                    onValueChange={(v) => setF({ ...f, poultryStaffId: Number(v) })}>
              <SelectTrigger><SelectValue placeholder="Choose a member of staff" /></SelectTrigger>
              <SelectContent>
                {staff.map((s) => (
                  <SelectItem key={s.poultryStaffId} value={String(s.poultryStaffId)}>
                    {s.firstName} {s.lastName} — {s.role}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1">
            <Label>Type *</Label>
            <Select value={f.loanType} onValueChange={(v) => setF({ ...f, loanType: v })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {EMPLOYEE_LOAN_TYPES.map((t) => (
                  <SelectItem key={t} value={t}>{EMPLOYEE_LOAN_TYPE_LABELS[t]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1">
            <Label>Amount *</Label>
            <NumberInput step="0.01" value={f.principalAmount}
                         onChange={(e) => setF({ ...f, principalAmount: Number(e.target.value) || 0 })} />
          </div>
          <div className="space-y-1">
            <Label>Date *</Label>
            <Input type="date" value={f.disbursementDate}
                   onChange={(e) => setF({ ...f, disbursementDate: e.target.value })} />
          </div>
          <div className="space-y-1">
            <Label>How will it be repaid?</Label>
            <Select value={f.repaymentMethod} onValueChange={(v) => setF({ ...f, repaymentMethod: v })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {EMPLOYEE_LOAN_REPAYMENT_METHODS.map((m) => (
                  <SelectItem key={m} value={m}>{EMPLOYEE_LOAN_REPAYMENT_METHOD_LABELS[m]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1">
            <Label>Suggested amount per payroll</Label>
            <NumberInput step="0.01" value={f.defaultPayrollDeduction}
                         onChange={(e) => setF({ ...f, defaultPayrollDeduction: Number(e.target.value) || 0 })} />
            {/* Section 36: a suggestion, never an instruction. */}
            <p className="text-[11px] text-slate-500">
              Offered when preparing payroll. Nothing is deducted automatically.
            </p>
          </div>
          <div className="sm:col-span-2 space-y-1">
            <Label>Purpose</Label>
            <Input value={f.purpose} onChange={(e) => setF({ ...f, purpose: e.target.value })}
                   placeholder="School fees, medical, rent…" />
          </div>

          <div className="sm:col-span-2 flex items-center justify-between rounded-md border p-3">
            <div>
              <Label className="text-sm">Charge interest</Label>
              <p className="text-[11px] text-slate-500">Most farm advances are interest-free.</p>
            </div>
            <Switch checked={f.interestEnabled}
                    onCheckedChange={(v) => setF({ ...f, interestEnabled: v })} />
          </div>
          {f.interestEnabled && (
            <div className="space-y-1">
              <Label>Interest amount</Label>
              <NumberInput step="0.01" value={f.interestAmount}
                           onChange={(e) => setF({ ...f, interestAmount: Number(e.target.value) || 0 })} />
            </div>
          )}

          <div className="sm:col-span-2 rounded-md bg-slate-50 p-3 text-sm">
            Total the worker will owe: <strong className="tabular-nums">{fmt(totalRepayable)}</strong>
          </div>

          <div className="sm:col-span-2 flex items-center justify-between rounded-md border p-3">
            <div>
              <Label className="text-sm">Hand the money over now</Label>
              <p className="text-[11px] text-slate-500">
                Off records the agreement only — nothing leaves the cash account and the worker
                owes nothing yet.
              </p>
            </div>
            <Switch checked={f.disburseNow} onCheckedChange={(v) => setF({ ...f, disburseNow: v })} />
          </div>

          {f.disburseNow && (
            <>
              <div className="space-y-1">
                <Label>Pay from *</Label>
                <Select value={f.poultryCashAccountId ? String(f.poultryCashAccountId) : ""}
                        onValueChange={(v) => setF({ ...f, poultryCashAccountId: Number(v) })}>
                  <SelectTrigger><SelectValue placeholder="Choose a cash account" /></SelectTrigger>
                  <SelectContent>
                    {accounts.map((a: any) => (
                      <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>
                        {a.accountName} — {fmt(a.currentBalance ?? 0)}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1">
                <Label>Reference</Label>
                <Input value={f.referenceNumber}
                       onChange={(e) => setF({ ...f, referenceNumber: e.target.value })}
                       placeholder="MoMo ID, voucher number…" />
              </div>
            </>
          )}
        </div>

        <div className="flex justify-end gap-2 pt-2">
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button disabled={busy || !canSave} onClick={() => void onSave({
            poultryStaffId: f.poultryStaffId,
            loanType: f.loanType,
            principalAmount: f.principalAmount,
            disbursementDate: f.disbursementDate,
            purpose: f.purpose || null,
            notes: f.notes || null,
            repaymentMethod: f.repaymentMethod,
            defaultPayrollDeduction: f.defaultPayrollDeduction || null,
            interestEnabled: f.interestEnabled,
            interestAmount: f.interestEnabled ? f.interestAmount : 0,
            disburseNow: f.disburseNow,
            poultryCashAccountId: f.disburseNow ? f.poultryCashAccountId : null,
            paymentMethod: f.disburseNow ? f.paymentMethod : null,
            referenceNumber: f.referenceNumber || null,
          })}>
            {busy && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}
            {f.disburseNow ? "Record and hand over" : "Record only"}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}

// ---------------------------------------------------------------------------
function DisburseDialog({
  loan, onClose, accounts, busy, fmt, onSave,
}: {
  loan: PoultryEmployeeLoan | null
  onClose: () => void
  accounts: PoultryCashAccount[]
  busy: boolean
  fmt: (n: number) => string
  onSave: (id: number, input: any) => Promise<boolean>
}) {
  const [accountId, setAccountId] = useState(0)
  const [reference, setReference] = useState("")
  useEffect(() => { if (loan) { setAccountId(0); setReference("") } }, [loan])
  if (!loan) return null

  return (
    <Dialog open onOpenChange={(o) => { if (!o) onClose() }}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Hand over {fmt(loan.principalAmount)}</DialogTitle>
          <DialogDescription>
            To {loan.staffName}. The cash leaves the account and {loan.staffName} will owe{" "}
            {fmt(loan.totalRepayable)}. No expense is recorded.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div className="space-y-1">
            <Label>Pay from *</Label>
            <Select value={accountId ? String(accountId) : ""} onValueChange={(v) => setAccountId(Number(v))}>
              <SelectTrigger><SelectValue placeholder="Choose a cash account" /></SelectTrigger>
              <SelectContent>
                {accounts.map((a: any) => (
                  <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>
                    {a.accountName} — {fmt(a.currentBalance ?? 0)}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1">
            <Label>Reference</Label>
            <Input value={reference} onChange={(e) => setReference(e.target.value)} />
          </div>
        </div>
        <div className="flex justify-end gap-2 pt-2">
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button disabled={busy || accountId <= 0}
                  onClick={() => void onSave(loan.poultryEmployeeLoanId, {
                    poultryCashAccountId: accountId,
                    paymentMethod: "Cash",
                    referenceNumber: reference || null,
                  })}>
            {busy && <Loader2 className="h-4 w-4 mr-1 animate-spin" />} Hand it over
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}

// ---------------------------------------------------------------------------
// Section 23. The employee is not asked for -- it is the advance's own, and a
// repayment against someone else's advance is refused by the server anyway.
function RepayDialog({
  loan, onClose, accounts, busy, fmt, onSave,
}: {
  loan: PoultryEmployeeLoan | null
  onClose: () => void
  accounts: PoultryCashAccount[]
  busy: boolean
  fmt: (n: number) => string
  onSave: (input: any) => Promise<boolean>
}) {
  const [amount, setAmount] = useState(0)
  const [source, setSource] = useState<string>("ManualCash")
  const [accountId, setAccountId] = useState(0)
  const [date, setDate] = useState(today())
  const [reference, setReference] = useState("")
  useEffect(() => {
    if (loan) { setAmount(0); setSource("ManualCash"); setAccountId(0); setDate(today()); setReference("") }
  }, [loan])
  if (!loan) return null

  const over = amount > loan.outstandingBalance
  const left = Math.max(loan.outstandingBalance - amount, 0)

  return (
    <Dialog open onOpenChange={(o) => { if (!o) onClose() }}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Record a repayment</DialogTitle>
          <DialogDescription>
            {loan.staffName} · {loan.loanNumber} · {fmt(loan.outstandingBalance)} outstanding.
            Money the worker hands over — a payroll deduction is added on the payroll run instead.
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-3 sm:grid-cols-2">
          <div className="space-y-1">
            <Label>Amount *</Label>
            <NumberInput step="0.01" value={amount}
                         onChange={(e) => setAmount(Number(e.target.value) || 0)} />
            {over && (
              <p className="text-[11px] text-rose-600">
                More than the {fmt(loan.outstandingBalance)} still owed.
              </p>
            )}
          </div>
          <div className="space-y-1">
            <Label>Date</Label>
            <Input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
          </div>
          <div className="space-y-1">
            <Label>How *</Label>
            <Select value={source} onValueChange={setSource}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {EMPLOYEE_LOAN_REPAYMENT_SOURCES.map((s) => (
                  <SelectItem key={s} value={s}>{EMPLOYEE_LOAN_SOURCE_LABELS[s]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1">
            <Label>Into *</Label>
            <Select value={accountId ? String(accountId) : ""} onValueChange={(v) => setAccountId(Number(v))}>
              <SelectTrigger><SelectValue placeholder="Cash account" /></SelectTrigger>
              <SelectContent>
                {accounts.map((a: any) => (
                  <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>
                    {a.accountName}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="sm:col-span-2 space-y-1">
            <Label>Reference</Label>
            <Input value={reference} onChange={(e) => setReference(e.target.value)}
                   placeholder="MoMo ID, receipt number…" />
          </div>
          <div className="sm:col-span-2 rounded-md bg-slate-50 p-3 text-sm">
            Still owed afterwards: <strong className="tabular-nums">{fmt(left)}</strong>
          </div>
        </div>
        <div className="flex justify-end gap-2 pt-2">
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button disabled={busy || amount <= 0 || over || accountId <= 0}
                  onClick={() => void onSave({
                    poultryEmployeeLoanId: loan.poultryEmployeeLoanId,
                    amount,
                    sourceType: source,
                    repaymentDate: date,
                    poultryCashAccountId: accountId,
                    referenceNumber: reference || null,
                  })}>
            {busy && <Loader2 className="h-4 w-4 mr-1 animate-spin" />} Record it
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}

// ---------------------------------------------------------------------------
function Stat({
  label, value, hint, accent = "slate",
}: {
  label: string
  value: string
  hint?: string
  accent?: "slate" | "emerald" | "rose" | "indigo"
}) {
  const colour = {
    slate: "text-slate-900",
    emerald: "text-emerald-700",
    rose: "text-rose-600",
    indigo: "text-indigo-700",
  }[accent]
  return (
    <Card>
      <CardContent className="p-4">
        <p className="text-xs font-medium text-slate-500 uppercase tracking-wider truncate">{label}</p>
        <div className={`text-lg sm:text-xl font-bold mt-1 truncate ${colour}`}>{value}</div>
        {hint && <div className="text-xs text-slate-500 mt-0.5 truncate">{hint}</div>}
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// The advance's own facts (section 17).
//
// Headed columns with the values in a row underneath -- the same shape as the
// list above it, so the expanded area reads as more of the same table rather
// than as a different kind of thing that happens to be nested inside one.
//
// Notes and the reversal reason are NOT columns. They are free text of
// unbounded length, and one long note would stretch a column that six short
// facts have to share. They go underneath, and only when they exist.
// ---------------------------------------------------------------------------
function OverviewTable({ loan, fmt }: { loan: PoultryEmployeeLoan; fmt: (n: number) => string }) {
  const cols: { head: string; value: string }[] = [
    { head: "Purpose", value: loan.purpose ?? loan.description ?? "—" },
    { head: "Interest", value: loan.interestEnabled ? fmt(loan.interestAmount) : "None" },
    { head: "Suggested per payroll",
      value: loan.defaultPayrollDeduction ? fmt(loan.defaultPayrollDeduction) : "—" },
    { head: "Paid from", value: loan.cashAccountName ?? "—" },
    { head: "Reference", value: loan.referenceNumber ?? "—" },
    { head: "Handed over", value: fmtDate(loan.disbursedAt) },
  ]

  return (
    <div className="mb-3">
      <div className="overflow-hidden rounded-md border border-slate-200 bg-white">
        <Table>
          <TableHeader>
            <TableRow className="hover:bg-transparent">
              {cols.map((c) => (
                <TableHead key={c.head} className="whitespace-nowrap">{c.head}</TableHead>
              ))}
            </TableRow>
          </TableHeader>
          <TableBody>
            <TableRow className="hover:bg-transparent">
              {cols.map((c) => (
                // whitespace-normal: TableCell ships whitespace-nowrap, which
                // would push a long purpose through the column beside it.
                <TableCell key={c.head}
                           className="text-sm break-words whitespace-normal text-slate-900">
                  {c.value}
                </TableCell>
              ))}
            </TableRow>
          </TableBody>
        </Table>
      </div>

      {(loan.notes || loan.reversalReason) && (
        <div className="mt-2 space-y-1 px-1 text-sm">
          {loan.notes && (
            <p><span className="text-slate-500">Notes: </span>{loan.notes}</p>
          )}
          {loan.reversalReason && (
            <p><span className="text-slate-500">Reversal reason: </span>{loan.reversalReason}</p>
          )}
        </div>
      )}
    </div>
  )
}
