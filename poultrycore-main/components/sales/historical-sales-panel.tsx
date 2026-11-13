"use client"

// =============================================================================
// "Before tracking" on the Sales page (migration 436).
//
// Sales made before the farm used VisibilityCore, entered in Initial Farm Setup
// or Batch Bird Reconciliation. They are NOT sale records: nothing here moves
// cash or touches the Sales tab's totals. P&L and Cash Flow count the amount
// received (435), so a correction here shows there at once.
//
//   Sale          editable (date, price, customer, received) and reversible
//   FlockOpening  a flock's opening "Sold" with no value -- birds only
//   Movement      an older bird movement with no sale record -- birds only
//
// The number of birds is never edited here: Reverse, then enter it again in
// Batch Bird Reconciliation, so the batch's bird totals stay right.
// =============================================================================

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { History, Pencil, Undo2, Loader2, Info } from "lucide-react"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Checkbox } from "@/components/ui/checkbox"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { useToast } from "@/hooks/use-toast"
import { formatCurrency } from "@/lib/utils/currency"
import {
  listHistoricalSales, updateHistoricalSale, reverseHistoricalSale, listReconciliationCustomers,
  type HistoricalSaleRow,
} from "@/lib/api/bird-reconciliation"

const RECON_HREF = "/poultry/reports/batch-bird-reconciliation"
const NO_CUSTOMER = "__none__"

function where(r: HistoricalSaleRow): string {
  const b = r.batchName ?? "No batch"
  return r.flockName ? `${b} · ${r.flockName}` : `${b} · not in a flock`
}

function sourceLabel(r: HistoricalSaleRow): string {
  if (r.kind === "FlockOpening") return "Flock opening history"
  if (r.kind === "Movement") return "Bird movement"
  const s = r.source === "Batch" ? "Batch Bird Reconciliation" : (r.source ?? "Reconciliation")
  return r.reconciliationNo ? `${s} · ${r.reconciliationNo}` : s
}

function moneyStatus(r: HistoricalSaleRow, cur: string) {
  if (r.status === "Reversed") return <Badge variant="outline" className="border-slate-300 text-slate-500">Reversed</Badge>
  if (r.valueUnknown) return <Badge variant="outline" className="border-amber-300 bg-amber-50 text-amber-800">Value not entered</Badge>
  if (r.amountOwed > 0) {
    return r.debtNumber
      ? <Badge variant="outline" className="border-orange-300 bg-orange-50 text-orange-800">Owes {formatCurrency(r.amountOwed, cur)} · {r.debtNumber}</Badge>
      : <Badge variant="outline" className="border-orange-300 bg-orange-50 text-orange-800">Owes {formatCurrency(r.amountOwed, cur)} · not tracked</Badge>
  }
  return <Badge variant="outline" className="border-emerald-300 bg-emerald-50 text-emerald-800">Paid</Badge>
}

interface EditForm {
  saleDate: string
  valueUnknown: boolean
  pricePerBird: string
  amountReceived: string
  customerId: string
  reference: string
  notes: string
}

