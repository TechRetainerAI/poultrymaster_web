"use client"

/**
 * Generic Cash Transfers — deep copy of Poultry Cash Transfers.
 *
 * Money moving between the business's own accounts: cash box to bank, bank to
 * MoMo, bank to petty cash. A transfer is the same money in a different box
 * and must never look like the business earned or spent anything.
 */

import { Suspense, useCallback, useEffect, useMemo, useState } from "react"
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
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { usePagination } from "@/hooks/use-pagination"
import { ArrowLeftRight, ArrowRight, Check, Loader2, Plus, X, AlertTriangle } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import {
  approveCashTransfer, cancelCashTransfer, createCashTransfer, getCashAccounts, getCashTransfers,
  type GenericCashAccount, type GenericCashTransfer,
} from "@/lib/api/generic"
import { fmtDateTime } from "@/lib/utils/company-datetime"

const STATUS_FILTERS = ["All", "Draft", "Approved", "Cancelled"] as const

function statusClass(s: string) {
  switch (s) {
    case "Approved":  return "bg-emerald-100 text-emerald-800"
    case "Reversed":  return "bg-amber-100 text-amber-800"
    case "Cancelled": return "bg-slate-100 text-slate-700"
    default:          return "bg-sky-100 text-sky-800"
  }
}

function today() { return new Date().toISOString().slice(0, 10) }

