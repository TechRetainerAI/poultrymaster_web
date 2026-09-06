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
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { Loader2, LayoutGrid, Plus } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { listRestaurantTables, createRestaurantTable, listHotelTableLocations, type HotelRestaurantTable, type HotelTableLocation } from "@/lib/api/hotel"

const STATUS_COLOR: Record<string, string> = { Available: "bg-emerald-100 text-emerald-700", Occupied: "bg-violet-100 text-violet-700", Reserved: "bg-blue-100 text-blue-700" }

export default function HotelTablesPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [items, setItems] = useState<HotelRestaurantTable[]>([]); const [locations, setLocations] = useState<HotelTableLocation[]>([])
  const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false); const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({ tableNumber: "", capacity: 4, location: "" })
  const [locSelection, setLocSelection] = useState("")
  const [customLoc, setCustomLoc] = useState("")

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])
  async function load() { setLoading(true); try { const [t, l] = await Promise.all([listRestaurantTables(), listHotelTableLocations().catch(() => [])]); setItems(t); setLocations(l) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setLoading(false) } }

  async function handleSave() {
    if (!form.tableNumber.trim()) { toast({ title: "Table number required", variant: "destructive" }); return }
    setSaving(true)
    try { await createRestaurantTable(form); toast({ title: "Table added" }); setDialogOpen(false); await load() }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setSaving(false) }
  }

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3"><LayoutGrid className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Restaurant Tables</h1></div>
          <Button onClick={() => { setForm({ tableNumber: "", capacity: 4, location: "" }); setLocSelection(""); setCustomLoc(""); setDialogOpen(true) }} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> Add Table</Button>
        </div>
        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-4">
            {items.map((t: any) => (
              <Card key={t.hotelRestaurantTableId ?? t.hotelrestauranttableid} className="text-center hover:shadow-md transition-shadow">
                <CardContent className="p-4">
                  <div className="text-2xl font-bold text-violet-700">{t.tableNumber ?? t.tablenumber}</div>
                  <div className="text-sm text-slate-500">{t.capacity} seats</div>
                  {(t.location) && <div className="text-xs text-slate-400">{t.location}</div>}
                  <Badge variant="outline" className={`mt-2 ${STATUS_COLOR[t.status] ?? ""}`}>{t.status}</Badge>
                </CardContent>
              </Card>
            ))}
            {items.length === 0 && <div className="col-span-full text-center py-12 text-slate-400">No tables. Add your restaurant tables.</div>}
          </div>
        )}
        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}><DialogContent><DialogHeader><DialogTitle>Add Table</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div><Label>Table Number *</Label><Input value={form.tableNumber} onChange={(e) => setForm({...form, tableNumber: e.target.value})} placeholder="e.g. T1, A1" /></div>
            <div className="grid grid-cols-2 gap-4">
              <div><Label>Capacity</Label><Input type="number" min={1} value={form.capacity} onChange={(e) => setForm({...form, capacity: Number(e.target.value)})} /></div>
              <div><Label>Location</Label>
                <Select value={locSelection || "__none__"} onValueChange={(v) => {
                  const sel = v === "__none__" ? "" : v
                  setLocSelection(sel)
                  if (sel !== "Other") { setCustomLoc(""); setForm({...form, location: sel}) }
                  else { setForm({...form, location: customLoc || ""}) }
                }}>
                  <SelectTrigger><SelectValue placeholder="Select location" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="__none__">None</SelectItem>
                    {locations.map(l => <SelectItem key={l.hotelTableLocationId} value={l.description}>{l.description}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
            </div>
            {locSelection === "Other" && (
              <div><Label>Specify Location</Label><Input value={customLoc} onChange={(e) => { setCustomLoc(e.target.value); setForm({...form, location: e.target.value}) }} placeholder="e.g. Beachfront, Balcony" /></div>
            )}
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setDialogOpen(false)}>Cancel</Button><Button onClick={handleSave} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}Add</Button></DialogFooter>
        </DialogContent></Dialog>
      </main></div></div>
  )
}
