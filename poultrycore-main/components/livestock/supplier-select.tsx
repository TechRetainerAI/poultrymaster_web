"use client"

// Supplier picker over the shared supplier list (lib/api/supplier, the same
// list every company type keeps), with "add a new supplier" in place.

import { useCallback, useEffect, useState } from "react"
import { Plus } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { useToast } from "@/hooks/use-toast"
import { getUserContext } from "@/lib/api/config"
import { createSupplier, getSuppliers, type Supplier } from "@/lib/api/supplier"
import { AMBER_BUTTON } from "./livestock-page"

const NONE = "__none"

export function useSuppliers() {
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const load = useCallback(async () => {
    const { userId, farmId } = getUserContext()
    const res = await getSuppliers(userId, farmId)
    setSuppliers(res.success ? (res.data ?? []).sort((a, b) => a.name.localeCompare(b.name)) : [])
  }, [])
  useEffect(() => { load() }, [load])
  return { suppliers, reload: load }
}

export function SupplierSelect({ value, onChange, allowNone = false, noneLabel = "No supplier (paid in cash)" }: {
  value: number | null
  onChange: (id: number | null) => void
  allowNone?: boolean
  noneLabel?: string
}) {
  const { suppliers, reload } = useSuppliers()
  const [adding, setAdding] = useState(false)
  return (
    <div className="flex gap-2">
      <Select value={value ? String(value) : allowNone ? NONE : ""} onValueChange={(v) => onChange(v === NONE ? null : Number(v))}>
        <SelectTrigger className="flex-1"><SelectValue placeholder="Choose a supplier" /></SelectTrigger>
        <SelectContent>
          {allowNone && <SelectItem value={NONE}>{noneLabel}</SelectItem>}
          {suppliers.map((s) => <SelectItem key={s.supplierId} value={String(s.supplierId)}>{s.name}</SelectItem>)}
        </SelectContent>
      </Select>
      <Button type="button" variant="outline" size="icon" aria-label="Add a supplier" onClick={() => setAdding(true)}><Plus className="h-4 w-4" /></Button>
      {adding && (
        <NewSupplierDialog onClose={() => setAdding(false)} onCreated={async (name) => {
          setAdding(false)
          await reload()
          const { userId, farmId } = getUserContext()
          const res = await getSuppliers(userId, farmId)
          const made = (res.data ?? []).filter((s) => s.name === name).sort((a, b) => b.supplierId - a.supplierId)[0]
          if (made) onChange(made.supplierId)
        }} />
      )}
    </div>
  )
}

export function NewSupplierDialog({ onClose, onCreated }: { onClose: () => void; onCreated: (name: string) => void }) {
  const { toast } = useToast()
  const [name, setName] = useState("")
  const [phone, setPhone] = useState("")
  const [address, setAddress] = useState("")
  const [saving, setSaving] = useState(false)
  const save = async () => {
    setSaving(true)
    const { userId, farmId } = getUserContext()
    const res = await createSupplier({ farmId, userId, name: name.trim(), contactPhone: phone.trim(), address: address.trim(), city: "" })
    setSaving(false)
    if (!res.success) { toast({ title: "Not saved", description: res.message, variant: "destructive" }); return }
    toast({ title: `${name.trim()} added` })
    onCreated(name.trim())
  }
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader><DialogTitle>New supplier</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <div><Label htmlFor="ns-name">Name</Label><Input id="ns-name" value={name} onChange={(e) => setName(e.target.value)} /></div>
          <div><Label htmlFor="ns-phone">Phone</Label><Input id="ns-phone" value={phone} onChange={(e) => setPhone(e.target.value)} /></div>
          <div><Label htmlFor="ns-addr">Address</Label><Input id="ns-addr" value={address} onChange={(e) => setAddress(e.target.value)} /></div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || !name.trim()} onClick={save}>{saving ? "Saving…" : "Add"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
