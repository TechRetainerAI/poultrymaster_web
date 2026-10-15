"use client"

// Manual deferred cost entries (371) on the Deferred Inventory Cost page.
//
// Cost for stock no purchase covers -- e.g. opening stock -- recorded as an
// event with a reason, recognised as the stock is used. The aggregate is never
// edited. Owner / admin records and reverses; reversing takes back only what is
// not yet on Profit & Loss.

import { DEFERRED_COST_REASONS, REVERSAL_REASONS } from "@/lib/reversal-reasons"
import { ReasonSelect } from "@/components/ui/reason-select"
import { useCallback, useEffect, useMemo, useState } from "react"
import { ChevronDown, ChevronRight, Layers, Loader2, Plus, Undo2 } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { useFmt } from "@/lib/currency"
import { fmtDateTime } from "@/lib/utils/company-datetime"
import {
  createManualDeferredCost, listManualDeferredCosts, listUncoveredStock, reverseManualDeferredCost,
  MANUAL_DEFERRED_ENTRY_LABEL, type ManualDeferredCostRow, type ManualDeferredEntryType, type UncoveredStockRow,
} from "@/lib/api/manual-deferred-cost"

const TYPES = Object.keys(MANUAL_DEFERRED_ENTRY_LABEL) as ManualDeferredEntryType[]

function today(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
}

const qty = (n: number) => Number(n || 0).toLocaleString(undefined, { maximumFractionDigits: 3 })

