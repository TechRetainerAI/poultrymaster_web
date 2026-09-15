"use client"

// Staff Payments — paying one person, now.
//
// The full payroll run is still the way to pay a whole team for a period. This
// is the other case: a monthly contractor, a one-off developer invoice, where a
// run is more machinery than the payment deserves. Both do the same two things
// — post an expense so the cost reaches the P&L, and move cash once — so a
// payment made here shows up in expense reports and cash flow exactly like one
// made through payroll.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Textarea } from "@/components/ui/textarea"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger,
} from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { FormSection, FormField } from "@/components/ui/form-section"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Loader2, Plus, Banknote, Undo2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  getStaffPayments, recordStaffPayment, reverseStaffPayment,
  type GenericStaffPayment,
} from "@/lib/api/generic-money-out"
import { getStaff, getCashAccounts, type GenericStaff } from "@/lib/api/generic"

const today = () => new Date().toISOString().slice(0, 10)

export default function GenericStaffPaymentsPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  const [rows, setRows] = useState<GenericStaffPayment[]>([])
  const [staff, setStaff] = useState<GenericStaff[]>([])
  const [accounts, setAccounts] = useState<{ genericCashAccountId: number; accountName: string; isActive: boolean }[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [search, setSearch] = useState("")
  const [open, setOpen] = useState(false)
  const [reversing, setReversing] = useState<GenericStaffPayment | null>(null)
  const [reason, setReason] = useState("")

  const EMPTY = {
    genericStaffId: "",
    amount: "0",
    paymentDate: today(),
    paymentMethod: "Bank",
    cashAccountId: "",
    periodStart: "",
    periodEnd: "",
    description: "",
    reference: "",
  }
  const [form, setForm] = useState(EMPTY)

  const load = async () => {
    setLoading(true)
    try {
      const [pays, people, accts] = await Promise.all([
        getStaffPayments(),
        getStaff().catch(() => [] as GenericStaff[]),
        getCashAccounts().catch(() => []),
      ])
      setRows(pays)
      setStaff(people)
      setAccounts(accts as any)
    } catch (e: any) {
      toast({
        title: "Could not load staff payments",
        description: e?.message ?? String(e),
        variant: "destructive",
      })
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (!activeFarmType) return
    if (activeFarmType !== "Generic") {
      router.replace("/dashboard")
      return
    }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router])

  const visible = useMemo(
    () =>
      filterByDateAndSearch(rows, {
        search,
        searchKeys: ["staffName", "staffRole", "description", "referenceNo"],
      }),
    [rows, search],
  )
  const pg = usePagination(visible)

  // Reversed payments are excluded: they no longer cost the business anything.
  const totalPaid = useMemo(
    () => rows.filter((r) => r.status !== "Reversed").reduce((s, r) => s + r.amount, 0),
    [rows],
  )

  // Picking a person pre-fills what they are usually paid, so the common case
  // is two clicks.
  const onPickStaff = (v: string) => {
    const person = staff.find((s) => String(s.genericStaffId) === v)
    setForm((f) => ({
      ...f,
      genericStaffId: v,
      amount: person?.basePay ? String(person.basePay) : f.amount,
    }))
  }

  const onSave = async () => {
    if (!form.genericStaffId) {
      toast({ title: "Pick who is being paid", variant: "destructive" })
      return
    }
    if (Number(form.amount) <= 0) {
      toast({ title: "The amount must be more than zero", variant: "destructive" })
      return
    }
    setSaving(true)
    try {
      await recordStaffPayment({
        genericStaffId: Number(form.genericStaffId),
        amount: Number(form.amount),
        paymentDate: form.paymentDate ? `${form.paymentDate}T00:00:00Z` : null,
        paymentMethod: form.paymentMethod || null,
        cashAccountId: form.cashAccountId ? Number(form.cashAccountId) : null,
        periodStart: form.periodStart || null,
        periodEnd: form.periodEnd || null,
        description: form.description || null,
        reference: form.reference || null,
      })
      toast({
        title: "Payment recorded.",
        description: "An expense was booked and the cash account has been reduced.",
      })
      setOpen(false)
      setForm(EMPTY)
      await load()
    } catch (e: any) {
      toast({ title: "Could not record it", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  const onReverse = async () => {
    if (!reversing) return
    if (!reason.trim()) {
      toast({ title: "A reason is required to reverse", variant: "destructive" })
      return
    }
    try {
      await reverseStaffPayment(reversing.genericStaffPaymentId, reason.trim())
      toast({
        title: "Payment reversed.",
        description: "The expense left the books and the cash came back.",
      })
      setReversing(null)
      setReason("")
      await load()
    } catch (e: any) {
      toast({ title: "Could not reverse it", description: e?.message ?? String(e), variant: "destructive" })
    }
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
                <Banknote className="h-6 w-6 text-indigo-600" /> Staff payments
              </h1>
              <p className="text-sm text-slate-500">
                {rows.filter((r) => r.status !== "Reversed").length} payment(s) · {fmt(totalPaid)} paid out
              </p>
            </div>
            <Dialog open={open} onOpenChange={setOpen}>
              <DialogTrigger asChild>
                <Button className="h-11 sm:h-10"><Plus className="h-4 w-4 mr-1" /> Record payment</Button>
              </DialogTrigger>
              <DialogContent className="w-[95vw] max-w-[900px] max-h-[90vh] overflow-y-auto">
                <DialogHeader>
                  <DialogTitle className="flex items-center gap-2">
                    <Banknote className="w-5 h-5 text-blue-600" /> Record a staff payment
                  </DialogTitle>
                  <DialogDescription>
                    Books an expense and moves the cash. Use a payroll run instead when paying
                    the whole team for a period.
                  </DialogDescription>
                </DialogHeader>

                <div className="space-y-4">
                  <FormSection title="Who and how much" color="indigo">
                    <FormField label="Person *">
                      <Select value={form.genericStaffId} onValueChange={onPickStaff}>
                        <SelectTrigger><SelectValue placeholder="Pick someone" /></SelectTrigger>
                        <SelectContent>
                          {staff.filter((s) => s.isActive).map((s) => (
                            <SelectItem key={s.genericStaffId} value={String(s.genericStaffId)}>
                              {s.firstName} {s.lastName} — {s.role}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </FormField>
                    <FormField label="Amount *">
                      <NumberInput step="0.01" value={form.amount}
                        onChange={(e) => setForm((f) => ({ ...f, amount: e.target.value }))} />
                    </FormField>
                    <FormField label="Paid on">
                      <Input type="date" value={form.paymentDate}
                        onChange={(e) => setForm((f) => ({ ...f, paymentDate: e.target.value }))} />
                    </FormField>
                  </FormSection>

                  <FormSection title="Out of which account" color="amber">
                    <FormField label="Method">
                      <Select value={form.paymentMethod}
                        onValueChange={(v) => setForm((f) => ({ ...f, paymentMethod: v }))}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>
                          {["Cash", "Bank", "Mobile Money", "Card", "Other"].map((m) => (
                            <SelectItem key={m} value={m}>{m}</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </FormField>
                    <FormField label="Cash account">
                      <Select value={form.cashAccountId}
                        onValueChange={(v) => setForm((f) => ({ ...f, cashAccountId: v }))}>
                        <SelectTrigger><SelectValue placeholder="Pick one" /></SelectTrigger>
                        <SelectContent>
                          {accounts.filter((a) => a.isActive).map((a) => (
                            <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>
                              {a.accountName}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </FormField>
                    <p className="text-xs text-slate-500 sm:col-span-2">
                      Leave the account empty to record what is owed without moving money yet.
                    </p>
                  </FormSection>

                  <FormSection title="What period it covers" color="emerald">
                    <FormField label="From">
                      <Input type="date" value={form.periodStart}
                        onChange={(e) => setForm((f) => ({ ...f, periodStart: e.target.value }))} />
                    </FormField>
                    <FormField label="To">
                      <Input type="date" value={form.periodEnd}
                        onChange={(e) => setForm((f) => ({ ...f, periodEnd: e.target.value }))} />
                    </FormField>
                    <FormField label="Reference">
                      <Input value={form.reference} maxLength={60}
                        onChange={(e) => setForm((f) => ({ ...f, reference: e.target.value }))} />
                    </FormField>
                  </FormSection>

                  <FormSection title="Notes" color="slate" columns={1}>
                    <FormField label="Description">
                      <Textarea rows={2} value={form.description}
                        placeholder="Left empty, this describes itself from the name and period."
                        onChange={(e) => setForm((f) => ({ ...f, description: e.target.value }))} />
                    </FormField>
                  </FormSection>

                  <div className="flex gap-3 justify-end pt-2">
                    <Button type="button" onClick={() => setOpen(false)}
                      className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
                    <Button onClick={onSave} disabled={saving}>
                      {saving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : "Record payment"}
                    </Button>
                  </div>
                </div>
              </DialogContent>
            </Dialog>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500">
              <Loader2 className="h-4 w-4 animate-spin" /> Loading…
            </div>
          ) : rows.length === 0 ? (
            <Card>
              <CardContent className="py-8 text-center text-slate-500">
                No staff payments yet.
              </CardContent>
            </Card>
          ) : (
            <>
              <ListFilters search={search} setSearch={setSearch} searchOnly
                searchPlaceholder="Search person, role or reference" />
              <Card>
                <CardContent className="p-0">
                  <MobileCardList
                    items={pg.pageItems}
                    getKey={(r) => r.genericStaffPaymentId}
                    primary={(r) => r.staffName ?? `#${r.genericStaffId}`}
                    secondary={(r) => (
                      <>
                        <span>{fmt(r.amount)}</span>
                        <span> · {new Date(r.paymentDate).toLocaleDateString()}</span>
                      </>
                    )}
                    trailing={(r) =>
                      r.status === "Reversed"
                        ? <Badge className="bg-slate-200 text-slate-700 hover:bg-slate-200">Reversed</Badge>
                        : <Badge className="bg-emerald-100 text-emerald-800 hover:bg-emerald-100">Posted</Badge>
                    }
                    details={(r) => [
                      { label: "Role", value: r.staffRole ?? "—" },
                      { label: "Type", value: r.workerType ?? "Employee" },
                      { label: "Category", value: r.categoryName ?? "—" },
                      { label: "Account", value: r.cashAccountName ?? "Not paid yet" },
                      {
                        label: "Period",
                        value: r.periodStart && r.periodEnd ? `${r.periodStart} → ${r.periodEnd}` : "—",
                      },
                    ]}
                    actions={(r) =>
                      r.status !== "Reversed" ? (
                        <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200"
                          onClick={() => { setReversing(r); setReason("") }}>
                          <Undo2 className="h-4 w-4 mr-1" /> Reverse
                        </Button>
                      ) : null
                    }
                    pagination={pg.paginationProps}
                    desktopTable={
                      <div className="overflow-x-auto">
                        <Table>
                          <TableHeader>
                            <TableRow>
                              <TableHead>Person</TableHead>
                              <TableHead>Type</TableHead>
                              <TableHead>Paid on</TableHead>
                              <TableHead>Period</TableHead>
                              <TableHead>Account</TableHead>
                              <TableHead className="text-right">Amount</TableHead>
                              <TableHead>Status</TableHead>
                              <TableHead />
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {pg.pageItems.map((r) => (
                              <TableRow key={r.genericStaffPaymentId}
                                className={r.status === "Reversed" ? "opacity-60" : ""}>
                                <TableCell className="font-medium">
                                  {r.staffName ?? `#${r.genericStaffId}`}
                                  {r.staffRole && <span className="text-slate-500"> · {r.staffRole}</span>}
                                </TableCell>
                                <TableCell>{r.workerType ?? "Employee"}</TableCell>
                                <TableCell>{new Date(r.paymentDate).toLocaleDateString()}</TableCell>
                                <TableCell className="whitespace-nowrap text-xs text-slate-600">
                                  {r.periodStart && r.periodEnd ? `${r.periodStart} → ${r.periodEnd}` : "—"}
                                </TableCell>
                                <TableCell>{r.cashAccountName ?? "—"}</TableCell>
                                <TableCell className="text-right font-medium">{fmt(r.amount)}</TableCell>
                                <TableCell>
                                  {r.status === "Reversed"
                                    ? <Badge className="bg-slate-200 text-slate-700 hover:bg-slate-200">Reversed</Badge>
                                    : <Badge className="bg-emerald-100 text-emerald-800 hover:bg-emerald-100">Posted</Badge>}
                                </TableCell>
                                <TableCell className="text-right">
                                  {r.status !== "Reversed" && (
                                    <Button size="sm" variant="outline" className="text-red-600 border-red-200"
                                      onClick={() => { setReversing(r); setReason("") }}>
                                      <Undo2 className="h-4 w-4 mr-1" /> Reverse
                                    </Button>
                                  )}
                                </TableCell>
                              </TableRow>
                            ))}
                          </TableBody>
                        </Table>
                        <DataPagination {...pg.paginationProps} />
                      </div>
                    }
                  />
                </CardContent>
              </Card>
            </>
          )}
        </main>
      </div>

      <Dialog open={reversing !== null} onOpenChange={(o) => !o && setReversing(null)}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Reverse this payment?</DialogTitle>
            <DialogDescription>
              {reversing && `${fmt(reversing.amount)} to ${reversing.staffName}. `}
              The expense leaves the books and the cash comes back. The payment itself is kept and
              marked reversed, so what happened stays on record.
            </DialogDescription>
          </DialogHeader>
          <Textarea rows={3} placeholder="Why is it being reversed?"
            value={reason} onChange={(e) => setReason(e.target.value)} />
          <DialogFooter>
            <Button variant="ghost" onClick={() => setReversing(null)}>Keep it</Button>
            <Button className="bg-red-600 hover:bg-red-700 text-white" onClick={onReverse}>
              Reverse it
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
