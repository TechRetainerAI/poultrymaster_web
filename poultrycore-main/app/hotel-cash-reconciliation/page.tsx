"use client"

export const dynamic = "force-dynamic"

/**
 * Hotel Reconciliation — Poultry's /poultry-cash-reconciliation, word for word,
 * in violet: pick an account, count it, post the difference (migration 331).
 *
 *   Cash count  — reality disagrees with the books. The count is saved as a
 *                 draft; posting it writes the difference as one adjustment.
 *   Recalculate — the books disagree with themselves: rebuilds the stored
 *                 balance from the ledger and moves no money.
 */

import { Suspense, useCallback, useEffect, useMemo, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Badge } from "@/components/ui/badge"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { Scale, RefreshCw, Undo2, AlertTriangle, ArrowLeft, Pencil, Trash2, RotateCcw, Check } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import { CashCountForm } from "@/components/cash/cash-count-form"
import { cashAccountVocabulary } from "@/components/cash/cash-account-vocabulary"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { fmtDateTime } from "@/lib/utils/company-datetime"
import {
  listHotelMoneyAccounts, getHotelCashAccountStatus, listHotelCashCounts,
  createHotelCashCount, updateHotelCashCount, deleteHotelCashCount,
  postHotelCashCount, reverseHotelCashCount, recalculateHotelCashBalances, hotelVocabularyType,
  HOTEL_CASH_REASONS, HOTEL_CASH_REVERSAL_REASONS,
  type HotelMoneyAccount, type HotelCashAccountStatus, type HotelCashCount,
} from "@/lib/api/hotel-money"

const COUNT_BADGE: Record<string, string> = {
  Draft: "bg-slate-100 text-slate-700",
  Posted: "bg-green-100 text-green-700",
  Reversed: "bg-amber-100 text-amber-700",
}

