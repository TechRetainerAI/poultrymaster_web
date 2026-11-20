"use client"

// Expenses -- running costs: labour, vet, transport, fuel, utilities... Paid
// expenses come out of a cash account now; bills on credit are entered as a
// purchase from the supplier (an expense line) and listed here too.

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

export default function LivestockExpensesPage() {
  const [rows, setRows] = useState<Expense[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [from, setFrom] = useState(firstOfMonth())
  const [to, setTo] = useState(todayIso())
  const [cat, setCat] = useState(ALL)
  const [adding, setAdding] = useState(false)
  const [reversing, setReversing] = useState<Expense | null>(null)

  const load = useCallback(async () => {
    setError(null)
    try { setRows(await listExpenses({ from, to, category: cat === ALL ? undefined : (cat as ExpenseCategory) })) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [from, to, cat])
  useEffect(() => { load() }, [load])

  const live = useMemo(() => (rows ?? []).filter((r) => !r.reversedAt), [rows])
  const byCat = useMemo(() => {
    const m = new Map<string, number>()
    for (const r of live) m.set(r.category, (m.get(r.category) ?? 0) + r.amount)
    return [...m.entries()].sort((a, b) => b[1] - a[1])
  }, [live])
  const total = live.reduce((s, r) => s + r.amount, 0)

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
          <SelectContent><SelectItem value={ALL}>Everything</SelectItem>{EXPENSE_CATEGORIES.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}</SelectContent>
        </Select>
      </div>
      {error ? <LoadError message={error} onRetry={load} /> : !rows ? <Loading /> : (
        <>
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-3">
            <StatCard label="Spent in these dates" value={fmtMoney(total)} tone="amber" />
            <Card className="lg:col-span-2">
              <CardHeader className="pb-1"><CardTitle className="text-sm text-stone-600">By kind</CardTitle></CardHeader>
              <CardContent className="text-sm flex flex-wrap gap-x-4 gap-y-1">
                {byCat.length === 0 ? <span className="text-stone-500">Nothing yet.</span> : byCat.map(([c, v]) => <span key={c}>{c} <strong>{fmtMoney(v)}</strong></span>)}
              </CardContent>
            </Card>
          </div>
          {rows.length === 0 ? <EmptyState title="No expenses in these dates" /> : (
            <div className="rounded-md border bg-white overflow-x-auto">
              <Table>
                <TableHeader><TableRow><TableHead>Date</TableHead><TableHead>Kind</TableHead><TableHead>What</TableHead><TableHead>Group</TableHead><TableHead>Paid</TableHead><TableHead className="text-right">Amount</TableHead><TableHead /></TableRow></TableHeader>
                <TableBody>
                  {rows.map((r) => (
                    <TableRow key={`${r.source}-${r.id}`} className={r.reversedAt ? "opacity-50" : undefined}>
                      <TableCell className="whitespace-nowrap">{fmtDate(r.date)}</TableCell>
                      <TableCell>{r.category}{r.reversedAt && <Badge variant="outline" className="ml-2">Reversed</Badge>}</TableCell>
                      <TableCell className="text-sm">{r.description ?? "—"}{r.payee && <span className="text-stone-500"> · {r.payee}</span>}</TableCell>
                      <TableCell>{r.groupName ?? "—"}</TableCell>
                      <TableCell className="text-sm">{r.source === "Bill" ? <Link className="text-amber-800 hover:underline" href={`/livestock-purchases/${r.purchaseId}`}>On credit</Link> : r.accountName}</TableCell>
                      <TableCell className="text-right">{fmtMoney(r.amount)}</TableCell>
                      <TableCell className="text-right">{r.source === "Paid" && !r.reversedAt && <Button variant="ghost" size="sm" onClick={() => setReversing(r)}>Reverse</Button>}</TableCell>
                    </TableRow>
                  ))}
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
