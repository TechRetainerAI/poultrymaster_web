"use client"

// Staff -- the people who work on the farm, their pay rate, and the advances
// they owe. Advances are lent from a cash account and repaid in cash or from
// pay (on the pay run).

import { useCallback, useEffect, useState } from "react"
import { HandCoins, Pencil, Plus, Users2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Switch } from "@/components/ui/switch"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { useToast } from "@/hooks/use-toast"
import {
  lendToStaff, listStaff, listStaffLoans, reverseStaffLoan, saveStaff, staffRepays,
  type Staff, type StaffInput, type StaffLoanEntry,
} from "@/lib/api/livestock"
import { AccountSelect, isShort, useCashAccounts } from "@/components/livestock/money-bits"
import { AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, fmtDate, fmtMoney, todayIso } from "@/components/livestock/livestock-page"

export default function LivestockStaffPage() {
  const [rows, setRows] = useState<Staff[] | null>(null)
  const [entries, setEntries] = useState<StaffLoanEntry[]>([])
  const [error, setError] = useState<string | null>(null)
  const [showAll, setShowAll] = useState(false)
  const [editing, setEditing] = useState<{ staff?: Staff } | null>(null)
  const [money, setMoney] = useState<{ staff: Staff; kind: "lend" | "repay" } | null>(null)
  const [reversing, setReversing] = useState<StaffLoanEntry | null>(null)
  const pg = usePagination(rows ?? [], 10)
  const entriesPg = usePagination(entries, 10)

  const load = useCallback(async () => {
    setError(null)
    try {
      const [s, e] = await Promise.all([listStaff(showAll), listStaffLoans()])
      setRows(s); setEntries(e)
    } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [showAll])
  useEffect(() => { load() }, [load])

  return (
    <LivestockPage title="Staff" description="Who works on the farm, their pay, and advances owed." icon={Users2}
      actions={<Button className={AMBER_BUTTON} onClick={() => setEditing({})}><Plus className="h-4 w-4 mr-1" /> Add person</Button>}>
      <label className="flex items-center gap-2 text-sm text-stone-600"><Switch checked={showAll} onCheckedChange={setShowAll} /> Show people who have left</label>
      {error ? <LoadError message={error} onRetry={load} /> : !rows ? <Loading /> : rows.length === 0 ? <EmptyState title="No staff yet" /> : (
        <div className="rounded-md border bg-white overflow-x-auto">
          <Table>
            <TableHeader><TableRow><TableHead>Name</TableHead><TableHead>Role</TableHead><TableHead>Phone</TableHead><TableHead className="text-right">Pay</TableHead><TableHead className="text-right">Owes</TableHead><TableHead>Last paid</TableHead><TableHead /></TableRow></TableHeader>
            <TableBody>
              {pg.pageItems.map((s) => (
                <TableRow key={s.staffId} className={s.isActive ? "" : "opacity-60"}>
                  <TableCell className="font-medium">{s.name}{!s.isActive && <Badge variant="outline" className="ml-2">Left</Badge>}</TableCell>
                  <TableCell>{s.role ?? "—"}</TableCell>
                  <TableCell>{s.phone ?? "—"}</TableCell>
                  <TableCell className="text-right">{fmtMoney(s.payRate)} {s.payType === "Daily" ? "a day" : "a month"}</TableCell>
                  <TableCell className={`text-right ${s.owes > 0 ? "text-amber-800 font-medium" : ""}`}>{s.owes > 0 ? fmtMoney(s.owes) : "—"}</TableCell>
                  <TableCell>{fmtDate(s.lastPaid)}</TableCell>
                  <TableCell className="text-right whitespace-nowrap">
                    <Button variant="ghost" size="sm" onClick={() => setMoney({ staff: s, kind: "lend" })}><HandCoins className="h-4 w-4 mr-1" />Advance</Button>
                    {s.owes > 0 && <Button variant="ghost" size="sm" onClick={() => setMoney({ staff: s, kind: "repay" })}>Repaid</Button>}
                    <Button variant="ghost" size="icon" aria-label={`Edit ${s.name}`} onClick={() => setEditing({ staff: s })}><Pencil className="h-4 w-4" /></Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
          <DataPagination {...pg.paginationProps} variant="records" />
        </div>
      )}
      {entries.length > 0 && (
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-base">Advances and repayments</CardTitle></CardHeader>
          <CardContent>
            <Table>
              <TableHeader><TableRow><TableHead>Date</TableHead><TableHead>Person</TableHead><TableHead>What</TableHead><TableHead className="text-right">Amount</TableHead><TableHead /></TableRow></TableHeader>
              <TableBody>
                {entriesPg.pageItems.map((e) => (
                  <TableRow key={`${e.kind}-${e.id}`} className={e.reversedAt ? "opacity-50" : undefined}>
                    <TableCell>{fmtDate(e.date)}</TableCell><TableCell>{e.name}</TableCell>
                    <TableCell>{e.kind === "Loan" ? `Advance${e.note ? `: ${e.note}` : ""}` : e.note}{e.reversedAt && <Badge variant="outline" className="ml-2">Reversed</Badge>}</TableCell>
                    <TableCell className={`text-right ${e.kind === "Loan" ? "text-rose-700" : "text-emerald-700"}`}>{fmtMoney(e.amount)}</TableCell>
                    <TableCell className="text-right">{!e.reversedAt && !e.fromPay && <Button variant="ghost" size="sm" onClick={() => setReversing(e)}>Reverse</Button>}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
            <DataPagination {...entriesPg.paginationProps} variant="records" />
          </CardContent>
        </Card>
      )}
      {editing && <StaffDialog staff={editing.staff} onClose={() => setEditing(null)} onSaved={() => { setEditing(null); load() }} />}
      {money && <AdvanceDialog staff={money.staff} kind={money.kind} onClose={() => setMoney(null)} onDone={() => { setMoney(null); load() }} />}
      <PromptDialog open={!!reversing} onOpenChange={(o) => !o && setReversing(null)} title="Reverse this?" label="Why" confirmLabel="Reverse" confirmVariant="destructive"
        onSubmit={async (r) => { await reverseStaffLoan(reversing!.kind, reversing!.id, r); setReversing(null); load() }} />
    </LivestockPage>
  )
}

function StaffDialog({ staff, onClose, onSaved }: { staff?: Staff; onClose: () => void; onSaved: () => void }) {
  const { toast } = useToast()
  const [f, setF] = useState<StaffInput>(staff ? { name: staff.name, role: staff.role, phone: staff.phone, payType: staff.payType, payRate: staff.payRate,
    startDate: staff.startDate, isActive: staff.isActive, notes: staff.notes } : { name: "", role: null, phone: null, payType: "Monthly", payRate: 0, startDate: todayIso(), notes: null })
  const [saving, setSaving] = useState(false)
  const set = <K extends keyof StaffInput>(k: K, v: StaffInput[K]) => setF((s) => ({ ...s, [k]: v }))
  const save = async () => {
    setSaving(true)
    try { await saveStaff(f, staff?.staffId); toast({ title: "Saved" }); onSaved() }
    catch (e: any) { toast({ title: "Not saved", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setSaving(false) }
  }
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader><DialogTitle>{staff ? `Edit ${staff.name}` : "Add a person"}</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <div><Label htmlFor="sf-name">Name</Label><Input id="sf-name" value={f.name} onChange={(e) => set("name", e.target.value)} /></div>
            <div><Label htmlFor="sf-role">Job</Label><Input id="sf-role" value={f.role ?? ""} placeholder="Herdsman, milker…" onChange={(e) => set("role", e.target.value || null)} /></div>
          </div>
          <div className="grid grid-cols-3 gap-3">
            <div>
              <Label>Paid</Label>
              <Select value={f.payType} onValueChange={(v) => set("payType", v as StaffInput["payType"])}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent><SelectItem value="Monthly">Monthly</SelectItem><SelectItem value="Daily">By the day</SelectItem></SelectContent>
              </Select>
            </div>
            <div><Label htmlFor="sf-rate">{f.payType === "Daily" ? "Per day" : "Per month"}</Label><Input id="sf-rate" type="number" min={0} step="0.01" value={f.payRate} onChange={(e) => set("payRate", Number(e.target.value))} /></div>
            <div><Label htmlFor="sf-start">Started</Label><Input id="sf-start" type="date" value={f.startDate ?? ""} onChange={(e) => set("startDate", e.target.value || null)} /></div>
          </div>
          <div><Label htmlFor="sf-phone">Phone</Label><Input id="sf-phone" value={f.phone ?? ""} onChange={(e) => set("phone", e.target.value || null)} /></div>
          {staff && <label className="flex items-center gap-2 text-sm"><Switch checked={f.isActive !== false} onCheckedChange={(v) => set("isActive", v)} /> Still works here</label>}
          <div><Label htmlFor="sf-notes">Notes</Label><Textarea id="sf-notes" rows={2} value={f.notes ?? ""} onChange={(e) => set("notes", e.target.value || null)} /></div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || !f.name.trim()} onClick={save}>{saving ? "Saving…" : "Save"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function AdvanceDialog({ staff, kind, onClose, onDone }: { staff: Staff; kind: "lend" | "repay"; onClose: () => void; onDone: () => void }) {
  const { toast } = useToast()
  const { accounts, defaultId } = useCashAccounts()
  const [accountId, setAccountId] = useState<number | null>(null)
  const [amount, setAmount] = useState(kind === "repay" ? String(staff.owes) : "")
  const [date, setDate] = useState(todayIso())
  const [reason, setReason] = useState("")
  const [saving, setSaving] = useState(false)
  useEffect(() => { if (!accountId && defaultId) setAccountId(defaultId) }, [defaultId, accountId])
  const n = Number(amount) || 0
  const save = async () => {
    setSaving(true)
    try {
      if (kind === "lend") await lendToStaff({ staffId: staff.staffId, date, amount: n, accountId: accountId!, reason: reason.trim() || null })
      else await staffRepays({ staffId: staff.staffId, date, amount: n, accountId: accountId! })
      toast({ title: "Saved" }); onDone()
    } catch (e: any) { toast({ title: "Not saved", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setSaving(false) }
  }
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader><DialogTitle>{kind === "lend" ? `Advance to ${staff.name}` : `${staff.name} repays`}</DialogTitle></DialogHeader>
        <div className="space-y-3">
          {staff.owes > 0 && <p className="text-sm text-stone-600">Owes now: <strong>{fmtMoney(staff.owes)}</strong></p>}
          <div className="grid grid-cols-2 gap-3">
            <div><Label htmlFor="ad-amt">Amount</Label><Input id="ad-amt" type="number" min={0} step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} /></div>
            <div><Label htmlFor="ad-date">Date</Label><Input id="ad-date" type="date" max={todayIso()} value={date} onChange={(e) => setDate(e.target.value)} /></div>
          </div>
          <AccountSelect label={kind === "lend" ? "Paid from" : "Into"} value={accountId} onChange={setAccountId} accounts={accounts} spend={kind === "lend" ? n : undefined} />
          {kind === "lend" && <div><Label htmlFor="ad-why">What for</Label><Input id="ad-why" value={reason} onChange={(e) => setReason(e.target.value)} /></div>}
          {kind === "lend" && <p className="text-xs text-stone-500">It can be taken back from pay on the pay run.</p>}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || n <= 0 || !accountId || (kind === "repay" && n > staff.owes) || (kind === "lend" && isShort(accounts, accountId, n))} onClick={save}>{saving ? "Saving…" : "Save"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
