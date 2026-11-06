"use client"

import { useEffect, useMemo, useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Boxes, Plus, Trash2, Wand2, AlertCircle } from "lucide-react"
import { BreedSelect } from "@/components/poultry/breed-select"
import { createFlockBatchesBulk, type FlockBatch } from "@/lib/api/flock-batch"
import type { Supplier } from "@/lib/api/supplier"
import type { PoultryCashAccount } from "@/lib/api/poultry-finance"
import {
  MAX_ROWS, applyToAll, emptyRow, errorsByRow, generateRows, nextStartNumber, rowTotal, summarize, toPayloadItems, validateRows,
  type BulkBatchField, type BulkBatchRow,
} from "@/lib/flock-batches/bulk"
import { batchStatusFromToggles } from "@/lib/utils/batch-status"
import { getUserContext } from "@/lib/utils/user-context"
import { useToast } from "@/hooks/use-toast"

// "Add Multiple Batches" -- the bulk counterpart of Add Flock Batch, which is
// untouched and still the way to add one. Same shape as Add Multiple
// Houses/Pens: generate rows, edit any of them, create all at once. The server
// re-runs every rule and creates all or none (MainFlockBatch/bulk), through the
// same insert as the single form, so payments and cash accounts behave the same.

interface Props {
  open: boolean
  onOpenChange: (open: boolean) => void
  /** Batch codes already on this farm, for the duplicate check. */
  existingCodes: string[]
  suppliers: Supplier[]
  cashAccounts: PoultryCashAccount[]
  knownBreeds?: string[]
  currencySymbol?: string
  onCreated?: (batches: FlockBatch[]) => void | Promise<void>
}

const today = () => new Date().toISOString().split("T")[0]

