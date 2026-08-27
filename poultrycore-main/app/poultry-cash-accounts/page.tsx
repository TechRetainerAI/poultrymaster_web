"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { ListFilters } from "@/components/ui/list-filters"
import { filterByDateAndSearch } from "@/components/ui/list-filters"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Badge } from "@/components/ui/badge"
import { Switch } from "@/components/ui/switch"
import { Plus, Pencil, Loader2, Wallet, RefreshCw, ArrowLeftRight, Eye, Trash2, Scale } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  listPoultryCashAccounts, createPoultryCashAccount, updatePoultryCashAccount, deletePoultryCashAccount, reconcilePoultryCashBalances,
  listPoultryCashTransactions, listPoultryCashTransfers, createPoultryCashTransfer, approvePoultryCashTransfer, cancelPoultryCashTransfer,
  POULTRY_CASH_ACCOUNT_TYPES, POULTRY_CASH_TRANSFER_REASONS,
  type PoultryCashAccount, type PoultryCashTransaction, type PoultryCashTransfer,
} from "@/lib/api/poultry-finance"

const ACCOUNT_TYPES = [...POULTRY_CASH_ACCOUNT_TYPES]

export default function PoultryCashAccountsPage() {
  // Amounts were rendering as bare numbers with no currency at all.
  const fmt = useFmt()
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [accounts, setAccounts] = useState<PoultryCashAccount[]>([])
  const [transfers, setTransfers] = useState<PoultryCashTransfer[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [loading, setLoading] = useState(true)

  const visibleAccounts = useMemo(
    () => filterByDateAndSearch(accounts, { search, dateFrom, dateTo, searchKeys: ["accountName", "accountType"] }),
    [accounts, search, dateFrom, dateTo],
  )

  // Client-side paging: the whole list is already in memory, so this is a
  // slice. Feed the SAME slice to the cards and the desktop table.
  const pg = usePagination(visibleAccounts)

  const [open, setOpen] = useState(false)
  const [editId, setEditId] = useState<number | null>(null)
  const [form, setForm] = useState({ accountName: "", accountType: "FarmCashBox", openingBalance: 0, allowNegativeBalance: false, notes: "", isActive: true })
  const [saving, setSaving] = useState(false)

  const [deleteTarget, setDeleteTarget] = useState<PoultryCashAccount | null>(null)
  const [txDlg, setTxDlg] = useState<{ open: boolean; acc?: PoultryCashAccount; rows: PoultryCashTransaction[] }>({ open: false, rows: [] })
  const [xferDlg, setXferDlg] = useState(false)
  const [xferForm, setXferForm] = useState({ fromPoultryCashAccountId: 0, toPoultryCashAccountId: 0, amount: 0, notes: "", notesOther: "" })

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const [accs, xfers] = await Promise.all([listPoultryCashAccounts(), listPoultryCashTransfers()])
      setAccounts(accs); setTransfers(xfers)
    } catch (e: any) { toast({ title: "Could not load cash accounts", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openNew() {
    setEditId(null)
    setForm({ accountName: "", accountType: "FarmCashBox", openingBalance: 0, allowNegativeBalance: false, notes: "", isActive: true })
    setOpen(true)
  }
  function openEdit(a: PoultryCashAccount) {
    setEditId(a.poultryCashAccountId)
    setForm({ accountName: a.accountName, accountType: a.accountType, openingBalance: a.openingBalance, allowNegativeBalance: a.allowNegativeBalance, notes: a.notes ?? "", isActive: a.isActive })
    setOpen(true)
  }

  async function save() {
    if (!form.accountName.trim()) return toast({ title: "Name required", variant: "destructive" })
    setSaving(true)
    try {
      if (editId) {
        await updatePoultryCashAccount(editId, { accountName: form.accountName, accountType: form.accountType, allowNegativeBalance: form.allowNegativeBalance, isActive: form.isActive, notes: form.notes })
        toast({ title: "Account updated" })
      } else {
        await createPoultryCashAccount({ accountName: form.accountName, accountType: form.accountType, openingBalance: form.openingBalance, allowNegativeBalance: form.allowNegativeBalance, notes: form.notes })
        toast({ title: "Account created" })
      }
      setOpen(false); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  // One-click default account — every farm should have a main cash box.
  async function createDefault() {
    const DEFAULT_NAME = "Main Cash Account"
    if (accounts.some((a) => a.accountName.trim().toLowerCase() === DEFAULT_NAME.toLowerCase())) {
      toast({ title: "Default account already exists", description: `"${DEFAULT_NAME}" is already set up.` })
      return
    }
    setSaving(true)
    try {
      await createPoultryCashAccount({ accountName: DEFAULT_NAME, accountType: "FarmCashBox", openingBalance: 0, allowNegativeBalance: false, notes: "Default cash account" })
      toast({ title: "Default account created", description: `"${DEFAULT_NAME}" is ready to use.` })
      await load()
    } catch (e: any) {
      toast({ title: "Could not create default account", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  async function reconcile() {
    try { await reconcilePoultryCashBalances(); toast({ title: "Balances recalculated" }); await load() }
    catch (e: any) { toast({ title: "Recalculate failed", description: e?.message, variant: "destructive" }) }
  }

  async function performDelete(acc: PoultryCashAccount) {
    await deletePoultryCashAccount(acc.poultryCashAccountId)
    toast({ title: "Cash account removed" })
    await load()
  }

  async function viewTransactions(acc: PoultryCashAccount) {
    setTxDlg({ open: true, acc, rows: [] })
    try {
      const rows = await listPoultryCashTransactions({ cashAccountId: acc.poultryCashAccountId })
      setTxDlg({ open: true, acc, rows })
    } catch (e: any) { toast({ title: "Failed to load transactions", description: e?.message, variant: "destructive" }) }
  }

  async function saveTransfer() {
    if (xferForm.fromPoultryCashAccountId === xferForm.toPoultryCashAccountId) return toast({ title: "From and To must differ", variant: "destructive" })
    if (xferForm.amount <= 0) return toast({ title: "Amount required", variant: "destructive" })
    if (xferForm.notes === "Other" && !xferForm.notesOther.trim()) {
      return toast({ title: "Say what happened", variant: "destructive" })
    }
    try {
      // "Other" sends what was typed; a picked option sends itself. notesOther
      // is dialog-local and never reaches the API.
      const { notesOther, ...rest } = xferForm
      const notes = xferForm.notes === "Other" ? notesOther.trim() : xferForm.notes
      const { poultryCashTransferId } = await createPoultryCashTransfer({ ...rest, notes })
      await approvePoultryCashTransfer(poultryCashTransferId)
      toast({ title: "Transfer approved" })
      setXferDlg(false)
      setXferForm({ fromPoultryCashAccountId: 0, toPoultryCashAccountId: 0, amount: 0, notes: "", notesOther: "" })
      await load()
    } catch (e: any) { toast({ title: "Transfer failed", description: e?.message, variant: "destructive" }) }
  }

  const totalCash = accounts.filter(a => a.isActive).reduce((s, a) => s + a.currentBalance, 0)

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <Wallet className="h-6 w-6 text-sky-600" /> Cash Account
            </h1>
            <div className="flex flex-wrap gap-2 w-full sm:w-auto">
              <Button variant="outline" className="flex-1 sm:flex-none whitespace-nowrap" onClick={reconcile}><RefreshCw className="h-4 w-4 mr-1" /> Recalculate</Button>
              {/* Reconcile opens the dedicated page — pick an account, count it,
                  post the difference. Recalculate (rebuilding the cached balance
                  from the ledger, which moves no money) stays here so the two
                  balance-truth jobs are one click apart without their names
                  sitting on top of each other. */}
              <Button asChild variant="outline" className="flex-1 sm:flex-none whitespace-nowrap">
                <Link href="/poultry-cash-reconciliation"><Scale className="h-4 w-4 mr-1" /> Reconcile</Link>
              </Button>
              <Button variant="outline" className="flex-1 sm:flex-none whitespace-nowrap" onClick={() => setXferDlg(true)}><ArrowLeftRight className="h-4 w-4 mr-1" /> Transfer</Button>
              <Button variant="outline" className="flex-1 sm:flex-none whitespace-nowrap" onClick={createDefault} disabled={saving}><Wallet className="h-4 w-4 mr-1" /> Create default account</Button>
              <Button className="flex-1 sm:flex-none whitespace-nowrap" onClick={openNew}><Plus className="h-4 w-4 mr-1" /> New account</Button>
            </div>
          </div>

          <button
            type="button"
            onClick={() => router.push("/cash")}
            className="mb-4 inline-flex items-center gap-1.5 text-sm font-medium text-sky-600 hover:text-sky-700 hover:underline"
          >
            <ArrowLeftRight className="h-4 w-4" /> Want to see all your money movement in one place? Click here →
          </button>

          <div className="mb-3 grid grid-cols-2 md:grid-cols-4 gap-3">
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Total cash at hand</div><div className="text-xl font-semibold tabular-nums">{fmt(totalCash)}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Active accounts</div><div className="text-xl font-semibold">{accounts.filter(a => a.isActive).length}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Pending transfers</div><div className="text-xl font-semibold">{transfers.filter(t => t.status === "Draft").length}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Approved transfers</div><div className="text-xl font-semibold">{transfers.filter(t => t.status === "Approved").length}</div></CardContent></Card>
          </div>

          <ListFilters search={search} setSearch={setSearch} searchOnly searchPlaceholder="Search account name or type" />

          <Card>
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
                  items={pg.pageItems}
                  pagination={pg.paginationProps}
                  getKey={(a) => a.poultryCashAccountId}
                  primary={(a) => a.accountName}
                  secondary={(a) => (
                    <>
                      <span>{a.accountType}</span>
                      {a.isActive ? <Badge className="bg-green-100 text-green-700">Active</Badge> : <Badge variant="outline">Inactive</Badge>}
                    </>
                  )}
                  details={(a) => [
                    { label: "Type", value: a.accountType },
                    { label: "Opening", value: fmt(a.openingBalance) },
                    { label: "Current", value: <span className={a.currentBalance < 0 ? "text-rose-600 font-semibold" : "font-semibold"}>{fmt(a.currentBalance)}</span> },
                    { label: "Status", value: a.isActive ? "Active" : "Inactive" },
                  ]}
                  actions={(a) => (
                    <>
                      <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => router.push(`/poultry-cash-accounts/${a.poultryCashAccountId}`)}>
                        <Eye className="h-4 w-4 mr-1" /> View details
                      </Button>
                      <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openEdit(a)}>Edit</Button>
                      <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => setDeleteTarget(a)}><Trash2 className="h-4 w-4 mr-1" /> Delete</Button>
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
                          <TableHead>Status</TableHead>
                          <TableHead className="text-right">Actions</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {pg.pageItems.map((a) => (
                          <TableRow key={a.poultryCashAccountId}>
                            <TableCell className="font-medium">{a.accountName}</TableCell>
                            <TableCell>{a.accountType}</TableCell>
                            <TableCell className="text-right tabular-nums">{fmt(a.openingBalance)}</TableCell>
                            <TableCell className={`text-right tabular-nums font-semibold ${a.currentBalance < 0 ? "text-rose-600" : ""}`}>{fmt(a.currentBalance)}</TableCell>
                            <TableCell>{a.isActive ? <Badge className="bg-green-100 text-green-700">Active</Badge> : <Badge variant="outline">Inactive</Badge>}</TableCell>
                            <TableCell className="text-right">
                              <Button size="sm" variant="ghost" onClick={() => router.push(`/poultry-cash-accounts/${a.poultryCashAccountId}`)} title="View details"><Eye className="h-4 w-4" /></Button>
                              <Button size="sm" variant="ghost" onClick={() => viewTransactions(a)} title="Quick transactions">Txns</Button>
                              <Button size="sm" variant="ghost" onClick={() => openEdit(a)}>Edit</Button>
                              <Button size="sm" variant="ghost" onClick={() => setDeleteTarget(a)} title="Delete account"><Trash2 className="h-4 w-4 text-red-500" /></Button>
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

          {transfers.length > 0 && (
            <Card className="mt-4">
              <CardContent className="p-4">
                <div className="mb-2 font-medium text-slate-700">Recent transfers</div>
                <MobileCardList
                  items={transfers.slice(0, 8)}
                  getKey={(t) => t.poultryCashTransferId}
                  primary={(t) => `${t.fromAccountName} → ${t.toAccountName}`}
                  secondary={(t) => (<><span>{t.transferDate.split("T")[0]}</span><Badge variant="outline">{t.status}</Badge></>)}
                  details={(t) => [
                    { label: "Date", value: t.transferDate.split("T")[0] },
                    { label: "From", value: t.fromAccountName },
                    { label: "To", value: t.toAccountName },
                    { label: "Amount", value: fmt(t.amount) },
                    { label: "Status", value: t.status },
                  ]}
                  actions={(t) => (
                    <>
                      {t.status === "Draft" && (
                        <>
                          <Button size="sm" variant="outline" className="flex-1 h-10 text-green-700 border-green-200" onClick={async () => { await approvePoultryCashTransfer(t.poultryCashTransferId); await load() }}>Approve</Button>
                          <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={async () => { await cancelPoultryCashTransfer(t.poultryCashTransferId); await load() }}>Cancel</Button>
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
                          <TableRow key={t.poultryCashTransferId}>
                            <TableCell>{t.transferDate.split("T")[0]}</TableCell>
                            <TableCell>{t.fromAccountName}</TableCell>
                            <TableCell>{t.toAccountName}</TableCell>
                            <TableCell className="text-right tabular-nums">{fmt(t.amount)}</TableCell>
                            <TableCell><Badge variant="outline">{t.status}</Badge></TableCell>
                            <TableCell className="text-right">
                              {t.status === "Draft" && <>
                                <Button size="sm" variant="ghost" onClick={async () => { await approvePoultryCashTransfer(t.poultryCashTransferId); await load() }}>Approve</Button>
                                <Button size="sm" variant="ghost" onClick={async () => { await cancelPoultryCashTransfer(t.poultryCashTransferId); await load() }}>Cancel</Button>
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

      {/* Create/edit account */}
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

      {/* Transactions view */}
      <Dialog open={txDlg.open} onOpenChange={(v) => setTxDlg({ open: v, rows: [] })}>
        <DialogContent className="w-[95vw] max-w-[1600px] max-h-[90vh] overflow-y-auto">
          <DialogHeader><DialogTitle>Transactions — {txDlg.acc?.accountName}</DialogTitle></DialogHeader>
          {txDlg.rows.length === 0 ? <div className="p-4 text-slate-500">No transactions yet.</div> : (
            <div className="max-h-96 overflow-auto overflow-x-auto">
              <Table>
                <TableHeader><TableRow><TableHead>Date</TableHead><TableHead>Type</TableHead><TableHead>Source</TableHead><TableHead className="text-right">Amount</TableHead><TableHead>Description</TableHead></TableRow></TableHeader>
                <TableBody>
                  {txDlg.rows.map((r) => (
                    <TableRow key={r.poultryCashTransactionId}>
                      <TableCell>{r.transactionDate.split("T")[0]}</TableCell>
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

      {/* Transfer */}
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
                <Select value={String(xferForm.fromPoultryCashAccountId)} onValueChange={(v) => setXferForm({ ...xferForm, fromPoultryCashAccountId: Number(v) })}>
                  <SelectTrigger><SelectValue placeholder="From account" /></SelectTrigger>
                  <SelectContent>{accounts.filter(a => a.isActive).map(a => <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>{a.accountName}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
              <FormField label="To">
                <Select value={String(xferForm.toPoultryCashAccountId)} onValueChange={(v) => setXferForm({ ...xferForm, toPoultryCashAccountId: Number(v) })}>
                  <SelectTrigger><SelectValue placeholder="To account" /></SelectTrigger>
                  <SelectContent>{accounts.filter(a => a.isActive).map(a => <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>{a.accountName}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
            </FormSection>

            <FormSection title="Amount" color="amber" columns={1}>
              <FormField label="Amount">
                <NumberInput min={0.01} step="0.01" value={xferForm.amount} onChange={(e) => setXferForm({ ...xferForm, amount: Number(e.target.value) || 0 })} />
              </FormField>
              {/* Its own vocabulary, not the adjustment one: a transfer moves
                  money between the company's own accounts, so shortage/overage
                  would be a miscategorisation waiting to happen. */}
              <FormField label="Reason">
                <Select
                  value={xferForm.notes}
                  onValueChange={(v) => setXferForm({ ...xferForm, notes: v, notesOther: "" })}
                >
                  <SelectTrigger><SelectValue placeholder="Why is the money moving?" /></SelectTrigger>
                  <SelectContent>
                    {POULTRY_CASH_TRANSFER_REASONS.map((r) => (
                      <SelectItem key={r.value} value={r.value}>{r.label}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </FormField>
              {xferForm.notes === "Other" && (
                <FormField label="Say what happened *">
                  <Input
                    autoFocus
                    value={xferForm.notesOther}
                    onChange={(e) => setXferForm({ ...xferForm, notesOther: e.target.value })}
                    placeholder="e.g. Moved to the depot safe overnight"
                  />
                </FormField>
              )}
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
