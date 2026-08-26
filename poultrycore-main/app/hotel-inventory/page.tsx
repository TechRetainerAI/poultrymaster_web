"use client"
import { useEffect, useState } from "react"
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
import { Loader2, Package, Plus } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listHotelInventory, createHotelInventoryItem, type HotelInventoryItem } from "@/lib/api/hotel"

const CATEGORIES = ["Linen", "Toiletry", "Minibar", "Kitchen", "Cleaning", "Stationery", "Uniform", "Other"]

export default function HotelInventoryPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [items, setItems] = useState<HotelInventoryItem[]>([]); const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false); const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({ name: "", category: "Linen", unit: "pcs", stockOnHand: 0, reorderLevel: 10, unitCost: 0 })

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])
  async function load() { setLoading(true); try { setItems(await listHotelInventory()) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setLoading(false) } }

  async function handleSave() {
    if (!form.name.trim()) { toast({ title: "Name required", variant: "destructive" }); return }
    setSaving(true)
    try { await createHotelInventoryItem(form); toast({ title: "Item added" }); setDialogOpen(false); await load() }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setSaving(false) }
  }

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3"><Package className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Supplies & Inventory</h1><span className="text-sm text-slate-500">({items.length})</span></div>
          <Button onClick={() => { setForm({ name: "", category: "Linen", unit: "pcs", stockOnHand: 0, reorderLevel: 10, unitCost: 0 }); setDialogOpen(true) }} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> Add Item</Button>
        </div>
        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
          <Card><CardContent className="p-0"><table className="w-full text-sm"><thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">Name</th><th className="text-left p-3">Category</th><th className="text-left p-3">Unit</th><th className="text-right p-3">Stock</th><th className="text-right p-3">Reorder</th><th className="text-right p-3">Unit Cost</th></tr></thead>
            <tbody>{items.map((i: any) => {
              const stock = Number(i.stockOnHand ?? i.stockonhand ?? 0); const reorder = Number(i.reorderLevel ?? i.reorderlevel ?? 0)
              return (<tr key={i.hotelInventoryItemId ?? i.hotelinventoryitemid} className="border-b hover:bg-slate-50"><td className="p-3 font-medium">{i.name}</td><td className="p-3"><Badge variant="outline">{i.category}</Badge></td><td className="p-3">{i.unit}</td>
                <td className={`p-3 text-right font-semibold ${stock <= reorder ? "text-red-600" : ""}`}>{stock} {stock <= reorder && <Badge className="ml-1 bg-red-100 text-red-700 text-[10px]">Low</Badge>}</td>
                <td className="p-3 text-right">{reorder}</td><td className="p-3 text-right">{Number(i.unitCost ?? i.unitcost ?? 0).toFixed(2)}</td></tr>)
            })}
              {items.length === 0 && <tr><td colSpan={6} className="p-8 text-center text-slate-400">No inventory items. Add your hotel supplies.</td></tr>}
            </tbody></table></CardContent></Card>
        )}
        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}><DialogContent><DialogHeader><DialogTitle>Add Supply Item</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div><Label>Name *</Label><Input value={form.name} onChange={(e) => setForm({...form, name: e.target.value})} placeholder="e.g. Bath Towels" /></div>
            <div className="grid grid-cols-2 gap-4"><div><Label>Category</Label><Select value={form.category} onValueChange={(v) => setForm({...form, category: v})}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent>{CATEGORIES.map(c => <SelectItem key={c} value={c}>{c}</SelectItem>)}</SelectContent></Select></div><div><Label>Unit</Label><Input value={form.unit} onChange={(e) => setForm({...form, unit: e.target.value})} placeholder="pcs, kg, litres" /></div></div>
            <div className="grid grid-cols-3 gap-4"><div><Label>Stock</Label><Input type="number" value={form.stockOnHand} onChange={(e) => setForm({...form, stockOnHand: Number(e.target.value)})} /></div><div><Label>Reorder Level</Label><Input type="number" value={form.reorderLevel} onChange={(e) => setForm({...form, reorderLevel: Number(e.target.value)})} /></div><div><Label>Unit Cost</Label><Input type="number" step="0.01" value={form.unitCost} onChange={(e) => setForm({...form, unitCost: Number(e.target.value)})} /></div></div>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setDialogOpen(false)}>Cancel</Button><Button onClick={handleSave} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}Add</Button></DialogFooter>
        </DialogContent></Dialog>
      </main></div></div>
  )
}
