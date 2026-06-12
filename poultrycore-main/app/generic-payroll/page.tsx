"use client"

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger,
} from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Loader2, Plus, Banknote } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  createPayrollRun, getCashAccounts, getPayrollRuns,
  type GenericCashAccount, type GenericPayrollRun,
} from "@/lib/api/generic"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}

function todayIso(): string {
  const d = new Date(); d.setMinutes(d.getMinutes() - d.getTimezoneOffset())
  return d.toISOString().slice(0, 10)
}

function firstOfMonthIso(): string {
  const d = new Date(); d.setDate(1); d.setMinutes(d.getMinutes() - d.getTimezoneOffset())
  return d.toISOString().slice(0, 10)
}

function statusBadgeClass(s: string) {
  switch (s) {
    case "Draft":     return "bg-slate-100 text-slate-700 hover:bg-slate-100"
    case "Approved":  return "bg-sky-100 text-sky-800 hover:bg-sky-100"
    case "Paid":      return "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"
    case "Cancelled": return "bg-rose-100 text-rose-800 hover:bg-rose-100"
    default:          return "bg-slate-100 text-slate-700 hover:bg-slate-100"
  }
}

export default function GenericPayrollPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()

  const [rows, setRows] = useState<GenericPayrollRun[]>([])
  const [cashAccounts, setCashAccounts] = useState<GenericCashAccount[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [loading, setLoading] = useState(true)
  const [filterStatus, setFilterStatus] = useState<string>("all")

  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({
    periodStart: firstOfMonthIso(),
    periodEnd: todayIso(),
    payDate: "",
    genericCashAccountId: "",
    notes: "",
  })

  const load = async () => {
    setLoading(true)
    try {
      const [r, ca] = await Promise.all([
        getPayrollRuns(filterStatus === "all" ? null : filterStatus),
        getCashAccounts(),
      ])
      setRows(r)
      setCashAccounts(ca.filter((a) => a.isActive))
    } catch (e: any) {
      toast({ title: "Could not load payroll", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router, filterStatus])

  const visibleRows = useMemo(
    () => filterByDateAndSearch(rows, {
      search, dateFrom, dateTo,
      searchKeys: ["status", "notes"],
      dateKey: "periodStart",
    }),
    [rows, search, dateFrom, dateTo],
  )

  const onCreate = async () => {
    if (!form.periodStart || !form.periodEnd) {
      toast({ title: "Period start and end are required", variant: "destructive" }); return
    }
    if (form.periodStart > form.periodEnd) {
      toast({ title: "Period start must be on or before end", variant: "destructive" }); return
    }
    setSaving(true)
    try {
      const created = await createPayrollRun({
        periodStart: form.periodStart,
        periodEnd:   form.periodEnd,
        payDate:     form.payDate || null,
        genericCashAccountId: form.genericCashAccountId ? Number(form.genericCashAccountId) : null,
        notes: form.notes || null,
      })
      if (created?.genericPayrollRunId) {
        toast({ title: "Payroll run created — now add staff lines." })
        setOpen(false)
        router.push(`/generic-payroll/${created.genericPayrollRunId}`)
      }
    } catch (e: any) {
      toast({ title: "Could not create payroll run", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <Banknote className="h-6 w-6 text-emerald-600" /> Payroll
              </h1>
              <p className="text-sm text-slate-500">{rows.length} run(s)</p>
            </div>
            <div className="flex items-center gap-2 flex-wrap w-full sm:w-auto">
              <Select value={filterStatus} onValueChange={setFilterStatus}>
                <SelectTrigger className="w-44"><SelectValue placeholder="Filter status" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All statuses</SelectItem>
                  <SelectItem value="Draft">Draft</SelectItem>
                  <SelectItem value="Approved">Approved</SelectItem>
                  <SelectItem value="Paid">Paid</SelectItem>
                  <SelectItem value="Cancelled">Cancelled</SelectItem>
                </SelectContent>
              </Select>

              <Dialog open={open} onOpenChange={setOpen}>
                <DialogTrigger asChild>
                  <Button className="w-full sm:w-auto h-11 sm:h-10"><Plus className="h-4 w-4 mr-1" />New payroll run</Button>
                </DialogTrigger>
                <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
                  <DialogHeader>
                    <DialogTitle className="flex items-center gap-2">
                      <Banknote className="w-5 h-5 text-blue-600" /> New payroll run
                    </DialogTitle>
                    <DialogDescription>Pick the period and the cash account that will pay out when you mark this run Paid.</DialogDescription>
                  </DialogHeader>
                  <div className="space-y-4">
                    <FormSection title="Period" color="indigo">
                      <FormField label="Period start *">
                        <Input type="date" value={form.periodStart} onChange={(e) => setForm((f) => ({ ...f, periodStart: e.target.value }))} />
                      </FormField>
                      <FormField label="Period end *">
                        <Input type="date" value={form.periodEnd} onChange={(e) => setForm((f) => ({ ...f, periodEnd: e.target.value }))} />
                      </FormField>
                    </FormSection>

                    <FormSection title="Pay-out" color="blue">
                      <FormField label="Pay date (optional)">
                        <Input type="date" value={form.payDate} onChange={(e) => setForm((f) => ({ ...f, payDate: e.target.value }))} />
                      </FormField>
                      <FormField label="Pay from">
                        <Select
                          value={form.genericCashAccountId}
                          onValueChange={(v) => setForm((f) => ({ ...f, genericCashAccountId: v }))}
                        >
                          <SelectTrigger><SelectValue placeholder="Select cash account" /></SelectTrigger>
                          <SelectContent>
                            {cashAccounts.map((a) => (
                              <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>
                                {a.accountName} — {fmt(a.currentBalance)}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </FormField>
                    </FormSection>

                    <FormSection title="Notes" color="slate" columns={1}>
                      <FormField label="Notes">
                        <Textarea rows={2} value={form.notes} onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} />
                      </FormField>
                    </FormSection>

                    <div className="flex gap-3 justify-end pt-2">
                      <Button type="button" onClick={() => setOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
                      <Button onClick={onCreate} disabled={saving}>
                        {saving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : "Create run"}
                      </Button>
                    </div>
                  </div>
                </DialogContent>
              </Dialog>
            </div>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : rows.length === 0 ? (
            <Card><CardContent className="py-8 text-center text-slate-500">No payroll runs yet.</CardContent></Card>
          ) : (
            <>
            <ListFilters
              search={search} setSearch={setSearch}
              dateFrom={dateFrom} setDateFrom={setDateFrom}
              dateTo={dateTo} setDateTo={setDateTo}
              searchPlaceholder="Search status or notes"
            />
            <Card>
              <CardContent className="p-0">
                <MobileCardList
                  items={visibleRows}
                  getKey={(r) => r.genericPayrollRunId}
                  primary={(r) => (
                    <Link href={`/generic-payroll/${r.genericPayrollRunId}`} className="text-emerald-700 hover:underline">
                      {r.periodStart.slice(0, 10)} — {r.periodEnd.slice(0, 10)}
                    </Link>
                  )}
                  secondary={(r) => (
                    <>
                      {r.payDate && <span>Pay {r.payDate.slice(0, 10)}</span>}
                      {r.cashAccountName && <><span>·</span><span>{r.cashAccountName}</span></>}
                    </>
                  )}
                  trailing={(r) => <Badge className={statusBadgeClass(r.status)}>{r.status}</Badge>}
                  details={(r) => [
                    { label: "Pay date", value: r.payDate ? r.payDate.slice(0, 10) : "—" },
                    { label: "Cash account", value: r.cashAccountName ?? "—" },
                    { label: "Gross", value: fmt(r.totalGrossPay) },
                    { label: "Deductions", value: fmt(r.totalDeductions) },
                    { label: "Net", value: <span className="font-semibold">{fmt(r.totalNetPay)}</span> },
                  ]}
                  actions={(r) => (
                    <Button asChild size="sm" variant="outline" className="flex-1 h-10">
                      <Link href={`/generic-payroll/${r.genericPayrollRunId}`}>Open run</Link>
                    </Button>
                  )}
                  desktopTable={
                    <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Period</TableHead>
                          <TableHead>Pay date</TableHead>
                          <TableHead>Cash account</TableHead>
                          <TableHead className="text-right">Gross</TableHead>
                          <TableHead className="text-right">Deductions</TableHead>
                          <TableHead className="text-right">Net</TableHead>
                          <TableHead>Status</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {visibleRows.map((r) => (
                          <TableRow key={r.genericPayrollRunId}>
                            <TableCell>
                              <Link href={`/generic-payroll/${r.genericPayrollRunId}`} className="text-emerald-700 hover:underline font-medium">
                                {r.periodStart.slice(0, 10)} — {r.periodEnd.slice(0, 10)}
                              </Link>
                            </TableCell>
                            <TableCell>{r.payDate ? r.payDate.slice(0, 10) : "—"}</TableCell>
                            <TableCell>{r.cashAccountName ?? "—"}</TableCell>
                            <TableCell className="text-right">{fmt(r.totalGrossPay)}</TableCell>
                            <TableCell className="text-right">{fmt(r.totalDeductions)}</TableCell>
                            <TableCell className="text-right font-semibold">{fmt(r.totalNetPay)}</TableCell>
                            <TableCell><Badge className={statusBadgeClass(r.status)}>{r.status}</Badge></TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                    </div>
                  }
                />
              </CardContent>
            </Card>
            </>
          )}
        </main>
      </div>
    </div>
  )
}
