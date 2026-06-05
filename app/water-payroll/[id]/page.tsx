"use client"

// Migration 082 — Full Payroll Run Details page (spec "Payroll Details Page,
// Delivery Return Approval, …" §1). One round-trip to
// /Water/payroll-runs/{id}/details returns: header, employee breakdown,
// year-to-date totals + per-staff YTD, and the linked WaterExpense (if any).
//
// This page is the destination for:
//   * Payroll list → "Open details" action
//   * /water-expenses Source column → Payroll #{id} link
//     (components/water/expense-source-link.tsx already routes here)

import { useEffect, useMemo, useState } from "react"
import { useRouter, useParams } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import {
  ArrowLeft, Banknote, Calendar, CheckCircle2, Loader2, Receipt,
  Trash2, RotateCcw, ExternalLink, FileText,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  getWaterPayrollRunDetails, approveWaterPayrollRun, markWaterPayrollRunPaid,
  unapproveWaterPayrollRun, deleteWaterPayrollRun,
  type WaterPayrollRunDetails,
} from "@/lib/api/water"

const STATUS_COLORS: Record<string, string> = {
  Draft:     "bg-slate-100 text-slate-700",
  Pending:   "bg-slate-100 text-slate-700",
  Approved:  "bg-blue-100 text-blue-700",
  Paid:      "bg-green-100 text-green-700",
  Reopened:  "bg-amber-100 text-amber-800",
  Cancelled: "bg-rose-100 text-rose-700",
}

const EDITABLE = new Set(["Draft", "Pending", "Reopened"])

function StatTile({ label, value, accent }: { label: string; value: string; accent?: string }) {
  return (
    <div className="rounded-md border bg-white p-3">
      <div className="text-xs text-slate-500">{label}</div>
      <div className={`text-xl font-semibold tabular-nums mt-1 ${accent ?? "text-slate-900"}`}>{value}</div>
    </div>
  )
}

