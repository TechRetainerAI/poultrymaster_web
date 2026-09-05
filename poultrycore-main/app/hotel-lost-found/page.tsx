"use client"
import { useEffect, useState, useMemo } from "react"
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
import { Loader2, Package, Plus, Search } from "lucide-react"
import { PaginationControls } from "@/components/ui/pagination-controls"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listLostFound, createLostFound, updateLostFoundStatus, listHotelRooms, type HotelRoom } from "@/lib/api/hotel"

const CATEGORIES = ["Electronics", "Clothing", "Documents", "Jewelry", "Personal", "Other"]
const STATUS_COLORS: Record<string, string> = { Found: "bg-amber-100 text-amber-700", Claimed: "bg-emerald-100 text-emerald-700", Stored: "bg-blue-100 text-blue-700", Disposed: "bg-slate-100 text-slate-700" }

export default function HotelLostFoundPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [items, setItems] = useState<any[]>([]); const [rooms, setRooms] = useState<HotelRoom[]>([])
  const [loading, setLoading] = useState(true); const [statusFilter, setStatusFilter] = useState("ALL")
  const [search, setSearch] = useState(""); const [page, setPage] = useState(1); const pageSize = 10
  const [open, setOpen] = useState(false); const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({ hotelRoomId: null as number | null, itemDescription: "", foundDate: new Date().toISOString().slice(0, 10), foundBy: "", foundLocation: "", category: "Other", storageLocation: "", notes: "" })
  const [claimOpen, setClaimOpen] = useState(false); const [claimTarget, setClaimTarget] = useState<any>(null); const [claimedBy, setClaimedBy] = useState("")

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])
  async function load() { setLoading(true); try { const [lf, rm] = await Promise.all([listLostFound(), listHotelRooms()]); setItems(lf); setRooms(rm) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setLoading(false) } }

  async function handleSave() { if (!form.itemDescription.trim()) { toast({ title: "Item description required", variant: "destructive" }); return }; setSaving(true); try { await createLostFound(form); toast({ title: "Item logged" }); setOpen(false); await load() } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setSaving(false) } }
  async function doStatus(id: number, status: string, cb?: string) { try { await updateLostFoundStatus(id, status, cb); toast({ title: `Item marked as ${status}` }); setClaimOpen(false); await load() } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }

  const filtered = useMemo(() => items.filter((r: any) => {
    if (statusFilter !== "ALL" && (r.status ?? "") !== statusFilter) return false
    if (search) { const q = search.toLowerCase(); if (!`${r.itemdescription ?? ""} ${r.roomnumber ?? ""} ${r.foundby ?? ""} ${r.foundlocation ?? ""} ${r.category ?? ""}`.toLowerCase().includes(q)) return false }
    return true
  }), [items, statusFilter, search])
  const paged = filtered.slice((page - 1) * pageSize, page * pageSize)

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center justify-between mb-4"><div className="flex items-center gap-3"><Package className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Lost & Found</h1></div>
          <Button onClick={() => { setForm({ hotelRoomId: null, itemDescription: "", foundDate: new Date().toISOString().slice(0, 10), foundBy: "", foundLocation: "", category: "Other", storageLocation: "", notes: "" }); setOpen(true) }} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> Log Item</Button></div>
        <div className="flex gap-2 flex-wrap mb-3">{[{ s: "ALL", l: "All" }, { s: "Found", l: "Found" }, { s: "Claimed", l: "Claimed" }, { s: "Stored", l: "Stored" }, { s: "Disposed", l: "Disposed" }].map(f => <Button key={f.s} variant={statusFilter === f.s ? "default" : "outline"} size="sm" onClick={() => { setStatusFilter(f.s); setPage(1) }} className={statusFilter === f.s ? "bg-violet-600" : ""}>{f.l}</Button>)}</div>
        <div className="mb-4 relative max-w-sm"><Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" /><Input placeholder="Search item, room, location..." className="pl-9" value={search} onChange={(e) => { setSearch(e.target.value); setPage(1) }} /></div>
        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
          <Card><CardContent className="p-0"><table className="w-full text-sm"><thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">Date</th><th className="text-left p-3">Room</th><th className="text-left p-3">Item</th><th className="text-left p-3">Category</th><th className="text-left p-3">Found By</th><th className="text-left p-3">Location</th><th className="text-left p-3">Storage</th><th className="text-left p-3">Status</th><th className="text-right p-3">Actions</th></tr></thead>
            <tbody>{paged.map((r: any, i: number) => (<tr key={r.hotellostandfoundid ?? i} className="border-b hover:bg-slate-50"><td className="p-3 text-xs">{(r.founddate ?? "").slice(0, 10)}</td><td className="p-3">{r.roomnumber ?? "—"}</td><td className="p-3 font-medium max-w-[200px] truncate">{r.itemdescription}</td><td className="p-3"><Badge variant="outline">{r.category}</Badge></td><td className="p-3">{r.foundby ?? "—"}</td><td className="p-3">{r.foundlocation ?? "—"}</td><td className="p-3">{r.storagelocation ?? "—"}</td><td className="p-3"><Badge className={STATUS_COLORS[r.status] ?? ""}>{r.status}</Badge></td>
              <td className="p-3 text-right whitespace-nowrap">{r.status === "Found" && <><Button size="sm" variant="ghost" onClick={() => { setClaimTarget(r); setClaimedBy(""); setClaimOpen(true) }}>Claim</Button><Button size="sm" variant="ghost" onClick={() => doStatus(r.hotellostandfoundid, "Stored")}>Store</Button></>}{r.status === "Stored" && <><Button size="sm" variant="ghost" onClick={() => { setClaimTarget(r); setClaimedBy(""); setClaimOpen(true) }}>Claim</Button><Button size="sm" variant="ghost" onClick={() => doStatus(r.hotellostandfoundid, "Disposed")}>Dispose</Button></>}</td></tr>))}
              {filtered.length === 0 && <tr><td colSpan={9} className="p-8 text-center text-slate-400">No items found.</td></tr>}</tbody></table>
            <PaginationControls page={page} pageSize={pageSize} total={filtered.length} onPageChange={setPage} /></CardContent></Card>)}

        <Dialog open={open} onOpenChange={setOpen}><DialogContent><DialogHeader><DialogTitle>Log Lost Item</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <div><Label>Item Description *</Label><Input value={form.itemDescription} onChange={(e) => setForm({ ...form, itemDescription: e.target.value })} /></div>
            <div className="grid grid-cols-2 gap-3"><div><Label>Room</Label><Select value={form.hotelRoomId ? String(form.hotelRoomId) : "__none__"} onValueChange={(v) => setForm({ ...form, hotelRoomId: v === "__none__" ? null : Number(v) })}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent><SelectItem value="__none__">None</SelectItem>{rooms.map((r: any) => <SelectItem key={r.hotelRoomId} value={String(r.hotelRoomId)}>Room {r.roomNumber}</SelectItem>)}</SelectContent></Select></div>
              <div><Label>Category</Label><Select value={form.category} onValueChange={(v) => setForm({ ...form, category: v })}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent>{CATEGORIES.map(c => <SelectItem key={c} value={c}>{c}</SelectItem>)}</SelectContent></Select></div></div>
            <div className="grid grid-cols-2 gap-3"><div><Label>Found Date</Label><Input type="date" value={form.foundDate} onChange={(e) => setForm({ ...form, foundDate: e.target.value })} /></div><div><Label>Found By</Label><Input value={form.foundBy} onChange={(e) => setForm({ ...form, foundBy: e.target.value })} /></div></div>
            <div className="grid grid-cols-2 gap-3"><div><Label>Found Location</Label><Input value={form.foundLocation} onChange={(e) => setForm({ ...form, foundLocation: e.target.value })} placeholder="e.g. Room 201 bathroom" /></div><div><Label>Storage Location</Label><Input value={form.storageLocation} onChange={(e) => setForm({ ...form, storageLocation: e.target.value })} placeholder="e.g. Front desk drawer 3" /></div></div>
          </div><DialogFooter><Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button><Button onClick={handleSave} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}Log Item</Button></DialogFooter></DialogContent></Dialog>

        <Dialog open={claimOpen} onOpenChange={setClaimOpen}><DialogContent><DialogHeader><DialogTitle>Mark Item as Claimed</DialogTitle></DialogHeader>
          <div className="space-y-3"><p className="text-sm text-slate-600">Item: <strong>{claimTarget?.itemdescription}</strong></p><div><Label>Claimed By *</Label><Input value={claimedBy} onChange={(e) => setClaimedBy(e.target.value)} placeholder="Guest/person name" /></div></div>
          <DialogFooter><Button variant="outline" onClick={() => setClaimOpen(false)}>Cancel</Button><Button onClick={() => { if (!claimedBy.trim()) { toast({ title: "Enter name", variant: "destructive" }); return }; doStatus(claimTarget?.hotellostandfoundid, "Claimed", claimedBy) }} className="bg-emerald-600 hover:bg-emerald-700">Confirm Claimed</Button></DialogFooter></DialogContent></Dialog>
      </main></div></div>
  )
}
