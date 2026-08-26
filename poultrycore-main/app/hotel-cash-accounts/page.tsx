"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { Loader2, Wallet, Plus, ArrowUpRight, ArrowDownLeft, History, TrendingUp, TrendingDown, Trash2, Link2, Unlink } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listHotelCashAccounts, createHotelCashAccount, deleteHotelCashAccount, updateCashAccountPurpose, listCashTransactions, type HotelCashAccount, type HotelCashTransaction } from "@/lib/api/hotel"

export default function HotelCashAccountsPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [items, setItems] = useState<HotelCashAccount[]>([]); const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false); const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({ accountName: "", accountType: "Cash", openingBalance: 0, purpose: "" as string })

  // Transaction history
  const [txnDialogOpen, setTxnDialogOpen] = useState(false)
  const [selectedAccount, setSelectedAccount] = useState<any>(null)
  const [transactions, setTransactions] = useState<HotelCashTransaction[]>([])
  const [txnLoading, setTxnLoading] = useState(false)

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])
  async function load() { setLoading(true); try { setItems(await listHotelCashAccounts()) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setLoading(false) } }

  async function handleSave() {
    if (!form.accountName.trim()) { toast({ title: "Name required", variant: "destructive" }); return }
    setSaving(true)
    try { await createHotelCashAccount({ ...form, purpose: form.purpose || null }); toast({ title: "Account created" }); setDialogOpen(false); await load() }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setSaving(false) }
  }

  async function handleDelete(account: any, e: React.MouseEvent) {
    e.stopPropagation()
    const id = account.hotelCashAccountId ?? account.hotelcashaccountid
    const name = account.accountName ?? account.accountname
    if (!confirm(`Delete "${name}"? This cannot be undone.`)) return
    try {
      await deleteHotelCashAccount(id)
      toast({ title: "Account deleted" })
      await load()
    } catch (err: any) { toast({ title: "Cannot delete", description: err?.message, variant: "destructive" }) }
  }

  async function openTransactions(account: any) {
    const acctId = account.hotelCashAccountId ?? account.hotelcashaccountid
    setSelectedAccount(account)
    setTxnDialogOpen(true)
    setTxnLoading(true)
    try {
      const txns = await listCashTransactions(acctId)
      setTransactions(txns)
    } catch (e: any) {
      toast({ title: "Failed to load transactions", description: e?.message, variant: "destructive" })
    } finally { setTxnLoading(false) }
  }

  const totalBalance = items.reduce((s, a: any) => s + Number(a.currentBalance ?? a.currentbalance ?? 0), 0)
  const totalCredits = transactions.filter(t => t.txntype === "Credit").reduce((s, t) => s + Number(t.amount), 0)
  const totalDebits = transactions.filter(t => t.txntype === "Debit").reduce((s, t) => s + Number(t.amount), 0)

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3">
            <Wallet className="h-6 w-6 text-violet-600" />
            <h1 className="text-2xl font-bold">Cash Accounts</h1>
            <Badge variant="outline" className="bg-violet-50 text-violet-700 text-sm font-semibold">{totalBalance.toFixed(2)} Total</Badge>
          </div>
          <Button onClick={() => { setForm({ accountName: "", accountType: "Cash", openingBalance: 0, purpose: "" }); setDialogOpen(true) }} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> Add Account</Button>
        </div>

        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {items.map((a: any) => {
              const balance = Number(a.currentBalance ?? a.currentbalance ?? 0)
              const purpose = a.purpose ?? null
              const acctId = a.hotelCashAccountId ?? a.hotelcashaccountid
              return (
                <Card key={acctId} className="hover:shadow-md transition-shadow">
                  <CardContent className="p-4 space-y-2">
                    <div className="flex items-center justify-between">
                      <div className="font-semibold text-lg cursor-pointer" onClick={() => openTransactions(a)}>{a.accountName ?? a.accountname}</div>
                      <div className="flex items-center gap-1">
                        <Button variant="ghost" size="icon" className="h-7 w-7 text-red-400 hover:text-red-600" onClick={(e) => handleDelete(a, e)} title="Delete account"><Trash2 className="h-3.5 w-3.5" /></Button>
                        <Button variant="ghost" size="icon" className="h-7 w-7 text-violet-400 hover:text-violet-600" onClick={() => openTransactions(a)} title="View transactions"><History className="h-3.5 w-3.5" /></Button>
                      </div>
                    </div>
                    <div className="flex items-center gap-2">
                      <Badge variant="outline" className="text-xs">{a.accountType ?? a.accounttype}</Badge>
                    </div>
                    <div className={`text-2xl font-bold ${balance >= 0 ? "text-emerald-700" : "text-red-700"}`}>{balance.toFixed(2)}</div>
                    <div className="text-xs text-slate-400">Opening: {Number(a.openingBalance ?? a.openingbalance ?? 0).toFixed(2)}</div>

                    {/* Link / Unlink purpose */}
                    <div className="pt-1 border-t">
                      <div className="flex items-center gap-2">
                        {purpose ? <Link2 className="h-3.5 w-3.5 text-violet-600 shrink-0" /> : <Unlink className="h-3.5 w-3.5 text-slate-400 shrink-0" />}
                        <Select value={purpose ?? "__none__"} onValueChange={async (v) => {
                          const newPurpose = v === "__none__" ? null : v
                          try {
                            await updateCashAccountPurpose(acctId, newPurpose)
                            toast({ title: newPurpose ? `Linked to ${newPurpose}` : "Unlinked" })
                            await load()
                          } catch (err: any) { toast({ title: "Failed", description: err?.message, variant: "destructive" }) }
                        }}>
                          <SelectTrigger className="h-8 text-xs">
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value="__none__">No link (General)</SelectItem>
                            <SelectItem value="FrontDesk">Front Desk — guest payments in</SelectItem>
                            <SelectItem value="Expenses">Expenses — money out</SelectItem>
                            <SelectItem value="POS">POS / Restaurant — orders in</SelectItem>
                            <SelectItem value="Payroll">Payroll — salaries out</SelectItem>
                          </SelectContent>
                        </Select>
                      </div>
                    </div>
                  </CardContent>
                </Card>
              )
            })}
            {items.length === 0 && <div className="col-span-full text-center py-12 text-slate-400">No cash accounts. Add one to track your hotel finances.</div>}
          </div>
        )}

        {/* Create Account Dialog */}
        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}><DialogContent><DialogHeader><DialogTitle>Add Cash Account</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div><Label>Account Name *</Label><Input value={form.accountName} onChange={(e) => setForm({...form, accountName: e.target.value})} placeholder="e.g. Front Desk Cash" /></div>
            <div><Label>Type</Label><Select value={form.accountType} onValueChange={(v) => setForm({...form, accountType: v})}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent><SelectItem value="Cash">Cash</SelectItem><SelectItem value="Bank">Bank</SelectItem><SelectItem value="MobileMoney">Mobile Money</SelectItem></SelectContent></Select></div>
            <div>
              <Label>Link To (Purpose)</Label>
              <Select value={form.purpose || "__none__"} onValueChange={(v) => setForm({...form, purpose: v === "__none__" ? "" : v})}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="__none__">No link (General)</SelectItem>
                  <SelectItem value="FrontDesk">Front Desk — receives guest payments (Credits)</SelectItem>
                  <SelectItem value="Expenses">Expenses — money goes out for expenses (Debits)</SelectItem>
                  <SelectItem value="POS">POS / Restaurant — receives order payments (Credits)</SelectItem>
                  <SelectItem value="Payroll">Payroll — money goes out for salaries (Debits)</SelectItem>
                </SelectContent>
              </Select>
              <p className="text-xs text-slate-400 mt-1">Linking an account auto-routes money in/out when transactions happen</p>
            </div>
            <div><Label>Opening Balance</Label><Input type="number" step="0.01" value={form.openingBalance} onChange={(e) => setForm({...form, openingBalance: Number(e.target.value)})} /></div>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setDialogOpen(false)}>Cancel</Button><Button onClick={handleSave} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}Create</Button></DialogFooter>
        </DialogContent></Dialog>

        {/* Transaction History Dialog */}
        <Dialog open={txnDialogOpen} onOpenChange={setTxnDialogOpen}>
          <DialogContent className="max-w-3xl max-h-[80vh] overflow-hidden flex flex-col">
            <DialogHeader>
              <DialogTitle className="flex items-center gap-2">
                <History className="h-5 w-5 text-violet-600" />
                {selectedAccount?.accountName ?? selectedAccount?.accountname} — Transactions
              </DialogTitle>
            </DialogHeader>

            {/* Summary Cards */}
            {!txnLoading && transactions.length > 0 && (
              <div className="grid grid-cols-3 gap-3 mb-2">
                <div className="p-3 bg-emerald-50 rounded-lg text-center">
                  <div className="flex items-center justify-center gap-1 text-xs text-emerald-600 mb-1"><TrendingUp className="h-3 w-3" /> Total In</div>
                  <div className="text-lg font-bold text-emerald-700">{totalCredits.toFixed(2)}</div>
                </div>
                <div className="p-3 bg-red-50 rounded-lg text-center">
                  <div className="flex items-center justify-center gap-1 text-xs text-red-600 mb-1"><TrendingDown className="h-3 w-3" /> Total Out</div>
                  <div className="text-lg font-bold text-red-700">{totalDebits.toFixed(2)}</div>
                </div>
                <div className="p-3 bg-violet-50 rounded-lg text-center">
                  <div className="text-xs text-violet-600 mb-1">Current Balance</div>
                  <div className="text-lg font-bold text-violet-700">{Number(selectedAccount?.currentBalance ?? selectedAccount?.currentbalance ?? 0).toFixed(2)}</div>
                </div>
              </div>
            )}

            <div className="flex-1 overflow-auto">
              {txnLoading ? (
                <div className="flex justify-center py-12"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div>
              ) : transactions.length === 0 ? (
                <div className="text-center py-12 text-slate-400">No transactions yet for this account.</div>
              ) : (
                <table className="w-full text-sm">
                  <thead className="bg-slate-50 border-b sticky top-0">
                    <tr>
                      <th className="text-left p-3">Date</th>
                      <th className="text-left p-3">Type</th>
                      <th className="text-left p-3">Description</th>
                      <th className="text-left p-3">Source</th>
                      <th className="text-left p-3">Reference</th>
                      <th className="text-right p-3">Amount</th>
                      <th className="text-right p-3">Balance</th>
                      <th className="text-left p-3">By</th>
                    </tr>
                  </thead>
                  <tbody>
                    {transactions.map((t, idx) => (
                      <tr key={t.hotelcashtxnid ?? idx} className="border-b hover:bg-slate-50">
                        <td className="p-3 text-xs">{t.txndate?.slice(0, 10)}</td>
                        <td className="p-3">
                          {t.txntype === "Credit" ? (
                            <Badge variant="outline" className="bg-emerald-100 text-emerald-700 text-xs"><ArrowDownLeft className="h-3 w-3 mr-1" />In</Badge>
                          ) : (
                            <Badge variant="outline" className="bg-red-100 text-red-700 text-xs"><ArrowUpRight className="h-3 w-3 mr-1" />Out</Badge>
                          )}
                        </td>
                        <td className="p-3 max-w-[200px] truncate" title={t.description ?? ""}>{t.description ?? "—"}</td>
                        <td className="p-3"><Badge variant="outline" className="text-xs">{t.sourcetype ?? "—"}</Badge></td>
                        <td className="p-3 font-mono text-xs">{t.reference ?? "—"}</td>
                        <td className={`p-3 text-right font-semibold ${t.txntype === "Credit" ? "text-emerald-700" : "text-red-700"}`}>
                          {t.txntype === "Credit" ? "+" : "-"}{Number(t.amount).toFixed(2)}
                        </td>
                        <td className="p-3 text-right text-slate-600">{Number(t.balanceafter).toFixed(2)}</td>
                        <td className="p-3 text-xs text-slate-500">{t.createdby ?? "System"}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </div>
          </DialogContent>
        </Dialog>
      </main></div></div>
  )
}
