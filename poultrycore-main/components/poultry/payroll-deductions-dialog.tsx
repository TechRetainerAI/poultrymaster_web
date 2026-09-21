"use client"

// What a payroll deduction actually IS (migration 306, spec sections 30-32).
//
// The Employee Breakdown keeps ONE Deductions column, because eight money
// columns already do not fit a phone and a column per deduction type would be
// unreadable within a month. The total is a button instead, and this is what it
// opens: the rows behind it, which always add up to exactly the figure on the
// payslip.
//
// THE LEGACY ROW
// --------------
// A run entered before deductions were itemised carries an amount with nothing
// behind it. That part comes back from the server as a row with a NULL id --
// it is the unexplained REMAINDER, computed, not stored. It renders greyed out
// with no delete button, and it is never described as a loan repayment:
// reinterpreting an old deduction would be inventing history (section 29).
//
// WHAT THIS DIALOG CANNOT DO
// --------------------------
// Move a loan balance. Every row added here is a PLAN until the payroll run is
// approved, which is the only thing that posts a repayment (section 38). The
// footer says so, because the natural assumption on typing "100" against an
// advance is that 100 has just come off it.

import { useCallback, useEffect, useState } from "react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Label } from "@/components/ui/label"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Loader2, Plus, Trash2, Info } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { cn } from "@/lib/utils"
import {
  listPoultryPayrollDeductions, savePoultryPayrollDeduction,
  deletePoultryPayrollDeduction, listEligiblePoultryEmployeeLoans,
  PAYROLL_DEDUCTION_TYPES, PAYROLL_DEDUCTION_TYPE_LABELS,
  type PoultryPayrollDeduction, type PoultryEmployeeLoanEligible,
} from "@/lib/api/poultry-finance"

export interface PayrollDeductionTarget {
  poultryPayrollItemId: number
  poultryStaffId: number
  staffName: string
  /** The run's status: lines are editable while Draft or Reopened. */
  runStatus: string
}

