"use client"

// Customer picker over the shared customer list, with "add a new customer" in
// place. Uses the livestock client (lib/api/customer would fall back to mock
// customers on failure, which must never be picked for a sale).

import { useCallback, useEffect, useState } from "react"
import { Plus } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { useToast } from "@/hooks/use-toast"
import { listCustomers, saveCustomer, type LsCustomer } from "@/lib/api/livestock"
import { AMBER_BUTTON } from "./livestock-page"

const NONE = "__none"

export function useCustomers() {
  const [customers, setCustomers] = useState<LsCustomer[]>([])
  const reload = useCallback(async () => {
    try { setCustomers(await listCustomers()) } catch { setCustomers([]) }
  }, [])
  useEffect(() => { reload() }, [reload])
  return { customers, reload }
}

export function CustomerSelect({ value, onChange, allowNone = false, noneLabel = "Walk-in (paid now)" }: {
  value: number | null
  onChange: (id: number | null) => void
  allowNone?: boolean
  noneLabel?: string
}) {
  const { customers, reload } = useCustomers()
  const [adding, setAdding] = useState(false)
  return (
    <div className="flex gap-2">
      <Select value={value ? String(value) : allowNone ? NONE : ""} onValueChange={(v) => onChange(v === NONE ? null : Number(v))}>
        <SelectTrigger className="flex-1"><SelectValue placeholder="Choose a customer" /></SelectTrigger>
        <SelectContent>
          {allowNone && <SelectItem value={NONE}>{noneLabel}</SelectItem>}
          {customers.map((c) => <SelectItem key={c.customerId} value={String(c.customerId)}>{c.name}{c.contactPhone ? ` · ${c.contactPhone}` : ""}</SelectItem>)}
        </SelectContent>
      </Select>
      <Button type="button" variant="outline" size="icon" aria-label="Add a customer" onClick={() => setAdding(true)}><Plus className="h-4 w-4" /></Button>
      {adding && (
        <CustomerDialog onClose={() => setAdding(false)} onSaved={async (name) => {
          setAdding(false)
          const list = await listCustomers().catch(() => [] as LsCustomer[])
          await reload()
          const made = list.filter((c) => c.name === name).sort((a, b) => b.customerId - a.customerId)[0]
          if (made) onChange(made.customerId)
        }} />
      )}
    </div>
  )
}

export function CustomerDialog({ customer, onClose, onSaved }: { customer?: LsCustomer; onClose: () => void; onSaved: (name: string) => void }) {
  const { toast } = useToast()
  const [name, setName] = useState(customer?.name ?? "")
  const [phone, setPhone] = useState(customer?.contactPhone ?? "")
  const [email, setEmail] = useState(customer?.contactEmail ?? "")
  const [address, setAddress] = useState(customer?.address ?? "")
  const [city, setCity] = useState(customer?.city ?? "")
  const [saving, setSaving] = useState(false)
  const save = async () => {
    setSaving(true)
    try {
      await saveCustomer({ name: name.trim(), contactPhone: phone.trim(), contactEmail: email.trim() || null, address: address.trim(), city: city.trim() }, customer?.customerId)
      toast({ title: customer ? "Customer updated" : `${name.trim()} added` })
      onSaved(name.trim())
    } catch (e: any) {
      toast({ title: "Not saved", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader><DialogTitle>{customer ? `Edit ${customer.name}` : "New customer"}</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <div><Label htmlFor="cu-name">Name</Label><Input id="cu-name" value={name} onChange={(e) => setName(e.target.value)} /></div>
          <div className="grid grid-cols-2 gap-3">
            <div><Label htmlFor="cu-phone">Phone</Label><Input id="cu-phone" value={phone} onChange={(e) => setPhone(e.target.value)} /></div>
            <div><Label htmlFor="cu-email">Email</Label><Input id="cu-email" value={email} onChange={(e) => setEmail(e.target.value)} /></div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div><Label htmlFor="cu-addr">Address</Label><Input id="cu-addr" value={address} onChange={(e) => setAddress(e.target.value)} /></div>
            <div><Label htmlFor="cu-city">Town</Label><Input id="cu-city" value={city} onChange={(e) => setCity(e.target.value)} /></div>
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || !name.trim()} onClick={save}>{saving ? "Saving…" : "Save"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
