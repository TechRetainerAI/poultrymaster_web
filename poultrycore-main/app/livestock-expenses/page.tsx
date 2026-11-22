"use client"

// Expenses -- every cost of the farm in one list, like the poultry Expenses
// page (migration 471). Typed-in expenses come out of a cash account; the rest
// are read from where they were recorded: purchases (stock, animals, bills on
// credit), animals entered on a batch, stock used on daily records /
// treatments / health records, stock lost, pay runs, loan interest and
// depreciation. Only typed-in expenses can be reversed here.
//
// Stock used is stock that was already bought -- it is shown (as poultry does)
// but kept OUT of "Money spent", so feed is not counted twice.

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { Plus, Receipt } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { useToast } from "@/hooks/use-toast"
import {
  EXPENSE_CATEGORIES, createExpense, listCashAccounts, listExpenses, listGroups, reverseExpense,
  type CashAccount, type Expense, type ExpenseCategory, type LivestockGroup,
} from "@/lib/api/livestock"
import { AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, StatCard, fmtDate, fmtMoney, todayIso } from "@/components/livestock/livestock-page"

const NONE = "__none"
const ALL = "__all"
const firstOfMonth = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-01` }

type Show = "all" | "money" | "used"
const SHOW_LABEL: Record<Show, string> = { all: "Everything", money: "Money spent & owed", used: "Stock used & depreciation" }
const isMoney = (r: Expense) => r.costKind === "Spent" || r.costKind === "Bought"

/** Where a row came from, and the page that holds it. */
function origin(r: Expense): { label: string; href: string | null } {
  switch (r.source) {
    case "Paid": return { label: "Typed in", href: null }
    case "Bill": return { label: `Bill ${r.reference ?? ""}`.trim(), href: `/livestock-purchases/${r.purchaseId}` }
    case "Purchase": return { label: `Purchase ${r.reference ?? ""}`.trim(), href: `/livestock-purchases/${r.purchaseId}` }
    case "Batch": return { label: "Batch", href: "/livestock-batches" }
    case "Animal": return { label: "Tagged animal", href: `/livestock-animals/${r.sourceId}` }
    case "StockUsed":
      if (r.reference === "ProductionRecord") return { label: "Daily record", href: `/livestock-production-records/${r.sourceId}` }
      if (r.reference === "TreatmentDay") return { label: "Treatment", href: "/livestock-treatments" }
      return { label: "Health record", href: "/livestock-health" }
    case "StockLost": return { label: "Stock lost", href: "/livestock-losses" }
    case "PayRun": return { label: "Pay run", href: "/livestock-payroll" }
    case "LoanInterest": return { label: "Loan", href: "/livestock-loans" }
    case "Depreciation": return { label: "Asset", href: "/livestock-assets" }
  }
}

function PaidCell({ r }: { r: Expense }) {
  if (r.costKind === "Used") return <span className="text-stone-500">Already bought</span>
  if (r.costKind === "NonCash") return <span className="text-stone-500">No money moved</span>
  if (r.payStatus === "NotRecorded") return <span className="text-stone-500">No payment recorded</span>
  if (r.payStatus === "Reversed") return <span className="text-stone-500">—</span>
  if (r.payStatus === "Unpaid") return <span className="text-rose-700">Owes {fmtMoney(r.owed ?? r.amount)}{r.payee && <> to {r.payee}</>}</span>
  if (r.payStatus === "PartPaid") return <span className="text-amber-700">Paid {fmtMoney(r.paid ?? 0)} · owes {fmtMoney(r.owed ?? 0)}</span>
  return <span>{r.accountName ?? "Paid"}</span>
}

export default function LivestockExpensesPage() {
  const [rows, setRows] = useState<Expense[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [from, setFrom] = useState(firstOfMonth())
  const [to, setTo] = useState(todayIso())
  const [cat, setCat] = useState(ALL)
  const [show, setShow] = useState<Show>("all")
  const [adding, setAdding] = useState(false)
  const [reversing, setReversing] = useState<Expense | null>(null)

  const load = useCallback(async () => {
    setError(null)
    try { setRows(await listExpenses({ from, to })) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [from, to])
  useEffect(() => { load() }, [load])

  // Kinds offered = whatever is in these dates (stock categories, Animals, Staff pay ... as well as typed-in kinds).
  const kinds = useMemo(() => [...new Set((rows ?? []).map((r) => r.category))].sort(), [rows])
  const shown = useMemo(() => (rows ?? []).filter((r) =>
    (cat === ALL || r.category === cat) && (show === "all" || (show === "money") === isMoney(r))), [rows, cat, show])
  const live = useMemo(() => shown.filter((r) => !r.reversedAt), [shown])
  const byCat = useMemo(() => {
    const m = new Map<string, number>()
    for (const r of live) if (isMoney(r)) m.set(r.category, (m.get(r.category) ?? 0) + r.amount)
    return [...m.entries()].sort((a, b) => b[1] - a[1])
  }, [live])
  const spent = live.filter(isMoney).reduce((s, r) => s + r.amount, 0)
  const owed = live.filter(isMoney).reduce((s, r) => s + (r.owed ?? 0), 0)
  const used = live.filter((r) => !isMoney(r)).reduce((s, r) => s + r.amount, 0)

  return (
    <LivestockPage title="Expenses" description="Running costs of the farm." icon={Receipt}
      actions={
        <>
          <Button asChild variant="outline"><Link href="/livestock-purchases/new">Bill on credit</Link></Button>
          <Button className={AMBER_BUTTON} onClick={() => setAdding(true)}><Plus className="h-4 w-4 mr-1" /> Record expense</Button>
        </>
      }>
      <div className="flex items-center gap-2 flex-wrap">
        <Input type="date" className="w-40" value={from} max={to} onChange={(e) => setFrom(e.target.value)} aria-label="From" />
        <span className="text-sm text-stone-500">to</span>
        <Input type="date" className="w-40" value={to} min={from} max={todayIso()} onChange={(e) => setTo(e.target.value)} aria-label="To" />
        <Select value={cat} onValueChange={setCat}>
          <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
          <SelectContent><SelectItem value={ALL}>Every kind</SelectItem>{kinds.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}</SelectContent>
        </Select>
        <Select value={show} onValueChange={(v) => setShow(v as Show)}>
          <SelectTrigger className="w-56"><SelectValue /></SelectTrigger>
          <SelectContent>{(Object.keys(SHOW_LABEL) as Show[]).map((s) => <SelectItem key={s} value={s}>{SHOW_LABEL[s]}</SelectItem>)}</SelectContent>
        </Select>
      </div>
      {error ? <LoadError message={error} onRetry={load} /> : !rows ? <Loading /> : (
        <>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <StatCard label="Money spent in these dates" value={fmtMoney(spent)} tone="amber" hint="Expenses, bills, purchases, pay, interest" />
            <StatCard label="Still owed" value={fmtMoney(owed)} tone={owed > 0 ? "rose" : "stone"} hint="On purchases and bills" />
            <StatCard label="Stock used & depreciation" value={fmtMoney(used)} hint="Already bought — not a new payment" />
          </div>
          <Card>
            <CardHeader className="pb-1"><CardTitle className="text-sm text-stone-600">Money spent by kind</CardTitle></CardHeader>
            <CardContent className="text-sm flex flex-wrap gap-x-4 gap-y-1">
              {byCat.length === 0 ? <span className="text-stone-500">Nothing yet.</span> : byCat.map(([c, v]) => <span key={c}>{c} <strong>{fmtMoney(v)}</strong></span>)}
            </CardContent>
          </Card>
          {shown.length === 0 ? <EmptyState title="No expenses in these dates" /> : (
            <div className="rounded-md border bg-white overflow-x-auto">
              <Table>
                <TableHeader><TableRow><TableHead>Date</TableHead><TableHead>Kind</TableHead><TableHead>What</TableHead><TableHead>From</TableHead><TableHead>Group</TableHead><TableHead>Paid</TableHead><TableHead className="text-right">Amount</TableHead><TableHead /></TableRow></TableHeader>
                <TableBody>
                  {shown.map((r) => {
                    const o = origin(r)
                    return (
                      <TableRow key={`${r.source}-${r.id}`} className={r.reversedAt ? "opacity-50" : undefined}>
                        <TableCell className="whitespace-nowrap">{fmtDate(r.date)}</TableCell>
                        <TableCell>{r.category}{r.reversedAt && <Badge variant="outline" className="ml-2">Reversed</Badge>}</TableCell>
                        <TableCell className="text-sm">
                          {r.description ?? "—"}{r.source === "Paid" && r.payee && <span className="text-stone-500"> · {r.payee}</span>}
                          {r.costKind === "Used" && <div className="text-[11px] text-stone-500">Stock already bought — not a second payment</div>}
                        </TableCell>
                        <TableCell className="text-sm whitespace-nowrap">{o.href ? <Link className="text-amber-800 hover:underline" href={o.href}>{o.label}</Link> : o.label}</TableCell>
                        <TableCell>{r.groupName ?? "—"}</TableCell>
                        <TableCell className="text-sm"><PaidCell r={r} /></TableCell>
                        <TableCell className={r.costKind === "Used" || r.costKind === "NonCash" ? "text-right text-stone-500" : "text-right"}>{fmtMoney(r.amount)}</TableCell>
                        <TableCell className="text-right">{r.source === "Paid" && !r.reversedAt && <Button variant="ghost" size="sm" onClick={() => setReversing(r)}>Reverse</Button>}</TableCell>
                      </TableRow>
                    )
                  })}
                </TableBody>
              </Table>
            </div>
          )}
        </>
      )}
      {adding && <ExpenseDialog onClose={() => setAdding(false)} onDone={() => { setAdding(false); load() }} />}
      <PromptDialog
        open={!!reversing}
        onOpenChange={(o) => !o && setReversing(null)}
        title="Reverse this expense?"
        description="The money goes back into the account it was paid from."
        label="Why"
        confirmLabel="Reverse"
        confirmVariant="destructive"
        onSubmit={async (reason) => { await reverseExpense(reversing!.id, reason); setReversing(null); load() }}
      />
    </LivestockPage>
  )
}

function ExpenseDialog({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const { toast } = useToast()
  const [accounts, setAccounts] = useState<CashAccount[]>([])
  const [groups, setGroups] = useState<LivestockGroup[]>([])
  const [date, setDate] = useState(todayIso())
  const [category, setCategory] = useState<ExpenseCategory>("Labour")
  const [description, setDescription] = useState("")
  const [amount, setAmount] = useState("")
  const [groupId, setGroupId] = useState<number | null>(null)
  const [accountId, setAccountId] = useState<number | null>(null)
  const [paidTo, setPaidTo] = useState("")
  const [saving, setSaving] = useState(false)
  useEffect(() => {
    listCashAccounts().then((a) => { setAccounts(a); setAccountId(a.find((x) => x.isDefault)?.accountId ?? a[0]?.accountId ?? null) }).catch(() => setAccounts([]))
    listGroups().then(setGroups).catch(() => setGroups([]))
  }, [])
  const acct = accounts.find((a) => a.accountId === accountId)
  const short = acct && !acct.allowNegative && Number(amount) > acct.balance
  const save = async () => {
    setSaving(true)
    try {
      await createExpense({ date, category, description: description.trim() || null, amount: Number(amount), groupId, accountId: accountId!, paidTo: paidTo.trim() || null, reference: null })
      toast({ title: "Expense recorded" }); onDone()
    } catch (e: any) { toast({ title: "Not recorded", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setSaving(false) }
  }
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader><DialogTitle>Record an expense</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label>Kind</Label>
              <Select value={category} onValueChange={(v) => setCategory(v as ExpenseCategory)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{EXPENSE_CATEGORIES.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}</SelectContent>
              </Select>
            </div>
            <div><Label htmlFor="ex-amt">Amount</Label><Input id="ex-amt" type="number" min={0} step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} /></div>
          </div>
          <div><Label htmlFor="ex-desc">What for{category === "Other" ? " (required)" : ""}</Label><Textarea id="ex-desc" rows={2} value={description} onChange={(e) => setDescription(e.target.value)} /></div>
          <div className="grid grid-cols-2 gap-3">
            <div><Label htmlFor="ex-date">Date</Label><Input id="ex-date" type="date" max={todayIso()} value={date} onChange={(e) => setDate(e.target.value)} /></div>
            <div><Label htmlFor="ex-to">Paid to</Label><Input id="ex-to" value={paidTo} onChange={(e) => setPaidTo(e.target.value)} /></div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label>Paid from</Label>
              <Select value={accountId ? String(accountId) : ""} onValueChange={(v) => setAccountId(Number(v))}>
                <SelectTrigger><SelectValue placeholder={accounts.length ? "Choose" : "Add a cash account first"} /></SelectTrigger>
                <SelectContent>{accounts.map((a) => <SelectItem key={a.accountId} value={String(a.accountId)}>{a.name} · {fmtMoney(a.balance)}</SelectItem>)}</SelectContent>
              </Select>
              {short && <p className="text-xs text-rose-700 mt-1">{acct!.name} holds only {fmtMoney(acct!.balance)}.</p>}
            </div>
            <div>
              <Label>For a group (optional)</Label>
              <Select value={groupId ? String(groupId) : NONE} onValueChange={(v) => setGroupId(v === NONE ? null : Number(v))}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent><SelectItem value={NONE}>The whole farm</SelectItem>{groups.map((g) => <SelectItem key={g.groupId} value={String(g.groupId)}>{g.name}</SelectItem>)}</SelectContent>
              </Select>
            </div>
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || !(Number(amount) > 0) || !accountId || !!short || (category === "Other" && !description.trim())} onClick={save}>{saving ? "Saving…" : "Record"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
