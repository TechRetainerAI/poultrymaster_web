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
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Badge } from "@/components/ui/badge"
import { cn } from "@/lib/utils"
import { ArrowLeft, Loader2, Wallet, RefreshCw, Scale, Trash2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { categoryLabel } from "@/lib/cash/cash-flow"
import {
  getPoultryCashAccount, listPoultryCashTransactions, adjustPoultryCashAccount, reconcilePoultryCashBalances,
  deletePoultryCashAccount, setPoultryCashClearing, POULTRY_CASH_REASONS,
  type PoultryCashAccount, type PoultryCashTransaction, type PoultryClearingStatus,
} from "@/lib/api/poultry-finance"

const CLEARING_BADGE: Record<string, string> = {
  Uncleared: "bg-slate-100 text-slate-600",
  Cleared: "bg-emerald-100 text-emerald-700",
  Disputed: "bg-rose-100 text-rose-700",
}

export default function PoultryCashAccountDetailPage() {
  const router = useRouter()
  const params = useParams<{ id: string }>()
  const id = Number(params?.id)
  const { toast } = useToast()
  const gh = useFmt()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [account, setAccount] = useState<PoultryCashAccount | null>(null)
  const [rows, setRows] = useState<PoultryCashTransaction[]>([])
  const [loading, setLoading] = useState(true)

  const [adjOpen, setAdjOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  // `reasonNote` only carries text when reason is "Other"; what reaches the API
  // is one string either way, since the SP stores a plain reason.
  const [adj, setAdj] = useState<{ direction: "in" | "out"; amount: number; reason: string; reasonNote: string }>(
    { direction: "in", amount: 0, reason: "", reasonNote: "" })
  const [delOpen, setDelOpen] = useState(false)
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    if (id) void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, id])

  async function load() {
    setLoading(true)
    // allSettled, not all: these are independent reads and a failure in one
    // must not blank the other.
    const [accRes, txRes] = await Promise.allSettled([
      getPoultryCashAccount(id),
      listPoultryCashTransactions({ cashAccountId: id }),
    ])

    if (accRes.status === "fulfilled") setAccount(accRes.value)
    else toast({ title: "Could not load account", description: accRes.reason?.message, variant: "destructive" })

    if (txRes.status === "fulfilled") setRows(txRes.value)
    else toast({ title: "Could not load transactions", description: txRes.reason?.message, variant: "destructive" })

    setLoading(false)
  }

  /** Mark rows cleared / uncleared / disputed from the ledger. */
  async function setClearing(txnId: number, status: PoultryClearingStatus) {
    try {
      await setPoultryCashClearing({
        poultryCashAccountId: id, transactionIds: [txnId], clearingStatus: status,
      })
      await load()
    } catch (e: any) {
      toast({ title: "Could not update clearing", description: e?.message, variant: "destructive" })
    }
  }

  const ledger = useMemo(() => {
    const opening = account?.openingBalance ?? 0
    // Order by CALENDAR DAY, then by id — not by the raw timestamp.
    //
    // Rows carry whatever time their source SP wrote. A sale stamps now(); a
    // posted cash count stamps the count's DATE, which arrives from a date
    // input as midnight. Sorting on the instant therefore buried a correction
    // posted this afternoon underneath every other row from the same day, and
    // on a busy account it fell off the first page entirely — which reads as
    // "posting did not write a ledger entry" when the entry is simply lower
    // down. Comparing days and tie-breaking on the id puts the newest row of a
    // day at the top of that day, which is what "newest first" means to
    // someone reading it. A genuinely back-dated row still sorts to its own
    // day. This also makes the running balance follow the order rows were
    // actually written within a day, rather than a clock time some of them
    // never had.
    const day = (r: { transactionDate: string }) => r.transactionDate.split("T")[0]
    const asc = [...rows].sort((a, b) => {
      const d = day(a).localeCompare(day(b))
      return d !== 0 ? d : a.poultryCashTransactionId - b.poultryCashTransactionId
    })
    let bal = opening
    const withRun = asc.map((r) => { bal += r.amount; return { ...r, running: bal } })
    return withRun.reverse()
  }, [rows, account])

  const totalIn = useMemo(() => rows.filter(r => r.amount > 0).reduce((s, r) => s + r.amount, 0), [rows])
  const totalOut = useMemo(() => rows.filter(r => r.amount < 0).reduce((s, r) => s + Math.abs(r.amount), 0), [rows])

  const visibleLedger = useMemo(
    () => filterByDateAndSearch(ledger, {
      search, dateFrom, dateTo,
      searchKeys: ["transactionType", "description", "sourceType"],
      dateKey: "transactionDate",
    }),
    [ledger, search, dateFrom, dateTo],
  )

  // Client-side paging: the whole list is already in memory, so this is a
  // slice. Feed the SAME slice to the cards and the desktop table.
  const pg = usePagination(visibleLedger)

  async function performDelete() {
    try {
      await deletePoultryCashAccount(id)
      toast({ title: "Cash account removed" })
      router.push("/poultry-cash-accounts")
    } catch (e: any) { toast({ title: "Could not remove account", description: e?.message, variant: "destructive" }) }
  }

  function openAdjust() { setAdj({ direction: "in", amount: 0, reason: "", reasonNote: "" }); setAdjOpen(true) }

  async function saveAdjust() {
    if (adj.amount <= 0) return toast({ title: "Enter an amount greater than 0", variant: "destructive" })
    if (!adj.reason) return toast({ title: "Pick a reason", variant: "destructive" })
    if (adj.reason === "Other" && !adj.reasonNote.trim()) {
      return toast({ title: "Say what happened", variant: "destructive" })
    }
    setSaving(true)
    try {
      const signed = adj.direction === "out" ? -Math.abs(adj.amount) : Math.abs(adj.amount)
      // "Other" submits what was typed; a picked option submits itself.
      const reason = adj.reason === "Other" ? adj.reasonNote.trim() : adj.reason
      await adjustPoultryCashAccount(id, { amount: signed, reason })
      toast({ title: "Balance adjusted", description: `${adj.direction === "out" ? "Removed" : "Added"} ${gh(adj.amount)}.` })
      setAdjOpen(false); await load()
    } catch (e: any) { toast({ title: "Adjustment failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function reconcile() {
    try { await reconcilePoultryCashBalances(); toast({ title: "Balance recalculated from transactions" }); await load() }
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
              <Link href="/poultry-cash-accounts"><ArrowLeft className="h-4 w-4 mr-1" /> Back to Cash Account</Link>
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
                {/* Reconciliation lives on its own page: it is a task, not a
                    property of this record. The account travels with the link. */}
                <Button asChild variant="outline" className="flex-1 sm:flex-none whitespace-nowrap">
                  <Link href={`/poultry-cash-reconciliation?accountId=${id}`}>
                    <Scale className="h-4 w-4 mr-1" /> Reconcile
                  </Link>
                </Button>
                <Button className="flex-1 sm:flex-none whitespace-nowrap" onClick={openAdjust}><Scale className="h-4 w-4 mr-1" /> Adjust balance</Button>
                <Button variant="outline" className="flex-1 sm:flex-none whitespace-nowrap text-red-600 border-red-200" onClick={() => setDelOpen(true)}><Trash2 className="h-4 w-4 mr-1" /> Delete</Button>
              </div>
            </div>
          </div>

          {loading ? (
            <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : !account ? (
            <div className="p-8 text-center text-slate-500">Account not found.</div>
          ) : (
            <>
              <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4">
                <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Opening balance</div><div className="text-xl font-semibold tabular-nums">{gh(account.openingBalance)}</div></CardContent></Card>
                <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Total money in</div><div className="text-xl font-semibold tabular-nums text-green-700">{gh(totalIn)}</div></CardContent></Card>
                <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Total money out</div><div className="text-xl font-semibold tabular-nums text-rose-600">{gh(totalOut)}</div></CardContent></Card>
                <Card><CardContent className="p-4"><div className="text-xs text-slate-500">Current balance</div><div className="text-xl font-semibold tabular-nums">{gh(account.currentBalance)}</div></CardContent></Card>
              </div>

              <ListFilters
                search={search} setSearch={setSearch}
                dateFrom={dateFrom} setDateFrom={setDateFrom}
                dateTo={dateTo} setDateTo={setDateTo}
                searchPlaceholder="Search type, source or description"
              />
              <Card>
                <CardContent className="p-0">
                  {ledger.length === 0 ? (
                    <div className="p-8 text-center text-slate-500">No transactions yet for this account.</div>
                  ) : visibleLedger.length === 0 ? (
                    <div className="p-8 text-center text-slate-500">No transactions match your filters.</div>
                  ) : (
                    <MobileCardList
                      items={pg.pageItems}
                      pagination={pg.paginationProps}
                      getKey={(r) => r.poultryCashTransactionId}
                      primary={(r) => `${r.amount < 0 ? "−" : "+"}${gh(Math.abs(r.amount))} · ${r.transactionType}`}
                      secondary={(r) => (<><span>{r.transactionDate.split("T")[0]}</span><span>· Bal {gh(r.running)}</span></>)}
                      details={(r) => [
                        { label: "Date", value: r.transactionDate.split("T")[0] },
                        { label: "Type", value: r.transactionType },
                        // Through the shared vocabulary so a row reads the same
                        // here as on Cash Flow. Printing the raw sourceType was
                        // the reason those labels had to stay unfriendly.
                        { label: "Source", value: categoryLabel(r.sourceType) },
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
                                <TableHead>Cleared</TableHead>
                                <TableHead>Description</TableHead>
                              </TableRow>
                            </TableHeader>
                            <TableBody>
                              {pg.pageItems.map((r) => (
                                <TableRow key={r.poultryCashTransactionId}>
                                  <TableCell className="whitespace-nowrap">{r.transactionDate.split("T")[0]}</TableCell>
                                  <TableCell>{r.transactionType}</TableCell>
                                  <TableCell>{categoryLabel(r.sourceType)}</TableCell>
                                  <TableCell className="text-right tabular-nums text-green-700">{r.amount > 0 ? gh(r.amount) : "—"}</TableCell>
                                  <TableCell className="text-right tabular-nums text-rose-600">{r.amount < 0 ? gh(Math.abs(r.amount)) : "—"}</TableCell>
                                  <TableCell className="text-right tabular-nums font-medium">{gh(r.running)}</TableCell>
                                  {/* Clearing. A row a posted count ticked off
                                      is locked — the server refuses to change it
                                      until that count is reversed, so it renders
                                      as a plain badge rather than a control. */}
                                  <TableCell>
                                    {r.poultryCashReconciliationId ? (
                                      <Badge variant="outline"
                                             title={`Cleared by cash count ${r.reconciliationReference ?? ""}`.trim()}
                                             className={cn("border-0", CLEARING_BADGE[r.clearingStatus ?? "Uncleared"])}>
                                        {r.clearingStatus ?? "Uncleared"}
                                      </Badge>
                                    ) : (
                                      <Select
                                        value={r.clearingStatus ?? "Uncleared"}
                                        onValueChange={(v) => void setClearing(r.poultryCashTransactionId, v as PoultryClearingStatus)}
                                      >
                                        <SelectTrigger className="h-7 w-[7.5rem] text-xs"><SelectValue /></SelectTrigger>
                                        <SelectContent>
                                          <SelectItem value="Uncleared">Uncleared</SelectItem>
                                          <SelectItem value="Cleared">Cleared</SelectItem>
                                          <SelectItem value="Disputed">Disputed</SelectItem>
                                        </SelectContent>
                                      </Select>
                                    )}
                                  </TableCell>
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
                <Select value={adj.reason} onValueChange={(v) => setAdj({ ...adj, reason: v, reasonNote: "" })}>
                  <SelectTrigger><SelectValue placeholder="Why is the balance changing?" /></SelectTrigger>
                  <SelectContent>
                    {POULTRY_CASH_REASONS.map((r) => (
                      <SelectItem key={r.value} value={r.value}>{r.label}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                {adj.reason === "Other" && (
                  <Input
                    autoFocus
                    className="mt-2"
                    value={adj.reasonNote}
                    onChange={(e) => setAdj({ ...adj, reasonNote: e.target.value })}
                    placeholder="Say what happened"
                  />
                )}
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

      <ConfirmDeleteDialog
        open={delOpen}
        onOpenChange={setDelOpen}
        title={`Remove ${account?.accountName ?? "this account"}?`}
        description="The account is deactivated so its transaction history stays intact."
        confirmLabel="Remove account"
        errorTitle="Could not remove account"
        onConfirm={performDelete}
      />
    </div>
  )
}
