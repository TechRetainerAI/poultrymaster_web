"use client"

// Generic Loans (Financing) — Poultry's Loans page (app/poultry-loans) on
// Generic's own tables ("GenericLoans" / "GenericLoanPayments", migration 455).
//
// A repayment is not one number: only the interest and the fees are a cost,
// the principal is the business swapping cash for a smaller debt. The shared
// LoanRepaymentDialog (components/cash/loan-repayment-dialog.tsx) asks for the
// parts and shows the total, exactly as on Poultry.
//
// Money rules live in the SPs (455): every cash move is one ledger row on the
// account, a received amount needs an account, a repayment cannot overdraw the
// account or pay more principal than is owed, a loan with posted repayments
// cannot be cancelled, and reversing or cancelling needs a reason.
//
// 509: Draft -> Approve, like Poultry's employee advances. A Draft has posted
// nothing and edits everything. Approve posts the money; after that only a
// light edit (lender, account number, due dates, notes). Reverse takes an
// approved loan back to Draft (money out again) so it can be corrected and
// approved again. Cancel discards a Draft.

import { CANCEL_REASONS, LOAN_REVERSAL_REASONS } from "@/lib/reversal-reasons"
import { ReasonSelect } from "@/components/ui/reason-select"
import { Fragment, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Textarea } from "@/components/ui/textarea"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { Ban, Banknote, CheckCircle2, ChevronDown, ChevronRight, HandCoins, Loader2, Pencil, Plus, Undo2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { cn } from "@/lib/utils"
import { useFmt } from "@/lib/currency"
import {
  LoanRepaymentDialog, isRepayableLoan, type RepayableLoanOption,
} from "@/components/cash/loan-repayment-dialog"
import {
  getCashAccounts, getLoans, getAllLoanPayments, createLoan, updateLoan, cancelLoan,
  approveLoan, reverseLoan, repayLoan, reverseLoanPayment,
  type GenericCashAccount, type GenericLoan, type GenericLoanPayment,
} from "@/lib/api/generic"
import { fmtDateTime } from "@/lib/utils/company-datetime"
import { useProjectListFilter } from "@/components/generic/projects/use-project-list-filter"
import { ProjectHead, ProjectSplitLabels, ProjectSplitTable, PROJECT_COLUMN_TITLE } from "@/components/generic/projects/project-column"
import {
  SingleProjectField, EMPTY_SINGLE_PROJECT, singleAssignment, loadSingleProject, type SingleProjectValue,
} from "@/components/generic/projects/form-project-field"
import { useProjectsEnabled } from "@/hooks/use-generic-projects"

const LENDER_TYPES = ["Bank", "FinancialInstitution", "Individual", "Owner", "FamilyFriend", "Supplier", "Other"]
const INTEREST_TYPES = ["Simple", "ReducingBalance", "Flat", "Unknown"]
const FREQUENCIES = ["Weekly", "BiWeekly", "Monthly", "Quarterly", "Custom"]
const STATUS_FILTERS = ["All", "Draft", "Active", "PaidOff", "Cancelled"] as const

function today() { return new Date().toISOString().slice(0, 10) }
const dateOnly = (d?: string | null) => (d ? d.slice(0, 10) : "")

const lenderCell = (l: GenericLoan) => {
  const name = (l.lenderName ?? "").trim()
  return name || <span className="italic text-slate-400">Lender not recorded</span>
}

const toLoanOption = (l: GenericLoan): RepayableLoanOption => ({
  loanId: l.genericLoanId,
  loanNumber: l.loanNumber,
  lenderName: l.lenderName,
  outstandingPrincipal: l.outstandingBalance,
  status: l.status,
  source: "Loan",
  defaultAccountId: l.genericCashAccountId ?? null,
})

function statusClass(l: GenericLoan) {
  if (l.status === "PaidOff") return "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"
  if (l.status === "Cancelled") return "bg-slate-100 text-slate-700 hover:bg-slate-100"
  if (l.status === "Draft") return "bg-sky-100 text-sky-800 hover:bg-sky-100"
  if (l.isOverdue) return "bg-rose-100 text-rose-800 hover:bg-rose-100"
  return "bg-amber-100 text-amber-800 hover:bg-amber-100"
}

const isDraft = (l: GenericLoan) => l.status === "Draft"
/** Approved = the money has posted (Active / PaidOff). */
const isApproved = (l: GenericLoan) => l.status === "Active" || l.status === "PaidOff"
// A Draft edits everything; an approved loan gets the light edit.
const canEdit = (l: GenericLoan) => isDraft(l) || isApproved(l)
// Reverse (back to Draft) is offered on every approved loan; repayments must be
// reversed first, and the dialog says so rather than hiding the action.
const canReverse = isApproved
const canCancel = isDraft

const blankForm = () => ({
  lenderName: "", lenderType: "Bank", accountNumber: "",
  originalPrincipal: "0", amountReceived: "0", genericCashAccountId: "",
  startDate: today(), interestRate: "", interestType: "ReducingBalance",
  termMonths: "", paymentFrequency: "Monthly", nextPaymentDate: "", notes: "",
})

function LoanRepaymentTable({ payments, fmt, onReverse }: {
  payments: GenericLoanPayment[]
  fmt: (n: number) => string
  onReverse: (p: GenericLoanPayment) => void
}) {
  if (payments.length === 0) {
    return (
      <div className="px-4 py-3 text-sm text-slate-500">
        No repayments recorded against this loan yet.
      </div>
    )
  }
  return (
    <div className="px-4 py-3">
      <p className="mb-2 text-xs text-slate-500">The total is what left the bank. Only the interest and the fees reach the profit and loss.</p>
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Date</TableHead>
              <TableHead>Payment #</TableHead>
              <TableHead className="text-right">Principal</TableHead>
              <TableHead className="text-right">Interest</TableHead>
              <TableHead className="text-right">Fees</TableHead>
              <TableHead className="text-right">Total paid</TableHead>
              <TableHead>Account</TableHead>
              <TableHead>Status</TableHead>
              <TableHead />
            </TableRow>
          </TableHeader>
          <TableBody>
            {payments.map((p) => (
              <TableRow key={p.genericLoanPaymentId} className="bg-white">
                <TableCell className="whitespace-nowrap">{fmtDateTime(p.paymentDate, p)}</TableCell>
                <TableCell className="font-medium">{p.paymentNumber ?? `#${p.genericLoanPaymentId}`}</TableCell>
                <TableCell className="text-right tabular-nums">{fmt(p.principalAmount)}</TableCell>
                <TableCell className="text-right tabular-nums text-amber-700">{fmt(p.interestAmount)}</TableCell>
                <TableCell className="text-right tabular-nums text-amber-700">{fmt(p.feeAmount)}</TableCell>
                <TableCell className="text-right tabular-nums font-medium">
                  <span className={p.status === "Reversed" ? "line-through text-slate-400" : ""}>
                    {fmt(p.totalPayment)}
                  </span>
                </TableCell>
                <TableCell className="text-slate-500">{p.accountName ?? "–"}</TableCell>
                <TableCell>
                  <Badge className={p.status === "Reversed"
                    ? "bg-slate-100 text-slate-700 hover:bg-slate-100"
                    : "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"}>
                    {p.status}
                  </Badge>
                </TableCell>
                <TableCell className="text-right">
                  {p.status === "Posted" && (
                    <Button size="sm" variant="outline" onClick={() => onReverse(p)}>
                      <Undo2 className="h-3 w-3 mr-1" /> Reverse
                    </Button>
                  )}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </div>
  )
}

function LoanRepaymentList({ payments, fmt, onReverse }: {
  payments: GenericLoanPayment[]
  fmt: (n: number) => string
  onReverse: (p: GenericLoanPayment) => void
}) {
  if (payments.length === 0) {
    return <div className="text-xs text-slate-500">No repayments recorded against this loan yet.</div>
  }
  return (
    <div className="space-y-2">
      <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
        Repayment history
      </div>
      <p className="text-[11px] text-slate-500">The total is what left the bank. Only the interest and the fees reach the profit and loss.</p>
      {payments.map((p) => (
        <div key={p.genericLoanPaymentId} className="rounded-lg border border-slate-200 bg-white px-3 py-2">
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <div className="font-medium text-slate-900">
                {fmtDateTime(p.paymentDate, p)}
              </div>
              <div className="text-[11px] text-slate-500 truncate">
                {p.paymentNumber ?? `#${p.genericLoanPaymentId}`}
                {p.accountName ? ` · ${p.accountName}` : ""}
              </div>
            </div>
            <div className="text-right shrink-0">
              <div className={cn("font-semibold tabular-nums",
                                 p.status === "Reversed" ? "text-slate-400 line-through" : "text-slate-900")}>
                {fmt(p.totalPayment)}
              </div>
              <Badge className={cn("mt-0.5 text-[10px]", p.status === "Reversed"
                ? "bg-slate-100 text-slate-700 hover:bg-slate-100"
                : "bg-emerald-100 text-emerald-800 hover:bg-emerald-100")}>
                {p.status}
              </Badge>
            </div>
          </div>
          <div className="mt-2 grid grid-cols-3 gap-2 text-[11px]">
            <div>
              <div className="text-slate-500">Principal</div>
              <div className="font-medium tabular-nums">{fmt(p.principalAmount)}</div>
            </div>
            <div>
              <div className="text-slate-500">Interest</div>
              <div className="font-medium tabular-nums text-amber-700">{fmt(p.interestAmount)}</div>
            </div>
            <div>
              <div className="text-slate-500">Fees</div>
              <div className="font-medium tabular-nums text-amber-700">{fmt(p.feeAmount)}</div>
            </div>
          </div>
          {p.status === "Posted" && (
            <Button size="sm" variant="outline" className="mt-2 h-9 w-full"
                    onClick={() => onReverse(p)}>
              <Undo2 className="h-3 w-3 mr-1" /> Reverse
            </Button>
          )}
        </div>
      ))}
    </div>
  )
}

export default function GenericLoansPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  const [accounts, setAccounts] = useState<GenericCashAccount[]>([])
  const [loans, setLoans] = useState<GenericLoan[]>([])
  const [payments, setPayments] = useState<GenericLoanPayment[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [status, setStatus] = useState<string>("All")

  const [newOpen, setNewOpen] = useState(false)
  /** The loan being edited; null = recording a new one. */
  const [editing, setEditing] = useState<GenericLoan | null>(null)
  const [form, setForm] = useState(blankForm())

  const [repaying, setRepaying] = useState<GenericLoan | null>(null)
  const [reversing, setReversing] = useState<GenericLoanPayment | null>(null)
  /** Reverse (approved -> Draft) or Cancel (Draft -> Cancelled); which one follows the loan's status. */
  const [cancelling, setCancelling] = useState<GenericLoan | null>(null)
  const [approving, setApproving] = useState<GenericLoan | null>(null)
  const [reason, setReason] = useState("")
  /** Editing an approved loan: only the light fields are open. */
  const lightEdit = !!editing && !isDraft(editing)

  const paymentsByLoan = useMemo(() => {
    const m = new Map<number, GenericLoanPayment[]>()
    for (const p of payments) {
      const list = m.get(p.genericLoanId)
      if (list) list.push(p)
      else m.set(p.genericLoanId, [p])
    }
    for (const list of m.values()) {
      list.sort((a, b) => (a.paymentDate < b.paymentDate ? 1 : a.paymentDate > b.paymentDate ? -1 : 0))
    }
    return m
  }, [payments])

  const [expanded, setExpanded] = useState<Set<number>>(new Set())
  const toggleExpanded = (id: number) =>
    setExpanded((prev) => {
      const next = new Set(prev)
      if (!next.delete(id)) next.add(id)
      return next
    })

  const load = async () => {
    setLoading(true)
    try {
      const [accs, ls, ps] = await Promise.all([getCashAccounts(), getLoans(), getAllLoanPayments()])
      setAccounts(accs); setLoans(ls); setPayments(ps)
    } catch (e: any) {
      toast({ title: "Could not load loans", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    if (!activeFarmId) return
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, activeFarmId, router])

  // 493: Project / Contract filter -- loans given to a project (Link older
  // transactions). The cards and the list both follow it.
  const { extraFilter: projectFilter, labels: projectLabels } = useProjectListFilter<GenericLoan>("Loan", (l) => l.genericLoanId, loans)

  // 496: the loan's project / contract, chosen on the form. Its repayments,
  // interest and fees follow it (P&L, Cash Flow, Financial Activity). It is
  // financing: the loan itself is never revenue or profit.
  const { enabled: projectsEnabled } = useProjectsEnabled()
  const [project, setProject] = useState<SingleProjectValue>(EMPTY_SINGLE_PROJECT)
  const [projectChanged, setProjectChanged] = useState(false)
  const changeProject = (v: SingleProjectValue) => { setProject(v); setProjectChanged(true) }
  const projectLoans = useMemo(
    () => (projectFilter ? loans.filter((l) => projectFilter.matches(l)) : loans),
    [loans, projectFilter],
  )

  // Poultry reads these from sppoultryloan_summary; the same sums, over the list.
  const summary = useMemo(() => {
    const loans = projectLoans
    // A Draft has posted nothing, so it is not borrowed money yet.
    const live = loans.filter(isApproved)
    const due = loans
      .filter((l) => l.status === "Active" && l.outstandingBalance > 0 && l.nextPaymentDate)
      .map((l) => l.nextPaymentDate as string)
      .sort()
    return {
      activeLoans: loans.filter((l) => l.status === "Active").length,
      draftLoans: loans.filter(isDraft).length,
      totalBorrowed: live.reduce((s, l) => s + l.originalPrincipal, 0),
      totalReceived: live.reduce((s, l) => s + l.amountReceived, 0),
      outstandingPrincipal: loans.reduce((s, l) => s + l.outstandingBalance, 0),
      totalPrincipalRepaid: loans.reduce((s, l) => s + l.totalPrincipalPaid, 0),
      totalInterestPaid: loans.reduce((s, l) => s + l.totalInterestPaid, 0),
      totalFeesPaid: loans.reduce((s, l) => s + l.totalFeesPaid, 0),
      overdueLoans: loans.filter((l) => l.isOverdue).length,
      nextPaymentDate: due[0] ?? null,
    }
  }, [projectLoans])

  const visible = useMemo(
    () => (status === "All" ? projectLoans : projectLoans.filter((l) => l.status === status)),
    [projectLoans, status],
  )
  const pg = usePagination(visible)

  const repayAccounts = useMemo(
    () => accounts.map((a) => ({
      accountId: a.genericCashAccountId,
      accountName: a.accountName,
      currentBalance: a.currentBalance,
      allowNegativeBalance: a.allowNegativeBalance,
      isActive: a.isActive,
    })),
    [accounts],
  )

  const openNew = () => {
    setEditing(null); setForm(blankForm()); setNewOpen(true)
    setProject({ ...EMPTY_SINGLE_PROJECT, costClass: "Financing" }); setProjectChanged(false)
  }
  const openEdit = (l: GenericLoan) => {
    setEditing(l)
    setProject({ ...EMPTY_SINGLE_PROJECT, costClass: "Financing" }); setProjectChanged(false)
    if (projectsEnabled) {
      void loadSingleProject("Loan", l.genericLoanId).then((v) => setProject({ ...v, costClass: "Financing" }))
    }
    setForm({
      lenderName: l.lenderName ?? "", lenderType: l.lenderType || "Other", accountNumber: l.accountNumber ?? "",
      originalPrincipal: String(l.originalPrincipal), amountReceived: String(l.amountReceived),
      genericCashAccountId: l.genericCashAccountId ? String(l.genericCashAccountId) : "",
      startDate: dateOnly(l.startDate ?? l.loanDate),
      interestRate: l.interestRate ? String(l.interestRate) : "", interestType: l.interestType || "Unknown",
      termMonths: l.termMonths != null ? String(l.termMonths) : "", paymentFrequency: l.paymentFrequency || "Monthly",
      nextPaymentDate: dateOnly(l.nextPaymentDate), notes: l.notes ?? "",
    })
    setNewOpen(true)
  }

  /** approve = also post the money (Save & Approve). A light edit never approves. */
  const saveLoan = async (approve: boolean) => {
    if (!form.lenderName.trim()) { toast({ title: "Who lent the money?", variant: "destructive" }); return }
    const princ = Number(form.originalPrincipal) || 0
    const recv = Number(form.amountReceived) || 0
    if (!lightEdit) {
      if (princ <= 0) { toast({ title: "Enter the loan amount", variant: "destructive" }); return }
      if (recv > princ) { toast({ title: "Received cannot exceed the principal", variant: "destructive" }); return }
      if (approve && recv > 0 && !form.genericCashAccountId) {
        toast({ title: "Choose the cash account", variant: "destructive" }); return
      }
    }
    setSaving(true)
    try {
      if (editing && lightEdit) {
        // Approved: the light fields only.
        await updateLoan(editing.genericLoanId, {
          lenderName: form.lenderName.trim(),
          lenderType: form.lenderType,
          accountNumber: form.accountNumber.trim() || null,
          nextPaymentDate: form.nextPaymentDate || null,
          notes: form.notes.trim() || null,
        })
        toast({ title: "Loan updated" })
      } else if (editing) {
        // Draft: everything.
        await updateLoan(editing.genericLoanId, {
          lenderName: form.lenderName.trim(),
          lenderType: form.lenderType,
          accountNumber: form.accountNumber.trim() || null,
          originalPrincipal: princ,
          amountReceived: recv,
          genericCashAccountId: form.genericCashAccountId ? Number(form.genericCashAccountId) : null,
          loanDate: form.startDate || null,
          interestRate: form.interestRate ? Number(form.interestRate) : null,
          interestType: form.interestType || null,
          termMonths: form.termMonths ? Number(form.termMonths) : null,
          paymentFrequency: form.paymentFrequency || null,
          nextPaymentDate: form.nextPaymentDate || null,
          notes: form.notes.trim() || null,
          projects: projectsEnabled && projectChanged ? singleAssignment({ ...project, costClass: "Financing" }) : undefined,
        })
        if (approve) {
          await approveLoan(editing.genericLoanId)
          toast({ title: "Loan approved", description: recv > 0 ? `${fmt(recv)} in. It is money in, not revenue.` : "Nothing was received, so no cash moved." })
        } else {
          toast({ title: "Draft saved", description: "Nothing has posted. Approve it when the details are right." })
        }
      } else {
        await createLoan({
          approve,
          lenderName: form.lenderName.trim(),
          lenderType: form.lenderType,
          accountNumber: form.accountNumber.trim() || null,
          originalPrincipal: princ,
          amountReceived: recv,
          genericCashAccountId: form.genericCashAccountId ? Number(form.genericCashAccountId) : null,
          loanDate: form.startDate,
          startDate: form.startDate,
          interestRate: form.interestRate ? Number(form.interestRate) : null,
          interestType: form.interestType || null,
          termMonths: form.termMonths ? Number(form.termMonths) : null,
          paymentFrequency: form.paymentFrequency || null,
          nextPaymentDate: form.nextPaymentDate || null,
          notes: form.notes.trim() || null,
          projects: projectsEnabled && (project.projectId != null || project.splits?.length)
            ? singleAssignment({ ...project, costClass: "Financing" }) : undefined,
        })
        toast(approve
          ? {
              title: "Loan recorded and approved",
              description: recv > 0
                ? `${fmt(recv)} in. It is money in, not revenue — the business borrowed it.`
                : "No money recorded as received yet.",
            }
          : { title: "Saved as Draft", description: "Nothing has posted. Approve it when the details are right." })
      }
      setNewOpen(false); setEditing(null)
      await load()
    } catch (e: any) {
      toast({ title: editing ? "Could not update the loan" : "Could not record the loan",
              description: e?.message ?? String(e), variant: "destructive" })
      // A Draft saved but refused on approval: show it as it now is.
      if (editing && approve) void load()
    } finally { setSaving(false) }
  }

  const doApprove = async () => {
    if (!approving) return
    setSaving(true)
    try {
      await approveLoan(approving.genericLoanId)
      toast({
        title: "Loan approved",
        description: approving.amountReceived > 0
          ? `${fmt(approving.amountReceived)} into ${approving.accountName ?? "the account"}. From now on only a light edit is allowed.`
          : "Nothing was received, so no cash moved. From now on only a light edit is allowed.",
      })
      setApproving(null)
      await load()
    } catch (e: any) {
      toast({ title: "Could not approve the loan", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  const doReverse = async () => {
    if (!reversing) return
    if (reason.trim().length < 3) {
      toast({ title: "Say why", description: "The reason is written to the audit trail.", variant: "destructive" })
      return
    }
    setSaving(true)
    try {
      await reverseLoanPayment(reversing.genericLoanPaymentId, reason.trim())
      toast({ title: "Repayment reversed", description: "The debt is back up and the cash returned." })
      setReversing(null); setReason("")
      await load()
    } catch (e: any) {
      toast({ title: "Could not reverse", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  const doCancel = async () => {
    if (!cancelling) return
    if (reason.trim().length < 3) {
      toast({ title: "Say why", description: "The reason is written to the audit trail.", variant: "destructive" })
      return
    }
    setSaving(true)
    const draft = isDraft(cancelling)
    try {
      if (draft) {
        await cancelLoan(cancelling.genericLoanId, reason.trim())
        toast({ title: "Draft cancelled", description: "Nothing had posted, so no cash moved." })
        setCancelling(null); setReason("")
        await load()
      } else {
        // Back to Draft: the money comes back out, then the loan opens for a full edit.
        const reversed = cancelling
        await reverseLoan(reversed.genericLoanId, reason.trim())
        toast({
          title: "Loan back to Draft",
          description: reversed.amountReceived > 0
            ? `${fmt(reversed.amountReceived)} taken back out of ${reversed.accountName ?? "the account"}. Correct it and approve it again.`
            : "Nothing was received, so no cash moved. Correct it and approve it again.",
        })
        setCancelling(null); setReason("")
        await load()
        openEdit({ ...reversed, status: "Draft" })
      }
    } catch (e: any) {
      toast({ title: draft ? "Could not cancel the draft" : "Could not reverse the loan",
              description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  const openRepay = (l: GenericLoan) => setRepaying(l)

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 min-w-0 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-end justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <Banknote className="h-6 w-6 text-violet-600" /> Loans (Financing)
              </h1>
              <p className="text-sm text-slate-500 max-w-2xl">
                Money the business has borrowed. Borrowing is <strong>not income</strong> and repaying
                principal is <strong>not an expense</strong> — only the interest and the fees are the
                cost of borrowing.
              </p>
            </div>
            <Button onClick={openNew} className="h-11 sm:h-10">
              <Plus className="h-4 w-4 mr-1" /> Record loan
            </Button>
          </div>

          <div className="grid grid-cols-2 lg:grid-cols-5 gap-3 mb-4">
            <Stat label="Still owed" value={fmt(summary.outstandingPrincipal)}
                  hint={`${summary.activeLoans} active loan(s)${summary.draftLoans ? ` · ${summary.draftLoans} draft` : ""}`} accent="violet" />
            <Stat label="Borrowed" value={fmt(summary.totalBorrowed)}
                  hint={`${fmt(summary.totalReceived)} received`} />
            <Stat label="Principal repaid" value={fmt(summary.totalPrincipalRepaid)} accent="emerald" />
            <Stat label="Cost of borrowing"
                  value={fmt(summary.totalInterestPaid + summary.totalFeesPaid)}
                  hint="Interest and fees — the only part that is an expense" accent="amber" />
            <Stat label="Next payment"
                  value={summary.nextPaymentDate ? fmtDateTime(summary.nextPaymentDate) : "—"}
                  hint={summary.overdueLoans > 0 ? `${summary.overdueLoans} overdue` : undefined}
                  accent={summary.overdueLoans > 0 ? "rose" : "slate"} />
          </div>

          <div className="flex flex-wrap items-end gap-2 mb-4">
            {projectFilter && <div className="mr-2">{projectFilter.control}</div>}
            {STATUS_FILTERS.map((s) => (
              <Button key={s} size="sm" variant={status === s ? "default" : "outline"}
                      onClick={() => setStatus(s)}>{s}</Button>
            ))}
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500">
              <Loader2 className="h-4 w-4 animate-spin" /> Loading…
            </div>
          ) : visible.length === 0 ? (
            <Card><CardContent className="py-8 text-center text-slate-500">
              {loans.length === 0 ? "No loans recorded yet." : "No loans match this filter."}
            </CardContent></Card>
          ) : (
            <MobileCardList
              defaultOpen
              striped
              items={pg.pageItems}
              getKey={(l) => String(l.genericLoanId)}
              primary={(l) => (
                <>{l.loanNumber ?? `#${l.genericLoanId}`} · {lenderCell(l)}</>
              )}
              secondary={(l) => (
                <>
                  <span>{fmtDateTime(l.startDate ?? l.loanDate, l)}</span>
                  <span>·</span>
                  <span className="text-xs">{l.lenderType}</span>
                </>
              )}
              trailing={(l) => (
                <Badge className={statusClass(l)}>{l.isOverdue ? "Overdue" : l.status}</Badge>
              )}
              highlights={(l) => [
                { label: "Still owed", value: fmt(l.outstandingBalance) },
                { label: "Borrowed", value: fmt(l.originalPrincipal) },
              ]}
              details={(l) => [
                ...(projectLabels.enabled ? [{ label: PROJECT_COLUMN_TITLE, value: <ProjectSplitLabels parts={projectLabels.partsOf(l.genericLoanId)} amount={l.originalPrincipal} fmt={fmt} /> }] : []),
                { label: "Received", value: fmt(l.amountReceived) },
                { label: "Principal repaid", value: fmt(l.totalPrincipalPaid) },
                { label: "Interest paid", value: fmt(l.totalInterestPaid) },
                { label: "Fees paid", value: fmt(l.totalFeesPaid) },
                { label: "Rate", value: l.interestRate ? `${l.interestRate}% ${l.interestType ?? ""}` : "–" },
                { label: "Next payment", value: l.nextPaymentDate ? fmtDateTime(l.nextPaymentDate) : "–" },
                { label: "Repayments", value: String(l.paymentCount) },
              ]}
              extra={(l) => (
                <LoanRepaymentList
                  payments={paymentsByLoan.get(l.genericLoanId) ?? []}
                  fmt={fmt}
                  onReverse={(p) => { setReversing(p); setReason("") }}
                />
              )}
              actions={(l) => (
                <>
                  {isRepayableLoan(toLoanOption(l)) && (
                    <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openRepay(l)}>
                      <HandCoins className="h-4 w-4 mr-1" /> Repay
                    </Button>
                  )}
                  {isDraft(l) && (
                    <Button size="sm" variant="outline" className="flex-1 h-10 text-emerald-700" onClick={() => setApproving(l)}>
                      <CheckCircle2 className="h-4 w-4 mr-1" /> Approve
                    </Button>
                  )}
                  {canEdit(l) && (
                    <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openEdit(l)}>
                      <Pencil className="h-4 w-4 mr-1" /> Edit
                    </Button>
                  )}
                  {canReverse(l) && (
                    <Button size="sm" variant="outline" className="flex-1 h-10 text-rose-700"
                            onClick={() => { setCancelling(l); setReason("") }}>
                      <Undo2 className="h-4 w-4 mr-1" /> Reverse
                    </Button>
                  )}
                  {canCancel(l) && (
                    <Button size="sm" variant="outline" className="flex-1 h-10 text-rose-700"
                            onClick={() => { setCancelling(l); setReason("") }}>
                      <Ban className="h-4 w-4 mr-1" /> Cancel
                    </Button>
                  )}
                </>
              )}
              pagination={pg.paginationProps}
              desktopTable={
                <div className="overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead className="w-8" />
                        <TableHead>Date</TableHead>
                        <TableHead>Loan #</TableHead>
                        <TableHead>Lender</TableHead>
                        {projectLabels.enabled && <ProjectHead />}
                        <TableHead className="text-right">Borrowed</TableHead>
                        <TableHead className="text-right">Received</TableHead>
                        <TableHead className="text-right">Repaid</TableHead>
                        <TableHead className="text-right">Still owed</TableHead>
                        <TableHead className="text-right">Interest</TableHead>
                        <TableHead className="text-right">Fees</TableHead>
                        <TableHead>Next payment</TableHead>
                        <TableHead>Status</TableHead>
                        <TableHead></TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {pg.pageItems.map((l) => {
                        const loanPayments = paymentsByLoan.get(l.genericLoanId) ?? []
                        const open = expanded.has(l.genericLoanId)
                        return (
                        <Fragment key={l.genericLoanId}>
                        <TableRow className="cursor-pointer" onClick={() => toggleExpanded(l.genericLoanId)}>
                          <TableCell className="px-1">
                            {open ? <ChevronDown className="w-4 h-4 text-slate-400" />
                                  : <ChevronRight className="w-4 h-4 text-slate-400" />}
                          </TableCell>
                          <TableCell className="whitespace-nowrap">{fmtDateTime(l.startDate ?? l.loanDate, l)}</TableCell>
                          <TableCell className="font-medium">
                            {l.loanNumber ?? `#${l.genericLoanId}`}
                            <div className="text-xs text-slate-500">
                              {loanPayments.length === 0
                                ? "no repayments"
                                : `${loanPayments.length} repayment${loanPayments.length === 1 ? "" : "s"}`}
                            </div>
                          </TableCell>
                          <TableCell>
                            {lenderCell(l)}<div className="text-xs text-slate-500">{l.lenderType}</div>
                          </TableCell>
                          {projectLabels.enabled && (
                            <TableCell><ProjectSplitLabels parts={projectLabels.partsOf(l.genericLoanId)} amount={l.originalPrincipal} fmt={fmt} /></TableCell>
                          )}
                          <TableCell className="text-right tabular-nums">{fmt(l.originalPrincipal)}</TableCell>
                          <TableCell className="text-right tabular-nums">{fmt(l.amountReceived)}</TableCell>
                          <TableCell className="text-right tabular-nums">{fmt(l.totalPrincipalPaid)}</TableCell>
                          <TableCell className="text-right tabular-nums font-medium">{fmt(l.outstandingBalance)}</TableCell>
                          <TableCell className="text-right tabular-nums text-amber-700">{fmt(l.totalInterestPaid)}</TableCell>
                          <TableCell className="text-right tabular-nums text-amber-700">{fmt(l.totalFeesPaid)}</TableCell>
                          <TableCell className={l.isOverdue ? "text-rose-600" : ""}>
                            {l.nextPaymentDate ? fmtDateTime(l.nextPaymentDate) : "–"}
                          </TableCell>
                          <TableCell><Badge className={statusClass(l)}>{l.isOverdue ? "Overdue" : l.status}</Badge></TableCell>
                          <TableCell className="text-right">
                            <div className="flex items-center justify-end gap-1">
                              {isRepayableLoan(toLoanOption(l)) && (
                                <Button size="sm" variant="outline"
                                        onClick={(e) => { e.stopPropagation(); openRepay(l) }}>
                                  <HandCoins className="h-3 w-3 mr-1" /> Repay
                                </Button>
                              )}
                              {isDraft(l) && (
                                <Button size="sm" variant="outline" className="text-emerald-700"
                                        onClick={(e) => { e.stopPropagation(); setApproving(l) }}>
                                  <CheckCircle2 className="h-3 w-3 mr-1" /> Approve
                                </Button>
                              )}
                              {canEdit(l) && (
                                <Button size="sm" variant="outline"
                                        title={isDraft(l) ? "Edit the draft" : "Light edit: lender, account number, due date, notes"}
                                        onClick={(e) => { e.stopPropagation(); openEdit(l) }}>
                                  <Pencil className="h-3 w-3" />
                                </Button>
                              )}
                              {canReverse(l) && (
                                <Button size="sm" variant="outline" className="text-rose-700" title="Reverse the loan back to Draft (to correct it)"
                                        onClick={(e) => { e.stopPropagation(); setCancelling(l); setReason("") }}>
                                  <Undo2 className="h-3 w-3" />
                                </Button>
                              )}
                              {canCancel(l) && (
                                <Button size="sm" variant="outline" className="text-rose-700" title="Cancel the draft"
                                        onClick={(e) => { e.stopPropagation(); setCancelling(l); setReason("") }}>
                                  <Ban className="h-3 w-3" />
                                </Button>
                              )}
                            </div>
                          </TableCell>
                        </TableRow>
                        {open && (
                          <TableRow>
                            <TableCell colSpan={projectLabels.enabled ? 14 : 13} className="bg-slate-50 p-0">
                              {projectLabels.enabled && projectLabels.partsOf(l.genericLoanId).length > 0 && (
                                <div className="border-b border-slate-200 px-4 py-3">
                                  <ProjectSplitTable title={`Project split of ${fmt(l.originalPrincipal)} borrowed`}
                                    parts={projectLabels.partsOf(l.genericLoanId)} amount={l.originalPrincipal} fmt={fmt} />
                                </div>
                              )}
                              <LoanRepaymentTable
                                payments={loanPayments}
                                fmt={fmt}
                                onReverse={(p) => { setReversing(p); setReason("") }}
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
          )}

        </main>
      </div>

      {/* ---- new / edit loan -------------------------------------------- */}
      <Dialog open={newOpen} onOpenChange={(o) => { setNewOpen(o); if (!o) setEditing(null) }}>
        <DialogContent className="max-w-2xl sm:max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Banknote className="w-5 h-5 text-violet-600" /> {!editing ? "Record a Loan" : lightEdit ? "Edit Approved Loan" : "Edit Draft Loan"}
            </DialogTitle>
            <DialogDescription>
              {lightEdit
                ? "This loan is approved, so only a light edit is allowed: lender, account number, next payment date and notes. To change the amounts or terms, reverse it back to Draft."
                : editing
                  ? "A Draft has posted nothing — everything can change. Approve it when the details are right; the money posts then."
                  : "Save it as a Draft to check it first, or approve it now. The money arriving is cash in, but it is not revenue — the business borrowed it and still owes it."}
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4">
            <FormSection title="Lender" color="purple">
              <FormField label="Lender *" full>
                <Input value={form.lenderName} placeholder="Who lent the money?"
                       onChange={(e) => setForm((f) => ({ ...f, lenderName: e.target.value }))} />
              </FormField>
              <FormField label="Lender type">
                <Select value={form.lenderType} onValueChange={(v) => setForm((f) => ({ ...f, lenderType: v }))}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{LENDER_TYPES.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
              <FormField label="Account number">
                <Input value={form.accountNumber}
                       onChange={(e) => setForm((f) => ({ ...f, accountNumber: e.target.value }))} />
              </FormField>
            </FormSection>

            <FormSection title="The money" color="green">
              <FormField label="Amount borrowed *"
                         info="What the business OWES. This is what the debt starts at.">
                <NumberInput value={form.originalPrincipal} min={0} disabled={lightEdit}
                             onChange={(e) => setForm((f) => ({ ...f, originalPrincipal: e.target.value }))} />
              </FormField>
              <FormField label="Amount received"
                         info="What actually ARRIVED. Less than the principal when the lender withheld a fee.">
                <NumberInput value={form.amountReceived} min={0} disabled={lightEdit}
                             onChange={(e) => setForm((f) => ({ ...f, amountReceived: e.target.value }))} />
              </FormField>
              <FormField label="Cash account" full>
                <Select value={form.genericCashAccountId} disabled={lightEdit}
                        onValueChange={(v) => setForm((f) => ({ ...f, genericCashAccountId: v }))}>
                  <SelectTrigger><SelectValue placeholder="Where did the money land?" /></SelectTrigger>
                  <SelectContent>
                    {accounts.filter((a) => a.isActive || String(a.genericCashAccountId) === form.genericCashAccountId).map((a) => (
                      <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>
                        {a.accountName} — {fmt(a.currentBalance)}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </FormField>
              {!lightEdit && Number(form.originalPrincipal) > Number(form.amountReceived) && Number(form.amountReceived) > 0 && (
                <div className="col-span-full text-xs text-slate-500">
                  {fmt(Number(form.originalPrincipal) - Number(form.amountReceived))} less than the
                  principal — usually a fee the lender withheld. You will still owe the full{" "}
                  {fmt(Number(form.originalPrincipal))}. Record the fee as an expense yourself if you
                  want it in the accounts.
                </div>
              )}
            </FormSection>

            <FormSection title="Terms" color="blue">
              <FormField label="Start date *">
                <Input type="date" value={form.startDate} disabled={lightEdit}
                       onChange={(e) => setForm((f) => ({ ...f, startDate: e.target.value }))} />
              </FormField>
              <FormField label="Next payment due">
                <Input type="date" value={form.nextPaymentDate}
                       onChange={(e) => setForm((f) => ({ ...f, nextPaymentDate: e.target.value }))} />
              </FormField>
              <FormField label="Interest rate (%)">
                <NumberInput value={form.interestRate} min={0} disabled={lightEdit}
                             onChange={(e) => setForm((f) => ({ ...f, interestRate: e.target.value }))} />
              </FormField>
              <FormField label="Interest type">
                <Select value={form.interestType} disabled={lightEdit} onValueChange={(v) => setForm((f) => ({ ...f, interestType: v }))}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{INTEREST_TYPES.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
              <FormField label="Term (months)">
                <NumberInput value={form.termMonths} min={0} disabled={lightEdit}
                             onChange={(e) => setForm((f) => ({ ...f, termMonths: e.target.value }))} />
              </FormField>
              <FormField label="Repayment frequency">
                <Select value={form.paymentFrequency} disabled={lightEdit} onValueChange={(v) => setForm((f) => ({ ...f, paymentFrequency: v }))}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{FREQUENCIES.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
            </FormSection>

            {projectsEnabled && !lightEdit && (
              <FormSection title="Project / contract" color="slate" columns={1}>
                <FormField label="Project / contract">
                  <SingleProjectField value={project} onChange={changeProject} amount={Number(form.amountReceived) || 0}
                    showCostClass={false} label=""
                    hint="Borrowed for this project. Its repayments, interest and fees follow it on the project's P&L, cash flow and Financial Activity. A loan is financing, never revenue or profit." />
                </FormField>
              </FormSection>
            )}

            <FormSection title="Notes" color="slate" columns={1}>
              <FormField label="Notes">
                <Textarea rows={2} value={form.notes}
                          onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} />
              </FormField>
            </FormSection>
          </div>

          <div className="flex gap-3 justify-end pt-2">
            <Button type="button" onClick={() => { setNewOpen(false); setEditing(null) }}
                    className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
            {lightEdit ? (
              <Button onClick={() => saveLoan(false)} disabled={saving}>
                {saving ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving...</>
                        : <><Pencil className="w-4 h-4 mr-2" />Save Changes</>}
              </Button>
            ) : (
              <>
                <Button variant="outline" onClick={() => saveLoan(false)} disabled={saving}>
                  {saving ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Banknote className="w-4 h-4 mr-2" />}
                  {editing ? "Save Draft" : "Save as Draft"}
                </Button>
                <Button onClick={() => saveLoan(true)} disabled={saving}
                        className="bg-emerald-600 hover:bg-emerald-700 text-white">
                  {saving ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <CheckCircle2 className="w-4 h-4 mr-2" />}
                  Save &amp; Approve
                </Button>
              </>
            )}
          </div>
        </DialogContent>
      </Dialog>

      {/* ---- repayment (shared with Poultry and Water) ------------------ */}
      <LoanRepaymentDialog
        open={!!repaying}
        onOpenChange={(o) => { if (!o) setRepaying(null) }}
        accounts={repayAccounts}
        fmtMoney={fmt}
        loan={repaying ? toLoanOption(repaying) : null}
        entityLabel="business"
        onSubmit={async (input) => {
          await repayLoan(input.loanId, {
            genericCashAccountId: input.accountId,
            principalAmount: input.principalAmount,
            interestAmount: input.interestAmount,
            feeAmount: input.feeAmount,
            otherAmount: input.otherAmount,
            paymentDate: input.paymentDate,
            paymentMethod: input.paymentMethod,
            referenceNumber: input.referenceNumber,
            notes: input.notes,
            nextPaymentDate: input.nextPaymentDate,
          })
        }}
        onDone={() => { setRepaying(null); void load() }}
      />

      {/* ---- reverse ---------------------------------------------------- */}
      <Dialog open={!!reversing} onOpenChange={(o) => { if (!o) { setReversing(null); setReason("") } }}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Undo2 className="w-5 h-5 text-amber-600" /> Reverse Repayment
            </DialogTitle>
            <DialogDescription>
              The debt goes back up, the cash returns, and the interest and fee costs are cancelled.
              Every original row stays on the record.
            </DialogDescription>
          </DialogHeader>

          {reversing && (
            <div className="space-y-4">
              <FormSection title="Repayment being reversed" color="slate" columns={1}>
                <div className="text-sm">
                  <div className="font-medium">{reversing.paymentNumber ?? "#" + reversing.genericLoanPaymentId}</div>
                  <div className="mt-1">
                    {fmt(reversing.totalPayment)} on {fmtDateTime(reversing.paymentDate, reversing)}
                  </div>
                  <div className="text-xs text-slate-500 mt-1">
                    {fmt(reversing.principalAmount)} principal · {fmt(reversing.interestAmount)} interest ·{" "}
                    {fmt(reversing.feeAmount)} fees
                  </div>
                </div>
              </FormSection>

              <FormSection title="Why" color="amber" columns={1}>
                <FormField label="Reason *" hint="Written to the audit trail.">
                  <ReasonSelect options={LOAN_REVERSAL_REASONS} value={reason} onChange={setReason} />
                </FormField>
              </FormSection>
            </div>
          )}

          <div className="flex gap-3 justify-end pt-2">
            <Button type="button" onClick={() => { setReversing(null); setReason("") }}
                    className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
            <Button variant="destructive" onClick={doReverse} disabled={saving}>
              {saving ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Reversing...</>
                      : <><Undo2 className="w-4 h-4 mr-2" />Reverse</>}
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* ---- reverse to Draft (approved) / cancel (Draft) --------------- */}
      <Dialog open={!!cancelling} onOpenChange={(o) => { if (!o) { setCancelling(null); setReason("") } }}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              {cancelling && isDraft(cancelling)
                ? <><Ban className="w-5 h-5 text-rose-600" /> Cancel draft loan</>
                : <><Undo2 className="w-5 h-5 text-rose-600" /> Reverse loan to Draft</>}
            </DialogTitle>
            <DialogDescription>
              {cancelling && isDraft(cancelling)
                ? "Nothing has posted on a Draft, so no cash moves. It stays on the record as Cancelled."
                : "The money received is taken back out of the account it landed in and the debt comes off the books. The loan goes back to Draft, where everything can be corrected and approved again."}
            </DialogDescription>
          </DialogHeader>

          {cancelling && (
            <div className="space-y-4">
              <FormSection title={isDraft(cancelling) ? "Draft being cancelled" : "Loan being reversed"} color="slate" columns={1}>
                <div className="text-sm">
                  <div className="font-medium">{cancelling.loanNumber ?? "#" + cancelling.genericLoanId} · {cancelling.lenderName}</div>
                  <div className="mt-1">
                    {fmt(cancelling.originalPrincipal)} borrowed · {fmt(cancelling.amountReceived)} received
                    {cancelling.accountName ? ` into ${cancelling.accountName}` : ""}
                  </div>
                </div>
              </FormSection>

              {cancelling.paymentCount > 0 ? (
                <div className="rounded-md border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
                  This loan has {cancelling.paymentCount} repayment{cancelling.paymentCount === 1 ? "" : "s"}. Reverse
                  {cancelling.paymentCount === 1 ? " it" : " them"} first (open the loan&apos;s row and use Reverse on each
                  repayment), then reverse the loan.
                </div>
              ) : (
                <FormSection title="Why" color="amber" columns={1}>
                  <FormField label="Reason *" hint="Written to the audit trail.">
                    <ReasonSelect options={isDraft(cancelling) ? CANCEL_REASONS : LOAN_REVERSAL_REASONS} value={reason} onChange={setReason} />
                  </FormField>
                </FormSection>
              )}
            </div>
          )}

          <div className="flex gap-3 justify-end pt-2">
            <Button type="button" onClick={() => { setCancelling(null); setReason("") }}
                    className="bg-red-600 hover:bg-red-700 text-white">Keep loan</Button>
            <Button variant="destructive" onClick={doCancel} disabled={saving || (cancelling?.paymentCount ?? 0) > 0}>
              {saving ? <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                      : cancelling && isDraft(cancelling) ? <Ban className="w-4 h-4 mr-2" /> : <Undo2 className="w-4 h-4 mr-2" />}
              {cancelling && isDraft(cancelling) ? "Cancel draft" : "Reverse to Draft"}
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* ---- approve a Draft ---------------------------------------------- */}
      <Dialog open={!!approving} onOpenChange={(o) => { if (!o) setApproving(null) }}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <CheckCircle2 className="w-5 h-5 text-emerald-600" /> Approve loan
            </DialogTitle>
            <DialogDescription>
              Approving posts the loan: the money received goes into the account and the debt starts. After this only a
              light edit is allowed (lender, account number, next payment date, notes). To change anything else, reverse it
              back to Draft.
            </DialogDescription>
          </DialogHeader>

          {approving && (
            <FormSection title="Loan being approved" color="slate" columns={1}>
              <div className="text-sm">
                <div className="font-medium">{approving.loanNumber ?? "#" + approving.genericLoanId} · {approving.lenderName}</div>
                <div className="mt-1">
                  {fmt(approving.originalPrincipal)} borrowed · {fmt(approving.amountReceived)} received
                  {approving.amountReceived > 0 ? ` into ${approving.accountName ?? "— no account chosen"}` : ""}
                </div>
                <div className="text-xs text-slate-500 mt-1">{fmtDateTime(approving.startDate ?? approving.loanDate, approving)}</div>
              </div>
            </FormSection>
          )}

          <div className="flex gap-3 justify-end pt-2">
            <Button type="button" onClick={() => setApproving(null)}
                    className="bg-red-600 hover:bg-red-700 text-white">Not yet</Button>
            <Button onClick={doApprove} disabled={saving} className="bg-emerald-600 hover:bg-emerald-700 text-white">
              {saving ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Approving...</>
                      : <><CheckCircle2 className="w-4 h-4 mr-2" />Approve</>}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}

function Stat({
  label, value, hint, accent = "slate",
}: {
  label: string
  value: string
  hint?: string
  accent?: "slate" | "emerald" | "amber" | "rose" | "violet"
}) {
  const colour = {
    slate: "text-slate-900",
    emerald: "text-emerald-700",
    amber: "text-amber-700",
    rose: "text-rose-600",
    violet: "text-violet-700",
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
