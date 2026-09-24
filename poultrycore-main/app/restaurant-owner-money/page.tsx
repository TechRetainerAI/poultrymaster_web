"use client"

/**
 * Restaurant Owner Money — contributions (owner puts money in) and drawings
 * (owner takes money out). Both move cash on the ledger but are equity, not
 * income or expense, so they never touch the Profit & Loss.
 * API: lib/api/restaurant-finance.ts (migration 323).
 */

import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { HandCoins, ArrowDownToLine, ArrowUpFromLine, Scale, CalendarDays, Undo2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { useFmt } from "@/lib/currency"
import { StatCard } from "@/components/restaurant/stat-card"
import { EmptyState } from "@/components/restaurant/empty-state"
import { PageHeader } from "@/components/restaurant/page-header"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import {
  listCashAccounts, listOwnerMoney, recordOwnerMoney, reverseOwnerMoney, todayIso,
  type CashAccount, type OwnerMoneyEntry,
} from "@/lib/api/restaurant-finance"

type EntryType = "Contribution" | "Draw"

interface OwnerForm {
  entryType: EntryType
  cashAccountId: string
  amount: string
  entryDate: string
  ownerName: string
  notes: string
}

function startOfYear(): string {
  return `${new Date().getFullYear()}-01-01`
}

function blankForm(entryType: EntryType): OwnerForm {
  return { entryType, cashAccountId: "", amount: "", entryDate: todayIso(), ownerName: "", notes: "" }
}

export default function RestaurantOwnerMoneyPage() {
  const router = useRouter()
  const { toast } = useToast()
  const fmt = useFmt()
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)

  const canView = permissions.isAdmin || permissions.featureAccess.canViewCashLedger

  const [loading, setLoading] = useState(true)
  const [entries, setEntries] = useState<OwnerMoneyEntry[]>([])
  const [accounts, setAccounts] = useState<CashAccount[]>([])
  const [dateFrom, setDateFrom] = useState(startOfYear())
  const [dateTo, setDateTo] = useState(todayIso())

  const [dialogOpen, setDialogOpen] = useState(false)
  const [form, setForm] = useState<OwnerForm>(blankForm("Contribution"))
  const [saving, setSaving] = useState(false)

  const [reverseTarget, setReverseTarget] = useState<OwnerMoneyEntry | null>(null)
  const [reverseReason, setReverseReason] = useState("")
  const [reversing, setReversing] = useState(false)

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
  }, [activeFarmType, router])

  const load = useCallback(async () => {
    try {
      const [rows, accs] = await Promise.all([
        listOwnerMoney(dateFrom || undefined, dateTo || undefined),
        listCashAccounts(),
      ])
      setEntries(rows ?? [])
      setAccounts((accs ?? []).filter((a) => a.isActive))
    } catch (e: any) {
      toast({ title: "Could not load owner money", description: e?.message ?? "Unknown error", variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }, [dateFrom, dateTo, toast])

  useEffect(() => {
    if (!activeFarmId || !canView) { setLoading(false); return }
    void load()
    // Reload only when the company changes; the date filter reloads on "Load".
  }, [activeFarmId, canView]) // eslint-disable-line react-hooks/exhaustive-deps

  /* ---------- stats (Posted only) ---------- */
  const stats = useMemo(() => {
    const posted = entries.filter((e) => e.status === "Posted")
    const putIn = posted.filter((e) => e.entryType === "Contribution").reduce((s, e) => s + (e.amount ?? 0), 0)
    const takenOut = posted.filter((e) => e.entryType === "Draw").reduce((s, e) => s + (e.amount ?? 0), 0)
    return { putIn, takenOut, net: putIn - takenOut }
  }, [entries])

  /* ---------- record ---------- */
  const openRecord = (entryType: EntryType) => {
    const f = blankForm(entryType)
    if (accounts.length === 1) f.cashAccountId = String(accounts[0].cashAccountId)
    setForm(f)
    setDialogOpen(true)
  }

  const handleRecord = async () => {
    const amount = parseFloat(form.amount)
    if (!form.cashAccountId) {
      toast({ title: "Pick an account", description: "Choose which account the money goes into or comes out of.", variant: "destructive" })
      return
    }
    if (!Number.isFinite(amount) || amount <= 0) {
      toast({ title: "Enter an amount", description: "The amount must be more than zero.", variant: "destructive" })
      return
    }
    if (form.entryDate && form.entryDate > todayIso()) {
      toast({ title: "Date is in the future", description: "Pick today or an earlier date.", variant: "destructive" })
      return
    }
    try {
      setSaving(true)
      await recordOwnerMoney({
        entryType: form.entryType,
        cashAccountId: Number(form.cashAccountId),
        amount,
        entryDate: form.entryDate || undefined,
        ownerName: form.ownerName.trim() || null,
        notes: form.notes.trim() || null,
      })
      toast({ title: "Saved", description: form.entryType === "Contribution" ? "Contribution recorded." : "Drawing recorded." })
      setDialogOpen(false)
      await load()
    } catch (e: any) {
      toast({ title: "Could not save", description: e?.message ?? "Unknown error", variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  /* ---------- reverse ---------- */
  const handleReverse = async () => {
    if (!reverseTarget || !reverseReason.trim()) return
    try {
      setReversing(true)
      await reverseOwnerMoney(reverseTarget.ownerMoneyId, reverseReason.trim())
      toast({ title: "Reversed", description: "The entry was reversed and the cash put back." })
      setReverseTarget(null)
      setReverseReason("")
      await load()
    } catch (e: any) {
      toast({ title: "Could not reverse", description: e?.message ?? "Unknown error", variant: "destructive" })
    } finally {
      setReversing(false)
    }
  }

  const accountLabel = (a: CashAccount) => `${a.name} — ${fmt(a.currentBalance)}`

  if (loading) return <PageSkeleton statCards={3} listRows={6} />

  if (!canView) return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 md:p-6">
          <div className="max-w-7xl mx-auto">
            <Card><CardContent className="py-12 text-center text-gray-600">You do not have access to Owner Money.</CardContent></Card>
          </div>
        </main>
      </div>
    </div>
  )

  const isContribution = form.entryType === "Contribution"

  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 md:p-6">
          <div className="max-w-7xl mx-auto space-y-6">
            <PageHeader icon={HandCoins} title="Owner Money" subtitle="Money the owner puts into or takes out of the business">
              <Button className="bg-rose-600 hover:bg-rose-700" onClick={() => openRecord("Contribution")}>
                <ArrowDownToLine className="h-4 w-4 mr-2" /> Record contribution
              </Button>
              <Button className="bg-rose-600 hover:bg-rose-700" onClick={() => openRecord("Draw")}>
                <ArrowUpFromLine className="h-4 w-4 mr-2" /> Record drawing
              </Button>
            </PageHeader>

            <p className="text-sm text-muted-foreground">
              Contributions and drawings move cash but are not income or expenses, so they never change profit.
            </p>

            {/* Date filter */}
            <div className="flex flex-wrap items-end gap-3">
              <div className="space-y-1">
                <Label className="text-xs text-muted-foreground">From</Label>
                <Input type="date" className="h-9 w-40" value={dateFrom} max={dateTo || undefined} onChange={(e) => setDateFrom(e.target.value)} />
              </div>
              <div className="space-y-1">
                <Label className="text-xs text-muted-foreground">To</Label>
                <Input type="date" className="h-9 w-40" value={dateTo} min={dateFrom || undefined} onChange={(e) => setDateTo(e.target.value)} />
              </div>
              <Button variant="outline" size="sm" className="h-9" onClick={() => { void load() }}>
                <CalendarDays className="h-4 w-4 mr-1" /> Load
              </Button>
            </div>

            {/* Stats */}
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
              <StatCard label="Put in" value={fmt(stats.putIn)} icon={ArrowDownToLine} color="green" />
              <StatCard label="Taken out" value={fmt(stats.takenOut)} icon={ArrowUpFromLine} color="amber" />
              <StatCard label="Net (in − out)" value={fmt(stats.net)} icon={Scale} color={stats.net >= 0 ? "green" : "red"} />
            </div>

            {entries.length === 0 ? (
              <Card>
                <CardContent className="pt-6">
                  <EmptyState
                    icon={HandCoins}
                    title="No owner money in this period"
                    description="Record money the owner puts in or takes out"
                    actionLabel="Record contribution"
                    onAction={() => openRecord("Contribution")}
                  />
                </CardContent>
              </Card>
            ) : (
              <Card>
                <CardContent className="p-0">
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm min-w-[640px]">
                      <thead className="bg-gray-50 border-b">
                        <tr>
                          <th className="text-left p-3">Number</th>
                          <th className="text-left p-3">Date</th>
                          <th className="text-left p-3">Type</th>
                          <th className="text-left p-3">Account</th>
                          <th className="text-left p-3">Owner</th>
                          <th className="text-right p-3">Amount</th>
                          <th className="text-left p-3">Status</th>
                          <th className="text-right p-3">Actions</th>
                        </tr>
                      </thead>
                      <tbody>
                        {entries.map((e) => {
                          const reversed = e.status !== "Posted"
                          return (
                            <tr key={e.ownerMoneyId} className={`border-b align-top ${reversed ? "text-gray-400" : ""}`}>
                              <td className="p-3 font-mono text-xs">{e.entryNumber || `#${e.ownerMoneyId}`}</td>
                              <td className="p-3 text-xs whitespace-nowrap">{e.entryDate?.split("T")[0]}</td>
                              <td className="p-3">
                                {e.entryType === "Contribution"
                                  ? <Badge variant="outline" className="text-xs bg-green-50 text-green-700 border-green-200">Contribution</Badge>
                                  : <Badge variant="outline" className="text-xs bg-amber-50 text-amber-700 border-amber-200">Draw</Badge>}
                              </td>
                              <td className="p-3">{e.accountName}</td>
                              <td className="p-3">{e.ownerName || "—"}</td>
                              <td className={`p-3 text-right font-semibold whitespace-nowrap ${reversed ? "line-through" : e.entryType === "Contribution" ? "text-green-700" : "text-amber-700"}`}>
                                {fmt(e.amount)}
                              </td>
                              <td className="p-3">
                                {reversed ? (
                                  <div>
                                    <Badge variant="outline" className="text-xs text-gray-500">{e.status}</Badge>
                                    {e.reversalReason && <p className="text-xs mt-1 max-w-[16rem]">{e.reversalReason}</p>}
                                  </div>
                                ) : (
                                  <Badge variant="outline" className="text-xs">Posted</Badge>
                                )}
                              </td>
                              <td className="p-3 text-right">
                                {!reversed && (
                                  <Button variant="outline" size="sm" onClick={() => { setReverseTarget(e); setReverseReason("") }}>
                                    <Undo2 className="h-4 w-4 mr-1" /> Reverse
                                  </Button>
                                )}
                              </td>
                            </tr>
                          )
                        })}
                      </tbody>
                    </table>
                  </div>
                </CardContent>
              </Card>
            )}
          </div>
        </main>
      </div>

      {/* Record dialog */}
      <Dialog open={dialogOpen} onOpenChange={(o) => { if (!saving) setDialogOpen(o) }}>
        <DialogContent className="sm:max-w-md max-h-[92vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{isContribution ? "Record contribution" : "Record drawing"}</DialogTitle>
            <DialogDescription>
              {isContribution
                ? "Money the owner puts into the business. It is not income."
                : "Money the owner takes out of the business. It is not an expense."}
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1.5">
              <Label>{isContribution ? "Money goes into" : "Money comes out of"} <span className="text-rose-500">*</span></Label>
              <Select value={form.cashAccountId} onValueChange={(v) => setForm((f) => ({ ...f, cashAccountId: v }))}>
                <SelectTrigger className="h-10"><SelectValue placeholder="Select account" /></SelectTrigger>
                <SelectContent>
                  {accounts.map((a) => (
                    <SelectItem key={a.cashAccountId} value={String(a.cashAccountId)}>{accountLabel(a)}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label>Amount <span className="text-rose-500">*</span></Label>
                <Input
                  type="number" inputMode="decimal" step="0.01" min="0" className="h-10"
                  value={form.amount}
                  onChange={(e) => setForm((f) => ({ ...f, amount: e.target.value }))}
                />
              </div>
              <div className="space-y-1.5">
                <Label>Date</Label>
                <Input
                  type="date" className="h-10" max={todayIso()}
                  value={form.entryDate}
                  onChange={(e) => setForm((f) => ({ ...f, entryDate: e.target.value }))}
                />
              </div>
            </div>
            <div className="space-y-1.5">
              <Label>Owner name</Label>
              <Input
                className="h-10" placeholder="Optional"
                value={form.ownerName}
                onChange={(e) => setForm((f) => ({ ...f, ownerName: e.target.value }))}
              />
            </div>
            <div className="space-y-1.5">
              <Label>Notes</Label>
              <Input
                className="h-10" placeholder="Optional"
                value={form.notes}
                onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))}
              />
            </div>
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setDialogOpen(false)} disabled={saving}>Cancel</Button>
            <Button className="bg-rose-600 hover:bg-rose-700" onClick={handleRecord} disabled={saving}>
              {saving ? "Saving..." : isContribution ? "Record contribution" : "Record drawing"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Reverse dialog */}
      <Dialog open={!!reverseTarget} onOpenChange={(o) => { if (!o && !reversing) setReverseTarget(null) }}>
        <DialogContent className="sm:max-w-md max-h-[92vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Reverse {reverseTarget?.entryType === "Draw" ? "drawing" : "contribution"}</DialogTitle>
            <DialogDescription>
              {reverseTarget && `${reverseTarget.entryNumber || `#${reverseTarget.ownerMoneyId}`} — ${fmt(reverseTarget.amount)} ${reverseTarget.entryType === "Draw" ? "goes back into" : "comes back out of"} ${reverseTarget.accountName}.`}
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-1.5">
            <Label>Reason <span className="text-rose-500">*</span></Label>
            <Input
              className="h-10" placeholder="Why is this being reversed?" autoFocus
              value={reverseReason}
              onChange={(e) => setReverseReason(e.target.value)}
            />
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setReverseTarget(null)} disabled={reversing}>Keep it</Button>
            <Button variant="destructive" onClick={handleReverse} disabled={reversing || !reverseReason.trim()}>
              {reversing ? "Reversing..." : "Reverse"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