export function HistoricalSalesPanel({ currencyCode, onCountChange }: {
  currencyCode: string
  onCountChange?: (n: number) => void
}) {
  const { toast } = useToast()
  const [rows, setRows] = useState<HistoricalSaleRow[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [showReversed, setShowReversed] = useState(false)
  const [customers, setCustomers] = useState<{ customerId: number; name: string }[]>([])

  const [editing, setEditing] = useState<HistoricalSaleRow | null>(null)
  const [form, setForm] = useState<EditForm | null>(null)
  const [saving, setSaving] = useState(false)
  const [reversing, setReversing] = useState<HistoricalSaleRow | null>(null)
  const [reason, setReason] = useState("")

  const load = useCallback(async () => {
    setLoading(true); setError(null)
    try {
      const r = await listHistoricalSales()
      setRows(r ?? [])
      onCountChange?.((r ?? []).filter((x) => x.status === "Posted").length)
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not load historical sales.")
    } finally {
      setLoading(false)
    }
  }, [onCountChange])

  useEffect(() => { void load() }, [load])

  const visible = useMemo(() => rows.filter((r) => showReversed || r.status === "Posted"), [rows, showReversed])
  const totals = useMemo(() => {
    const posted = rows.filter((r) => r.status === "Posted")
    return {
      n: posted.length,
      birds: posted.reduce((s, r) => s + (r.birds || 0), 0),
      value: posted.reduce((s, r) => s + (r.valueUnknown ? 0 : Number(r.totalValue) || 0), 0),
      received: posted.reduce((s, r) => s + (Number(r.amountReceived) || 0), 0),
      owed: posted.reduce((s, r) => s + (Number(r.amountOwed) || 0), 0),
      noValue: posted.filter((r) => r.valueUnknown).reduce((s, r) => s + (r.birds || 0), 0),
      reversed: rows.length - posted.length,
    }
  }, [rows])

  const openEdit = async (r: HistoricalSaleRow) => {
    setEditing(r)
    setForm({
      saleDate: (r.saleDate || "").split("T")[0],
      valueUnknown: r.valueUnknown,
      pricePerBird: r.pricePerBird != null ? String(r.pricePerBird) : "",
      amountReceived: r.valueUnknown ? "" : String(r.amountReceived ?? ""),
      customerId: r.customerId ? String(r.customerId) : NO_CUSTOMER,
      reference: r.reference ?? "",
      notes: r.notes ?? "",
    })
    if (customers.length === 0) {
      try { setCustomers(await listReconciliationCustomers()) } catch { /* the pick just stays empty */ }
    }
  }

  // Owed and the customer are fixed once the debt has payments, or when the
  // debt was recorded separately and only linked to this sale.
  const debtLocked = editing != null && editing.debtId != null
    && ((editing.debtPaid ?? 0) > 0 || editing.debtCreated === false)
  const value = form && !form.valueUnknown && editing
    ? Math.round(editing.birds * (Number(form.pricePerBird) || 0) * 100) / 100 : 0
  const received = form && !form.valueUnknown
    ? (form.amountReceived === "" ? value : Number(form.amountReceived) || 0) : 0
  const owed = Math.max(0, Math.round((value - received) * 100) / 100)

  const save = async () => {
    if (!editing?.historicalSaleId || !form) return
    if (!form.saleDate) { toast({ title: "Enter the date of the sale", variant: "destructive" }); return }
    if (!form.valueUnknown && form.pricePerBird === "") {
      toast({ title: "Enter the price per bird, or tick Value not known", variant: "destructive" }); return
    }
    if (received > value) { toast({ title: "Amount received cannot be more than the sale value", variant: "destructive" }); return }
    setSaving(true)
    try {
      const res = await updateHistoricalSale(editing.historicalSaleId, {
        saleDate: form.saleDate,
        valueUnknown: form.valueUnknown,
        pricePerBird: form.valueUnknown ? null : Number(form.pricePerBird) || 0,
        amountReceived: form.valueUnknown ? null : (form.amountReceived === "" ? null : Number(form.amountReceived) || 0),
        customerId: form.customerId === NO_CUSTOMER ? null : Number(form.customerId),
        reference: form.reference || null,
        notes: form.notes || null,
      })
      toast({
        title: "Historical sale updated",
        description: res.amountOwed > 0
          ? (res.debtNumber ? `${formatCurrency(res.amountOwed, currencyCode)} still owed, on debt ${res.debtNumber}.` : `${formatCurrency(res.amountOwed, currencyCode)} still owed, not tracked as a debt (no customer).`)
          : "Profit & Loss and Cash Flow now show the new amount received.",
      })
      setEditing(null); setForm(null)
      await load()
    } catch (e) {
      toast({ title: "Could not save", description: e instanceof Error ? e.message : String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  const reverse = async () => {
    if (!reversing?.historicalSaleId) return
    if (!reason.trim()) { toast({ title: "Say why this sale is being reversed", variant: "destructive" }); return }
    setSaving(true)
    try {
      const res = await reverseHistoricalSale(reversing.historicalSaleId, reason.trim())
      toast({
        title: "Historical sale reversed",
        description: res.birdsReturned > 0
          ? `${res.birdsReturned.toLocaleString()} birds are back in ${reversing.batchName ?? "the batch"} as "not yet in a flock". Enter the right figures in Batch Bird Reconciliation.`
          : "It no longer counts in Profit & Loss or Cash Flow.",
      })
      setReversing(null); setReason("")
      await load()
    } catch (e) {
      toast({ title: "Could not reverse", description: e instanceof Error ? e.message : String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  const actions = (r: HistoricalSaleRow) => {
    if (r.kind === "Sale" && r.canEdit) {
      return (
        <div className="flex justify-end gap-1">
          <Button variant="ghost" size="sm" className="h-8 gap-1" onClick={() => void openEdit(r)}><Pencil className="h-3.5 w-3.5" />Edit</Button>
          <Button variant="ghost" size="sm" className="h-8 gap-1 text-red-600 hover:text-red-700" onClick={() => { setReversing(r); setReason("") }}><Undo2 className="h-3.5 w-3.5" />Reverse</Button>
        </div>
      )
    }
    if (r.kind === "FlockOpening") {
      return <Link href={RECON_HREF} className="text-xs text-blue-700 hover:underline">Add value in Bird Reconciliation</Link>
    }
    return null
  }

  return (
    <div className="space-y-4">
      <div className="flex gap-2 rounded-md border border-sky-200 bg-sky-50 p-3 text-sm text-sky-900">
        <Info className="mt-0.5 h-4 w-4 shrink-0" />
        <p>
          Sales made <strong>before you started tracking</strong> in VisibilityCore, entered in Initial Farm Setup or Batch Bird
          Reconciliation. They are not counted in the Sales tab&apos;s totals and moved no cash today. Profit &amp; Loss and Cash Flow
          include the amount received, as &quot;Bird Sales (before tracking)&quot;.
        </p>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {[
          { label: "Birds sold", value: totals.birds.toLocaleString(), note: `${totals.n} entr${totals.n === 1 ? "y" : "ies"}` },
          { label: "Sale value", value: formatCurrency(totals.value, currencyCode), note: totals.noValue > 0 ? `${totals.noValue.toLocaleString()} birds with no value` : "All valued" },
          { label: "Received", value: formatCurrency(totals.received, currencyCode), note: "In Profit & Loss and Cash Flow" },
          { label: "Still owed", value: formatCurrency(totals.owed, currencyCode), note: "Opening customer debts" },
        ].map((c) => (
          <Card key={c.label} className="bg-white">
            <CardContent className="p-4">
              <p className="text-xs font-medium text-slate-500">{c.label}</p>
              <p className="mt-1 text-lg font-bold tabular-nums text-slate-900">{c.value}</p>
              <p className="mt-0.5 truncate text-[11px] text-slate-500">{c.note}</p>
            </CardContent>
          </Card>
        ))}
      </div>

      <Card className="bg-white overflow-hidden">
        <CardHeader className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <CardTitle className="flex items-center gap-2"><History className="h-5 w-5 text-slate-500" />Sales before tracking</CardTitle>
            <CardDescription>To change the number of birds, reverse the entry and enter it again in{" "}
              <Link href={RECON_HREF} className="text-blue-700 hover:underline">Batch Bird Reconciliation</Link>.</CardDescription>
          </div>
          {totals.reversed > 0 && (
            <label className="flex items-center gap-2 text-sm text-slate-600">
              <Checkbox checked={showReversed} onCheckedChange={(v) => setShowReversed(v === true)} />
              Show reversed ({totals.reversed})
            </label>
          )}
        </CardHeader>
        <CardContent className="p-0 sm:p-6 sm:pt-0">
          {loading ? (
            <p className="py-10 text-center text-slate-600"><Loader2 className="mr-2 inline h-4 w-4 animate-spin" />Loading…</p>
          ) : error ? (
            <p className="py-10 text-center text-red-600">{error}</p>
          ) : visible.length === 0 ? (
            <p className="px-4 py-10 text-center text-slate-600">No sales before tracking were entered for this company.</p>
          ) : (
            <>
              {/* Phone: one card per sale. */}
              <div className="divide-y sm:hidden">
                {visible.map((r) => (
                  <div key={r.key} className={r.status === "Reversed" ? "p-4 text-slate-400" : "p-4"}>
                    <div className="flex items-start justify-between gap-2">
                      <div className="min-w-0">
                        <p className="font-semibold text-slate-900">{r.birds.toLocaleString()} birds</p>
                        <p className="truncate text-xs text-slate-500">{where(r)}</p>
                      </div>
                      <p className="shrink-0 text-xs text-slate-500">{(r.saleDate || "").split("T")[0]}</p>
                    </div>
                    <div className="mt-2 flex flex-wrap items-center gap-2 text-sm">
                      {!r.valueUnknown && <span className="tabular-nums">{formatCurrency(Number(r.totalValue) || 0, currencyCode)}</span>}
                      {moneyStatus(r, currencyCode)}
                    </div>
                    {r.customerName && <p className="mt-1 text-xs text-slate-600">Customer: {r.customerName}</p>}
                    <p className="mt-1 text-[11px] text-slate-500">{sourceLabel(r)}</p>
                    {r.reversalReason && <p className="mt-1 text-[11px] text-slate-500">Reversed: {r.reversalReason}</p>}
                    <div className="mt-2">{actions(r)}</div>
                  </div>
                ))}
              </div>
              {/* Tablet and up: a table. */}
              <div className="hidden overflow-x-auto sm:block">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Date</TableHead>
                      <TableHead>Batch / Flock</TableHead>
                      <TableHead className="text-right">Birds</TableHead>
                      <TableHead className="text-right">Price</TableHead>
                      <TableHead className="text-right">Value</TableHead>
                      <TableHead className="text-right">Received</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead>Customer</TableHead>
                      <TableHead>Entered in</TableHead>
                      <TableHead className="text-right"> </TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {visible.map((r) => (
                      <TableRow key={r.key} className={r.status === "Reversed" ? "text-slate-400" : ""}>
                        <TableCell className="whitespace-nowrap">{(r.saleDate || "").split("T")[0]}</TableCell>
                        <TableCell className="max-w-[220px] truncate" title={where(r)}>{where(r)}</TableCell>
                        <TableCell className="text-right tabular-nums">{r.birds.toLocaleString()}</TableCell>
                        <TableCell className="text-right tabular-nums">{r.valueUnknown || r.pricePerBird == null ? "—" : formatCurrency(Number(r.pricePerBird), currencyCode)}</TableCell>
                        <TableCell className="text-right tabular-nums">{r.valueUnknown ? "—" : formatCurrency(Number(r.totalValue) || 0, currencyCode)}</TableCell>
                        <TableCell className="text-right tabular-nums">{r.valueUnknown ? "—" : formatCurrency(Number(r.amountReceived) || 0, currencyCode)}</TableCell>
                        <TableCell>{moneyStatus(r, currencyCode)}</TableCell>
                        <TableCell>{r.customerName ?? "—"}</TableCell>
                        <TableCell className="text-xs text-slate-500" title={r.reversalReason ? `Reversed: ${r.reversalReason}` : undefined}>{sourceLabel(r)}</TableCell>
                        <TableCell className="text-right">{actions(r)}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            </>
          )}
        </CardContent>
      </Card>

      {/* Edit */}
      <Dialog open={editing != null} onOpenChange={(o) => { if (!o && !saving) { setEditing(null); setForm(null) } }}>
        <DialogContent className="w-[95vw] sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>Edit historical sale</DialogTitle>
            <DialogDescription>
              {editing ? `${editing.birds.toLocaleString()} birds · ${where(editing)}` : ""}. The number of birds is not changed here.
            </DialogDescription>
          </DialogHeader>
          {editing && form && (
            <div className="space-y-3">
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <div className="space-y-1.5">
                  <Label htmlFor="hs-date">Date of sale</Label>
                  <Input id="hs-date" type="date" value={form.saleDate} onChange={(e) => setForm({ ...form, saleDate: e.target.value })} />
                </div>
                <div className="space-y-1.5">
                  <Label>Birds</Label>
                  <Input value={editing.birds.toLocaleString()} disabled />
                </div>
              </div>
              <label className="flex items-center gap-2 text-sm">
                <Checkbox checked={form.valueUnknown} disabled={debtLocked}
                  onCheckedChange={(v) => setForm({ ...form, valueUnknown: v === true })} />
                Value not known (birds only)
              </label>
              {!form.valueUnknown && (
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                  <div className="space-y-1.5">
                    <Label htmlFor="hs-price">Price per bird</Label>
                    <NumberInput id="hs-price" min="0" step="0.01" value={form.pricePerBird} disabled={debtLocked}
                      onChange={(e) => setForm({ ...form, pricePerBird: e.target.value })} />
                  </div>
                  <div className="space-y-1.5">
                    <Label htmlFor="hs-recv">Amount received</Label>
                    <NumberInput id="hs-recv" min="0" step="0.01" value={form.amountReceived} placeholder={String(value)} disabled={debtLocked}
                      onChange={(e) => setForm({ ...form, amountReceived: e.target.value })} />
                  </div>
                </div>
              )}
              {!form.valueUnknown && (
                <p className="text-sm text-slate-700">
                  Sale value <strong className="tabular-nums">{formatCurrency(value, currencyCode)}</strong>
                  {" · "}still owed <strong className="tabular-nums">{formatCurrency(owed, currencyCode)}</strong>
                </p>
              )}
              <div className="space-y-1.5">
                <Label>Customer</Label>
                <Select value={form.customerId} disabled={debtLocked} onValueChange={(v) => setForm({ ...form, customerId: v })}>
                  <SelectTrigger><SelectValue placeholder="No customer" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value={NO_CUSTOMER}>No customer</SelectItem>
                    {editing.customerId && !customers.some((c) => c.customerId === editing.customerId) && (
                      <SelectItem value={String(editing.customerId)}>{editing.customerName ?? `Customer #${editing.customerId}`}</SelectItem>
                    )}
                    {customers.map((c) => <SelectItem key={c.customerId} value={String(c.customerId)}>{c.name}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
              {debtLocked ? (
                <p className="rounded-md bg-amber-50 p-2 text-xs text-amber-800">
                  {(editing.debtPaid ?? 0) > 0
                    ? `${formatCurrency(editing.debtPaid ?? 0, currencyCode)} has been paid on debt ${editing.debtNumber}, so the price, amount received and customer are fixed. Reverse those payments first (Payments Received) to change them.`
                    : `The amount owed is on debt ${editing.debtNumber}, recorded separately. Change it on Customer Debts.`}
                </p>
              ) : !form.valueUnknown && owed > 0 && (
                <p className="rounded-md bg-amber-50 p-2 text-xs text-amber-800">
                  {form.customerId === NO_CUSTOMER
                    ? "No customer chosen, so the amount still owed is not tracked as a debt."
                    : `${formatCurrency(owed, currencyCode)} is recorded as an opening debt for this customer${editing.debtNumber && owed !== editing.amountOwed ? ` (replaces ${editing.debtNumber})` : ""}. When they pay it, record it on Payments Received.`}
                </p>
              )}
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <div className="space-y-1.5">
                  <Label htmlFor="hs-ref">Reference</Label>
                  <Input id="hs-ref" value={form.reference} onChange={(e) => setForm({ ...form, reference: e.target.value })} />
                </div>
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="hs-notes">Notes</Label>
                <Textarea id="hs-notes" rows={2} value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} />
              </div>
            </div>
          )}
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => { setEditing(null); setForm(null) }} disabled={saving}>Cancel</Button>
            <Button onClick={() => void save()} disabled={saving} className="bg-blue-600 hover:bg-blue-700">{saving ? "Saving…" : "Save changes"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Reverse */}
      <Dialog open={reversing != null} onOpenChange={(o) => { if (!o && !saving) setReversing(null) }}>
        <DialogContent className="w-[95vw] sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Reverse historical sale</DialogTitle>
            <DialogDescription>
              {reversing ? `${reversing.birds.toLocaleString()} birds · ${where(reversing)} · ${(reversing.saleDate || "").split("T")[0]}` : ""}
            </DialogDescription>
          </DialogHeader>
          {reversing && (
            <div className="space-y-3 text-sm">
              <ul className="list-disc space-y-1 pl-5 text-slate-700">
                {reversing.scope === "BatchUnallocated" && (
                  <li>The {reversing.birds.toLocaleString()} birds go back to {reversing.batchName ?? "the batch"} as &quot;not yet in a flock&quot;.</li>
                )}
                {reversing.debtNumber && reversing.debtCreated && <li>Debt {reversing.debtNumber} is reversed (refused if anything has been paid on it).</li>}
                <li>It stops counting in Profit &amp; Loss and Cash Flow. It stays here, marked reversed.</li>
                <li>Enter the right figures again in <Link href={RECON_HREF} className="text-blue-700 hover:underline">Batch Bird Reconciliation</Link>.</li>
              </ul>
              <div className="space-y-1.5">
                <Label htmlFor="hs-reason">Why is it being reversed?</Label>
                <Textarea id="hs-reason" rows={2} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. Wrong number of birds entered" />
              </div>
            </div>
          )}
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setReversing(null)} disabled={saving}>Cancel</Button>
            <Button onClick={() => void reverse()} disabled={saving || !reason.trim()} className="bg-red-600 hover:bg-red-700">{saving ? "Reversing…" : "Reverse"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
