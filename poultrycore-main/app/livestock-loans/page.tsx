"use client"

// Loans -- money the farm borrowed (bank, microfinance, family), what is left
// to repay, and repayments split into the loan itself and interest. Interest
// is a cost of the farm; repaying the loan itself is not.

import { useCallback, useEffect, useState } from "react"
import { Landmark, Plus } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { useToast } from "@/hooks/use-toast"
import { borrow, listLoans, repayLoan, reverseLoan, type Loan } from "@/lib/api/livestock"
import { AccountSelect, isShort, useCashAccounts } from "@/components/livestock/money-bits"
import { AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, StatCard, fmtDate, fmtMoney, todayIso } from "@/components/livestock/livestock-page"

export default function LivestockLoansPage() {
  const [rows, setRows] = useState<Loan[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [dialog, setDialog] = useState<null | { kind: "borrow" } | { kind: "repay"; loan: Loan }>(null)
  const [reversing, setReversing] = useState<{ kind: "Loan" | "Repayment"; id: number } | null>(null)
  const { reload } = useCashAccounts()
  const load = useCallback(async () => {
    setError(null)
    try { setRows(await listLoans()) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [])
  useEffect(() => { load() }, [load])
  const live = (rows ?? []).filter((l) => !l.reversedAt)

  return (
    <LivestockPage title="Loans" description="Money the farm borrowed and is repaying." icon={Landmark}
      actions={<Button className={AMBER_BUTTON} onClick={() => setDialog({ kind: "borrow" })}><Plus className="h-4 w-4 mr-1" /> Record a loan</Button>}>
      <div className="grid grid-cols-2 lg:grid-cols-3 gap-3">
        <StatCard label="Still to repay" value={fmtMoney(live.reduce((s, l) => s + l.balance, 0))} tone="amber" />
        <StatCard label="Interest paid" value={fmtMoney(live.reduce((s, l) => s + l.interestPaid, 0))} />
      </div>
      {error ? <LoadError message={error} onRetry={load} /> : !rows ? <Loading /> : rows.length === 0 ? <EmptyState title="No loans" /> : (
        <div className="space-y-3">
          {rows.map((l) => (
            <Card key={l.loanId} className={l.reversedAt ? "opacity-50" : ""}>
              <CardHeader className="pb-2 flex-row items-start justify-between space-y-0 gap-2">
                <div>
                  <CardTitle className="text-base">{l.lender}{l.reversedAt && <Badge variant="outline" className="ml-2">Reversed</Badge>}</CardTitle>
                  <p className="text-sm text-stone-500">{fmtMoney(l.amount)} received {fmtDate(l.date)} into {l.accountName}{l.interestNote ? ` · ${l.interestNote}` : ""}{l.dueDate ? ` · due ${fmtDate(l.dueDate)}` : ""}</p>
                </div>
                {!l.reversedAt && (
                  <div className="flex gap-1">
                    {l.balance > 0 && <Button size="sm" className={AMBER_BUTTON} onClick={() => setDialog({ kind: "repay", loan: l })}>Repay</Button>}
                    {l.repayments.every((r) => r.reversedAt) && <Button size="sm" variant="ghost" onClick={() => setReversing({ kind: "Loan", id: l.loanId })}>Reverse</Button>}
                  </div>
                )}
              </CardHeader>
              <CardContent className="text-sm">
                <div className="font-medium mb-1">Left to repay: {fmtMoney(l.balance)}</div>
                {l.repayments.length > 0 && (
                  <ul className="divide-y">
                    {l.repayments.map((r) => (
                      <li key={r.repaymentId} className={`py-1.5 flex justify-between gap-3 ${r.reversedAt ? "opacity-50" : ""}`}>
                        <span>{fmtDate(r.date)} · {r.accountName}{r.reversedAt ? " (reversed)" : ""}</span>
                        <span>{fmtMoney(r.principal)} loan + {fmtMoney(r.interest)} interest
                          {!r.reversedAt && <Button variant="link" size="sm" className="h-auto p-0 ml-2" onClick={() => setReversing({ kind: "Repayment", id: r.repaymentId })}>Reverse</Button>}</span>
                      </li>
                    ))}
                  </ul>
                )}
              </CardContent>
            </Card>
          ))}
        </div>
      )}
      {dialog && <LoanDialog dialog={dialog} onClose={() => setDialog(null)} onDone={() => { setDialog(null); load(); reload() }} />}
      <PromptDialog open={!!reversing} onOpenChange={(o) => !o && setReversing(null)} title="Reverse this?" label="Why" confirmLabel="Reverse" confirmVariant="destructive"
        onSubmit={async (r) => { await reverseLoan(reversing!.kind, reversing!.id, r); setReversing(null); load(); reload() }} />
    </LivestockPage>
  )
}

function LoanDialog({ dialog, onClose, onDone }: { dialog: { kind: "borrow" } | { kind: "repay"; loan: Loan }; onClose: () => void; onDone: () => void }) {
  const { toast } = useToast()
  const { accounts, defaultId } = useCashAccounts()
  const [accountId, setAccountId] = useState<number | null>(null)
  const [lender, setLender] = useState("")
  const [amount, setAmount] = useState("")
  const [interest, setInterest] = useState("")
  const [terms, setTerms] = useState("")
  const [due, setDue] = useState("")
  const [date, setDate] = useState(todayIso())
  const [notes, setNotes] = useState("")
  const [saving, setSaving] = useState(false)
  useEffect(() => { if (!accountId && defaultId) setAccountId(defaultId) }, [defaultId, accountId])
  const repay = dialog.kind === "repay"
  const n = Number(amount) || 0
  const out = n + (Number(interest) || 0)
  const save = async () => {
    setSaving(true)
    try {
      if (dialog.kind === "repay") await repayLoan({ loanId: dialog.loan.loanId, date, principal: n, interest: Number(interest) || 0, accountId: accountId!, notes: notes.trim() || null })
      else await borrow({ lender: lender.trim(), date, amount: n, accountId: accountId!, interestNote: terms.trim() || null, dueDate: due || null, notes: notes.trim() || null })
      toast({ title: "Saved" }); onDone()
    } catch (e: any) { toast({ title: "Not saved", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setSaving(false) }
  }
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader><DialogTitle>{dialog.kind === "repay" ? `Repay ${dialog.loan.lender}` : "Record a loan"}</DialogTitle></DialogHeader>
        <div className="space-y-3">
          {dialog.kind === "repay"
            ? <p className="text-sm text-stone-600">Left to repay: <strong>{fmtMoney(dialog.loan.balance)}</strong></p>
            : <div><Label htmlFor="ln-lender">Lender</Label><Input id="ln-lender" value={lender} onChange={(e) => setLender(e.target.value)} placeholder="Rural bank, susu, family" /></div>}
          <div className="grid grid-cols-2 gap-3">
            <div><Label htmlFor="ln-amt">{repay ? "Off the loan" : "Amount borrowed"}</Label><Input id="ln-amt" type="number" min={0} step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} /></div>
            {repay
              ? <div><Label htmlFor="ln-int">Interest</Label><Input id="ln-int" type="number" min={0} step="0.01" value={interest} onChange={(e) => setInterest(e.target.value)} /></div>
              : <div><Label htmlFor="ln-due">Repay by</Label><Input id="ln-due" type="date" value={due} onChange={(e) => setDue(e.target.value)} /></div>}
          </div>
          {!repay && <div><Label htmlFor="ln-terms">Terms</Label><Input id="ln-terms" value={terms} onChange={(e) => setTerms(e.target.value)} placeholder="e.g. 3% a month" /></div>}
          <div className="grid grid-cols-2 gap-3">
            <div><Label htmlFor="ln-date">Date</Label><Input id="ln-date" type="date" max={todayIso()} value={date} onChange={(e) => setDate(e.target.value)} /></div>
            <AccountSelect label={repay ? "Paid from" : "Into"} value={accountId} onChange={setAccountId} accounts={accounts} spend={repay ? out : undefined} />
          </div>
          <div><Label htmlFor="ln-notes">Notes</Label><Textarea id="ln-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} /></div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || !accountId || (repay ? out <= 0 || (dialog.kind === "repay" && n > dialog.loan.balance) || isShort(accounts, accountId, out) : n <= 0 || !lender.trim())} onClick={save}>{saving ? "Saving…" : "Save"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
