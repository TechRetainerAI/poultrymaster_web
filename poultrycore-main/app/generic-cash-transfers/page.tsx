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
import { ArrowRightLeft, Check, Loader2, Plus, X } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  approveCashTransfer, cancelCashTransfer, createCashTransfer, getCashAccounts, getCashTransfers,
  type GenericCashAccount, type GenericCashTransfer,
} from "@/lib/api/generic"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"

const STATUS_FILTERS = ["All", "Draft", "Approved", "Cancelled"] as const

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

function GenericCashTransfersPageInner() {
  const router = useRouter()
  const sp = useSearchParams()
  const status = sp.get("status") || "All"
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()

  const [rows, setRows] = useState<GenericCashTransfer[]>([])
  const [cashAccounts, setCashAccounts] = useState<GenericCashAccount[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [loading, setLoading] = useState(true)
  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)

  const [form, setForm] = useState({
    fromGenericCashAccountId: "",
    toGenericCashAccountId: "",
    amount: "0",
    transferDate: new Date().toISOString().slice(0, 10),
    notes: "",
  })

  const load = async () => {
    setLoading(true)
    try {
      const [ts, as] = await Promise.all([getCashTransfers(status === "All" ? null : status), getCashAccounts()])
      setRows(ts); setCashAccounts(as)
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
      searchKeys: ["fromAccountName", "toAccountName", "notes"],
      dateKey: "transferDate",
    }),
    [rows, search, dateFrom, dateTo],
  )

  const onSave = async () => {
    if (!form.fromGenericCashAccountId || !form.toGenericCashAccountId) {
      toast({ title: "Pick both accounts", variant: "destructive" }); return
    }
    if (form.fromGenericCashAccountId === form.toGenericCashAccountId) {
      toast({ title: "From and To must differ", variant: "destructive" }); return
    }
    const amount = Number(form.amount)
    if (!(amount > 0)) { toast({ title: "Amount must be greater than zero", variant: "destructive" }); return }
    setSaving(true)
    try {
      const created = await createCashTransfer({
        fromGenericCashAccountId: Number(form.fromGenericCashAccountId),
        toGenericCashAccountId: Number(form.toGenericCashAccountId),
        amount,
        transferDate: form.transferDate,
        notes: form.notes || null,
      })
      if (created) {
        toast({ title: "Transfer created as Draft. Approve to move the cash." })
        setOpen(false)
        setForm({ fromGenericCashAccountId: "", toGenericCashAccountId: "", amount: "0", transferDate: new Date().toISOString().slice(0, 10), notes: "" })
        await load()
      }
    } catch (e: any) {
      toast({ title: "Could not create transfer", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  const onApprove = async (id: number) => {
    try { await approveCashTransfer(id); toast({ title: `Transfer #${id} approved.` }); await load() }
    catch (e: any) { toast({ title: "Approve failed", description: e?.message ?? String(e), variant: "destructive" }) }
  }

  const onCancel = async (id: number) => {
    try { await cancelCashTransfer(id); toast({ title: `Transfer #${id} cancelled.` }); await load() }
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
                <ArrowRightLeft className="h-6 w-6 text-sky-600" /> Cash transfers
              </h1>
              <p className="text-sm text-slate-500">Move cash between your own accounts (Cash Box â†’ MoMo â†’ Bank etc.)</p>
            </div>
            <Dialog open={open} onOpenChange={setOpen}>
              <DialogTrigger asChild><Button className="w-full sm:w-auto h-11 sm:h-10"><Plus className="h-4 w-4 mr-1" />New transfer</Button></DialogTrigger>
              <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
                <DialogHeader>
                  <DialogTitle className="flex items-center gap-2">
                    <ArrowRightLeft className="w-5 h-5 text-blue-600" /> New cash transfer
                  </DialogTitle>
                  <DialogDescription>Creates a Draft. Approval writes paired TransferOut + TransferIn entries.</DialogDescription>
                </DialogHeader>
                <div className="space-y-4">
                  <FormSection title="Accounts" color="indigo">
                    <FormField label="From *">
                      <Select value={form.fromGenericCashAccountId} onValueChange={(v) => setForm((f) => ({ ...f, fromGenericCashAccountId: v }))}>
                        <SelectTrigger><SelectValue placeholder="Source..." /></SelectTrigger>
                        <SelectContent>{cashAccounts.filter((a) => a.isActive).map((a) => <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>{a.accountName} – {fmt(a.currentBalance)}</SelectItem>)}</SelectContent>
                      </Select>
                    </FormField>
                    <FormField label="To *">
                      <Select value={form.toGenericCashAccountId} onValueChange={(v) => setForm((f) => ({ ...f, toGenericCashAccountId: v }))}>
                        <SelectTrigger><SelectValue placeholder="Destination..." /></SelectTrigger>
                        <SelectContent>{cashAccounts.filter((a) => a.isActive && String(a.genericCashAccountId) !== form.fromGenericCashAccountId).map((a) => <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>{a.accountName}</SelectItem>)}</SelectContent>
                      </Select>
                    </FormField>
                  </FormSection>

                  <FormSection title="Transfer details" color="blue">
                    <FormField label="Amount *">
                      <NumberInput step="0.01" min="0" value={form.amount} onChange={(e) => setForm((f) => ({ ...f, amount: e.target.value }))} />
                    </FormField>
                    <FormField label="Date">
                      <Input type="date" value={form.transferDate} onChange={(e) => setForm((f) => ({ ...f, transferDate: e.target.value }))} />
                    </FormField>
                  </FormSection>

                  <FormSection title="Notes" color="slate" columns={1}>
                    <FormField label="Notes">
                      <Textarea rows={2} value={form.notes} onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} maxLength={500} />
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
                onClick={() => router.replace(s === "All" ? "/generic-cash-transfers" : `/generic-cash-transfers?status=${s}`)}>{s}</Button>
            ))}
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading...</div>
          ) : rows.length === 0 ? (
            <Card><CardContent className="py-8 text-center text-slate-500">No transfers yet.</CardContent></Card>
          ) : (
            <>
            <ListFilters
              search={search} setSearch={setSearch}
              dateFrom={dateFrom} setDateFrom={setDateFrom}
              dateTo={dateTo} setDateTo={setDateTo}
              searchPlaceholder="Search from/to account or notes"
            />
            <Card>
              <CardContent className="p-0">
                <MobileCardList
                  items={visibleRows}
                  getKey={(t) => t.genericCashTransferId}
                  primary={(t) => `#${t.genericCashTransferId} · ${t.fromAccountName ?? `#${t.fromGenericCashAccountId}`} → ${t.toAccountName ?? `#${t.toGenericCashAccountId}`}`}
                  secondary={(t) => <span>{new Date(t.transferDate).toLocaleDateString()}</span>}
                  trailing={(t) => <Badge className={badgeClass(t.status)}>{t.status}</Badge>}
                  details={(t) => [
                    { label: "Date", value: new Date(t.transferDate).toLocaleDateString() },
                    { label: "From", value: t.fromAccountName ?? `#${t.fromGenericCashAccountId}` },
                    { label: "To", value: t.toAccountName ?? `#${t.toGenericCashAccountId}` },
                    { label: "Amount", value: <span className="font-semibold">{fmt(t.amount)}</span> },
                  ]}
                  actions={(t) => (
                    <>
                      {t.status === "Draft" && (
                        <>
                          <Button size="sm" variant="outline" className="flex-1 h-10 text-emerald-700 border-emerald-200" onClick={() => onApprove(t.genericCashTransferId)}>
                            <Check className="h-4 w-4 mr-1" /> Approve
                          </Button>
                          <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => onCancel(t.genericCashTransferId)}>
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
                          <TableHead>From</TableHead>
                          <TableHead></TableHead>
                          <TableHead>To</TableHead>
                          <TableHead className="text-right">Amount</TableHead>
                          <TableHead>Status</TableHead>
                          <TableHead></TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {visibleRows.map((t) => (
                          <TableRow key={t.genericCashTransferId}>
                            <TableCell>#{t.genericCashTransferId}</TableCell>
                            <TableCell>{new Date(t.transferDate).toLocaleDateString()}</TableCell>
                            <TableCell>{t.fromAccountName ?? `#${t.fromGenericCashAccountId}`}</TableCell>
                            <TableCell><ArrowRightLeft className="h-3 w-3 text-slate-400" /></TableCell>
                            <TableCell>{t.toAccountName ?? `#${t.toGenericCashAccountId}`}</TableCell>
                            <TableCell className="text-right font-semibold">{fmt(t.amount)}</TableCell>
                            <TableCell><Badge className={badgeClass(t.status)}>{t.status}</Badge></TableCell>
                            <TableCell className="flex gap-1">
                              {t.status === "Draft" && (
                                <>
                                  <Button size="sm" className="bg-emerald-600 hover:bg-emerald-700" onClick={() => onApprove(t.genericCashTransferId)}><Check className="h-3 w-3 mr-1" />Approve</Button>
                                  <Button size="sm" variant="outline" onClick={() => onCancel(t.genericCashTransferId)}><X className="h-3 w-3" /></Button>
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

export default function GenericCashTransfersPage() {
  return (
    <Suspense fallback={<div className="p-6 text-slate-500">Loading...</div>}>
      <GenericCashTransfersPageInner />
    </Suspense>
  )
}
