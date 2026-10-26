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
import { Dialog, DialogContent, DialogDescription, DialogHeader } from "@/components/ui/dialog"
import { FORM_DIALOG_CONTENT, FORM_DIALOG_PRIMARY, FormDialogFooter, FormDialogTitle } from "@/components/ui/form-dialog"
import { FormField, FormSection } from "@/components/ui/form-section"
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
      <DialogContent className={cn(FORM_DIALOG_CONTENT, "sm:max-w-2xl")}>
        <DialogHeader>
          <FormDialogTitle icon={Wallet} color="amber">Pay supplier advance</FormDialogTitle>
          <DialogDescription>
            Pay a supplier before anything is delivered. The money leaves the account you choose and is held as their
            credit, to use on their next purchases. It is not a purchase and not an expense.
          </DialogDescription>
        </DialogHeader>
        <div className="min-w-0 space-y-4">
          <FormSection title="Supplier & Date" color="blue" tinted stackOnMobile>
            <FormField label="Supplier *">
              <Select value={supplierId} onValueChange={setSupplierId}>
                <SelectTrigger className="w-full bg-white"><SelectValue placeholder={suppliers.length ? "Choose the supplier" : "Loading suppliers…"} /></SelectTrigger>
                <SelectContent>{suppliers.map((s) => <SelectItem key={s.id} value={String(s.id)}>{s.name}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <div className="min-w-0 space-y-1">
              <Label htmlFor="sa-date">Date *</Label>
              <Input id="sa-date" type="date" className="bg-white" value={date} onChange={(e) => setDate(e.target.value)} />
            </div>
          </FormSection>
          <FormSection title="Payment" color="green" tinted>
            <div className="min-w-0 space-y-1">
              <Label htmlFor="sa-amount">Amount *</Label>
              <Input id="sa-amount" type="number" min={0} step="0.01" className="bg-white text-right font-semibold tabular-nums"
                     value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="0.00" />
            </div>
            <FormField label="Pay from *">
              <Select value={accountId} onValueChange={setAccountId}>
                <SelectTrigger className="w-full bg-white"><SelectValue placeholder="Cash account" /></SelectTrigger>
                <SelectContent>
                  {accounts.map((a) => (
                    <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>
                      {a.accountName} · {formatCurrency(a.currentBalance, currencyCode)}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </FormField>
            <FormField label="Method *">
              <Select value={method} onValueChange={setMethod}>
                <SelectTrigger className="w-full bg-white"><SelectValue /></SelectTrigger>
                <SelectContent>{METHODS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <div className="min-w-0 space-y-1">
              <Label htmlFor="sa-ref">Reference</Label>
              <Input id="sa-ref" className="bg-white" value={reference} onChange={(e) => setReference(e.target.value)} placeholder="Optional, e.g. receipt or transfer ID" />
            </div>
          </FormSection>
          <FormSection title="Notes" color="slate" tinted columns={1}>
            <div className="min-w-0 space-y-1">
              <Label htmlFor="sa-notes" className="sr-only">Notes</Label>
              <Textarea id="sa-notes" rows={2} className="bg-white" value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Optional, e.g. maize for next month" />
            </div>
          </FormSection>
          {value > 0 && supplierName && (
            <p className="rounded-md border border-amber-200 bg-amber-50 p-2.5 text-sm text-amber-900">
              {account?.accountName ?? "The account"} goes down by <b className="tabular-nums">{formatCurrency(value, currencyCode)}</b>,
              and {supplierName} holds the same amount as credit for you.
            </p>
          )}
          <ErrorLine error={error} />
        </div>
        <FormDialogFooter onCancel={() => onOpenChange(false)} cancelDisabled={saving}>
          <Button onClick={save} disabled={!valid || saving} className={cn("px-6", FORM_DIALOG_PRIMARY.amber)}>
            {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            {value > 0 ? `Pay advance · ${formatCurrency(value, currencyCode)}` : "Pay advance"}
          </Button>
        </FormDialogFooter>
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
      <DialogContent className={cn(FORM_DIALOG_CONTENT, "sm:max-w-2xl")}>
        <DialogHeader>
          <FormDialogTitle icon={FileMinus} color="blue">Add supplier credit</FormDialogTitle>
          <DialogDescription>
            Credit a supplier owes you with no money moving now. If you paid them money in advance, use Pay advance instead.
          </DialogDescription>
        </DialogHeader>
        <div className="min-w-0 space-y-4">
          <FormSection title="Supplier & Date" color="blue" tinted stackOnMobile>
            <FormField label="Supplier *">
              <Select value={supplierId} onValueChange={setSupplierId}>
                <SelectTrigger className="w-full bg-white"><SelectValue placeholder={suppliers.length ? "Choose the supplier" : "Loading suppliers…"} /></SelectTrigger>
                <SelectContent>{suppliers.map((s) => <SelectItem key={s.id} value={String(s.id)}>{s.name}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <div className="min-w-0 space-y-1">
              <Label htmlFor="sc-date">Date *</Label>
              <Input id="sc-date" type="date" className="bg-white" value={date} onChange={(e) => setDate(e.target.value)} />
            </div>
          </FormSection>
          <FormSection title="What is it *" color="amber" tinted columns={1}>
            {KINDS.map((k) => (
              <label key={k.value} className={cn("flex cursor-pointer gap-2.5 rounded-md border p-2.5", kind === k.value ? "border-amber-400 bg-amber-50" : "border-slate-200 bg-white")}>
                <input type="radio" name="supplier-credit-kind" className="mt-1" checked={kind === k.value} onChange={() => setKind(k.value)} />
                <span className="text-sm">
                  <span className="font-medium text-slate-900">{SUPPLIER_CREDIT_KIND_LABEL[k.value]}</span>
                  <span className="block text-xs text-slate-600">{k.body}</span>
                </span>
              </label>
            ))}
          </FormSection>
          <FormSection title="Amount" color="green" tinted>
            <div className="min-w-0 space-y-1">
              <Label htmlFor="sc-amount">Amount *</Label>
              <Input id="sc-amount" type="number" min={0} step="0.01" className="bg-white text-right font-semibold tabular-nums"
                     value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="0.00" />
            </div>
            <div className="min-w-0 space-y-1">
              <Label htmlFor="sc-ref">Reference</Label>
              <Input id="sc-ref" className="bg-white" value={reference} onChange={(e) => setReference(e.target.value)} placeholder="Optional, e.g. credit note number" />
            </div>
          </FormSection>
          <FormSection title="Reason *" color="slate" tinted columns={1}>
            <ReasonSelect id="sc-reason" options={SUPPLIER_CREDIT_REASONS} value={reason} onChange={setReason} />
          </FormSection>
          {value > 0 && supplierName && (
            <p className="rounded-md border border-blue-200 bg-blue-50 p-2.5 text-sm text-blue-900">
              {supplierName} will hold <b className="tabular-nums">{formatCurrency(value, currencyCode)}</b> of credit for you. No cash moves.
            </p>
          )}
          <ErrorLine error={error} />
        </div>
        <FormDialogFooter onCancel={() => onOpenChange(false)} cancelDisabled={saving}>
          <Button onClick={save} disabled={!valid || saving} className={cn("px-6", FORM_DIALOG_PRIMARY.blue)}>
            {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            {value > 0 ? `Add credit · ${formatCurrency(value, currencyCode)}` : "Add credit"}
          </Button>
        </FormDialogFooter>
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
      <DialogContent className={cn(FORM_DIALOG_CONTENT, "sm:max-w-2xl")}>
        <DialogHeader>
          <FormDialogTitle icon={Link2} color="blue">Apply supplier credit</FormDialogTitle>
          <DialogDescription>
            Use {credit?.creditNumber} ({credit?.source.toLowerCase()}) to pay something {credit?.supplierName ?? "the supplier"} is owed.
            No money moves now -- it already left with the {credit?.source === "Credit note" ? "credit note" : "payment"}.
          </DialogDescription>
        </DialogHeader>
        {credit && (
          <div className="min-w-0 space-y-4">
            <p className="rounded-md border border-blue-200 bg-blue-50 p-2.5 text-sm text-blue-900">
              Available on this credit: <span className="font-semibold tabular-nums">{money(credit.available)}</span>
            </p>
            <FormSection title="Apply to" color="blue" tinted columns={1}>
              <FormField label="Apply to *">
                {docs === null ? (
                  <p className="flex items-center gap-2 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading what is owed…</p>
                ) : docs.length === 0 ? (
                  <p className="text-sm text-slate-500">Nothing is owed to {credit.supplierName ?? "this supplier"} right now.</p>
                ) : (
                  <Select value={docKey} onValueChange={setDocKey}>
                    <SelectTrigger className="w-full bg-white"><SelectValue placeholder="Choose a purchase, bill or debt" /></SelectTrigger>
                    <SelectContent>
                      {docs.map((d) => (
                        <SelectItem key={`${d.documentType}:${d.documentId}`} value={`${d.documentType}:${d.documentId}`}>
                          {d.reference ?? d.documentId} · {d.label ?? d.documentType} · owes {money(d.balance)}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                )}
              </FormField>
            </FormSection>
            <FormSection title="Amount" color="green" tinted columns={1}>
              <div className="min-w-0 space-y-1">
                <Label htmlFor="ap-amount">Amount *</Label>
                <Input id="ap-amount" type="number" min={0} step="0.01" className="bg-white text-right font-semibold tabular-nums"
                       value={amount} onChange={(e) => setAmount(e.target.value)} disabled={!doc} />
                {doc && <p className="text-xs text-slate-500">At most {money(max)}.</p>}
              </div>
            </FormSection>
            <ErrorLine error={error} />
          </div>
        )}
        <FormDialogFooter onCancel={() => onOpenChange(false)} cancelDisabled={saving}>
          <Button onClick={save} disabled={!valid || saving} className={cn("px-6", FORM_DIALOG_PRIMARY.blue)}>
            {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            {value > 0 ? `Apply credit · ${money(value)}` : "Apply credit"}
          </Button>
        </FormDialogFooter>
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
      <DialogContent className={cn(FORM_DIALOG_CONTENT, "sm:max-w-xl")}>
        <DialogHeader>
          <FormDialogTitle icon={ArrowDownToLine} color="emerald">Receive supplier refund</FormDialogTitle>
          <DialogDescription>
            {credit?.supplierName ?? "The supplier"} sends back money out of {credit?.creditNumber}. It comes into the account you choose
            (Money In on Cash Flow). It is not a sale.
          </DialogDescription>
        </DialogHeader>
        {credit && (
          <div className="min-w-0 space-y-4">
            <p className="rounded-md border border-emerald-200 bg-emerald-50 p-2.5 text-sm text-emerald-900">
              Available on this credit: <span className="font-semibold tabular-nums">{money(credit.available)}</span>
            </p>
            <FormSection title="Refund" color="green" tinted>
              <div className="min-w-0 space-y-1">
                <Label htmlFor="sr-amount">Amount *</Label>
                <Input id="sr-amount" type="number" min={0} step="0.01" className="bg-white text-right font-semibold tabular-nums"
                       value={amount} onChange={(e) => setAmount(e.target.value)} />
              </div>
              <div className="min-w-0 space-y-1">
                <Label htmlFor="sr-date">Date *</Label>
                <Input id="sr-date" type="date" className="bg-white" value={date} onChange={(e) => setDate(e.target.value)} />
              </div>
              <FormField label="Received into *">
                <Select value={accountId} onValueChange={setAccountId}>
                  <SelectTrigger className="w-full bg-white"><SelectValue placeholder="Cash account" /></SelectTrigger>
                  <SelectContent>
                    {accounts.map((a) => <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>{a.accountName}</SelectItem>)}
                  </SelectContent>
                </Select>
              </FormField>
              <FormField label="Method *">
                <Select value={method} onValueChange={setMethod}>
                  <SelectTrigger className="w-full bg-white"><SelectValue /></SelectTrigger>
                  <SelectContent>{METHODS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}</SelectContent>
                </Select>
              </FormField>
            </FormSection>
            <FormSection title="Reason *" color="slate" tinted columns={1}>
              <ReasonSelect id="sr-reason" options={SUPPLIER_REFUND_REASONS} value={reason} onChange={setReason} />
            </FormSection>
            <ErrorLine error={error} />
          </div>
        )}
        <FormDialogFooter onCancel={() => onOpenChange(false)} cancelDisabled={saving}>
          <Button onClick={save} disabled={!valid || saving} className={cn("px-6", FORM_DIALOG_PRIMARY.emerald)}>
            {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            {value > 0 ? `Record refund · ${money(value)}` : "Record refund"}
          </Button>
        </FormDialogFooter>
      </DialogContent>
    </Dialog>
  )
}
