"use client"

// Cash Reconciliation for Generic businesses.
// Pick an account, count it, post the difference as an adjustment.

import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { NumberInput } from "@/components/ui/number-input"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip"
import { Scale, ArrowLeft, Loader2, RefreshCw, AlertTriangle, Info } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import {
  getCashAccounts, getCashAccountDetails, getCashReconciliations, createCashReconciliation,
  type GenericCashAccount, type GenericCashAccountDetails, type GenericCashReconciliation,
} from "@/lib/api/generic"

const fmtDate = (d?: string | null) => (d ? String(d).slice(0, 10) : "\u2014")

function daysSince(iso: string | null | undefined): string | undefined {
  if (!iso) return undefined
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return undefined
  const days = Math.floor((Date.now() - d.getTime()) / 86_400_000)
  if (days === 0) return "Today"
  if (days === 1) return "1 day ago"
  return `${days} days ago`
}

export default function GenericCashReconciliationPage() {
  const router = useRouter()
  const { toast } = useToast()
  const fmt = useFmt()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [accounts, setAccounts] = useState<GenericCashAccount[]>([])
  const [details, setDetails] = useState<GenericCashAccountDetails | null>(null)
  const [reconciliations, setReconciliations] = useState<GenericCashReconciliation[]>([])
  const [accountId, setAccountId] = useState<number | null>(null)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState("")
  const [formOpen, setFormOpen] = useState(false)

  // Form state
  const [actualBalance, setActualBalance] = useState(0)
  const [reason, setReason] = useState("")
  const [notes, setNotes] = useState("")

  const loadAccounts = useCallback(async () => {
    setError("")
    try {
      const accs = await getCashAccounts()
      setAccounts(accs)
      return accs
    } catch (e: any) {
      setError(e?.message ?? String(e))
      return []
    }
  }, [])

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    setLoading(true)
    void loadAccounts().then((accs) => {
      setAccountId((current) => {
        if (current != null) return current
        return accs.find((a) => a.isActive)?.genericCashAccountId ?? accs[0]?.genericCashAccountId ?? null
      })
    }).finally(() => setLoading(false))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router, loadAccounts])

  const loadDetails = useCallback(async (id: number | null) => {
    if (id == null) { setDetails(null); setReconciliations([]); return }
    try {
      const [d, r] = await Promise.all([
        getCashAccountDetails(id),
        getCashReconciliations(id),
      ])
      setDetails(d)
      setReconciliations(r ?? [])
    } catch {
      setDetails(null)
      setReconciliations([])
    }
  }, [])

  useEffect(() => { void loadDetails(accountId) }, [accountId, loadDetails])

  const account = useMemo(
    () => accounts.find((a) => a.genericCashAccountId === accountId) ?? null,
    [accounts, accountId],
  )

  const systemBalance = details?.ledgerBalance ?? account?.currentBalance ?? 0

  async function refreshAll() {
    await loadAccounts()
    await loadDetails(accountId)
  }

  function openReconcile() {
    setActualBalance(0)
    setReason("")
    setNotes("")
    setFormOpen(true)
  }

  async function submitReconciliation() {
    if (accountId == null) return
    setBusy(true)
    try {
      const res = await createCashReconciliation({
        genericCashAccountId: accountId,
        actualBalance,
        reason: reason || null,
        notes: notes || null,
      })
      const diff = actualBalance - systemBalance
      toast({
        title: diff === 0 ? "Balanced" : "Cash count posted",
        description: diff === 0
          ? "The count matched the system balance, so no adjustment was needed."
          : `An adjustment of ${fmt(diff)} has been posted.`,
      })
      setFormOpen(false)
      await refreshAll()
    } catch (e: any) {
      toast({ title: "Reconciliation failed", description: e?.message, variant: "destructive" })
    } finally { setBusy(false) }
  }

  const pg = usePagination(reconciliations)
  const variance = actualBalance - systemBalance

  return (
    <TooltipProvider delayDuration={200}>
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-3 md:p-4">
          <div className="mb-2">
            <Button asChild variant="ghost" size="sm" className="-ml-2 text-slate-600">
              <Link href="/generic-cash"><ArrowLeft className="h-4 w-4 mr-1" /> Back to Cash &amp; Accounts</Link>
            </Button>

            <div className="mt-0.5">
              <h1 className="text-xl font-semibold text-slate-900 flex items-center gap-2">
                <Scale className="h-5 w-5 text-sky-600" />
                Reconciliation
              </h1>
              <p className="mt-1 text-xs text-slate-500 max-w-3xl">
                Check what an account actually holds against what the system says. The difference is
                posted as an adjustment — balances are never edited directly.
              </p>
            </div>

            <div className="mt-3 rounded-lg border border-slate-200 bg-white p-3">
              <div className="flex flex-wrap items-end gap-3">
                {accounts.length > 0 && (
                  <div className="min-w-0 flex-1 sm:flex-none">
                    <label htmlFor="reconcile-account"
                           className="text-[11px] font-semibold uppercase tracking-wide text-slate-500">
                      Account to reconcile
                    </label>
                    <Select
                      value={accountId != null ? String(accountId) : ""}
                      onValueChange={(v) => setAccountId(Number(v))}
                    >
                      <SelectTrigger id="reconcile-account"
                                     className="mt-1 h-11 w-full text-base font-medium sm:w-[26rem]">
                        <SelectValue placeholder="Pick an account to reconcile" />
                      </SelectTrigger>
                      <SelectContent>
                        {accounts.map((a) => (
                          <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>
                            {a.accountName}{a.isActive ? "" : " (inactive)"}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                )}
                <div className="grid w-full grid-cols-2 gap-2 sm:ml-auto sm:flex sm:w-auto">
                  <Button size="sm" variant="outline" className="h-10 sm:h-9"
                    onClick={() => { setLoading(true); void refreshAll().finally(() => setLoading(false)) }}>
                    <RefreshCw className="h-4 w-4 mr-1" /> Refresh
                  </Button>
                  {account && (
                    <Button size="sm" className="col-span-2 h-10 w-full whitespace-nowrap sm:col-span-1 sm:h-9 sm:w-auto" onClick={openReconcile}>
                      <Scale className="h-4 w-4 mr-1" />
                      Count &amp; reconcile
                    </Button>
                  )}
                </div>
              </div>
            </div>
          </div>

          <div className="space-y-2">
            {error && <Alert variant="destructive"><AlertDescription>{error}</AlertDescription></Alert>}

            {loading ? (
              <Card><CardContent className="py-12 text-center text-slate-600">Loading cash accounts…</CardContent></Card>
            ) : accounts.length === 0 ? (
              <Card><CardContent className="py-12 text-center text-slate-600">
                No cash accounts yet. Create one under Cash accounts first.
              </CardContent></Card>
            ) : (
              <>
                {account && details && (
                  <>
                    {/* Drift detection */}
                    {details.ledgerBalance !== account.currentBalance && (
                      <Alert className="border-amber-200 bg-amber-50 py-2">
                        <AlertTriangle className="h-4 w-4 text-amber-700" />
                        <AlertDescription className="text-xs text-amber-900">
                          <b>Cache drift detected.</b> The stored balance ({fmt(account.currentBalance)})
                          does not match the ledger total ({fmt(details.ledgerBalance)}).
                          The ledger total is used below. This can happen when a transaction
                          was posted outside the normal flow.
                        </AlertDescription>
                      </Alert>
                    )}

                    <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
                      <Tile label="System balance" value={fmt(systemBalance)}
                            tip="The sum of every transaction on this account\u2019s ledger. This is what the books say the account holds." />
                      <Tile label="Last counted"
                            value={details.lastReconciledAt
                              ? fmtDate(details.lastReconciledAt)
                              : "Never"}
                            hint={details.lastReconciledAt ? daysSince(details.lastReconciledAt) : undefined}
                            tip="When someone last counted and reconciled this account." />
                      <Tile label="Counted then"
                            value={details.lastReconciledBalance != null
                              ? fmt(details.lastReconciledBalance) : "\u2014"}
                            tip="What the count showed last time. The difference between this and the system balance at that moment was posted as an adjustment." />
                      <Tile label="Unreconciled entries"
                            value={String(details.unreconciledCount)}
                            tip="Transactions posted since the last reconciliation. A high number means it has been a while." />
                    </div>

                    <Card>
                      <CardHeader className="pb-2">
                        <CardTitle className="text-base">Reconciliation History</CardTitle>
                        <CardDescription className="text-xs">
                          Each reconciliation posts an adjustment for the difference between the system and the actual count.
                        </CardDescription>
                      </CardHeader>
                      <CardContent className="px-0 lg:px-6">
                        {reconciliations.length === 0 ? (
                          <p className="px-6 py-6 text-center text-sm text-slate-500">
                            No reconciliations recorded yet for this account.
                          </p>
                        ) : (
                          <MobileCardList
                            defaultOpen
                            striped
                            stripeAccent="blue"
                            items={pg.pageItems}
                            pagination={pg.paginationProps}
                            getKey={(c) => c.genericCashReconciliationId}
                            primary={(c) => `#${c.genericCashReconciliationId}`}
                            secondary={(c) => <span className="text-xs">{fmtDate(c.reconciliationDate)}</span>}
                            trailing={(c) => (
                              <Badge variant="outline" className={cn("border-0",
                                c.status === "Approved" ? "bg-green-100 text-green-700" : "bg-slate-100 text-slate-700"
                              )}>{c.status}</Badge>
                            )}
                            highlights={(c) => [
                              { label: "System", value: fmt(c.systemBalance) },
                              { label: "Counted", value: fmt(c.actualBalance), accent: "violet" as const },
                              {
                                label: "Difference",
                                value: c.difference === 0 ? "Balanced" : fmt(c.difference),
                                accent: (c.difference < 0 ? "rose" : "emerald") as "rose" | "emerald",
                                wide: true,
                              },
                            ]}
                            details={(c) => [{ label: "Reason", value: c.reason ?? "—" }]}
                            desktopTable={
                              <div className="max-h-[28rem] overflow-auto">
                                <Table>
                                  <TableHeader>
                                    <TableRow>
                                      <TableHead>#</TableHead>
                                      <TableHead>Date</TableHead>
                                      <TableHead className="text-right">System</TableHead>
                                      <TableHead className="text-right">Actual</TableHead>
                                      <TableHead className="text-right">Difference</TableHead>
                                      <TableHead>Reason</TableHead>
                                      <TableHead>Status</TableHead>
                                    </TableRow>
                                  </TableHeader>
                                  <TableBody>
                                    {pg.pageItems.map((c) => (
                                      <TableRow key={c.genericCashReconciliationId}>
                                        <TableCell className="font-medium">#{c.genericCashReconciliationId}</TableCell>
                                        <TableCell className="whitespace-nowrap">{fmtDate(c.reconciliationDate)}</TableCell>
                                        <TableCell className="text-right tabular-nums">{fmt(c.systemBalance)}</TableCell>
                                        <TableCell className="text-right tabular-nums">{fmt(c.actualBalance)}</TableCell>
                                        <TableCell className={cn("text-right tabular-nums font-medium",
                                                                 c.difference === 0 ? "text-slate-500"
                                                                 : c.difference > 0 ? "text-emerald-700" : "text-rose-700")}>
                                          {c.difference === 0 ? "Balanced" : fmt(c.difference)}
                                        </TableCell>
                                        <TableCell className="text-slate-600">{c.reason ?? "—"}</TableCell>
                                        <TableCell>
                                          <Badge variant="outline" className={cn("border-0",
                                            c.status === "Approved" ? "bg-green-100 text-green-700" : "bg-slate-100 text-slate-700"
                                          )}>{c.status}</Badge>
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
                  </>
                )}
              </>
            )}
          </div>
        </main>
      </div>

      {/* Reconciliation form dialog */}
      <Dialog open={formOpen} onOpenChange={setFormOpen}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Scale className="h-5 w-5 text-sky-600" />
              Count &amp; reconcile
            </DialogTitle>
            <DialogDescription>
              {account?.accountName ?? ""} — enter the actual balance you counted. The difference
              will be posted as an adjustment.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4">
            <div className="rounded-md bg-slate-50 p-3">
              <div className="text-xs text-slate-500">System balance</div>
              <div className="text-lg font-semibold tabular-nums">{fmt(systemBalance)}</div>
            </div>

            <div className="space-y-1">
              <Label>Actual balance counted *</Label>
              <NumberInput step="0.01" value={actualBalance}
                           onChange={(e) => setActualBalance(Number(e.target.value) || 0)} />
            </div>

            {actualBalance > 0 && (
              <div className={cn("rounded-md p-3 text-sm",
                variance === 0 ? "bg-emerald-50 text-emerald-800"
                : variance > 0 ? "bg-emerald-50 text-emerald-800"
                : "bg-rose-50 text-rose-800")}>
                {variance === 0
                  ? "Balanced — no adjustment needed."
                  : <>Difference: <strong className="tabular-nums">{fmt(variance)}</strong> ({variance > 0 ? "surplus" : "shortage"})</>}
              </div>
            )}

            <div className="space-y-1">
              <Label>Reason</Label>
              <Input value={reason} onChange={(e) => setReason(e.target.value)}
                     placeholder="e.g. End of day count, Monthly reconciliation" />
            </div>

            <div className="space-y-1">
              <Label>Notes</Label>
              <Input value={notes} onChange={(e) => setNotes(e.target.value)}
                     placeholder="Any additional notes" />
            </div>

            <div className="flex flex-col-reverse gap-2 pt-2 sm:flex-row sm:justify-end">
              <Button variant="outline" onClick={() => setFormOpen(false)}>Cancel</Button>
              <Button disabled={busy} onClick={submitReconciliation}>
                {busy && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}
                Post reconciliation
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
    </TooltipProvider>
  )
}

function Tile({ label, value, hint, tip }: { label: string; value: string; hint?: string; tip?: string }) {
  return (
    <Card>
      <CardContent className="p-3">
        <div className="flex items-center gap-1 text-[11px] uppercase tracking-wide text-slate-500">
          <span className="truncate">{label}</span>
          {tip && (
            <Tooltip>
              <TooltipTrigger asChild>
                <button type="button" className="ml-auto shrink-0 text-slate-400 hover:text-slate-600">
                  <Info className="h-3.5 w-3.5" />
                </button>
              </TooltipTrigger>
              <TooltipContent className="max-w-xs text-xs leading-snug">{tip}</TooltipContent>
            </Tooltip>
          )}
        </div>
        <div className="mt-1 text-lg font-semibold tabular-nums text-slate-900">{value}</div>
        {hint && <div className="text-[11px] text-slate-500">{hint}</div>}
      </CardContent>
    </Card>
  )
}
