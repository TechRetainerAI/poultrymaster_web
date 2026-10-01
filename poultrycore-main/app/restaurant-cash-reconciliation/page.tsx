"use client"

/**
 * Reconciliation — check what the system says against what is really there.
 *
 * The restaurant equivalent of Poultry's and Water's Reconciliation page: a
 * count is saved as a Draft first, and posting it — the only step that moves
 * money — is a separate action (migration 338, wording and card layout from
 * app/poultry-cash-reconciliation). Cash boxes, banks and wallets are counted
 * here (or confirmed against a bank statement); tills are counted when their
 * shift closes on Tills & Shifts. Either way, posting writes the difference to
 * the ledger as over / short, so the account ends at what was counted and
 * Cash Flow and the P&L both see it. The history below shows both kinds
 * together, drafts included.
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
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { AlertTriangle, Check, Loader2, Pencil, Scale, Trash2 } from "lucide-react"
import { PageHeader } from "@/components/restaurant/page-header"
import { MoneyStat } from "@/components/restaurant/money-stat"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { useAuthStore } from "@/lib/store/auth-store"
import { usePermissions } from "@/hooks/use-permissions"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  listCashAccounts, listCounts, listShifts, saveCountDraft, updateCountDraft, discardCountDraft, postCountDraft,
  reverseCount, todayIso, ACCOUNT_TYPE_LABELS,
  type CashAccount, type CashCount, type CashShift,
} from "@/lib/api/restaurant-finance"

const COUNT_BADGE: Record<string, string> = {
  Draft: "bg-slate-100 text-slate-700",
  Posted: "bg-green-100 text-green-700",
  Reversed: "bg-amber-100 text-amber-700",
}

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
  // null = a fresh draft for the chosen account. A number = editing THAT
  // draft; submitting UPDATEs it rather than creating a second one (an
  // account can only have one open draft at a time).
  const [editingDraftId, setEditingDraftId] = useState<number | null>(null)
  const [discardTarget, setDiscardTarget] = useState<CashCount | null>(null)

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

  // An account may hold only one open draft, so if one exists the form is
  // either editing it (editingDraftId matches) or must be disabled — a second
  // save would be refused by the database anyway.
  const accountDraft = useMemo(
    () => (chosen ? counts.find((c) => c.cashAccountId === chosen.cashAccountId && c.status === "Draft") ?? null : null),
    [counts, chosen],
  )
  const formLocked = !!accountDraft && editingDraftId !== accountDraft.countId

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

  function startEditDraft(id: number) {
    const c = counts.find((x) => x.countId === id)
    if (!c) return
    setAccountId(String(c.cashAccountId)); setCounted(String(c.countedBalance)); setNotes(c.notes ?? ""); setEditingDraftId(id)
  }
  function cancelEdit() { setEditingDraftId(null); setCounted(""); setNotes("") }

  /** Saves only. Posting is a separate step -- see postDraft() below. */
  async function saveDraft() {
    if (!chosen || counted === "") return
    setSaving(true)
    try {
      if (editingDraftId) {
        await updateCountDraft(editingDraftId, { counted: parseFloat(counted) || 0, notes: notes || null })
        toast({ title: "Draft updated" })
      } else {
        await saveCountDraft({ cashAccountId: chosen.cashAccountId, counted: parseFloat(counted) || 0, notes: notes || null })
        toast({ title: "Draft saved", description: "Nothing has been posted yet -- post it below to move the money." })
      }
      cancelEdit(); await load()
    } catch (e: any) { toast({ title: "Could not save the draft", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  /** The only thing on this page that moves money. */
  async function postDraft(id: number) {
    setSaving(true)
    try {
      const res = await postCountDraft(id)
      toast({ title: res.adjustmentTransactionId ? "Cash count posted" : "Balanced",
        description: res.adjustmentTransactionId
          ? "The difference has been posted to the ledger as an adjustment."
          : "The count matched the ledger, so no adjustment was needed." })
      if (editingDraftId === id) cancelEdit()
      await load()
    } catch (e: any) { toast({ title: "Couldn't post the count", description: e?.message, variant: "destructive" }) }
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
            <PageHeader icon={Scale} title="Reconciliation" subtitle="Count the cash box, confirm the bank and wallet balances, see every over and short">
              <Button asChild variant="outline"><Link href="/restaurant-cash-accounts">Back to Cash Accounts</Link></Button>
            </PageHeader>

            <div className="grid grid-cols-2 lg:grid-cols-3 gap-3">
              <MoneyStat label="Short this period" value={gh(short)} accent="rose" />
              <MoneyStat label="Over this period" value={gh(over)} accent="amber" />
              <MoneyStat label="Checks that balanced" value={`${live.filter((h) => h.difference === 0).length} of ${live.length}`} accent="emerald" />
            </div>

            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-base">Record a count</CardTitle>
                <CardDescription>
                  Count the cash, or read the balance off the bank or mobile-money statement, then save it as a
                  draft — saving does not move money, you post it after. Tills are counted when you close their
                  shift on <Link href="/restaurant-tills" className="underline">Tills & Shifts</Link>.
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-3">
                {/* Poultry's per-account row (app/poultry-cash-reconciliation). */}
                {chosen && (
                  <div className="grid grid-cols-2 md:grid-cols-3 gap-2">
                    <AccTile label="System balance" value={gh(chosen.currentBalance)} />
                    <AccTile label="Last counted" value={chosen.lastCountedAt ? chosen.lastCountedAt.slice(0, 10) : "Never"} />
                    <AccTile label="Counted then" value={chosen.lastCountedBalance != null ? gh(chosen.lastCountedBalance) : "—"} />
                  </div>
                )}
                {/* A saved count sits here until someone posts it. One open draft
                    per account is a database rule, so this is also what explains
                    why the form below locks (Poultry's banner, in rose). */}
                {accountDraft && (
                  <Alert className="border-rose-200 bg-rose-50 py-2">
                    <AlertTriangle className="h-4 w-4 text-rose-700" />
                    <AlertDescription className="text-xs text-rose-900 flex flex-wrap items-center gap-2">
                      <span>
                        Count #{accountDraft.countId} is saved but not posted — nothing has reached the ledger yet.
                        {" "}Counted {gh(accountDraft.countedBalance)}.
                      </span>
                      <Button size="sm" className="h-6 px-2 text-xs bg-rose-600 hover:bg-rose-700"
                              onClick={() => void postDraft(accountDraft.countId)} disabled={saving}>
                        Post it
                      </Button>
                      {editingDraftId !== accountDraft.countId && (
                        <Button size="sm" variant="outline" className="h-6 px-2 text-xs"
                                onClick={() => startEditDraft(accountDraft.countId)}>
                          Edit
                        </Button>
                      )}
                      <Button size="sm" variant="outline" className="h-6 px-2 text-xs"
                              onClick={() => setDiscardTarget(accountDraft)}>
                        Discard
                      </Button>
                    </AlertDescription>
                  </Alert>
                )}
                {editingDraftId && (
                  <Alert className="border-sky-200 bg-sky-50 py-2">
                    <AlertDescription className="text-xs text-sky-900 flex flex-wrap items-center justify-between gap-2">
                      <span>Editing draft count #{editingDraftId}. Saving updates it — posting is still a separate step.</span>
                      <Button size="sm" variant="ghost" className="h-6 px-2 text-xs" onClick={cancelEdit}>Cancel edit</Button>
                    </AlertDescription>
                  </Alert>
                )}
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                  <div className="space-y-1.5">
                    <Label>Account</Label>
                    <Select value={accountId} disabled={!!editingDraftId}
                            onValueChange={(v) => { setAccountId(v); setCounted(""); setNotes("") }}>
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
                    <Input type="number" inputMode="decimal" step="0.01" min={0} value={counted} disabled={!chosen || formLocked}
                      onChange={(e) => setCounted(e.target.value)} className="h-10" />
                  </div>
                </div>
                {chosen && counted !== "" && (
                  <div className={`rounded-lg p-3 text-sm font-medium ${diff === 0 ? "bg-green-50 text-green-800" : diff > 0 ? "bg-amber-50 text-amber-800" : "bg-red-50 text-red-800"}`}>
                    {diff === 0 ? "It balances." : `${diff > 0 ? "Over" : "Short"} by ${gh(Math.abs(diff))} — saved as a draft; posting it moves cash ${diff > 0 ? "in" : "out"}.`}
                  </div>
                )}
                <div className="flex flex-col sm:flex-row gap-3">
                  <Input value={notes} onChange={(e) => setNotes(e.target.value)} placeholder={diff < 0 ? "Why is it short?" : "Notes (optional)"} className="h-10" disabled={!chosen || formLocked} />
                  <Button className="bg-rose-600 hover:bg-rose-700 sm:w-48" disabled={!chosen || counted === "" || saving || formLocked} onClick={saveDraft}>
                    {saving && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}{editingDraftId ? "Update draft" : "Save draft"}
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
              <CardContent className="p-0 lg:p-2">
                {history.length === 0 ? <p className="p-6 text-center text-sm text-muted-foreground">No counts or cash-ups in this period.</p> : (
                  <MobileCardList
                    striped
                    items={history}
                    getKey={(h) => h.key}
                    primary={(h) => h.account}
                    secondary={(h) => <span>{h.date} · {h.kind}{h.reference ? ` · ${h.reference}` : ""}</span>}
                    trailing={(h) => h.status !== "Posted"
                      ? <Badge variant="outline" className={`border-0 text-xs ${COUNT_BADGE[h.status] ?? "text-gray-500"}`}>{h.status}</Badge>
                      : null}
                    highlights={(h) => [
                      { label: h.difference < 0 ? "Short" : h.difference > 0 ? "Over" : "Balanced",
                        value: <span className={h.status === "Reversed" ? "line-through" : ""}>{gh(h.difference)}</span>,
                        accent: h.difference < 0 ? "rose" : h.difference > 0 ? "amber" : "emerald", wide: true },
                      { label: "System", value: gh(h.system), accent: "slate" },
                      { label: "Counted", value: gh(h.counted), accent: "blue" },
                    ]}
                    details={(h) => [
                      { label: "By", value: h.by || "—" },
                      { label: "Note", value: h.note || "—" },
                    ]}
                    // A Draft: post it, correct it, or throw it away -- the only
                    // ways out of the one-open-draft-per-account lock. Posted:
                    // reverse (Poultry/Hotel's layout, in rose).
                    actions={(h) => h.kind !== "Count" ? null : h.status === "Draft" ? (
                      <>
                        <Button size="sm" variant="outline" className="h-10 flex-1 bg-white text-emerald-700 border-emerald-200 hover:bg-emerald-50"
                                onClick={(e) => { e.stopPropagation(); void postDraft(h.countId!) }} disabled={saving}>
                          <Check className="mr-2 h-4 w-4" /> Post
                        </Button>
                        <Button size="sm" variant="outline" className="h-10 flex-1 bg-white text-rose-700 border-rose-200 hover:bg-rose-50"
                                onClick={(e) => { e.stopPropagation(); startEditDraft(h.countId!) }}>
                          <Pencil className="mr-2 h-4 w-4" /> Edit
                        </Button>
                        <Button size="sm" variant="outline" className="h-10 flex-1 bg-white text-red-600 border-red-200 hover:bg-red-50"
                                onClick={(e) => { e.stopPropagation(); const c = counts.find((x) => x.countId === h.countId); if (c) setDiscardTarget(c) }}>
                          <Trash2 className="mr-2 h-4 w-4" /> Discard
                        </Button>
                      </>
                    ) : h.status === "Posted" ? (
                      <Button variant="outline" size="sm" className="flex-1 h-10 bg-white" onClick={() => { setReverseFor(h); setReason("") }}>Reverse</Button>
                    ) : null}
                    desktopTable={
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm min-w-[820px]">
                      <thead className="bg-gray-50 border-b"><tr>
                        {["Date", "Type", "Account", "Reference", "System", "Counted", "Over / short", "By", "Note", ""].map((h, i) =>
                          <th key={i} className={`p-3 ${i >= 4 && i <= 6 ? "text-right" : "text-left"}`}>{h}</th>)}
                      </tr></thead>
                      <tbody>{history.map((h) => (
                        <tr key={h.key} className={`border-b ${h.status === "Reversed" ? "text-slate-400" : ""}`}>
                          <td className="p-3">{h.date}</td>
                          <td className="p-3">
                            <Badge variant="outline">{h.kind}</Badge>
                            {h.status !== "Posted" && (
                              <Badge variant="outline" className={`ml-1 border-0 text-xs ${COUNT_BADGE[h.status] ?? "text-gray-500"}`}>{h.status}</Badge>
                            )}
                          </td>
                          <td className="p-3 font-medium">{h.account}</td>
                          <td className="p-3 text-xs">{h.reference}</td>
                          <td className="p-3 text-right tabular-nums">{gh(h.system)}</td>
                          <td className="p-3 text-right tabular-nums">{gh(h.counted)}</td>
                          <td className={`p-3 text-right tabular-nums font-semibold ${h.status === "Reversed" ? "line-through" : h.difference < 0 ? "text-red-600" : h.difference > 0 ? "text-amber-600" : "text-green-700"}`}>{gh(h.difference)}</td>
                          <td className="p-3 text-xs">{h.by}</td>
                          <td className="p-3 text-xs max-w-[14rem]">{h.note}</td>
                          <td className="p-3 text-right whitespace-nowrap">
                            {h.kind === "Count" && h.status === "Draft" && (
                              <>
                                <Button size="sm" variant="ghost" title="Post this count to the ledger"
                                        onClick={() => void postDraft(h.countId!)} disabled={saving}>
                                  <Check className="h-4 w-4 text-emerald-600" />
                                </Button>
                                <Button size="sm" variant="ghost" title="Edit this draft"
                                        onClick={() => startEditDraft(h.countId!)}>
                                  <Pencil className="h-4 w-4 text-rose-600" />
                                </Button>
                                <Button size="sm" variant="ghost" title="Discard this draft"
                                        onClick={() => { const c = counts.find((x) => x.countId === h.countId); if (c) setDiscardTarget(c) }}>
                                  <Trash2 className="h-4 w-4 text-red-600" />
                                </Button>
                              </>
                            )}
                            {h.kind === "Count" && h.status === "Posted" && (
                              <Button variant="outline" size="sm" onClick={() => { setReverseFor(h); setReason("") }}>Reverse</Button>
                            )}
                          </td>
                        </tr>
                      ))}</tbody>
                    </table>
                  </div>
                    }
                  />
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

      <ConfirmDeleteDialog
        open={!!discardTarget}
        onOpenChange={(o) => { if (!o) setDiscardTarget(null) }}
        title={`Discard count #${discardTarget?.countId ?? ""}?`}
        description="Nothing was posted, so no money moves and nothing is reversed. The draft is removed and the account can be counted again."
        confirmLabel="Discard draft"
        errorTitle="Could not discard the draft"
        onConfirm={async () => {
          if (!discardTarget) return
          await discardCountDraft(discardTarget.countId)
          if (editingDraftId === discardTarget.countId) cancelEdit()
          setDiscardTarget(null)
          await load()
        }}
      />
    </div>
  )
}

function AccTile({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg border border-slate-200 bg-white px-3 py-2">
      <div className="text-[11px] uppercase tracking-wide text-slate-500">{label}</div>
      <div className="font-semibold tabular-nums text-slate-900">{value}</div>
    </div>
  )
}
