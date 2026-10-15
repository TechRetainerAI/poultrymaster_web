"use client"

// Supplier credit dialogs (370, poultry):
//   PaySupplierAdvanceDialog   money out now, before any purchase -> supplier credit
//   SupplierCreditDialog       credit with no cash (credit note / opening / manual) -- owner / admin
//   ApplySupplierCreditDialog  use one credit on an open purchase, bill or debt -- no cash
//   SupplierRefundDialog       the supplier sends money back out of one credit -- Money In

import { SUPPLIER_CREDIT_REASONS, SUPPLIER_REFUND_REASONS } from "@/lib/reversal-reasons"
import { ReasonSelect } from "@/components/ui/reason-select"
import { useEffect, useMemo, useState } from "react"
import { ArrowDownToLine, FileMinus, Link2, Loader2, Wallet } from "lucide-react"
import { Button } from "@/components/ui/button"
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { cn } from "@/lib/utils"
import { formatCurrency } from "@/lib/utils/currency"
import { getUserContext } from "@/lib/api/config"
import { getSuppliers } from "@/lib/api/supplier"
import { listOpenDocuments, recordPayment, type OpenDocumentRow } from "@/lib/api/balances"
import { listPoultryCashAccounts, type PoultryCashAccount } from "@/lib/api/poultry-finance"
import { entryTimestamp } from "@/lib/utils/date-key"
import {
  applySupplierCredit, createSupplierCredit, recordSupplierRefund, SUPPLIER_CREDIT_KIND_LABEL,
  type SupplierCreditEvent, type SupplierCreditKind,
} from "@/lib/api/supplier-credit"

const METHODS = ["Cash", "Mobile Money", "Bank Transfer", "Check"]

function today(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
}

function useSuppliers(open: boolean) {
  const [list, setList] = useState<{ id: number; name: string }[]>([])
  useEffect(() => {
    if (!open) return
    const { userId, farmId } = getUserContext()
    getSuppliers(userId, farmId)
      .then((r) => setList((r?.data ?? [])
        .map((s) => ({ id: Number(s.supplierId), name: String(s.name ?? "") }))
        .filter((s) => s.id > 0 && s.name)
        .sort((a, b) => a.name.localeCompare(b.name))))
      .catch(() => setList([]))
  }, [open])
  return list
}

function useAccounts(open: boolean) {
  const [list, setList] = useState<PoultryCashAccount[]>([])
  useEffect(() => {
    if (!open) return
    listPoultryCashAccounts()
      .then((a) => setList(a.filter((x) => x.isActive !== false)))
      .catch(() => setList([]))
  }, [open])
  return list
}

function ErrorLine({ error }: { error: string | null }) {
  return error ? <p className="rounded-md bg-red-50 p-2.5 text-sm text-red-700">{error}</p> : null
}

