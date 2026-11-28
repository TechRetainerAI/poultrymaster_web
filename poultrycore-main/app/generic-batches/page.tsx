"use client"

// Pharmacy -> Batches & expiry (migration 511).
// Every batch of every medicine: batch number, expiry date, how much came in and how much
// is left. Batches are created by approving a purchase whose lines carry a batch number /
// expiry date, or here ("Label stock on the shelf") for stock that is already counted.
// Sales take stock from the batch that expires first. Expired or damaged stock is written
// off here; that is a stock adjustment and shows on Loss & Damage.

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { Loader2, PackageMinus, Pencil, Plus, Tag, Trash2 } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { PharmacyShell } from "@/components/generic/pharmacy/pharmacy-shell"
import { ClassBadge, ExpiryBadge } from "@/components/generic/pharmacy/badges"
import {
  addBatch, deleteBatch, getBatches, getMedicines, getPharmacySettings, updateBatch, writeOffBatch,
  type Medicine, type ProductBatch,
} from "@/lib/api/generic-pharmacy"
import { describeQty, expiryState, sellUnits, type SellUnit } from "@/lib/generic/pharmacy"

type View = "live" | "expired" | "soon" | "ok" | "used" | "all"

const today = () => new Date().toISOString().slice(0, 10)

export default function GenericBatchesPage() {
  const { toast } = useToast()
  const fmt = useFmt()
  const [loading, setLoading] = useState(true)
  const [batches, setBatches] = useState<ProductBatch[]>([])
  const [medicines, setMedicines] = useState<Medicine[]>([])
  const [days, setDays] = useState(90)
  const [productId, setProductId] = useState<string>("all")
  const [view, setView] = useState<View>("live")
  const [search, setSearch] = useState("")

  const [addOpen, setAddOpen] = useState(false)
  const [addForm, setAddForm] = useState({ productId: "", batchNumber: "", expiryDate: "", qty: "", unit: "", receivedDate: today(), notes: "" })
  const [editTarget, setEditTarget] = useState<ProductBatch | null>(null)
  const [editForm, setEditForm] = useState({ batchNumber: "", expiryDate: "", notes: "" })
  const [woTarget, setWoTarget] = useState<ProductBatch | null>(null)
  const [woForm, setWoForm] = useState({ qty: "", unit: "", reason: "" })
  const [delTarget, setDelTarget] = useState<ProductBatch | null>(null)
  const [busy, setBusy] = useState(false)

  const load = async () => {
    setLoading(true)
    try {
      const [bs, ms, st] = await Promise.all([getBatches(), getMedicines(), getPharmacySettings()])
      setBatches(bs); setMedicines(ms); setDays(st.expiryWarningDays || 90)
    } catch (e: any) {
      toast({ title: "Could not load batches", description: e?.message, variant: "destructive" })
    } finally { setLoading(false) }
  }
  useEffect(() => {
    const p = new URLSearchParams(window.location.search).get("productId")
    if (p) setProductId(p)
    const v = new URLSearchParams(window.location.search).get("view") as View | null
    if (v) setView(v)
    load()
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  const medById = useMemo(() => new Map(medicines.map((m) => [m.genericProductId, m])), [medicines])
  const unitsOf = (pid: number): SellUnit[] => {
    const m = medById.get(pid)
    return m ? sellUnits(m) : [{ unit: "unit", factor: 1, price: 0 }]
  }

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase()
    return batches.filter((b) => {
      if (productId !== "all" && String(b.genericProductId) !== productId) return false
      const s = expiryState(b.expiryDate, days)
      const left = b.quantityRemaining > 0
      if (view === "live" && !left) return false
      if (view === "used" && left) return false
      if (view === "expired" && !(left && s === "expired")) return false
      if (view === "soon" && !(left && s === "soon")) return false
      if (view === "ok" && !(left && (s === "ok" || s === "none"))) return false
      if (!q) return true
      return [b.productName, b.genericName, b.batchNumber, b.invoiceNumber].some((v) => (v ?? "").toLowerCase().includes(q))
    })
  }, [batches, productId, view, search, days])

  const totals = useMemo(() => {
    const live = batches.filter((b) => b.quantityRemaining > 0)
    const exp = live.filter((b) => expiryState(b.expiryDate, days) === "expired")
    const soon = live.filter((b) => expiryState(b.expiryDate, days) === "soon")
    const value = (xs: ProductBatch[]) => xs.reduce((s, b) => s + b.quantityRemaining * (Number(b.unitCost) || 0), 0)
    return { expired: exp.length, expiredValue: value(exp), soon: soon.length, soonValue: value(soon), live: live.length }
  }, [batches, days])

  // ---- Label stock already on the shelf --------------------------------
  const addMed = addForm.productId ? medById.get(Number(addForm.productId)) : undefined
  const addUnits = addMed ? sellUnits(addMed) : []
  const addFactor = addUnits.find((u) => u.unit === addForm.unit)?.factor ?? 1

  const onAdd = async () => {
    if (!addMed) { toast({ title: "Choose the medicine", variant: "destructive" }); return }
    const qty = (Number(addForm.qty) || 0) * addFactor
    if (qty <= 0) { toast({ title: "Enter the quantity", variant: "destructive" }); return }
    if (!addForm.batchNumber.trim() && !addForm.expiryDate) { toast({ title: "Enter a batch number or an expiry date", variant: "destructive" }); return }
    setBusy(true)
    try {
      await addBatch({
        genericProductId: addMed.genericProductId, batchNumber: addForm.batchNumber || null, expiryDate: addForm.expiryDate || null,
        quantity: qty, unitCost: addMed.costPrice || null, receivedDate: addForm.receivedDate || null, notes: addForm.notes || null,
      })
      toast({ title: "Batch recorded" })
      setAddOpen(false)
      load()
    } catch (e: any) {
      toast({ title: "Could not record the batch", description: e?.message, variant: "destructive" })
    } finally { setBusy(false) }
  }

  // ---- Edit ---------------------------------------------------------------
  const onEdit = async () => {
    if (!editTarget) return
    setBusy(true)
    try {
      await updateBatch(editTarget.genericProductBatchId, {
        batchNumber: editForm.batchNumber || null, expiryDate: editForm.expiryDate || null, notes: editForm.notes || null,
      })
      toast({ title: "Batch updated" })
      setEditTarget(null)
      load()
    } catch (e: any) {
      toast({ title: "Could not update", description: e?.message, variant: "destructive" })
    } finally { setBusy(false) }
  }

  // ---- Write off ---------------------------------------------------------
  const woUnits = woTarget ? unitsOf(woTarget.genericProductId) : []
  const woFactor = woUnits.find((u) => u.unit === woForm.unit)?.factor ?? 1
  const onWriteOff = async () => {
    if (!woTarget) return
    const qty = (Number(woForm.qty) || 0) * woFactor
    if (qty <= 0) { toast({ title: "Enter the quantity to write off", variant: "destructive" }); return }
    if (qty > woTarget.quantityRemaining) { toast({ title: "More than is left in this batch", variant: "destructive" }); return }
    setBusy(true)
    try {
      await writeOffBatch(woTarget.genericProductBatchId, qty, woForm.reason || null)
      toast({ title: "Written off", description: "Stock is reduced and the loss shows on Loss & Damage." })
      setWoTarget(null)
      load()
    } catch (e: any) {
      toast({ title: "Could not write off", description: e?.message, variant: "destructive" })
    } finally { setBusy(false) }
  }

  const onDelete = async () => {
    if (!delTarget) return
    try {
      await deleteBatch(delTarget.genericProductBatchId)
      toast({ title: "Batch removed" })
      setDelTarget(null)
      load()
    } catch (e: any) {
      toast({ title: "Could not remove", description: e?.message, variant: "destructive" })
    }
  }

  const VIEWS: { value: View; label: string }[] = [
    { value: "live", label: "In stock" },
    { value: "expired", label: "Expired" },
    { value: "soon", label: `Expiring within ${days} days` },
    { value: "ok", label: "Good" },
    { value: "used", label: "Used up" },
    { value: "all", label: "All" },
  ]

  return (
    <PharmacyShell
      title="Batches & expiry"
      subtitle="Batch numbers, expiry dates and what is left of each delivery"
      wide
      actions={
        <>
          <Button variant="outline" asChild><Link href="/generic-purchases/new"><Plus className="h-4 w-4 mr-1" /> Receive a purchase</Link></Button>
          <Button onClick={() => { setAddForm({ productId: productId !== "all" ? productId : "", batchNumber: "", expiryDate: "", qty: "", unit: "", receivedDate: today(), notes: "" }); setAddOpen(true) }}>
            <Tag className="h-4 w-4 mr-1" /> Label stock on the shelf
          </Button>
        </>
      }
    >
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Card><CardContent className="p-3">
          <div className="text-xs text-slate-500">Batches in stock</div>
          <div className="text-2xl font-semibold">{totals.live}</div>
        </CardContent></Card>
        <Card className="cursor-pointer" onClick={() => setView("expired")}><CardContent className="p-3">
          <div className="text-xs text-slate-500">Expired batches (cannot be sold)</div>
          <div className={`text-2xl font-semibold ${totals.expired ? "text-rose-600" : ""}`}>{totals.expired}</div>
          <div className="text-xs text-slate-500">{fmt(totals.expiredValue)} at cost</div>
        </CardContent></Card>
        <Card className="cursor-pointer" onClick={() => setView("soon")}><CardContent className="p-3">
          <div className="text-xs text-slate-500">Expiring within {days} days</div>
          <div className={`text-2xl font-semibold ${totals.soon ? "text-amber-600" : ""}`}>{totals.soon}</div>
          <div className="text-xs text-slate-500">{fmt(totals.soonValue)} at cost</div>
        </CardContent></Card>
        <Card><CardContent className="p-3 text-xs text-slate-600">
          Sales take stock from the batch that expires first. Expired stock is kept out of the till until it is written off.
        </CardContent></Card>
      </div>

      <Card>
        <CardContent className="space-y-3 p-3">
          <div className="flex flex-wrap gap-2">
            <Select value={productId} onValueChange={setProductId}>
              <SelectTrigger className="w-[260px]"><SelectValue placeholder="All medicines" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All medicines</SelectItem>
                {medicines.map((m) => <SelectItem key={m.genericProductId} value={String(m.genericProductId)}>{m.productName}</SelectItem>)}
              </SelectContent>
            </Select>
            <Select value={view} onValueChange={(v) => setView(v as View)}>
              <SelectTrigger className="w-[230px]"><SelectValue /></SelectTrigger>
              <SelectContent>{VIEWS.map((v) => <SelectItem key={v.value} value={v.value}>{v.label}</SelectItem>)}</SelectContent>
            </Select>
            <Input className="max-w-xs" placeholder="Search medicine, batch no., invoice" value={search} onChange={(e) => setSearch(e.target.value)} />
          </div>

          {loading ? (
            <div className="flex justify-center py-12"><Loader2 className="h-5 w-5 animate-spin text-slate-400" /></div>
          ) : filtered.length === 0 ? (
            <p className="py-10 text-center text-sm text-slate-500">
              No batches here. Batches are made when a purchase with batch numbers or expiry dates is approved,
              or with “Label stock on the shelf”.
            </p>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Medicine</TableHead>
                    <TableHead>Batch no.</TableHead>
                    <TableHead>Expiry</TableHead>
                    <TableHead>Received</TableHead>
                    <TableHead className="text-right">Came in</TableHead>
                    <TableHead className="text-right">Left</TableHead>
                    <TableHead>From</TableHead>
                    <TableHead className="text-right">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {filtered.map((b) => {
                    const units = unitsOf(b.genericProductId)
                    return (
                      <TableRow key={b.genericProductBatchId}>
                        <TableCell>
                          <div className="font-medium">{b.productName}</div>
                          <div className="flex items-center gap-1 text-xs text-slate-500">
                            {b.genericName}{b.medicineClass && <ClassBadge cls={b.medicineClass} />}
                          </div>
                        </TableCell>
                        <TableCell className="font-mono text-sm">{b.batchNumber ?? "—"}</TableCell>
                        <TableCell><ExpiryBadge date={b.expiryDate} days={days} /></TableCell>
                        <TableCell className="whitespace-nowrap text-sm">{String(b.receivedDate).slice(0, 10)}</TableCell>
                        <TableCell className="text-right text-sm whitespace-nowrap">{describeQty(b.quantityReceived, units)}</TableCell>
                        <TableCell className="text-right text-sm whitespace-nowrap font-medium">
                          {b.quantityRemaining > 0 ? describeQty(b.quantityRemaining, units) : <Badge variant="secondary">Used up</Badge>}
                        </TableCell>
                        <TableCell className="text-sm">
                          {b.sourceType === "Purchase"
                            ? <span>Purchase {b.invoiceNumber ?? `#${b.genericPurchaseId}`}</span>
                            : <span className="text-slate-500">Labelled by hand</span>}
                        </TableCell>
                        <TableCell className="text-right whitespace-nowrap">
                          <Button variant="ghost" size="sm" title="Correct batch no. / expiry" onClick={() => {
                            setEditTarget(b)
                            setEditForm({ batchNumber: b.batchNumber ?? "", expiryDate: b.expiryDate ? String(b.expiryDate).slice(0, 10) : "", notes: b.notes ?? "" })
                          }}><Pencil className="h-3.5 w-3.5" /></Button>
                          {b.quantityRemaining > 0 && (
                            <Button variant="outline" size="sm" onClick={() => { setWoTarget(b); setWoForm({ qty: "", unit: units[0]?.unit ?? "", reason: "" }) }}>
                              <PackageMinus className="h-3.5 w-3.5 mr-1" /> Write off
                            </Button>
                          )}
                          {b.sourceType === "Manual" && (
                            <Button variant="ghost" size="sm" title="Remove this label" onClick={() => setDelTarget(b)}>
                              <Trash2 className="h-3.5 w-3.5 text-red-500" />
                            </Button>
                          )}
                        </TableCell>
                      </TableRow>
                    )
                  })}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Label stock on the shelf */}
      <Dialog open={addOpen} onOpenChange={setAddOpen}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>Label stock on the shelf</DialogTitle>
            <DialogDescription>
              For stock that is already counted (opening stock, older purchases). It gives that stock a batch number and
              expiry date; it does not add stock. New deliveries get their batch on the purchase.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            <div>
              <Label>Medicine *</Label>
              <Select value={addForm.productId} onValueChange={(v) => {
                const m = medById.get(Number(v))
                setAddForm((f) => ({ ...f, productId: v, unit: m ? sellUnits(m)[0].unit : "" }))
              }}>
                <SelectTrigger><SelectValue placeholder="Choose" /></SelectTrigger>
                <SelectContent>{medicines.map((m) => <SelectItem key={m.genericProductId} value={String(m.genericProductId)}>{m.productName}</SelectItem>)}</SelectContent>
              </Select>
              {addMed && (
                <p className="mt-1 text-xs text-slate-500">
                  Without a batch yet: <strong>{describeQty(Math.max(0, addMed.unbatchedQty), addUnits)}</strong>
                </p>
              )}
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div><Label>Batch no.</Label><Input value={addForm.batchNumber} maxLength={80} onChange={(e) => setAddForm((f) => ({ ...f, batchNumber: e.target.value }))} /></div>
              <div><Label>Expiry date</Label><Input type="date" value={addForm.expiryDate} onChange={(e) => setAddForm((f) => ({ ...f, expiryDate: e.target.value }))} /></div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div><Label>Quantity *</Label><NumberInput min="0" step="1" value={addForm.qty} onChange={(e) => setAddForm((f) => ({ ...f, qty: e.target.value }))} /></div>
              <div>
                <Label>Unit</Label>
                <Select value={addForm.unit} onValueChange={(v) => setAddForm((f) => ({ ...f, unit: v }))} disabled={!addMed}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{addUnits.map((u) => <SelectItem key={u.unit} value={u.unit}>{u.unit}{u.factor !== 1 ? ` (${u.factor})` : ""}</SelectItem>)}</SelectContent>
                </Select>
              </div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div><Label>Received</Label><Input type="date" value={addForm.receivedDate} onChange={(e) => setAddForm((f) => ({ ...f, receivedDate: e.target.value }))} /></div>
              <div><Label>Notes</Label><Input value={addForm.notes} maxLength={500} onChange={(e) => setAddForm((f) => ({ ...f, notes: e.target.value }))} /></div>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setAddOpen(false)}>Cancel</Button>
            <Button onClick={onAdd} disabled={busy}>{busy && <Loader2 className="h-4 w-4 mr-1 animate-spin" />} Record batch</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Edit */}
      <Dialog open={!!editTarget} onOpenChange={(o) => { if (!o) setEditTarget(null) }}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Correct batch</DialogTitle>
            <DialogDescription>{editTarget?.productName}. Quantities do not change here.</DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            <div><Label>Batch no.</Label><Input value={editForm.batchNumber} maxLength={80} onChange={(e) => setEditForm((f) => ({ ...f, batchNumber: e.target.value }))} /></div>
            <div><Label>Expiry date</Label><Input type="date" value={editForm.expiryDate} onChange={(e) => setEditForm((f) => ({ ...f, expiryDate: e.target.value }))} /></div>
            <div><Label>Notes</Label><Input value={editForm.notes} maxLength={500} onChange={(e) => setEditForm((f) => ({ ...f, notes: e.target.value }))} /></div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setEditTarget(null)}>Cancel</Button>
            <Button onClick={onEdit} disabled={busy}>{busy && <Loader2 className="h-4 w-4 mr-1 animate-spin" />} Save</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Write off */}
      <Dialog open={!!woTarget} onOpenChange={(o) => { if (!o) setWoTarget(null) }}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Write off from batch {woTarget?.batchNumber ?? ""}</DialogTitle>
            <DialogDescription>
              {woTarget?.productName}: {woTarget ? describeQty(woTarget.quantityRemaining, woUnits) : ""} left.
              Stock goes down and the loss is listed on Loss &amp; Damage.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <div><Label>Quantity *</Label><NumberInput min="0" step="1" value={woForm.qty} onChange={(e) => setWoForm((f) => ({ ...f, qty: e.target.value }))} /></div>
              <div>
                <Label>Unit</Label>
                <Select value={woForm.unit} onValueChange={(v) => setWoForm((f) => ({ ...f, unit: v }))}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>{woUnits.map((u) => <SelectItem key={u.unit} value={u.unit}>{u.unit}{u.factor !== 1 ? ` (${u.factor})` : ""}</SelectItem>)}</SelectContent>
                </Select>
              </div>
            </div>
            {woTarget && (
              <Button variant="link" className="h-auto p-0 text-xs" onClick={() => setWoForm((f) => ({ ...f, qty: String(woTarget.quantityRemaining), unit: woUnits[0]?.unit ?? "" }))}>
                Write off all that is left
              </Button>
            )}
            <div><Label>Reason</Label><Input value={woForm.reason} maxLength={300} placeholder={woTarget && expiryState(woTarget.expiryDate, days) === "expired" ? "Expired" : "e.g. Damaged, broken bottle"} onChange={(e) => setWoForm((f) => ({ ...f, reason: e.target.value }))} /></div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setWoTarget(null)}>Cancel</Button>
            <Button variant="destructive" onClick={onWriteOff} disabled={busy}>{busy && <Loader2 className="h-4 w-4 mr-1 animate-spin" />} Write off</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <ConfirmDeleteDialog
        open={!!delTarget}
        onOpenChange={() => setDelTarget(null)}
        onConfirm={onDelete}
        title="Remove this batch label"
        description="The stock stays; it just has no batch number or expiry date any more."
      />
    </PharmacyShell>
  )
}
