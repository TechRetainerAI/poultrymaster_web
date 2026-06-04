"use client"

// Reusable Paid-To picker used by the Expense form, the Raw Material &
// Supplies Purchase form, and any other place we need to pick a supplier
// from the WaterSuppliers master list (migration 076).
//
// Includes a "+ Add new" affordance that opens a tiny inline dialog so the
// user can create a supplier without leaving the parent form — required by
// the spec ("Option to add a new supplier quickly if needed").
//
// `allowNone` adds a "No supplier / Other" entry that resolves to null —
// also a spec requirement so manual one-off expenses don't have to commit
// to a supplier record.

import * as React from "react"
import { Plus, Loader2 } from "lucide-react"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterSuppliers,
  createWaterSupplier,
  type WaterSupplier,
  type WaterSupplierInput,
  WATER_SUPPLIER_TYPES,
} from "@/lib/api/water"

// Sentinel so Radix Select can hold a value for "none" (Radix forbids "").
const NONE_VALUE = "__none__"

export interface SupplierSelectProps {
  value: number | null | undefined
  onChange: (id: number | null) => void
  allowNone?: boolean
  noneLabel?: string
  placeholder?: string
  disabled?: boolean
  className?: string
  // Defaults to the first SupplierType in the list when the inline-create
  // dialog opens. Lets parent forms pre-seed e.g. "Fuel Supplier" on the
  // fuel-expense form. Optional — falls back to "Other".
  defaultNewSupplierType?: string
}

export function SupplierSelect(props: SupplierSelectProps) {
  const { value, onChange, allowNone = true, noneLabel = "No supplier / Other",
          placeholder = "Select supplier…", disabled, className, defaultNewSupplierType } = props
  const { toast } = useToast()

  const [suppliers, setSuppliers] = React.useState<WaterSupplier[]>([])
  const [loading, setLoading]     = React.useState(true)
  const [addOpen, setAddOpen]     = React.useState(false)

  // Inline-create form state.
  const [addForm, setAddForm] = React.useState<WaterSupplierInput>({
    supplierName: "", supplierType: defaultNewSupplierType ?? "Other",
    contactPerson: "", phone: "", email: "",
  })
  const [saving, setSaving] = React.useState(false)

  const load = React.useCallback(async () => {
    setLoading(true)
    try { setSuppliers(await listWaterSuppliers()) }
    catch (e: any) { toast({ title: "Could not load suppliers", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }, [toast])

  React.useEffect(() => { void load() }, [load])

  // Radix Select treats value="" as "no value selected" (it renders the
  // placeholder). We use a sentinel for the explicit "No supplier" choice.
  const selectValue = value == null
    ? (allowNone ? NONE_VALUE : "")
    : String(value)

  function handleChange(v: string) {
    if (v === NONE_VALUE) { onChange(null); return }
    if (v === "__add__") { setAddOpen(true); return }
    const id = Number(v)
    onChange(Number.isFinite(id) ? id : null)
  }

  async function saveNew() {
    if (!addForm.supplierName.trim()) {
      toast({ title: "Supplier name is required", variant: "destructive" })
      return
    }
    setSaving(true)
    try {
      const created = await createWaterSupplier(addForm)
      toast({ title: "Supplier added", description: created.supplierName })
      setSuppliers((prev) => [...prev, created].sort((a, b) => a.supplierName.localeCompare(b.supplierName)))
      onChange(created.waterSupplierId)
      setAddOpen(false)
      setAddForm({ supplierName: "", supplierType: defaultNewSupplierType ?? "Other",
                   contactPerson: "", phone: "", email: "" })
    } catch (e: any) {
      toast({ title: "Could not save supplier", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  return (
    <>
      <Select value={selectValue} onValueChange={handleChange} disabled={disabled || loading}>
        <SelectTrigger className={className}>
          <SelectValue placeholder={loading ? "Loading suppliers…" : placeholder} />
        </SelectTrigger>
        <SelectContent>
          {allowNone && <SelectItem value={NONE_VALUE}>{noneLabel}</SelectItem>}
          {suppliers.map((s) => (
            <SelectItem key={s.waterSupplierId} value={String(s.waterSupplierId)}>
              {s.supplierName}{s.supplierType ? ` · ${s.supplierType}` : ""}
            </SelectItem>
          ))}
          <SelectItem value="__add__">+ Add new supplier…</SelectItem>
        </SelectContent>
      </Select>

      <Dialog open={addOpen} onOpenChange={setAddOpen}>
        <DialogContent className="w-[95vw] max-w-[560px]">
          <DialogHeader>
            <DialogTitle>Add supplier</DialogTitle>
            <DialogDescription>
              Quick-add. You can fill in the rest of the details from the
              Suppliers page later.
            </DialogDescription>
          </DialogHeader>
          <div className="grid gap-3 py-2">
            <div className="grid gap-1.5">
              <Label htmlFor="sup-name">Supplier name *</Label>
              <Input id="sup-name" value={addForm.supplierName}
                onChange={(e) => setAddForm({ ...addForm, supplierName: e.target.value })}
                placeholder="e.g. Goil Station, ECG, Acme Spare Parts" />
            </div>
            <div className="grid gap-1.5">
              <Label htmlFor="sup-type">Supplier type</Label>
              <Select value={addForm.supplierType ?? "Other"}
                onValueChange={(v) => setAddForm({ ...addForm, supplierType: v })}>
                <SelectTrigger id="sup-type"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {WATER_SUPPLIER_TYPES.map((t) => (
                    <SelectItem key={t} value={t}>{t}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <div className="grid gap-1.5">
                <Label htmlFor="sup-contact">Contact person</Label>
                <Input id="sup-contact" value={addForm.contactPerson ?? ""}
                  onChange={(e) => setAddForm({ ...addForm, contactPerson: e.target.value })} />
              </div>
              <div className="grid gap-1.5">
                <Label htmlFor="sup-phone">Phone</Label>
                <Input id="sup-phone" value={addForm.phone ?? ""}
                  onChange={(e) => setAddForm({ ...addForm, phone: e.target.value })} />
              </div>
            </div>
            <div className="grid gap-1.5">
              <Label htmlFor="sup-email">Email</Label>
              <Input id="sup-email" type="email" value={addForm.email ?? ""}
                onChange={(e) => setAddForm({ ...addForm, email: e.target.value })} />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setAddOpen(false)} disabled={saving}>Cancel</Button>
            <Button onClick={saveNew} disabled={saving}>
              {saving ? <><Loader2 className="mr-2 h-4 w-4 animate-spin" />Saving…</> : <><Plus className="mr-2 h-4 w-4" />Add supplier</>}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  )
}