// ------------------------------------------------------------------ advance
export function PaySupplierAdvanceDialog({ open, currencyCode, onOpenChange, onPaid }: {
  open: boolean; currencyCode: string; onOpenChange: (o: boolean) => void
  onPaid: (s: { supplierName: string; amount: number }) => void
}) {
  const suppliers = useSuppliers(open)
  const accounts = useAccounts(open)
  const [supplierId, setSupplierId] = useState("")
  const [amount, setAmount] = useState("")
  const [date, setDate] = useState(today())
  const [accountId, setAccountId] = useState("")
  const [method, setMethod] = useState("Cash")
  const [reference, setReference] = useState("")
  const [notes, setNotes] = useState("")
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!open) return
    setSupplierId(""); setAmount(""); setDate(today()); setMethod("Cash"); setReference(""); setNotes(""); setError(null)
  }, [open])
  useEffect(() => { if (!accountId && accounts[0]) setAccountId(String(accounts[0].poultryCashAccountId)) }, [accounts, accountId])

  const value = Math.round((Number(amount) || 0) * 100) / 100
  const valid = !!supplierId && value > 0 && !!accountId && !!date
  const supplierName = suppliers.find((s) => String(s.id) === supplierId)?.name ?? ""
  const account = accounts.find((a) => String(a.poultryCashAccountId) === accountId)

  const save = async () => {
    if (!valid || saving) return
    setSaving(true); setError(null)
    try {
      await recordPayment("poultry", "supplier", {
        partyId: Number(supplierId), amount: value, paymentDate: entryTimestamp(date), paymentMethod: method,
        cashAccountId: Number(accountId), reference: reference.trim() || null, notes: notes.trim() || null,
        sourceType: "SupplierCredits",
        // Applied to nothing: the whole amount is the supplier's credit.
        allocations: [],
      })
      onPaid({ supplierName, amount: value })
    } catch (e: any) { setError(e?.message ?? String(e)) } finally { setSaving(false) }
  }

  return (
    <Dialog open={open} onOpenChange={(o) => { if (!saving) onOpenChange(o) }}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2"><Wallet className="h-5 w-5 text-amber-600" /> Pay supplier advance</DialogTitle>
          <DialogDescription>
            Pay a supplier before anything is delivered. The money leaves the account you choose and is held as their
            credit, to use on their next purchases. It is not a purchase and not an expense.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-1.5">
            <Label>Supplier *</Label>
            <Select value={supplierId} onValueChange={setSupplierId}>
              <SelectTrigger><SelectValue placeholder={suppliers.length ? "Choose the supplier" : "Loading suppliers…"} /></SelectTrigger>
              <SelectContent>{suppliers.map((s) => <SelectItem key={s.id} value={String(s.id)}>{s.name}</SelectItem>)}</SelectContent>
            </Select>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="sa-amount">Amount *</Label>
              <Input id="sa-amount" type="number" min={0} step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="0.00" />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="sa-date">Date *</Label>
              <Input id="sa-date" type="date" value={date} onChange={(e) => setDate(e.target.value)} />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>Pay from *</Label>
              <Select value={accountId} onValueChange={setAccountId}>
                <SelectTrigger><SelectValue placeholder="Cash account" /></SelectTrigger>
                <SelectContent>
                  {accounts.map((a) => (
                    <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>
                      {a.accountName} · {formatCurrency(a.currentBalance, currencyCode)}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>Method *</Label>
              <Select value={method} onValueChange={setMethod}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{METHODS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}</SelectContent>
              </Select>
            </div>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="sa-ref">Reference</Label>
            <Input id="sa-ref" value={reference} onChange={(e) => setReference(e.target.value)} placeholder="Optional, e.g. receipt or transfer ID" />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="sa-notes">Notes</Label>
            <Textarea id="sa-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Optional, e.g. maize for next month" />
          </div>
          {value > 0 && supplierName && (
            <p className="rounded-md bg-slate-50 p-2.5 text-sm text-slate-700">
              {account?.accountName ?? "The account"} goes down by <b className="tabular-nums">{formatCurrency(value, currencyCode)}</b>,
              and {supplierName} holds the same amount as credit for you.
            </p>
          )}
          <ErrorLine error={error} />
        </div>
        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancel</Button>
          <Button onClick={save} disabled={!valid || saving} className="bg-amber-600 hover:bg-amber-700">
            {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />} Pay advance
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

// ------------------------------------------------------------ manual credit
const KINDS: { value: SupplierCreditKind; body: string }[] = [
  { value: "SupplierCreditNote", body: "The supplier issued a credit note, e.g. for a short or damaged delivery." },
  { value: "SupplierOpeningCredit", body: "Credit the supplier already held for you before you started using the system." },
  { value: "SupplierManualCredit", body: "Any other credit the supplier owes you, recorded by hand." },
]

export function SupplierCreditDialog({ open, currencyCode, onOpenChange, onCreated }: {
  open: boolean; currencyCode: string; onOpenChange: (o: boolean) => void
  onCreated: (s: { supplierName: string; amount: number; kind: SupplierCreditKind }) => void
}) {
  const suppliers = useSuppliers(open)
  const [supplierId, setSupplierId] = useState("")
  const [kind, setKind] = useState<SupplierCreditKind>("SupplierCreditNote")
  const [amount, setAmount] = useState("")
  const [date, setDate] = useState(today())
  const [reference, setReference] = useState("")
  const [reason, setReason] = useState("")
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!open) return
    setSupplierId(""); setKind("SupplierCreditNote"); setAmount(""); setDate(today()); setReference(""); setReason(""); setError(null)
  }, [open])

  const value = Math.round((Number(amount) || 0) * 100) / 100
  const valid = !!supplierId && value > 0 && reason.trim().length > 0 && !!date
  const supplierName = suppliers.find((s) => String(s.id) === supplierId)?.name ?? ""

  const save = async () => {
    if (!valid || saving) return
    setSaving(true); setError(null)
    try {
      await createSupplierCredit({ supplierId: Number(supplierId), kind, amount: value, creditDate: date,
        reference: reference.trim() || null, reason: reason.trim() })
      onCreated({ supplierName, amount: value, kind })
    } catch (e: any) { setError(e?.message ?? String(e)) } finally { setSaving(false) }
  }

  return (
    <Dialog open={open} onOpenChange={(o) => { if (!saving) onOpenChange(o) }}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2"><FileMinus className="h-5 w-5 text-blue-600" /> Add supplier credit</DialogTitle>
          <DialogDescription>
            Credit a supplier owes you with no money moving now. If you paid them money in advance, use Pay advance instead.
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-1.5">
            <Label>Supplier *</Label>
            <Select value={supplierId} onValueChange={setSupplierId}>
              <SelectTrigger><SelectValue placeholder={suppliers.length ? "Choose the supplier" : "Loading suppliers…"} /></SelectTrigger>
              <SelectContent>{suppliers.map((s) => <SelectItem key={s.id} value={String(s.id)}>{s.name}</SelectItem>)}</SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label>What is it *</Label>
            {KINDS.map((k) => (
              <label key={k.value} className={cn("flex cursor-pointer gap-2.5 rounded-md border p-2.5", kind === k.value ? "border-blue-400 bg-blue-50/60" : "border-slate-200")}>
                <input type="radio" name="supplier-credit-kind" className="mt-1" checked={kind === k.value} onChange={() => setKind(k.value)} />
                <span className="text-sm">
                  <span className="font-medium text-slate-900">{SUPPLIER_CREDIT_KIND_LABEL[k.value]}</span>
                  <span className="block text-xs text-slate-600">{k.body}</span>
                </span>
              </label>
            ))}
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="sc-amount">Amount *</Label>
              <Input id="sc-amount" type="number" min={0} step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="0.00" />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="sc-date">Date *</Label>
              <Input id="sc-date" type="date" value={date} onChange={(e) => setDate(e.target.value)} />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="sc-ref">Reference</Label>
            <Input id="sc-ref" value={reference} onChange={(e) => setReference(e.target.value)} placeholder="Optional, e.g. credit note number" />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="sc-reason">Reason *</Label>
            <ReasonSelect id="sc-reason" options={SUPPLIER_CREDIT_REASONS} value={reason} onChange={setReason} />
          </div>
          {value > 0 && supplierName && (
            <p className="rounded-md bg-slate-50 p-2.5 text-sm text-slate-700">
              {supplierName} will hold <b className="tabular-nums">{formatCurrency(value, currencyCode)}</b> of credit for you. No cash moves.
            </p>
          )}
          <ErrorLine error={error} />
        </div>
        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancel</Button>
          <Button onClick={save} disabled={!valid || saving} className="bg-blue-600 hover:bg-blue-700">
            {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />} Add credit
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

// ---------------------------------------------------------------- apply
export function ApplySupplierCreditDialog({ credit, currencyCode, onOpenChange, onApplied }: {
  credit: SupplierCreditEvent | null; currencyCode: string; onOpenChange: (o: boolean) => void
  onApplied: (s: { reference: string; amount: number }) => void
}) {
  const [docs, setDocs] = useState<OpenDocumentRow[] | null>(null)
  const [docKey, setDocKey] = useState("")
  const [amount, setAmount] = useState("")
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const money = (n: number) => formatCurrency(Number(n) || 0, currencyCode)

  useEffect(() => {
    setDocs(null); setDocKey(""); setAmount(""); setError(null)
    if (!credit) return
    listOpenDocuments("poultry", "supplier", credit.supplierId)
      .then((d) => setDocs(d))
      .catch(() => setDocs([]))
  }, [credit])

  const doc = useMemo(() => docs?.find((d) => `${d.documentType}:${d.documentId}` === docKey) ?? null, [docs, docKey])
  useEffect(() => {
    if (doc && credit) setAmount(Math.min(doc.balance, credit.available).toFixed(2))
  }, [doc, credit])

  const value = Math.round((Number(amount) || 0) * 100) / 100
  const max = doc && credit ? Math.min(doc.balance, credit.available) : 0
  const valid = !!doc && value > 0 && value <= max + 0.005

  const save = async () => {
    if (!credit || !doc || !valid || saving) return
    setSaving(true); setError(null)
    try {
      await applySupplierCredit({ poultrySupplierPaymentId: credit.poultrySupplierPaymentId,
        documentType: doc.documentType, documentId: doc.documentId, amount: value })
      onApplied({ reference: doc.reference ?? `${doc.documentType} #${doc.documentId}`, amount: value })
    } catch (e: any) { setError(e?.message ?? String(e)) } finally { setSaving(false) }
  }

  return (
    <Dialog open={!!credit} onOpenChange={(o) => { if (!saving) onOpenChange(o) }}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2"><Link2 className="h-5 w-5 text-blue-600" /> Apply supplier credit</DialogTitle>
          <DialogDescription>
            Use {credit?.creditNumber} ({credit?.source.toLowerCase()}) to pay something {credit?.supplierName ?? "the supplier"} is owed.
            No money moves now -- it already left with the {credit?.source === "Credit note" ? "credit note" : "payment"}.
          </DialogDescription>
        </DialogHeader>
        {credit && (
          <div className="space-y-3">
            <p className="text-sm text-slate-600">Available on this credit: <span className="font-semibold tabular-nums">{money(credit.available)}</span></p>
            <div className="space-y-1.5">
              <Label>Apply to *</Label>
              {docs === null ? (
                <p className="flex items-center gap-2 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading what is owed…</p>
              ) : docs.length === 0 ? (
                <p className="text-sm text-slate-500">Nothing is owed to {credit.supplierName ?? "this supplier"} right now.</p>
              ) : (
                <Select value={docKey} onValueChange={setDocKey}>
                  <SelectTrigger><SelectValue placeholder="Choose a purchase, bill or debt" /></SelectTrigger>
                  <SelectContent>
                    {docs.map((d) => (
                      <SelectItem key={`${d.documentType}:${d.documentId}`} value={`${d.documentType}:${d.documentId}`}>
                        {d.reference ?? d.documentId} · {d.label ?? d.documentType} · owes {money(d.balance)}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              )}
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="ap-amount">Amount *</Label>
              <Input id="ap-amount" type="number" min={0} step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} disabled={!doc} />
              {doc && <p className="text-xs text-slate-500">At most {money(max)}.</p>}
            </div>
            <ErrorLine error={error} />
          </div>
        )}
        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancel</Button>
          <Button onClick={save} disabled={!valid || saving} className="bg-blue-600 hover:bg-blue-700">
            {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />} Apply credit
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

// --------------------------------------------------------------- refund
export function SupplierRefundDialog({ credit, currencyCode, onOpenChange, onRefunded }: {
  credit: SupplierCreditEvent | null; currencyCode: string; onOpenChange: (o: boolean) => void
  onRefunded: (s: { amount: number }) => void
}) {
  const accounts = useAccounts(!!credit)
  const [accountId, setAccountId] = useState("")
  const [method, setMethod] = useState("Cash")
  const [amount, setAmount] = useState("")
  const [date, setDate] = useState(today())
  const [reason, setReason] = useState("")
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const money = (n: number) => formatCurrency(Number(n) || 0, currencyCode)

  useEffect(() => {
    setError(null); setReason(""); setMethod("Cash"); setDate(today())
    if (credit) setAmount(credit.available.toFixed(2))
  }, [credit])
  useEffect(() => { if (!accountId && accounts[0]) setAccountId(String(accounts[0].poultryCashAccountId)) }, [accounts, accountId])

  const value = Math.round((Number(amount) || 0) * 100) / 100
  const valid = !!credit && value > 0 && value <= credit.available + 0.005 && !!accountId && reason.trim().length > 0

  const save = async () => {
    if (!credit || !valid || saving) return
    setSaving(true); setError(null)
    try {
      await recordSupplierRefund({ poultrySupplierPaymentId: credit.poultrySupplierPaymentId, amount: value,
        poultryCashAccountId: Number(accountId), paymentMethod: method, refundDate: date, reason: reason.trim() })
      onRefunded({ amount: value })
    } catch (e: any) { setError(e?.message ?? String(e)) } finally { setSaving(false) }
  }

  return (
    <Dialog open={!!credit} onOpenChange={(o) => { if (!saving) onOpenChange(o) }}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2"><ArrowDownToLine className="h-5 w-5 text-emerald-600" /> Receive supplier refund</DialogTitle>
          <DialogDescription>
            {credit?.supplierName ?? "The supplier"} sends back money out of {credit?.creditNumber}. It comes into the account you choose
            (Money In on Cash Flow). It is not a sale.
          </DialogDescription>
        </DialogHeader>
        {credit && (
          <div className="space-y-3">
            <p className="text-sm text-slate-600">Available on this credit: <span className="font-semibold tabular-nums">{money(credit.available)}</span></p>
            <div className="grid grid-cols-2 gap-2">
              <div className="space-y-1">
                <Label htmlFor="sr-amount">Amount *</Label>
                <Input id="sr-amount" type="number" min={0} step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} />
              </div>
              <div className="space-y-1">
                <Label htmlFor="sr-date">Date *</Label>
                <Input id="sr-date" type="date" value={date} onChange={(e) => setDate(e.target.value)} />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-2">
              <div className="space-y-1">
                <Label>Received into *</Label>
                <Select value={accountId} onValueChange={setAccountId}>
                  <SelectTrigger><SelectValue placeholder="Cash account" /></SelectTrigger>
                  <SelectContent>
                    {accounts.map((a) => <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>{a.accountName}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1">
                <Label>Method *</Label>
                <Select value={method} onValueChange={setMethod}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{METHODS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}</SelectContent>
                </Select>
              </div>
            </div>
            <div className="space-y-1">
              <Label htmlFor="sr-reason">Reason *</Label>
              <ReasonSelect id="sr-reason" options={SUPPLIER_REFUND_REASONS} value={reason} onChange={setReason} />
            </div>
            <ErrorLine error={error} />
          </div>
        )}
        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={saving}>Cancel</Button>
          <Button onClick={save} disabled={!valid || saving} className="bg-emerald-600 hover:bg-emerald-700">
            {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />} Record refund
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
