"use client"

// Payroll -- paying staff for a period: each person's pay, other deductions,
// and what comes back off their advance. The net leaves one account; gross
// pay is the farm's labour cost.

import { Fragment, useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { Banknote, Plus } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { useToast } from "@/hooks/use-toast"
import { createPayRun, listPayRuns, listStaff, reversePayRun, type PayRun, type Staff } from "@/lib/api/livestock"
import { AccountSelect, firstOfMonth, isShort, useCashAccounts } from "@/components/livestock/money-bits"
import { AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, fmtDate, fmtMoney, todayIso } from "@/components/livestock/livestock-page"

export default function LivestockPayrollPage() {
  const [runs, setRuns] = useState<PayRun[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [paying, setPaying] = useState(false)
  const [open, setOpen] = useState<number | null>(null)
  const [reversing, setReversing] = useState<PayRun | null>(null)
  const load = useCallback(async () => {
    setError(null)
    try { setRuns(await listPayRuns()) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [])
  useEffect(() => { load() }, [load])

  return (
    <LivestockPage title="Payroll" description="Paying the people who work on the farm." icon={Banknote}
      actions={
        <>
          <Button asChild variant="outline"><Link href="/livestock-staff">Staff</Link></Button>
          <Button className={AMBER_BUTTON} onClick={() => setPaying(true)}><Plus className="h-4 w-4 mr-1" /> Pay staff</Button>
        </>
      }>
      {error ? <LoadError message={error} onRetry={load} /> : !runs ? <Loading /> : runs.length === 0 ? <EmptyState title="Nobody paid yet" /> : (
        <div className="rounded-md border bg-white overflow-x-auto">
          <Table>
            <TableHeader><TableRow><TableHead>Paid on</TableHead><TableHead>For</TableHead><TableHead>From</TableHead><TableHead className="text-right">People</TableHead><TableHead className="text-right">Gross</TableHead><TableHead className="text-right">Paid out</TableHead><TableHead /></TableRow></TableHeader>
            <TableBody>
              {runs.map((r) => (
                <Fragment key={r.runId}>
                  <TableRow className={`cursor-pointer hover:bg-amber-50/60 ${r.reversedAt ? "opacity-50" : ""}`} onClick={() => setOpen(open === r.runId ? null : r.runId)}>
                    <TableCell>{fmtDate(r.payDate)}{r.reversedAt && <Badge variant="outline" className="ml-2">Reversed</Badge>}</TableCell>
                    <TableCell>{fmtDate(r.periodStart)} – {fmtDate(r.periodEnd)}</TableCell>
                    <TableCell>{r.accountName}</TableCell>
                    <TableCell className="text-right">{r.lines.length}</TableCell>
                    <TableCell className="text-right">{fmtMoney(r.gross)}</TableCell>
                    <TableCell className="text-right font-medium">{fmtMoney(r.net)}</TableCell>
                    <TableCell className="text-right">{!r.reversedAt && <Button variant="ghost" size="sm" onClick={(e) => { e.stopPropagation(); setReversing(r) }}>Reverse</Button>}</TableCell>
                  </TableRow>
                  {open === r.runId && r.lines.map((l) => (
                    <TableRow key={`${r.runId}-${l.staffId}`} className="bg-stone-50 text-sm">
                      <TableCell /><TableCell colSpan={2}>{l.name}{l.days ? ` · ${l.days} days` : ""}</TableCell>
                      <TableCell className="text-right">{l.deductions ? `−${fmtMoney(l.deductions)}` : ""}</TableCell>
                      <TableCell className="text-right">{fmtMoney(l.gross)}</TableCell>
                      <TableCell className="text-right">{fmtMoney(l.net)}{l.loanRepayment ? <div className="text-xs text-stone-500">advance −{fmtMoney(l.loanRepayment)}</div> : null}</TableCell>
                      <TableCell />
                    </TableRow>
                  ))}
                </Fragment>
              ))}
            </TableBody>
          </Table>
        </div>
      )}
      {paying && <PayDialog onClose={() => setPaying(false)} onDone={() => { setPaying(false); load() }} />}
      <PromptDialog open={!!reversing} onOpenChange={(o) => !o && setReversing(null)} title="Reverse this pay run?"
        description="The money goes back into the account, and advance repayments taken from pay are put back." label="Why" confirmLabel="Reverse" confirmVariant="destructive"
        onSubmit={async (r) => { await reversePayRun(reversing!.runId, r); setReversing(null); load() }} />
    </LivestockPage>
  )
}

type Line = { staff: Staff; include: boolean; days: string; gross: string; deductions: string; loan: string }

function PayDialog({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const { toast } = useToast()
  const { accounts, defaultId } = useCashAccounts()
  const [accountId, setAccountId] = useState<number | null>(null)
  const [from, setFrom] = useState(firstOfMonth())
  const [to, setTo] = useState(todayIso())
  const [payDate, setPayDate] = useState(todayIso())
  const [lines, setLines] = useState<Line[]>([])
  const [saving, setSaving] = useState(false)
  useEffect(() => { if (!accountId && defaultId) setAccountId(defaultId) }, [defaultId, accountId])
  useEffect(() => {
    listStaff().then((s) => setLines(s.map((x) => ({ staff: x, include: true, days: x.payType === "Daily" ? "" : "",
      gross: x.payType === "Monthly" ? String(x.payRate) : "", deductions: "", loan: "" })))).catch(() => setLines([]))
  }, [])
  const setLine = (i: number, patch: Partial<Line>) => setLines((ls) => ls.map((l, j) => {
    if (j !== i) return l
    const n = { ...l, ...patch }
    if (patch.days !== undefined && l.staff.payType === "Daily") n.gross = String(Math.round((Number(patch.days) || 0) * l.staff.payRate * 100) / 100)
    return n
  }))
  const net = (l: Line) => (Number(l.gross) || 0) - (Number(l.deductions) || 0) - (Number(l.loan) || 0)
  const picked = lines.filter((l) => l.include)
  const total = useMemo(() => picked.reduce((s, l) => s + net(l), 0), [picked])
  const bad = picked.some((l) => net(l) < 0 || (Number(l.loan) || 0) > l.staff.owes)
  const save = async () => {
    setSaving(true)
    try {
      await createPayRun({ periodStart: from, periodEnd: to, payDate, accountId: accountId!, notes: null,
        lines: picked.map((l) => ({ staffId: l.staff.staffId, days: l.days ? Number(l.days) : null, gross: Number(l.gross) || 0,
          deductions: Number(l.deductions) || 0, loanRepayment: Number(l.loan) || 0, notes: null })) })
      toast({ title: `Paid ${picked.length} people ${fmtMoney(total)}` }); onDone()
    } catch (e: any) { toast({ title: "Not paid", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setSaving(false) }
  }
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-4xl">
        <DialogHeader><DialogTitle>Pay staff</DialogTitle></DialogHeader>
        <div className="space-y-3 max-h-[70vh] overflow-y-auto pr-1">
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <div><Label htmlFor="pr-from">For work from</Label><Input id="pr-from" type="date" value={from} max={to} onChange={(e) => setFrom(e.target.value)} /></div>
            <div><Label htmlFor="pr-to">To</Label><Input id="pr-to" type="date" value={to} min={from} onChange={(e) => setTo(e.target.value)} /></div>
            <div><Label htmlFor="pr-pay">Paid on</Label><Input id="pr-pay" type="date" max={todayIso()} value={payDate} onChange={(e) => setPayDate(e.target.value)} /></div>
            <AccountSelect label="Paid from" value={accountId} onChange={setAccountId} accounts={accounts} spend={total} />
          </div>
          {lines.length === 0 ? <EmptyState title="Add staff first"><Link className="underline" href="/livestock-staff">Staff</Link></EmptyState> : (
            <Table>
              <TableHeader><TableRow><TableHead /><TableHead>Person</TableHead><TableHead className="w-20">Days</TableHead><TableHead className="w-28">Pay</TableHead><TableHead className="w-28">Deductions</TableHead><TableHead className="w-28">Off advance</TableHead><TableHead className="text-right">Paid out</TableHead></TableRow></TableHeader>
              <TableBody>
                {lines.map((l, i) => (
                  <TableRow key={l.staff.staffId} className={l.include ? "" : "opacity-50"}>
                    <TableCell><input type="checkbox" aria-label={`Pay ${l.staff.name}`} checked={l.include} onChange={(e) => setLine(i, { include: e.target.checked })} /></TableCell>
                    <TableCell>{l.staff.name}<div className="text-xs text-stone-500">{fmtMoney(l.staff.payRate)} {l.staff.payType === "Daily" ? "a day" : "a month"}</div></TableCell>
                    <TableCell>{l.staff.payType === "Daily" ? <Input type="number" min={0} step="0.5" value={l.days} onChange={(e) => setLine(i, { days: e.target.value })} /> : null}</TableCell>
                    <TableCell><Input type="number" min={0} step="0.01" value={l.gross} onChange={(e) => setLine(i, { gross: e.target.value })} /></TableCell>
                    <TableCell><Input type="number" min={0} step="0.01" value={l.deductions} onChange={(e) => setLine(i, { deductions: e.target.value })} /></TableCell>
                    <TableCell>
                      {l.staff.owes > 0 ? (
                        <>
                          <Input type="number" min={0} max={l.staff.owes} step="0.01" value={l.loan} onChange={(e) => setLine(i, { loan: e.target.value })} />
                          <div className="text-xs text-stone-500">owes {fmtMoney(l.staff.owes)}</div>
                        </>
                      ) : null}
                    </TableCell>
                    <TableCell className={`text-right font-medium ${net(l) < 0 ? "text-rose-700" : ""}`}>{fmtMoney(net(l))}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
          <div className="text-right font-semibold">Paid out in all: {fmtMoney(total)}</div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || picked.length === 0 || bad || !accountId || isShort(accounts, accountId, total)} onClick={save}>{saving ? "Paying…" : "Pay"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
