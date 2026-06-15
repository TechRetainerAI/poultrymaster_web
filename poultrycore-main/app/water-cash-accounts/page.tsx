"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Badge } from "@/components/ui/badge"
import { Switch } from "@/components/ui/switch"
import { Plus, Pencil, Loader2, Wallet, RefreshCw, ArrowLeftRight, Eye } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterCashAccounts, createWaterCashAccount, updateWaterCashAccount, reconcileWaterCashBalances,
  listWaterCashTransactions, listWaterCashTransfers, createWaterCashTransfer, approveWaterCashTransfer, cancelWaterCashTransfer,
  type WaterCashAccount, type WaterCashTransaction, type WaterCashTransfer,
} from "@/lib/api/water"

const ACCOUNT_TYPES = ["FactoryCashBox", "OwnerCash", "MoMoWallet", "BankAccount", "DriverCash", "PettyCash", "Other"]

export default function WaterCashAccountsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [accounts, setAccounts] = useState<WaterCashAccount[]>([])
  const [transfers, setTransfers] = useState<WaterCashTransfer[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [loading, setLoading] = useState(true)

  const visibleAccounts = useMemo(
    () => filterByDateAndSearch(accounts, {
      search, dateFrom, dateTo,
      searchKeys: ["accountName", "accountType"],
    }),
    [accounts, search, dateFrom, dateTo],
  )

  const [open, setOpen] = useState(false)
  const [editId, setEditId] = useState<number | null>(null)
  const [form, setForm] = useState({ accountName: "", accountType: "FactoryCashBox", openingBalance: 0, allowNegativeBalance: false, notes: "", isActive: true })
  const [saving, setSaving] = useState(false)

  const [txDlg, setTxDlg] = useState<{ open: boolean; acc?: WaterCashAccount; rows: WaterCashTransaction[] }>({ open: false, rows: [] })
  const [xferDlg, setXferDlg] = useState(false)
  const [xferForm, setXferForm] = useState({ fromWaterCashAccountId: 0, toWaterCashAccountId: 0, amount: 0, notes: "" })

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const [accs, xfers] = await Promise.all([listWaterCashAccounts(), listWaterCashTransfers()])
      setAccounts(accs); setTransfers(xfers)
    } catch (e: any) { toast({ title: "Could not load cash accounts", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openNew() {
    setEditId(null)
    setForm({ accountName: "", accountType: "FactoryCashBox", openingBalance: 0, allowNegativeBalance: false, notes: "", isActive: true })
    setOpen(true)
  }
  function openEdit(a: WaterCashAccount) {
    setEditId(a.waterCashAccountId)
    setForm({ accountName: a.accountName, accountType: a.accountType, openingBalance: a.openingBalance, allowNegativeBalance: a.allowNegativeBalance, notes: a.notes ?? "", isActive: a.isActive })
    setOpen(true)
  }

  async function save() {
    if (!form.accountName.trim()) return toast({ title: "Name required", variant: "destructive" })
    setSaving(true)
    try {
      if (editId) {
        await updateWaterCashAccount(editId, { accountName: form.accountName, accountType: form.accountType, allowNegativeBalance: form.allowNegativeBalance, isActive: form.isActive, notes: form.notes })
        toast({ title: "Account updated" })
      } else {
        await createWaterCashAccount({ accountName: form.accountName, accountType: form.accountType, openingBalance: form.openingBalance, allowNegativeBalance: form.allowNegativeBalance, notes: form.notes })
        toast({ title: "Account created" })
      }
      setOpen(false); await load()
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function reconcile() {
    try { await reconcileWaterCashBalances(); toast({ title: "Balances reconciled" }); await load() }
    catch (e: any) { toast({ title: "Reconcile failed", description: e?.message, variant: "destructive" }) }
  }

  async function viewTransactions(acc: WaterCashAccount) {
    setTxDlg({ open: true, acc, rows: [] })
    try {
      const rows = await listWaterCashTransactions({ cashAccountId: acc.waterCashAccountId })
      setTxDlg({ open: true, acc, rows })
    } catch (e: any) { toast({ title: "Failed to load transactions", description: e?.message, variant: "destructive" }) }
  }

  async function saveTransfer() {
    if (xferForm.fromWaterCashAccountId === xferForm.toWaterCashAccountId) return toast({ title: "From and To must differ", variant: "destructive" })
    if (xferForm.amount <= 0) return toast({ title: "Amount required", variant: "destructive" })
    try {
      const { waterCashTransferId } = await createWaterCashTransfer(xferForm)
      await approveWaterCashTransfer(waterCashTransferId)
      toast({ title: "Transfer approved" })
      setXferDlg(false); setXferForm({ fromWaterCashAccountId: 0, toWaterCashAccountId: 0, amount: 0, notes: "" })
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
              <Wallet className="h-6 w-6 text-sky-600" /> Cash accounts
            </h1>
            {/* Buttons fill the row and wrap on mobile so "New account" is never
                clipped off-screen; natural-width and right-aligned from sm:. */}
            <div className="flex flex-wrap gap-2 w-full sm:w-auto">
              <Button variant="outline" className="flex-1 sm:flex-none whitespace-nowrap" onClick={reconcile}><RefreshCw className="h-4 w-4 mr-1" /> Reconcile</Button>
              <Button variant="outline" className="flex-1 sm:flex-none whitespace-nowrap" onClick={() => setXferDlg(true)}><ArrowLeftRight className="h-4 w-4 mr-1" /> Transfer</Button>
              <Button className="flex-1 sm:flex-none whitespace-nowrap" onClick={openNew}><Plus className="h-4 w-4 mr-1" /> New account</Button>
            </div>
          </div>

          <div className="mb-3 grid grid-cols-2 md:grid-cols-4 gap-3">
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Total cash at hand</div><div className="text-xl font-semibold tabular-nums">{totalCash.toFixed(2)}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Active accounts</div><div className="text-xl font-semibold">{accounts.filter(a => a.isActive).length}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Pending transfers</div><div className="text-xl font-semibold">{transfers.filter(t => t.status === "Draft").length}</div></CardContent></Card>
            <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Approved transfers</div><div className="text-xl font-semibold">{transfers.filter(t => t.status === "Approved").length}</div></CardContent></Card>
          </div>

          <ListFilters
            search={search} setSearch={setSearch}
            searchOnly
            searchPlaceholder="Search account name or type"
          />

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : accounts.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No cash accounts. Use Setup to seed defaults or create one above.</div>
              ) : (
                <MobileCardList
                  items={visibleAccounts}
                  getKey={(a) => a.waterCashAccountId}
                  primary={(a) => a.accountName}
                  secondary={(a) => (
                    <>
                      <span>{a.accountType}</span>
                      {a.isActive ? <Badge className="bg-green-100 text-green-700">Active</Badge> : <Badge variant="outline">Inactive</Badge>}
                    </>
                  )}
                  details={(a) => [
                    { label: "Type", value: a.accountType },
                    { label: "Opening", value: a.openingBalance.toFixed(2) },
                    { label: "Current", value: <span className={a.currentBalance < 0 ? "text-rose-600 font-semibold" : "font-semibold"}>{a.currentBalance.toFixed(2)}</span> },
                    { label: "Status", value: a.isActive ? "Active" : "Inactive" },
                  ]}
                  actions={(a) => (
                    <>
                      <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => router.push(`/water-cash-accounts/${a.waterCashAccountId}`)}>
                        <Eye className="h-4 w-4 mr-1" /> View details
                      </Button>
                      <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openEdit(a)}>Edit</Button>
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
                        {visibleAccounts.map((a) => (
                          <TableRow key={a.waterCashAccountId}>
                            <TableCell className="font-medium">{a.accountName}</TableCell>
                            <TableCell>{a.accountType}</TableCell>
                            <TableCell className="text-right tabular-nums">{a.openingBalance.toFixed(2)}</TableCell>
                            <TableCell className={`text-right tabular-nums font-semibold ${a.currentBalance < 0 ? "text-rose-600" : ""}`}>{a.currentBalance.toFixed(2)}</TableCell>
                            <TableCell>{a.isActive ? <Badge className="bg-green-100 text-green-700">Active</Badge> : <Badge variant="outline">Inactive</Badge>}</TableCell>
                            <TableCell className="text-right">
                              <Button size="sm" variant="ghost" onClick={() => router.push(`/water-cash-accounts/${a.waterCashAccountId}`)} title="View details"><Eye className="h-4 w-4" /></Button>
                              <Button size="sm" variant="ghost" onClick={() => openEdit(a)}>Edit</Button>
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
                  getKey={(t) => t.waterCashTransferId}
                  primary={(t) => `${t.fromAccountName} → ${t.toAccountName}`}
                  secondary={(t) => (
                    <>
                      <span>{t.transferDate.split("T")[0]}</span>
                      <Badge variant="outline">{t.status}</Badge>
                    </>
                  )}
                  details={(t) => [
                    { label: "Date", value: t.transferDate.split("T")[0] },
                    { label: "From", value: t.fromAccountName },
                    { label: "To", value: t.toAccountName },
                    { label: "Amount", value: t.amount.toFixed(2) },
                    { label: "Status", value: t.status },
                  ]}
                  actions={(t) => (
                    <>
                      {t.status === "Draft" && (
                        <>
                          <Button size="sm" variant="outline" className="flex-1 h-10 text-green-700 border-green-200" onClick={async () => { await approveWaterCashTransfer(t.waterCashTransferId); await load() }}>Approve</Button>
                          <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={async () => { await cancelWaterCashTransfer(t.waterCashTransferId); await load() }}>Cancel</Button>
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
                          <TableRow key={t.waterCashTransferId}>
                            <TableCell>{t.transferDate.split("T")[0]}</TableCell>
                            <TableCell>{t.fromAccountName}</TableCell>
                            <TableCell>{t.toAccountName}</TableCell>
                            <TableCell className="text-right tabular-nums">{t.amount.toFixed(2)}</TableCell>
                            <TableCell><Badge variant="outline">{t.status}</Badge></TableCell>
                            <TableCell className="text-right">
                              {t.status === "Draft" && <>
                                <Button size="sm" variant="ghost" onClick={async () => { await approveWaterCashTransfer(t.waterCashTransferId); await load() }}>Approve</Button>
                                <Button size="sm" variant="ghost" onClick={async () => { await cancelWaterCashTransfer(t.waterCashTransferId); await load() }}>Cancel</Button>
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
                    <TableRow key={r.waterCashTransactionId}>
                      <TableCell>{r.transactionDate.split("T")[0]}</TableCell>
                      <TableCell>{r.transactionType}</TableCell>
                      <TableCell>{r.sourceType ?? "—"}</TableCell>
                      <TableCell className={`text-right tabular-nums ${r.amount < 0 ? "text-rose-600" : "text-green-700"}`}>{r.amount.toFixed(2)}</TableCell>
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
                <Select value={String(xferForm.fromWaterCashAccountId)} onValueChange={(v) => setXferForm({ ...xferForm, fromWaterCashAccountId: Number(v) })}>
                  <SelectTrigger><SelectValue placeholder="From account" /></SelectTrigger>
                  <SelectContent>{accounts.filter(a => a.isActive).map(a => <SelectItem key={a.waterCashAccountId} value={String(a.waterCashAccountId)}>{a.accountName}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
              <FormField label="To">
                <Select value={String(xferForm.toWaterCashAccountId)} onValueChange={(v) => setXferForm({ ...xferForm, toWaterCashAccountId: Number(v) })}>
                  <SelectTrigger><SelectValue placeholder="To account" /></SelectTrigger>
                  <SelectContent>{accounts.filter(a => a.isActive).map(a => <SelectItem key={a.waterCashAccountId} value={String(a.waterCashAccountId)}>{a.accountName}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
            </FormSection>

            <FormSection title="Amount" color="amber" columns={1}>
              <FormField label="Amount">
                <NumberInput min={0.01} step="0.01" value={xferForm.amount} onChange={(e) => setXferForm({ ...xferForm, amount: Number(e.target.value) || 0 })} />
              </FormField>
              <FormField label="Notes">
                <Input value={xferForm.notes} onChange={(e) => setXferForm({ ...xferForm, notes: e.target.value })} />
              </FormField>
            </FormSection>

            <div className="flex gap-3 justify-end pt-2">
              <Button type="button" onClick={() => setXferDlg(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
              <Button onClick={saveTransfer}>Create &amp; approve</Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}
