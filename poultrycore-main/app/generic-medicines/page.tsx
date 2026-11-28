"use client"

// Pharmacy -> Medicines (migration 515).
// A medicine is a Generic product (name, base unit such as "tablet", price per tablet, cost)
// plus medicine details (generic name, strength, form, class A/B/C, FDA Ghana reg. no.)
// and the packs it is sold in (Strip = 10 tablets, Box = 100 tablets) with a price each.
// The shop's type (pharmacy or chemical shop) is set at the top of this page.

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Boxes, Loader2, Pencil, Plus, Save, Trash2 } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { PharmacyShell } from "@/components/generic/pharmacy/pharmacy-shell"
import { ClassBadge, ExpiryBadge } from "@/components/generic/pharmacy/badges"
import {
  getMedicines, getPharmacySettings, saveMedicine, savePharmacySettings,
  type Medicine, type MedicineClass, type PharmacySettings, type ProductPack,
} from "@/lib/api/generic-pharmacy"
import {
  DOSAGE_FORMS, MEDICINE_CLASSES, SHOP_TYPES, describeQty, packProblems, sellBlockReason, sellUnits,
} from "@/lib/generic/pharmacy"

type Show = "all" | "medicines" | "notset"

const EMPTY_FORM = {
  genericName: "", strength: "", dosageForm: "", medicineClass: "C" as MedicineClass,
  fdaRegNo: "", manufacturer: "", storageNote: "", isControlled: false,
  packs: [] as { packName: string; unitsPerPack: string; sellingPrice: string }[],
}

