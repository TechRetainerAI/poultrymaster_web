"use client"
import { useEffect, useRef, useState, useMemo } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { Loader2, Package, Plus, ShoppingCart, Undo2 } from "lucide-react"
import { useFmt } from "@/lib/currency"
import { HotelSupplyPurchaseDialog } from "@/components/hotel/supply-purchase-dialog"
import { listHotelSuppliers, type HotelSupplier } from "@/lib/api/hotel-suppliers"
import { loadHotelCashAccounts } from "@/lib/hotel/balances"
import type { CashAccountOption } from "@/components/balances/record-payment-dialog"
import {
  listSupplyPurchases, reverseSupplyPurchase, listSupplyCostModes, setSupplyCostMode, COST_MODE_LABELS,
  type HotelSupplyPurchase, type HotelSupplyCostModeRow, type CostMode,
} from "@/lib/api/hotel-supplies"

import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listHotelInventory, createHotelInventoryItem, listHotelSupplyCategories, listHotelSupplyItems,
  type HotelInventoryItem, type HotelSupplyCategory, type HotelSupplyItem,
} from "@/lib/api/hotel"
import { HotelOtherSelect, type HotelOtherSelectHandle } from "@/components/hotel/other-select"

export default function HotelInventoryPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [items, setItems] = useState<HotelInventoryItem[]>([])
  const [supplyCategories, setSupplyCategories] = useState<HotelSupplyCategory[]>([])
  const [supplyItems, setSupplyItems] = useState<HotelSupplyItem[]>([])
  const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false); const [saving, setSaving] = useState(false)
  // Handles on both "Other" dropdowns -- see handleSave.
  const supplyCategoryOther = useRef<HotelOtherSelectHandle>(null)
  const supplyItemOther = useRef<HotelOtherSelectHandle>(null)
  const [form, setForm] = useState({ name: "", category: "", unit: "pcs", stockOnHand: 0, reorderLevel: 10, unitCost: 0 })
  // 334: purchases that carry a cost, and how each category's cost is recognised.
  const fmt = useFmt()
  const [purchases, setPurchases] = useState<HotelSupplyPurchase[]>([])
  const [suppliers, setSuppliers] = useState<HotelSupplier[]>([])
  const [cashAccounts, setCashAccounts] = useState<CashAccountOption[]>([])
  const [costModes, setCostModes] = useState<HotelSupplyCostModeRow[]>([])
  const [purchaseOpen, setPurchaseOpen] = useState(false)
  const [purchaseDefaults, setPurchaseDefaults] = useState<{ itemId?: number | null }>({})
  const [focusPurchase, setFocusPurchase] = useState<number | null>(null)
  const [reverseTarget, setReverseTarget] = useState<HotelSupplyPurchase | null>(null)
  const [reverseReason, setReverseReason] = useState("")
  const [reversing, setReversing] = useState(false)

  // Deep links, Poultry's ?purchase=1 (&itemId=) and ?purchaseId= from other pages.
  useEffect(() => {
    if (typeof window === "undefined") return
    const q = new URLSearchParams(window.location.search)
    if (q.get("purchase") === "1") { setPurchaseDefaults({ itemId: Number(q.get("itemId")) || null }); setPurchaseOpen(true) }
    if (q.get("purchaseId")) setFocusPurchase(Number(q.get("purchaseId")) || null)
  }, [])

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])

  async function load() {
    setLoading(true)
    try {
      const [inv, cats, si] = await Promise.all([
        listHotelInventory(),
        listHotelSupplyCategories().catch(() => []),
        listHotelSupplyItems().catch(() => []),
      ])
      setItems(inv); setSupplyCategories(cats); setSupplyItems(si)
      const [pu, cm] = await Promise.all([listSupplyPurchases().catch(() => []), listSupplyCostModes().catch(() => [])])
      setPurchases(pu); setCostModes(cm)
      listHotelSuppliers().then(setSuppliers).catch(() => setSuppliers([]))
      loadHotelCashAccounts().then(setCashAccounts).catch(() => setCashAccounts([]))
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openCreate() {
    setForm({ name: "", category: "", unit: "pcs", stockOnHand: 0, reorderLevel: 10, unitCost: 0 })
    setDialogOpen(true)
  }

  async function handleSave() {
    if (!form.name.trim()) { toast({ title: "Name required", variant: "destructive" }); return }
    if (!form.category) { toast({ title: "Category required", variant: "destructive" }); return }
    setSaving(true)
    try {
      await createHotelInventoryItem(form)
      // Before setDialogOpen(false): closing unmounts the fields and nulls the refs.
      await supplyCategoryOther.current?.remember()
      await supplyItemOther.current?.remember()
      toast({ title: "Item added" }); setDialogOpen(false); await load()
    }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setSaving(false) }
  }

  // Filter supply items by selected category
  const filteredSupplyItems = useMemo(() => {
    if (!form.category) return supplyItems
    return supplyItems.filter(si => si.category === form.category)
  }, [supplyItems, form.category])

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3"><Package className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Supplies & Inventory</h1><span className="text-sm text-slate-500">({items.length})</span></div>
          <div className="flex gap-2">
            <Button variant="outline" onClick={() => { setPurchaseDefaults({}); setPurchaseOpen(true) }} className="border-violet-300 text-violet-700"><ShoppingCart className="h-4 w-4 mr-1" /> Record Purchase</Button>
            <Button onClick={openCreate} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> Add Item</Button>
          </div>
        </div>
        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
          <Card><CardContent className="p-0"><div className="overflow-x-auto"><table className="w-full text-sm min-w-[660px]"><thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">Name</th><th className="text-left p-3">Category</th><th className="text-left p-3">Unit</th><th className="text-right p-3">Stock</th><th className="text-right p-3">Reorder</th><th className="text-right p-3">Unit Cost</th></tr></thead>
            <tbody>{items.map((i: any) => {
              const stock = Number(i.stockOnHand ?? i.stockonhand ?? 0); const reorder = Number(i.reorderLevel ?? i.reorderlevel ?? 0)
              return (<tr key={i.hotelInventoryItemId ?? i.hotelinventoryitemid} className="border-b hover:bg-slate-50"><td className="p-3 font-medium">{i.name}</td><td className="p-3"><Badge variant="outline">{i.category}</Badge></td><td className="p-3">{i.unit}</td>
                <td className={`p-3 text-right font-semibold ${stock <= reorder ? "text-red-600" : ""}`}>{stock} {stock <= reorder && <Badge className="ml-1 bg-red-100 text-red-700 text-[10px]">Low</Badge>}</td>
                <td className="p-3 text-right">{reorder}</td><td className="p-3 text-right">{Number(i.unitCost ?? i.unitcost ?? 0).toFixed(2)}</td></tr>)
            })}
              {items.length === 0 && <tr><td colSpan={6} className="p-8 text-center text-slate-400">No inventory items. Add your hotel supplies.</td></tr>}
            </tbody></table></div></CardContent></Card>
        )}

        {!loading && (
          <Card className="mt-6"><CardContent className="p-0">
            <div className="flex items-center justify-between p-4 border-b">
              <div><h2 className="font-semibold">Purchases</h2><p className="text-xs text-slate-500">Each delivery is a cost lot used oldest first. What was not paid now is on Supplier Balances.</p></div>
              {focusPurchase && <Button variant="ghost" size="sm" onClick={() => setFocusPurchase(null)}>Show all</Button>}
            </div>
            <div className="overflow-x-auto"><table className="w-full text-sm min-w-[900px]"><thead className="bg-slate-50 border-b"><tr>
              <th className="text-left p-3">Purchase</th><th className="text-left p-3">Date</th><th className="text-left p-3">Item</th><th className="text-left p-3">Supplier</th>
              <th className="text-right p-3">Qty</th><th className="text-right p-3">Total</th><th className="text-right p-3">Paid</th><th className="text-right p-3">Balance</th>
              <th className="text-left p-3">Status</th><th className="text-left p-3">Cost recognition</th><th className="p-3"></th></tr></thead>
              <tbody>{purchases.filter((x) => !focusPurchase || x.purchaseId === focusPurchase).map((x) => (
                <tr key={x.purchaseId} className="border-b">
                  <td className="p-3 font-mono text-xs">PO-{x.purchaseId}</td><td className="p-3">{String(x.purchaseDate).slice(0, 10)}</td>
                  <td className="p-3">{x.itemName}</td><td className="p-3">{x.supplierName ?? "—"}</td>
                  <td className="p-3 text-right tabular-nums">{Number(x.quantity)} {x.unit ?? ""}</td>
                  <td className="p-3 text-right tabular-nums">{fmt(x.totalCost)}</td>
                  <td className="p-3 text-right tabular-nums text-emerald-700">{fmt(Number(x.amountPaid) + Number(x.allocated))}</td>
                  <td className={`p-3 text-right tabular-nums ${Number(x.balance) > 0 ? "font-semibold text-amber-700" : "text-slate-400"}`}>{fmt(x.balance)}</td>
                  <td className="p-3"><Badge variant="outline">{x.status === "Reversed" ? "Reversed" : x.paymentStatus}</Badge></td>
                  <td className="p-3 text-xs">{COST_MODE_LABELS[x.costMode] ?? x.costMode}</td>
                  <td className="p-3 text-right">{x.status !== "Reversed" && (
                    <Button variant="ghost" size="sm" onClick={() => { setReverseTarget(x); setReverseReason("") }} aria-label="Reverse purchase"><Undo2 className="h-4 w-4" /></Button>)}</td>
                </tr>))}
                {purchases.length === 0 && <tr><td colSpan={11} className="p-8 text-center text-slate-400">No purchases yet. Record a delivery with Record Purchase.</td></tr>}
              </tbody></table></div>
          </CardContent></Card>
        )}

        {!loading && costModes.length > 0 && (
          <Card className="mt-6"><CardContent className="p-4 space-y-3">
            <div><h2 className="font-semibold">Cost recognition</h2>
              <p className="text-xs text-slate-500">Per category: charge the whole purchase to Profit &amp; Loss when it is bought, or hold it as stock value and charge it as it is used (Deferred inventory cost). Applies to purchases recorded from now on.</p></div>
            <div className="grid gap-2 sm:grid-cols-2">
              {costModes.map((m) => (
                <div key={m.category} className="flex items-center justify-between gap-3 rounded-md border p-2">
                  <span className="text-sm font-medium">{m.category} <span className="text-xs text-slate-500">({m.itemCount})</span></span>
                  <Select value={m.costMode} onValueChange={async (v) => {
                    try { await setSupplyCostMode(m.category, v as CostMode); setCostModes(await listSupplyCostModes()); toast({ title: "Cost recognition saved" }) }
                    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
                  }}>
                    <SelectTrigger className="w-[220px]"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="EXPENSE_WHEN_PURCHASED">{COST_MODE_LABELS.EXPENSE_WHEN_PURCHASED}</SelectItem>
                      <SelectItem value="EXPENSE_WHEN_CONSUMED">{COST_MODE_LABELS.EXPENSE_WHEN_CONSUMED}</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
              ))}
            </div>
          </CardContent></Card>
        )}

        <HotelSupplyPurchaseDialog
          open={purchaseOpen}
          onOpenChange={setPurchaseOpen}
          items={items}
          suppliers={suppliers}
          cashAccounts={cashAccounts}
          costModes={costModes}
          defaults={purchaseDefaults}
          onSaved={load}
        />

        <Dialog open={!!reverseTarget} onOpenChange={(o) => { if (!o) setReverseTarget(null) }}>
          <DialogContent className="sm:max-w-md"><DialogHeader><DialogTitle>Reverse purchase</DialogTitle></DialogHeader>
            <p className="text-sm text-slate-600">PO-{reverseTarget?.purchaseId} · {reverseTarget?.itemName}. The stock goes back out and any cash paid comes back today.</p>
            <div><Label>Why is this being reversed? *</Label><Input value={reverseReason} onChange={(e) => setReverseReason(e.target.value)} placeholder="e.g. entered twice" /></div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setReverseTarget(null)}>Cancel</Button>
              <Button className="bg-red-600 hover:bg-red-700" disabled={reversing || !reverseReason.trim()} onClick={async () => {
                if (!reverseTarget) return
                setReversing(true)
                try { await reverseSupplyPurchase(reverseTarget.purchaseId, reverseReason.trim()); toast({ title: "Purchase reversed" }); setReverseTarget(null); await load() }
                catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
                finally { setReversing(false) }
              }}>{reversing && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}Reverse</Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}><DialogContent><DialogHeader><DialogTitle>Add Supply Item</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div>
              <Label>Category *</Label>
              {/* This dropdown used to offer BOTH "Other" (a seeded row in
                  hotelsupplycategories) and "Other (type category)" (this page's
                  own sentinel) — two entries, one of which silently stored the
                  word "Other" as the category. HotelOtherSelect drops any base
                  option literally reading "Other" and appends exactly one. */}
              <HotelOtherSelect
                ref={supplyCategoryOther}
                listKey="SupplyCategory"
                baseOptions={supplyCategories.map(c => c.description)}
                value={form.category}
                /* Changing category must clear the name: the item list below is
                   filtered by it, so a name from the previous category would be
                   left selected but no longer offered. */
                onChange={(v) => setForm({...form, category: v ?? "", name: ""})}
                placeholder="Select category"
                includeNone
                noneLabel="Select category"
                otherLabel="Other (type category)"
              />
            </div>
            <div>
              <Label>Name *</Label>
              <HotelOtherSelect
                ref={supplyItemOther}
                listKey="SupplyItemName"
                baseOptions={filteredSupplyItems.map(si => si.description)}
                value={form.name}
                onChange={(v) => setForm({...form, name: v ?? ""})}
                placeholder="Select item"
                includeNone
                noneLabel="Select item"
                otherLabel="Other (type name)"
              />
            </div>
            <div><Label>Unit</Label><Input value={form.unit} onChange={(e) => setForm({...form, unit: e.target.value})} placeholder="pcs, kg, litres" /></div>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              <div><Label>Stock</Label><Input type="number" value={form.stockOnHand} onChange={(e) => setForm({...form, stockOnHand: Number(e.target.value)})} /></div>
              <div><Label>Reorder Level</Label><Input type="number" value={form.reorderLevel} onChange={(e) => setForm({...form, reorderLevel: Number(e.target.value)})} /></div>
              <div><Label>Unit Cost</Label><Input type="number" step="0.01" value={form.unitCost} onChange={(e) => setForm({...form, unitCost: Number(e.target.value)})} /></div>
            </div>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setDialogOpen(false)}>Cancel</Button><Button onClick={handleSave} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}Add</Button></DialogFooter>
        </DialogContent></Dialog>
      </main></div></div>
  )
}
