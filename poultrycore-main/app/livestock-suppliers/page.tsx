"use client"

// Suppliers -- the shared supplier list (the same one every company type
// keeps), with what this farm owes each.

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { Pencil, Plus, Truck } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { useToast } from "@/hooks/use-toast"
import { getUserContext } from "@/lib/api/config"
import { updateSupplier, type Supplier } from "@/lib/api/supplier"
import { listSupplierBalances, type SupplierBalance } from "@/lib/api/livestock"
import { NewSupplierDialog, useSuppliers } from "@/components/livestock/supplier-select"
import { AMBER_BUTTON, EmptyState, LivestockPage, fmtMoney } from "@/components/livestock/livestock-page"

export default function LivestockSuppliersPage() {
  const { suppliers, reload } = useSuppliers()
  const [balances, setBalances] = useState<SupplierBalance[]>([])
  const [adding, setAdding] = useState(false)
  const [editing, setEditing] = useState<Supplier | null>(null)
  const loadBalances = useCallback(() => { listSupplierBalances().then(setBalances).catch(() => setBalances([])) }, [])
  useEffect(() => { loadBalances() }, [loadBalances])
  const owed = useMemo(() => new Map(balances.map((b) => [b.supplierId, b.owed])), [balances])
  const pg = usePagination(suppliers, 10)

  return (
    <LivestockPage
      title="Suppliers"
      description="Who you buy feed, medicine and animals from."
      icon={Truck}
      actions={<Button className={AMBER_BUTTON} onClick={() => setAdding(true)}><Plus className="h-4 w-4 mr-1" /> Add supplier</Button>}
    >
      {suppliers.length === 0 ? <EmptyState title="No suppliers yet" /> : (
        <div className="rounded-md border bg-white overflow-x-auto">
          <Table>
            <TableHeader><TableRow><TableHead>Name</TableHead><TableHead>Phone</TableHead><TableHead>Address</TableHead><TableHead className="text-right">You owe</TableHead><TableHead /></TableRow></TableHeader>
            <TableBody>
              {pg.pageItems.map((s) => (
                <TableRow key={s.supplierId}>
                  <TableCell className="font-medium">{s.name}</TableCell>
                  <TableCell>{s.contactPhone || "—"}</TableCell>
                  <TableCell>{[s.address, s.city].filter(Boolean).join(", ") || "—"}</TableCell>
                  <TableCell className="text-right">
                    {owed.get(s.supplierId) ? <Link className="text-amber-800 hover:underline" href={`/livestock-supplier-balances?supplierId=${s.supplierId}`}>{fmtMoney(owed.get(s.supplierId))}</Link> : "—"}
                  </TableCell>
                  <TableCell className="text-right"><Button variant="ghost" size="icon" aria-label={`Edit ${s.name}`} onClick={() => setEditing(s)}><Pencil className="h-4 w-4" /></Button></TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
          <DataPagination {...pg.paginationProps} variant="records" />
        </div>
      )}
      {adding && <NewSupplierDialog onClose={() => setAdding(false)} onCreated={() => { setAdding(false); reload() }} />}
      {editing && <EditSupplierDialog supplier={editing} onClose={() => setEditing(null)} onSaved={() => { setEditing(null); reload(); loadBalances() }} />}
    </LivestockPage>
  )
}

function EditSupplierDialog({ supplier, onClose, onSaved }: { supplier: Supplier; onClose: () => void; onSaved: () => void }) {
  const { toast } = useToast()
  const [name, setName] = useState(supplier.name)
  const [phone, setPhone] = useState(supplier.contactPhone)
  const [email, setEmail] = useState(supplier.contactEmail)
  const [address, setAddress] = useState(supplier.address)
  const [city, setCity] = useState(supplier.city)
  const [saving, setSaving] = useState(false)
  const save = async () => {
    setSaving(true)
    const { userId, farmId } = getUserContext()
    const res = await updateSupplier(supplier.supplierId, { farmId, userId, name: name.trim(), contactPhone: phone, contactEmail: email, address, city })
    setSaving(false)
    if (!res.success) { toast({ title: "Not saved", description: res.message, variant: "destructive" }); return }
    toast({ title: "Supplier updated" }); onSaved()
  }
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader><DialogTitle>Edit {supplier.name}</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <div><Label htmlFor="es-name">Name</Label><Input id="es-name" value={name} onChange={(e) => setName(e.target.value)} /></div>
          <div className="grid grid-cols-2 gap-3">
            <div><Label htmlFor="es-phone">Phone</Label><Input id="es-phone" value={phone} onChange={(e) => setPhone(e.target.value)} /></div>
            <div><Label htmlFor="es-email">Email</Label><Input id="es-email" value={email} onChange={(e) => setEmail(e.target.value)} /></div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div><Label htmlFor="es-addr">Address</Label><Input id="es-addr" value={address} onChange={(e) => setAddress(e.target.value)} /></div>
            <div><Label htmlFor="es-city">Town</Label><Input id="es-city" value={city} onChange={(e) => setCity(e.target.value)} /></div>
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
