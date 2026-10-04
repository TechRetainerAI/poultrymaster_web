"use client"

// Hotel Cash Account — Poultry's /poultry-cash-accounts page structure and
// wording, in violet, amounts in the company currency (useFmt).
//
// The table shows the stored balance ("Current") beside the one the ledger adds
// up to ("Calculated"): when they differ the cache has drifted, and Recalculate
// rebuilds it from the ledger without moving any money. Money only ever moves
// through a posting (transfer, adjustment, reconciliation) — migration 331.

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
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Badge } from "@/components/ui/badge"
import { Switch } from "@/components/ui/switch"
import { Plus, Pencil, Loader2, Wallet, RefreshCw, ArrowLeftRight, Eye, Trash2, Scale, Undo2, FileText } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cashByAccount, sourceTypeLabel } from "@/lib/cash/cash-flow"
import { RecordCashAdjustmentDialog } from "@/components/cash/record-cash-adjustment-dialog"
import { fmtDateTime } from "@/lib/utils/company-datetime"
import { listCashTransactions, type HotelCashTransaction } from "@/lib/api/hotel"
import {
  listHotelMoneyAccounts, getHotelCashAccountStatus, createHotelMoneyAccount, updateHotelMoneyAccount,
  recalculateHotelCashBalances, adjustHotelCashAccount, reverseHotelCashAdjustment,
  listHotelCashTransfers, recordHotelCashTransfer, hotelAccountTypeLabel,
  HOTEL_CASH_ACCOUNT_TYPES, HOTEL_CASH_PURPOSES, HOTEL_CASH_REASONS, HOTEL_CASH_TRANSFER_REASONS,
  type HotelMoneyAccount, type HotelCashAccountStatus, type HotelCashTransfer,
} from "@/lib/api/hotel-money"

const NO_PURPOSE = "__none__"

// Tinted summary tile, Poultry's StatCard.
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

const purposeLabel = (p?: string | null) =>
  HOTEL_CASH_PURPOSES.find((x) => x.value === p)?.label.split(" — ")[0] ?? null

