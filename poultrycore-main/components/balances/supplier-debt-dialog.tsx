"use client"

// Record supplier debt (370), owner / admin only.
//
// What the business already owes a supplier without a purchase in the system --
// e.g. maize bought before the farm started using it. Not a purchase: no stock,
// no expense, no cash. Paid like a purchase on Supplier Balances.

import { useEffect, useState } from "react"
import { FileWarning, Loader2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogDescription, DialogHeader } from "@/components/ui/dialog"
import { FORM_DIALOG_CONTENT, FORM_DIALOG_PRIMARY, FormDialogFooter, FormDialogTitle } from "@/components/ui/form-dialog"
import { FormField, FormSection } from "@/components/ui/form-section"
import { cn } from "@/lib/utils"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { formatCurrency } from "@/lib/utils/currency"
import { getSuppliers } from "@/lib/api/supplier"
import { getUserContext } from "@/lib/api/config"
import {
  createSupplierDebt, SUPPLIER_DEBT_ENTRY_LABEL, type SupplierDebtEntryType,
} from "@/lib/api/supplier-credit"

const ENTRY_TYPES = Object.keys(SUPPLIER_DEBT_ENTRY_LABEL) as SupplierDebtEntryType[]

interface Props {
  open: boolean
  currencyCode: string
  onOpenChange: (open: boolean) => void
  onCreated: (summary: { supplierName: string; amount: number; debtNumber: string }) => void
}

function today(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
}

export function SupplierDebtDialog({ open, currencyCode, onOpenChange, onCreated }: Props) {
  const [suppliers, setSuppliers] = useState<{ id: number; name: string }[]>([])
  const [supplierId, setSupplierId] = useState("")
  const [amount, setAmount] = useState("")
  const [date, setDate] = useState(today())
  const [entryType, setEntryType] = useState<SupplierDebtEntryType>("OpeningBalance")
  const [description, setDescription] = useState("")
  const [reference, setReference] = useState("")
  const [notes, setNotes] = useState("")
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!open) return
    setSupplierId(""); setAmount(""); setDate(today()); setEntryType("OpeningBalance")
    setDescription(""); setReference(""); setNotes(""); setError(null)
    const { userId, farmId } = getUserContext()
    getSuppliers(userId, farmId)
      .then((r) => setSuppliers((r?.data ?? [])
        .map((x) => ({ id: Number(x.supplierId), name: String(x.name ?? "") }))
        .filter((x) => x.id > 0 && x.name)
        .sort((a, b) => a.name.localeCompare(b.name))))
      .catch(() => setSuppliers([]))
  }, [open])

  const value = Math.round((Number(amount) || 0) * 100) / 100
  const valid = !!supplierId && value > 0 && !!date && description.trim().length > 0
  const supplierName = suppliers.find((c) => String(c.id) === supplierId)?.name ?? ""

  const save = async () => {
    if (!valid || saving) return
    setSaving(true); setError(null)
    try {
      const res = await createSupplierDebt({
        supplierId: Number(supplierId),
        amount: value,
        debtDate: date,
        entryType,
        description: description.trim(),
        reference: reference.trim() || null,
        notes: notes.trim() || null,
      })
      onCreated({ supplierName, amount: value, debtNumber: res?.debtNumber ?? "" })
    } catch (e: any) {
      setError(e?.message ?? String(e))
    } finally {
      setSaving(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={(o) => { if (!saving) onOpenChange(o) }}>
      <DialogContent className={cn(FORM_DIALOG_CONTENT, "sm:max-w-2xl")}>
        <DialogHeader>
          <FormDialogTitle icon={FileWarning} color="amber">Record supplier debt</FormDialogTitle>
          <DialogDescription>
            Money you already owe a supplier that is not on any purchase here, e.g. maize bought before you started using the
            system. It is added to what you owe them and is paid like a purchase. It is not a purchase: no stock, no expense and no cash.
          </DialogDescription>
        </DialogHeader>

        <div className="min-w-0 space-y-4">
          <FormSection title="Supplier & Date" color="blue" tinted stackOnMobile>
            <FormField label="Supplier *">
              <Select value={supplierId} onValueChange={setSupplierId}>
                <SelectTrigger className="w-full bg-white"><SelectValue placeholder={suppliers.length ? "Choose the supplier" : "Loading suppliers…"} /></SelectTrigger>
                <SelectContent>
                  {suppliers.map((c) => <SelectItem key={c.id} value={String(c.id)}>{c.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </FormField>
            <div className="min-w-0 space-y-1">
              <Label htmlFor="cd-date">Owed from *</Label>
              <Input id="cd-date" type="date" className="bg-white" value={date} onChange={(e) => setDate(e.target.value)} />
            </div>
          </FormSection>

          <FormSection title="Debt" color="amber" tinted>
            <div className="min-w-0 space-y-1">
              <Label htmlFor="cd-amount">Amount owed *</Label>
              <Input id="cd-amount" type="number" min={0} step="0.01" className="bg-white text-right font-semibold tabular-nums"
                     value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="0.00" />
            </div>
            <FormField label="Why is it owed *">
              <Select value={entryType} onValueChange={(v) => setEntryType(v as SupplierDebtEntryType)}>
                <SelectTrigger className="w-full bg-white"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {ENTRY_TYPES.map((t) => <SelectItem key={t} value={t}>{SUPPLIER_DEBT_ENTRY_LABEL[t]}</SelectItem>)}
                </SelectContent>
              </Select>
            </FormField>
            <div className="col-span-full min-w-0 space-y-1">
              <Label htmlFor="cd-desc">Description *</Label>
              <Input id="cd-desc" className="bg-white" value={description} onChange={(e) => setDescription(e.target.value)}
                     placeholder="e.g. Maize bought before we started using the system" />
            </div>
            <div className="col-span-full min-w-0 space-y-1">
              <Label htmlFor="cd-ref">Reference</Label>
              <Input id="cd-ref" className="bg-white" value={reference} onChange={(e) => setReference(e.target.value)} placeholder="Optional, e.g. old ledger page or invoice" />
            </div>
          </FormSection>

          <FormSection title="Notes" color="slate" tinted columns={1}>
            <div className="min-w-0 space-y-1">
              <Label htmlFor="cd-notes" className="sr-only">Notes</Label>
              <Textarea id="cd-notes" rows={2} className="bg-white" value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Optional" />
            </div>
          </FormSection>

          {value > 0 && supplierName && (
            <p className="rounded-md border border-amber-200 bg-amber-50 p-2.5 text-sm text-amber-900">
              You will owe {supplierName} <b className="tabular-nums">{formatCurrency(value, currencyCode)}</b> more. No cash moves and
              stock is not affected.
            </p>
          )}
          {error && <p className="rounded-md bg-red-50 p-2.5 text-sm text-red-700">{error}</p>}
        </div>

        <FormDialogFooter onCancel={() => onOpenChange(false)} cancelDisabled={saving}>
          <Button onClick={save} disabled={!valid || saving} className={cn("px-6", FORM_DIALOG_PRIMARY.amber)}>
            {saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            {value > 0 ? `Record debt · ${formatCurrency(value, currencyCode)}` : "Record debt"}
          </Button>
        </FormDialogFooter>
      </DialogContent>
    </Dialog>
  )
}