export function BulkFlockBatchDialog({ open, onOpenChange, existingCodes, suppliers, cashAccounts, knownBreeds = [], currencySymbol = "", onCreated }: Props) {
  const { toast } = useToast()

  // Generator
  const [count, setCount] = useState("5")
  const [namePrefix, setNamePrefix] = useState("Batch")
  const [codePrefix, setCodePrefix] = useState("B")
  const [startNumber, setStartNumber] = useState("1")
  const [breed, setBreed] = useState("")
  const [startDate, setStartDate] = useState(today())
  const [birds, setBirds] = useState("")
  const [costPerChick, setCostPerChick] = useState("")
  const [amountPaid, setAmountPaid] = useState("")

  // Shared by every batch in this run
  const [supplierType, setSupplierType] = useState("local")
  const [supplierId, setSupplierId] = useState("")
  const [cashAccountId, setCashAccountId] = useState("")
  const [hasArrived, setHasArrived] = useState(true)
  const [active, setActive] = useState(true)
  const [notes, setNotes] = useState("")

  const [rows, setRows] = useState<BulkBatchRow[]>([])
  const [submitted, setSubmitted] = useState(false)
  const [saving, setSaving] = useState(false)
  const [serverErrors, setServerErrors] = useState<Record<number, Partial<Record<string, string>>>>({})

  useEffect(() => {
    if (!open) return
    setCount("5"); setNamePrefix("Batch"); setCodePrefix("B")
    setStartNumber(String(nextStartNumber("B", existingCodes)))
    setBreed(""); setStartDate(today()); setBirds(""); setCostPerChick(""); setAmountPaid("")
    setSupplierType("local"); setSupplierId(""); setCashAccountId(""); setHasArrived(true); setActive(true); setNotes("")
    setRows([]); setSubmitted(false); setServerErrors({})
    // existingCodes only matters on open
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open])

  const errors = useMemo(() => validateRows(rows, existingCodes), [rows, existingCodes])
  const rowErrors = useMemo(() => errorsByRow(errors), [errors])
  const batchError = errors.find((e) => e.index < 0)
  const summary = useMemo(() => summarize(rows), [rows])
  const money = (n: number) => `${currencySymbol}${n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

  // Quiet until submit, except duplicate codes -- the point of the preview.
  const errorFor = (i: number, f: BulkBatchField) => {
    const m = rowErrors[i]?.[f]
    if (!m) return serverErrors[i]?.[f]
    if (submitted) return m
    return m.includes("already exists") || m.includes("more than once") ? m : undefined
  }

  const generate = () => {
    const n = parseInt(count, 10)
    if (!Number.isFinite(n) || n < 1) {
      toast({ title: "Nothing to generate", description: "Enter how many batches you need.", variant: "warning" })
      return
    }
    if (n > MAX_ROWS) {
      toast({ title: "Too many at once", description: `You can create at most ${MAX_ROWS} batches at a time.`, variant: "warning" })
      return
    }
    setRows(generateRows({
      count: n, namePrefix, codePrefix, startNumber: parseInt(startNumber, 10) || 1,
      breed, startDate, numberOfBirds: birds, costPerChick, amountPaid,
    }))
    setSubmitted(false); setServerErrors({})
  }

  const patch = (i: number, p: Partial<BulkBatchRow>) => { setRows((prev) => prev.map((r, j) => (j === i ? { ...r, ...p } : r))); setServerErrors({}) }
  const remove = (i: number) => { setRows((prev) => prev.filter((_, j) => j !== i)); setServerErrors({}) }
  const add = () => {
    setRows((prev) => [...prev, emptyRow({ breed, startDate, numberOfBirds: birds, costPerChick, amountPaid })])
    setServerErrors({})
  }

  const submit = async () => {
    setSubmitted(true); setServerErrors({})
    if (errors.length > 0) {
      toast({ title: "Check the rows below", description: batchError?.message ?? `${errors.length} row${errors.length === 1 ? "" : "s"} need attention before these batches can be created.`, variant: "warning" })
      return
    }
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      toast({ title: "Session issue", description: "We could not confirm your farm or user. Please sign in again.", variant: "destructive" })
      return
    }
    setSaving(true)
    try {
      const res = await createFlockBatchesBulk({
        userId, farmId, source: "Flock Purchases page",
        batches: toPayloadItems(rows, {
          supplierType, supplierId, poultryCashAccountId: cashAccountId,
          status: batchStatusFromToggles(hasArrived, active), notes,
        }),
      })
      if (!res.success) {
        const fromServer: Record<number, Partial<Record<string, string>>> = {}
        for (const e of res.data?.errors ?? []) {
          if (e.index < 0) continue
          fromServer[e.index] = { ...(fromServer[e.index] ?? {}), [e.field]: e.message }
        }
        setServerErrors(fromServer)
        toast({ title: "No batches were created", description: res.data?.message || res.message || "Nothing was saved.", variant: "destructive" })
        return
      }
      toast({ title: "Batches created", description: res.data?.message || `${summary.count} batches created.` })
      onOpenChange(false)
      await onCreated?.(res.data?.batches ?? [])
    } finally {
      setSaving(false)
    }
  }

  const cell = (i: number, f: BulkBatchField) => errorFor(i, f) && (
    <p className="text-[11px] leading-tight text-red-600 flex items-start gap-1 mt-1"><AlertCircle className="w-3 h-3 shrink-0 mt-px" />{errorFor(i, f)}</p>
  )

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="w-[95vw] sm:max-w-6xl max-h-[90vh] flex flex-col">
        <DialogHeader>
          <DialogTitle>Add Multiple Batches</DialogTitle>
          <DialogDescription>
            Generate a list of batches, edit any row, then create them all at once. Nothing is saved until you click create — and
            if one batch cannot be created, none of them are.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-5 py-4 overflow-y-auto pr-1">
          {/* ---- Generator ---- */}
          <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
            <div className="bg-blue-600 px-4 py-2 text-sm font-semibold text-white">Generate Batches</div>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 items-end gap-4 p-4">
              <div className="space-y-2"><Label htmlFor="bb-count">No. of batches *</Label>
                <NumberInput id="bb-count" min="1" max={String(MAX_ROWS)} value={count} onChange={(e) => setCount(e.target.value)} /></div>
              <div className="space-y-2"><Label htmlFor="bb-name">Name prefix</Label>
                <Input id="bb-name" value={namePrefix} onChange={(e) => setNamePrefix(e.target.value)} placeholder="Batch" /></div>
              <div className="space-y-2"><Label htmlFor="bb-code">Code prefix</Label>
                <Input id="bb-code" value={codePrefix} onChange={(e) => { setCodePrefix(e.target.value); setStartNumber(String(nextStartNumber(e.target.value, existingCodes))) }} placeholder="B" /></div>
              <div className="space-y-2"><Label htmlFor="bb-start">Starting number</Label>
                <NumberInput id="bb-start" min="1" value={startNumber} onChange={(e) => setStartNumber(e.target.value)} />
                <p className="text-[11px] text-slate-500">First code: {codePrefix.trim()}{String(parseInt(startNumber, 10) || 1).padStart(3, "0")}</p></div>
              <div className="space-y-2"><Label>Breed</Label>
                <BreedSelect value={breed} known={knownBreeds} onChange={setBreed} /></div>
              <div className="space-y-2"><Label htmlFor="bb-date">Start date</Label>
                <Input id="bb-date" type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} /></div>
              <div className="space-y-2"><Label htmlFor="bb-birds">Birds per batch</Label>
                <NumberInput id="bb-birds" min="1" value={birds} onChange={(e) => setBirds(e.target.value)} placeholder="1000" /></div>
              <div className="space-y-2"><Label htmlFor="bb-cost">Cost per chick</Label>
                <NumberInput id="bb-cost" min="0" step="0.01" value={costPerChick} onChange={(e) => setCostPerChick(e.target.value)} placeholder="0.00" /></div>
              <div className="space-y-2"><Label htmlFor="bb-paid">Amount paid per batch ({currencySymbol || "amount"})</Label>
                <NumberInput id="bb-paid" min="0" step="0.01" value={amountPaid} onChange={(e) => setAmountPaid(e.target.value)} placeholder="0.00" /></div>
            </div>
            <div className="flex flex-wrap items-center gap-2 px-4 pb-4">
              <Button type="button" onClick={generate} className="bg-blue-600 hover:bg-blue-700 flex items-center gap-2"><Wand2 className="w-4 h-4" />Generate</Button>
              {rows.length > 0 && (<>
                <Button type="button" variant="outline" size="sm" onClick={() => setRows(applyToAll(rows, { breed }))}>Apply breed to all</Button>
                <Button type="button" variant="outline" size="sm" onClick={() => setRows(applyToAll(rows, { startDate }))}>Apply date to all</Button>
                <Button type="button" variant="outline" size="sm" onClick={() => setRows(applyToAll(rows, { numberOfBirds: birds }))}>Apply birds to all</Button>
                <Button type="button" variant="outline" size="sm" onClick={() => setRows(applyToAll(rows, { costPerChick }))}>Apply cost to all</Button>
                <Button type="button" variant="outline" size="sm" onClick={() => setRows(applyToAll(rows, { amountPaid }))}>Apply paid to all</Button>
                <Button type="button" variant="outline" size="sm" onClick={() => setRows(rows.map((r) => ({ ...r, amountPaid: String(rowTotal(r)) })))}>Mark all fully paid</Button>
              </>)}
              <span className="basis-full text-xs text-slate-500 lg:basis-auto lg:ml-auto">Generating replaces the rows below. Everything stays editable.</span>
            </div>
          </div>

          {/* ---- Shared ---- */}
          <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
            <div className="bg-emerald-600 px-4 py-2 text-sm font-semibold text-white">Supplier, payment &amp; status — same for every batch</div>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 p-4">
              <div className="space-y-2"><Label>Type</Label>
                <Select value={supplierType} onValueChange={setSupplierType}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent><SelectItem value="local">Local</SelectItem><SelectItem value="foreign">Foreign</SelectItem></SelectContent>
                </Select></div>
              <div className="space-y-2"><Label>Supplier</Label>
                <Select value={supplierId || "none"} onValueChange={(v) => setSupplierId(v === "none" ? "" : v)}>
                  <SelectTrigger><SelectValue placeholder="Select supplier" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="none">No supplier</SelectItem>
                    {suppliers.map((s) => <SelectItem key={s.supplierId} value={String(s.supplierId)}>{s.name}</SelectItem>)}
                  </SelectContent>
                </Select></div>
              <div className="space-y-2"><Label>Pay from cash account</Label>
                <Select value={cashAccountId || "none"} onValueChange={(v) => setCashAccountId(v === "none" ? "" : v)}>
                  <SelectTrigger><SelectValue placeholder="None (no cash movement)" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="none">None (no cash movement)</SelectItem>
                    {cashAccounts.map((a) => <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>{a.accountName} ({money(a.currentBalance)})</SelectItem>)}
                  </SelectContent>
                </Select>
                <p className="text-xs text-slate-500">Each batch&apos;s amount paid comes out of this account.</p></div>
              <div className="flex items-center gap-2"><Switch checked={hasArrived} onCheckedChange={setHasArrived} /><Label>Batches have arrived</Label></div>
              <div className="flex items-center gap-2"><Switch checked={active} onCheckedChange={setActive} disabled={!hasArrived} /><Label>Active batches</Label></div>
              <div className="space-y-2 sm:col-span-2 lg:col-span-1"><Label htmlFor="bb-notes">Notes (optional)</Label>
                <Input id="bb-notes" value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="e.g. November chick order" /></div>
            </div>
          </div>

          {/* ---- Preview & edit ---- */}
          <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
            <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Preview &amp; Edit</div>
            {rows.length === 0 ? (
              <div className="text-center py-10 px-4">
                <Boxes className="h-10 w-10 text-slate-400 mx-auto mb-3" />
                <p className="text-slate-600">No rows yet. Generate batches above, or add a single row.</p>
                <Button type="button" variant="outline" size="sm" onClick={add} className="mt-3"><Plus className="w-4 h-4 mr-1" />Add a row</Button>
              </div>
            ) : (
              <div className="p-4 space-y-3">
                <div className="overflow-x-auto">
                  <table className="w-full min-w-[960px] text-sm">
                    <thead>
                      <tr className="text-left text-xs font-medium text-slate-500">
                        <th className="px-1 pb-2">Batch name *</th><th className="px-1 pb-2">Code *</th><th className="px-1 pb-2">Breed</th>
                        <th className="px-1 pb-2">Start date *</th><th className="px-1 pb-2">Birds *</th><th className="px-1 pb-2">Cost/chick</th>
                        <th className="px-1 pb-2 text-right">Total</th><th className="px-1 pb-2">Amount paid</th><th className="px-1 pb-2" />
                      </tr>
                    </thead>
                    <tbody>
                      {rows.map((r, i) => (
                        <tr key={r.id} className="align-top">
                          <td className="p-1 w-[18%]"><Input aria-label={`Batch name, row ${i + 1}`} value={r.batchName} onChange={(e) => patch(i, { batchName: e.target.value })} />{cell(i, "batchName")}</td>
                          <td className="p-1 w-[11%]"><Input aria-label={`Batch code, row ${i + 1}`} value={r.batchCode} onChange={(e) => patch(i, { batchCode: e.target.value })} />{cell(i, "batchCode")}</td>
                          <td className="p-1 w-[13%]"><Input aria-label={`Breed, row ${i + 1}`} value={r.breed} onChange={(e) => patch(i, { breed: e.target.value })} /></td>
                          <td className="p-1 w-[13%]"><Input type="date" aria-label={`Start date, row ${i + 1}`} value={r.startDate} onChange={(e) => patch(i, { startDate: e.target.value })} />{cell(i, "startDate")}</td>
                          <td className="p-1 w-[9%]"><NumberInput min="1" aria-label={`Birds, row ${i + 1}`} value={r.numberOfBirds} onChange={(e) => patch(i, { numberOfBirds: e.target.value })} />{cell(i, "numberOfBirds")}</td>
                          <td className="p-1 w-[9%]"><NumberInput min="0" step="0.01" aria-label={`Cost per chick, row ${i + 1}`} value={r.costPerChick} onChange={(e) => patch(i, { costPerChick: e.target.value })} />{cell(i, "costPerChick")}</td>
                          <td className="p-1 w-[10%] text-right tabular-nums pt-3">{money(rowTotal(r))}</td>
                          <td className="p-1 w-[11%]"><NumberInput min="0" step="0.01" aria-label={`Amount paid, row ${i + 1}`} value={r.amountPaid} onChange={(e) => patch(i, { amountPaid: e.target.value })} />{cell(i, "amountPaid")}</td>
                          <td className="p-1 w-[4%] text-right">
                            <Button type="button" variant="ghost" size="sm" onClick={() => remove(i)} className="text-red-600 hover:text-red-700 hover:bg-red-50" title="Remove row"><Trash2 className="h-4 w-4" /></Button>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                <Button type="button" variant="outline" size="sm" onClick={add}><Plus className="w-4 h-4 mr-1" />Add another row</Button>
              </div>
            )}
          </div>

          {/* ---- Review ---- */}
          {rows.length > 0 && (
            <div className="rounded-xl border border-slate-200 bg-white px-4 py-3">
              <p className="font-medium text-slate-900">{summary.count === 1 ? "1 batch will be created." : `${summary.count} batches will be created.`}</p>
              <p className="text-sm text-slate-600">
                {summary.birds.toLocaleString()} birds · Total cost {money(summary.totalCost)} · Paid {money(summary.amountPaid)} · Balance {money(summary.balance)}
              </p>
              {submitted && errors.length > 0 && (
                <p className="text-sm text-red-600 mt-1 flex items-center gap-1"><AlertCircle className="w-4 h-4 shrink-0" />
                  {batchError?.message ?? `${errors.length} row${errors.length === 1 ? "" : "s"} need attention.`}</p>
              )}
            </div>
          )}
        </div>

        <div className="flex justify-end space-x-2 pt-2 border-t">
          <Button onClick={() => onOpenChange(false)} disabled={saving} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
          <Button onClick={submit} disabled={saving || rows.length === 0} className="bg-blue-600 hover:bg-blue-700">
            {saving ? "Creating…" : summary.count === 1 ? "Create 1 Batch" : `Create ${summary.count} Batches`}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}
