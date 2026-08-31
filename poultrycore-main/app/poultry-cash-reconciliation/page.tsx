"use client"

export const dynamic = "force-dynamic"

/**
 * Reconcile cash — pick an account, count it, post the difference.
 *
 * The reconciliation work used to sit inside the account detail page. It has its
 * own page because it is a task rather than a property of one record: you arrive
 * wanting to check the money, not wanting to look at an account.
 *
 * Two different jobs live here on purpose, and the page is careful to keep them
 * apart, because their names collide in this codebase:
 *
 *   Cash count  — reality disagrees with the books. Someone counts the drawer,
 *                 the difference is posted as a real adjustment transaction.
 *   Recalculate — the books disagree with themselves. `currentbalance` is a
 *                 stored cache maintained by hand in every posting SP, so it can
 *                 drift; this rebuilds it from the ledger and moves no money.
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
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { Scale, RefreshCw, Undo2, ExternalLink, AlertTriangle, ArrowLeft, Pencil, Trash2, RotateCcw, Check } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import { CashCountForm } from "@/components/cash/cash-count-form"
import { cashAccountVocabulary } from "@/components/cash/cash-account-vocabulary"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import {
  listPoultryCashAccounts, getPoultryCashAccountCountStatus, listPoultryCashCountsForAccount,
  createPoultryCashCount, updatePoultryCashCount, deletePoultryCashCount,
  postPoultryCashCount, reversePoultryCashCount, reconcilePoultryCashBalances,
  POULTRY_CASH_REASONS, POULTRY_CASH_REVERSAL_REASONS,
  type PoultryCashAccount, type PoultryCashAccountCountStatus, type PoultryCashCount,
} from "@/lib/api/poultry-finance"

const COUNT_BADGE: Record<string, string> = {
  Draft: "bg-slate-100 text-slate-700",
  Posted: "bg-green-100 text-green-700",
  Reversed: "bg-amber-100 text-amber-700",
}

function PoultryCashReconciliationPageInner() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const { toast } = useToast()
  const gh = useFmt()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [accounts, setAccounts] = useState<PoultryCashAccount[]>([])
  const [status, setStatus] = useState<PoultryCashAccountCountStatus[]>([])
  const [counts, setCounts] = useState<PoultryCashCount[]>([])
  const [accountId, setAccountId] = useState<number | null>(null)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState("")
  const [reverseTarget, setReverseTarget] = useState<PoultryCashCount | null>(null)
  const [discardTarget, setDiscardTarget] = useState<PoultryCashCount | null>(null)
  const [formOpen, setFormOpen] = useState(false)
  /**
   * What the form is working on.
   *
   *   null   — a fresh count for the selected account.
   *   draft  — an unfinished count is being corrected. Submitting UPDATEs that
   *            record and posts it, so the one-open-draft index is satisfied
   *            rather than fought.
   *   copy   — a reversed count is being taken again. Submitting CREATEs a NEW
   *            record seeded from it; the SP refuses to re-post a reversed one,
   *            and rightly so — the ledger is append-only and the reversal is
   *            part of the story.
   */
  const [editing, setEditing] = useState<{ count: PoultryCashCount; mode: "draft" | "copy" } | null>(null)

  const loadAccounts = useCallback(async () => {
    setError("")
    // allSettled: the status feed comes from migration 223. If it has not been
    // applied the accounts list must still render, with the status tiles blank,
    // rather than the page failing whole.
    const [accRes, statusRes] = await Promise.allSettled([
      listPoultryCashAccounts(),
      getPoultryCashAccountCountStatus(),
    ])
    if (accRes.status === "fulfilled") setAccounts(accRes.value)
    else setError(accRes.reason?.message ?? String(accRes.reason))
    setStatus(statusRes.status === "fulfilled" ? statusRes.value : [])
    return accRes.status === "fulfilled" ? accRes.value : []
  }, [])

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    setLoading(true)
    void loadAccounts().then((accs) => {
      setAccountId((current) => {
        if (current != null) return current
        // Arriving from a specific account keeps its context.
        const wanted = Number(searchParams.get("accountId"))
        if (wanted && accs.some((a) => a.poultryCashAccountId === wanted)) return wanted
        return accs.find((a) => a.isActive)?.poultryCashAccountId ?? accs[0]?.poultryCashAccountId ?? null
      })
    }).finally(() => setLoading(false))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router, loadAccounts])

  const loadCounts = useCallback(async (id: number | null) => {
    if (id == null) { setCounts([]); return }
    try { setCounts(await listPoultryCashCountsForAccount(id) ?? []) }
    catch { setCounts([]) }
  }, [])

  useEffect(() => { void loadCounts(accountId) }, [accountId, loadCounts])

  // A count belongs to one account; switching accounts must not leave the form
  // pointed at a record the user can no longer see in the history below.
  useEffect(() => { setEditing(null) }, [accountId])

  const account = useMemo(
    () => accounts.find((a) => a.poultryCashAccountId === accountId) ?? null,
    [accounts, accountId],
  )
  const accountStatus = useMemo(
    () => status.find((s) => s.poultryCashAccountId === accountId) ?? null,
    [status, accountId],
  )

  // What the count is measured against. `currentbalance` is a cache the posting
  // SP does not trust: it heals it from the ledger first, then computes the
  // difference against that truth. Quoting the cache here would show one
  // variance on screen and post another. Falls back to the cache only while the
  // status read is still in flight.
  const systemBalance = accountStatus?.ledgerBalance ?? account?.currentBalance ?? 0

  async function refreshAll() {
    await loadAccounts()
    await loadCounts(accountId)
  }

  /**
   * Apply a saved count to the ledger. This is the only thing on this page that
   * moves money, and it is deliberately separate from saving the count: the
   * draft is the figure someone wrote down, posting is the decision to believe
   * it. The SP re-measures the difference at this moment rather than trusting
   * what the draft recorded, so a posted correction is always against the
   * ledger as it stands now.
   */
  async function postDraft(c: PoultryCashCount) {
    setBusy(true)
    try {
      const res = await postPoultryCashCount(c.poultryCashReconciliationId)
      toast({
        title: res?.adjustmentTransactionId ? "Cash count posted" : "Balanced",
        description: res?.adjustmentTransactionId
          ? "The difference has been posted to the ledger as an adjustment."
          : "The count matched the ledger, so no adjustment was needed.",
      })
      if (editing?.count.poultryCashReconciliationId === c.poultryCashReconciliationId) { setEditing(null); setFormOpen(false) }
      await refreshAll()
    } catch (e: any) {
      toast({ title: "Couldn't post the count", description: e?.message, variant: "destructive" })
    } finally { setBusy(false) }
  }

  /**
   * Open the reconciliation form. An account may hold only one open draft
   * (ux_poultrycashrecon_one_draft), so if one exists this reopens THAT rather
   * than starting a second one that the database would refuse.
   */
  function openReconcile() {
    setEditing(openDraft ? { count: openDraft, mode: "draft" } : null)
    setFormOpen(true)
  }

  async function recalculate() {
    setBusy(true)
    try {
      await reconcilePoultryCashBalances()
      toast({
        title: "Balances recalculated",
        description: "Every cash account's balance was rebuilt from its transactions.",
      })
      await refreshAll()
    } catch (e: any) {
      toast({ title: "Recalculate failed", description: e?.message, variant: "destructive" })
    } finally { setBusy(false) }
  }

  // The database allows exactly one open draft per account, so a count that was
  // created but failed to post blocks every later attempt. Surfacing it is what
  // makes that state escapable instead of a dead end.
  const openDraft = useMemo(
    () => counts.find((c) => c.status === "Draft") ?? null,
    [counts],
  )

  // Derived from the selected account, so every label on this page follows the
  // account picker with no extra wiring. A cash box says "count", a bank
  // account says "statement" — same mechanism underneath.
  const vocab = useMemo(() => cashAccountVocabulary(account?.accountType), [account])

  const drift = accountStatus?.cacheDrift ?? 0
  const hasDrift = Math.abs(drift) >= 0.01

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-3 md:p-4">
          {/* Three lines total: back link; title and blurb sharing a line;
              then one control row — account on the left, actions on the right.
              The picker used to sit alone below this block, which cost a row to
              show a single select. */}
          <div className="mb-2">
            <Button asChild variant="ghost" size="sm" className="-ml-2 text-slate-600">
              <Link href="/poultry-cash-accounts"><ArrowLeft className="h-4 w-4 mr-1" /> Back to Cash &amp; Accounts</Link>
            </Button>

            {/* Description under the title, not beside it. Sharing the line
                saved a row but read as a caption hung off the heading; stacked,
                it reads as the sentence explaining the page. */}
            <div className="mt-0.5">
              <h1 className="text-xl font-semibold text-slate-900 flex items-center gap-2">
                <Scale className="h-5 w-5 text-sky-600" />
                Reconcile cash
              </h1>
              <p className="mt-1 text-xs text-slate-500 max-w-3xl">
                Check what an account actually holds against what the system says. The difference is
                posted as an adjustment — balances are never edited directly.
              </p>
            </div>

            {/* The account picker is the page. Every figure, every button and the
                whole history below answer for whichever account is chosen here,
                so it gets a panel of its own and a full-height trigger rather
                than sitting inline as a small control among the buttons — where
                it read as a filter, which it is not.

                The actions live in the same panel deliberately: they all act on
                the selected account, and separating them would invite the reader
                to think Recalculate or Open ledger meant something company-wide. */}
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
                          <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>
                            {a.accountName}{a.isActive ? "" : " (inactive)"}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                )}
                <div className="flex gap-2 ml-auto">
                  {account && (
                    <Button asChild variant="outline" size="sm" className="whitespace-nowrap">
                      <Link href={`/poultry-cash-accounts/${account.poultryCashAccountId}`}>
                        <ExternalLink className="h-4 w-4 mr-1" /> Open ledger
                      </Link>
                    </Button>
                  )}
                  <Button variant="outline" size="sm" className="whitespace-nowrap"
                          onClick={recalculate} disabled={busy || loading}>
                    <RefreshCw className={cn("h-4 w-4 mr-1", busy && "animate-spin")} />
                    Recalculate
                  </Button>
                  {/* Named for the account, never a bare "Reconcile": the word
                      that follows is the whole point of the vocabulary. */}
                  {account && (
                    <Button size="sm" className="whitespace-nowrap" onClick={openReconcile}>
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
                    {/* Same four-up KPI row the account detail page uses. */}
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

                    {/* Drift is a software problem, not a cash problem, so it
                        must never reach the counter as a "difference". The count
                        is safe — both this page and the posting SP measure against
                        the ledger — but every other screen still reads the cache. */}
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

                    {/* A saved count sits here until someone posts it. One open
                        draft per account is a database rule, so this is also
                        what explains why the form below is locked. */}
                    {openDraft && (
                      <Alert className="border-sky-200 bg-sky-50 py-2">
                        <AlertTriangle className="h-4 w-4 text-sky-700" />
                        <AlertDescription className="text-xs text-sky-900 flex flex-wrap items-center gap-2">
                          <span>
                            {openDraft.referenceNo ?? `#${openDraft.poultryCashReconciliationId}`} is saved but not posted —
                            nothing has reached the ledger yet.
                            {openDraft.actualBalance != null && (
                              <> Counted {gh(openDraft.actualBalance)}.</>
                            )}
                          </span>
                          <Button size="sm" className="h-6 px-2 text-xs" onClick={() => void postDraft(openDraft)}
                                  disabled={busy}>
                            Post it
                          </Button>
                          {editing?.count.poultryCashReconciliationId !== openDraft.poultryCashReconciliationId && (
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

                    {/* History IS the page. The form that writes to it lives in a
                        modal — see the dialog at the foot of this file. */}
                    <Card>
                      <CardHeader className="pb-2">
                        <CardTitle className="text-base">Reconciliation History</CardTitle>
                        <CardDescription className="text-xs">
                          Reversing one posts an opposite adjustment — the original is kept.
                        </CardDescription>
                      </CardHeader>
                        <CardContent>
                          {counts.length === 0 ? (
                            <p className="py-6 text-center text-sm text-slate-500">
                              {vocab.emptyHistory}
                            </p>
                          ) : (
                            // Only this scrolls. Everything else stays on
                            // screen. Raised from 22rem to spend what the
                            // compacted header and tiles gave back: the point of
                            // the tidy-up was more history visible, not more
                            // whitespace.
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
                                {counts.map((c) => (
                                  <TableRow key={c.poultryCashReconciliationId}>
                                    <TableCell className="font-medium">{c.referenceNo ?? `#${c.poultryCashReconciliationId}`}</TableCell>
                                    <TableCell className="whitespace-nowrap">{c.reconciliationDate.split("T")[0]}</TableCell>
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
                                    {/* Draft: correct it or throw it away — those are
                                        the only two ways out of the one-open-draft
                                        lock. Posted: reverse. Reversed: count again,
                                        which seeds a NEW count rather than reviving
                                        this one. */}
                                    <TableCell className="text-right whitespace-nowrap">
                                      {c.status === "Draft" && (
                                        <>
                                          <Button size="sm" variant="ghost" title="Post this count to the ledger"
                                                  onClick={() => void postDraft(c)} disabled={busy}>
                                            <Check className="h-4 w-4 text-emerald-600" />
                                          </Button>
                                          <Button size="sm" variant="ghost" title="Edit this count"
                                                  onClick={() => { setEditing({ count: c, mode: "draft" }); setFormOpen(true) }}>
                                            <Pencil className="h-4 w-4 text-sky-600" />
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
                                          <RotateCcw className="h-4 w-4 text-sky-600" />
                                        </Button>
                                      )}
                                    </TableCell>
                                  </TableRow>
                                ))}
                              </TableBody>
                            </Table>
                            </div>
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

      {/* The reconciliation form. A modal because the history is what the page
          is for; the form is something you do TO it and then dismiss. */}
      <Dialog open={formOpen} onOpenChange={(o) => { setFormOpen(o); if (!o) setEditing(null) }}>
        {/* Matches the Adjust balance dialog on the cash account page: icon in
            the title, one-line description, coloured FormSection bands inside,
            ghost Cancel beside the primary action. */}
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Scale className="h-5 w-5 text-sky-600" />
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
              // Changing this re-seeds the fields, so it has to name the exact
              // record being worked on.
              resetKey={editing ? `${editing.mode}-${editing.count.poultryCashReconciliationId}` : `new-${account.poultryCashAccountId}`}
              initial={editing ? {
                actualBalance: editing.count.actualBalance,
                reason: editing.count.reason,
                notes: editing.count.notes,
                reconciliationDate: editing.mode === "draft" ? editing.count.reconciliationDate : null,
              } : null}
              intent="draft"
              // Only reachable by taking a reversed record again while a draft
              // is already open — one open draft per account is a database rule,
              // so saving could only fail. The banner on the page says why.
              disabled={!!openDraft && editing?.count.poultryCashReconciliationId !== openDraft.poultryCashReconciliationId}
              onCancel={() => { setFormOpen(false); setEditing(null) }}
              systemBalance={systemBalance}
              reasons={POULTRY_CASH_REASONS}
              fmtMoney={gh}
              onSubmit={async (input) => {
                // Saves only. Posting is the banner's button and the history
                // row's tick — see postDraft().
                const fields = {
                  reconciliationDate: input.reconciliationDate,
                  actualBalance: input.actualBalance,
                  reason: input.reason,
                  notes: input.notes,
                }
                if (editing?.mode === "draft") {
                  await updatePoultryCashCount(editing.count.poultryCashReconciliationId, fields)
                } else {
                  await createPoultryCashCount({ poultryCashAccountId: account.poultryCashAccountId, ...fields })
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
          await deletePoultryCashCount(discardTarget.poultryCashReconciliationId)
          if (editing?.count.poultryCashReconciliationId === discardTarget.poultryCashReconciliationId) setEditing(null)
          setDiscardTarget(null)
          await refreshAll()
        }}
      />

      {/* Reversal reason is PICKED, not typed. It lands in reversalreason,
          which is what an audit reads to understand why a posted count was
          undone — free text there degrades to "mistake", "wrong" and blanks
          within a month. "Other" still opens a box, so the list never forces
          someone into the nearest wrong answer. */}
      <PromptDialog
        open={!!reverseTarget}
        onOpenChange={(o) => { if (!o) setReverseTarget(null) }}
        title="Reverse this cash count?"
        description="An opposite adjustment is posted, the original entries are kept, and anything this count marked as cleared goes back to uncleared."
        label="Reason for reversal"
        options={POULTRY_CASH_REVERSAL_REASONS}
        placeholder="Why is this count being reversed?"
        confirmLabel="Reverse"
        confirmVariant="destructive"
        onSubmit={async (reason: string) => {
          if (!reverseTarget) return
          try {
            await reversePoultryCashCount(reverseTarget.poultryCashReconciliationId, reason)
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

/** The account detail page's KPI card, with an optional second line. */
/**
 * Compact KPI card. Deliberately smaller than the account detail page's: four
 * of these sit above the count form and the history table, and at p-4/text-xl
 * they pushed the actual work below the fold. The figures are read at a glance,
 * not studied, so they do not need the extra weight.
 */
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

// useSearchParams needs a Suspense boundary to prerender; the house pattern
// pairs it with the force-dynamic above (see app/generic-expenses/page.tsx).
export default function PoultryCashReconciliationPage() {
  return (
    <Suspense fallback={<div className="p-6 text-slate-500">Loading...</div>}>
      <PoultryCashReconciliationPageInner />
    </Suspense>
  )
}
