"use client"

// Count the Money -- the poultry Cash Reconciliation for livestock. Count the
// cash box (or read the bank statement) on a date; the books are set to match
// and any difference is kept, with what is known about it.

import { useCallback, useEffect, useState } from "react"
import { Calculator } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { useToast } from "@/hooks/use-toast"
import { getCashAccount, listReconciliations, reconcile, type Reconciliation } from "@/lib/api/livestock"
import { AccountSelect, useCashAccounts } from "@/components/livestock/money-bits"
import { AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, fmtDate, fmtMoney, todayIso } from "@/components/livestock/livestock-page"

export default function LivestockCashReconciliationPage() {
  const { toast } = useToast()
  const { accounts, defaultId, reload } = useCashAccounts()
  const [rows, setRows] = useState<Reconciliation[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [accountId, setAccountId] = useState<number | null>(null)
  const [date, setDate] = useState(todayIso())
  const [booked, setBooked] = useState<number | null>(null)
  const [counted, setCounted] = useState("")
  const [notes, setNotes] = useState("")
  const [saving, setSaving] = useState(false)
  const pg = usePagination(rows ?? [], 10)

  useEffect(() => { if (!accountId && defaultId) setAccountId(defaultId) }, [defaultId, accountId])
  const load = useCallback(async () => {
    setError(null)
    try { setRows(await listReconciliations()) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [])
  useEffect(() => { load() }, [load])
  // What the books say on the count date.
  useEffect(() => {
    if (!accountId) { setBooked(null); return }
    getCashAccount(accountId, undefined, date).then((a) => {
      const sum = a.transactions.filter((t) => !t.reversedAt).reduce((s, t) => s + t.amount, 0)
      setBooked(a.openingBalance + sum)
    }).catch(() => setBooked(null))
  }, [accountId, date, rows])

  const diff = counted === "" || booked == null ? null : Math.round((Number(counted) - booked) * 100) / 100
  const save = async () => {
    setSaving(true)
    try {
      const r = await reconcile({ accountId: accountId!, date, counted: Number(counted), notes: notes.trim() || null })
      toast({ title: r.difference === 0 ? "Matches the books" : `Books corrected by ${fmtMoney(r.difference)}` })
      setCounted(""); setNotes(""); load(); reload()
    } catch (e: any) { toast({ title: "Not saved", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setSaving(false) }
  }

  return (
    <LivestockPage title="Count the money" description="Check each account against what is really there." icon={Calculator}>
      <Card>
        <CardHeader className="pb-2"><CardTitle className="text-base">New count</CardTitle></CardHeader>
        <CardContent className="space-y-3">
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <AccountSelect value={accountId} onChange={setAccountId} accounts={accounts} />
            <div><Label htmlFor="rc-date">Date</Label><Input id="rc-date" type="date" max={todayIso()} value={date} onChange={(e) => setDate(e.target.value)} /></div>
            <div><Label htmlFor="rc-count">Counted</Label><Input id="rc-count" type="number" step="0.01" value={counted} onChange={(e) => setCounted(e.target.value)} /></div>
          </div>
          {booked != null && (
            <p className="text-sm text-stone-700">
              The books say <strong>{fmtMoney(booked)}</strong> on {fmtDate(date)}.
              {diff != null && (diff === 0 ? " It matches." : <span className={diff < 0 ? "text-rose-700" : "text-emerald-700"}> {diff < 0 ? "Short" : "Over"} by <strong>{fmtMoney(Math.abs(diff))}</strong>.</span>)}
            </p>
          )}
          {diff != null && diff !== 0 && (
            <div><Label htmlFor="rc-notes">What do you know about the difference? (required)</Label><Textarea id="rc-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} /></div>
          )}
          <Button className={AMBER_BUTTON} disabled={saving || !accountId || counted === "" || (diff !== 0 && !notes.trim())} onClick={save}>{saving ? "Saving…" : "Save count"}</Button>
        </CardContent>
      </Card>
      {error ? <LoadError message={error} onRetry={load} /> : !rows ? <Loading /> : rows.length === 0 ? <EmptyState title="No counts yet" /> : (
        <div className="rounded-md border bg-white overflow-x-auto">
          <Table>
            <TableHeader><TableRow><TableHead>Date</TableHead><TableHead>Account</TableHead><TableHead className="text-right">Books said</TableHead><TableHead className="text-right">Counted</TableHead><TableHead className="text-right">Difference</TableHead><TableHead>Notes</TableHead></TableRow></TableHeader>
            <TableBody>
              {pg.pageItems.map((r) => (
                <TableRow key={r.reconId}>
                  <TableCell>{fmtDate(r.date)}</TableCell><TableCell>{r.accountName}</TableCell>
                  <TableCell className="text-right">{fmtMoney(r.booked)}</TableCell><TableCell className="text-right">{fmtMoney(r.counted)}</TableCell>
                  <TableCell className={`text-right font-medium ${r.difference < 0 ? "text-rose-700" : r.difference > 0 ? "text-emerald-700" : ""}`}>{r.difference === 0 ? "Matched" : fmtMoney(r.difference)}</TableCell>
                  <TableCell className="text-sm text-stone-600">{r.notes ?? ""}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
          <DataPagination {...pg.paginationProps} variant="records" />
        </div>
      )}
    </LivestockPage>
  )
}
