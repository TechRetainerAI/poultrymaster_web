"use client"
import { useEffect, useRef, useState } from "react"
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
import { Loader2, ShoppingCart, Plus, Edit2, Trash2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listMenuItems, createMenuItem, updateMenuItem, deleteMenuItem, type HotelMenuItem } from "@/lib/api/hotel"
import { HotelOtherSelect, type HotelOtherSelectHandle } from "@/components/hotel/other-select"

// "Other" is NOT listed here: HotelOtherSelect appends its own "Other" row that
// opens a text box. Leaving it in would show the word twice.
const CATEGORIES = ["Breakfast", "Lunch", "Dinner", "Drinks", "Snacks", "Desserts", "Appetizers", "Sides", "Cocktails"]

export default function HotelMenuPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [items, setItems] = useState<HotelMenuItem[]>([]); const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false); const [editing, setEditing] = useState<any>(null); const [saving, setSaving] = useState(false)
  // Handle on the Category dropdown -- see handleSave.
  const categoryOther = useRef<HotelOtherSelectHandle>(null)
  const [form, setForm] = useState({ name: "", category: "Lunch", description: "", price: 0 })

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])
  async function load() { setLoading(true); try { setItems(await listMenuItems()) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setLoading(false) } }

  async function handleSave() {
    if (!form.name.trim()) { toast({ title: "Name required", variant: "destructive" }); return }
    setSaving(true)
    try {
      if (editing) { await updateMenuItem(editing.hotelMenuItemId ?? editing.hotelmenuitemid, form); toast({ title: "Updated" }) }
      else { await createMenuItem(form); toast({ title: "Menu item added" }) }
      // Before setDialogOpen(false): closing unmounts the field and nulls the ref.
      await categoryOther.current?.remember()
      setDialogOpen(false); await load()
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setSaving(false) }
  }

  async function handleDelete(item: any) {
    if (!confirm(`Delete ${item.name}?`)) return
    try { await deleteMenuItem(item.hotelMenuItemId ?? item.hotelmenuitemid); toast({ title: "Deleted" }); await load() }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  // Derived from the ITEMS, not from CATEGORIES: a category an operator typed
  // ("Grills") is not in the built-in array, and keying off that array would
  // silently drop every item filed under it.
  const grouped = Array.from(new Set(items.map((i: any) => i.category).filter(Boolean)))
    .map(c => ({ category: c as string, items: items.filter((i: any) => i.category === c) }))

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3"><ShoppingCart className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Menu Items</h1><span className="text-sm text-slate-500">({items.length})</span></div>
          <Button onClick={() => { setEditing(null); setForm({ name: "", category: "Lunch", description: "", price: 0 }); setDialogOpen(true) }} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> Add Item</Button>
        </div>
        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
          <Card><CardContent className="p-0"><div className="overflow-x-auto"><table className="w-full text-sm min-w-[550px]"><thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">Name</th><th className="text-left p-3">Category</th><th className="text-right p-3">Price</th><th className="text-left p-3">Available</th><th className="text-right p-3">Actions</th></tr></thead>
            <tbody>{items.map((i: any) => (<tr key={i.hotelMenuItemId ?? i.hotelmenuitemid} className="border-b hover:bg-slate-50"><td className="p-3 font-medium">{i.name}</td><td className="p-3"><Badge variant="outline">{i.category}</Badge></td><td className="p-3 text-right font-semibold">{Number(i.price).toFixed(2)}</td><td className="p-3">{(i.isAvailable ?? i.isavailable) ? <Badge className="bg-emerald-100 text-emerald-700">Yes</Badge> : <Badge className="bg-red-100 text-red-700">No</Badge>}</td>
              <td className="p-3 text-right space-x-1"><Button variant="ghost" size="icon" onClick={() => { setEditing(i); setForm({ name: i.name, category: i.category, description: i.description ?? "", price: Number(i.price) }); setDialogOpen(true) }}><Edit2 className="h-4 w-4" /></Button><Button variant="ghost" size="icon" className="text-red-600" onClick={() => handleDelete(i)}><Trash2 className="h-4 w-4" /></Button></td></tr>))}
              {items.length === 0 && <tr><td colSpan={5} className="p-8 text-center text-slate-400">No menu items. Add your restaurant menu.</td></tr>}
            </tbody></table></div></CardContent></Card>
        )}
        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}><DialogContent><DialogHeader><DialogTitle>{editing ? "Edit Item" : "Add Menu Item"}</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div><Label>Name *</Label><Input value={form.name} onChange={(e) => setForm({...form, name: e.target.value})} placeholder="e.g. Jollof Rice" /></div>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4"><div><Label>Category</Label><HotelOtherSelect ref={categoryOther} listKey="MenuCategory" baseOptions={CATEGORIES} value={form.category} onChange={(v) => setForm({...form, category: v ?? ""})} placeholder="Select category" otherLabel="Other (type category)" /></div><div><Label>Price</Label><Input type="number" step="0.01" value={form.price} onChange={(e) => setForm({...form, price: Number(e.target.value)})} /></div></div>
            <div><Label>Description</Label><Input value={form.description} onChange={(e) => setForm({...form, description: e.target.value})} /></div>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setDialogOpen(false)}>Cancel</Button><Button onClick={handleSave} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}{editing ? "Update" : "Add"}</Button></DialogFooter>
        </DialogContent></Dialog>
      </main></div></div>
  )
}