function GenericCashTransfersPageInner() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const logout = useLogout()
  const { toast } = useToast()
  const gh = useFmt()

  const [accounts, setAccounts] = useState<GenericCashAccount[]>([])
  const [rows, setRows] = useState<GenericCashTransfer[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)

  const [statusFilter, setStatusFilter] = useState<string>("All")
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")

  const [newOpen, setNewOpen] = useState(false)
  const [form, setForm] = useState({
    fromId: "", toId: "", amount: "0", transferDate: today(), notes: "",
  })

  const load = useCallback(async () => {
    const [ts, as] = await Promise.allSettled([getCashTransfers(), getCashAccounts()])
    if (ts.status === "fulfilled") setRows(ts.value)
    if (as.status === "fulfilled") setAccounts(as.value)
    setLoading(false)
  }, [])

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    if (!activeFarmId) return
    setLoading(true)
    void load()
  }, [activeFarmType, activeFarmId, router, load])

  const activeAccounts = useMemo(() => accounts.filter((a) => a.isActive), [accounts])
  const acctBalance = (id: string | number) => {
    const a = accounts.find((a) => a.genericCashAccountId === Number(id))
    return a?.currentBalance ?? 0
  }
  const acctAllowsNegative = (id: string | number) => {
    const a = accounts.find((a) => a.genericCashAccountId === Number(id))
    return a?.allowNegativeBalance ?? false
  }

  const filtered = useMemo(() => {
    let list = rows
    if (statusFilter !== "All") list = list.filter((t) => t.status === statusFilter)
    return filterByDateAndSearch(list, {
      search, dateFrom, dateTo,
      searchKeys: ["fromAccountName", "toAccountName", "notes"],
      dateKey: "transferDate",
    })
  }, [rows, statusFilter, search, dateFrom, dateTo])

  const pg = usePagination(filtered)

  const totals = useMemo(() => {
    const approved = rows.filter((t) => t.status === "Approved")
    const moved = approved.reduce((s, t) => s + t.amount, 0)
    return { moved, count: approved.length, total: rows.length }
  }, [rows])

  // Balance preview
  const amt = Number(form.amount) || 0
  const fromBalance = form.fromId ? acctBalance(form.fromId) : 0
  const afterFrom = fromBalance - amt
  const wouldOverdraw = amt > 0 && form.fromId && afterFrom < 0 && !acctAllowsNegative(form.fromId)

  async function doCreate() {
    if (!form.fromId || !form.toId) { toast({ title: "Pick both accounts", variant: "destructive" }); return }
    if (form.fromId === form.toId) { toast({ title: "From and To must differ", variant: "destructive" }); return }
    if (!(amt > 0)) { toast({ title: "Amount must be > 0", variant: "destructive" }); return }
    setSaving(true)
    try {
      const id = await createCashTransfer({
        fromGenericCashAccountId: Number(form.fromId),
        toGenericCashAccountId: Number(form.toId),
        amount: amt,
        transferDate: form.transferDate,
        notes: form.notes || null,
      })
      // Auto-approve — the poultry page approves immediately too.
      if (id) {
        try { await approveCashTransfer(id) } catch { /* draft is still fine */ }
      }
      toast({ title: "Transfer recorded and approved." })
      setNewOpen(false)
      setForm({ fromId: "", toId: "", amount: "0", transferDate: today(), notes: "" })
      await load()
    } catch (e: any) {
      toast({ title: "Could not create transfer", description: e?.message, variant: "destructive" })
    } finally { setSaving(false) }
  }

  async function doApprove(id: number) {
    try { await approveCashTransfer(id); toast({ title: "Transfer approved." }); await load() }
    catch (e: any) { toast({ title: "Approve failed", description: e?.message, variant: "destructive" }) }
  }

  async function doCancel(id: number) {
    try { await cancelCashTransfer(id); toast({ title: "Transfer cancelled." }); await load() }
    catch (e: any) { toast({ title: "Cancel failed", description: e?.message, variant: "destructive" }) }
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
                <ArrowLeftRight className="h-5 w-5 text-sky-600" /> Cash Transfers
              </h1>
              <p className="text-xs text-slate-500">
                Move cash between your own accounts. Never company-wide money in or money out.
              </p>
            </div>
            <Button onClick={() => setNewOpen(true)}>
              <Plus className="h-4 w-4 mr-1" /> New Transfer
            </Button>
          </div>

          {/* KPI tiles */}
          <div className="grid grid-cols-3 gap-2">
            <Card><CardContent className="p-3">
              <div className="text-[11px] uppercase tracking-wide text-slate-500">Moved (Approved)</div>
              <div className="mt-1 text-lg font-semibold tabular-nums">{gh(totals.moved)}</div>
            </CardContent></Card>
            <Card><CardContent className="p-3">
              <div className="text-[11px] uppercase tracking-wide text-slate-500">Transfers</div>
              <div className="mt-1 text-lg font-semibold tabular-nums">{totals.count}</div>
            </CardContent></Card>
            <Card><CardContent className="p-3">
              <div className="text-[11px] uppercase tracking-wide text-slate-500">On record</div>
              <div className="mt-1 text-lg font-semibold tabular-nums">{totals.total}</div>
            </CardContent></Card>
          </div>

          {/* Status filter buttons */}
          <div className="flex gap-1 flex-wrap">
            {STATUS_FILTERS.map((s) => (
              <Button key={s} size="sm" variant={s === statusFilter ? "default" : "outline"}
                onClick={() => setStatusFilter(s)}>{s}</Button>
            ))}
          </div>

          <ListFilters
            search={search} setSearch={setSearch}
            dateFrom={dateFrom} setDateFrom={setDateFrom}
            dateTo={dateTo} setDateTo={setDateTo}
            searchPlaceholder="Search from/to account or notes"
          />

          {loading ? (
            <Card><CardContent className="py-12 text-center text-slate-600">
              <Loader2 className="h-4 w-4 animate-spin inline mr-2" />Loading transfers...
            </CardContent></Card>
          ) : (
            <Card>
              <CardContent className="p-0 md:p-2">
                {filtered.length === 0 ? (
                  <p className="px-4 py-8 text-center text-sm text-slate-500">
                    No transfers match the current filters.
                  </p>
                ) : (
                  <MobileCardList
                    defaultOpen striped stripeAccent="blue"
                    items={pg.pageItems} pagination={pg.paginationProps}
                    getKey={(t: any) => t.genericCashTransferId}
                    primary={(t: any) => `${t.fromAccountName ?? "?"} \u2192 ${t.toAccountName ?? "?"}`}
                    secondary={(t: any) => fmtDateTime(t.transferDate, t)}
                    trailing={(t: any) => <Badge className={statusClass(t.status)}>{t.status}</Badge>}
                    highlights={(t: any) => [
                      { label: "Amount", value: gh(t.amount), accent: "blue" },
                    ]}
                    details={(t: any) => [
                      { label: "From", value: t.fromAccountName ?? `#${t.fromGenericCashAccountId}` },
                      { label: "To", value: t.toAccountName ?? `#${t.toGenericCashAccountId}` },
                      { label: "Notes", value: t.notes ?? "\u2014" },
                    ]}
                    actions={(t: any) => (
                      <>
                        {t.status === "Draft" && (
                          <>
                            <Button size="sm" variant="outline" className="flex-1 h-10 text-emerald-700 border-emerald-200"
                              onClick={() => doApprove(t.genericCashTransferId)}>
                              <Check className="h-4 w-4 mr-1" /> Approve
                            </Button>
                            <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200"
                              onClick={() => doCancel(t.genericCashTransferId)}>
                              <X className="h-4 w-4 mr-1" /> Cancel
                            </Button>
                          </>
                        )}
                      </>
                    )}
                    desktopTable={
                      <div className="overflow-x-auto">
                        <Table>
                          <TableHeader><TableRow>
                            <TableHead>Date</TableHead>
                            <TableHead>From</TableHead>
                            <TableHead className="w-8" />
                            <TableHead>To</TableHead>
                            <TableHead className="text-right">Amount</TableHead>
                            <TableHead>Status</TableHead>
                            <TableHead>Notes</TableHead>
                            <TableHead className="text-right">Actions</TableHead>
                          </TableRow></TableHeader>
                          <TableBody>
                            {pg.pageItems.map((t: any) => (
                              <TableRow key={t.genericCashTransferId}
                                className={cn(t.status === "Cancelled" && "text-slate-400 line-through")}>
                                <TableCell className="whitespace-nowrap">{fmtDateTime(t.transferDate, t)}</TableCell>
                                <TableCell className="font-medium">{t.fromAccountName ?? `#${t.fromGenericCashAccountId}`}</TableCell>
                                <TableCell><ArrowRight className="h-3.5 w-3.5 text-slate-400" /></TableCell>
                                <TableCell className="font-medium">{t.toAccountName ?? `#${t.toGenericCashAccountId}`}</TableCell>
                                <TableCell className="text-right tabular-nums font-semibold">{gh(t.amount)}</TableCell>
                                <TableCell><Badge className={statusClass(t.status)}>{t.status}</Badge></TableCell>
                                <TableCell className="max-w-[200px] truncate text-sm text-slate-600">{t.notes ?? "\u2014"}</TableCell>
                                <TableCell className="text-right whitespace-nowrap">
                                  {t.status === "Draft" && (
                                    <div className="inline-flex gap-1">
                                      <Button size="sm" className="bg-emerald-600 hover:bg-emerald-700 text-white"
                                        onClick={() => doApprove(t.genericCashTransferId)}>
                                        <Check className="h-3.5 w-3.5 mr-1" /> Approve
                                      </Button>
                                      <Button size="sm" variant="outline"
                                        onClick={() => doCancel(t.genericCashTransferId)}>
                                        <X className="h-3.5 w-3.5" />
                                      </Button>
                                    </div>
                                  )}
                                </TableCell>
                              </TableRow>
                            ))}
                          </TableBody>
                        </Table>
                      </div>
                    }
                  />
                )}
              </CardContent>
            </Card>
          )}
        </main>
      </div>

      {/* New transfer dialog */}
      <Dialog open={newOpen} onOpenChange={setNewOpen}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <ArrowLeftRight className="w-5 h-5 text-sky-600" /> New cash transfer
            </DialogTitle>
            <DialogDescription>
              Moving money between your own accounts. Not money in or money out.
            </DialogDescription>
          </DialogHeader>
          <FormSection title="Accounts" color="indigo">
            <FormField label="From *">
              <Select value={form.fromId} onValueChange={(v) => setForm((f) => ({ ...f, fromId: v }))}>
                <SelectTrigger><SelectValue placeholder="Source account" /></SelectTrigger>
                <SelectContent>
                  {activeAccounts.map((a) => (
                    <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>
                      {a.accountName} ({gh(a.currentBalance)})
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </FormField>
            <FormField label="To *">
              <Select value={form.toId} onValueChange={(v) => setForm((f) => ({ ...f, toId: v }))}>
                <SelectTrigger><SelectValue placeholder="Destination account" /></SelectTrigger>
                <SelectContent>
                  {activeAccounts.filter((a) => String(a.genericCashAccountId) !== form.fromId).map((a) => (
                    <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>
                      {a.accountName} ({gh(a.currentBalance)})
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </FormField>
          </FormSection>
          <FormSection title="Transfer" color="blue">
            <FormField label="Amount *">
              <NumberInput step="0.01" min="0" value={form.amount}
                onChange={(e) => setForm((f) => ({ ...f, amount: e.target.value }))} />
            </FormField>
            <FormField label="Date">
              <Input type="date" value={form.transferDate}
                onChange={(e) => setForm((f) => ({ ...f, transferDate: e.target.value }))} />
            </FormField>
          </FormSection>

          {/* Balance preview */}
          {form.fromId && amt > 0 && (
            <div className="rounded-md border border-slate-200 bg-slate-50 px-3 py-2 text-xs">
              <span className="text-slate-600">
                {accounts.find((a) => a.genericCashAccountId === Number(form.fromId))?.accountName}:
              </span>{" "}
              <span className="tabular-nums">{gh(fromBalance)}</span>
              <span className="mx-1">&rarr;</span>
              <span className={cn("tabular-nums font-medium", afterFrom < 0 ? "text-rose-700" : "text-slate-900")}>
                {gh(afterFrom)}
              </span>
            </div>
          )}

          {wouldOverdraw && (
            <Alert className="border-amber-200 bg-amber-50 py-2">
              <AlertTriangle className="h-4 w-4 text-amber-700" />
              <AlertDescription className="text-xs text-amber-900">
                This transfer would take the source account negative. It does not allow negative balances.
              </AlertDescription>
            </Alert>
          )}

          <FormSection title="Notes" color="slate" columns={1}>
            <FormField label="Notes">
              <Textarea rows={2} value={form.notes}
                onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} maxLength={500} />
            </FormField>
          </FormSection>

          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setNewOpen(false)}>Cancel</Button>
            <Button onClick={doCreate} disabled={saving || !!wouldOverdraw}>
              {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : "Transfer & Approve"}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
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
