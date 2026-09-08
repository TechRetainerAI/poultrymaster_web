"use client"

// Water Cash Transfers.
//
// Money moving between the company's own accounts: cash box to bank, bank to
// MoMo, bank to petty cash. Water has had the transfer SPs and an API since
// migration 047, but never a screen -- transfers could only be made from the
// Cash Accounts page's Transfer button, and there was nowhere to see them all,
// search them, or undo one.
//
// THE POINT OF THIS PAGE
// ----------------------
// A transfer is the same money in a different box. It must never look like the
// business earned or spent anything, which is why the subtitle says so and why
// the totals below are labelled "moved", never "in" or "out".
//
// Reversal is the reason this page exists. Before migration 257 an approved
// transfer was permanent -- Cancel only ever accepted a Draft, and the create
// flow approves immediately, so nothing could ever be cancelled. A transfer
// typed into the wrong account could only be answered with a second transfer,
// leaving the mistake and the correction looking like two deliberate movements.
//
// Ported from app/poultry-cash-transfers, deliberately shape-for-shape: the two
// rails should not drift into two different ideas of what a transfer is.

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Textarea } from "@/components/ui/textarea"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { usePagination } from "@/hooks/use-pagination"
import { ArrowLeftRight, ArrowRight, Loader2, Plus, Undo2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { entryTimestamp } from "@/lib/utils/date-key"
import { useFmt } from "@/lib/currency"
import {
  listWaterCashAccounts, listWaterCashTransfers, createWaterCashTransfer,
  approveWaterCashTransfer, reverseWaterCashTransfer,
  type WaterCashAccount, type WaterCashTransfer,
} from "@/lib/api/water"

const STATUS_FILTERS = ["All", "Approved", "Draft", "Reversed", "Cancelled"] as const

function statusClass(s: string) {
  switch (s) {
    case "Approved":  return "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"
    case "Reversed":  return "bg-amber-100 text-amber-800 hover:bg-amber-100"
    case "Cancelled": return "bg-slate-100 text-slate-700 hover:bg-slate-100"
    default:          return "bg-sky-100 text-sky-800 hover:bg-sky-100"
  }
}

function today() {
  return new Date().toISOString().slice(0, 10)
}

function monthStart() {
  const n = new Date()
  return new Date(n.getFullYear(), n.getMonth(), 1).toISOString().slice(0, 10)
}

export default function WaterCashTransfersPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  const [accounts, setAccounts] = useState<WaterCashAccount[]>([])
  const [rows, setRows] = useState<WaterCashTransfer[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)

  const [status, setStatus] = useState<string>("All")
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")

  const [newOpen, setNewOpen] = useState(false)
  const [form, setForm] = useState({
    fromWaterCashAccountId: "", toWaterCashAccountId: "",
    amount: "0", transferDate: today(), referenceNumber: "", notes: "",
  })

  const [reversing, setReversing] = useState<WaterCashTransfer | null>(null)
  const [reason, setReason] = useState("")

  const load = async () => {
    setLoading(true)
    try {
      const [accs, xfers] = await Promise.all([listWaterCashAccounts(), listWaterCashTransfers()])
      setAccounts(accs)
      setRows(xfers)
    } catch (e: any) {
      toast({ title: "Could not load transfers", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router])

  // ---- derived -------------------------------------------------------------
  const visible = useMemo(() => {
    const byStatus = status === "All" ? rows : rows.filter((r) => r.status === status)
    return filterByDateAndSearch(byStatus, {
      dateFrom, dateTo, dateKey: "transferDate",
      search,
      searchKeys: ["transferNumber", "fromAccountName", "toAccountName", "referenceNumber", "notes"],
    })
  }, [rows, status, search, dateFrom, dateTo])
  const pg = usePagination(visible)

  // Only movements that actually happened count towards the totals: a draft
  // moved nothing, and a reversed transfer moved it and moved it back.
  const live = rows.filter((r) => r.status === "Approved")
  const movedToday = live.filter((r) => r.transferDate?.slice(0, 10) === today())
  const movedThisMonth = live.filter((r) => (r.transferDate ?? "") >= monthStart())
  const sum = (xs: WaterCashTransfer[]) => xs.reduce((t, r) => t + r.amount, 0)

  const busiest = (key: "fromAccountName" | "toAccountName") => {
    const tally = new Map<string, number>()
    live.forEach((r) => {
      const k = r[key] ?? "—"
      tally.set(k, (tally.get(k) ?? 0) + r.amount)
    })
    const top = [...tally.entries()].sort((a, b) => b[1] - a[1])[0]
    return top ? { name: top[0], amount: top[1] } : null
  }
  const topFrom = busiest("fromAccountName")
  const topTo = busiest("toAccountName")

  const balanceOf = (id: string) =>
    accounts.find((a) => String(a.waterCashAccountId) === id)?.currentBalance ?? 0
  const allowsNegative = (id: string) =>
    accounts.find((a) => String(a.waterCashAccountId) === id)?.allowNegativeBalance ?? false

  const amountNum = Number(form.amount) || 0
  const fromAfter = balanceOf(form.fromWaterCashAccountId) - amountNum
  const toAfter = balanceOf(form.toWaterCashAccountId) + amountNum
  const wouldOverdraw =
    !!form.fromWaterCashAccountId && amountNum > 0 &&
    fromAfter < 0 && !allowsNegative(form.fromWaterCashAccountId)

  // ---- actions -------------------------------------------------------------
  const save = async () => {
    if (!form.fromWaterCashAccountId || !form.toWaterCashAccountId) {
      toast({ title: "Pick both accounts", variant: "destructive" }); return
    }
    if (form.fromWaterCashAccountId === form.toWaterCashAccountId) {
      toast({ title: "Pick two different accounts", variant: "destructive" }); return
    }
    if (amountNum <= 0) {
      toast({ title: "Enter an amount", variant: "destructive" }); return
    }
    setSaving(true)
    try {
      // Create then approve, the flow the Cash Accounts page has always used:
      // a transfer someone typed is a transfer they meant to make. The Draft
      // step exists for callers that want an approval gate.
      const { waterCashTransferId } = await createWaterCashTransfer({
        fromWaterCashAccountId: Number(form.fromWaterCashAccountId),
        toWaterCashAccountId: Number(form.toWaterCashAccountId),
        amount: amountNum,
        // A date picker binds to midnight, which buries a transfer recorded
        // just now beneath everything else already recorded today. Today
        // gets the real clock time; a back-dated one keeps midnight, because
        // nobody knows what time last Tuesday's transfer happened.
        transferDate: entryTimestamp(form.transferDate) ?? undefined,
        referenceNumber: form.referenceNumber.trim() || null,
        notes: form.notes.trim() || null,
      })
      await approveWaterCashTransfer(waterCashTransferId)
      toast({ title: "Transfer recorded" })
      setNewOpen(false)
      setForm({
        fromWaterCashAccountId: "", toWaterCashAccountId: "",
        amount: "0", transferDate: today(), referenceNumber: "", notes: "",
      })
      await load()
    } catch (e: any) {
      toast({ title: "Transfer failed", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  const doReverse = async () => {
    if (!reversing) return
    if (reason.trim().length < 3) {
      toast({ title: "Say why", description: "The reason is written to the audit trail.", variant: "destructive" })
      return
    }
    setSaving(true)
    try {
      await reverseWaterCashTransfer(reversing.waterCashTransferId, reason.trim())
      toast({
        title: "Transfer reversed",
        description: `${fmt(reversing.amount)} put back on ${reversing.fromAccountName ?? "the source account"}.`,
      })
      setReversing(null)
      setReason("")
      await load()
    } catch (e: any) {
      toast({ title: "Could not reverse", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-end justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <ArrowLeftRight className="h-6 w-6 text-sky-600" /> Cash Transfers
              </h1>
              <p className="text-sm text-slate-500 max-w-2xl">
                Move money between the company's own cash accounts. A transfer is the same money in a
                different box — it never counts as money in or money out on{" "}
                <Link href="/water-cash-flow" className="text-sky-700 hover:underline">Cash Flow</Link>.
              </p>
            </div>
            <Button onClick={() => setNewOpen(true)} className="h-11 sm:h-10">
              <Plus className="h-4 w-4 mr-1" /> Record transfer
            </Button>
          </div>

          {/* Totals say "moved", never "in" or "out". */}
          <div className="grid grid-cols-2 lg:grid-cols-5 gap-3 mb-4">
            <Stat label="Moved today" value={fmt(sum(movedToday))} hint={`${movedToday.length} transfer(s)`} />
            <Stat label="Moved this month" value={fmt(sum(movedThisMonth))} hint={`${movedThisMonth.length} transfer(s)`} />
            <Stat label="Transfers on record" value={String(rows.length)} hint={`${live.length} approved`} />
            <Stat label="Most used source" value={topFrom?.name ?? "—"} hint={topFrom ? fmt(topFrom.amount) : undefined} />
            <Stat label="Most used destination" value={topTo?.name ?? "—"} hint={topTo ? fmt(topTo.amount) : undefined} />
          </div>

          <Card className="mb-4">
            <CardContent className="pt-6">
              <ListFilters
                search={search} setSearch={setSearch}
                searchPlaceholder="Search number, account, reference or note"
                dateFrom={dateFrom} setDateFrom={setDateFrom}
                dateTo={dateTo} setDateTo={setDateTo}
              />
              <div className="flex flex-wrap gap-2 mt-3">
                {STATUS_FILTERS.map((s) => (
                  <Button key={s} size="sm" variant={status === s ? "default" : "outline"}
                          onClick={() => setStatus(s)}>{s}</Button>
                ))}
              </div>
            </CardContent>
          </Card>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500">
              <Loader2 className="h-4 w-4 animate-spin" /> Loading…
            </div>
          ) : visible.length === 0 ? (
            <Card><CardContent className="py-8 text-center text-slate-500">
              {rows.length === 0
                ? "No transfers yet. Record one when you move money between accounts."
                : "No transfers match these filters."}
            </CardContent></Card>
          ) : (
            <MobileCardList
              items={pg.pageItems}
              getKey={(t) => t.waterCashTransferId}
              primary={(t) => t.transferNumber ?? `#${t.waterCashTransferId}`}
              secondary={(t) => (
                <>
                  <span>{new Date(t.transferDate).toLocaleDateString()}</span>
                  <span>·</span>
                  <span className="text-xs">{t.fromAccountName} → {t.toAccountName}</span>
                </>
              )}
              trailing={(t) => <Badge className={statusClass(t.status)}>{t.status}</Badge>}
              highlights={(t) => [{ label: "Amount", value: fmt(t.amount) }]}
              details={(t) => [
                { label: "From", value: t.fromAccountName ?? "–" },
                { label: "To", value: t.toAccountName ?? "–" },
                { label: "Reference", value: t.referenceNumber ?? "–" },
                { label: "Notes", value: t.notes ?? "–" },
                { label: "Recorded by", value: t.createdBy ?? "–" },
                ...(t.status === "Reversed"
                  ? [{ label: "Reversed", value: t.reversalReason ?? "–" }]
                  : []),
              ]}
              actions={(t) => (
                <>
                  {t.status === "Approved" && (
                    <Button size="sm" variant="outline" className="flex-1 h-10"
                            onClick={() => { setReversing(t); setReason("") }}>
                      <Undo2 className="h-4 w-4 mr-1" /> Reverse
                    </Button>
                  )}
                </>
              )}
              {...pg.paginationProps}
              desktopTable={
                <div className="overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Date</TableHead>
                        <TableHead>Transfer #</TableHead>
                        <TableHead>From</TableHead>
                        <TableHead>To</TableHead>
                        <TableHead className="text-right">Amount</TableHead>
                        <TableHead>Reference</TableHead>
                        <TableHead>Recorded by</TableHead>
                        <TableHead>Status</TableHead>
                        <TableHead></TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {pg.pageItems.map((t) => (
                        <TableRow key={t.waterCashTransferId}>
                          <TableCell className="whitespace-nowrap">
                            {new Date(t.transferDate).toLocaleDateString()}
                          </TableCell>
                          <TableCell className="font-medium">
                            {t.transferNumber ?? `#${t.waterCashTransferId}`}
                          </TableCell>
                          <TableCell>{t.fromAccountName ?? "–"}</TableCell>
                          <TableCell>{t.toAccountName ?? "–"}</TableCell>
                          <TableCell className="text-right font-medium tabular-nums">
                            <span className={t.status === "Reversed" ? "line-through text-slate-400" : ""}>
                              {fmt(t.amount)}
                            </span>
                          </TableCell>
                          <TableCell className="text-slate-500">{t.referenceNumber ?? "–"}</TableCell>
                          <TableCell className="text-slate-500">{t.createdBy ?? "–"}</TableCell>
                          <TableCell>
                            <Badge className={statusClass(t.status)}>{t.status}</Badge>
                            {t.status === "Reversed" && t.reversalReason && (
                              <div className="text-xs text-slate-500 mt-0.5 max-w-[16rem] truncate"
                                   title={t.reversalReason}>
                                {t.reversalReason}
                              </div>
                            )}
                          </TableCell>
                          <TableCell className="text-right">
                            {t.status === "Approved" && (
                              <Button size="sm" variant="outline"
                                      onClick={() => { setReversing(t); setReason("") }}>
                                <Undo2 className="h-3 w-3 mr-1" /> Reverse
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
        </main>
      </div>

      {/* ---- record ---------------------------------------------------- */}
      <Dialog open={newOpen} onOpenChange={setNewOpen}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <ArrowLeftRight className="w-5 h-5 text-sky-600" /> Record Cash Transfer
            </DialogTitle>
            <DialogDescription>
              Writes a matching pair of ledger rows — one out of the source, one into the
              destination. Company-wide cash flow is unaffected.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4">
            <FormSection title="Movement" color="sky">
              <FormField label="Transfer date *">
                <Input type="date" value={form.transferDate}
                       onChange={(e) => setForm((f) => ({ ...f, transferDate: e.target.value }))} />
              </FormField>
              <FormField label="Amount *">
                <NumberInput value={form.amount} min={0}
                             onChange={(e) => setForm((f) => ({ ...f, amount: e.target.value }))} />
              </FormField>
              <FormField label="From account *" full>
                <Select value={form.fromWaterCashAccountId}
                        onValueChange={(v) => setForm((f) => ({ ...f, fromWaterCashAccountId: v }))}>
                  <SelectTrigger><SelectValue placeholder="Pick the account the money leaves" /></SelectTrigger>
                  <SelectContent>
                    {accounts.filter((a) => a.isActive).map((a) => (
                      <SelectItem key={a.waterCashAccountId} value={String(a.waterCashAccountId)}>
                        {a.accountName} — {fmt(a.currentBalance)}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </FormField>
              <FormField label="To account *" full>
                <Select value={form.toWaterCashAccountId}
                        onValueChange={(v) => setForm((f) => ({ ...f, toWaterCashAccountId: v }))}>
                  <SelectTrigger><SelectValue placeholder="Pick the account the money arrives in" /></SelectTrigger>
                  <SelectContent>
                    {accounts
                      .filter((a) => a.isActive && String(a.waterCashAccountId) !== form.fromWaterCashAccountId)
                      .map((a) => (
                        <SelectItem key={a.waterCashAccountId} value={String(a.waterCashAccountId)}>
                          {a.accountName} — {fmt(a.currentBalance)}
                        </SelectItem>
                      ))}
                  </SelectContent>
                </Select>
              </FormField>
            </FormSection>

            {/* What the two accounts will read afterwards, before anything is
                committed — the question a person actually has at this moment. */}
            {form.fromWaterCashAccountId && form.toWaterCashAccountId && amountNum > 0 && (
              <FormSection title="After this transfer" color="slate" columns={1}>
                <div className="text-sm space-y-1">
                  <Preview label="Source" before={balanceOf(form.fromWaterCashAccountId)}
                           after={fromAfter} fmt={fmt} />
                  <Preview label="Destination" before={balanceOf(form.toWaterCashAccountId)}
                           after={toAfter} fmt={fmt} />
                  {wouldOverdraw && (
                    <p className="text-rose-600 text-xs pt-1">
                      This would take the source account below zero, and it is not allowed to go
                      negative. The transfer will be rejected.
                    </p>
                  )}
                </div>
              </FormSection>
            )}

            <FormSection title="Reference" color="slate" columns={1}>
              <FormField label="Reference">
                <Input value={form.referenceNumber} placeholder="Bank or MoMo reference"
                       onChange={(e) => setForm((f) => ({ ...f, referenceNumber: e.target.value }))} />
              </FormField>
              <FormField label="Notes" full>
                <Textarea rows={2} value={form.notes}
                          onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} />
              </FormField>
            </FormSection>
          </div>

          <div className="flex gap-3 justify-end pt-2">
            <Button type="button" onClick={() => setNewOpen(false)}
                    className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
            <Button onClick={save} disabled={saving || wouldOverdraw}>
              {saving ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Recording...</>
                      : <><ArrowLeftRight className="w-4 h-4 mr-2" />Record Transfer</>}
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* ---- reverse --------------------------------------------------- */}
      <Dialog open={!!reversing} onOpenChange={(o) => { if (!o) { setReversing(null); setReason("") } }}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Undo2 className="w-5 h-5 text-amber-600" /> Reverse Transfer
            </DialogTitle>
            <DialogDescription>
              The original stays on the record. Two opposite rows are added, putting both accounts
              back where they were.
            </DialogDescription>
          </DialogHeader>

          {reversing && (
            <div className="space-y-4">
              <FormSection title="Transfer being reversed" color="slate" columns={1}>
                <div className="text-sm">
                  <div className="font-medium">{reversing.transferNumber ?? "#" + reversing.waterCashTransferId}</div>
                  <div className="flex items-center gap-1 text-slate-600 mt-1">
                    {reversing.fromAccountName} <ArrowRight className="h-3 w-3" /> {reversing.toAccountName}
                  </div>
                  <div className="mt-1">{fmt(reversing.amount)} on {new Date(reversing.transferDate).toLocaleDateString()}</div>
                  <div className="text-xs text-slate-500 mt-2">
                    {fmt(reversing.amount)} comes back out of {reversing.toAccountName} and returns to{" "}
                    {reversing.fromAccountName}. If the destination no longer holds it and cannot go
                    negative, the reversal will be refused.
                  </div>
                </div>
              </FormSection>

              <FormSection title="Why" color="amber" columns={1}>
                <FormField label="Reason *" hint="Written to the audit trail.">
                  <Textarea rows={3} value={reason} onChange={(e) => setReason(e.target.value)}
                            placeholder="Why is this being reversed?" />
                </FormField>
              </FormSection>
            </div>
          )}

          <div className="flex gap-3 justify-end pt-2">
            <Button type="button" onClick={() => { setReversing(null); setReason("") }}
                    className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
            <Button variant="destructive" onClick={doReverse} disabled={saving}>
              {saving ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Reversing...</>
                      : <><Undo2 className="w-4 h-4 mr-2" />Reverse Transfer</>}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}

function Stat({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <Card>
      <CardContent className="p-4">
        <p className="text-xs font-medium text-slate-500 uppercase tracking-wider truncate">{label}</p>
        <div className="text-lg sm:text-xl font-bold text-slate-900 mt-1 truncate">{value}</div>
        {hint && <div className="text-xs text-slate-500 mt-0.5 truncate">{hint}</div>}
      </CardContent>
    </Card>
  )
}

function Preview({
  label, before, after, fmt,
}: {
  label: string
  before: number
  after: number
  fmt: (n: number) => string
}) {
  return (
    <div className="flex items-center justify-between gap-2">
      <span className="text-slate-500">{label}</span>
      <span className="tabular-nums">
        <span className="text-slate-400">{fmt(before)}</span>
        {" → "}
        <span className={`font-medium ${after < 0 ? "text-rose-600" : "text-slate-900"}`}>{fmt(after)}</span>
      </span>
    </div>
  )
}