export default function HotelCashAccountsPage() {
  const fmt = useFmt()
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [accounts, setAccounts] = useState<HotelMoneyAccount[]>([])
  const [transfers, setTransfers] = useState<HotelCashTransfer[]>([])
  const [status, setStatus] = useState<HotelCashAccountStatus[]>([])
  const [search, setSearch] = useState("")
  const [loading, setLoading] = useState(true)

  const visibleAccounts = useMemo(
    () => filterByDateAndSearch(accounts, { search, searchKeys: ["accountName", "accountType"] }),
    [accounts, search],
  )
  const pg = usePagination(visibleAccounts)

  const [open, setOpen] = useState(false)
  const [editId, setEditId] = useState<number | null>(null)
  const blankForm = { accountName: "", accountType: "FrontDeskCash", openingBalance: 0, allowNegativeBalance: false, notes: "", isActive: true, purpose: NO_PURPOSE }
  const [form, setForm] = useState(blankForm)
  const [saving, setSaving] = useState(false)

  const [deleteTarget, setDeleteTarget] = useState<HotelMoneyAccount | null>(null)
  const [txDlg, setTxDlg] = useState<{ open: boolean; acc?: HotelMoneyAccount; rows: HotelCashTransaction[] }>({ open: false, rows: [] })
  const [reverseAdj, setReverseAdj] = useState<number | null>(null)
  const [xferDlg, setXferDlg] = useState(false)
  const [adjustDlg, setAdjustDlg] = useState(false)
  const [xferForm, setXferForm] = useState({ fromId: 0, toId: 0, amount: 0, notes: "", notesOther: "" })

  useEffect(() => {
    if (!activeFarmType) return
    if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const [accs, xfers] = await Promise.all([listHotelMoneyAccounts(), listHotelCashTransfers()])
      setAccounts(accs); setTransfers(xfers)
      const st = await getHotelCashAccountStatus().catch(() => [])
      setStatus(st ?? [])
    } catch (e: any) { toast({ title: "Could not load cash accounts", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openNew() {
    setEditId(null)
    setForm(blankForm)
    setOpen(true)
  }
  function openEdit(a: HotelMoneyAccount) {
    setEditId(a.hotelCashAccountId)
    setForm({ accountName: a.accountName, accountType: a.accountType, openingBalance: a.openingBalance,
              allowNegativeBalance: a.allowNegativeBalance, notes: a.notes ?? "", isActive: a.isActive,
              purpose: a.purpose ?? NO_PURPOSE })
    setOpen(true)
  }

  async function save() {
    if (!form.accountName.trim()) return toast({ title: "Name required", variant: "destructive" })
    setSaving(true)
    const purpose = form.purpose === NO_PURPOSE ? null : form.purpose
    try {
      if (editId) {
        await updateHotelMoneyAccount(editId, { accountName: form.accountName.trim(), accountType: form.accountType,
          allowNegativeBalance: form.allowNegativeBalance, isActive: form.isActive, notes: form.notes, purpose })
        toast({ title: "Account updated" })
      } else {
        await createHotelMoneyAccount({ accountName: form.accountName.trim(), accountType: form.accountType,
          openingBalance: form.openingBalance, allowNegativeBalance: form.allowNegativeBalance, notes: form.notes, purpose })
        toast({ title: "Account created" })
      }
      setOpen(false); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  // One-click default account — every hotel should have a main cash box.
  async function createDefault() {
    const DEFAULT_NAME = "Main Cash Account"
    if (accounts.some((a) => a.accountName.trim().toLowerCase() === DEFAULT_NAME.toLowerCase())) {
      toast({ title: "Default account already exists", description: `"${DEFAULT_NAME}" is already set up.` })
      return
    }
    setSaving(true)
    try {
      await createHotelMoneyAccount({ accountName: DEFAULT_NAME, accountType: "CashBox", openingBalance: 0,
                                      allowNegativeBalance: false, notes: "Default cash account" })
      toast({ title: "Default account created", description: `"${DEFAULT_NAME}" is ready to use.` })
      await load()
    } catch (e: any) {
      toast({ title: "Could not create default account", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  async function reconcile() {
    try {
      const r = await recalculateHotelCashBalances()
      toast({ title: "Balances recalculated", description: `${r?.changed ?? 0} account(s) rebuilt from their transactions.` })
      await load()
    }
    catch (e: any) { toast({ title: "Recalculate failed", description: e?.message, variant: "destructive" }) }
  }

  // Remove = deactivate, as Poultry does: the history stays intact.
  async function performDelete(acc: HotelMoneyAccount) {
    await updateHotelMoneyAccount(acc.hotelCashAccountId, { accountName: acc.accountName, accountType: acc.accountType,
      allowNegativeBalance: acc.allowNegativeBalance, isActive: false, notes: acc.notes, purpose: acc.purpose })
    toast({ title: "Cash account removed" })
    await load()
  }

  async function viewTransactions(acc: HotelMoneyAccount) {
    setTxDlg({ open: true, acc, rows: [] })
    try {
      const rows = await listCashTransactions(acc.hotelCashAccountId)
      setTxDlg({ open: true, acc, rows })
    } catch (e: any) { toast({ title: "Failed to load transactions", description: e?.message, variant: "destructive" }) }
  }

  async function saveTransfer() {
    if (!xferForm.fromId || !xferForm.toId) return toast({ title: "Pick both accounts", variant: "destructive" })
    if (xferForm.fromId === xferForm.toId) return toast({ title: "From and To must differ", variant: "destructive" })
    if (xferForm.amount <= 0) return toast({ title: "Amount required", variant: "destructive" })
    if (xferForm.notes === "Other" && !xferForm.notesOther.trim()) {
      return toast({ title: "Say what happened", variant: "destructive" })
    }
    try {
      const notes = xferForm.notes === "Other" ? xferForm.notesOther.trim() : xferForm.notes
      await recordHotelCashTransfer({ fromHotelCashAccountId: xferForm.fromId, toHotelCashAccountId: xferForm.toId,
        amount: xferForm.amount, transferDate: null, referenceNumber: null, notes: notes || null })
      toast({ title: "Transfer approved" })
      setXferDlg(false)
      setXferForm({ fromId: 0, toId: 0, amount: 0, notes: "", notesOther: "" })
      await load()
    } catch (e: any) { toast({ title: "Transfer failed", description: e?.message, variant: "destructive" }) }
  }

  const statusById = useMemo(() => {
    const rows = cashByAccount((status ?? []).map((s) => ({
      accountId: s.hotelCashAccountId,
      accountName: s.accountName,
      accountType: s.accountType,
      isActive: s.isActive,
      currentBalance: s.currentBalance,
      ledgerBalance: s.ledgerBalance,
      cacheDrift: s.cacheDrift,
      lastReconciledAt: s.lastReconciledAt,
      daysSinceReconciled: s.daysSinceReconciled,
      unclearedCount: s.unclearedCount,
    })))
    return new Map(rows.map((r) => [r.accountId, r]))
  }, [status])

  // Sum the LEDGER, not the cache; the cache only when the status feed is unavailable.
  const totalCash = accounts.filter((a) => a.isActive).reduce(
    (s, a) => s + (statusById.get(a.hotelCashAccountId)?.ledgerBalance ?? a.currentBalance), 0)

  // Which adjustments in the open ledger have already been reversed.
  const reversedAdjustments = useMemo(
    () => new Set(txDlg.rows.filter((r) => r.sourcetype === "CashAdjustmentReversal").map((r) => r.sourceid)),
    [txDlg.rows],
  )

  const activeAccounts = accounts.filter((a) => a.isActive)

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <Wallet className="h-6 w-6 text-violet-600" /> Cash Account
            </h1>
            <div className="flex flex-wrap gap-2 w-full sm:w-auto">
              <Button variant="outline" className="flex-1 sm:flex-none whitespace-nowrap" onClick={() => setAdjustDlg(true)}><Scale className="h-4 w-4 mr-1" /> Record Cash Adjustment</Button>
              <Button variant="outline" className="flex-1 sm:flex-none whitespace-nowrap" onClick={reconcile}><RefreshCw className="h-4 w-4 mr-1" /> Recalculate</Button>
              <Button asChild variant="outline" className="flex-1 sm:flex-none whitespace-nowrap">
                <Link href="/hotel-cash-reconciliation"><Scale className="h-4 w-4 mr-1" /> Reconcile</Link>
              </Button>
              {/* Poultry's Cash Account Report button. The Hotel's nearest report is
                  its Cash Flow Report (money in/out of every account, running balances). */}
              <Button asChild variant="outline" className="flex-1 sm:flex-none whitespace-nowrap">
                <Link href="/hotel-reports/cash-flow-report"><FileText className="h-4 w-4 mr-1" /> Cash Account Report</Link>
              </Button>
              <Button variant="outline" className="flex-1 sm:flex-none whitespace-nowrap" onClick={() => setXferDlg(true)}><ArrowLeftRight className="h-4 w-4 mr-1" /> Transfer</Button>
              <Button variant="outline" className="flex-1 sm:flex-none whitespace-nowrap" onClick={createDefault} disabled={saving}><Wallet className="h-4 w-4 mr-1" /> Create default account</Button>
              <Button className="flex-1 sm:flex-none whitespace-nowrap bg-violet-600 hover:bg-violet-700" onClick={openNew}><Plus className="h-4 w-4 mr-1" /> New account</Button>
            </div>
          </div>

          <button
            type="button"
            onClick={() => router.push("/hotel-cash-flow")}
            className="mb-4 inline-flex items-center gap-1.5 text-sm font-medium text-violet-600 hover:text-violet-700 hover:underline"
          >
            <ArrowLeftRight className="h-4 w-4" /> See the whole company&apos;s cash flow →
          </button>

          <div className="mb-3 grid grid-cols-2 md:grid-cols-4 gap-3">
            <StatCard label="Total cash at hand" value={fmt(totalCash)} accent="violet" />
            <StatCard label="Active accounts" value={activeAccounts.length} accent="emerald" />
            <StatCard label="Reversed transfers" value={transfers.filter((t) => t.status === "Reversed").length} accent="amber" />
            <StatCard label="Approved transfers" value={transfers.filter((t) => t.status === "Approved").length} accent="blue" />
          </div>

          <ListFilters search={search} setSearch={setSearch} searchOnly searchPlaceholder="Search account name or type" />

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : accounts.length === 0 ? (
                <div className="p-8 text-center text-slate-500">
                  <p>No cash accounts yet.</p>
                  <Button className="mt-3 bg-violet-600 hover:bg-violet-700" onClick={createDefault} disabled={saving}><Wallet className="h-4 w-4 mr-1" /> Create default account</Button>
                </div>
              ) : (
                <MobileCardList
                  defaultOpen
                  striped
                  items={pg.pageItems}
                  pagination={{ ...pg.paginationProps, variant: "records" }}
                  getKey={(a) => a.hotelCashAccountId}
                  primary={(a) => a.accountName}
                  secondary={(a) => (
                    <>
                      <span>{hotelAccountTypeLabel(a.accountType)}</span>
                      {a.isActive ? <Badge className="bg-green-100 text-green-700">Active</Badge> : <Badge variant="outline">Inactive</Badge>}
                    </>
                  )}
                  highlights={(a) => [
                    { label: "Opening", value: fmt(a.openingBalance), accent: "blue" },
                    { label: "Current", value: fmt(a.currentBalance), accent: a.currentBalance < 0 ? "rose" : "emerald" },
                  ]}
                  details={(a) => [
                    { label: "Type", value: hotelAccountTypeLabel(a.accountType) },
                    { label: "Used for", value: purposeLabel(a.purpose) ?? "—" },
                    { label: "Calculated", value: statusById.get(a.hotelCashAccountId) ? fmt(statusById.get(a.hotelCashAccountId)!.ledgerBalance) : "—" },
                    { label: "Reconciled", value: statusById.get(a.hotelCashAccountId)?.attentionReason
                        ?? (statusById.get(a.hotelCashAccountId) ? `${statusById.get(a.hotelCashAccountId)!.daysSinceReconciled}d ago` : "—") },
                    { label: "Status", value: a.isActive ? "Active" : "Inactive" },
                  ]}
                  actions={(a) => (
                    <>
                      <Button size="sm" variant="outline" className="flex-1 h-10 bg-white" onClick={() => viewTransactions(a)}>
                        <Eye className="h-4 w-4 mr-1" /> View details
                      </Button>
                      <Button size="sm" variant="outline" className="flex-1 h-10 bg-white" onClick={() => router.push(`/hotel-cash-reconciliation?accountId=${a.hotelCashAccountId}`)}>Reconcile</Button>
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
                          <TableHead>Reconciled</TableHead>
                          <TableHead>Status</TableHead>
                          <TableHead className="text-right">Actions</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {pg.pageItems.map((a) => (
                          <TableRow key={a.hotelCashAccountId}>
                            <TableCell className="font-medium">
                              {a.accountName}
                              {purposeLabel(a.purpose) && (
                                <div className="text-[11px] font-normal text-violet-700">{purposeLabel(a.purpose)}</div>
                              )}
                            </TableCell>
                            <TableCell>{hotelAccountTypeLabel(a.accountType)}</TableCell>
                            <TableCell className="text-right tabular-nums">{fmt(a.openingBalance)}</TableCell>
                            <TableCell className={`text-right tabular-nums ${a.currentBalance < 0 ? "text-rose-600" : "text-slate-500"}`}>{fmt(a.currentBalance)}</TableCell>
                            <TableCell className="text-right tabular-nums font-semibold">
                              {(() => {
                                const s = statusById.get(a.hotelCashAccountId)
                                if (!s) return <span className="text-slate-400">—</span>
                                const drifted = Math.abs(s.cacheDrift) >= 0.01
                                return (
                                  <span className={s.ledgerBalance < 0 ? "text-rose-600" : undefined}>
                                    {fmt(s.ledgerBalance)}
                                    {drifted && (
                                      <span className="ml-1 text-[10px] font-normal text-amber-700"
                                            title={`Stored balance is ${fmt(Math.abs(s.cacheDrift))} away from this`}>
                                        drift
                                      </span>
                                    )}
                                  </span>
                                )
                              })()}
                            </TableCell>
                            <TableCell className="text-xs">
                              {(() => {
                                const s = statusById.get(a.hotelCashAccountId)
                                if (!s) return <span className="text-slate-400">—</span>
                                return s.needsAttention
                                  ? <span className="text-amber-700">{s.attentionReason}</span>
                                  : <span className="text-emerald-700">{s.daysSinceReconciled}d ago</span>
                              })()}
                            </TableCell>
                            <TableCell>{a.isActive ? <Badge className="bg-green-100 text-green-700">Active</Badge> : <Badge variant="outline">Inactive</Badge>}</TableCell>
                            <TableCell className="text-right whitespace-nowrap">
                              <Button size="sm" variant="ghost" onClick={() => viewTransactions(a)} title="View details"><Eye className="h-4 w-4" /></Button>
                              <Button size="sm" variant="ghost" onClick={() => router.push(`/hotel-cash-reconciliation?accountId=${a.hotelCashAccountId}`)} title="Reconcile this account">Reconcile</Button>
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
                <div className="mb-2 flex items-center justify-between gap-2">
                  <div className="font-medium text-slate-700">Recent transfers</div>
                  <Link href="/hotel-cash-transfers" className="text-xs text-violet-700 hover:underline">All transfers →</Link>
                </div>
                <MobileCardList
                  defaultOpen
                  items={transfers.slice(0, 8)}
                  getKey={(t) => t.hotelCashTransferId}
                  primary={(t) => `${t.fromAccountName} → ${t.toAccountName}`}
                  secondary={(t) => (<><span>{fmtDateTime(t.transferDate, t)}</span><Badge variant="outline">{t.status}</Badge></>)}
                  details={(t) => [
                    { label: "Date", value: fmtDateTime(t.transferDate, t) },
                    { label: "From", value: t.fromAccountName ?? "—" },
                    { label: "To", value: t.toAccountName ?? "—" },
                    { label: "Amount", value: fmt(t.amount) },
                    { label: "Status", value: t.status },
                  ]}
                  desktopTable={
                    <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow><TableHead>Date</TableHead><TableHead>From</TableHead><TableHead>To</TableHead><TableHead className="text-right">Amount</TableHead><TableHead>Status</TableHead></TableRow>
                      </TableHeader>
                      <TableBody>
                        {transfers.slice(0, 8).map((t) => (
                          <TableRow key={t.hotelCashTransferId}>
                            <TableCell>{fmtDateTime(t.transferDate, t)}</TableCell>
                            <TableCell>{t.fromAccountName}</TableCell>
                            <TableCell>{t.toAccountName}</TableCell>
                            <TableCell className="text-right tabular-nums">{fmt(t.amount)}</TableCell>
                            <TableCell><Badge variant="outline">{t.status}</Badge></TableCell>
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
        <DialogContent className="sm:max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              {editId ? <Pencil className="w-5 h-5 text-violet-600" /> : <Wallet className="w-5 h-5 text-violet-600" />}
              {editId ? "Edit account" : "New cash account"}
            </DialogTitle>
            <DialogDescription>Configure where cash flows into or out of</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormSection title="Identity" color="purple">
              <FormField label="Name *" full>
                <Input value={form.accountName} placeholder="e.g. Front Desk Cash" onChange={(e) => setForm({ ...form, accountName: e.target.value })} />
              </FormField>
              <FormField label="Type" full={!!editId}>
                <Select value={form.accountType} onValueChange={(v) => setForm({ ...form, accountType: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {HOTEL_CASH_ACCOUNT_TYPES.map((t) => <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>)}
                    {form.accountType && !HOTEL_CASH_ACCOUNT_TYPES.some((t) => t.value === form.accountType) && (
                      <SelectItem value={form.accountType}>{form.accountType}</SelectItem>
                    )}
                  </SelectContent>
                </Select>
              </FormField>
              {!editId && (
                <FormField label="Opening balance">
                  <NumberInput step="0.01" value={form.openingBalance} onChange={(e) => setForm({ ...form, openingBalance: Number(e.target.value) || 0 })} />
                </FormField>
              )}
              <FormField label="Used for" full hint="Linking an account auto-routes money in/out when transactions happen">
                <Select value={form.purpose} onValueChange={(v) => setForm({ ...form, purpose: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value={NO_PURPOSE}>No link (General)</SelectItem>
                    {HOTEL_CASH_PURPOSES.map((p) => <SelectItem key={p.value} value={p.value}>{p.label}</SelectItem>)}
                  </SelectContent>
                </Select>
              </FormField>
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
              <Button onClick={save} disabled={saving} className="bg-violet-600 hover:bg-violet-700">
                {saving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : "Save"}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Transactions view */}
      <Dialog open={txDlg.open} onOpenChange={(v) => setTxDlg({ open: v, rows: [] })}>
        <DialogContent className="w-[95vw] sm:max-w-5xl max-h-[90vh] overflow-y-auto">
          <DialogHeader><DialogTitle>Transactions — {txDlg.acc?.accountName}</DialogTitle></DialogHeader>
          {txDlg.rows.length === 0 ? <div className="p-4 text-slate-500">No transactions yet.</div> : (
            <div className="max-h-96 overflow-auto overflow-x-auto">
              <Table>
                <TableHeader><TableRow><TableHead>Date</TableHead><TableHead>Type</TableHead><TableHead>Source</TableHead><TableHead className="text-right">Amount</TableHead><TableHead className="text-right">Balance</TableHead><TableHead>Description</TableHead><TableHead /></TableRow></TableHeader>
                <TableBody>
                  {txDlg.rows.map((r) => {
                    const signed = r.txntype === "Credit" ? Number(r.amount) : -Number(r.amount)
                    return (
                      <TableRow key={r.hotelcashtxnid}>
                        <TableCell className="whitespace-nowrap">{fmtDateTime(r.txndate, { createdAt: r.createdat })}</TableCell>
                        <TableCell>{r.txntype === "Credit" ? "Money in" : "Money out"}</TableCell>
                        <TableCell>{sourceTypeLabel(r.sourcetype)}</TableCell>
                        <TableCell className={`text-right tabular-nums ${signed < 0 ? "text-rose-600" : "text-green-700"}`}>{fmt(signed)}</TableCell>
                        <TableCell className="text-right tabular-nums text-slate-500">{fmt(Number(r.balanceafter))}</TableCell>
                        <TableCell className="max-w-sm whitespace-normal break-words align-top">{r.description ?? "—"}</TableCell>
                        <TableCell className="text-right">
                          {r.sourcetype === "CashAdjustment" && r.sourceid != null && !reversedAdjustments.has(r.sourceid) && (
                            <Button size="sm" variant="outline" onClick={() => setReverseAdj(r.sourceid!)}>
                              <Undo2 className="h-3 w-3 mr-1" /> Reverse
                            </Button>
                          )}
                        </TableCell>
                      </TableRow>
                    )
                  })}
                </TableBody>
              </Table>
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* Transfer */}
      <Dialog open={xferDlg} onOpenChange={setXferDlg}>
        <DialogContent className="sm:max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <ArrowLeftRight className="w-5 h-5 text-violet-600" /> Cash transfer
            </DialogTitle>
            <DialogDescription>Move funds between two cash accounts</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormSection title="Accounts" color="purple">
              <FormField label="From">
                <Select value={xferForm.fromId ? String(xferForm.fromId) : ""} onValueChange={(v) => setXferForm({ ...xferForm, fromId: Number(v) })}>
                  <SelectTrigger><SelectValue placeholder="From account" /></SelectTrigger>
                  <SelectContent>{activeAccounts.map((a) => <SelectItem key={a.hotelCashAccountId} value={String(a.hotelCashAccountId)}>{a.accountName}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
              <FormField label="To">
                <Select value={xferForm.toId ? String(xferForm.toId) : ""} onValueChange={(v) => setXferForm({ ...xferForm, toId: Number(v) })}>
                  <SelectTrigger><SelectValue placeholder="To account" /></SelectTrigger>
                  <SelectContent>{activeAccounts.map((a) => <SelectItem key={a.hotelCashAccountId} value={String(a.hotelCashAccountId)}>{a.accountName}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
            </FormSection>

            <FormSection title="Amount" color="amber" columns={1}>
              <FormField label="Amount">
                <NumberInput min={0.01} step="0.01" value={xferForm.amount} onChange={(e) => setXferForm({ ...xferForm, amount: Number(e.target.value) || 0 })} />
              </FormField>
              <FormField label="Reason">
                <Select value={xferForm.notes} onValueChange={(v) => setXferForm({ ...xferForm, notes: v, notesOther: "" })}>
                  <SelectTrigger><SelectValue placeholder="Why is the money moving?" /></SelectTrigger>
                  <SelectContent>
                    {HOTEL_CASH_TRANSFER_REASONS.map((r) => (
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
                    placeholder="e.g. Moved to the back-office safe overnight"
                  />
                </FormField>
              )}
            </FormSection>

            <div className="flex gap-3 justify-end pt-2">
              <Button type="button" onClick={() => setXferDlg(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
              <Button onClick={saveTransfer} className="bg-violet-600 hover:bg-violet-700">Record transfer</Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      <RecordCashAdjustmentDialog
        open={adjustDlg}
        onOpenChange={setAdjustDlg}
        accent="violet"
        accounts={accounts.map((a) => ({
          accountId: a.hotelCashAccountId,
          accountName: a.accountName,
          accountType: a.accountType,
          isActive: a.isActive,
        }))}
        reasons={HOTEL_CASH_REASONS}
        fmtMoney={fmt}
        reconcileHref="/hotel-cash-reconciliation"
        onSubmit={async ({ accountId, amount, reason }) => {
          await adjustHotelCashAccount(accountId, { amount, reason })
        }}
        onDone={() => { void load() }}
      />

      <PromptDialog
        open={reverseAdj != null}
        onOpenChange={(o) => { if (!o) setReverseAdj(null) }}
        title="Reverse this adjustment?"
        description="An opposite transaction is posted and the original is kept."
        label="Reason for reversal"
        placeholder="Why is this adjustment being reversed?"
        confirmLabel="Reverse"
        confirmVariant="destructive"
        onSubmit={async (reason: string) => {
          if (reverseAdj == null) return
          try {
            await reverseHotelCashAdjustment(reverseAdj, reason)
            toast({ title: "Adjustment reversed" })
            setReverseAdj(null)
            if (txDlg.acc) await viewTransactions(txDlg.acc)
            await load()
          } catch (e: any) {
            toast({ title: "Couldn't reverse", description: e?.message, variant: "destructive" })
          }
        }}
      />

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
