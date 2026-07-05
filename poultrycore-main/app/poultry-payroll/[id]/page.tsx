"use client"

import { useEffect, useState } from "react"
import { useParams, useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Badge } from "@/components/ui/badge"
import { ArrowLeft, Loader2, Banknote } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { getPoultryPayrollRunDetails, type PoultryPayrollRunDetails } from "@/lib/api/poultry-finance"

const STATUS_STYLE: Record<string, string> = {
  Draft: "bg-slate-100 text-slate-700",
  Approved: "bg-blue-100 text-blue-700",
  Paid: "bg-green-100 text-green-700",
  Reopened: "bg-amber-100 text-amber-700",
  Cancelled: "bg-rose-100 text-rose-700",
}
const d = (s?: string | null) => (s ? s.split("T")[0] : "—")

export default function PoultryPayrollDetailPage() {
  const router = useRouter()
  const params = useParams<{ id: string }>()
  const id = Number(params?.id)
  const { toast } = useToast()
  const gh = useFmt()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [data, setData] = useState<PoultryPayrollRunDetails | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    if (id) void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, id])

  async function load() {
    setLoading(true)
    try { setData(await getPoultryPayrollRunDetails(id)) }
    catch (e: any) { toast({ title: "Could not load run", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  const run = data?.run
  const ytd = data?.ytdTotals
  const exp = data?.linkedExpense

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <Button asChild variant="ghost" size="sm" className="mb-2 -ml-2 text-slate-600">
            <Link href="/poultry-payroll"><ArrowLeft className="h-4 w-4 mr-1" /> Back to Payroll</Link>
          </Button>

          {loading ? (
            <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : !run ? (
            <div className="p-8 text-center text-slate-500">Payroll run not found.</div>
          ) : (
            <>
              <div className="mb-4 flex flex-wrap items-center gap-2">
                <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                  <Banknote className="h-6 w-6 text-green-600" />
                  Payroll · {d(run.periodStart)} → {d(run.periodEnd)}
                </h1>
                <Badge className={STATUS_STYLE[run.status] ?? ""}>{run.status}</Badge>
              </div>

              {/* Run summary */}
              <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4">
                <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Gross pay</div><div className="text-xl font-semibold tabular-nums">{gh(run.totalGrossPay)}</div></CardContent></Card>
                <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Deductions</div><div className="text-xl font-semibold tabular-nums text-rose-600">{gh(run.totalDeductions)}</div></CardContent></Card>
                <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Net pay</div><div className="text-xl font-semibold tabular-nums text-green-700">{gh(run.totalNetPay)}</div></CardContent></Card>
                <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Pay date</div><div className="text-xl font-semibold">{d(run.payDate)}</div></CardContent></Card>
              </div>

              {/* Employee breakdown */}
              <Card className="mb-4">
                <CardContent className="p-4">
                  <div className="mb-2 font-medium text-slate-700">Employee breakdown</div>
                  <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Staff</TableHead><TableHead>Role</TableHead>
                          <TableHead className="text-right">Basic</TableHead><TableHead className="text-right">Daily</TableHead>
                          <TableHead className="text-right">Commission</TableHead><TableHead className="text-right">Bonus</TableHead>
                          <TableHead className="text-right">Deductions</TableHead><TableHead className="text-right">Net</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {(run.items ?? []).length === 0 ? (
                          <TableRow><TableCell colSpan={8} className="text-center text-slate-500 py-4">No staff lines.</TableCell></TableRow>
                        ) : (run.items ?? []).map((it) => (
                          <TableRow key={it.poultryPayrollItemId}>
                            <TableCell className="font-medium">{it.staffName ?? `#${it.poultryStaffId}`}</TableCell>
                            <TableCell>{it.staffRole ?? "—"}</TableCell>
                            <TableCell className="text-right tabular-nums">{gh(it.basicPay)}</TableCell>
                            <TableCell className="text-right tabular-nums">{gh(it.dailyWage)}</TableCell>
                            <TableCell className="text-right tabular-nums">{gh(it.commission)}</TableCell>
                            <TableCell className="text-right tabular-nums">{gh(it.bonus)}</TableCell>
                            <TableCell className="text-right tabular-nums">{gh(it.deductions)}</TableCell>
                            <TableCell className="text-right tabular-nums font-semibold">{gh(it.netPay)}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </div>
                </CardContent>
              </Card>

              {/* YTD */}
              {ytd && (
                <>
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4">
                    <Card><CardContent className="p-4"><div className="text-xs text-slate-500">YTD gross ({ytd.year})</div><div className="text-lg font-semibold tabular-nums">{gh(ytd.ytdGrossPaid)}</div></CardContent></Card>
                    <Card><CardContent className="p-4"><div className="text-xs text-slate-500">YTD net paid</div><div className="text-lg font-semibold tabular-nums text-green-700">{gh(ytd.ytdNetPaid)}</div></CardContent></Card>
                    <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Payroll runs</div><div className="text-lg font-semibold">{ytd.totalPayrollRuns}</div></CardContent></Card>
                    <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Staff paid</div><div className="text-lg font-semibold">{ytd.totalStaffPaid}</div></CardContent></Card>
                  </div>

                  {data!.ytdByStaff.length > 0 && (
                    <Card className="mb-4">
                      <CardContent className="p-4">
                        <div className="mb-2 font-medium text-slate-700">Year-to-date by staff ({ytd.year})</div>
                        <div className="overflow-x-auto">
                          <Table>
                            <TableHeader>
                              <TableRow>
                                <TableHead>Staff</TableHead><TableHead>Role</TableHead>
                                <TableHead className="text-right">YTD gross</TableHead>
                                <TableHead className="text-right">YTD deductions</TableHead>
                                <TableHead className="text-right">YTD net</TableHead>
                              </TableRow>
                            </TableHeader>
                            <TableBody>
                              {data!.ytdByStaff.map((s) => (
                                <TableRow key={s.poultryStaffId}>
                                  <TableCell className="font-medium">{s.staffName ?? `#${s.poultryStaffId}`}</TableCell>
                                  <TableCell>{s.staffRole ?? "—"}</TableCell>
                                  <TableCell className="text-right tabular-nums">{gh(s.ytdGross)}</TableCell>
                                  <TableCell className="text-right tabular-nums">{gh(s.ytdDeductions)}</TableCell>
                                  <TableCell className="text-right tabular-nums font-semibold">{gh(s.ytdNet)}</TableCell>
                                </TableRow>
                              ))}
                            </TableBody>
                          </Table>
                        </div>
                      </CardContent>
                    </Card>
                  )}
                </>
              )}

              {/* Linked expense + audit */}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <Card>
                  <CardContent className="p-4">
                    <div className="mb-2 font-medium text-slate-700">Linked expense</div>
                    {exp ? (
                      <dl className="text-sm space-y-1">
                        <div className="flex justify-between"><dt className="text-slate-500">Category</dt><dd>{exp.category ?? "Payroll"}</dd></div>
                        <div className="flex justify-between"><dt className="text-slate-500">Amount</dt><dd className="tabular-nums font-medium">{gh(exp.amount)}</dd></div>
                        <div className="flex justify-between"><dt className="text-slate-500">Date</dt><dd>{d(exp.expenseDate)}</dd></div>
                        <div className="flex justify-between"><dt className="text-slate-500">Description</dt><dd className="text-right">{exp.description ?? "—"}</dd></div>
                      </dl>
                    ) : (
                      <p className="text-sm text-slate-500">No linked expense (created when the run is approved).</p>
                    )}
                  </CardContent>
                </Card>
                <Card>
                  <CardContent className="p-4">
                    <div className="mb-2 font-medium text-slate-700">Audit</div>
                    <dl className="text-sm space-y-1">
                      <div className="flex justify-between"><dt className="text-slate-500">Created by</dt><dd>{run.createdBy ?? "—"}</dd></div>
                      <div className="flex justify-between"><dt className="text-slate-500">Approved</dt><dd>{run.approvedBy ? `${run.approvedBy} · ${d(run.approvedAt)}` : "—"}</dd></div>
                      <div className="flex justify-between"><dt className="text-slate-500">Paid</dt><dd>{run.paidBy ? `${run.paidBy} · ${d(run.paidAt)}` : "—"}</dd></div>
                      {run.reopenedBy && <div className="flex justify-between"><dt className="text-slate-500">Reopened</dt><dd>{run.reopenedBy} · {d(run.reopenedAt)}</dd></div>}
                      {run.reopenReason && <div className="flex justify-between"><dt className="text-slate-500">Reopen reason</dt><dd className="text-right">{run.reopenReason}</dd></div>}
                      {run.reapprovedBy && <div className="flex justify-between"><dt className="text-slate-500">Reapproved</dt><dd>{run.reapprovedBy} · {d(run.reapprovedAt)}</dd></div>}
                      <div className="flex justify-between"><dt className="text-slate-500">Cash account</dt><dd>{run.cashAccountName ?? "—"}</dd></div>
                    </dl>
                  </CardContent>
                </Card>
              </div>
            </>
          )}
        </main>
      </div>
    </div>
  )
}
