"use client"

// Employee Loans & Advances for Generic businesses.
// Adapted from the Poultry employee loans page — same UX, Generic data model.

import { CANCEL_REASONS, LOAN_REVERSAL_REASONS } from "@/lib/reversal-reasons"
import { ReasonSelect } from "@/components/ui/reason-select"
import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
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
import { ProjectFilter } from "@/components/generic/projects/project-filter"
import { ProjectCell, ProjectHead, ProjectLabels, PROJECT_COLUMN_TITLE } from "@/components/generic/projects/project-column"
import { SingleProjectField, EMPTY_SINGLE_PROJECT, singleAssignment, type SingleProjectValue } from "@/components/generic/projects/form-project-field"
import { useProjectTeam } from "@/components/generic/projects/use-project-team"
import { useProjectLabels } from "@/hooks/use-project-labels"
import { ALL_PROJECTS, type ProjectFilterValue } from "@/lib/generic/project-math"
import { getCashAccounts, getStaff, type GenericCashAccount, type GenericStaff } from "@/lib/api/generic"
import {
  listGenericEmployeeLoans, getGenericEmployeeLoanSummary,
  listGenericEmployeeLoanRepayments,
  createGenericEmployeeLoan, disburseGenericEmployeeLoan,
  cancelGenericEmployeeLoan, reverseGenericEmployeeLoan,
  recordGenericEmployeeLoanRepayment, reverseGenericEmployeeLoanRepayment,
  EMPLOYEE_LOAN_TYPES, EMPLOYEE_LOAN_TYPE_LABELS,
  EMPLOYEE_LOAN_REPAYMENT_METHODS, EMPLOYEE_LOAN_REPAYMENT_METHOD_LABELS,
  EMPLOYEE_LOAN_REPAYMENT_SOURCES, EMPLOYEE_LOAN_SOURCE_LABELS,
  EMPLOYEE_LOAN_STATUS_LABELS,
  type GenericEmployeeLoan, type GenericEmployeeLoanRepayment,
  type GenericEmployeeLoanSummary,
} from "@/lib/api/generic-employee-loans"

const PAGE_SIZE = 25
const today = () => new Date().toISOString().slice(0, 10)
const fmtDate = (d?: string | null) => (d ? String(d).slice(0, 10) : "—")

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

