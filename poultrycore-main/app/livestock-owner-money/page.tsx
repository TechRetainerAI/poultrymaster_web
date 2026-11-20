"use client"

// Owner Money -- money the owner puts into the farm or takes out. It moves
// cash but is not income or a cost, so it is kept apart from both.

import { useCallback, useEffect, useState } from "react"
import { PiggyBank, Plus } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { useToast } from "@/hooks/use-toast"
import { getOwnerMoney, recordOwnerMoney, reverseOwnerMoney, type OwnerMoney } from "@/lib/api/livestock"
import { AccountSelect, isShort, useCashAccounts } from "@/components/livestock/money-bits"
import { AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, StatCard, fmtDate, fmtMoney, todayIso } from "@/components/livestock/livestock-page"

export default function LivestockOwnerMoneyPage() {
  const { toast } = useToast()
  const { accounts, defaultId, reload } = useCashAccounts()
  const [data, setData] = useState<OwnerMoney | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [adding, setAdding] = useState(false)
  const [reversing, setReversing] = useState<number | null>(null)
  const [f, setF] = useState({ direction: "In" as "In" | "Out", amount: "", date: todayIso(), accountId: null as number | null, notes: "" })
  const [saving, setSaving] = useState(false)
  const load = useCallback(async () => {
    setError(null)
    try { setData(await getOwnerMoney()) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [])
  useEffect(() => { load() }, [load])
  useEffect(() => { if (adding) setF({ direction: "In", amount: "", date: todayIso(), accountId: defaultId, notes: "" }) }, [adding, defaultId])
  const n = Number(f.amount) || 0
  const save = async () => {
    setSaving(true)
    try { await recordOwnerMoney({ date: f.date, direction: f.direction, amount: n, accountId: f.accountId!, notes: f.notes.trim() || null }); toast({ title: "Saved" }); setAdding(false); load(); reload() }
    catch (e: any) { toast({ title: "Not saved", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setSaving(false) }
  }
  return (
    <LivestockPage title="Owner money" description="Money the owner puts in or takes out. Not income, not a cost." icon={PiggyBank}
      actions={<Button className={AMBER_BUTTON} onClick={() => setAdding(true)}><Plus className="h-4 w-4 mr-1" /> Record</Button>}>
      {error ? <LoadError message={error} onRetry={load} /> : !data ? <Loading /> : (
        <>
          <div className="grid grid-cols-2 lg:grid-cols-3 gap-3">
            <StatCard label="Put in" value={fmtMoney(data.putIn)} tone="emerald" />
            <StatCard label="Taken out" value={fmtMoney(data.tookOut)} tone="rose" />
            <StatCard label="Owner has put in, net" value={fmtMoney(data.putIn - data.tookOut)} tone="amber" />
          </div>
          {data.entries.length === 0 ? <EmptyState title="Nothing recorded yet" /> : (
            <div className="rounded-md border bg-white overflow-x-auto">
              <Table>
                <TableHeader><TableRow><TableHead>Date</TableHead><TableHead>What</TableHead><TableHead>Account</TableHead><TableHead className="text-right">Amount</TableHead><TableHead>Notes</TableHead><TableHead /></TableRow></TableHeader>
                <TableBody>
                  {data.entries.map((e) => (
                    <TableRow key={e.entryId} className={e.reversedAt ? "opacity-50" : undefined}>
                      <TableCell>{fmtDate(e.date)}</TableCell>
                      <TableCell>{e.direction === "In" ? "Put in" : "Taken out"}{e.reversedAt && <Badge variant="outline" className="ml-2">Reversed</Badge>}</TableCell>
                      <TableCell>{e.accountName}</TableCell>
                      <TableCell className={`text-right ${e.direction === "In" ? "text-emerald-700" : "text-rose-700"}`}>{fmtMoney(e.amount)}</TableCell>
                      <TableCell className="text-sm text-stone-600">{e.reverseReason ?? e.notes ?? ""}</TableCell>
                      <TableCell className="text-right">{!e.reversedAt && <Button variant="ghost" size="sm" onClick={() => setReversing(e.entryId)}>Reverse</Button>}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </>
      )}
      <Dialog open={adding} onOpenChange={setAdding}>
        <DialogContent>
          <DialogHeader><DialogTitle>Owner money</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <div className="grid grid-cols-3 gap-3">
              <div>
                <Label>What</Label>
                <Select value={f.direction} onValueChange={(v) => setF((s) => ({ ...s, direction: v as "In" | "Out" }))}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent><SelectItem value="In">Put in</SelectItem><SelectItem value="Out">Taken out</SelectItem></SelectContent>
                </Select>
              </div>
              <div><Label htmlFor="om-amt">Amount</Label><Input id="om-amt" type="number" min={0} step="0.01" value={f.amount} onChange={(e) => setF((s) => ({ ...s, amount: e.target.value }))} /></div>
              <div><Label htmlFor="om-date">Date</Label><Input id="om-date" type="date" max={todayIso()} value={f.date} onChange={(e) => setF((s) => ({ ...s, date: e.target.value }))} /></div>
            </div>
            <AccountSelect label={f.direction === "In" ? "Into" : "From"} value={f.accountId} onChange={(v) => setF((s) => ({ ...s, accountId: v }))} accounts={accounts} spend={f.direction === "Out" ? n : undefined} />
            <div><Label htmlFor="om-notes">Notes</Label><Textarea id="om-notes" rows={2} value={f.notes} onChange={(e) => setF((s) => ({ ...s, notes: e.target.value }))} /></div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setAdding(false)}>Cancel</Button>
            <Button className={AMBER_BUTTON} disabled={saving || n <= 0 || !f.accountId || (f.direction === "Out" && isShort(accounts, f.accountId, n))} onClick={save}>{saving ? "Saving…" : "Save"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
      <PromptDialog open={reversing != null} onOpenChange={(o) => !o && setReversing(null)} title="Reverse this?" label="Why" confirmLabel="Reverse" confirmVariant="destructive"
        onSubmit={async (r) => { await reverseOwnerMoney(reversing!, r); setReversing(null); load(); reload() }} />
    </LivestockPage>
  )
}
