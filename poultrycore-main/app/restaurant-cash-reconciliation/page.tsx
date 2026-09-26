"use client"

/**
 * Reconciliation — check what the system says against what is really there.
 *
 * The restaurant equivalent of Poultry's and Water's Reconciliation page.
 * Cash boxes, banks and wallets are counted here (or confirmed against a bank
 * statement); tills are counted when their shift closes on Tills & Shifts.
 * Either way the difference is posted to the ledger as over / short, so the
 * account ends at what was counted and Cash Flow and the P&L both see it.
 * The history below shows both kinds together.
 */

import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { CheckCircle2, Loader2, Scale, TrendingDown, TrendingUp } from "lucide-react"
import { PageHeader } from "@/components/restaurant/page-header"
import { StatCard } from "@/components/restaurant/stat-card"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import { useAuthStore } from "@/lib/store/auth-store"
import { usePermissions } from "@/hooks/use-permissions"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  listCashAccounts, listCounts, listShifts, postCount, reverseCount, todayIso, ACCOUNT_TYPE_LABELS,
  type CashAccount, type CashCount, type CashShift,
} from "@/lib/api/restaurant-finance"

function firstOfMonth() {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-01`
}

interface HistoryRow {
  key: string; date: string; kind: "Count" | "Till shift"; account: string; reference: string
  system: number; counted: number; difference: number; by: string; note: string; status: string; countId?: number
}

export default function RestaurantCashReconciliationPage() {
  const router = useRouter()
  const { toast } = useToast()
  const gh = useFmt()
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const canView = permissions.isAdmin || permissions.featureAccess.canViewCashLedger

  const [loading, setLoading] = useState(true)
  const [accounts, setAccounts] = useState<CashAccount[]>([])
  const [counts, setCounts] = useState<CashCount[]>([])
  const [shifts, setShifts] = useState<CashShift[]>([])
  const [from, setFrom] = useState(firstOfMonth())
  const [to, setTo] = useState(todayIso())
  const [accountId, setAccountId] = useState("")
  const [counted, setCounted] = useState("")
  const [notes, setNotes] = useState("")
  const [saving, setSaving] = useState(false)
  const [reverseFor, setReverseFor] = useState<HistoryRow | null>(null)
  const [reason, setReason] = useState("")

  const load = useCallback(async () => {
    try {
      const [a, c, s] = await Promise.all([listCashAccounts(), listCounts(), listShifts("Closed", from, to)])
      setAccounts(a); setCounts(c); setShifts(s)
    } catch (e: any) {
      toast({ title: "Could not load reconciliation", description: e?.message, variant: "destructive" })
    } finally { setLoading(false) }
  }, [from, to, toast])

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    if (!activeFarmId) return
    void load()
  }, [activeFarmType, activeFarmId, router, load])

  // Tills are reconciled by closing their shift, so they are not offered here.
  const countable = accounts.filter((a) => a.isActive && a.accountType !== "Till")
  const chosen = countable.find((a) => String(a.cashAccountId) === accountId)
  const diff = chosen && counted !== "" ? Math.round(((parseFloat(counted) || 0) - chosen.currentBalance) * 100) / 100 : 0

  const history = useMemo<HistoryRow[]>(() => [
    ...counts.filter((c) => c.countDate.slice(0, 10) >= from && c.countDate.slice(0, 10) <= to).map((c) => ({
      key: `c${c.countId}`, date: c.countDate.slice(0, 10), kind: "Count" as const, account: c.accountName,
      reference: `Count #${c.countId}`, system: c.systemBalance, counted: c.countedBalance, difference: c.difference,
      by: c.createdBy ?? "", note: c.status === "Reversed" ? `Reversed: ${c.reversalReason ?? ""}` : (c.notes ?? ""),
      status: c.status, countId: c.countId,
    })),
    ...shifts.map((s) => ({
      key: `s${s.shiftId}`, date: (s.closedAt ?? s.openedAt).slice(0, 10), kind: "Till shift" as const, account: s.tillName,
      reference: s.shiftNumber ?? "", system: s.expectedCash ?? 0, counted: s.countedCash ?? 0, difference: s.variance ?? 0,
      by: s.closedBy ?? "", note: s.closeNotes ?? "", status: "Posted",
    })),
  ].sort((a, b) => b.date.localeCompare(a.date)), [counts, shifts, from, to])

  const live = history.filter((h) => h.status === "Posted")
  const short = -live.filter((h) => h.difference < 0).reduce((t, h) => t + h.difference, 0)
  const over = live.filter((h) => h.difference > 0).reduce((t, h) => t + h.difference, 0)

  async function submit() {
    if (!chosen || counted === "") return
    setSaving(true)
    try {
      await postCount({ cashAccountId: chosen.cashAccountId, counted: parseFloat(counted) || 0, notes: notes || null })
      toast({ title: diff === 0 ? `${chosen.name} balances` : `${chosen.name}: ${diff > 0 ? "over" : "short"} by ${gh(Math.abs(diff))}`,
        description: diff === 0 ? undefined : "The difference was posted, so the account now shows what you counted." })
      setCounted(""); setNotes(""); await load()
    } catch (e: any) { toast({ title: "Count not recorded", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function submitReverse() {
    if (!reverseFor?.countId || !reason.trim()) return
    setSaving(true)
    try {
      await reverseCount(reverseFor.countId, reason.trim())
      toast({ title: "Count reversed" }); setReverseFor(null); setReason(""); await load()
    } catch (e: any) { toast({ title: "Could not reverse", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  if (!canView) return (
    <div className="flex h-screen bg-gray-50"><DashboardSidebar /><div className="flex-1 flex flex-col overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-y-auto p-4 md:p-6"><Card><CardContent className="py-12 text-center text-slate-600">You do not have access to Reconciliation.</CardContent></Card></main>
    </div></div>
  )
  if (loading) return <PageSkeleton statCards={3} listRows={6} />

  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 md:p-6 pb-24 lg:pb-6">
          <div className="max-w-7xl mx-auto space-y-6">
            <PageHeader icon={Scale} title="Reconciliation" subtitle="Count the cash box, confirm the bank and wallet balances, see every over and short" />

            <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
              <StatCard label="Short this period" value={gh(short)} icon={TrendingDown} color="red" />
              <StatCard label="Over this period" value={gh(over)} icon={TrendingUp} color="amber" />
              <StatCard label="Checks that balanced" value={`${live.filter((h) => h.difference === 0).length} of ${live.length}`} icon={CheckCircle2} color="green" />
            </div>

            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-base">Record a count</CardTitle>
                <CardDescription>
                  Count the cash, or read the balance off the bank or mobile-money statement. Tills are counted when you
                  close their shift on <Link href="/restaurant-tills" className="underline">Tills & Shifts</Link>.
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-3">
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                  <div className="space-y-1.5">
                    <Label>Account</Label>
                    <Select value={accountId} onValueChange={(v) => { setAccountId(v); setCounted("") }}>
                      <SelectTrigger className="h-10"><SelectValue placeholder="Choose an account" /></SelectTrigger>
                      <SelectContent>{countable.map((a) => (
                        <SelectItem key={a.cashAccountId} value={String(a.cashAccountId)}>{a.name} ({ACCOUNT_TYPE_LABELS[a.accountType] ?? a.accountType})</SelectItem>
                      ))}</SelectContent>
                    </Select>
                  </div>
                  <div className="space-y-1.5">
                    <Label>System says</Label>
                    <div className="h-10 rounded-md border bg-gray-50 px-3 flex items-center font-semibold tabular-nums">{chosen ? gh(chosen.currentBalance) : "—"}</div>
                  </div>
                  <div className="space-y-1.5">
                    <Label>Counted / statement balance</Label>
                    <Input type="number" inputMode="decimal" step="0.01" min={0} value={counted} disabled={!chosen}
                      onChange={(e) => setCounted(e.target.value)} className="h-10" />
                  </div>
                </div>
                {chosen && counted !== "" && (
                  <div className={`rounded-lg p-3 text-sm font-medium ${diff === 0 ? "bg-green-50 text-green-800" : diff > 0 ? "bg-amber-50 text-amber-800" : "bg-red-50 text-red-800"}`}>
                    {diff === 0 ? "It balances." : `${diff > 0 ? "Over" : "Short"} by ${gh(Math.abs(diff))} — this will be posted as cash ${diff > 0 ? "over" : "short"}.`}
                  </div>
                )}
                <div className="flex flex-col sm:flex-row gap-3">
                  <Input value={notes} onChange={(e) => setNotes(e.target.value)} placeholder={diff < 0 ? "Why is it short?" : "Notes (optional)"} className="h-10" disabled={!chosen} />
                  <Button className="bg-rose-600 hover:bg-rose-700 sm:w-48" disabled={!chosen || counted === "" || saving} onClick={submit}>
                    {saving && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}Record count
                  </Button>
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader className="pb-2">
                <div className="flex flex-col sm:flex-row sm:items-end sm:justify-between gap-3">
                  <div><CardTitle className="text-base">Reconciliation history</CardTitle>
                    <CardDescription>Account counts and till cash-ups together.</CardDescription></div>
                  <div className="flex flex-wrap items-end gap-2">
                    <Input type="date" className="h-9 w-40" value={from} onChange={(e) => setFrom(e.target.value)} />
                    <Input type="date" className="h-9 w-40" value={to} onChange={(e) => setTo(e.target.value)} />
                    <Button variant="outline" size="sm" className="h-9" onClick={() => void load()}>Show</Button>
                  </div>
                </div>
              </CardHeader>
              <CardContent className="p-0">
                {history.length === 0 ? <p className="p-6 text-center text-sm text-muted-foreground">No counts or cash-ups in this period.</p> : (
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm min-w-[820px]">
                      <thead className="bg-gray-50 border-b"><tr>
                        {["Date", "Type", "Account", "Reference", "System", "Counted", "Over / short", "By", "Note", ""].map((h, i) =>
                          <th key={i} className={`p-3 ${i >= 4 && i <= 6 ? "text-right" : "text-left"}`}>{h}</th>)}
                      </tr></thead>
                      <tbody>{history.map((h) => (
                        <tr key={h.key} className={`border-b ${h.status === "Reversed" ? "text-slate-400" : ""}`}>
                          <td className="p-3">{h.date}</td>
                          <td className="p-3"><Badge variant="outline">{h.kind}</Badge></td>
                          <td className="p-3 font-medium">{h.account}</td>
                          <td className="p-3 text-xs">{h.reference}</td>
                          <td className="p-3 text-right tabular-nums">{gh(h.system)}</td>
                          <td className="p-3 text-right tabular-nums">{gh(h.counted)}</td>
                          <td className={`p-3 text-right tabular-nums font-semibold ${h.status === "Reversed" ? "line-through" : h.difference < 0 ? "text-red-600" : h.difference > 0 ? "text-amber-600" : "text-green-700"}`}>{gh(h.difference)}</td>
                          <td className="p-3 text-xs">{h.by}</td>
                          <td className="p-3 text-xs max-w-[14rem]">{h.note}</td>
                          <td className="p-3 text-right">
                            {h.kind === "Count" && h.status === "Posted" && (
                              <Button variant="outline" size="sm" onClick={() => { setReverseFor(h); setReason("") }}>Reverse</Button>
                            )}
                          </td>
                        </tr>
                      ))}</tbody>
                    </table>
                  </div>
                )}
              </CardContent>
            </Card>
          </div>
        </main>
      </div>

      <Dialog open={!!reverseFor} onOpenChange={(o) => { if (!o) setReverseFor(null) }}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Reverse this count?</DialogTitle>
            <DialogDescription>The over / short it posted is taken back out, dated today. The count stays on record as reversed.</DialogDescription>
          </DialogHeader>
          <div className="space-y-1.5"><Label>Reason</Label><Input value={reason} onChange={(e) => setReason(e.target.value)} className="h-10" /></div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setReverseFor(null)}>Cancel</Button>
            <Button className="bg-rose-600 hover:bg-rose-700" disabled={saving || !reason.trim()} onClick={submitReverse}>Reverse</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