function RepaymentHistory({
  rows, loading, fmt, onReverse,
}: {
  rows: GenericEmployeeLoanRepayment[]
  loading: boolean
  fmt: (n: number) => string
  onReverse: (r: GenericEmployeeLoanRepayment) => void
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
              <TableRow key={r.genericEmployeeLoanRepaymentId}
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
                        : `Payroll run ${r.genericPayrollRunId ?? "—"}`)
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
export default function GenericEmployeeLoansPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") router.replace("/dashboard")
  }, [activeFarmType, router])

  const [rows, setRows] = useState<GenericEmployeeLoan[]>([])
  const [total, setTotal] = useState(0)
  const [summary, setSummary] = useState<GenericEmployeeLoanSummary | null>(null)
  const [staff, setStaff] = useState<GenericStaff[]>([])
  const [accounts, setAccounts] = useState<GenericCashAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")

  const [status, setStatus] = useState<string>("Active")
  const [search, setSearch] = useState("")
  const [staffId, setStaffId] = useState<string>("ALL")
  const [loanType, setLoanType] = useState<string>("ALL")
  const [offset, setOffset] = useState(0)
  // 501: Project / contract. A loan shows for a project when it was taken FOR
  // that project, or when its employee is on the project's team (500).
  const [projectFilter, setProjectFilter] = useState<ProjectFilterValue>(ALL_PROJECTS)
  const projectOn = projectFilter.kind !== "all"

  const [historyByLoan, setHistoryByLoan] =
    useState<Map<number, GenericEmployeeLoanRepayment[]>>(new Map())
  const [historyLoading, setHistoryLoading] = useState(false)
  const [detailFor, setDetailFor] = useState<GenericEmployeeLoan | null>(null)

  const load = useCallback(async () => {
    setError("")
    try {
      const [page, sum] = await Promise.all([
        listGenericEmployeeLoans({
          status: status || null,
          search: search || null,
          staffId: staffId === "ALL" ? null : Number(staffId),
          loanType: loanType === "ALL" ? null : loanType,
          // With a project picked, read every loan so the filter covers all pages.
          limit: projectOn ? 1000 : PAGE_SIZE,
          offset: projectOn ? 0 : offset,
        }),
        getGenericEmployeeLoanSummary(),
      ])
      setRows(page.items)
      setTotal(page.totalCount)
      setSummary(sum)
    } catch (e: any) {
      setError(e?.message ?? String(e))
    } finally {
      setLoading(false)
    }
  }, [status, search, staffId, loanType, offset, projectOn])

  useEffect(() => { void load() }, [load])

  const projectLabels = useProjectLabels("EmployeeLoan", rows)
  const team = useProjectTeam()
  const shownRows = useMemo(() => {
    if (!projectLabels.enabled || !projectOn) return rows
    return rows.filter((l) => projectFilter.kind === "general"
      ? projectLabels.matches(l.genericEmployeeLoanId, projectFilter)
      : projectLabels.matches(l.genericEmployeeLoanId, projectFilter) || team.staffMatches(l.genericStaffId, projectFilter))
  }, [rows, projectLabels, projectOn, projectFilter, team])
  const projectCell = (l: GenericEmployeeLoan) => {
    const tagged = projectLabels.labelsOf(l.genericEmployeeLoanId)
    const onTeam = team.teamLabels(l.genericStaffId)
    return (
      <span className="flex flex-col gap-0.5">
        {tagged.length > 0 ? <ProjectLabels labels={tagged} /> : <span className="text-xs text-slate-400">Personal</span>}
        {onTeam.length > 0 && <span className="block text-[11px] text-slate-500">Team: {onTeam.map((x) => x.split(" — ")[0]).join(", ")}</span>}
      </span>
    )
  }

  useEffect(() => {
    void (async () => {
      try {
        const [s, a] = await Promise.all([getStaff(), getCashAccounts()])
        setStaff(s.filter((x) => x.isActive && !x.isDeleted))
        setAccounts(a)
      } catch { /* page still works without pickers pre-filled */ }
    })()
  }, [])

  const loadHistories = useCallback(async (list: GenericEmployeeLoan[]) => {
    if (list.length === 0) { setHistoryByLoan(new Map()); return }
    setHistoryLoading(true)
    try {
      const pairs = await Promise.all(list.map(async (l) => {
        try {
          return [l.genericEmployeeLoanId,
                  await listGenericEmployeeLoanRepayments(l.genericEmployeeLoanId)] as const
        } catch {
          return [l.genericEmployeeLoanId, [] as GenericEmployeeLoanRepayment[]] as const
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
  const [repayFor, setRepayFor] = useState<GenericEmployeeLoan | null>(null)
  const [disburseFor, setDisburseFor] = useState<GenericEmployeeLoan | null>(null)
  const [reversingLoan, setReversingLoan] = useState<GenericEmployeeLoan | null>(null)
  const [reversingRepayment, setReversingRepayment] =
    useState<GenericEmployeeLoanRepayment | null>(null)
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
                <Link href="/generic-payroll">Payroll</Link>
              </Button>
              <Button onClick={() => setNewOpen(true)} className="h-11 sm:h-10">
                <Plus className="h-4 w-4 mr-1" /> New loan / advance
              </Button>
            </div>
          </div>

          <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
            <Stat label="Outstanding" value={fmt(summary?.outstandingTotal ?? 0)}
                  hint="What staff still owe the business" accent="indigo" />
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
                  <SelectItem key={s.genericStaffId} value={String(s.genericStaffId)}>
                    {s.firstName} {s.lastName}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            {projectLabels.enabled && (
              <ProjectFilter value={projectFilter} onChange={(v) => { setProjectFilter(v); setOffset(0) }} className="h-9 w-full sm:w-64" />
            )}
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
          ) : shownRows.length === 0 ? (
            <Card><CardContent className="py-8 text-center text-slate-500">
              {status || search || staffId !== "ALL" || loanType !== "ALL" || projectOn
                ? "No advances match this filter."
                : "No advances recorded yet."}
            </CardContent></Card>
          ) : (
            <>
              <MobileCardList
                striped
                defaultOpen
                items={shownRows}
                getKey={(l: GenericEmployeeLoan) => l.genericEmployeeLoanId}
                primary={(l: GenericEmployeeLoan) => (
                  <>{l.loanNumber ?? `#${l.genericEmployeeLoanId}`} · {l.staffName}</>
                )}
                secondary={(l: GenericEmployeeLoan) => (
                  <>
                    <span>{fmtDate(l.disbursementDate)}</span>
                    <span>·</span>
                    <span className="text-xs">{EMPLOYEE_LOAN_TYPE_LABELS[l.loanType] ?? l.loanType}</span>
                  </>
                )}
                trailing={(l: GenericEmployeeLoan) => (
                  <Badge className={statusClass(l.status)}>
                    {EMPLOYEE_LOAN_STATUS_LABELS[l.status] ?? l.status}
                  </Badge>
                )}
                highlights={(l: GenericEmployeeLoan) => [
                  { label: "Outstanding", value: fmt(l.outstandingBalance), accent: "blue" as const, wide: true },
                  { label: "Advanced", value: fmt(l.principalAmount), accent: "rose" as const },
                  { label: "Repaid", value: fmt(l.totalRepaid), accent: "emerald" as const },
                ]}
                details={(l: GenericEmployeeLoan) => [
                  { label: "Total repayable", value: fmt(l.totalRepayable) },
                  { label: "Repayment", value: EMPLOYEE_LOAN_REPAYMENT_METHOD_LABELS[l.repaymentMethod] ?? l.repaymentMethod },
                  { label: "Suggested per payroll", value: l.defaultPayrollDeduction ? fmt(l.defaultPayrollDeduction) : "—" },
                  { label: "Paid from", value: l.cashAccountName ?? "—" },
                  { label: "Reference", value: l.referenceNumber ?? "—" },
                  { label: "Purpose", value: l.purpose ?? l.description ?? "—" },
                  ...(projectLabels.enabled ? [{ label: PROJECT_COLUMN_TITLE, value: projectCell(l) }] : []),
                  { label: "Repayments", value: String(l.repaymentCount) },
                ]}
                actions={(l: GenericEmployeeLoan) => (
                  <>
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
                          {projectLabels.enabled && <ProjectHead />}
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
                        {shownRows.map((l) => (
                          <TableRow key={l.genericEmployeeLoanId} className="cursor-pointer"
                                    onClick={() => setDetailFor(l)}>
                            <TableCell className="font-medium whitespace-nowrap">
                              {l.loanNumber ?? `#${l.genericEmployeeLoanId}`}
                            </TableCell>
                            <TableCell>{l.staffName}</TableCell>
                            {projectLabels.enabled && <TableCell>{projectCell(l)}</TableCell>}
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
                        ))}
                      </TableBody>
                    </Table>
                  </div>
                }
              />

              {projectOn ? (
                <div className="mt-3 text-sm text-slate-500">
                  {shownRows.length} {shownRows.length === 1 ? "advance" : "advances"} for this project filter
                  (taken for the project, or by staff on its team).
                </div>
              ) : (
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
              )}
            </>
          )}

          <Card className="border-sky-200 bg-sky-50 mt-4">
            <CardContent className="p-4 flex items-start gap-2">
              <Info className="h-4 w-4 text-sky-700 mt-0.5 shrink-0" />
              <p className="text-xs text-sky-900">
                Repayments taken from a wage do not show as money coming in, because none did —
                the business simply paid out less that month. They still reduce what the worker owes.
                To undo one, reopen the payroll run that created it.
              </p>
            </CardContent>
          </Card>
        </main>
      </div>

      <NewLoanDialog
        open={newOpen} onOpenChange={setNewOpen} staff={staff} accounts={accounts}
        busy={busy} fmt={fmt}
        onSave={(input) => run(async () => { await createGenericEmployeeLoan(input); setNewOpen(false) },
                               "Advance recorded")}
      />

      <DisburseDialog
        loan={disburseFor} onClose={() => setDisburseFor(null)} accounts={accounts} busy={busy} fmt={fmt}
        onSave={(id, input) => run(async () => {
          await disburseGenericEmployeeLoan(id, input); setDisburseFor(null)
        }, "Advance handed over")}
      />

      <RepayDialog
        loan={repayFor} onClose={() => setRepayFor(null)} accounts={accounts} busy={busy} fmt={fmt}
        onSave={(input) => run(async () => {
          await recordGenericEmployeeLoanRepayment(input); setRepayFor(null)
        }, "Repayment recorded")}
      />

      <LoanDetailDialog
        loan={detailFor}
        onClose={() => setDetailFor(null)}
        rows={detailFor ? historyByLoan.get(detailFor.genericEmployeeLoanId) ?? [] : []}
        loading={historyLoading}
        fmt={fmt}
        onReverse={(r) => { setReversingRepayment(r); setReason("") }}
      />

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
            <ReasonSelect options={!reversingRepayment && reversingLoan?.status === "Draft" ? CANCEL_REASONS : LOAN_REVERSAL_REASONS} value={reason} onChange={setReason} />
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
                    await reverseGenericEmployeeLoanRepayment(rep.genericEmployeeLoanRepaymentId, reason || null)
                  } else if (loan) {
                    if (loan.status === "Draft") await cancelGenericEmployeeLoan(loan.genericEmployeeLoanId, reason || null)
                    else await reverseGenericEmployeeLoan(loan.genericEmployeeLoanId, reason || null)
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
  staff: GenericStaff[]
  accounts: GenericCashAccount[]
  busy: boolean
  fmt: (n: number) => string
  onSave: (input: any) => Promise<boolean>
}) {
  // 501: an advance taken FOR a project. Blank = a personal loan (stays with the employee).
  const [project, setProject] = useState<SingleProjectValue>(EMPTY_SINGLE_PROJECT)
  const [f, setF] = useState({
    genericStaffId: 0, loanType: "EmployeeLoan", principalAmount: 0,
    disbursementDate: today(), purpose: "", notes: "",
    repaymentMethod: "PayrollDeduction", defaultPayrollDeduction: 0,
    interestEnabled: false, interestAmount: 0,
    disburseNow: true, genericCashAccountId: 0, paymentMethod: "Cash", referenceNumber: "",
  })
  useEffect(() => {
    if (open) {
      setF((p) => ({ ...p, genericStaffId: 0, principalAmount: 0, purpose: "", notes: "", referenceNumber: "" }))
      setProject(EMPTY_SINGLE_PROJECT)
    }
  }, [open])

  const totalRepayable = f.principalAmount + (f.interestEnabled ? f.interestAmount : 0)
  const canSave = f.genericStaffId > 0 && f.principalAmount > 0 &&
                  (!f.disburseNow || f.genericCashAccountId > 0)

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
            <Select value={f.genericStaffId ? String(f.genericStaffId) : ""}
                    onValueChange={(v) => setF({ ...f, genericStaffId: Number(v) })}>
              <SelectTrigger><SelectValue placeholder="Choose a member of staff" /></SelectTrigger>
              <SelectContent>
                {staff.map((s) => (
                  <SelectItem key={s.genericStaffId} value={String(s.genericStaffId)}>
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
              <p className="text-[11px] text-slate-500">Most business advances are interest-free.</p>
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

          <SingleProjectField className="sm:col-span-2" value={project} onChange={setProject}
            amount={f.principalAmount} showCostClass={false} label="For a project / contract (optional)"
            hint="Only for an advance given for project work. Leave blank for a personal loan: it stays with the employee and never becomes a project cost." />

          {f.disburseNow && (
            <>
              <div className="space-y-1">
                <Label>Pay from *</Label>
                <Select value={f.genericCashAccountId ? String(f.genericCashAccountId) : ""}
                        onValueChange={(v) => setF({ ...f, genericCashAccountId: Number(v) })}>
                  <SelectTrigger><SelectValue placeholder="Choose a cash account" /></SelectTrigger>
                  <SelectContent>
                    {accounts.map((a) => (
                      <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>
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
            genericStaffId: f.genericStaffId,
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
            genericCashAccountId: f.disburseNow ? f.genericCashAccountId : null,
            paymentMethod: f.disburseNow ? f.paymentMethod : null,
            referenceNumber: f.referenceNumber || null,
            projects: project.projectId != null || (project.splits?.length ?? 0) > 0 ? singleAssignment(project) : undefined,
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
  loan: GenericEmployeeLoan | null
  onClose: () => void
  accounts: GenericCashAccount[]
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
                {accounts.map((a) => (
                  <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>
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
                  onClick={() => void onSave(loan.genericEmployeeLoanId, {
                    genericCashAccountId: accountId,
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
function RepayDialog({
  loan, onClose, accounts, busy, fmt, onSave,
}: {
  loan: GenericEmployeeLoan | null
  onClose: () => void
  accounts: GenericCashAccount[]
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
                {accounts.map((a) => (
                  <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>
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
                    genericEmployeeLoanId: loan.genericEmployeeLoanId,
                    amount,
                    sourceType: source,
                    repaymentDate: date,
                    genericCashAccountId: accountId,
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
function LoanFacts({ loan, fmt }: { loan: GenericEmployeeLoan; fmt: (n: number) => string }) {
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
function LoanDetailDialog({
  loan, onClose, rows, loading, fmt, onReverse,
}: {
  loan: GenericEmployeeLoan | null
  onClose: () => void
  rows: GenericEmployeeLoanRepayment[]
  loading: boolean
  fmt: (n: number) => string
  onReverse: (r: GenericEmployeeLoanRepayment) => void
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
      <DialogContent className="sm:max-w-5xl">
        <DialogHeader>
          <DialogTitle className="flex flex-wrap items-center gap-2">
            {loan.loanNumber ?? `#${loan.genericEmployeeLoanId}`}
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
