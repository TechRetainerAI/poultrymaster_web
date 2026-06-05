"use client"

export const dynamic = "force-dynamic"

import { Suspense, useEffect, useMemo, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Check, CreditCard, Loader2, Plus, X } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  approveSupplierPayment, cancelSupplierPayment, createSupplierPayment, getCashAccounts, getSupplierPayments, getSuppliers,
  type GenericCashAccount, type GenericSupplier, type GenericSupplierPayment,
} from "@/lib/api/generic"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"

const STATUS_FILTERS = ["All", "Draft", "Approved", "Cancelled"] as const
const PAY_METHODS = ["Cash", "MoMo", "Bank", "Card"]

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}

function badgeClass(s: string) {
  switch (s) {
    case "Approved":  return "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"
    case "Cancelled": return "bg-rose-100 text-rose-800 hover:bg-rose-100"
    default:          return "bg-slate-100 text-slate-800 hover:bg-slate-100"
  }
}

function GenericSupplierPaymentsPageInner() {
  const router = useRouter()
  const sp = useSearchParams()
  const status = sp.get("status") || "All"
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()

  const [rows, setRows] = useState<GenericSupplierPayment[]>([])
  const [suppliers, setSuppliers] = useState<GenericSupplier[]>([])
  const [cashAccounts, setCashAccounts] = useState<GenericCashAccount[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [loading, setLoading] = useState(true)
  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)

  const [form, setForm] = useState({
    genericSupplierId: "",
    amount: "0",
    paymentMethod: "Cash",
    genericCashAccountId: "",
    paymentDate: new Date().toISOString().slice(0, 10),
    notes: "",
  })

  const load = async () => {
    setLoading(true)
    try {
      const [ps, ss, as] = await Promise.all([
        getSupplierPayments(status === "All" ? null : status),
        getSuppliers(),
        getCashAccounts(),
      ])
      setRows(ps); setSuppliers(ss); setCashAccounts(as)
      const firstCash = as.find((a) => a.isActive)
      if (firstCash && !form.genericCashAccountId) setForm((f) => ({ ...f, genericCashAccountId: String(firstCash.genericCashAccountId) }))
    } catch (e: any) {
      toast({ title: "Could not load", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router, status])

  const visibleRows = useMemo(
    () => filterByDateAndSearch(rows, {
      search, dateFrom, dateTo,
      searchKeys: ["supplierName", "paymentMethod", "notes"],
      dateKey: "paymentDate",
    }),
    [rows, search, dateFrom, dateTo],
  )

  const onSave = async () => {
    if (!form.genericSupplierId) { toast({ title: "Pick a supplier", variant: "destructive" }); return }
    const amount = Number(form.amount)
    if (!(amount > 0)) { toast({ title: "Amount must be greater than zero", variant: "destructive" }); return }
    setSaving(true)
    try {
      const created = await createSupplierPayment({
        genericSupplierId: Number(form.genericSupplierId),
        amount,
        paymentMethod: form.paymentMethod,
        genericCashAccountId: form.genericCashAccountId ? Number(form.genericCashAccountId) : null,
        paymentDate: form.paymentDate,
        notes: form.notes || null,
      })
      if (created) {
        toast({ title: "Supplier payment created as Draft. Approve to debit supplier + cash." })
        setOpen(false)
        setForm({ genericSupplierId: "", amount: "0", paymentMethod: "Cash", genericCashAccountId: form.genericCashAccountId, paymentDate: new Date().toISOString().slice(0, 10), notes: "" })
        await load()
      }
    } catch (e: any) {
      toast({ title: "Could not create payment", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  const onApprove = async (id: number) => {
    try { await approveSupplierPayment(id); toast({ title: `Payment #${id} approved.` }); await load() }
    catch (e: any) { toast({ title: "Approve failed", description: e?.message ?? String(e), variant: "destructive" }) }
  }

  const onCancel = async (id: number) => {
    try { await cancelSupplierPayment(id); toast({ title: `Payment #${id} cancelled.` }); await load() }
    catch (e: any) { toast({ title: "Cancel failed", description: e?.message ?? String(e), variant: "destructive" }) }
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
                <CreditCard className="h-6 w-6 text-orange-600" /> Supplier payments
              </h1>
              <p className="text-sm text-slate-500">{rows.length} payment(s) – money going out to suppliers.</p>
            </div>
            <Dialog open={open} onOpenChange={setOpen}>
              <DialogTrigger asChild><Button className="w-full sm:w-auto h-11 sm:h-10"><Plus className="h-4 w-4 mr-1" />Record payment</Button></DialogTrigger>
              <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
                <DialogHeader>
                  <DialogTitle className="flex items-center gap-2">
                    <CreditCard className="w-5 h-5 text-blue-600" /> New supplier payment
                  </DialogTitle>
                  <DialogDescription>Creates a Draft payment. Approval debits the supplier ledger and decreases cash.</DialogDescription>
                </DialogHeader>
                <div className="space-y-4">
                  <FormSection title="Supplier" color="indigo" columns={1}>
                    <FormField label="Supplier *">
                      <Select value={form.genericSupplierId} onValueChange={(v) => setForm((f) => ({ ...f, genericSupplierId: v }))}>
                        <SelectTrigger><SelectValue placeholder="Pick supplier..." /></SelectTrigger>
                        <SelectContent>{suppliers.map((s) => <SelectItem key={s.genericSupplierId} value={String(s.genericSupplierId)}>{s.supplierName}{s.currentBalance > 0 ? ` – owed ${fmt(s.currentBalance)}` : ""}</SelectItem>)}</SelectContent>
                      </Select>
                    </FormField>
                  </FormSection>

                  <FormSection title="Payment details" color="blue">
                    <FormField label="Date">
                      <Input type="date" value={form.paymentDate} onChange={(e) => setForm((f) => ({ ...f, paymentDate: e.target.value }))} />
                    </FormField>
                    <FormField label="Amount *">
                      <NumberInput step="0.01" min="0" value={form.amount} onChange={(e) => setForm((f) => ({ ...f, amount: e.target.value }))} />
                    </FormField>
                    <FormField label="Method">
                      <Select value={form.paymentMethod} onValueChange={(v) => setForm((f) => ({ ...f, paymentMethod: v }))}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>{PAY_METHODS.map((p) => <SelectItem key={p} value={p}>{p}</SelectItem>)}</SelectContent>
                      </Select>
                    </FormField>
                    <FormField label="Cash account (paid from)">
                      <Select value={form.genericCashAccountId || "__none__"} onValueChange={(v) => setForm((f) => ({ ...f, genericCashAccountId: v === "__none__" ? "" : v }))}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="__none__">– none –</SelectItem>
                          {cashAccounts.filter((a) => a.isActive).map((a) => <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>{a.accountName} ({a.accountType})</SelectItem>)}
                        </SelectContent>
                      </Select>
                    </FormField>
                  </FormSection>

                  <FormSection title="Notes" color="slate" columns={1}>
                    <FormField label="Notes">
                      <Textarea rows={2} value={form.notes} onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} maxLength={1000} />
                    </FormField>
                  </FormSection>

                  <div className="flex gap-3 justify-end pt-2">
                    <Button type="button" onClick={() => setOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
                    <Button onClick={onSave} disabled={saving}>
                      {saving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : "Create"}
                    </Button>
                  </div>
                </div>
              </DialogContent>
            </Dialog>
          </div>

          <div className="flex gap-1 mb-3 flex-wrap">
            {STATUS_FILTERS.map((s) => (
              <Button key={s} size="sm" variant={s === status ? "default" : "outline"}
                onClick={() => router.replace(s === "All" ? "/generic-supplier-payments" : `/generic-supplier-payments?status=${s}`)}>{s}</Button>
            ))}
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading...</div>
          ) : rows.length === 0 ? (
            <Card><CardContent className="py-8 text-center text-slate-500">No supplier payments yet.</CardContent></Card>
          ) : (
            <>
            <ListFilters
              search={search} setSearch={setSearch}
              dateFrom={dateFrom} setDateFrom={setDateFrom}
              dateTo={dateTo} setDateTo={setDateTo}
              searchPlaceholder="Search supplier, method or notes"
            />
            <Card>
              <CardContent className="p-0">
                <MobileCardList
                  items={visibleRows}
                  getKey={(p) => p.genericSupplierPaymentId}
                  primary={(p) => `#${p.genericSupplierPaymentId} · ${p.supplierName ?? "–"}`}
                  secondary={(p) => (
                    <>
                      <span>{new Date(p.paymentDate).toLocaleDateString()}</span>
                      <span>·</span>
                      <span className="text-xs">{p.paymentMethod}</span>
                    </>
                  )}
                  trailing={(p) => <Badge className={badgeClass(p.status)}>{p.status}</Badge>}
                  details={(p) => [
                    { label: "Date", value: new Date(p.paymentDate).toLocaleDateString() },
                    { label: "Supplier", value: p.supplierName ?? "–" },
                    { label: "Method", value: p.paymentMethod },
                    { label: "Amount", value: <span className="font-semibold text-rose-700">{fmt(p.amount)}</span> },
                  ]}
                  actions={(p) => (
                    <>
                      {p.status === "Draft" && (
                        <>
                          <Button size="sm" variant="outline" className="flex-1 h-10 text-emerald-700 border-emerald-200" onClick={() => onApprove(p.genericSupplierPaymentId)}>
                            <Check className="h-4 w-4 mr-1" /> Approve
                          </Button>
                          <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => onCancel(p.genericSupplierPaymentId)}>
                            <X className="h-4 w-4 mr-1" /> Cancel
                          </Button>
                        </>
                      )}
                    </>
                  )}
                  desktopTable={
                    <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>#</TableHead>
                          <TableHead>Date</TableHead>
                          <TableHead>Supplier</TableHead>
                          <TableHead>Method</TableHead>
                          <TableHead className="text-right">Amount</TableHead>
                          <TableHead>Status</TableHead>
                          <TableHead></TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {visibleRows.map((p) => (
                          <TableRow key={p.genericSupplierPaymentId}>
                            <TableCell>#{p.genericSupplierPaymentId}</TableCell>
                            <TableCell>{new Date(p.paymentDate).toLocaleDateString()}</TableCell>
                            <TableCell>{p.supplierName ?? "–"}</TableCell>
                            <TableCell className="text-xs text-slate-500">{p.paymentMethod}</TableCell>
                            <TableCell className="text-right font-semibold text-rose-700">{fmt(p.amount)}</TableCell>
                            <TableCell><Badge className={badgeClass(p.status)}>{p.status}</Badge></TableCell>
                            <TableCell className="flex gap-1">
                              {p.status === "Draft" && (
                                <>
                                  <Button size="sm" className="bg-emerald-600 hover:bg-emerald-700" onClick={() => onApprove(p.genericSupplierPaymentId)}><Check className="h-3 w-3 mr-1" />Approve</Button>
                                  <Button size="sm" variant="outline" onClick={() => onCancel(p.genericSupplierPaymentId)}><X className="h-3 w-3" /></Button>
                                </>
                              )}
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
            </>
          )}
        </main>
      </div>
    </div>
  )
}

export default function GenericSupplierPaymentsPage() {
  return (
    <Suspense fallback={<div className="p-6 text-slate-500">Loading...</div>}>
      <GenericSupplierPaymentsPageInner />
    </Suspense>
  )
}