export default function WaterPayrollDetailsPage() {
  const router = useRouter()
  const params = useParams<{ id: string }>()
  const id = Number(params?.id ?? 0)
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [data, setData] = useState<WaterPayrollRunDetails | null>(null)
  const [loading, setLoading] = useState(true)
  const [unapproveOpen, setUnapproveOpen] = useState(false)
  const [deleteOpen, setDeleteOpen] = useState(false)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    if (!id) return
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, id])

  async function load() {
    setLoading(true)
    try {
      setData(await getWaterPayrollRunDetails(id))
    } catch (e: any) {
      toast({ title: "Could not load payroll", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  const run = data?.run ?? null
  const ytd = data?.ytdTotals ?? null
  const expense = data?.linkedExpense ?? null
  const isEditable = run ? EDITABLE.has(run.status) : false

  const period = useMemo(() => {
    if (!run) return ""
    return `${run.periodStart.split("T")[0]} → ${run.periodEnd.split("T")[0]}`
  }, [run])

  async function doApprove() {
    if (!run) return
    try {
      await approveWaterPayrollRun(run.waterPayrollRunId)
      toast({ title: run.status === "Reopened" ? "Run re-approved" : "Run approved" })
      await load()
    } catch (e: any) { toast({ title: "Approve failed", description: e?.message, variant: "destructive" }) }
  }
  async function doPay() {
    if (!run) return
    try {
      await markWaterPayrollRunPaid(run.waterPayrollRunId)
      toast({ title: "Marked paid" })
      await load()
    } catch (e: any) { toast({ title: "Mark paid failed", description: e?.message, variant: "destructive" }) }
  }
  async function confirmUnapprove(reason: string) {
    if (!run) return
    if (!reason.trim()) {
      toast({ title: "Reason required", variant: "destructive" })
      throw new Error("Reason required")
    }
    try {
      await unapproveWaterPayrollRun(run.waterPayrollRunId, reason.trim())
      toast({ title: "Run reopened" })
      setUnapproveOpen(false)
      await load()
    } catch (e: any) {
      toast({ title: "Reopen failed", description: e?.message, variant: "destructive" })
      throw e
    }
  }
  async function performDelete() {
    if (!run) return
    await deleteWaterPayrollRun(run.waterPayrollRunId)
    router.replace("/water-payroll")
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6 space-y-4">
          <div className="flex items-center gap-2">
            <Button asChild size="sm" variant="ghost"><Link href="/water-payroll"><ArrowLeft className="h-4 w-4 mr-1" /> Payroll runs</Link></Button>
          </div>

          {loading ? (
            <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : !run ? (
            <Card><CardContent className="p-6 text-slate-500">Payroll run not found.</CardContent></Card>
          ) : (
            <>
              {/* Header */}
              <Card>
                <CardContent className="p-4 md:p-5 space-y-3">
                  <div className="flex flex-wrap items-center justify-between gap-3">
                    <div className="flex items-center gap-2">
                      <Banknote className="h-6 w-6 text-sky-600" />
                      <h1 className="text-2xl font-semibold text-slate-900">
                        Payroll Run #{run.waterPayrollRunId}
                      </h1>
                      <Badge className={STATUS_COLORS[run.status] ?? ""}>{run.status}</Badge>
                    </div>
                    <div className="flex flex-wrap gap-2">
                      {isEditable && (
                        <Button size="sm" onClick={doApprove}>
                          <CheckCircle2 className="h-4 w-4 mr-1" /> {run.status === "Reopened" ? "Re-approve" : "Approve"}
                        </Button>
                      )}
                      {run.status === "Approved" && (
                        <Button size="sm" variant="outline" onClick={doPay}>Mark paid</Button>
                      )}
                      {(run.status === "Approved" || run.status === "Paid") && (
                        <Button size="sm" variant="outline" className="text-amber-700 border-amber-200" onClick={() => setUnapproveOpen(true)}>
                          <RotateCcw className="h-4 w-4 mr-1" /> Reopen
                        </Button>
                      )}
                      {isEditable && (
                        <Button size="sm" variant="outline" className="text-red-600 border-red-200" onClick={() => setDeleteOpen(true)}>
                          <Trash2 className="h-4 w-4 mr-1" /> Delete
                        </Button>
                      )}
                    </div>
                  </div>

                  <div className="grid grid-cols-2 md:grid-cols-4 gap-2 text-sm">
                    <div className="flex items-center gap-1"><Calendar className="h-3.5 w-3.5 text-slate-400" /><span className="text-slate-500">Period:</span> <span className="font-medium">{period}</span></div>
                    <div><span className="text-slate-500">Pay date:</span> <span className="font-medium">{run.payDate?.split("T")[0] ?? "—"}</span></div>
                    <div><span className="text-slate-500">Cash account:</span> <span className="font-medium">{run.cashAccountName ?? "—"}</span></div>
                    <div><span className="text-slate-500">Notes:</span> <span>{run.notes ?? "—"}</span></div>
                  </div>

                  <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
                    <StatTile label="Gross"      value={run.totalGrossPay.toFixed(2)} />
                    <StatTile label="Deductions" value={run.totalDeductions.toFixed(2)} accent="text-rose-700" />
                    <StatTile label="Net"        value={run.totalNetPay.toFixed(2)} accent="text-emerald-700" />
                  </div>
                </CardContent>
              </Card>

              {/* Audit history */}
              {(run.approvedBy || run.paidBy || run.reopenedBy || run.reapprovedBy || run.createdBy) && (
                <Card>
                  <CardContent className="p-4 space-y-2">
                    <div className="font-medium flex items-center gap-2"><FileText className="h-4 w-4 text-slate-400" /> History</div>
                    <ul className="text-sm text-slate-600 space-y-1">
                      {run.createdBy && <li>Created by <span className="font-medium">{run.createdBy}</span> on {run.createdAt.split("T")[0]}</li>}
                      {run.approvedBy && <li>Approved by <span className="font-medium">{run.approvedBy}</span>{run.approvedAt ? ` on ${run.approvedAt.split("T")[0]}` : ""}</li>}
                      {run.paidBy && <li>Paid by <span className="font-medium">{run.paidBy}</span>{run.paidAt ? ` on ${run.paidAt.split("T")[0]}` : ""}</li>}
                      {run.reopenedBy && (
                        <li>
                          Reopened by <span className="font-medium">{run.reopenedBy}</span>
                          {run.reopenedAt ? ` on ${run.reopenedAt.split("T")[0]}` : ""}
                          {run.reopenReason ? <> — <span className="italic">"{run.reopenReason}"</span></> : null}
                        </li>
                      )}
                      {run.reapprovedBy && <li>Re-approved by <span className="font-medium">{run.reapprovedBy}</span>{run.reapprovedAt ? ` on ${run.reapprovedAt.split("T")[0]}` : ""}</li>}
                    </ul>
                  </CardContent>
                </Card>
              )}

              {/* Employee breakdown */}
              <Card>
                <CardContent className="p-0">
                  <div className="px-4 py-3 border-b font-medium">Employee breakdown</div>
                  {!run.items?.length ? (
                    <div className="p-6 text-slate-500 text-sm">No payroll items for this run.</div>
                  ) : (
                    <div className="overflow-x-auto">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Staff</TableHead>
                            <TableHead className="text-right">Basic</TableHead>
                            <TableHead className="text-right">Daily</TableHead>
                            <TableHead className="text-right">Commission</TableHead>
                            <TableHead className="text-right">Bonus</TableHead>
                            <TableHead className="text-right">Deductions</TableHead>
                            <TableHead className="text-right">Gross</TableHead>
                            <TableHead className="text-right">Net</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {run.items.map((i) => {
                            const gross = i.basicPay + i.dailyWage + i.commission + i.bonus
                            return (
                              <TableRow key={i.waterPayrollItemId}>
                                <TableCell className="font-medium">{i.staffName ?? `Staff #${i.waterStaffId}`}</TableCell>
                                <TableCell className="text-right tabular-nums">{i.basicPay.toFixed(2)}</TableCell>
                                <TableCell className="text-right tabular-nums">{i.dailyWage.toFixed(2)}</TableCell>
                                <TableCell className="text-right tabular-nums">{i.commission.toFixed(2)}</TableCell>
                                <TableCell className="text-right tabular-nums">{i.bonus.toFixed(2)}</TableCell>
                                <TableCell className="text-right tabular-nums text-rose-700">{i.deductions.toFixed(2)}</TableCell>
                                <TableCell className="text-right tabular-nums">{gross.toFixed(2)}</TableCell>
                                <TableCell className="text-right tabular-nums font-semibold text-emerald-700">{i.netPay.toFixed(2)}</TableCell>
                              </TableRow>
                            )
                          })}
                        </TableBody>
                      </Table>
                    </div>
                  )}
                </CardContent>
              </Card>

              {/* YTD section */}
              <Card>
                <CardContent className="p-4 space-y-3">
                  <div className="font-medium">Year-to-date · {ytd?.year ?? "—"}</div>
                  <div className="grid grid-cols-2 md:grid-cols-5 gap-2 text-sm">
                    <StatTile label="YTD Gross"        value={(ytd?.ytdGrossPaid ?? 0).toFixed(2)} />
                    <StatTile label="YTD Deductions"   value={(ytd?.ytdDeductions ?? 0).toFixed(2)} accent="text-rose-700" />
                    <StatTile label="YTD Net"          value={(ytd?.ytdNetPaid ?? 0).toFixed(2)}    accent="text-emerald-700" />
                    <StatTile label="Total runs"       value={String(ytd?.totalPayrollRuns ?? 0)} />
                    <StatTile label="Distinct staff"   value={String(ytd?.totalStaffPaid   ?? 0)} />
                  </div>

                  {data?.ytdByStaff?.length ? (
                    <div className="overflow-x-auto">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Staff</TableHead>
                            <TableHead className="text-right">YTD Basic</TableHead>
                            <TableHead className="text-right">YTD Daily</TableHead>
                            <TableHead className="text-right">YTD Commission</TableHead>
                            <TableHead className="text-right">YTD Bonus</TableHead>
                            <TableHead className="text-right">YTD Deductions</TableHead>
                            <TableHead className="text-right">YTD Gross</TableHead>
                            <TableHead className="text-right">YTD Net</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {data!.ytdByStaff.map((s) => (
                            <TableRow key={s.waterStaffId}>
                              <TableCell className="font-medium">{s.staffName ?? `Staff #${s.waterStaffId}`}</TableCell>
                              <TableCell className="text-right tabular-nums">{s.ytdBasic.toFixed(2)}</TableCell>
                              <TableCell className="text-right tabular-nums">{s.ytdDaily.toFixed(2)}</TableCell>
                              <TableCell className="text-right tabular-nums">{s.ytdCommission.toFixed(2)}</TableCell>
                              <TableCell className="text-right tabular-nums">{s.ytdBonus.toFixed(2)}</TableCell>
                              <TableCell className="text-right tabular-nums text-rose-700">{s.ytdDeductions.toFixed(2)}</TableCell>
                              <TableCell className="text-right tabular-nums">{s.ytdGross.toFixed(2)}</TableCell>
                              <TableCell className="text-right tabular-nums font-semibold text-emerald-700">{s.ytdNet.toFixed(2)}</TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    </div>
                  ) : (
                    <div className="text-sm text-slate-500">No approved/paid runs in this year yet.</div>
                  )}
                </CardContent>
              </Card>

              {/* Linked expense */}
              <Card>
                <CardContent className="p-4 space-y-3">
                  <div className="font-medium flex items-center gap-2"><Receipt className="h-4 w-4 text-slate-400" /> Linked expense</div>
                  {expense ? (
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-2 text-sm">
                      <div><span className="text-slate-500">Category:</span> {expense.categoryName ?? `#${expense.waterExpenseCategoryId}`}</div>
                      <div><span className="text-slate-500">Amount:</span> <span className="font-semibold tabular-nums">{expense.amount.toFixed(2)}</span></div>
                      <div><span className="text-slate-500">Date:</span> {expense.expenseDate.split("T")[0]}</div>
                      <div><span className="text-slate-500">Status:</span> <Badge variant="outline">{expense.status ?? "—"}</Badge></div>
                      <div><span className="text-slate-500">Payment:</span> {expense.paymentMethod ?? "—"} {expense.cashAccountName ? `· ${expense.cashAccountName}` : ""}</div>
                      <div><span className="text-slate-500">Source:</span> {expense.sourceType} #{expense.sourceId}</div>
                      <div className="md:col-span-2"><span className="text-slate-500">Description:</span> {expense.description ?? "—"}</div>
                      <div className="md:col-span-2">
                        <Button asChild size="sm" variant="outline">
                          <Link href={`/water-expenses`}>
                            <ExternalLink className="h-4 w-4 mr-1" /> Open in Expenses
                          </Link>
                        </Button>
                      </div>
                    </div>
                  ) : (
                    <div className="text-sm text-slate-500">
                      No linked expense yet. An expense is created automatically when this run is approved
                      (migration 075) and reversed on Cancel/Unapprove.
                    </div>
                  )}
                </CardContent>
              </Card>
            </>
          )}
        </main>
      </div>

      <PromptDialog
        open={unapproveOpen}
        onOpenChange={setUnapproveOpen}
        title="Reopen payroll run"
        description={run ? `Run ${period} will be reopened. The linked payroll expense will be reversed${run.status === "Paid" ? " and the cash account refunded" : ""}.` : ""}
        label="Reason *"
        placeholder="e.g. wrong amount for Kofi, missed bonus, correcting period…"
        confirmLabel="Reopen run"
        confirmVariant="destructive"
        onSubmit={confirmUnapprove}
      />

      <ConfirmDeleteDialog
        open={deleteOpen}
        onOpenChange={setDeleteOpen}
        title="Delete payroll run?"
        description="This removes the payroll run and all its employee payroll lines. Only available while the run is Draft, Pending, or Reopened — and never while an approved expense is still linked."
        itemLabel={period}
        successTitle="Payroll run removed"
        errorTitle="Delete failed"
        onConfirm={performDelete}
      />
    </div>
  )
}