function HotelCashReconciliationPageInner() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const { toast } = useToast()
  const gh = useFmt()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [accounts, setAccounts] = useState<HotelMoneyAccount[]>([])
  const [status, setStatus] = useState<HotelCashAccountStatus[]>([])
  const [counts, setCounts] = useState<HotelCashCount[]>([])
  const [accountId, setAccountId] = useState<number | null>(null)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState("")
  const [reverseTarget, setReverseTarget] = useState<HotelCashCount | null>(null)
  const [discardTarget, setDiscardTarget] = useState<HotelCashCount | null>(null)
  const [formOpen, setFormOpen] = useState(false)
  const [editing, setEditing] = useState<{ count: HotelCashCount; mode: "draft" | "copy" } | null>(null)

  const loadAccounts = useCallback(async () => {
    setError("")
    const [accRes, statusRes] = await Promise.allSettled([
      listHotelMoneyAccounts(),
      getHotelCashAccountStatus(),
    ])
    if (accRes.status === "fulfilled") setAccounts(accRes.value)
    else setError(accRes.reason?.message ?? String(accRes.reason))
    setStatus(statusRes.status === "fulfilled" ? statusRes.value : [])
    return accRes.status === "fulfilled" ? accRes.value : []
  }, [])

  useEffect(() => {
    if (!activeFarmType) return
    if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    setLoading(true)
    void loadAccounts().then((accs) => {
      setAccountId((current) => {
        if (current != null) return current
        const wanted = Number(searchParams.get("accountId"))
        if (wanted && accs.some((a) => a.hotelCashAccountId === wanted)) return wanted
        return accs.find((a) => a.isActive)?.hotelCashAccountId ?? accs[0]?.hotelCashAccountId ?? null
      })
    }).finally(() => setLoading(false))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router, loadAccounts])

  const loadCounts = useCallback(async (id: number | null) => {
    if (id == null) { setCounts([]); return }
    try { setCounts(await listHotelCashCounts(id) ?? []) }
    catch { setCounts([]) }
  }, [])

  useEffect(() => { void loadCounts(accountId) }, [accountId, loadCounts])
  useEffect(() => { setEditing(null) }, [accountId])

  const account = useMemo(
    () => accounts.find((a) => a.hotelCashAccountId === accountId) ?? null,
    [accounts, accountId],
  )
  const accountStatus = useMemo(
    () => status.find((s) => s.hotelCashAccountId === accountId) ?? null,
    [status, accountId],
  )

  // Measured against the ledger, exactly as the posting function measures it.
  const systemBalance = accountStatus?.ledgerBalance ?? account?.currentBalance ?? 0

  async function refreshAll() {
    await loadAccounts()
    await loadCounts(accountId)
  }

  async function postDraft(c: HotelCashCount) {
    setBusy(true)
    try {
      const res = await postHotelCashCount(c.hotelCashReconciliationId)
      toast({
        title: res?.adjustmentTransactionId ? "Cash count posted" : "Balanced",
        description: res?.adjustmentTransactionId
          ? "The difference has been posted to the ledger as an adjustment."
          : "The count matched the ledger, so no adjustment was needed.",
      })
      if (editing?.count.hotelCashReconciliationId === c.hotelCashReconciliationId) { setEditing(null); setFormOpen(false) }
      await refreshAll()
    } catch (e: any) {
      toast({ title: "Couldn't post the count", description: e?.message, variant: "destructive" })
    } finally { setBusy(false) }
  }

  const openDraft = useMemo(
    () => counts.find((c) => c.status === "Draft") ?? null,
    [counts],
  )

  function openReconcile() {
    setEditing(openDraft ? { count: openDraft, mode: "draft" } : null)
    setFormOpen(true)
  }

  async function recalculate() {
    setBusy(true)
    try {
      await recalculateHotelCashBalances()
      toast({
        title: "Balances recalculated",
        description: "Every cash account's balance was rebuilt from its transactions.",
      })
      await refreshAll()
    } catch (e: any) {
      toast({ title: "Recalculate failed", description: e?.message, variant: "destructive" })
    } finally { setBusy(false) }
  }

  const vocab = useMemo(() => cashAccountVocabulary(hotelVocabularyType(account?.accountType)), [account])

  const drift = accountStatus?.cacheDrift ?? 0
  const hasDrift = Math.abs(drift) >= 0.01

  const pg = usePagination(counts)

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-3 md:p-4">
          <div className="mb-2">
            <Button asChild variant="ghost" size="sm" className="-ml-2 text-slate-600">
              <Link href="/hotel-cash-accounts"><ArrowLeft className="h-4 w-4 mr-1" /> Back to Cash &amp; Accounts</Link>
            </Button>

            <div className="mt-0.5">
              <h1 className="text-xl font-semibold text-slate-900 flex items-center gap-2">
                <Scale className="h-5 w-5 text-violet-600" />
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
                          <SelectItem key={a.hotelCashAccountId} value={String(a.hotelCashAccountId)}>
                            {a.accountName}{a.isActive ? "" : " (inactive)"}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                )}
                <div className="grid w-full grid-cols-2 gap-2 sm:ml-auto sm:flex sm:w-auto">
                  <Button variant="outline" size="sm" className="h-10 w-full whitespace-nowrap sm:h-9 sm:w-auto"
                          onClick={recalculate} disabled={busy || loading}>
                    <RefreshCw className={cn("h-4 w-4 mr-1", busy && "animate-spin")} />
                    Recalculate
                  </Button>
                  {account && (
                    <Button size="sm" className="h-10 w-full whitespace-nowrap sm:h-9 sm:w-auto bg-violet-600 hover:bg-violet-700"
                            onClick={openReconcile}>
                      <Scale className="h-4 w-4 mr-1" />
                      {openDraft ? `Finish ${openDraft.referenceNo ?? vocab.recordNoun}` : vocab.action}
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
                {account && (
                  <>
                    <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
                      <Tile label="System balance" value={gh(systemBalance)}
                            hint={hasDrift ? "rebuilt from transactions" : undefined} />
                      <Tile label="Last counted"
                            value={accountStatus?.lastReconciledAt
                              ? accountStatus.lastReconciledAt.split("T")[0]
                              : "Never"}
                            hint={accountStatus?.daysSinceReconciled != null
                              ? `${accountStatus.daysSinceReconciled} days ago` : undefined} />
                      <Tile label="Counted then"
                            value={accountStatus?.lastReconciledBalance != null
                              ? gh(accountStatus.lastReconciledBalance) : "—"} />
                      <Tile label="Uncleared entries"
                            value={accountStatus ? String(accountStatus.unclearedCount) : "—"}
                            hint={accountStatus && accountStatus.unclearedCount > 0
                              ? gh(accountStatus.unclearedAmount) : undefined} />
                    </div>

                    {hasDrift && (
                      <Alert className="border-amber-200 bg-amber-50 py-2">
                        <AlertTriangle className="h-4 w-4 text-amber-700" />
                        <AlertDescription className="text-xs text-amber-900">
                          The stored balance for this account is {gh(Math.abs(drift))} away from what
                          its transactions add up to. The reconciliation uses the transactions, so it
                          is safe to post — but other screens will show the stale figure until you
                          recalculate.
                        </AlertDescription>
                      </Alert>
                    )}

                    {openDraft && (
                      <Alert className="border-violet-200 bg-violet-50 py-2">
                        <AlertTriangle className="h-4 w-4 text-violet-700" />
                        <AlertDescription className="text-xs text-violet-900 flex flex-wrap items-center gap-2">
                          <span>
                            {openDraft.referenceNo ?? `#${openDraft.hotelCashReconciliationId}`} is saved but not posted —
                            nothing has reached the ledger yet.
                            {openDraft.actualBalance != null && (
                              <> Counted {gh(openDraft.actualBalance)}.</>
                            )}
                          </span>
                          <Button size="sm" className="h-6 px-2 text-xs bg-violet-600 hover:bg-violet-700"
                                  onClick={() => void postDraft(openDraft)} disabled={busy}>
                            Post it
                          </Button>
                          {editing?.count.hotelCashReconciliationId !== openDraft.hotelCashReconciliationId && (
                            <Button size="sm" variant="outline" className="h-6 px-2 text-xs"
                                    onClick={() => { setEditing({ count: openDraft, mode: "draft" }); setFormOpen(true) }}>
                              Edit
                            </Button>
                          )}
                          <Button size="sm" variant="outline" className="h-6 px-2 text-xs"
                                  onClick={() => setDiscardTarget(openDraft)}>
                            Discard
                          </Button>
                        </AlertDescription>
                      </Alert>
                    )}

                    <Card>
                      <CardHeader className="pb-2">
                        <CardTitle className="text-base">Reconciliation History</CardTitle>
                        <CardDescription className="text-xs">
                          Reversing one posts an opposite adjustment — the original is kept.
                        </CardDescription>
                      </CardHeader>
                      <CardContent className="px-0 lg:px-6">
                        {counts.length === 0 ? (
                          <p className="px-6 py-6 text-center text-sm text-slate-500">
                            {vocab.emptyHistory}
                          </p>
                        ) : (
                          <MobileCardList
                            defaultOpen
                            striped
                            stripeAccent="blue"
                            items={pg.pageItems}
                            pagination={{ ...pg.paginationProps, variant: "records" }}
                            getKey={(c) => c.hotelCashReconciliationId}
                            primary={(c) => c.referenceNo ?? `#${c.hotelCashReconciliationId}`}
                            secondary={(c) => <span className="text-xs">{fmtDateTime(c.reconciliationDate, c)}</span>}
                            trailing={(c) => (
                              <Badge variant="outline" className={cn("border-0", COUNT_BADGE[c.status])}>{c.status}</Badge>
                            )}
                            highlights={(c) => [
                              { label: "System", value: gh(c.systemBalance) },
                              { label: "Counted", value: c.actualBalance != null ? gh(c.actualBalance) : "—", accent: "violet" },
                              {
                                label: "Difference",
                                value: c.difference === 0 ? "Balanced" : gh(c.difference),
                                accent: c.difference < 0 ? "rose" : "emerald",
                                wide: true,
                              },
                            ]}
                            details={(c) => [{ label: "Reason", value: c.reason ?? "—" }]}
                            actions={(c) => (
                              <>
                                {c.status === "Draft" && (
                                  <>
                                    <Button size="sm" variant="outline" className="h-10 flex-1 bg-white text-emerald-700 border-emerald-200 hover:bg-emerald-50"
                                            onClick={(e) => { e.stopPropagation(); void postDraft(c) }} disabled={busy}>
                                      <Check className="mr-2 h-4 w-4" /> Post
                                    </Button>
                                    <Button size="sm" variant="outline" className="h-10 flex-1 bg-white text-violet-700 border-violet-200 hover:bg-violet-50"
                                            onClick={(e) => { e.stopPropagation(); setEditing({ count: c, mode: "draft" }); setFormOpen(true) }}>
                                      <Pencil className="mr-2 h-4 w-4" /> Edit
                                    </Button>
                                    <Button size="sm" variant="outline" className="h-10 flex-1 bg-white text-rose-600 border-rose-200 hover:bg-rose-50"
                                            onClick={(e) => { e.stopPropagation(); setDiscardTarget(c) }}>
                                      <Trash2 className="mr-2 h-4 w-4" /> Discard
                                    </Button>
                                  </>
                                )}
                                {c.status === "Posted" && (
                                  <Button size="sm" variant="outline" className="h-10 flex-1 bg-white text-amber-700 border-amber-200 hover:bg-amber-50"
                                          onClick={(e) => { e.stopPropagation(); setReverseTarget(c) }}>
                                    <Undo2 className="mr-2 h-4 w-4" /> Reverse
                                  </Button>
                                )}
                                {c.status === "Reversed" && (
                                  <Button size="sm" variant="outline" className="h-10 flex-1 bg-white text-violet-700 border-violet-200 hover:bg-violet-50"
                                          onClick={(e) => { e.stopPropagation(); setEditing({ count: c, mode: "copy" }); setFormOpen(true) }}>
                                    <RotateCcw className="mr-2 h-4 w-4" /> Count again
                                  </Button>
                                )}
                              </>
                            )}
                            desktopTable={
                              <div className="max-h-[28rem] overflow-auto">
                                <Table>
                                  <TableHeader>
                                    <TableRow>
                                      <TableHead>Reference</TableHead>
                                      <TableHead>Date</TableHead>
                                      <TableHead className="text-right">System</TableHead>
                                      <TableHead className="text-right">Actual Balance</TableHead>
                                      <TableHead className="text-right">Difference</TableHead>
                                      <TableHead>Reason</TableHead>
                                      <TableHead>Status</TableHead>
                                      <TableHead className="text-right">Actions</TableHead>
                                    </TableRow>
                                  </TableHeader>
                                  <TableBody>
                                    {pg.pageItems.map((c) => (
                                      <TableRow key={c.hotelCashReconciliationId}>
                                        <TableCell className="font-medium">{c.referenceNo ?? `#${c.hotelCashReconciliationId}`}</TableCell>
                                        <TableCell className="whitespace-nowrap">{fmtDateTime(c.reconciliationDate, c)}</TableCell>
                                        <TableCell className="text-right tabular-nums">{gh(c.systemBalance)}</TableCell>
                                        <TableCell className="text-right tabular-nums">{c.actualBalance != null ? gh(c.actualBalance) : "—"}</TableCell>
                                        <TableCell className={cn("text-right tabular-nums font-medium",
                                                                 c.difference === 0 ? "text-slate-500"
                                                                 : c.difference > 0 ? "text-emerald-700" : "text-rose-700")}>
                                          {c.difference === 0 ? "Balanced" : gh(c.difference)}
                                        </TableCell>
                                        <TableCell className="text-slate-600">{c.reason ?? "—"}</TableCell>
                                        <TableCell>
                                          <Badge variant="outline" className={cn("border-0", COUNT_BADGE[c.status])}>{c.status}</Badge>
                                        </TableCell>
                                        <TableCell className="text-right whitespace-nowrap">
                                          {c.status === "Draft" && (
                                            <>
                                              <Button size="sm" variant="ghost" title="Post this count to the ledger"
                                                      onClick={() => void postDraft(c)} disabled={busy}>
                                                <Check className="h-4 w-4 text-emerald-600" />
                                              </Button>
                                              <Button size="sm" variant="ghost" title="Edit this count"
                                                      onClick={() => { setEditing({ count: c, mode: "draft" }); setFormOpen(true) }}>
                                                <Pencil className="h-4 w-4 text-violet-600" />
                                              </Button>
                                              <Button size="sm" variant="ghost" title="Discard this draft"
                                                      onClick={() => setDiscardTarget(c)}>
                                                <Trash2 className="h-4 w-4 text-rose-600" />
                                              </Button>
                                            </>
                                          )}
                                          {c.status === "Posted" && (
                                            <Button size="sm" variant="ghost" title="Reverse this count"
                                                    onClick={() => setReverseTarget(c)}>
                                              <Undo2 className="h-4 w-4 text-amber-600" />
                                            </Button>
                                          )}
                                          {c.status === "Reversed" && (
                                            <Button size="sm" variant="ghost" title="Count again from this one"
                                                    onClick={() => { setEditing({ count: c, mode: "copy" }); setFormOpen(true) }}>
                                              <RotateCcw className="h-4 w-4 text-violet-600" />
                                            </Button>
                                          )}
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

      <Dialog open={formOpen} onOpenChange={(o) => { setFormOpen(o); if (!o) setEditing(null) }}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Scale className="h-5 w-5 text-violet-600" />
              {editing?.mode === "draft"
                ? `Edit ${editing.count.referenceNo ?? vocab.recordNoun}`
                : editing?.mode === "copy"
                  ? `${vocab.action} again`
                  : vocab.action}
            </DialogTitle>
            <DialogDescription>
              {editing?.mode === "draft"
                ? "Correct the figures. The saved record is updated, not duplicated — posting is a separate step."
                : editing?.mode === "copy"
                  ? `Seeded from ${editing.count.referenceNo ?? "the reversed record"}. This saves a new one; the reversed one stays in the history.`
                  : `${account?.accountName ?? ""} — saving does not move money. You post it after.`}
            </DialogDescription>
          </DialogHeader>
          {account && (
            <CashCountForm
              vocab={vocab}
              sectionColor="purple"
              resetKey={editing ? `${editing.mode}-${editing.count.hotelCashReconciliationId}` : `new-${account.hotelCashAccountId}`}
              initial={editing ? {
                actualBalance: editing.count.actualBalance,
                reason: editing.count.reason,
                notes: editing.count.notes,
                reconciliationDate: editing.mode === "draft" ? editing.count.reconciliationDate : null,
              } : null}
              intent="draft"
              disabled={!!openDraft && editing?.count.hotelCashReconciliationId !== openDraft.hotelCashReconciliationId}
              onCancel={() => { setFormOpen(false); setEditing(null) }}
              systemBalance={systemBalance}
              reasons={HOTEL_CASH_REASONS}
              fmtMoney={gh}
              onSubmit={async (input) => {
                const fields = {
                  reconciliationDate: input.reconciliationDate,
                  actualBalance: input.actualBalance,
                  reason: input.reason,
                  notes: input.notes,
                }
                if (editing?.mode === "draft") {
                  await updateHotelCashCount(editing.count.hotelCashReconciliationId, account.hotelCashAccountId, fields)
                } else {
                  await createHotelCashCount(account.hotelCashAccountId, fields)
                }
                return null
              }}
              onDone={() => { setFormOpen(false); setEditing(null); void refreshAll() }}
            />
          )}
        </DialogContent>
      </Dialog>

      <ConfirmDeleteDialog
        open={!!discardTarget}
        onOpenChange={(o) => { if (!o) setDiscardTarget(null) }}
        title={`Discard ${discardTarget?.referenceNo ?? "this draft"}?`}
        description="Nothing was posted, so no money moves and nothing is reversed. The draft is removed and the account can be counted again."
        confirmLabel="Discard draft"
        errorTitle="Could not discard the draft"
        onConfirm={async () => {
          if (!discardTarget) return
          await deleteHotelCashCount(discardTarget.hotelCashReconciliationId)
          if (editing?.count.hotelCashReconciliationId === discardTarget.hotelCashReconciliationId) setEditing(null)
          setDiscardTarget(null)
          await refreshAll()
        }}
      />

      <PromptDialog
        open={!!reverseTarget}
        onOpenChange={(o) => { if (!o) setReverseTarget(null) }}
        title="Reverse this cash count?"
        description="An opposite adjustment is posted and the original entries are kept."
        label="Reason for reversal"
        options={HOTEL_CASH_REVERSAL_REASONS}
        placeholder="Why is this count being reversed?"
        confirmLabel="Reverse"
        confirmVariant="destructive"
        onSubmit={async (reason: string) => {
          if (!reverseTarget) return
          try {
            await reverseHotelCashCount(reverseTarget.hotelCashReconciliationId, reason)
            toast({ title: "Cash count reversed", description: "The adjustment has been undone." })
            setReverseTarget(null)
            await refreshAll()
          } catch (e: any) {
            toast({ title: "Couldn't reverse", description: e?.message, variant: "destructive" })
          }
        }}
      />
    </div>
  )
}

function Tile({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <Card>
      <CardContent className="p-2.5">
        <div className="text-[11px] leading-tight text-slate-500">{label}</div>
        <div className="text-base font-semibold tabular-nums leading-snug">{value}</div>
        {hint && <div className="text-[10px] leading-tight text-slate-500">{hint}</div>}
      </CardContent>
    </Card>
  )
}

export default function HotelCashReconciliationPage() {
  return (
    <Suspense fallback={<div className="p-6 text-slate-500">Loading...</div>}>
      <HotelCashReconciliationPageInner />
    </Suspense>
  )
}
