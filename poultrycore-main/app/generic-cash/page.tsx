"use client"

// Generic Cash & Accounts — deep copy of poultry-cash-accounts page structure.
// Full CRUD for accounts, transfer dialog, transactions quick-view, recalculate,
// delete confirmation, and the same stat cards / table / mobile layout as poultry.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Switch } from "@/components/ui/switch"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { usePagination } from "@/hooks/use-pagination"
import { Loader2, Wallet, ArrowLeftRight, Eye, Plus, Pencil, Trash2, RefreshCw, Scale, FileText } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  getCashAccounts, getCashAccountDetails, getCashTransfers,
  createCashTransfer, approveCashTransfer, cancelCashTransfer,
  createCashAccount, updateCashAccount, deleteCashAccount, listCashTransactions,
  type GenericCashAccount, type GenericCashAccountDetails, type GenericCashTransfer, type GenericCashTransaction,
} from "@/lib/api/generic"
import { fmtDateTime } from "@/lib/utils/company-datetime"

const ACCOUNT_TYPES = ["CashBox", "Bank", "MobileMoney", "PettyCash", "Other"]

// Tinted summary tile — same as poultry cash accounts StatCard
function StatCard({ label, value, accent }: { label: string; value: string | number; accent: "violet" | "emerald" | "amber" | "blue" }) {
  const tile = accent === "emerald" ? "bg-emerald-100 border-emerald-300"
    : accent === "amber" ? "bg-amber-100 border-amber-300"
    : accent === "blue" ? "bg-blue-100 border-blue-300"
    : "bg-violet-100 border-violet-300"
  const labelC = accent === "emerald" ? "text-emerald-900"
    : accent === "amber" ? "text-amber-900"
    : accent === "blue" ? "text-blue-900"
    : "text-violet-900"
  const valueC = accent === "emerald" ? "text-emerald-800"
    : accent === "amber" ? "text-amber-800"
    : accent === "blue" ? "text-blue-800"
    : "text-violet-900"
  return (
    <div className={`rounded-lg border px-3 py-2 shadow-sm ${tile}`}>
      <p className={`text-[11px] font-semibold uppercase tracking-wide ${labelC}`}>{label}</p>
      <p className={`text-xl font-extrabold leading-tight tabular-nums ${valueC}`}>{value}</p>
    </div>
  )
}