export function PayrollDeductionsDialog({
  target, onClose, onChanged, fmt,
}: {
  target: PayrollDeductionTarget | null
  onClose: () => void
  /** Called after any change, so the payslip's total can be re-read. */
  onChanged: () => void | Promise<void>
  fmt: (n: number) => string
}) {
  const { toast } = useToast()
  const [rows, setRows] = useState<PoultryPayrollDeduction[]>([])
  const [eligible, setEligible] = useState<PoultryEmployeeLoanEligible[]>([])
  const [loading, setLoading] = useState(false)
  const [busy, setBusy] = useState(false)

  const [type, setType] = useState<string>("EmployeeLoanRepayment")
  const [loanId, setLoanId] = useState<string>("")
  const [amount, setAmount] = useState(0)
  const [description, setDescription] = useState("")

  const editable = target?.runStatus === "Draft" || target?.runStatus === "Reopened"
  const isLoanType = type === "EmployeeLoanRepayment" || type === "SalaryAdvanceRepayment"
  const chosen = eligible.find((e) => String(e.poultryEmployeeLoanId) === loanId)

  const load = useCallback(async () => {
    if (!target) return
    setLoading(true)
    try {
      const [ded, elig] = await Promise.all([
        listPoultryPayrollDeductions(target.poultryPayrollItemId),
        listEligiblePoultryEmployeeLoans(target.poultryStaffId),
      ])
      setRows(ded)
      setEligible(elig)
      // Offer the advance's own suggested amount, which is what section 36
      // means by a suggestion: it is filled in, and it is not posted.
      if (elig.length > 0) {
        setLoanId(String(elig[0].poultryEmployeeLoanId))
        setAmount(Math.min(elig[0].defaultPayrollDeduction ?? 0, elig[0].outstandingBalance))
      } else {
        setLoanId("")
        setType("OtherDeduction")
      }
    } catch (e: any) {
      toast({ title: "Could not load the breakdown", description: e?.message, variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }, [target, toast])

  useEffect(() => { void load() }, [load])

  if (!target) return null

  const total = rows.reduce((s, r) => s + r.amount, 0)
  // Never more than is left, and what other draft rows already claim against
  // the same advance is the server's job to police -- this is the first line of
  // defence, not the only one.
  const over = isLoanType && chosen ? amount > chosen.outstandingBalance : false
  const canAdd = editable && amount > 0 && !over && (!isLoanType || !!loanId)

  const run = async (fn: () => Promise<void>, ok: string) => {
    setBusy(true)
    try {
      await fn()
      toast({ title: ok })
      await load()
      await onChanged()
    } catch (e: any) {
      toast({ title: "That did not work", description: e?.message, variant: "destructive" })
    } finally {
      setBusy(false)
    }
  }

  return (
    <Dialog open onOpenChange={(o) => { if (!o) onClose() }}>
      <DialogContent className="w-[95vw] sm:max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Deductions — {target.staffName}</DialogTitle>
          <DialogDescription>
            What the money taken off this payslip is for. These rows always add up to the
            Deductions figure on the line.
          </DialogDescription>
        </DialogHeader>

        {loading ? (
          <div className="flex items-center gap-2 py-6 text-sm text-slate-500">
            <Loader2 className="h-4 w-4 animate-spin" /> Loading…
          </div>
        ) : (
          <>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>What for</TableHead>
                  <TableHead>Detail</TableHead>
                  <TableHead className="text-right">Amount</TableHead>
                  <TableHead className="w-12" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={4} className="py-4 text-center text-sm text-slate-500">
                      Nothing deducted from this payslip.
                    </TableCell>
                  </TableRow>
                ) : rows.map((r, i) => (
                  <TableRow key={r.poultryPayrollItemDeductionId ?? `legacy-${i}`}
                            className={cn(r.isLegacy && "text-slate-500")}>
                    <TableCell>
                      {r.isLegacy
                        ? "Other deduction"
                        : PAYROLL_DEDUCTION_TYPE_LABELS[r.deductionType] ?? r.deductionType}
                      {r.status === "Posted" && !r.isLegacy && (
                        <Badge className="ml-2 bg-emerald-100 text-emerald-700">Posted</Badge>
                      )}
                    </TableCell>
                    <TableCell className="text-xs">
                      {r.loanNumber
                        ? <>{r.loanNumber}
                            {r.loanOutstanding != null && (
                              <span className="text-slate-400"> · {fmt(r.loanOutstanding)} left</span>
                            )}
                          </>
                        : (r.description || "—")}
                    </TableCell>
                    <TableCell className="text-right tabular-nums">{fmt(r.amount)}</TableCell>
                    <TableCell className="text-right">
                      {/* Draft rows only. A posted one has a repayment behind it
                          and is undone by reopening the payroll; a legacy row is
                          a leftover, not a record, so there is nothing to delete. */}
                      {editable && !r.isLegacy && r.status === "Draft" && r.poultryPayrollItemDeductionId && (
                        <Button size="sm" variant="ghost" disabled={busy}
                                onClick={() => void run(
                                  () => deletePoultryPayrollDeduction(r.poultryPayrollItemDeductionId!),
                                  "Deduction removed")}>
                          <Trash2 className="h-4 w-4 text-red-500" />
                        </Button>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
                <TableRow className="border-t-2">
                  <TableCell colSpan={2} className="font-semibold">Total</TableCell>
                  <TableCell className="text-right font-semibold tabular-nums">{fmt(total)}</TableCell>
                  <TableCell />
                </TableRow>
              </TableBody>
            </Table>

            {editable ? (
              <div className="rounded-md border p-3 space-y-3">
                <div className="text-sm font-medium">Add a deduction</div>
                <div className="grid gap-3 sm:grid-cols-2">
                  <div className="space-y-1">
                    <Label>What for *</Label>
                    <Select value={type} onValueChange={(v) => { setType(v); if (v === "OtherDeduction") setLoanId("") }}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>
                        {PAYROLL_DEDUCTION_TYPES.map((t) => (
                          <SelectItem key={t} value={t} disabled={t !== "OtherDeduction" && eligible.length === 0}>
                            {PAYROLL_DEDUCTION_TYPE_LABELS[t]}
                            {t !== "OtherDeduction" && eligible.length === 0 ? " (no active advances)" : ""}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>

                  {isLoanType && (
                    <div className="space-y-1">
                      <Label>Which advance *</Label>
                      <Select value={loanId} onValueChange={(v) => {
                        setLoanId(v)
                        const e = eligible.find((x) => String(x.poultryEmployeeLoanId) === v)
                        if (e) setAmount(Math.min(e.defaultPayrollDeduction ?? 0, e.outstandingBalance))
                      }}>
                        <SelectTrigger><SelectValue placeholder="Choose an advance" /></SelectTrigger>
                        <SelectContent>
                          {/* Only this worker's live advances. The server applies
                              the same rule when the payroll is approved. */}
                          {eligible.map((e) => (
                            <SelectItem key={e.poultryEmployeeLoanId} value={String(e.poultryEmployeeLoanId)}>
                              {e.loanNumber} — {fmt(e.outstandingBalance)} outstanding
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                  )}

                  <div className="space-y-1">
                    <Label>Amount *</Label>
                    <NumberInput step="0.01" value={amount}
                                 onChange={(e) => setAmount(Number(e.target.value) || 0)} />
                    {over && chosen && (
                      <p className="text-[11px] text-rose-600">
                        Only {fmt(chosen.outstandingBalance)} is left on {chosen.loanNumber}.
                      </p>
                    )}
                  </div>

                  {!isLoanType && (
                    <div className="space-y-1">
                      <Label>What is it</Label>
                      <Input value={description} onChange={(e) => setDescription(e.target.value)}
                             placeholder="Uniform, tools, damage…" />
                    </div>
                  )}
                </div>

                <div className="flex justify-end">
                  <Button disabled={busy || !canAdd} onClick={() => void run(async () => {
                    await savePoultryPayrollDeduction({
                      poultryPayrollItemId: target.poultryPayrollItemId,
                      deductionType: type,
                      amount,
                      poultryEmployeeLoanId: isLoanType ? Number(loanId) : null,
                      description: description || null,
                    })
                    setAmount(0)
                    setDescription("")
                  }, "Deduction added")}>
                    {busy ? <Loader2 className="h-4 w-4 mr-1 animate-spin" /> : <Plus className="h-4 w-4 mr-1" />}
                    Add
                  </Button>
                </div>
              </div>
            ) : (
              <p className="rounded-md bg-slate-50 p-3 text-xs text-slate-600">
                This payroll is {target.runStatus}. Reopen it to change deductions.
              </p>
            )}

            {/* Section 38, said out loud. Typing 100 against an advance looks
                like it has just taken 100 off it, and it has not. */}
            <div className="flex items-start gap-2 rounded-md border border-sky-200 bg-sky-50 p-3">
              <Info className="h-4 w-4 text-sky-700 mt-0.5 shrink-0" />
              <p className="text-xs text-sky-900">
                Nothing here changes what a worker owes yet. Advances are only repaid when this
                payroll is <strong>approved</strong> — and reopening it puts them back.
              </p>
            </div>
          </>
        )}
      </DialogContent>
    </Dialog>
  )
}
