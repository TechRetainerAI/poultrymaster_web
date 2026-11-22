"use client"

// Cash Transfers -- moving money between the farm's own accounts (cash to
// bank, bank to mobile money). A bank fee is recorded as a Fees expense.

import { useCallback, useEffect, useState } from "react"
import { ArrowLeftRight, Plus } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { useToast } from "@/hooks/use-toast"
import { createTransfer, listTransfers, reverseTransfer, type CashTransfer } from "@/lib/api/livestock"
import { AccountSelect, isShort, useCashAccounts } from "@/components/livestock/money-bits"
import { AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, fmtDate, fmtMoney, todayIso } from "@/components/livestock/livestock-page"

export default function LivestockCashTransfersPage() {
  const { toast } = useToast()
  const { accounts, defaultId, reload } = useCashAccounts()
  const [rows, setRows] = useState<CashTransfer[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [adding, setAdding] = useState(false)
  const [reversing, setReversing] = useState<CashTransfer | null>(null)
  const [f, setF] = useState({ date: todayIso(), from: null as number | null, to: null as number | null, amount: "", fee: "", notes: "" })
  const [saving, setSaving] = useState(false)

  const load = useCallback(async () => {
    setError(null)
    try { setRows(await listTransfers()) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [])
  useEffect(() => { load() }, [load])
  useEffect(() => { if (adding) setF({ date: todayIso(), from: defaultId, to: null, amount: "", fee: "", notes: "" }) }, [adding, defaultId])

  const total = (Number(f.amount) || 0) + (Number(f.fee) || 0)
  const save = async () => {
    setSaving(true)
    try {
      await createTransfer({ date: f.date, fromAccountId: f.from!, toAccountId: f.to!, amount: Number(f.amount), fee: Number(f.fee) || 0, notes: f.notes.trim() || null })
      toast({ title: "Money moved" }); setAdding(false); load(); reload()
    } catch (e: any) { toast({ title: "Not moved", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setSaving(false) }
  }

  return (
    <LivestockPage title="Move money" description="Moving money between your own accounts." icon={ArrowLeftRight}
      actions={<Button className={AMBER_BUTTON} disabled={accounts.length < 2} onClick={() => setAdding(true)}><Plus className="h-4 w-4 mr-1" /> Move money</Button>}>
      {accounts.length < 2 && <p className="text-sm text-stone-600">Add a second cash account to move money between them.</p>}
      {error ? <LoadError message={error} onRetry={load} /> : !rows ? <Loading /> : rows.length === 0 ? <EmptyState title="No money moved yet" /> : (
        <div className="rounded-md border bg-white overflow-x-auto">
          <Table>
            <TableHeader><TableRow><TableHead>Date</TableHead><TableHead>From</TableHead><TableHead>To</TableHead><TableHead className="text-right">Amount</TableHead><TableHead className="text-right">Fee</TableHead><TableHead>Notes</TableHead><TableHead /></TableRow></TableHeader>
            <TableBody>
              {rows.map((t) => (
                <TableRow key={t.transferId} className={t.reversedAt ? "opacity-50" : undefined}>
                  <TableCell>{fmtDate(t.date)}</TableCell>
                  <TableCell>{t.fromName}</TableCell>
                  <TableCell>{t.toName}{t.reversedAt && <Badge variant="outline" className="ml-2">Reversed</Badge>}</TableCell>
                  <TableCell className="text-right">{fmtMoney(t.amount)}</TableCell>
                  <TableCell className="text-right">{t.fee ? fmtMoney(t.fee) : "—"}</TableCell>
                  <TableCell className="text-sm text-stone-600">{t.reverseReason ?? t.notes ?? ""}</TableCell>
                  <TableCell className="text-right">{!t.reversedAt && <Button variant="ghost" size="sm" onClick={() => setReversing(t)}>Reverse</Button>}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}
      <Dialog open={adding} onOpenChange={setAdding}>
        <DialogContent>
          <DialogHeader><DialogTitle>Move money</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <AccountSelect label="From" value={f.from} onChange={(v) => setF((s) => ({ ...s, from: v }))} accounts={accounts} spend={total} exclude={f.to} />
              <AccountSelect label="To" value={f.to} onChange={(v) => setF((s) => ({ ...s, to: v }))} accounts={accounts} exclude={f.from} />
            </div>
            <div className="grid grid-cols-3 gap-3">
              <div><Label htmlFor="mt-amt">Amount</Label><Input id="mt-amt" type="number" min={0} step="0.01" value={f.amount} onChange={(e) => setF((s) => ({ ...s, amount: e.target.value }))} /></div>
              <div><Label htmlFor="mt-fee">Fee charged</Label><Input id="mt-fee" type="number" min={0} step="0.01" value={f.fee} onChange={(e) => setF((s) => ({ ...s, fee: e.target.value }))} /></div>
              <div><Label htmlFor="mt-date">Date</Label><Input id="mt-date" type="date" max={todayIso()} value={f.date} onChange={(e) => setF((s) => ({ ...s, date: e.target.value }))} /></div>
            </div>
            <div><Label htmlFor="mt-notes">Notes</Label><Textarea id="mt-notes" rows={2} value={f.notes} onChange={(e) => setF((s) => ({ ...s, notes: e.target.value }))} /></div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setAdding(false)}>Cancel</Button>
            <Button className={AMBER_BUTTON} disabled={saving || !f.from || !f.to || !(Number(f.amount) > 0) || isShort(accounts, f.from, total)} onClick={save}>{saving ? "Moving…" : "Move"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
      <PromptDialog open={!!reversing} onOpenChange={(o) => !o && setReversing(null)} title="Reverse this move?"
        description="The money goes back to where it came from, and any fee is reversed." label="Why" confirmLabel="Reverse" confirmVariant="destructive"
        onSubmit={async (r) => { await reverseTransfer(reversing!.transferId, r); setReversing(null); load(); reload() }} />
    </LivestockPage>
  )
}