export default function GenericCashPage() {
  const router = useRouter()
  const fmt = useFmt()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()

  const [accounts, setAccounts] = useState<GenericCashAccount[]>([])
  const [transfers, setTransfers] = useState<GenericCashTransfer[]>([])
  const [details, setDetails] = useState<Map<number, GenericCashAccountDetails>>(new Map())
  const [search, setSearch] = useState("")
  const [loading, setLoading] = useState(true)

  const visibleAccounts = useMemo(
    () => filterByDateAndSearch(accounts, { search, searchKeys: ["accountName", "accountType"] }),
    [accounts, search],
  )
  const pg = usePagination(visibleAccounts)

  // Create/edit account dialog
  const [open, setOpen] = useState(false)
  const [editId, setEditId] = useState<number | null>(null)
  const [form, setForm] = useState({ accountName: "", accountType: "CashBox", openingBalance: 0, allowNegativeBalance: false, notes: "", isActive: true })
  const [saving, setSaving] = useState(false)

  // Delete dialog
  const [deleteTarget, setDeleteTarget] = useState<GenericCashAccount | null>(null)

  // Transactions quick-view dialog
  const [txDlg, setTxDlg] = useState<{ open: boolean; acc?: GenericCashAccount; rows: GenericCashTransaction[] }>({ open: false, rows: [] })

  // Detail dialog
  const [detailDlg, setDetailDlg] = useState<{ open: boolean; acc?: GenericCashAccount; detail?: GenericCashAccountDetails }>({ open: false })

  // Transfer dialog
  const [xferDlg, setXferDlg] = useState(false)
  const [xferForm, setXferForm] = useState({ fromGenericCashAccountId: 0, toGenericCashAccountId: 0, amount: 0, notes: "" })

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const [accs, xfers] = await Promise.all([getCashAccounts(), getCashTransfers()])
      setAccounts(accs); setTransfers(xfers)
      const detailMap = new Map<number, GenericCashAccountDetails>()
      const detailResults = await Promise.allSettled(
        accs.map((a) => getCashAccountDetails(a.genericCashAccountId))
      )
      detailResults.forEach((r, i) => {
        if (r.status === "fulfilled" && r.value) detailMap.set(accs[i].genericCashAccountId, r.value)
      })
      setDetails(detailMap)
    } catch (e: any) { toast({ title: "Could not load cash accounts", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  // Create/Edit
  function openNew() {
    setEditId(null)
    setForm({ accountName: "", accountType: "CashBox", openingBalance: 0, allowNegativeBalance: false, notes: "", isActive: true })
    setOpen(true)
  }
  function openEdit(a: GenericCashAccount) {
    setEditId(a.genericCashAccountId)
    setForm({ accountName: a.accountName, accountType: a.accountType, openingBalance: a.openingBalance, allowNegativeBalance: a.allowNegativeBalance, notes: a.notes ?? "", isActive: a.isActive })
    setOpen(true)
  }

  async function save() {
    if (!form.accountName.trim()) return toast({ title: "Name required", variant: "destructive" })
    setSaving(true)
    try {
      if (editId) {
        await updateCashAccount(editId, { accountName: form.accountName, accountType: form.accountType, allowNegativeBalance: form.allowNegativeBalance, isActive: form.isActive, notes: form.notes })
        toast({ title: "Account updated" })
      } else {
        await createCashAccount({ accountName: form.accountName, accountType: form.accountType, openingBalance: form.openingBalance, allowNegativeBalance: form.allowNegativeBalance, notes: form.notes })
        toast({ title: "Account created" })
      }
      setOpen(false); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  // Default account
  async function createDefault() {
    const DEFAULT_NAME = "Main Cash Account"
    if (accounts.some((a) => a.accountName.trim().toLowerCase() === DEFAULT_NAME.toLowerCase())) {
      toast({ title: "Default account already exists", description: `"${DEFAULT_NAME}" is already set up.` })
      return
    }
    setSaving(true)
    try {
      await createCashAccount({ accountName: DEFAULT_NAME, accountType: "CashBox", openingBalance: 0, allowNegativeBalance: false, notes: "Default cash account" })
      toast({ title: "Default account created", description: `"${DEFAULT_NAME}" is ready to use.` })
      await load()
    } catch (e: any) {
      toast({ title: "Could not create default account", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  // Recalculate — reload details (ledger balances recalculated server-side)
  async function recalculate() {
    toast({ title: "Recalculating…" })
    await load()
    toast({ title: "Balances recalculated" })
  }

  // Delete
  async function performDelete(acc: GenericCashAccount) {
    await deleteCashAccount(acc.genericCashAccountId)
    toast({ title: "Cash account removed" })
    await load()
  }

  // Transactions quick-view
  async function viewTransactions(acc: GenericCashAccount) {
    setTxDlg({ open: true, acc, rows: [] })
    try {
      const rows = await listCashTransactions({ cashAccountId: acc.genericCashAccountId })
      setTxDlg({ open: true, acc, rows })
    } catch (e: any) { toast({ title: "Failed to load transactions", description: e?.message, variant: "destructive" }) }
  }

  // Details
  async function viewDetails(acc: GenericCashAccount) {
    setDetailDlg({ open: true, acc })
    try {
      const detail = await getCashAccountDetails(acc.genericCashAccountId)
      if (detail) setDetailDlg({ open: true, acc, detail })
    } catch (e: any) { toast({ title: "Failed to load details", description: e?.message, variant: "destructive" }) }
  }

  // Transfer
  async function saveTransfer() {
    if (xferForm.fromGenericCashAccountId === xferForm.toGenericCashAccountId) return toast({ title: "From and To must differ", variant: "destructive" })
    if (xferForm.amount <= 0) return toast({ title: "Amount required", variant: "destructive" })
    try {
      const created = await createCashTransfer({
        fromGenericCashAccountId: xferForm.fromGenericCashAccountId,
        toGenericCashAccountId: xferForm.toGenericCashAccountId,
        amount: xferForm.amount,
        notes: xferForm.notes || null,
      })
      if (created) {
        await approveCashTransfer(created.genericCashTransferId)
        toast({ title: "Transfer approved" })
      }
      setXferDlg(false)
      setXferForm({ fromGenericCashAccountId: 0, toGenericCashAccountId: 0, amount: 0, notes: "" })
      await load()
    } catch (e: any) { toast({ title: "Transfer failed", description: e?.message, variant: "destructive" }) }
  }

  const totalCash = accounts.filter(a => a.isActive).reduce((s, a) => {
    const d = details.get(a.genericCashAccountId)
    return s + (d?.ledgerBalance ?? a.currentBalance)
  }, 0)

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          {/* Header — matching poultry */}
          <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <Wallet className="h-6 w-6 text-sky-600" /> Cash Account
            </h1>
            <div className="flex flex-wrap gap-2">
              <Button size="sm" onClick={openNew}>
                <Plus className="h-4 w-4 mr-1" /> New account
              </Button>
              <Button size="sm" onClick={() => setXferDlg(true)}>
                <ArrowLeftRight className="h-4 w-4 mr-1" /> Transfer
              </Button>
              <Button size="sm" variant="outline" onClick={() => router.push("/generic-cash-reconciliation")}>
                <Scale className="h-4 w-4 mr-1" /> Reconcile
              </Button>
              <Button size="sm" variant="outline" onClick={recalculate}>
                <RefreshCw className="h-4 w-4 mr-1" /> Recalculate
              </Button>
            </div>
          </div>

          {/* Cash flow link — matching poultry */}
          <button
            type="button"
            onClick={() => router.push("/generic-cash-flow")}
            className="mb-4 inline-flex items-center gap-1.5 text-sm font-medium text-sky-600 hover:text-sky-700 hover:underline"
          >
            <ArrowLeftRight className="h-4 w-4" /> See the whole company&apos;s cash flow →
          </button>

          {/* Summary cards — matching poultry */}
          <div className="mb-3 grid grid-cols-2 md:grid-cols-4 gap-3">
            <StatCard label="Total cash at hand" value={fmt(totalCash)} accent="violet" />
            <StatCard label="Active accounts" value={accounts.filter(a => a.isActive).length} accent="emerald" />
            <StatCard label="Pending transfers" value={transfers.filter(t => t.status === "Draft").length} accent="amber" />
            <StatCard label="Approved transfers" value={transfers.filter(t => t.status === "Approved").length} accent="blue" />
          </div>

          <ListFilters search={search} setSearch={setSearch} searchOnly searchPlaceholder="Search account name or type" />

          {/* Accounts table — matching poultry */}
          <Card className="gap-0 py-0">
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : accounts.length === 0 ? (
                <div className="p-8 text-center text-slate-500">
                  <p>No cash accounts yet.</p>
                  <Button className="mt-3" onClick={createDefault} disabled={saving}><Wallet className="h-4 w-4 mr-1" /> Create default account</Button>
                </div>
              ) : (
                <MobileCardList
                  defaultOpen
                  striped
                  items={pg.pageItems}
                  pagination={pg.paginationProps}
                  getKey={(a) => a.genericCashAccountId}
                  primary={(a) => a.accountName}
                  secondary={(a) => (
                    <>
                      <span>{a.accountType}</span>
                      {a.isActive ? <Badge className="bg-green-100 text-green-700">Active</Badge> : <Badge variant="outline">Inactive</Badge>}
                    </>
                  )}
                  highlights={(a) => [
                    { label: "Opening", value: fmt(a.openingBalance), accent: "blue" },
                    { label: "Current", value: fmt(a.currentBalance), accent: a.currentBalance < 0 ? "rose" : "emerald" },
                  ]}
                  details={(a) => [
                    { label: "Type", value: a.accountType },
                    { label: "Allows negative", value: a.allowNegativeBalance ? "Yes" : "No" },
                    { label: "Status", value: a.isActive ? "Active" : "Inactive" },
                  ]}
                  actions={(a) => (
                    <>
                      <Button size="sm" variant="outline" className="flex-1 h-10 bg-white" onClick={() => viewDetails(a)}>
                        <Eye className="h-4 w-4 mr-1" /> View details
                      </Button>
                      <Button size="sm" variant="outline" className="flex-1 h-10 bg-white" onClick={() => openEdit(a)}>Edit</Button>
                      <Button size="sm" variant="outline" className="flex-1 h-10 bg-white text-red-600 border-red-200" onClick={() => setDeleteTarget(a)}><Trash2 className="h-4 w-4 mr-1" /> Delete</Button>
                    </>
                  )}
                  desktopTable={
                    <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Name</TableHead>
                          <TableHead>Type</TableHead>
                          <TableHead className="text-right">Opening</TableHead>
                          <TableHead className="text-right">Current</TableHead>
                          <TableHead className="text-right">Calculated</TableHead>
                          <TableHead>Allows negative</TableHead>
                          <TableHead>Status</TableHead>
                          <TableHead className="text-right">Actions</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {pg.pageItems.map((a) => {
                          const d = details.get(a.genericCashAccountId)
                          return (
                            <TableRow key={a.genericCashAccountId}>
                              <TableCell className="font-medium">{a.accountName}</TableCell>
                              <TableCell>{a.accountType}</TableCell>
                              <TableCell className="text-right tabular-nums">{fmt(a.openingBalance)}</TableCell>
                              <TableCell className={`text-right tabular-nums ${a.currentBalance < 0 ? "text-rose-600" : "text-slate-500"}`}>{fmt(a.currentBalance)}</TableCell>
                              <TableCell className="text-right tabular-nums font-semibold">
                                {d ? (
                                  <span className={d.ledgerBalance < 0 ? "text-rose-600" : undefined}>
                                    {fmt(d.ledgerBalance)}
                                    {Math.abs(d.ledgerBalance - a.currentBalance) >= 0.01 && (
                                      <span className="ml-1 text-[10px] font-normal text-amber-700" title="Balance drifted from calculated">drift</span>
                                    )}
                                  </span>
                                ) : <span className="text-slate-400">—</span>}
                              </TableCell>
                              <TableCell>{a.allowNegativeBalance ? "Yes" : "No"}</TableCell>
                              <TableCell>{a.isActive ? <Badge className="bg-green-100 text-green-700">Active</Badge> : <Badge variant="outline">Inactive</Badge>}</TableCell>
                              <TableCell className="text-right">
                                <Button size="sm" variant="ghost" onClick={() => viewDetails(a)} title="View details"><Eye className="h-4 w-4" /></Button>
                                <Button size="sm" variant="ghost" onClick={() => viewTransactions(a)} title="Quick transactions">Txns</Button>
                                <Button size="sm" variant="ghost" onClick={() => router.push(`/generic-cash-reconciliation?accountId=${a.genericCashAccountId}`)} title="Reconcile this account">Reconcile</Button>
                                <Button size="sm" variant="ghost" onClick={() => openEdit(a)}>Edit</Button>
                                <Button size="sm" variant="ghost" onClick={() => setDeleteTarget(a)} title="Delete account"><Trash2 className="h-4 w-4 text-red-500" /></Button>
                              </TableCell>
                            </TableRow>
                          )
                        })}
                      </TableBody>
                    </Table>
                    </div>
                  }
                />
              )}
            </CardContent>
          </Card>

          {/* Recent transfers — matching poultry */}
          {transfers.length > 0 && (
            <Card className="mt-4">
              <CardContent className="p-4">
                <div className="mb-2 font-medium text-slate-700">Recent transfers</div>
                <MobileCardList
                  defaultOpen
                  items={transfers.slice(0, 8)}
                  getKey={(t) => t.genericCashTransferId}
                  primary={(t) => `${t.fromAccountName ?? "Account"} → ${t.toAccountName ?? "Account"}`}
                  secondary={(t) => (<><span>{fmtDateTime(t.transferDate, t)}</span><Badge variant="outline">{t.status}</Badge></>)}
                  details={(t) => [
                    { label: "Date", value: fmtDateTime(t.transferDate, t) },
                    { label: "From", value: t.fromAccountName ?? "—" },
                    { label: "To", value: t.toAccountName ?? "—" },
                    { label: "Amount", value: fmt(t.amount) },
                    { label: "Status", value: t.status },
                  ]}
                  actions={(t) => (
                    <>
                      {t.status === "Draft" && (
                        <>
                          <Button size="sm" variant="outline" className="flex-1 h-10 text-green-700 border-green-200" onClick={async () => { await approveCashTransfer(t.genericCashTransferId); await load() }}>Approve</Button>
                          <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={async () => { await cancelCashTransfer(t.genericCashTransferId); await load() }}>Cancel</Button>
                        </>
                      )}
                    </>
                  )}
                  desktopTable={
                    <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow><TableHead>Date</TableHead><TableHead>From</TableHead><TableHead>To</TableHead><TableHead className="text-right">Amount</TableHead><TableHead>Status</TableHead><TableHead className="text-right">Actions</TableHead></TableRow>
                      </TableHeader>
                      <TableBody>
                        {transfers.slice(0, 8).map((t) => (
                          <TableRow key={t.genericCashTransferId}>
                            <TableCell>{fmtDateTime(t.transferDate, t)}</TableCell>
                            <TableCell>{t.fromAccountName ?? "—"}</TableCell>
                            <TableCell>{t.toAccountName ?? "—"}</TableCell>
                            <TableCell className="text-right tabular-nums">{fmt(t.amount)}</TableCell>
                            <TableCell><Badge variant="outline">{t.status}</Badge></TableCell>
                            <TableCell className="text-right">
                              {t.status === "Draft" && <>
                                <Button size="sm" variant="ghost" onClick={async () => { await approveCashTransfer(t.genericCashTransferId); await load() }}>Approve</Button>
                                <Button size="sm" variant="ghost" onClick={async () => { await cancelCashTransfer(t.genericCashTransferId); await load() }}>Cancel</Button>
                              </>}
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

      {/* Create/edit account — matching poultry */}
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              {editId ? <Pencil className="w-5 h-5 text-blue-600" /> : <Wallet className="w-5 h-5 text-blue-600" />}
              {editId ? "Edit account" : "New cash account"}
            </DialogTitle>
            <DialogDescription>Configure where cash flows into or out of</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormSection title="Identity" color="indigo">
              <FormField label="Name *" full>
                <Input value={form.accountName} onChange={(e) => setForm({ ...form, accountName: e.target.value })} />
              </FormField>
              <FormField label="Type" full={!!editId}>
                <Select value={form.accountType} onValueChange={(v) => setForm({ ...form, accountType: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{ACCOUNT_TYPES.map(t => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
              {!editId && (
                <FormField label="Opening balance">
                  <NumberInput step="0.01" value={form.openingBalance} onChange={(e) => setForm({ ...form, openingBalance: Number(e.target.value) || 0 })} />
                </FormField>
              )}
            </FormSection>

            <FormSection title="Behavior" color="amber" columns={1}>
              <FormField label="Allow negative balance">
                <div className="flex items-center justify-between rounded border p-2">
                  <span className="text-sm text-slate-700">Allow this account to go below zero</span>
                  <Switch checked={form.allowNegativeBalance} onCheckedChange={(v) => setForm({ ...form, allowNegativeBalance: v })} />
                </div>
              </FormField>
              {editId && (
                <FormField label="Active">
                  <div className="flex items-center justify-between rounded border p-2">
                    <span className="text-sm text-slate-700">Active</span>
                    <Switch checked={form.isActive} onCheckedChange={(v) => setForm({ ...form, isActive: v })} />
                  </div>
                </FormField>
              )}
            </FormSection>

            <FormSection title="Notes" color="slate" columns={1}>
              <FormField label="Notes">
                <Input value={form.notes ?? ""} onChange={(e) => setForm({ ...form, notes: e.target.value })} />
              </FormField>
            </FormSection>

            <div className="flex gap-3 justify-end pt-2">
              <Button type="button" onClick={() => setOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
              <Button onClick={save} disabled={saving}>
                {saving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : "Save"}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Transactions quick-view — matching poultry */}
      <Dialog open={txDlg.open} onOpenChange={(v) => setTxDlg({ open: v, rows: [] })}>
        <DialogContent className="w-[95vw] max-w-[1600px] max-h-[90vh] overflow-y-auto">
          <DialogHeader><DialogTitle>Transactions — {txDlg.acc?.accountName}</DialogTitle></DialogHeader>
          {txDlg.rows.length === 0 ? <div className="p-4 text-slate-500">No transactions yet.</div> : (
            <div className="max-h-96 overflow-auto overflow-x-auto">
              <Table>
                <TableHeader><TableRow><TableHead>Date</TableHead><TableHead>Type</TableHead><TableHead>Source</TableHead><TableHead className="text-right">Amount</TableHead><TableHead>Description</TableHead></TableRow></TableHeader>
                <TableBody>
                  {txDlg.rows.map((r) => (
                    <TableRow key={r.genericCashTransactionId}>
                      <TableCell>{fmtDateTime(r.transactionDate, r)}</TableCell>
                      <TableCell>{r.transactionType}</TableCell>
                      <TableCell>{r.sourceType ?? "—"}</TableCell>
                      <TableCell className={`text-right tabular-nums ${r.amount < 0 ? "text-rose-600" : "text-green-700"}`}>{fmt(r.amount)}</TableCell>
                      <TableCell className="max-w-sm whitespace-normal break-words align-top">{r.description ?? "—"}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* Account detail dialog */}
      <Dialog open={detailDlg.open} onOpenChange={(v) => setDetailDlg({ open: v })}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Wallet className="w-5 h-5 text-sky-600" /> {detailDlg.acc?.accountName}
            </DialogTitle>
            <DialogDescription>{detailDlg.acc?.accountType} · {detailDlg.acc?.isActive ? "Active" : "Inactive"}</DialogDescription>
          </DialogHeader>
          {detailDlg.detail ? (
            <div className="space-y-3">
              <div className="grid grid-cols-2 gap-3">
                <div className="rounded-lg border bg-slate-50 p-3">
                  <div className="text-[10px] uppercase text-slate-500">Opening Balance</div>
                  <div className="text-lg font-semibold tabular-nums">{fmt(detailDlg.detail.openingBalance)}</div>
                </div>
                <div className="rounded-lg border bg-slate-50 p-3">
                  <div className="text-[10px] uppercase text-slate-500">Current Balance</div>
                  <div className={`text-lg font-semibold tabular-nums ${detailDlg.detail.currentBalance < 0 ? "text-rose-600" : ""}`}>{fmt(detailDlg.detail.currentBalance)}</div>
                </div>
                <div className="rounded-lg border bg-emerald-50 p-3">
                  <div className="text-[10px] uppercase text-emerald-700">Total Money In</div>
                  <div className="text-lg font-semibold tabular-nums text-emerald-700">{fmt(detailDlg.detail.totalMoneyIn)}</div>
                </div>
                <div className="rounded-lg border bg-rose-50 p-3">
                  <div className="text-[10px] uppercase text-rose-700">Total Money Out</div>
                  <div className="text-lg font-semibold tabular-nums text-rose-700">{fmt(detailDlg.detail.totalMoneyOut)}</div>
                </div>
                <div className="rounded-lg border bg-blue-50 p-3">
                  <div className="text-[10px] uppercase text-blue-700">Transfer In</div>
                  <div className="text-lg font-semibold tabular-nums text-blue-700">{fmt(detailDlg.detail.transferIn)}</div>
                </div>
                <div className="rounded-lg border bg-amber-50 p-3">
                  <div className="text-[10px] uppercase text-amber-700">Transfer Out</div>
                  <div className="text-lg font-semibold tabular-nums text-amber-700">{fmt(detailDlg.detail.transferOut)}</div>
                </div>
              </div>
              <div className="rounded-lg border p-3">
                <div className="flex items-center justify-between">
                  <span className="text-sm text-slate-600">Ledger Balance</span>
                  <span className="font-semibold tabular-nums">{fmt(detailDlg.detail.ledgerBalance)}</span>
                </div>
                <div className="flex items-center justify-between mt-1">
                  <span className="text-sm text-slate-600">Total Adjustments</span>
                  <span className="tabular-nums">{fmt(detailDlg.detail.totalAdjustments)}</span>
                </div>
                <div className="flex items-center justify-between mt-1">
                  <span className="text-sm text-slate-600">Unreconciled</span>
                  <span className="tabular-nums">{detailDlg.detail.unreconciledCount}</span>
                </div>
                {detailDlg.detail.lastReconciledAt && (
                  <div className="flex items-center justify-between mt-1">
                    <span className="text-sm text-slate-600">Last Reconciled</span>
                    <span className="text-xs text-slate-500">{fmtDateTime(detailDlg.detail.lastReconciledAt, detailDlg.detail)}</span>
                  </div>
                )}
              </div>
            </div>
          ) : (
            <div className="flex items-center gap-2 text-slate-500 py-6 justify-center"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          )}
        </DialogContent>
      </Dialog>

      {/* Transfer dialog — matching poultry */}
      <Dialog open={xferDlg} onOpenChange={setXferDlg}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <ArrowLeftRight className="w-5 h-5 text-blue-600" /> Cash transfer (Draft → Approved)
            </DialogTitle>
            <DialogDescription>Move funds between two cash accounts</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormSection title="Accounts" color="indigo">
              <FormField label="From">
                <Select value={String(xferForm.fromGenericCashAccountId)} onValueChange={(v) => setXferForm({ ...xferForm, fromGenericCashAccountId: Number(v) })}>
                  <SelectTrigger><SelectValue placeholder="From account" /></SelectTrigger>
                  <SelectContent>{accounts.filter(a => a.isActive).map(a => <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>{a.accountName}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
              <FormField label="To">
                <Select value={String(xferForm.toGenericCashAccountId)} onValueChange={(v) => setXferForm({ ...xferForm, toGenericCashAccountId: Number(v) })}>
                  <SelectTrigger><SelectValue placeholder="To account" /></SelectTrigger>
                  <SelectContent>{accounts.filter(a => a.isActive).map(a => <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>{a.accountName}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
            </FormSection>

            <FormSection title="Amount" color="amber" columns={1}>
              <FormField label="Amount">
                <NumberInput min={0.01} step="0.01" value={xferForm.amount} onChange={(e) => setXferForm({ ...xferForm, amount: Number(e.target.value) || 0 })} />
              </FormField>
              <FormField label="Notes">
                <Input value={xferForm.notes} onChange={(e) => setXferForm({ ...xferForm, notes: e.target.value })} placeholder="Reason for transfer" />
              </FormField>
            </FormSection>

            <div className="flex gap-3 justify-end pt-2">
              <Button type="button" onClick={() => setXferDlg(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
              <Button onClick={saveTransfer}>Create &amp; approve</Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      <ConfirmDeleteDialog
        open={!!deleteTarget}
        onOpenChange={(o) => { if (!o) setDeleteTarget(null) }}
        title={`Remove ${deleteTarget?.accountName ?? "this account"}?`}
        description="The account is deactivated so its transaction history stays intact."
        confirmLabel="Remove account"
        errorTitle="Could not remove account"
        onConfirm={async () => { if (deleteTarget) await performDelete(deleteTarget) }}
      />
    </div>
  )
}
