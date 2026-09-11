"use client"

// Poultry Owner Money.
//
// What the owner has put into the farm, and what they have taken out.
//
// THE DISTINCTION THIS PAGE EXISTS TO MAKE
// ----------------------------------------
// A contribution is not a sale and a draw is not an expense. The farm did not
// earn the first or spend the second — the owner funded it, and took funding
// back. Both move cash, and both show on Cash Flow as financing, but neither
// touches profit. The page says so out loud, because the habit of filing a
// draw under "expenses" is exactly what makes a profitable month look like a
// loss.
//
// Before this, both were free-text cash adjustments typed "Owner injection" or
// "Withdrawal": the money moved, and nothing else was recorded — no owner, no
// net funding figure, and no way to undo one.

import { useEffect, useMemo, useState } from "react"
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
import {
  ArrowDownCircle, ArrowUpCircle, Loader2, Undo2, Wallet,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { entryTimestamp } from "@/lib/utils/date-key"
import { useFmt } from "@/lib/currency"
import {
  listPoultryCashAccounts, listPoultryOwnerMoney, getPoultryOwnerMoneySummary,
  recordPoultryOwnerMoney, reversePoultryOwnerMoney,
  type OwnerMoneyType, type PoultryCashAccount,
  type PoultryOwnerMoney, type PoultryOwnerMoneySummary,
} from "@/lib/api/poultry-finance"

const PAYMENT_METHODS = ["Cash", "BankTransfer", "MoMo", "Cheque", "Card", "Other"]
const TYPE_FILTERS = ["All", "Contribution", "Draw"] as const
const STATUS_FILTERS = ["All", "Posted", "Reversed"] as const

function today() {
  return new Date().toISOString().slice(0, 10)
}

export default function PoultryOwnerMoneyPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  const [accounts, setAccounts] = useState<PoultryCashAccount[]>([])
  const [rows, setRows] = useState<PoultryOwnerMoney[]>([])
  const [summary, setSummary] = useState<PoultryOwnerMoneySummary | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)

  const [typeFilter, setTypeFilter] = useState<string>("All")
  const [statusFilter, setStatusFilter] = useState<string>("All")
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")

  // One dialog for both directions: they differ by a single field, and two
  // dialogs would be two copies of the same validation.
  const [recording, setRecording] = useState<OwnerMoneyType | null>(null)
  const [form, setForm] = useState({
    amount: "0", poultryCashAccountId: "", transactionDate: today(),
    paymentMethod: "Cash", ownerName: "", referenceNumber: "", notes: "",
  })

  const [reversing, setReversing] = useState<PoultryOwnerMoney | null>(null)
  const [reason, setReason] = useState("")

  const load = async () => {
    setLoading(true)
    try {
      const [accs, list, sum] = await Promise.all([
        listPoultryCashAccounts(),
        listPoultryOwnerMoney(),
        getPoultryOwnerMoneySummary(),
      ])
      setAccounts(accs)
      setRows(list)
      setSummary(sum)
    } catch (e: any) {
      toast({ title: "Could not load owner money", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router])

  const visible = useMemo(() => {
    let list = rows
    if (typeFilter !== "All") list = list.filter((r) => r.transactionType === typeFilter)
    if (statusFilter !== "All") list = list.filter((r) => r.status === statusFilter)
    return filterByDateAndSearch(list, {
      dateFrom, dateTo, dateKey: "transactionDate",
      search,
      searchKeys: ["transactionNumber", "ownerName", "accountName", "referenceNumber", "notes"],
    })
  }, [rows, typeFilter, statusFilter, search, dateFrom, dateTo])
  const pg = usePagination(visible)

  const balanceOf = (id: string) =>
    accounts.find((a) => String(a.poultryCashAccountId) === id)?.currentBalance ?? 0
  const allowsNegative = (id: string) =>
    accounts.find((a) => String(a.poultryCashAccountId) === id)?.allowNegativeBalance ?? false

  const amountNum = Number(form.amount) || 0
  const isDraw = recording === "Draw"
  const after = isDraw
    ? balanceOf(form.poultryCashAccountId) - amountNum
    : balanceOf(form.poultryCashAccountId) + amountNum
  const wouldOverdraw =
    isDraw && !!form.poultryCashAccountId && amountNum > 0 &&
    after < 0 && !allowsNegative(form.poultryCashAccountId)

  const openRecord = (t: OwnerMoneyType) => {
    setRecording(t)
    setForm({
      amount: "0", poultryCashAccountId: "", transactionDate: today(),
      paymentMethod: "Cash", ownerName: "", referenceNumber: "", notes: "",
    })
  }

  const save = async () => {
    if (!recording) return
    if (!form.poultryCashAccountId) {
      toast({ title: "Pick a cash account", variant: "destructive" }); return
    }
    if (amountNum <= 0) {
      toast({ title: "Enter an amount", variant: "destructive" }); return
    }
    setSaving(true)
    try {
      await recordPoultryOwnerMoney({
        transactionType: recording,
        amount: amountNum,
        poultryCashAccountId: Number(form.poultryCashAccountId),
        // Today gets a real clock time so it sorts to the top; a back-dated
        // entry keeps midnight. See entryTimestamp.
        transactionDate: entryTimestamp(form.transactionDate),
        paymentMethod: form.paymentMethod || null,
        ownerName: form.ownerName.trim() || null,
        referenceNumber: form.referenceNumber.trim() || null,
        notes: form.notes.trim() || null,
      })
      toast({
        title: recording === "Contribution" ? "Contribution recorded" : "Draw recorded",
        description: recording === "Contribution"
          ? "Cash is up. It is funding, not revenue — it does not touch profit."
          : "Cash is down. It is the owner taking funding back, not a business expense.",
      })
      setRecording(null)
      await load()
    } catch (e: any) {
      toast({ title: "Could not record", description: e?.message ?? String(e), variant: "destructive" })
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
      await reversePoultryOwnerMoney(reversing.poultryOwnerMoneyId, reason.trim())
      toast({ title: "Reversed", description: `${fmt(reversing.amount)} put back.` })
      setReversing(null)
      setReason("")
      await load()
    } catch (e: any) {
      toast({ title: "Could not reverse", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  const typeBadge = (t: string) =>
    t === "Contribution"
      ? "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"
      : "bg-orange-100 text-orange-800 hover:bg-orange-100"

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-end justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <Wallet className="h-6 w-6 text-emerald-600" /> Owner Money
              </h1>
              <p className="text-sm text-slate-500 max-w-2xl">
                Money the owner puts into the business and takes out of it. A contribution is
                <strong> not revenue</strong> and a draw is <strong>not an expense</strong> — both move
                cash, neither touches profit.
              </p>
            </div>
            <div className="flex gap-2 flex-wrap">
              <Button onClick={() => openRecord("Contribution")} className="h-11 sm:h-10">
                <ArrowDownCircle className="h-4 w-4 mr-1" /> Record contribution
              </Button>
              <Button onClick={() => openRecord("Draw")} variant="outline" className="h-11 sm:h-10">
                <ArrowUpCircle className="h-4 w-4 mr-1" /> Record draw
              </Button>
            </div>
          </div>

          <div className="grid grid-cols-2 lg:grid-cols-5 gap-3 mb-4">
            <Stat label="Total contributions" value={fmt(summary?.totalContributions ?? 0)}
                  hint={`${summary?.contributionCount ?? 0} record(s)`} accent="emerald" />
            <Stat label="Total draws" value={fmt(summary?.totalDraws ?? 0)}
                  hint={`${summary?.drawCount ?? 0} record(s)`} accent="orange" />
            <Stat label="Net owner funding" value={fmt(summary?.netFunding ?? 0)}
                  hint="Contributions less draws"
                  accent={(summary?.netFunding ?? 0) >= 0 ? "emerald" : "rose"} />
            <Stat label="Contributions in range" value={fmt(summary?.periodContributions ?? 0)} />
            <Stat label="Draws in range" value={fmt(summary?.periodDraws ?? 0)} />
          </div>

          <Card className="mb-4">
            <CardContent className="pt-6">
              <ListFilters
                search={search} setSearch={setSearch}
                searchPlaceholder="Search number, owner, account, reference or note"
                dateFrom={dateFrom} setDateFrom={setDateFrom}
                dateTo={dateTo} setDateTo={setDateTo}
              />
              <div className="flex flex-wrap gap-2 mt-3">
                {TYPE_FILTERS.map((t) => (
                  <Button key={t} size="sm" variant={typeFilter === t ? "default" : "outline"}
                          onClick={() => setTypeFilter(t)}>{t}</Button>
                ))}
                <span className="w-px bg-slate-200 mx-1" />
                {STATUS_FILTERS.map((st) => (
                  <Button key={st} size="sm" variant={statusFilter === st ? "secondary" : "outline"}
                          onClick={() => setStatusFilter(st)}>{st}</Button>
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
                ? "Nothing recorded yet. Use the buttons above when the owner puts money in or takes it out."
                : "Nothing matches these filters."}
            </CardContent></Card>
          ) : (
            <MobileCardList
              defaultOpen
              striped
              items={pg.pageItems}
              // Keyed on source + id: a Cash-page row carries
              // poultryOwnerMoneyId 0, and the two id spaces overlap anyway.
              getKey={(o) => `${o.source}:${o.sourceId}`}
              primary={(o) => o.transactionNumber ?? `#${o.sourceId}`}
              secondary={(o) => (
                <>
                  <span>{new Date(o.transactionDate).toLocaleDateString()}</span>
                  <span>·</span>
                  <span className="text-xs">{o.accountName ?? "–"}</span>
                </>
              )}
              trailing={(o) => (
                <Badge className={o.status === "Reversed"
                  ? "bg-slate-100 text-slate-700 hover:bg-slate-100"
                  : typeBadge(o.transactionType)}>
                  {o.status === "Reversed" ? "Reversed" : o.transactionType}
                </Badge>
              )}
              highlights={(o) => [{
                label: o.transactionType === "Contribution" ? "In" : "Out",
                value: fmt(o.amount),
              }]}
              details={(o) => [
                { label: "Type", value: o.transactionType },
                { label: "Owner", value: o.ownerName ?? "–" },
                { label: "Account", value: o.accountName ?? "–" },
                { label: "Method", value: o.paymentMethod ?? "–" },
                { label: "Reference", value: o.referenceNumber ?? "–" },
                { label: "Notes", value: o.notes ?? "–" },
                ...(o.status === "Reversed"
                  ? [{ label: "Reversed", value: o.reversalReason ?? "–" }]
                  : []),
              ]}
              actions={(o) => (
                <>
                  {/* Recorded on the Cash page, so it is edited and deleted
                      there. Reversing from here would write a cash row that
                      page knows nothing about. */}
                  {o.status === "Posted" && o.source === "OwnerMoney" && (
                    <Button size="sm" variant="outline" className="flex-1 h-10"
                            onClick={() => { setReversing(o); setReason("") }}>
                      <Undo2 className="h-4 w-4 mr-1" /> Reverse
                    </Button>
                  )}
                  {o.source === "CashAdjustment" && (
                    <span className="flex-1 text-[11px] text-slate-500 self-center">
                      Recorded on the Cash page â€” edit it there.
                    </span>
                  )}
                </>
              )}
              pagination={pg.paginationProps}
              desktopTable={
                <div className="overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Date</TableHead>
                        <TableHead>Number</TableHead>
                        <TableHead>Owner</TableHead>
                        <TableHead>Type</TableHead>
                        <TableHead className="text-right">Amount</TableHead>
                        <TableHead>Cash account</TableHead>
                        <TableHead>Method</TableHead>
                        <TableHead>Reference</TableHead>
                        <TableHead>Status</TableHead>
                        <TableHead></TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {pg.pageItems.map((o) => (
                        <TableRow key={`${o.source}:${o.sourceId}`}>
                          <TableCell className="whitespace-nowrap">
                            {new Date(o.transactionDate).toLocaleDateString()}
                          </TableCell>
                          <TableCell className="font-medium">
                            {o.transactionNumber ?? `#${o.sourceId}`}
                            {o.source === "CashAdjustment" && (
                              <div className="text-[11px] font-normal text-slate-500">
                                From the Cash page
                              </div>
                            )}
                          </TableCell>
                          <TableCell>{o.ownerName ?? "–"}</TableCell>
                          <TableCell>
                            <Badge className={typeBadge(o.transactionType)}>{o.transactionType}</Badge>
                          </TableCell>
                          <TableCell className="text-right font-medium tabular-nums">
                            <span className={o.status === "Reversed" ? "line-through text-slate-400" : ""}>
                              {o.transactionType === "Draw" ? "−" : "+"}{fmt(o.amount)}
                            </span>
                          </TableCell>
                          <TableCell>{o.accountName ?? "–"}</TableCell>
                          <TableCell className="text-slate-500">{o.paymentMethod ?? "–"}</TableCell>
                          <TableCell className="text-slate-500">{o.referenceNumber ?? "–"}</TableCell>
                          <TableCell>
                            <Badge className={o.status === "Reversed"
                              ? "bg-slate-100 text-slate-700 hover:bg-slate-100"
                              : "bg-sky-100 text-sky-800 hover:bg-sky-100"}>
                              {o.status}
                            </Badge>
                          </TableCell>
                          <TableCell className="text-right">
                            {o.status === "Posted" && o.source === "OwnerMoney" && (
                              <Button size="sm" variant="outline"
                                      onClick={() => { setReversing(o); setReason("") }}>
                                <Undo2 className="h-3 w-3 mr-1" /> Reverse
                              </Button>
                            )}
                            {/* Editing and deleting these belongs to the Cash
                                page, which is where they were recorded. */}
                            {o.source === "CashAdjustment" && (
                              <span className="text-[11px] text-slate-500">Cash page</span>
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
      <Dialog open={!!recording} onOpenChange={(o) => { if (!o) setRecording(null) }}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              {recording === "Draw"
                ? <><ArrowUpCircle className="w-5 h-5 text-orange-600" /> Record Owner Draw</>
                : <><ArrowDownCircle className="w-5 h-5 text-emerald-600" /> Record Owner Contribution</>}
            </DialogTitle>
            <DialogDescription>
              {recording === "Draw"
                ? "Cash leaves the account. It is the owner taking funding back — it is not an operating expense and it will not reduce profit."
                : "Cash arrives in the account. It is the owner funding the business — it is not a sale and it will not increase revenue."}
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4">
            <FormSection title={recording === "Draw" ? "Draw" : "Contribution"}
                         color={recording === "Draw" ? "amber" : "emerald"}>
              <FormField label="Date *">
                <Input type="date" value={form.transactionDate}
                       onChange={(e) => setForm((f) => ({ ...f, transactionDate: e.target.value }))} />
              </FormField>
              <FormField label="Amount *">
                <NumberInput value={form.amount} min={0}
                             onChange={(e) => setForm((f) => ({ ...f, amount: e.target.value }))} />
              </FormField>
              <FormField label="Cash account *" full>
                <Select value={form.poultryCashAccountId}
                        onValueChange={(v) => setForm((f) => ({ ...f, poultryCashAccountId: v }))}>
                  <SelectTrigger>
                    <SelectValue placeholder={recording === "Draw" ? "Which account does it leave?" : "Which account does it arrive in?"} />
                  </SelectTrigger>
                  <SelectContent>
                    {accounts.filter((a) => a.isActive).map((a) => (
                      <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>
                        {a.accountName} — {fmt(a.currentBalance)}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </FormField>
            </FormSection>

            {form.poultryCashAccountId && amountNum > 0 && (
              <FormSection title="After this" color="slate" columns={1}>
                <div className="text-sm">
                  <div className="flex items-center justify-between">
                    <span className="text-slate-500">Account balance</span>
                    <span className="tabular-nums">
                      <span className="text-slate-400">{fmt(balanceOf(form.poultryCashAccountId))}</span>
                      {" → "}
                      <span className={after < 0 ? "font-medium text-rose-600" : "font-medium text-slate-900"}>
                        {fmt(after)}
                      </span>
                    </span>
                  </div>
                  {wouldOverdraw && (
                    <p className="text-rose-600 text-xs pt-1">
                      This would take the account below zero, and it is not allowed to go negative.
                      The draw will be rejected.
                    </p>
                  )}
                </div>
              </FormSection>
            )}

            <FormSection title="Details" color="slate">
              <FormField label="Owner">
                <Input value={form.ownerName} placeholder="Whose money is this?"
                       onChange={(e) => setForm((f) => ({ ...f, ownerName: e.target.value }))} />
              </FormField>
              <FormField label="Method">
                <Select value={form.paymentMethod}
                        onValueChange={(v) => setForm((f) => ({ ...f, paymentMethod: v }))}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {PAYMENT_METHODS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}
                  </SelectContent>
                </Select>
              </FormField>
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
            <Button type="button" onClick={() => setRecording(null)}
                    className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
            <Button onClick={save} disabled={saving || wouldOverdraw}>
              {saving ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Recording...</>
                : recording === "Draw"
                  ? <><ArrowUpCircle className="w-4 h-4 mr-2" />Record Draw</>
                  : <><ArrowDownCircle className="w-4 h-4 mr-2" />Record Contribution</>}
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* ---- reverse --------------------------------------------------- */}
      <Dialog open={!!reversing} onOpenChange={(o) => { if (!o) { setReversing(null); setReason("") } }}>
        <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Undo2 className="w-5 h-5 text-amber-600" /> Reverse Owner Money
            </DialogTitle>
            <DialogDescription>
              The original stays on the record. One opposite cash row is added, putting the account
              back where it was, and the record stops counting towards owner funding.
            </DialogDescription>
          </DialogHeader>

          {reversing && (
            <div className="space-y-4">
              <FormSection title="Record being reversed" color="slate" columns={1}>
                <div className="text-sm">
                  <div className="font-medium">
                    {reversing.transactionNumber ?? "#" + reversing.poultryOwnerMoneyId} · {reversing.transactionType}
                  </div>
                  <div className="mt-1">
                    {fmt(reversing.amount)} on {new Date(reversing.transactionDate).toLocaleDateString()}
                    {reversing.accountName ? " · " + reversing.accountName : ""}
                  </div>
                  <div className="text-xs text-slate-500 mt-2">
                    {reversing.transactionType === "Contribution"
                      ? "The money comes back out of the account. If it has since been spent and the account cannot go negative, the reversal will be refused."
                      : "The money goes back into the account."}
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
                      : <><Undo2 className="w-4 h-4 mr-2" />Reverse</>}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}

function Stat({
  label, value, hint, accent = "slate",
}: {
  label: string
  value: string
  hint?: string
  accent?: "slate" | "emerald" | "orange" | "rose"
}) {
  const colour = {
    slate: "text-slate-900",
    emerald: "text-emerald-700",
    orange: "text-orange-700",
    rose: "text-rose-600",
  }[accent]
  return (
    <Card>
      <CardContent className="p-4">
        <p className="text-xs font-medium text-slate-500 uppercase tracking-wider truncate">{label}</p>
        <div className={`text-lg sm:text-xl font-bold mt-1 truncate ${colour}`}>{value}</div>
        {hint && <div className="text-xs text-slate-500 mt-0.5 truncate">{hint}</div>}
      </CardContent>
    </Card>
  )
}
