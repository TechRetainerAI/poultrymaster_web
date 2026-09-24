"use client"

/**
 * Restaurant Cash Accounts — every place the restaurant keeps money (tills,
 * cash box / safe, petty cash, mobile money, bank) with its balance, ledger
 * and cash counts. Backed by lib/api/restaurant-finance.ts (migration 323).
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
import { Checkbox } from "@/components/ui/checkbox"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Wallet, Plus, Coins, AlertTriangle, Clock, BookOpen, Calculator, Pencil, Undo2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { useFmt } from "@/lib/currency"
import { StatCard } from "@/components/restaurant/stat-card"
import { EmptyState } from "@/components/restaurant/empty-state"
import { PageHeader } from "@/components/restaurant/page-header"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import {
  listCashAccounts, createCashAccount, updateCashAccount, getAccountLedger,
  listCounts, postCount, reverseCount,
  ACCOUNT_TYPES, ACCOUNT_TYPE_LABELS, DEFAULT_FOR_LABELS, ledgerSourceLabel, todayIso,
  type CashAccount, type CashCount, type LedgerRow,
} from "@/lib/api/restaurant-finance"

const NONE = "__none__"
const DEFAULT_FOR_OPTIONS = ["Cash", "Bank", "MobileMoney"] as const

function firstOfMonthIso(): string {
  return `${todayIso().slice(0, 8)}01`
}

interface AccountForm {
  name: string
  accountType: string
  openingBalance: string
  defaultFor: string // NONE or a DEFAULT_FOR_OPTIONS value
  allowNegative: boolean
  isActive: boolean
  notes: string
}

const emptyForm: AccountForm = {
  name: "", accountType: "CashBox", openingBalance: "", defaultFor: NONE,
  allowNegative: false, isActive: true, notes: "",
}

export default function RestaurantCashAccountsPage() {
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
  const [activeTab, setActiveTab] = useState<"accounts" | "counts">("accounts")

  // New / edit account
  const [formOpen, setFormOpen] = useState(false)
  const [editing, setEditing] = useState<CashAccount | null>(null)
  const [form, setForm] = useState<AccountForm>({ ...emptyForm })
  const [saving, setSaving] = useState(false)

  // Ledger
  const [ledgerAccount, setLedgerAccount] = useState<CashAccount | null>(null)
  const [ledgerFrom, setLedgerFrom] = useState(firstOfMonthIso())
  const [ledgerTo, setLedgerTo] = useState(todayIso())
  const [ledgerRows, setLedgerRows] = useState<LedgerRow[]>([])
  const [ledgerLoading, setLedgerLoading] = useState(false)

  // Count
  const [countAccount, setCountAccount] = useState<CashAccount | null>(null)
  const [counted, setCounted] = useState("")
  const [countNotes, setCountNotes] = useState("")
  const [countSaving, setCountSaving] = useState(false)

  // Reverse count
  const [reverseTarget, setReverseTarget] = useState<CashCount | null>(null)
  const [reverseReason, setReverseReason] = useState("")
  const [reversing, setReversing] = useState(false)

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
  }, [activeFarmType, router])

  const fetchData = useCallback(async () => {
    try {
      setLoading(true)
      const [acc, cnt] = await Promise.all([listCashAccounts(), listCounts()])
      setAccounts(acc ?? [])
      setCounts(cnt ?? [])
    } catch (e: any) {
      toast({ title: "Error loading cash accounts", description: e?.message ?? "Unknown error", variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }, [toast])

  useEffect(() => {
    if (!activeFarmId || !canView) { setLoading(false); return }
    void fetchData()
  }, [activeFarmId, canView, fetchData])

  /* ---------- stats ---------- */
  const stats = useMemo(() => {
    const active = accounts.filter((a) => a.isActive)
    return {
      total: active.reduce((s, a) => s + (a.currentBalance ?? 0), 0),
      tills: accounts.filter((a) => a.accountType === "Till").length,
      belowZero: accounts.filter((a) => (a.currentBalance ?? 0) < 0).length,
      openShifts: accounts.filter((a) => !!a.openShiftId).length,
    }
  }, [accounts])

  /* ---------- account form ---------- */
  const openNew = () => { setEditing(null); setForm({ ...emptyForm }); setFormOpen(true) }
  const openEdit = (a: CashAccount) => {
    setEditing(a)
    setForm({
      name: a.name, accountType: a.accountType, openingBalance: "",
      defaultFor: a.defaultFor || NONE, allowNegative: a.allowNegative, isActive: a.isActive, notes: a.notes ?? "",
    })
    setFormOpen(true)
  }

  const handleSaveAccount = async () => {
    if (!form.name.trim()) {
      toast({ title: "Name required", description: "Give the account a name.", variant: "destructive" })
      return
    }
    const defaultFor = form.defaultFor === NONE ? null : form.defaultFor
    try {
      setSaving(true)
      if (editing) {
        await updateCashAccount(editing.cashAccountId, {
          name: form.name.trim(), accountType: form.accountType, allowNegative: form.allowNegative,
          isActive: form.isActive, defaultFor, notes: form.notes.trim() || null,
        })
        toast({ title: "Account updated", description: form.name.trim() })
      } else {
        let openingBalance: number | undefined
        if (form.openingBalance.trim() !== "") {
          const n = parseFloat(form.openingBalance)
          if (!Number.isFinite(n)) {
            toast({ title: "Invalid opening balance", description: "Enter a number or leave it blank.", variant: "destructive" })
            setSaving(false)
            return
          }
          openingBalance = n
        }
        await createCashAccount({
          name: form.name.trim(), accountType: form.accountType, openingBalance,
          allowNegative: form.allowNegative, defaultFor, notes: form.notes.trim() || null,
        })
        toast({ title: "Account created", description: form.name.trim() })
      }
      setFormOpen(false)
      await fetchData()
    } catch (e: any) {
      toast({ title: "Could not save account", description: e?.message ?? "Unknown error", variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  /* ---------- ledger ---------- */
  const loadLedger = async (acc: CashAccount, from: string, to: string) => {
    try {
      setLedgerLoading(true)
      const rows = await getAccountLedger(acc.cashAccountId, from || undefined, to || undefined)
      setLedgerRows(rows ?? [])
    } catch (e: any) {
      toast({ title: "Could not load ledger", description: e?.message ?? "Unknown error", variant: "destructive" })
      setLedgerRows([])
    } finally {
      setLedgerLoading(false)
    }
  }

  const openLedger = (a: CashAccount) => {
    const from = firstOfMonthIso()
    const to = todayIso()
    setLedgerFrom(from); setLedgerTo(to); setLedgerRows([])
    setLedgerAccount(a)
    void loadLedger(a, from, to)
  }

  /* ---------- count ---------- */
  const openCount = (a: CashAccount) => {
    setCountAccount(a); setCounted(""); setCountNotes("")
  }
  const countedNum = counted.trim() === "" ? NaN : parseFloat(counted)
  const countDiff = countAccount && Number.isFinite(countedNum) ? countedNum - (countAccount.currentBalance ?? 0) : null

  const handlePostCount = async () => {
    if (!countAccount) return
    if (!Number.isFinite(countedNum)) {
      toast({ title: "Enter the counted balance", description: "Type the amount you counted or confirmed.", variant: "destructive" })
      return
    }
    try {
      setCountSaving(true)
      await postCount({ cashAccountId: countAccount.cashAccountId, counted: countedNum, notes: countNotes.trim() || null })
      const diff = countedNum - (countAccount.currentBalance ?? 0)
      toast({
        title: "Count posted",
        description: diff === 0
          ? `${countAccount.name} balances exactly.`
          : `${countAccount.name} is ${gh(Math.abs(diff))} ${diff > 0 ? "over" : "short"}.`,
      })
      setCountAccount(null)
      await fetchData()
    } catch (e: any) {
      toast({ title: "Could not post count", description: e?.message ?? "Unknown error", variant: "destructive" })
    } finally {
      setCountSaving(false)
    }
  }

  /* ---------- reverse count ---------- */
  const handleReverseCount = async () => {
    if (!reverseTarget) return
    if (!reverseReason.trim()) {
      toast({ title: "Reason required", description: "Say why this count is being reversed.", variant: "destructive" })
      return
    }
    try {
      setReversing(true)
      await reverseCount(reverseTarget.countId, reverseReason.trim())
      toast({ title: "Count reversed" })
      setReverseTarget(null); setReverseReason("")
      await fetchData()
    } catch (e: any) {
      toast({ title: "Could not reverse count", description: e?.message ?? "Unknown error", variant: "destructive" })
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
            <Card><CardContent className="py-12 text-center text-gray-600">You do not have access to Cash Accounts.</CardContent></Card>
          </div>
        </main>
      </div>
    </div>
  )

  if (loading) return <PageSkeleton statCards={4} listRows={6} />

  /* ---------- render ---------- */
  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 md:p-6">
          <div className="max-w-7xl mx-auto space-y-6">
            <div className="space-y-2">
              <PageHeader icon={Wallet} title="Cash Accounts" subtitle="Tills, cash box, petty cash, mobile money and bank — with their balances">
                <Button className="bg-rose-600 hover:bg-rose-700" onClick={openNew}>
                  <Plus className="h-4 w-4 mr-2" /> New account
                </Button>
              </PageHeader>
              <p className="text-sm text-muted-foreground">
                Every payment, expense, transfer and till shift posts here automatically. The three default accounts are created for you.
              </p>
            </div>

            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <StatCard label="Total cash held" value={gh(stats.total)} icon={Wallet} color="rose" />
              <StatCard label="Tills" value={stats.tills} icon={Coins} color="blue" />
              <StatCard label="Accounts below zero" value={stats.belowZero} icon={AlertTriangle} color={stats.belowZero > 0 ? "red" : "green"} />
              <StatCard label="Open till shifts" value={stats.openShifts} icon={Clock} color="amber" />
            </div>

            {/* Tabs */}
            <div className="flex gap-2 border-b pb-1">
              {(["accounts", "counts"] as const).map((tab) => (
                <button
                  key={tab}
                  onClick={() => setActiveTab(tab)}
                  className={`px-4 py-2 text-sm font-medium rounded-t-lg transition-colors ${
                    activeTab === tab ? "bg-white border border-b-white -mb-px text-rose-600" : "text-gray-500 hover:text-gray-700"
                  }`}
                >
                  {tab === "accounts" ? "Accounts" : "Count history"}
                </button>
              ))}
            </div>

            {activeTab === "accounts" && (
              accounts.length === 0 ? (
                <Card>
                  <CardContent className="pt-6">
                    <EmptyState icon={Wallet} title="No cash accounts yet" description="Add the places where the restaurant keeps money." actionLabel="New account" onAction={openNew} />
                  </CardContent>
                </Card>
              ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
                  {accounts.map((a) => {
                    const outOfSync = Math.abs((a.ledgerBalance ?? 0) - (a.currentBalance ?? 0)) > 0.005
                    const tillLocked = a.accountType === "Till" && !!a.openShiftId
                    return (
                      <Card key={a.cashAccountId} className={a.isActive ? "" : "opacity-70"}>
                        <CardContent className="p-4 space-y-3">
                          <div className="flex items-start justify-between gap-2">
                            <div className="min-w-0">
                              <div className="font-semibold text-gray-900 truncate">{a.name}</div>
                              <div className="text-xs text-muted-foreground">{ACCOUNT_TYPE_LABELS[a.accountType] ?? a.accountType}</div>
                            </div>
                            <div className={`text-right text-lg font-bold whitespace-nowrap ${(a.currentBalance ?? 0) < 0 ? "text-red-600" : "text-gray-900"}`}>
                              {gh(a.currentBalance)}
                            </div>
                          </div>

                          <div className="flex flex-wrap gap-1.5">
                            {a.defaultFor && (
                              <Badge variant="secondary" className="text-xs bg-rose-50 text-rose-700 border-rose-200">
                                Default for {DEFAULT_FOR_LABELS[a.defaultFor] ?? a.defaultFor}
                              </Badge>
                            )}
                            {a.openShiftId && (
                              <Badge variant="outline" className="text-xs border-amber-300 text-amber-700 bg-amber-50">
                                Open shift {a.openShiftNumber ?? `SH-${a.openShiftId}`}
                              </Badge>
                            )}
                            {!a.isActive && <Badge variant="outline" className="text-xs text-gray-500">Inactive</Badge>}
                            {outOfSync && (
                              <Badge variant="outline" className="text-xs border-red-300 text-red-700 bg-red-50" title={`Ledger says ${gh(a.ledgerBalance)}`}>
                                <AlertTriangle className="h-3 w-3 mr-1" /> Out of sync
                              </Badge>
                            )}
                          </div>

                          <div className="text-xs text-muted-foreground">
                            {a.lastCountedAt
                              ? <>Last counted {a.lastCountedAt.slice(0, 10)}{a.lastCountedBalance != null && <> at {gh(a.lastCountedBalance)}</>}</>
                              : "Never counted"}
                          </div>

                          <div className="flex flex-wrap gap-2">
                            <Button variant="outline" size="sm" onClick={() => openLedger(a)}>
                              <BookOpen className="h-4 w-4 mr-1" /> Ledger
                            </Button>
                            <Button variant="outline" size="sm" onClick={() => openCount(a)} disabled={tillLocked}>
                              <Calculator className="h-4 w-4 mr-1" /> Count
                            </Button>
                            <Button variant="outline" size="sm" onClick={() => openEdit(a)}>
                              <Pencil className="h-4 w-4 mr-1" /> Edit
                            </Button>
                          </div>
                          {tillLocked && <p className="text-xs text-amber-700">Close the shift to count this till.</p>}
                        </CardContent>
                      </Card>
                    )
                  })}
                </div>
              )
            )}

            {activeTab === "counts" && (
              counts.length === 0 ? (
                <Card>
                  <CardContent className="pt-6">
                    <EmptyState icon={Calculator} title="No counts yet" description="Use Count on an account to confirm what is really there." />
                  </CardContent>
                </Card>
              ) : (
                <Card>
                  <CardContent className="p-0">
                    <div className="overflow-x-auto">
                      <table className="w-full text-sm min-w-[640px]">
                        <thead className="bg-gray-50 border-b">
                          <tr>
                            <th className="text-left p-3">Date</th>
                            <th className="text-left p-3">Account</th>
                            <th className="text-right p-3">System</th>
                            <th className="text-right p-3">Counted</th>
                            <th className="text-right p-3">Difference</th>
                            <th className="text-left p-3">Status</th>
                            <th className="text-right p-3">Actions</th>
                          </tr>
                        </thead>
                        <tbody>
                          {counts.map((c) => (
                            <tr key={c.countId} className="border-b">
                              <td className="p-3 text-xs text-muted-foreground whitespace-nowrap">{(c.countDate ?? "").slice(0, 10)}</td>
                              <td className="p-3 font-medium text-gray-900">
                                {c.accountName}
                                {c.notes && <div className="text-xs font-normal text-muted-foreground">{c.notes}</div>}
                              </td>
                              <td className="p-3 text-right">{gh(c.systemBalance)}</td>
                              <td className="p-3 text-right">{gh(c.countedBalance)}</td>
                              <td className={`p-3 text-right font-semibold ${c.difference > 0 ? "text-green-600" : c.difference < 0 ? "text-red-600" : "text-gray-700"}`}>
                                {c.difference > 0 ? "+" : ""}{gh(c.difference)}
                                {c.difference !== 0 && <span className="ml-1 text-xs font-normal">{c.difference > 0 ? "over" : "short"}</span>}
                              </td>
                              <td className="p-3">
                                {c.status === "Posted"
                                  ? <Badge className="text-xs bg-green-100 text-green-800 border-green-200" variant="outline">Posted</Badge>
                                  : (
                                    <div>
                                      <Badge className="text-xs bg-gray-100 text-gray-600" variant="outline" title={c.reversalReason ?? undefined}>{c.status}</Badge>
                                      {c.reversalReason && <div className="text-xs text-muted-foreground mt-0.5">{c.reversalReason}</div>}
                                    </div>
                                  )}
                              </td>
                              <td className="p-3 text-right">
                                {c.status === "Posted" && (
                                  <Button variant="outline" size="sm" onClick={() => { setReverseTarget(c); setReverseReason("") }}>
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
              )
            )}
          </div>
        </main>
      </div>

      {/* New / Edit account */}
      <Dialog open={formOpen} onOpenChange={(o) => { if (!saving) setFormOpen(o) }}>
        <DialogContent className="sm:max-w-md max-h-[92vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{editing ? "Edit account" : "New account"}</DialogTitle>
            <DialogDescription>{editing ? editing.name : "Add a place where the restaurant keeps money."}</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1.5">
              <Label>Name <span className="text-rose-500">*</span></Label>
              <Input className="h-10" placeholder="e.g. Front till" value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} />
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label>Type</Label>
                <Select value={form.accountType} onValueChange={(v) => setForm((f) => ({ ...f, accountType: v }))}>
                  <SelectTrigger className="h-10"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {ACCOUNT_TYPES.map((t) => <SelectItem key={t} value={t}>{ACCOUNT_TYPE_LABELS[t] ?? t}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
              {!editing && (
                <div className="space-y-1.5">
                  <Label>Opening balance</Label>
                  <Input
                    type="number" inputMode="decimal" step="0.01" className="h-10" placeholder="0.00"
                    value={form.openingBalance}
                    onChange={(e) => setForm((f) => ({ ...f, openingBalance: e.target.value }))}
                  />
                </div>
              )}
            </div>
            {form.accountType === "Till" && (
              <p className="text-xs text-muted-foreground">Tills are cash drawers used in shifts — open and close them on the Tills page.</p>
            )}
            <div className="space-y-1.5">
              <Label>Default for</Label>
              <Select value={form.defaultFor} onValueChange={(v) => setForm((f) => ({ ...f, defaultFor: v }))}>
                <SelectTrigger className="h-10"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value={NONE}>None</SelectItem>
                  {DEFAULT_FOR_OPTIONS.map((d) => <SelectItem key={d} value={d}>{DEFAULT_FOR_LABELS[d] ?? d}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="flex items-center gap-2">
              <Checkbox id="allowNegative" checked={form.allowNegative} onCheckedChange={(v) => setForm((f) => ({ ...f, allowNegative: v === true }))} />
              <Label htmlFor="allowNegative" className="font-normal">Allow negative balance</Label>
            </div>
            {editing && (
              <div className="flex items-center gap-2">
                <Checkbox id="isActive" checked={form.isActive} onCheckedChange={(v) => setForm((f) => ({ ...f, isActive: v === true }))} />
                <Label htmlFor="isActive" className="font-normal">Active</Label>
              </div>
            )}
            <div className="space-y-1.5">
              <Label>Notes</Label>
              <Input className="h-10" placeholder="Optional" value={form.notes} onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} />
            </div>
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setFormOpen(false)} disabled={saving}>Cancel</Button>
            <Button className="bg-rose-600 hover:bg-rose-700" onClick={handleSaveAccount} disabled={saving}>
              {saving ? "Saving..." : editing ? "Save changes" : "Create account"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Ledger */}
      <Dialog open={!!ledgerAccount} onOpenChange={(o) => { if (!o) setLedgerAccount(null) }}>
        <DialogContent className="sm:max-w-3xl max-h-[92vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Ledger — {ledgerAccount?.name}</DialogTitle>
            <DialogDescription>Current balance {gh(ledgerAccount?.currentBalance ?? 0)}. Newest first.</DialogDescription>
          </DialogHeader>
          <div className="flex flex-wrap items-end gap-3">
            <div className="space-y-1">
              <Label className="text-xs text-muted-foreground">From</Label>
              <Input type="date" className="h-9 w-40" value={ledgerFrom} onChange={(e) => setLedgerFrom(e.target.value)} />
            </div>
            <div className="space-y-1">
              <Label className="text-xs text-muted-foreground">To</Label>
              <Input type="date" className="h-9 w-40" value={ledgerTo} onChange={(e) => setLedgerTo(e.target.value)} />
            </div>
            <Button variant="outline" size="sm" className="h-9" disabled={ledgerLoading}
              onClick={() => { if (ledgerAccount) void loadLedger(ledgerAccount, ledgerFrom, ledgerTo) }}>
              {ledgerLoading ? "Loading..." : "Load"}
            </Button>
          </div>
          {ledgerLoading ? (
            <p className="py-8 text-center text-sm text-muted-foreground">Loading...</p>
          ) : ledgerRows.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted-foreground">No entries in this period.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm min-w-[640px]">
                <thead className="bg-gray-50 border-b">
                  <tr>
                    <th className="text-left p-2">Date</th>
                    <th className="text-left p-2">What</th>
                    <th className="text-left p-2">Description</th>
                    <th className="text-right p-2">Amount</th>
                    <th className="text-right p-2">Balance</th>
                  </tr>
                </thead>
                <tbody>
                  {ledgerRows.map((r) => (
                    <tr key={r.cashTxnId} className="border-b">
                      <td className="p-2 text-xs text-muted-foreground whitespace-nowrap">{(r.txnDate ?? "").slice(0, 10)}</td>
                      <td className="p-2 whitespace-nowrap">{ledgerSourceLabel(r.sourceType)}</td>
                      <td className="p-2 text-xs text-gray-600">{r.description || "—"}</td>
                      <td className={`p-2 text-right font-medium whitespace-nowrap ${r.amount >= 0 ? "text-green-600" : "text-red-600"}`}>
                        {r.amount >= 0 ? "+" : "−"}{gh(Math.abs(r.amount))}
                      </td>
                      <td className={`p-2 text-right whitespace-nowrap ${r.runningBalance < 0 ? "text-red-600" : ""}`}>{gh(r.runningBalance)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => setLedgerAccount(null)}>Close</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Count */}
      <Dialog open={!!countAccount} onOpenChange={(o) => { if (!o && !countSaving) setCountAccount(null) }}>
        <DialogContent className="sm:max-w-md max-h-[92vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Count — {countAccount?.name}</DialogTitle>
            <DialogDescription>Count the cash (or check the statement) and enter what is really there. Any difference is posted to the ledger.</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="rounded-lg bg-gray-50 border p-3 flex items-center justify-between">
              <span className="text-sm text-muted-foreground">System balance</span>
              <span className="font-semibold">{gh(countAccount?.currentBalance ?? 0)}</span>
            </div>
            <div className="space-y-1.5">
              <Label>Counted / confirmed balance <span className="text-rose-500">*</span></Label>
              <Input type="number" inputMode="decimal" step="0.01" className="h-10" value={counted} onChange={(e) => setCounted(e.target.value)} />
            </div>
            {countDiff !== null && (
              <div className={`text-sm font-medium ${countDiff > 0 ? "text-green-600" : countDiff < 0 ? "text-red-600" : "text-gray-700"}`}>
                {countDiff === 0 ? "Balances exactly." : `${gh(Math.abs(countDiff))} ${countDiff > 0 ? "over" : "short"}`}
              </div>
            )}
            <div className="space-y-1.5">
              <Label>Notes</Label>
              <Input className="h-10" placeholder="Optional" value={countNotes} onChange={(e) => setCountNotes(e.target.value)} />
            </div>
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setCountAccount(null)} disabled={countSaving}>Cancel</Button>
            <Button className="bg-rose-600 hover:bg-rose-700" onClick={handlePostCount} disabled={countSaving || !Number.isFinite(countedNum)}>
              {countSaving ? "Posting..." : "Post count"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Reverse count */}
      <Dialog open={!!reverseTarget} onOpenChange={(o) => { if (!o && !reversing) setReverseTarget(null) }}>
        <DialogContent className="sm:max-w-md max-h-[92vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Reverse count</DialogTitle>
            <DialogDescription>
              {reverseTarget ? `${reverseTarget.accountName}, ${(reverseTarget.countDate ?? "").slice(0, 10)} — the difference of ${gh(reverseTarget.difference)} will be undone.` : ""}
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-1.5">
            <Label>Reason <span className="text-rose-500">*</span></Label>
            <Input className="h-10" required placeholder="e.g. Miscounted" value={reverseReason} onChange={(e) => setReverseReason(e.target.value)} />
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setReverseTarget(null)} disabled={reversing}>Cancel</Button>
            <Button className="bg-rose-600 hover:bg-rose-700" onClick={handleReverseCount} disabled={reversing || !reverseReason.trim()}>
              {reversing ? "Reversing..." : "Reverse"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
