"use client"

/**
 * Restaurant Cash Transfers — move money between cash accounts (e.g. cash box
 * to bank deposit). Both sides post in one database call; a reversal posts the
 * opposite pair dated today. Backed by lib/api/restaurant-finance.ts.
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
import { ArrowLeftRight, ArrowRight, Plus, CalendarDays, DollarSign, Undo2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { useFmt } from "@/lib/currency"
import { StatCard } from "@/components/restaurant/stat-card"
import { EmptyState } from "@/components/restaurant/empty-state"
import { PageHeader } from "@/components/restaurant/page-header"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import {
  listCashAccounts, listTransfers, createTransfer, reverseTransfer, todayIso,
  type CashAccount, type CashTransfer,
} from "@/lib/api/restaurant-finance"

function firstOfMonthIso(): string {
  return `${todayIso().slice(0, 8)}01`
}

interface TransferForm {
  fromAccountId: string
  toAccountId: string
  amount: string
  transferDate: string
  reference: string
  notes: string
}

const newForm = (): TransferForm => ({
  fromAccountId: "", toAccountId: "", amount: "", transferDate: todayIso(), reference: "", notes: "",
})

export default function RestaurantCashTransfersPage() {
  const router = useRouter()
  const { toast } = useToast()
  const gh = useFmt()
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const canView = permissions.isAdmin || permissions.featureAccess.canViewCashLedger

  const [loading, setLoading] = useState(true)
  const [accounts, setAccounts] = useState<CashAccount[]>([])
  const [transfers, setTransfers] = useState<CashTransfer[]>([])
  const [dateFrom, setDateFrom] = useState(firstOfMonthIso())
  const [dateTo, setDateTo] = useState(todayIso())

  const [formOpen, setFormOpen] = useState(false)
  const [form, setForm] = useState<TransferForm>(newForm())
  const [saving, setSaving] = useState(false)

  const [reverseTarget, setReverseTarget] = useState<CashTransfer | null>(null)
  const [reverseReason, setReverseReason] = useState("")
  const [reversing, setReversing] = useState(false)

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
  }, [activeFarmType, router])

  const fetchData = useCallback(async (from: string, to: string) => {
    try {
      setLoading(true)
      const [acc, tr] = await Promise.all([listCashAccounts(), listTransfers(from || undefined, to || undefined)])
      setAccounts(acc ?? [])
      setTransfers(tr ?? [])
    } catch (e: any) {
      toast({ title: "Error loading transfers", description: e?.message ?? "Unknown error", variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }, [toast])

  // Initial load only; the date filter reloads via the Filter button.
  useEffect(() => {
    if (!activeFarmId || !canView) { setLoading(false); return }
    void fetchData(dateFrom, dateTo)
  }, [activeFarmId, canView, fetchData]) // eslint-disable-line react-hooks/exhaustive-deps

  const reload = () => fetchData(dateFrom, dateTo)

  const activeAccounts = useMemo(() => accounts.filter((a) => a.isActive), [accounts])
  const toOptions = activeAccounts.filter((a) => String(a.cashAccountId) !== form.fromAccountId)

  const stats = useMemo(() => {
    const posted = transfers.filter((t) => t.status === "Posted")
    return {
      count: posted.length,
      moved: posted.reduce((s, t) => s + (t.amount ?? 0), 0),
      reversed: transfers.filter((t) => t.status === "Reversed").length,
    }
  }, [transfers])

  const accountLabel = (a: CashAccount) => `${a.name} — ${gh(a.currentBalance)}`

  /* ---------- create ---------- */
  const openNew = () => { setForm(newForm()); setFormOpen(true) }

  const handleCreate = async () => {
    const fromId = Number(form.fromAccountId)
    const toId = Number(form.toAccountId)
    const amount = parseFloat(form.amount)
    if (!fromId || !toId) {
      toast({ title: "Pick both accounts", description: "Choose where the money comes from and where it goes.", variant: "destructive" })
      return
    }
    if (fromId === toId) {
      toast({ title: "Same account", description: "The from and to accounts must be different.", variant: "destructive" })
      return
    }
    if (!Number.isFinite(amount) || amount <= 0) {
      toast({ title: "Invalid amount", description: "Enter an amount greater than zero.", variant: "destructive" })
      return
    }
    if (form.transferDate && form.transferDate > todayIso()) {
      toast({ title: "Future date", description: "A transfer cannot be dated in the future.", variant: "destructive" })
      return
    }
    try {
      setSaving(true)
      await createTransfer({
        fromAccountId: fromId, toAccountId: toId, amount,
        transferDate: form.transferDate || undefined,
        reference: form.reference.trim() || null, notes: form.notes.trim() || null,
      })
      toast({ title: "Transfer posted", description: `${gh(amount)} moved.` })
      setFormOpen(false)
      await reload()
    } catch (e: any) {
      toast({ title: "Could not post transfer", description: e?.message ?? "Unknown error", variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  /* ---------- reverse ---------- */
  const handleReverse = async () => {
    if (!reverseTarget) return
    if (!reverseReason.trim()) {
      toast({ title: "Reason required", description: "Say why this transfer is being reversed.", variant: "destructive" })
      return
    }
    try {
      setReversing(true)
      await reverseTransfer(reverseTarget.transferId, reverseReason.trim())
      toast({ title: "Transfer reversed" })
      setReverseTarget(null); setReverseReason("")
      await reload()
    } catch (e: any) {
      toast({ title: "Could not reverse transfer", description: e?.message ?? "Unknown error", variant: "destructive" })
    } finally {
      setReversing(false)
    }
  }

  /* ---------- gates ---------- */
  if (!canView) return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 md:p-6">
          <div className="max-w-7xl mx-auto">
            <Card><CardContent className="py-12 text-center text-gray-600">You do not have access to Cash Transfers.</CardContent></Card>
          </div>
        </main>
      </div>
    </div>
  )

  if (loading) return <PageSkeleton statCards={3} listRows={6} />

  /* ---------- render ---------- */
  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 md:p-6">
          <div className="max-w-7xl mx-auto space-y-6">
            <div className="space-y-2">
              <PageHeader icon={ArrowLeftRight} title="Cash Transfers" subtitle="Move money between your cash accounts">
                <Button className="bg-rose-600 hover:bg-rose-700" onClick={openNew}>
                  <Plus className="h-4 w-4 mr-2" /> New transfer
                </Button>
              </PageHeader>
              <p className="text-sm text-muted-foreground">
                A transfer posts both sides at once. Reversing it posts the opposite pair dated today — the original stays on record.
              </p>
            </div>

            <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
              <StatCard label="Transfers this period" value={stats.count} icon={ArrowLeftRight} color="rose" />
              <StatCard label="Total moved" value={gh(stats.moved)} icon={DollarSign} color="blue" />
              <StatCard label="Reversed" value={stats.reversed} icon={Undo2} color="amber" />
            </div>

            <div className="flex flex-wrap items-end gap-3">
              <div className="space-y-1">
                <Label className="text-xs text-muted-foreground">From</Label>
                <Input type="date" className="h-9 w-40" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
              </div>
              <div className="space-y-1">
                <Label className="text-xs text-muted-foreground">To</Label>
                <Input type="date" className="h-9 w-40" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
              </div>
              <Button variant="outline" size="sm" className="h-9" onClick={() => void reload()}>
                <CalendarDays className="h-4 w-4 mr-1" /> Filter
              </Button>
            </div>

            {transfers.length === 0 ? (
              <Card>
                <CardContent className="pt-6">
                  <EmptyState icon={ArrowLeftRight} title="No transfers in this period" description="Move money between accounts, e.g. a bank deposit from the cash box." actionLabel="New transfer" onAction={openNew} />
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
                          <th className="text-left p-3">From → To</th>
                          <th className="text-right p-3">Amount</th>
                          <th className="text-left p-3">Reference</th>
                          <th className="text-left p-3">Status</th>
                          <th className="text-left p-3">Created by</th>
                          <th className="text-right p-3">Actions</th>
                        </tr>
                      </thead>
                      <tbody>
                        {transfers.map((t) => (
                          <tr key={t.transferId} className="border-b">
                            <td className="p-3 font-medium text-gray-900 whitespace-nowrap">{t.transferNumber ?? `#${t.transferId}`}</td>
                            <td className="p-3 text-xs text-muted-foreground whitespace-nowrap">{(t.transferDate ?? "").slice(0, 10)}</td>
                            <td className="p-3">
                              <span className="inline-flex items-center gap-1 flex-wrap">
                                {t.fromAccountName} <ArrowRight className="h-3 w-3 text-gray-400" /> {t.toAccountName}
                              </span>
                              {t.notes && <div className="text-xs text-muted-foreground">{t.notes}</div>}
                            </td>
                            <td className="p-3 text-right font-semibold whitespace-nowrap">{gh(t.amount)}</td>
                            <td className="p-3 text-xs">{t.reference || "—"}</td>
                            <td className="p-3">
                              {t.status === "Posted" ? (
                                <Badge variant="outline" className="text-xs bg-green-100 text-green-800 border-green-200">Posted</Badge>
                              ) : (
                                <div>
                                  <Badge variant="outline" className="text-xs bg-gray-100 text-gray-600" title={t.reversalReason ?? undefined}>{t.status}</Badge>
                                  {t.reversalReason && <div className="text-xs text-muted-foreground mt-0.5">{t.reversalReason}</div>}
                                </div>
                              )}
                            </td>
                            <td className="p-3 text-xs">{t.createdBy || "—"}</td>
                            <td className="p-3 text-right">
                              {t.status === "Posted" && (
                                <Button variant="outline" size="sm" onClick={() => { setReverseTarget(t); setReverseReason("") }}>
                                  <Undo2 className="h-4 w-4 mr-1" /> Reverse
                                </Button>
                              )}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </CardContent>
              </Card>
            )}
          </div>
        </main>
      </div>

      {/* New transfer */}
      <Dialog open={formOpen} onOpenChange={(o) => { if (!saving) setFormOpen(o) }}>
        <DialogContent className="sm:max-w-md max-h-[92vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>New transfer</DialogTitle>
            <DialogDescription>Move money from one account to another.</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1.5">
              <Label>From account <span className="text-rose-500">*</span></Label>
              <Select
                value={form.fromAccountId}
                onValueChange={(v) => setForm((f) => ({ ...f, fromAccountId: v, toAccountId: f.toAccountId === v ? "" : f.toAccountId }))}
              >
                <SelectTrigger className="h-10"><SelectValue placeholder="Select account" /></SelectTrigger>
                <SelectContent>
                  {activeAccounts.map((a) => <SelectItem key={a.cashAccountId} value={String(a.cashAccountId)}>{accountLabel(a)}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>To account <span className="text-rose-500">*</span></Label>
              <Select value={form.toAccountId} onValueChange={(v) => setForm((f) => ({ ...f, toAccountId: v }))}>
                <SelectTrigger className="h-10"><SelectValue placeholder="Select account" /></SelectTrigger>
                <SelectContent>
                  {toOptions.map((a) => <SelectItem key={a.cashAccountId} value={String(a.cashAccountId)}>{accountLabel(a)}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label>Amount <span className="text-rose-500">*</span></Label>
                <Input type="number" inputMode="decimal" step="0.01" min="0" className="h-10" value={form.amount}
                  onChange={(e) => setForm((f) => ({ ...f, amount: e.target.value }))} />
              </div>
              <div className="space-y-1.5">
                <Label>Date</Label>
                <Input type="date" className="h-10" max={todayIso()} value={form.transferDate}
                  onChange={(e) => setForm((f) => ({ ...f, transferDate: e.target.value }))} />
              </div>
            </div>
            <div className="space-y-1.5">
              <Label>Reference</Label>
              <Input className="h-10" placeholder="e.g. Deposit slip number" value={form.reference}
                onChange={(e) => setForm((f) => ({ ...f, reference: e.target.value }))} />
            </div>
            <div className="space-y-1.5">
              <Label>Notes</Label>
              <Input className="h-10" placeholder="Optional" value={form.notes}
                onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} />
            </div>
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setFormOpen(false)} disabled={saving}>Cancel</Button>
            <Button className="bg-rose-600 hover:bg-rose-700" onClick={handleCreate} disabled={saving}>
              {saving ? "Posting..." : "Post transfer"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Reverse transfer */}
      <Dialog open={!!reverseTarget} onOpenChange={(o) => { if (!o && !reversing) setReverseTarget(null) }}>
        <DialogContent className="sm:max-w-md max-h-[92vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Reverse transfer</DialogTitle>
            <DialogDescription>
              {reverseTarget
                ? `${reverseTarget.transferNumber ?? `#${reverseTarget.transferId}`}: ${gh(reverseTarget.amount)} from ${reverseTarget.fromAccountName} to ${reverseTarget.toAccountName}. The opposite pair will be posted dated today.`
                : ""}
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-1.5">
            <Label>Reason <span className="text-rose-500">*</span></Label>
            <Input className="h-10" required placeholder="e.g. Wrong account" value={reverseReason} onChange={(e) => setReverseReason(e.target.value)} />
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setReverseTarget(null)} disabled={reversing}>Cancel</Button>
            <Button className="bg-rose-600 hover:bg-rose-700" onClick={handleReverse} disabled={reversing || !reverseReason.trim()}>
              {reversing ? "Reversing..." : "Reverse"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
