"use client"

// Employee Loans & Advances, water side.
//
// The poultry twin is app/poultry-employee-loans/page.tsx. Same page, same
// rules; the two company types keep separate tables, so they keep separate
// pages rather than one that branches on farm type.
//
// Money the company has LENT TO ITS STAFF: what went out, what has come back, and
// how each repayment was made.
//
// THE TWO THINGS THIS PAGE MUST TEACH
// -----------------------------------
// 1. AN ADVANCE IS NOT A COST. Handing a worker 2,000 does not make the company
//    2,000 poorer -- it swaps cash for a claim on that worker. It never reaches
//    the Profit & Loss, and a salary advance is not payroll expense until it is
//    earned. The page says so under the heading, because "where did my profit
//    go" is the question an advance provokes.
//
// 2. A PAYROLL DEDUCTION IS NOT A RECEIPT. When 100 is withheld from a 2,200
//    wage, the company pays out 2,100. No money arrives, so no cash account moves
//    and Cash Flow shows nothing -- the receivable simply comes down. The
//    repayment history labels those rows "Payroll" with no account, and the
//    reverse button is deliberately absent on them: undoing one means reopening
//    the payroll that created it, which is the only thing that can put the
//    payslip and the advance back in step (spec section 60).
//
// WHY THE LIST IS SERVER-PAGED
// ----------------------------
// A company that has been running for years has more advances than a browser
// should hold, and every filter here is applied in SQL rather than over a list
// pulled down whole (sections 70-72). That is also why the count under the
// table is the SERVER's count, not `rows.length`.

import { useCallback, useEffect, useState } from "react"
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
  HandCoins, Loader2, Plus, Undo2, Wallet, Users, AlertTriangle, Info, Eye,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import {
  listWaterCashAccounts, listWaterStaff,
  listWaterEmployeeLoans, getWaterEmployeeLoanSummary,
  listWaterEmployeeLoanRepayments,
  createWaterEmployeeLoan, disburseWaterEmployeeLoan,
  cancelWaterEmployeeLoan, reverseWaterEmployeeLoan,
  recordWaterEmployeeLoanRepayment, reverseWaterEmployeeLoanRepayment,
  EMPLOYEE_LOAN_TYPES, EMPLOYEE_LOAN_TYPE_LABELS,
  EMPLOYEE_LOAN_REPAYMENT_METHODS, EMPLOYEE_LOAN_REPAYMENT_METHOD_LABELS,
  EMPLOYEE_LOAN_REPAYMENT_SOURCES, EMPLOYEE_LOAN_SOURCE_LABELS,
  EMPLOYEE_LOAN_STATUS_LABELS,
  type WaterEmployeeLoan, type WaterEmployeeLoanRepayment,
  type WaterEmployeeLoanSummary, type WaterCashAccount, type WaterStaff,
} from "@/lib/api/water"

const PAGE_SIZE = 25
const today = () => new Date().toISOString().slice(0, 10)
const fmtDate = (d?: string | null) => (d ? String(d).slice(0, 10) : "—")

