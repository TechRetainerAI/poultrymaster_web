"use client"

import { useEffect, useMemo, useState } from "react"
import { useParams, useRouter } from "next/navigation"
import Link from "next/link"
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
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Badge } from "@/components/ui/badge"
import { ArrowLeft, Loader2, Wallet, RefreshCw, Scale } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  getWaterCashAccount, listWaterCashTransactions, adjustWaterCashAccount, reconcileWaterCashBalances,
  type WaterCashAccount, type WaterCashTransaction,
} from "@/lib/api/water"

export default function WaterCashAccountDetailPage() {
  const router = useRouter()
  const params = useParams<{ id: string }>()
  const id = Number(params?.id)
  const { toast } = useToast()
  const gh = useFmt()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [account, setAccount] = useState<WaterCashAccount | null>(null)
  const [rows, setRows] = useState<WaterCashTransaction[]>([])
  const [loading, setLoading] = useState(true)

  const [adjOpen, setAdjOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [adj, setAdj] = useState<{ direction: "in" | "out"; amount: number; reason: string }>({ direction: "in", amount: 0, reason: "" })

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    if (id) void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, id])

  async function load() {
    setLoading(true)
    try {
      const [acc, tx] = await Promise.all([
        getWaterCashAccount(id),
        listWaterCashTransactions({ cashAccountId: id }),
      ])
      setAccount(acc); setRows(tx)
    } catch (e: any) { toast({ title: "Could not load account", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  // Ledger oldest→newest with a running balance from the opening balance, then
  // shown newest-first so the latest movement is on top.
  const ledger = useMemo(() => {
    const opening = account?.openingBalance ?? 0
    const asc = [...rows].sort((a, b) => {
      const d = new Date(a.transactionDate).getTime() - new Date(b.transactionDate).getTime()
      return d !== 0 ? d : a.waterCashTransactionId - b.waterCashTransactionId
    })
    let bal = opening
    const withRun = asc.map((r) => { bal += r.amount; return { ...r, running: bal } })
    return withRun.reverse()
  }, [rows, account])

  const totalIn = useMemo(() => rows.filter(r => r.amount > 0).reduce((s, r) => s + r.amount, 0), [rows])
  const totalOut = useMemo(() => rows.filter(r => r.amount < 0).reduce((s, r) => s + Math.abs(r.amount), 0), [rows])

  function openAdjust() { setAdj({ direction: "in", amount: 0, reason: "" }); setAdjOpen(true) }

  async function saveAdjust() {
    if (adj.amount <= 0) return toast({ title: "Enter an amount greater than 0", variant: "destructive" })
    if (!adj.reason.trim()) return toast({ title: "A reason is required", variant: "destructive" })
    setSaving(true)
    try {
      const signed = adj.direction === "out" ? -Math.abs(adj.amount) : Math.abs(adj.amount)
      await adjustWaterCashAccount(id, { amount: signed, reason: adj.reason.trim() })
      toast({ title: "Balance adjusted", description: `${adj.direction === "out" ? "Removed" : "Added"} ${gh(adj.amount)}.` })
      setAdjOpen(false); await load()
    } catch (e: any) { toast({ title: "Adjustment failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function reconcile() {
    try { await reconcileWaterCashBalances(); toast({ title: "Balance recalculated from transactions" }); await load() }
    catch (e: any) { toast({ title: "Recalculate failed", description: e?.message, variant: "destructive" }) }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4">
            <Button asChild variant="ghost" size="sm" className="mb-2 -ml-2 text-slate-600">
              <Link href="/water-cash-accounts"><ArrowLeft className="h-4 w-4 mr-1" /> Back to Cash &amp; Accounts</Link>
            </Button>
            <div className="flex flex-wrap items-center justify-between gap-2">
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <Wallet className="h-6 w-6 text-sky-600" />
                {account?.accountName ?? (loading ? "Loading…" : `Account #${id}`)}
                {account && <Badge variant="outline" className="ml-1">{account.accountType}</Badge>}
                {account && !account.isActive && <Badge className="bg-amber-100 text-amber-700">Inactive</Badge>}
              </h1>
              <div className="flex flex-wrap gap-2 w-full sm:w-auto">
                <Button variant="outline" className="flex-1 sm:flex-none whitespace-nowrap" onClick={reconcile}><RefreshCw className="h-4 w-4 mr-1" /> Recalculate</Button>
                <Button className="flex-1 sm:flex-none whitespace-nowrap" onClick={openAdjust}><Scale className="h-4 w-4 mr-1" /> Adjust balance</Button>
              </div>
            </div>
          </div>

          {loading ? (
            <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : !account ? (
            <div className="p-8 text-center text-slate-500">Account not found.</div>
          ) : (
            <>
              {/* Summary */}
              <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4">
                <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Opening balance</div><div className="text-xl font-semibold tabular-nums">{gh(account.openingBalance)}</div></CardContent></Card>
                <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Total money in</div><div className="text-xl font-semibold tabular-nums text-green-700">{gh(totalIn)}</div></CardContent></Card>
                <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Total money out</div><div className="text-xl font-semibold tabular-nums text-rose-600">{gh(totalOut)}</div></CardContent></Card>
                <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Current balance</div><div className="text-xl font-semibold tabular-nums">{gh(account.currentBalance)}</div></CardContent></Card>
              </div>

              {/* Ledger */}
              <Card>
                <CardContent className="p-0">
                  {ledger.length === 0 ? (
                    <div className="p-8 text-center text-slate-500">No transactions yet for this account.</div>
                  ) : (
                    <MobileCardList
                      items={ledger}
                      getKey={(r) => r.waterCashTransactionId}
                      primary={(r) => `${r.amount < 0 ? "−" : "+"}${gh(Math.abs(r.amount))} · ${r.transactionType}`}
                      secondary={(r) => (<><span>{r.transactionDate.split("T")[0]}</span><span>· Bal {gh(r.running)}</span></>)}
                      details={(r) => [
                        { label: "Date", value: r.transactionDate.split("T")[0] },
                        { label: "Type", value: r.transactionType },
                        { label: "Source", value: r.sourceType ?? "—" },
                        { label: "Money in", value: r.amount > 0 ? gh(r.amount) : "—" },
                        { label: "Money out", value: r.amount < 0 ? gh(Math.abs(r.amount)) : "—" },
                        { label: "Running balance", value: gh(r.running) },
                        { label: "Description", value: r.description ?? "—" },
                      ]}
                      desktopTable={
                        <div className="overflow-x-auto">
                          <Table>
                            <TableHeader>
                              <TableRow>
                                <TableHead>Date</TableHead>
                                <TableHead>Type</TableHead>
                                <TableHead>Source</TableHead>
                                <TableHead className="text-right">Money in</TableHead>
                                <TableHead className="text-right">Money out</TableHead>
                                <TableHead className="text-right">Running balance</TableHead>
                                <TableHead>Description</TableHead>
                              </TableRow>
                            </TableHeader>
                            <TableBody>
                              {ledger.map((r) => (
                                <TableRow key={r.waterCashTransactionId}>
                                  <TableCell className="whitespace-nowrap">{r.transactionDate.split("T")[0]}</TableCell>
                                  <TableCell>{r.transactionType}</TableCell>
                                  <TableCell>{r.sourceType ?? "—"}</TableCell>
                                  <TableCell className="text-right tabular-nums text-green-700">{r.amount > 0 ? gh(r.amount) : "—"}</TableCell>
                                  <TableCell className="text-right tabular-nums text-rose-600">{r.amount < 0 ? gh(Math.abs(r.amount)) : "—"}</TableCell>
                                  <TableCell className="text-right tabular-nums font-medium">{gh(r.running)}</TableCell>
                                  <TableCell className="max-w-sm whitespace-normal break-words align-top">{r.description ?? "—"}</TableCell>
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
            </>
          )}
        </main>
      </div>

      {/* Adjust balance */}
      <Dialog open={adjOpen} onOpenChange={setAdjOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2"><Scale className="h-5 w-5 text-sky-600" /> Adjust balance</DialogTitle>
            <DialogDescription>Posts an adjustment transaction and moves the balance — it is never edited directly.</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormSection title="Adjustment" color="indigo" columns={1}>
              <FormField label="Direction">
                <Select value={adj.direction} onValueChange={(v) => setAdj({ ...adj, direction: v as "in" | "out" })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="in">Add money (cash in)</SelectItem>
                    <SelectItem value="out">Remove money (cash out)</SelectItem>
                  </SelectContent>
                </Select>
              </FormField>
              <FormField label="Amount *">
                <NumberInput min={0} step="0.01" value={adj.amount} onChange={(e) => setAdj({ ...adj, amount: Number(e.target.value) || 0 })} />
              </FormField>
              <FormField label="Reason *">
                <Input value={adj.reason} onChange={(e) => setAdj({ ...adj, reason: e.target.value })} placeholder="e.g. Cash count correction, bank charge" />
              </FormField>
            </FormSection>
            {account && (
              <p className="text-xs text-slate-500">
                New balance will be{" "}
                <span className="font-medium">
                  {gh((account.currentBalance ?? 0) + (adj.direction === "out" ? -Math.abs(adj.amount) : Math.abs(adj.amount)))}
                </span>{" "}
                (from {gh(account.currentBalance ?? 0)}).
              </p>
            )}
            <div className="flex gap-3 justify-end pt-2">
              <Button type="button" variant="ghost" onClick={() => setAdjOpen(false)}>Cancel</Button>
              <Button onClick={saveAdjust} disabled={saving}>
                {saving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : "Save adjustment"}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}