export function ManualDeferredCostPanel({ onChanged }: { onChanged?: () => void }) {
  const { toast } = useToast()
  const { isAdmin } = usePermissions()
  const fmt = useFmt()
  const [rows, setRows] = useState<ManualDeferredCostRow[]>([])
  const [loaded, setLoaded] = useState(false)
  const [open, setOpen] = useState(false)
  const [addOpen, setAddOpen] = useState(false)
  const [reverseFor, setReverseFor] = useState<ManualDeferredCostRow | null>(null)
  const [reason, setReason] = useState("")
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(() => {
    listManualDeferredCosts().then(setRows).catch(() => setRows([])).finally(() => setLoaded(true))
  }, [])
  useEffect(() => { load() }, [load])

  const waiting = useMemo(() => rows.filter((r) => r.status === "Posted").reduce((t, r) => t + (Number(r.remaining) || 0), 0), [rows])

  const doReverse = async () => {
    if (!reverseFor || !reason.trim()) return
    setBusy(true); setError(null)
    try {
      const res = await reverseManualDeferredCost(reverseFor.entryId, reason.trim())
      toast({ title: "Entry reversed", description: `${reverseFor.entryNumber}: ${fmt(res.reversedAmount)} not yet recognised was taken back. What was already on Profit & Loss stays.` })
      setReverseFor(null); load(); onChanged?.()
    } catch (e: any) { setError(e?.message ?? String(e)) } finally { setBusy(false) }
  }

  if (!loaded || (rows.length === 0 && !isAdmin)) return null

  return (
    <Card className="border-violet-200">
      <CardContent className="space-y-3 p-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <button type="button" className="flex items-center gap-2 text-left" onClick={() => setOpen((o) => !o)} disabled={rows.length === 0}>
            {rows.length > 0 && (open ? <ChevronDown className="h-4 w-4 text-slate-500" /> : <ChevronRight className="h-4 w-4 text-slate-500" />)}
            <h2 className="flex items-center gap-2 text-sm font-semibold text-slate-900">
              <Layers className="h-4 w-4 text-violet-600" /> Manual entries
              <span className="font-normal text-slate-500">— cost for stock no purchase covers (e.g. opening stock)</span>
            </h2>
          </button>
          <span className="flex flex-wrap items-center gap-3">
            {rows.length > 0 && <span className="text-sm font-semibold tabular-nums text-violet-700">{fmt(waiting)} waiting</span>}
            {isAdmin && (
              <Button size="sm" onClick={() => setAddOpen(true)} className="h-9 bg-violet-600 hover:bg-violet-700">
                <Plus className="mr-1 h-4 w-4" /> Manual deferred cost entry
              </Button>
            )}
          </span>
        </div>

        {open && rows.length > 0 && (
          <div className="overflow-x-auto rounded-md border">
            <table className="w-full min-w-[60rem] text-sm">
              <thead className="bg-slate-50 text-left text-xs uppercase tracking-wider text-slate-500">
                <tr className="whitespace-nowrap">
                  <th className="px-3 py-2 font-medium">Entry</th>
                  <th className="px-3 py-2 font-medium">From</th>
                  <th className="px-3 py-2 font-medium">Item</th>
                  <th className="px-3 py-2 font-medium">Type</th>
                  <th className="px-3 py-2 text-right font-medium">Quantity</th>
                  <th className="px-3 py-2 text-right font-medium">Cost</th>
                  <th className="px-3 py-2 text-right font-medium">On P&amp;L</th>
                  <th className="px-3 py-2 text-right font-medium">Waiting</th>
                  <th className="px-3 py-2 font-medium">Reason</th>
                  <th className="px-3 py-2 text-right font-medium">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {rows.map((r) => {
                  const reversed = r.status === "Reversed"
                  return (
                    <tr key={r.entryId} className={reversed ? "text-slate-400" : undefined}>
                      <td className="whitespace-nowrap px-3 py-2 font-medium">{r.entryNumber}</td>
                      <td className="whitespace-nowrap px-3 py-2">{fmtDateTime(r.effectiveDate)}</td>
                      <td className="px-3 py-2">{r.itemName ?? `Item ${r.poultryRawMaterialItemId}`}</td>
                      <td className="whitespace-nowrap px-3 py-2">{MANUAL_DEFERRED_ENTRY_LABEL[r.entryType] ?? r.entryType}</td>
                      <td className="whitespace-nowrap px-3 py-2 text-right tabular-nums">{qty(r.quantity)} {r.unitOfMeasure ?? ""}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{fmt(r.amount)}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{fmt(r.recognised)}</td>
                      <td className="px-3 py-2 text-right font-semibold tabular-nums text-violet-700">{fmt(r.remaining)}</td>
                      <td className="max-w-[16rem] px-3 py-2">
                        <span className="block truncate" title={[r.reason, r.reference, r.notes].filter(Boolean).join(" · ")}>{r.reason}</span>
                        {reversed && <span className="block truncate text-xs">Reversed {r.reversedAmount != null ? fmt(r.reversedAmount) : ""}: {r.reversalReason}</span>}
                      </td>
                      <td className="px-3 py-2 text-right">
                        {reversed ? <Badge variant="secondary">Reversed</Badge> : isAdmin && (
                          <Button size="sm" variant="outline" className="h-8" onClick={() => { setReverseFor(r); setReason(""); setError(null) }}>
                            <Undo2 className="mr-1.5 h-4 w-4" /> Reverse
                          </Button>
                        )}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </CardContent>

      <ManualDeferredCostDialog open={addOpen} onOpenChange={setAddOpen}
        onCreated={(n) => { toast({ title: "Entry recorded", description: `${n}: recognised on Profit & Loss as the stock is used.` }); setAddOpen(false); setOpen(true); load(); onChanged?.() }} />

      <Dialog open={!!reverseFor} onOpenChange={(o) => { if (!o && !busy) setReverseFor(null) }}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2"><Undo2 className="h-5 w-5 text-red-600" /> Reverse {reverseFor?.entryNumber}?</DialogTitle>
            <DialogDescription>It stays in the history, marked Reversed.</DialogDescription>
          </DialogHeader>
          {reverseFor && (
            <div className="space-y-3 text-sm">
              <p className="rounded-md border border-amber-200 bg-amber-50 p-2.5 text-amber-900">
                <b>{fmt(reverseFor.remaining)}</b> not yet recognised is taken back. <b>{fmt(reverseFor.recognised)}</b> already on Profit &amp; Loss
                through usage stays there. The stock itself does not change.
              </p>
              <div className="space-y-1">
                <Label htmlFor="mdc-reverse-reason">Reason *</Label>
                <ReasonSelect id="mdc-reverse-reason" options={REVERSAL_REASONS} value={reason} onChange={setReason} />
              </div>
              {error && <p className="rounded-md bg-red-50 p-2.5 text-red-700">{error}</p>}
            </div>
          )}
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setReverseFor(null)} disabled={busy}>Cancel</Button>
            <Button className="bg-red-600 hover:bg-red-700" onClick={doReverse} disabled={busy || !reason.trim()}>
              {busy && <Loader2 className="mr-2 h-4 w-4 animate-spin" />} Reverse
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  )
}

function ManualDeferredCostDialog({ open, onOpenChange, onCreated }: {
  open: boolean; onOpenChange: (o: boolean) => void; onCreated: (entryNumber: string) => void
}) {
  const fmt = useFmt()
  const [items, setItems] = useState<UncoveredStockRow[] | null>(null)
  const [itemId, setItemId] = useState("")
  const [amount, setAmount] = useState("")
  const [quantity, setQuantity] = useState("")
  const [date, setDate] = useState(today())
  const [entryType, setEntryType] = useState<ManualDeferredEntryType>("OpeningDeferredCost")
  const [reason, setReason] = useState("")
  const [reference, setReference] = useState("")
  const [notes, setNotes] = useState("")
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!open) return
    setItems(null); setItemId(""); setAmount(""); setQuantity(""); setDate(today()); setEntryType("OpeningDeferredCost")
    setReason(""); setReference(""); setNotes(""); setError(null)
    listUncoveredStock().then(setItems).catch(() => setItems([]))
  }, [open])

  const item = items?.find((i) => String(i.poultryRawMaterialItemId) === itemId) ?? null
  useEffect(() => { if (item) setQuantity(String(item.uncoveredQuantity)) }, [item])

  const amt = Math.round((Number(amount) || 0) * 100) / 100
  const q = Number(quantity) || 0
  const valid = !!item && amt > 0 && q > 0 && q <= item.uncoveredQuantity + 0.0005 && !!date && reason.trim().length > 0

  const save = async () => {
    if (!item || !valid || saving) return
    setSaving(true); setError(null)
    try {
      const res = await createManualDeferredCost({ poultryRawMaterialItemId: item.poultryRawMaterialItemId, amount: amt, quantity: q,
        effectiveDate: date, entryType, reason: reason.trim(), reference: reference.trim() || null, notes: notes.trim() || null })
      onCreated(res?.entryNumber ?? "")
    } catch (e: any) { setError(e?.message ?? String(e)) } finally { setSaving(false) }
  }

  return (
    <Dialog open={open} onOpenChange={(o) => { if (!saving) onOpenChange(o) }}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2"><Layers className="h-5 w-5 text-violet-600" /> Manual deferred cost entry</DialogTitle>
          <DialogDescription>
            Cost for stock you already hold that no purchase here covers, e.g. opening stock. It goes on Profit &amp; Loss as the stock
            is used, like any stock expensed when used. No purchase, no supplier, no cash, and the stock quantity does not change.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-1.5">
            <Label>Item *</Label>
            {items === null ? (
              <p className="flex items-center gap-2 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading items…</p>
            ) : items.length === 0 ? (
              <p className="rounded-md bg-slate-50 p-2.5 text-sm text-slate-600">
                Every item&apos;s stock is already covered by its purchases, so there is nothing to add a manual cost for.
              </p>
            ) : (
              <Select value={itemId} onValueChange={setItemId}>
                <SelectTrigger><SelectValue placeholder="Choose the item" /></SelectTrigger>
                <SelectContent>
                  {items.map((i) => (
                    <SelectItem key={i.poultryRawMaterialItemId} value={String(i.poultryRawMaterialItemId)}>
                      {i.itemName} · {qty(i.uncoveredQuantity)} {i.unitOfMeasure ?? ""} not covered
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            )}
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="mdc-qty">Quantity * {item?.unitOfMeasure ? `(${item.unitOfMeasure})` : ""}</Label>
              <Input id="mdc-qty" type="number" min={0} step="0.001" value={quantity} onChange={(e) => setQuantity(e.target.value)} disabled={!item} />
              {item && <p className="text-xs text-slate-500">At most {qty(item.uncoveredQuantity)} {item.unitOfMeasure ?? ""}.</p>}
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="mdc-amount">Cost *</Label>
              <Input id="mdc-amount" type="number" min={0} step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="0.00" />
              {amt > 0 && q > 0 && <p className="text-xs text-slate-500">{fmt(amt / q)} per {item?.unitOfMeasure ?? "unit"}</p>}
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="mdc-date">Effective date *</Label>
              <Input id="mdc-date" type="date" value={date} onChange={(e) => setDate(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label>Type *</Label>
              <Select value={entryType} onValueChange={(v) => setEntryType(v as ManualDeferredEntryType)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{TYPES.map((t) => <SelectItem key={t} value={t}>{MANUAL_DEFERRED_ENTRY_LABEL[t]}</SelectItem>)}</SelectContent>
              </Select>
            </div>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="mdc-reason">Reason *</Label>
            <ReasonSelect id="mdc-reason" options={DEFERRED_COST_REASONS} value={reason} onChange={setReason} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="mdc-ref">Reference</Label>
            <Input id="mdc-ref" value={reference} onChange={(e) => setReference(e.target.value)} placeholder="Optional, e.g. stock sheet" />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="mdc-notes">Notes</Label>
            <Textarea id="mdc-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Optional" />
          </div>
          {error && <p className="rounded-md bg-red-50 p-2.5 text-sm text-red-700">{error}</p>}
        </div>
        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancel</Button>
          <Button onClick={save} disabled={!valid || saving} className="bg-violet-600 hover:bg-violet-700">
            {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />} Record entry
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
