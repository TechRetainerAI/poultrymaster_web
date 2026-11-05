"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Badge } from "@/components/ui/badge"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { Landmark, Plus, Loader2, Banknote, TrendingDown } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import { getLoans, createLoan, getLoanPayments, repayLoan, type GenericLoan, type GenericLoanPayment } from "@/lib/api/generic"
import { fmtDateTime } from "@/lib/utils/company-datetime"

const STATUS_COLORS: Record<string, string> = {
  Active: "bg-blue-100 text-blue-700", Paid: "bg-emerald-100 text-emerald-700", Defaulted: "bg-red-100 text-red-700",
}

export default function GenericLoansPage() {
  const router = useRouter()
  const logout = useLogout()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const gh = useFmt()

  const [rows, setRows] = useState<GenericLoan[]>([])
  const [loading, setLoading] = useState(true)
  const [createOpen, setCreateOpen] = useState(false)
  const [repayTarget, setRepayTarget] = useState<GenericLoan | null>(null)
  const [payments, setPayments] = useState<GenericLoanPayment[]>([])
  const [paymentsTarget, setPaymentsTarget] = useState<GenericLoan | null>(null)
  const [saving, setSaving] = useState(false)

  const [form, setForm] = useState({
    lenderName: "", originalPrincipal: 0, amountReceived: 0, interestRate: 0,
    loanDate: new Date().toISOString().split("T")[0], startDate: "", dueDate: "", notes: "",
  })
  const [repayForm, setRepayForm] = useState({
    principalAmount: 0, interestAmount: 0, feeAmount: 0,
    paymentDate: new Date().toISOString().split("T")[0], notes: "",
  })

  const pg = usePagination(rows)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try { setRows(await getLoans()) }
    catch (e: any) { toast({ title: "Could not load loans", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  const totals = useMemo(() => {
    let borrowed = 0, outstanding = 0, repaid = 0
    for (const l of rows) { borrowed += l.originalPrincipal; outstanding += l.outstandingBalance; repaid += l.totalPrincipalPaid }
    return { borrowed, outstanding, repaid, active: rows.filter((l) => l.status === "Active").length }
  }, [rows])

  async function doCreate() {
    if (!form.lenderName.trim()) { toast({ title: "Lender name is required", variant: "destructive" }); return }
    if (form.originalPrincipal <= 0) { toast({ title: "Amount must be > 0", variant: "destructive" }); return }
    setSaving(true)
    try {
      await createLoan({ ...form, amountReceived: form.amountReceived || form.originalPrincipal })
      toast({ title: "Loan recorded" })
      setCreateOpen(false)
      setForm({ lenderName: "", originalPrincipal: 0, amountReceived: 0, interestRate: 0, loanDate: new Date().toISOString().split("T")[0], startDate: "", dueDate: "", notes: "" })
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
      await repayLoan(repayTarget.genericLoanId, repayForm)
      toast({ title: "Repayment recorded" })
      setRepayTarget(null)
      await load()
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function showPayments(loan: GenericLoan) {
    setPaymentsTarget(loan)
    try { setPayments(await getLoanPayments(loan.genericLoanId)) }
    catch { setPayments([]) }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-3 md:p-4 space-y-3">
          <div className="flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-xl font-semibold text-slate-900 flex items-center gap-2">
                <Landmark className="h-5 w-5 text-emerald-600" /> Loans (Financing)
              </h1>
              <p className="text-xs text-slate-500">Record, repay and track business loans.</p>
            </div>
            <Button onClick={() => setCreateOpen(true)}><Plus className="h-4 w-4 mr-1" /> New Loan</Button>
          </div>

          <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
            <Card><CardContent className="p-3">
              <div className="text-[11px] uppercase tracking-wide text-slate-500">Total Borrowed</div>
              <div className="mt-1 text-lg font-semibold tabular-nums">{gh(totals.borrowed)}</div>
            </CardContent></Card>
            <Card><CardContent className="p-3">
              <div className="text-[11px] uppercase tracking-wide text-slate-500">Outstanding</div>
              <div className="mt-1 text-lg font-semibold tabular-nums text-red-700">{gh(totals.outstanding)}</div>
            </CardContent></Card>
            <Card><CardContent className="p-3">
              <div className="text-[11px] uppercase tracking-wide text-slate-500">Total Repaid</div>
              <div className="mt-1 text-lg font-semibold tabular-nums text-emerald-700">{gh(totals.repaid)}</div>
            </CardContent></Card>
            <Card><CardContent className="p-3">
              <div className="text-[11px] uppercase tracking-wide text-slate-500">Active Loans</div>
              <div className="mt-1 text-lg font-semibold tabular-nums">{totals.active}</div>
            </CardContent></Card>
          </div>

          {loading ? (
            <Card><CardContent className="py-12 text-center text-slate-600"><Loader2 className="h-4 w-4 animate-spin inline mr-2" />Loading…</CardContent></Card>
          ) : (
            <Card>
              <CardContent className="p-0 md:p-2">
                <MobileCardList
                  defaultOpen striped stripeAccent="blue"
                  items={pg.pageItems} pagination={pg.paginationProps}
                  getKey={(l: any) => l.genericLoanId}
                  primary={(l: any) => l.lenderName}
                  secondary={(l: any) => fmtDateTime(l.loanDate, l)}
                  trailing={(l: any) => <Badge className={STATUS_COLORS[l.status] ?? "bg-slate-100"}>{l.status}</Badge>}
                  highlights={(l: any) => [
                    { label: "Borrowed", value: gh(l.originalPrincipal), accent: "blue" },
                    { label: "Outstanding", value: gh(l.outstandingBalance), accent: l.outstandingBalance > 0 ? "rose" : "emerald" },
                  ]}
                  details={(l: any) => [
                    { label: "Interest rate", value: `${l.interestRate}%` },
                    { label: "Principal paid", value: gh(l.totalPrincipalPaid) },
                    { label: "Interest paid", value: gh(l.totalInterestPaid) },
                    { label: "Fees paid", value: gh(l.totalFeesPaid) },
                    { label: "Due date", value: l.dueDate ? fmtDateTime(l.dueDate, l) : "—" },
                  ]}
                  actions={(l: any) => (
                    <>
                      {l.status === "Active" && (
                        <Button size="sm" variant="outline" className="flex-1 h-10 text-emerald-700 border-emerald-200"
                          onClick={() => { setRepayTarget(l); setRepayForm({ principalAmount: 0, interestAmount: 0, feeAmount: 0, paymentDate: new Date().toISOString().split("T")[0], notes: "" }) }}>
                          <Banknote className="h-4 w-4 mr-1" /> Repay
                        </Button>
                      )}
                      <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => showPayments(l)}>
                        <TrendingDown className="h-4 w-4 mr-1" /> Payments
                      </Button>
                    </>
                  )}
                  desktopTable={
                    <div className="overflow-x-auto">
                      <Table>
                        <TableHeader><TableRow>
                          <TableHead>Date</TableHead><TableHead>Lender</TableHead>
                          <TableHead className="text-right">Borrowed</TableHead>
                          <TableHead className="text-right">Outstanding</TableHead>
                          <TableHead className="text-right">Rate</TableHead>
                          <TableHead>Due</TableHead><TableHead>Status</TableHead>
                          <TableHead className="text-right">Actions</TableHead>
                        </TableRow></TableHeader>
                        <TableBody>
                          {rows.length === 0 ? (
                            <TableRow><TableCell colSpan={8} className="text-center text-slate-500 py-6">No loans recorded.</TableCell></TableRow>
                          ) : pg.pageItems.map((l: any) => (
                            <TableRow key={l.genericLoanId}>
                              <TableCell className="whitespace-nowrap">{fmtDateTime(l.loanDate, l)}</TableCell>
                              <TableCell className="font-medium">{l.lenderName}</TableCell>
                              <TableCell className="text-right tabular-nums">{gh(l.originalPrincipal)}</TableCell>
                              <TableCell className={cn("text-right tabular-nums font-medium", l.outstandingBalance > 0 ? "text-red-700" : "text-emerald-700")}>{gh(l.outstandingBalance)}</TableCell>
                              <TableCell className="text-right">{l.interestRate}%</TableCell>
                              <TableCell className="whitespace-nowrap">{l.dueDate ? fmtDateTime(l.dueDate, l) : "—"}</TableCell>
                              <TableCell><Badge className={STATUS_COLORS[l.status] ?? "bg-slate-100"}>{l.status}</Badge></TableCell>
                              <TableCell className="text-right whitespace-nowrap">
                                {l.status === "Active" && (
                                  <Button size="sm" variant="ghost" onClick={() => { setRepayTarget(l); setRepayForm({ principalAmount: 0, interestAmount: 0, feeAmount: 0, paymentDate: new Date().toISOString().split("T")[0], notes: "" }) }}>
                                    <Banknote className="h-4 w-4 text-emerald-600" />
                                  </Button>
                                )}
                                <Button size="sm" variant="ghost" onClick={() => showPayments(l)}>
                                  <TrendingDown className="h-4 w-4 text-blue-600" />
                                </Button>
                              </TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    </div>
                  }
                />
              </CardContent>
            </Card>
          )}
        </main>
      </div>

      {/* Create loan */}
      <Dialog open={createOpen} onOpenChange={setCreateOpen}>
        <DialogContent className="max-w-lg"><DialogHeader><DialogTitle>Record a new loan</DialogTitle></DialogHeader>
          <FormSection title="Loan details" color="indigo">
            <FormField label="Lender *"><Input value={form.lenderName} onChange={(e) => setForm({ ...form, lenderName: e.target.value })} /></FormField>
            <FormField label="Amount borrowed *"><NumberInput min={0} step="0.01" value={form.originalPrincipal} onChange={(e) => setForm({ ...form, originalPrincipal: Number(e.target.value) || 0 })} /></FormField>
            <FormField label="Amount received"><NumberInput min={0} step="0.01" value={form.amountReceived} onChange={(e) => setForm({ ...form, amountReceived: Number(e.target.value) || 0 })} /></FormField>
            <FormField label="Interest rate %"><NumberInput min={0} step="0.01" value={form.interestRate} onChange={(e) => setForm({ ...form, interestRate: Number(e.target.value) || 0 })} /></FormField>
            <FormField label="Loan date"><Input type="date" value={form.loanDate} onChange={(e) => setForm({ ...form, loanDate: e.target.value })} /></FormField>
            <FormField label="Due date"><Input type="date" value={form.dueDate} onChange={(e) => setForm({ ...form, dueDate: e.target.value })} /></FormField>
            <FormField label="Notes"><Input value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></FormField>
          </FormSection>
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setCreateOpen(false)}>Cancel</Button>
            <Button onClick={doCreate} disabled={saving}>{saving ? <Loader2 className="h-4 w-4 animate-spin" /> : "Record Loan"}</Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Repay */}
      <Dialog open={!!repayTarget} onOpenChange={(o) => !o && setRepayTarget(null)}>
        <DialogContent className="max-w-lg"><DialogHeader><DialogTitle>Repay — {repayTarget?.lenderName}</DialogTitle></DialogHeader>
          {repayTarget && (
            <>
              <p className="text-sm text-slate-600">Outstanding: <strong className="text-red-700">{gh(repayTarget.outstandingBalance)}</strong></p>
              <FormSection title="Payment breakdown" color="emerald">
                <FormField label="Principal"><NumberInput min={0} step="0.01" value={repayForm.principalAmount} onChange={(e) => setRepayForm({ ...repayForm, principalAmount: Number(e.target.value) || 0 })} /></FormField>
                <FormField label="Interest"><NumberInput min={0} step="0.01" value={repayForm.interestAmount} onChange={(e) => setRepayForm({ ...repayForm, interestAmount: Number(e.target.value) || 0 })} /></FormField>
                <FormField label="Fees"><NumberInput min={0} step="0.01" value={repayForm.feeAmount} onChange={(e) => setRepayForm({ ...repayForm, feeAmount: Number(e.target.value) || 0 })} /></FormField>
                <FormField label="Total" full>
                  <p className="text-sm font-semibold">{gh(repayForm.principalAmount + repayForm.interestAmount + repayForm.feeAmount)}</p>
                </FormField>
                <FormField label="Date"><Input type="date" value={repayForm.paymentDate} onChange={(e) => setRepayForm({ ...repayForm, paymentDate: e.target.value })} /></FormField>
                <FormField label="Notes"><Input value={repayForm.notes} onChange={(e) => setRepayForm({ ...repayForm, notes: e.target.value })} /></FormField>
              </FormSection>
              <div className="flex justify-end gap-2">
                <Button variant="outline" onClick={() => setRepayTarget(null)}>Cancel</Button>
                <Button onClick={doRepay} disabled={saving}>{saving ? <Loader2 className="h-4 w-4 animate-spin" /> : "Record Payment"}</Button>
              </div>
            </>
          )}
        </DialogContent>
      </Dialog>

      {/* Payments history */}
      <Dialog open={!!paymentsTarget} onOpenChange={(o) => !o && setPaymentsTarget(null)}>
        <DialogContent className="max-w-2xl"><DialogHeader><DialogTitle>Payments — {paymentsTarget?.lenderName}</DialogTitle></DialogHeader>
          {payments.length === 0 ? (
            <p className="text-sm text-slate-500 py-4 text-center">No payments recorded for this loan.</p>
          ) : (
            <div className="overflow-x-auto max-h-[400px]">
              <Table>
                <TableHeader><TableRow>
                  <TableHead>Date</TableHead><TableHead className="text-right">Principal</TableHead>
                  <TableHead className="text-right">Interest</TableHead><TableHead className="text-right">Fees</TableHead>
                  <TableHead className="text-right">Total</TableHead><TableHead>Notes</TableHead>
                </TableRow></TableHeader>
                <TableBody>
                  {payments.map((p) => (
                    <TableRow key={p.genericLoanPaymentId}>
                      <TableCell className="whitespace-nowrap">{fmtDateTime(p.paymentDate, p)}</TableCell>
                      <TableCell className="text-right tabular-nums">{gh(p.principalAmount)}</TableCell>
                      <TableCell className="text-right tabular-nums">{gh(p.interestAmount)}</TableCell>
                      <TableCell className="text-right tabular-nums">{gh(p.feeAmount)}</TableCell>
                      <TableCell className="text-right tabular-nums font-semibold">{gh(p.totalPayment)}</TableCell>
                      <TableCell className="text-sm text-slate-600">{p.notes ?? "—"}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}