export default function GenericMedicinesPage() {
  const { toast } = useToast()
  const fmt = useFmt()
  const [loading, setLoading] = useState(true)
  const [rows, setRows] = useState<Medicine[]>([])
  const [settings, setSettings] = useState<PharmacySettings>({ shopType: "Pharmacy", requirePrescriptionClassA: true, expiryWarningDays: 90, saved: false })
  const [savingSettings, setSavingSettings] = useState(false)
  const [search, setSearch] = useState("")
  const [show, setShow] = useState<Show>("all")
  const [editing, setEditing] = useState<Medicine | null>(null)
  const [form, setForm] = useState(EMPTY_FORM)
  const [saving, setSaving] = useState(false)

  const load = async () => {
    setLoading(true)
    try {
      const [ms, st] = await Promise.all([getMedicines(), getPharmacySettings()])
      setRows(ms); setSettings(st)
    } catch (e: any) {
      toast({ title: "Could not load medicines", description: e?.message, variant: "destructive" })
    } finally { setLoading(false) }
  }
  useEffect(() => { load() }, []) // eslint-disable-line react-hooks/exhaustive-deps

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase()
    return rows.filter((m) => {
      if (show === "medicines" && !m.isMedicine) return false
      if (show === "notset" && m.isMedicine) return false
      if (!q) return true
      return [m.productName, m.genericName, m.sku, m.barcode, m.fdaRegNo].some((v) => (v ?? "").toLowerCase().includes(q))
    })
  }, [rows, search, show])

  const counts = useMemo(() => ({
    medicines: rows.filter((m) => m.isMedicine).length,
    notSet: rows.filter((m) => !m.isMedicine).length,
    expired: rows.filter((m) => m.expiredQty > 0).length,
    low: rows.filter((m) => m.trackInventory && m.minimumStockAlert > 0 && m.currentStock <= m.minimumStockAlert).length,
  }), [rows])

  const onSaveSettings = async () => {
    setSavingSettings(true)
    try {
      await savePharmacySettings({
        shopType: settings.shopType,
        requirePrescriptionClassA: settings.requirePrescriptionClassA,
        expiryWarningDays: Math.min(730, Math.max(1, Math.round(settings.expiryWarningDays || 90))),
      })
      toast({ title: "Pharmacy settings saved" })
      setSettings((s) => ({ ...s, saved: true }))
    } catch (e: any) {
      toast({ title: "Could not save settings", description: e?.message, variant: "destructive" })
    } finally { setSavingSettings(false) }
  }

  const openEdit = (m: Medicine) => {
    setEditing(m)
    setForm({
      genericName: m.genericName ?? "", strength: m.strength ?? "", dosageForm: m.dosageForm ?? "",
      medicineClass: m.medicineClass ?? "C", fdaRegNo: m.fdaRegNo ?? "", manufacturer: m.manufacturer ?? "",
      storageNote: m.storageNote ?? "", isControlled: !!m.isControlled,
      packs: (m.packs ?? []).map((p) => ({ packName: p.packName, unitsPerPack: String(p.unitsPerPack), sellingPrice: String(p.sellingPrice) })),
    })
  }

  const formPacks = (): ProductPack[] => form.packs
    .filter((p) => p.packName.trim())
    .map((p) => ({ packName: p.packName.trim(), unitsPerPack: Number(p.unitsPerPack) || 0, sellingPrice: Number(p.sellingPrice) || 0 }))

  const onSave = async () => {
    if (!editing) return
    const problems = packProblems(editing.baseUnit, formPacks())
    if (problems.length) { toast({ title: "Check the packs", description: problems.join(" "), variant: "destructive" }); return }
    setSaving(true)
    try {
      await saveMedicine(editing.genericProductId, {
        genericName: form.genericName || null, strength: form.strength || null, dosageForm: form.dosageForm || null,
        medicineClass: form.medicineClass, fdaRegNo: form.fdaRegNo || null, manufacturer: form.manufacturer || null,
        storageNote: form.storageNote || null, isControlled: form.isControlled, packs: formPacks(),
      })
      toast({ title: `${editing.productName} saved` })
      setEditing(null)
      load()
    } catch (e: any) {
      toast({ title: "Could not save", description: e?.message, variant: "destructive" })
    } finally { setSaving(false) }
  }

  const setPack = (i: number, patch: Partial<(typeof form.packs)[number]>) =>
    setForm((f) => ({ ...f, packs: f.packs.map((p, k) => (k === i ? { ...p, ...patch } : p)) }))

  const classWarning = editing ? sellBlockReason(settings.shopType, form.medicineClass) : null

  return (
    <PharmacyShell
      title="Medicines"
      subtitle="Medicine details and the packs each one is sold in"
      actions={
        <Button asChild variant="outline">
          <Link href="/generic-products"><Plus className="h-4 w-4 mr-1" /> Add a product</Link>
        </Button>
      }
    >
      <Card>
        <CardHeader className="pb-2"><CardTitle className="text-base">Shop settings</CardTitle></CardHeader>
        <CardContent className="grid gap-4 md:grid-cols-[1.4fr_1fr_1fr_auto] md:items-end">
          <div>
            <Label>This shop is a</Label>
            <Select value={settings.shopType} onValueChange={(v) => setSettings((s) => ({ ...s, shopType: v as PharmacySettings["shopType"] }))}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {SHOP_TYPES.map((t) => <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>)}
              </SelectContent>
            </Select>
            <p className="mt-1 text-xs text-slate-500">{SHOP_TYPES.find((t) => t.value === settings.shopType)?.hint}</p>
          </div>
          <div className="flex items-center gap-2 pb-6">
            <Switch id="rx-required" checked={settings.requirePrescriptionClassA}
              onCheckedChange={(v) => setSettings((s) => ({ ...s, requirePrescriptionClassA: v }))} />
            <Label htmlFor="rx-required" className="cursor-pointer text-sm">Class A sale needs a prescription record</Label>
          </div>
          <div>
            <Label>Warn about expiry (days before)</Label>
            <NumberInput min="1" max="730" step="1" value={settings.expiryWarningDays}
              onChange={(e) => setSettings((s) => ({ ...s, expiryWarningDays: Number(e.target.value) || 0 }))} />
          </div>
          <div className="pb-0.5">
            <Button onClick={onSaveSettings} disabled={savingSettings}>
              {savingSettings ? <Loader2 className="h-4 w-4 mr-1 animate-spin" /> : <Save className="h-4 w-4 mr-1" />} Save
            </Button>
          </div>
        </CardContent>
      </Card>

      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        {[
          { label: "Medicines set up", value: counts.medicines },
          { label: "Products not set up yet", value: counts.notSet },
          { label: "With expired stock", value: counts.expired, warn: counts.expired > 0 },
          { label: "Low stock", value: counts.low, warn: counts.low > 0 },
        ].map((k) => (
          <Card key={k.label}><CardContent className="p-3">
            <div className="text-xs text-slate-500">{k.label}</div>
            <div className={`text-2xl font-semibold ${k.warn ? "text-rose-600" : "text-slate-900"}`}>{k.value}</div>
          </CardContent></Card>
        ))}
      </div>

      <Card>
        <CardContent className="space-y-3 p-3">
          <div className="flex flex-wrap gap-2">
            <Input className="max-w-xs" placeholder="Search name, generic name, barcode, FDA no." value={search} onChange={(e) => setSearch(e.target.value)} />
            <Select value={show} onValueChange={(v) => setShow(v as Show)}>
              <SelectTrigger className="w-[220px]"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All products</SelectItem>
                <SelectItem value="medicines">Medicines set up</SelectItem>
                <SelectItem value="notset">Not set up as a medicine yet</SelectItem>
              </SelectContent>
            </Select>
          </div>

          {loading ? (
            <div className="flex justify-center py-12"><Loader2 className="h-5 w-5 animate-spin text-slate-400" /></div>
          ) : filtered.length === 0 ? (
            <p className="py-10 text-center text-sm text-slate-500">
              No products yet. Add each medicine in <Link className="text-emerald-700 underline" href="/generic-products">Products &amp; Services</Link> with
              its smallest unit (for example “tablet”) and the price of one, then set it up here.
            </p>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Medicine</TableHead>
                    <TableHead>Class</TableHead>
                    <TableHead>Sold as</TableHead>
                    <TableHead className="text-right">In stock</TableHead>
                    <TableHead>Nearest expiry</TableHead>
                    <TableHead className="text-right">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {filtered.map((m) => {
                    const units = sellUnits(m)
                    return (
                      <TableRow key={m.genericProductId}>
                        <TableCell>
                          <div className="font-medium">{m.productName}</div>
                          <div className="text-xs text-slate-500">
                            {[m.genericName, m.strength, m.dosageForm].filter(Boolean).join(" · ") || (m.isMedicine ? "" : "Not set up as a medicine yet")}
                            {m.fdaRegNo ? ` · FDA ${m.fdaRegNo}` : ""}
                          </div>
                        </TableCell>
                        <TableCell>{m.isMedicine ? <ClassBadge cls={m.medicineClass} /> : <span className="text-slate-400">—</span>}</TableCell>
                        <TableCell className="text-sm">
                          {units.map((u) => (
                            <div key={u.unit} className="whitespace-nowrap">
                              {u.unit}{u.factor !== 1 ? ` (${u.factor} ${m.baseUnit})` : ""}: <strong>{fmt(u.price)}</strong>
                            </div>
                          ))}
                        </TableCell>
                        <TableCell className="text-right text-sm">
                          <div className="whitespace-nowrap">{describeQty(m.currentStock, units)}</div>
                          {m.expiredQty > 0 && <div className="text-xs text-rose-600">{describeQty(m.expiredQty, units)} expired</div>}
                        </TableCell>
                        <TableCell><ExpiryBadge date={m.nearestExpiry} days={settings.expiryWarningDays} /></TableCell>
                        <TableCell className="text-right whitespace-nowrap">
                          <Button variant="outline" size="sm" onClick={() => openEdit(m)}>
                            <Pencil className="h-3.5 w-3.5 mr-1" /> {m.isMedicine ? "Edit" : "Set up"}
                          </Button>{" "}
                          <Button variant="ghost" size="sm" asChild>
                            <Link href={`/generic-batches?productId=${m.genericProductId}`}><Boxes className="h-3.5 w-3.5 mr-1" /> Batches</Link>
                          </Button>
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

      <Dialog open={!!editing} onOpenChange={(o) => { if (!o) setEditing(null) }}>
        <DialogContent className="sm:max-w-3xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{editing?.productName}</DialogTitle>
            <DialogDescription>
              Sold by the {editing?.baseUnit} at {fmt(editing?.sellingPrice ?? 0)} (cost {fmt(editing?.costPrice ?? 0)}).
              The name, base unit and these prices are changed in <Link className="text-emerald-700 underline" href="/generic-products">Products &amp; Services</Link>.
            </DialogDescription>
          </DialogHeader>

          <div className="grid gap-3 sm:grid-cols-2">
            <div>
              <Label>Generic name</Label>
              <Input value={form.genericName} maxLength={200} placeholder="e.g. Paracetamol" onChange={(e) => setForm((f) => ({ ...f, genericName: e.target.value }))} />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <Label>Strength</Label>
                <Input value={form.strength} maxLength={80} placeholder="e.g. 500mg" onChange={(e) => setForm((f) => ({ ...f, strength: e.target.value }))} />
              </div>
              <div>
                <Label>Form</Label>
                <Select value={form.dosageForm || "__none"} onValueChange={(v) => setForm((f) => ({ ...f, dosageForm: v === "__none" ? "" : v }))}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="__none">—</SelectItem>
                    {DOSAGE_FORMS.map((d) => <SelectItem key={d} value={d}>{d}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
            </div>
            <div>
              <Label>Class</Label>
              <Select value={form.medicineClass} onValueChange={(v) => setForm((f) => ({ ...f, medicineClass: v as MedicineClass }))}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {MEDICINE_CLASSES.map((c) => <SelectItem key={c.value} value={c.value}>{c.label}</SelectItem>)}
                </SelectContent>
              </Select>
              <p className={`mt-1 text-xs ${classWarning ? "text-amber-700" : "text-slate-500"}`}>
                {classWarning ?? MEDICINE_CLASSES.find((c) => c.value === form.medicineClass)?.hint}
              </p>
            </div>
            <div>
              <Label>FDA Ghana registration no.</Label>
              <Input value={form.fdaRegNo} maxLength={80} onChange={(e) => setForm((f) => ({ ...f, fdaRegNo: e.target.value }))} />
            </div>
            <div>
              <Label>Manufacturer</Label>
              <Input value={form.manufacturer} maxLength={200} onChange={(e) => setForm((f) => ({ ...f, manufacturer: e.target.value }))} />
            </div>
            <div>
              <Label>Storage</Label>
              <Input value={form.storageNote} maxLength={300} placeholder="e.g. Store below 25°C" onChange={(e) => setForm((f) => ({ ...f, storageNote: e.target.value }))} />
            </div>
            <div className="flex items-center gap-2 sm:col-span-2">
              <Switch id="controlled" checked={form.isControlled} onCheckedChange={(v) => setForm((f) => ({ ...f, isControlled: v }))} />
              <Label htmlFor="controlled" className="cursor-pointer text-sm">Controlled drug (shows on the controlled drugs list in Pharmacy reports)</Label>
            </div>
          </div>

          <div className="mt-2 space-y-2 rounded-md border p-3">
            <div className="flex items-center justify-between">
              <div>
                <div className="font-medium text-sm">Packs</div>
                <div className="text-xs text-slate-500">
                  Bigger units this medicine is sold in. Stock is always counted in {editing?.baseUnit}s, so selling one
                  strip takes its {editing?.baseUnit}s out of stock. Purchases offer these packs too.
                </div>
              </div>
              <Button variant="outline" size="sm" onClick={() => setForm((f) => ({ ...f, packs: [...f.packs, { packName: "", unitsPerPack: "", sellingPrice: "" }] }))}>
                <Plus className="h-3.5 w-3.5 mr-1" /> Add pack
              </Button>
            </div>
            {form.packs.length === 0 ? (
              <p className="text-xs text-slate-500">No packs: sold by the {editing?.baseUnit} only.</p>
            ) : form.packs.map((p, i) => {
              const per = Number(p.unitsPerPack) > 0 ? (Number(p.sellingPrice) || 0) / Number(p.unitsPerPack) : null
              return (
                <div key={i} className="grid grid-cols-[1fr_1fr_1fr_auto] items-end gap-2">
                  <div>
                    <Label className="text-xs">Pack name</Label>
                    <Input value={p.packName} maxLength={50} placeholder="Strip, Card, Box" onChange={(e) => setPack(i, { packName: e.target.value })} />
                  </div>
                  <div>
                    <Label className="text-xs">{editing?.baseUnit}s in one</Label>
                    <NumberInput min="0" step="1" value={p.unitsPerPack} onChange={(e) => setPack(i, { unitsPerPack: e.target.value })} />
                  </div>
                  <div>
                    <Label className="text-xs">Price of one pack</Label>
                    <NumberInput min="0" step="0.01" value={p.sellingPrice} onChange={(e) => setPack(i, { sellingPrice: e.target.value })} />
                    {per != null && <div className="text-[11px] text-slate-500">= {fmt(per)} per {editing?.baseUnit}</div>}
                  </div>
                  <Button variant="ghost" size="sm" onClick={() => setForm((f) => ({ ...f, packs: f.packs.filter((_, k) => k !== i) }))} title="Remove pack">
                    <Trash2 className="h-4 w-4 text-red-500" />
                  </Button>
                </div>
              )
            })}
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={() => setEditing(null)}>Cancel</Button>
            <Button onClick={onSave} disabled={saving}>{saving ? <Loader2 className="h-4 w-4 mr-1 animate-spin" /> : null} Save medicine</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </PharmacyShell>
  )
}