/** Active / Paid / All — the three anyone actually asks for (section 70). */
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
  rows: WaterEmployeeLoanRepayment[]
  loading: boolean
  fmt: (n: number) => string
  onReverse: (r: WaterEmployeeLoanRepayment) => void
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
    // The same bordered white panel the facts grid above it sits in, so the
    // dialog reads as two blocks of one record rather than a grid with a loose
    // table under it.
    //
    // overflow-x-auto, NOT overflow-hidden. Eight columns do not fit a phone,
    // and hidden does not shrink them -- it CLIPS them, silently taking the
    // balance-after column and the reverse button off the right-hand edge of a
    // statement whose whole job is to be reconcilable. It scrolls sideways
    // instead. (overflow-x-auto still clips the corners the border rounds.)
    <div className="overflow-x-auto rounded-md border border-slate-200 bg-white">
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
              <TableRow key={r.waterEmployeeLoanRepaymentId}
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
                        : `Payroll run ${r.waterPayrollRunId ?? "—"}`)
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
export default function WaterEmployeeLoansPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") router.replace("/dashboard")
  }, [activeFarmType, router])

  const [rows, setRows] = useState<WaterEmployeeLoan[]>([])
  const [total, setTotal] = useState(0)
  const [summary, setSummary] = useState<WaterEmployeeLoanSummary | null>(null)
  const [staff, setStaff] = useState<WaterStaff[]>([])
  const [accounts, setAccounts] = useState<WaterCashAccount[]>([])
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
    useState<Map<number, WaterEmployeeLoanRepayment[]>>(new Map())
  const [historyLoading, setHistoryLoading] = useState(false)
  /**
   * The advance whose detail is open, or null.
   *
   * ONE dialog, not a set of expanded rows. The detail is an overview plus a
   * repayment statement -- two tables -- and unfolding that inside the list
   * pushed every other advance off the screen, so comparing the row you opened
   * with the one below it meant closing it again. A reader who opens a detail
   * is asking about ONE advance; the list stays where it was behind it.
   */
  const [detailFor, setDetailFor] = useState<WaterEmployeeLoan | null>(null)

  const load = useCallback(async () => {
    setError("")
    try {
      const [page, sum] = await Promise.all([
        listWaterEmployeeLoans({
          status: status || null,
          search: search || null,
          staffId: staffId === "ALL" ? null : Number(staffId),
          loanType: loanType === "ALL" ? null : loanType,
          limit: PAGE_SIZE,
          offset,
        }),
        getWaterEmployeeLoanSummary(),
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
        const [s, a] = await Promise.all([listWaterStaff(), listWaterCashAccounts()])
        setStaff(s.filter((x) => x.isActive && !x.isDeleted))
        setAccounts(a)
      } catch { /* the page still works without the pickers pre-filled */ }
    })()
  }, [])

  const loadHistories = useCallback(async (list: WaterEmployeeLoan[]) => {
    if (list.length === 0) { setHistoryByLoan(new Map()); return }
    setHistoryLoading(true)
    try {
      const pairs = await Promise.all(list.map(async (l) => {
        // One advance failing to load its statement must not blank the other
        // twenty-four, so each settles on its own.
        try {
          return [l.waterEmployeeLoanId,
                  await listWaterEmployeeLoanRepayments(l.waterEmployeeLoanId)] as const
        } catch {
          return [l.waterEmployeeLoanId, [] as WaterEmployeeLoanRepayment[]] as const
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
  const [repayFor, setRepayFor] = useState<WaterEmployeeLoan | null>(null)
  const [disburseFor, setDisburseFor] = useState<WaterEmployeeLoan | null>(null)
  const [reversingLoan, setReversingLoan] = useState<WaterEmployeeLoan | null>(null)
  const [reversingRepayment, setReversingRepayment] =
    useState<WaterEmployeeLoanRepayment | null>(null)
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
                <Link href="/water-payroll">Payroll</Link>
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
                  hint="What staff still owe the company" accent="indigo" />
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
                  <SelectItem key={s.waterStaffId} value={String(s.waterStaffId)}>
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
                /* Open on arrival. The card's own tiles answer "how much?" while
                   it is shut, but the rest -- what it was for, what account it
                   came out of, how it is being repaid -- is why a reader came to
                   this page at all, and a stack of shut cards makes them tap
                   every one to find the advance they meant. defaultOpen rather
                   than alwaysExpanded, so the "View table format" toggle stays. */
                defaultOpen
                items={rows}
                getKey={(l: WaterEmployeeLoan) => l.waterEmployeeLoanId}
                primary={(l: WaterEmployeeLoan) => (
                  <>{l.loanNumber ?? `#${l.waterEmployeeLoanId}`} · {l.staffName}</>
                )}
                secondary={(l: WaterEmployeeLoan) => (
                  <>
                    <span>{fmtDate(l.disbursementDate)}</span>
                    <span>·</span>
                    <span className="text-xs">{EMPLOYEE_LOAN_TYPE_LABELS[l.loanType] ?? l.loanType}</span>
                  </>
                )}
                trailing={(l: WaterEmployeeLoan) => (
                  <Badge className={statusClass(l.status)}>
                    {EMPLOYEE_LOAN_STATUS_LABELS[l.status] ?? l.status}
                  </Badge>
                )}
                /* Tinted, and in the colours the four Stat cards at the top
                   of the page already use for the same three figures -- blue
                   for what is still owed, rose for money out, emerald for money
                   back. A grey tile beside a grey tile makes the reader work
                   out which number is the one they came for.

                   Outstanding spans the row because it IS the one they came
                   for: it is the bold column on the desktop table for the same
                   reason. */
                highlights={(l: WaterEmployeeLoan) => [
                  { label: "Outstanding", value: fmt(l.outstandingBalance), accent: "blue" as const, wide: true },
                  { label: "Advanced", value: fmt(l.principalAmount), accent: "rose" as const },
                  { label: "Repaid", value: fmt(l.totalRepaid), accent: "emerald" as const },
                ]}
                details={(l: WaterEmployeeLoan) => [
                  { label: "Total repayable", value: fmt(l.totalRepayable) },
                  { label: "Repayment", value: EMPLOYEE_LOAN_REPAYMENT_METHOD_LABELS[l.repaymentMethod] ?? l.repaymentMethod },
                  { label: "Suggested per payroll", value: l.defaultPayrollDeduction ? fmt(l.defaultPayrollDeduction) : "—" },
                  { label: "Paid from", value: l.cashAccountName ?? "—" },
                  { label: "Reference", value: l.referenceNumber ?? "—" },
                  { label: "Purpose", value: l.purpose ?? l.description ?? "—" },
                  { label: "Repayments", value: String(l.repaymentCount) },
                ]}
                actions={(l: WaterEmployeeLoan) => (
                  <>
                    {/* First, and on every card whatever the status: looking is
                        the one thing you can always do to an advance. */}
                    <Button size="sm" variant="outline" className="flex-1 basis-32 h-10"
                            onClick={() => setDetailFor(l)}>
                      <Eye className="h-4 w-4 mr-1" /> Details
                    </Button>
                    {l.status === "Draft" && (
                      <Button size="sm" variant="outline" className="flex-1 basis-32 h-10"
                              onClick={() => setDisburseFor(l)}>
                        <Wallet className="h-4 w-4 mr-1" /> Hand over
                      </Button>
                    )}
                    {l.status === "Active" && (
                      <Button size="sm" variant="outline" className="flex-1 basis-32 h-10"
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
                          <TableHead className="w-52" />
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {rows.map((l) => {
                          return (
                            <TableRow key={l.waterEmployeeLoanId} className="cursor-pointer"
                                      onClick={() => setDetailFor(l)}>
                              <TableCell className="font-medium whitespace-nowrap">
                                {l.loanNumber ?? `#${l.waterEmployeeLoanId}`}
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
                                  {/* The row itself opens this too. The button
                                      is what makes it reachable by keyboard --
                                      a clickable <tr> is not focusable -- and
                                      what tells a reader the row does
                                      anything at all. */}
                                  <Button size="sm" variant="ghost" onClick={() => setDetailFor(l)}>
                                    <Eye className="h-4 w-4" />
                                  </Button>
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
                the company simply paid out less that month. They still reduce what the worker owes.
                To undo one, reopen the payroll run that created it.
              </p>
            </CardContent>
          </Card>
        </main>
      </div>

      <NewLoanDialog
        open={newOpen} onOpenChange={setNewOpen} staff={staff} accounts={accounts}
        busy={busy} fmt={fmt}
        onSave={(input) => run(async () => { await createWaterEmployeeLoan(input); setNewOpen(false) },
                               "Advance recorded")}
      />

      <DisburseDialog
        loan={disburseFor} onClose={() => setDisburseFor(null)} accounts={accounts} busy={busy} fmt={fmt}
        onSave={(id, input) => run(async () => {
          await disburseWaterEmployeeLoan(id, input); setDisburseFor(null)
        }, "Advance handed over")}
      />

      <RepayDialog
        loan={repayFor} onClose={() => setRepayFor(null)} accounts={accounts} busy={busy} fmt={fmt}
        onSave={(input) => run(async () => {
          await recordWaterEmployeeLoanRepayment(input); setRepayFor(null)
        }, "Repayment recorded")}
      />

      <LoanDetailDialog
        loan={detailFor}
        onClose={() => setDetailFor(null)}
        rows={detailFor ? historyByLoan.get(detailFor.waterEmployeeLoanId) ?? [] : []}
        loading={historyLoading}
        fmt={fmt}
        onReverse={(r) => { setReversingRepayment(r); setReason("") }}
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
          <div className="flex flex-col-reverse gap-2 pt-2 sm:flex-row sm:justify-end">
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
                    await reverseWaterEmployeeLoanRepayment(rep.waterEmployeeLoanRepaymentId, reason || null)
                  } else if (loan) {
                    if (loan.status === "Draft") await cancelWaterEmployeeLoan(loan.waterEmployeeLoanId, reason || null)
                    else await reverseWaterEmployeeLoan(loan.waterEmployeeLoanId, reason || null)
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
  staff: WaterStaff[]
  accounts: WaterCashAccount[]
  busy: boolean
  fmt: (n: number) => string
  onSave: (input: any) => Promise<boolean>
}) {
  const [f, setF] = useState({
    waterStaffId: 0, loanType: "EmployeeLoan", principalAmount: 0,
    disbursementDate: today(), purpose: "", notes: "",
    repaymentMethod: "PayrollDeduction", defaultPayrollDeduction: 0,
    interestEnabled: false, interestAmount: 0,
    disburseNow: true, waterCashAccountId: 0, paymentMethod: "Cash", referenceNumber: "",
  })
  useEffect(() => {
    if (open) setF((p) => ({ ...p, waterStaffId: 0, principalAmount: 0, purpose: "", notes: "", referenceNumber: "" }))
  }, [open])

  const totalRepayable = f.principalAmount + (f.interestEnabled ? f.interestAmount : 0)
  const canSave = f.waterStaffId > 0 && f.principalAmount > 0 &&
                  (!f.disburseNow || f.waterCashAccountId > 0)

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
            <Select value={f.waterStaffId ? String(f.waterStaffId) : ""}
                    onValueChange={(v) => setF({ ...f, waterStaffId: Number(v) })}>
              <SelectTrigger><SelectValue placeholder="Choose a member of staff" /></SelectTrigger>
              <SelectContent>
                {staff.map((s) => (
                  <SelectItem key={s.waterStaffId} value={String(s.waterStaffId)}>
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
              <p className="text-[11px] text-slate-500">Most staff advances are interest-free.</p>
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
                <Select value={f.waterCashAccountId ? String(f.waterCashAccountId) : ""}
                        onValueChange={(v) => setF({ ...f, waterCashAccountId: Number(v) })}>
                  <SelectTrigger><SelectValue placeholder="Choose a cash account" /></SelectTrigger>
                  <SelectContent>
                    {accounts.map((a: any) => (
                      <SelectItem key={a.waterCashAccountId} value={String(a.waterCashAccountId)}>
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

        <div className="flex flex-col-reverse gap-2 pt-2 sm:flex-row sm:justify-end">
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button disabled={busy || !canSave} onClick={() => void onSave({
            waterStaffId: f.waterStaffId,
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
            waterCashAccountId: f.disburseNow ? f.waterCashAccountId : null,
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
  loan: WaterEmployeeLoan | null
  onClose: () => void
  accounts: WaterCashAccount[]
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
                  <SelectItem key={a.waterCashAccountId} value={String(a.waterCashAccountId)}>
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
        <div className="flex flex-col-reverse gap-2 pt-2 sm:flex-row sm:justify-end">
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button disabled={busy || accountId <= 0}
                  onClick={() => void onSave(loan.waterEmployeeLoanId, {
                    waterCashAccountId: accountId,
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
  loan: WaterEmployeeLoan | null
  onClose: () => void
  accounts: WaterCashAccount[]
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
                  <SelectItem key={a.waterCashAccountId} value={String(a.waterCashAccountId)}>
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
        <div className="flex flex-col-reverse gap-2 pt-2 sm:flex-row sm:justify-end">
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button disabled={busy || amount <= 0 || over || accountId <= 0}
                  onClick={() => void onSave({
                    waterEmployeeLoanId: loan.waterEmployeeLoanId,
                    amount,
                    sourceType: source,
                    repaymentDate: date,
                    waterCashAccountId: accountId,
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
// A label/value GRID, not the headed table this used to be. As six columns it
// was shaped to match the list it was nested inside; in a dialog there is no
// list to match, and six headed columns in a modal give every fact the same
// narrow share of the width whether it reads "None" or carries a two-line
// purpose.
//
// Notes and the reversal reason are still not part of the grid. They are free
// text of unbounded length, and one long note would stretch a cell the short
// facts have to share. They go underneath, and only when they exist.
// ---------------------------------------------------------------------------
function LoanFacts({ loan, fmt }: { loan: WaterEmployeeLoan; fmt: (n: number) => string }) {
  const facts: { head: string; value: string }[] = [
    { head: "Purpose", value: loan.purpose ?? loan.description ?? "—" },
    { head: "Interest", value: loan.interestEnabled ? fmt(loan.interestAmount) : "None" },
    { head: "Suggested per payroll",
      value: loan.defaultPayrollDeduction ? fmt(loan.defaultPayrollDeduction) : "—" },
    { head: "Paid from", value: loan.cashAccountName ?? "—" },
    { head: "Reference", value: loan.referenceNumber ?? "—" },
    { head: "Handed over", value: fmtDate(loan.disbursedAt) },
  ]

  return (
    <div>
      <div className="grid gap-x-6 gap-y-3 rounded-md border border-slate-200 bg-white p-4 sm:grid-cols-2 lg:grid-cols-3">
        {facts.map((f) => (
          <div key={f.head} className="min-w-0">
            <div className="text-[11px] uppercase tracking-wide text-slate-500">{f.head}</div>
            <div className="text-sm break-words text-slate-900">{f.value}</div>
          </div>
        ))}
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

// ---------------------------------------------------------------------------
// Everything about one advance, in a dialog.
//
// The money first, because "what is still owed" is why the detail was opened;
// then the facts of the advance; then the statement that explains the balance.
//
// The repayment rows come from the page's own history map rather than a fetch
// of their own -- the page already holds the history for every advance on the
// current page, so opening a detail costs nothing and shows no spinner.
// ---------------------------------------------------------------------------
function LoanDetailDialog({
  loan, onClose, rows, loading, fmt, onReverse,
}: {
  loan: WaterEmployeeLoan | null
  onClose: () => void
  rows: WaterEmployeeLoanRepayment[]
  loading: boolean
  fmt: (n: number) => string
  onReverse: (r: WaterEmployeeLoanRepayment) => void
}) {
  if (!loan) return null

  const money = [
    { label: "Advanced", value: fmt(loan.principalAmount) },
    { label: "Repayable", value: fmt(loan.totalRepayable) },
    { label: "Repaid", value: fmt(loan.totalRepaid) },
    { label: "Outstanding", value: fmt(loan.outstandingBalance), strong: true },
  ]

  return (
    <Dialog open onOpenChange={(o) => { if (!o) onClose() }}>
      {/* Only the desktop cap is set here. DialogContent already ships
          w-full, max-w-[calc(100%-2rem)], max-h-[90vh] and overflow-y-auto, so
          a phone gets a full-width sheet that scrolls, and repeating those
          would just be four classes to keep in step with the shared one. */}
      <DialogContent className="sm:max-w-5xl">
        <DialogHeader>
          <DialogTitle className="flex flex-wrap items-center gap-2">
            {loan.loanNumber ?? `#${loan.waterEmployeeLoanId}`}
            <span className="text-slate-400">·</span>
            {loan.staffName}
            <Badge className={statusClass(loan.status)}>
              {EMPLOYEE_LOAN_STATUS_LABELS[loan.status] ?? loan.status}
            </Badge>
          </DialogTitle>
          <DialogDescription>
            {EMPLOYEE_LOAN_TYPE_LABELS[loan.loanType] ?? loan.loanType}
            {" · issued "}{fmtDate(loan.disbursementDate)}
            {" · repaid by "}
            {EMPLOYEE_LOAN_REPAYMENT_METHOD_LABELS[loan.repaymentMethod] ?? loan.repaymentMethod}
          </DialogDescription>
        </DialogHeader>

        {/* min-w-0: DialogContent is a GRID, and a grid item is min-width
            auto -- so without this the repayment table below stretches the
            dialog itself instead of scrolling inside its own panel, and the
            whole sheet runs off the side of a phone. */}
        <div className="min-w-0 space-y-4">
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            {money.map((m) => (
              <div key={m.label} className="rounded-md border border-slate-200 bg-white p-3">
                <div className="text-[11px] uppercase tracking-wide text-slate-500">{m.label}</div>
                <div className={cn("mt-0.5 text-base sm:text-lg tabular-nums break-words",
                                   m.strong ? "font-bold text-slate-900" : "font-semibold text-slate-700")}>
                  {m.value}
                </div>
              </div>
            ))}
          </div>

          <LoanFacts loan={loan} fmt={fmt} />

          <div>
            <div className="mb-1 text-xs font-semibold uppercase tracking-wide text-slate-500">
              Repayment history
            </div>
            <RepaymentHistory rows={rows} loading={loading} fmt={fmt} onReverse={onReverse} />
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}
