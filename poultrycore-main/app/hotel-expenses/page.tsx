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
import { Loader2, Wallet, Plus } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listHotelExpenses, createHotelExpense, type HotelExpense } from "@/lib/api/hotel"

const CATEGORIES = ["Utilities", "Repairs", "Supplies", "Salaries", "Food & Beverage", "Marketing", "Insurance", "Rent", "Transport", "Other"]

export default function HotelExpensesPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [items, setItems] = useState<HotelExpense[]>([]); const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false); const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({ category: "Utilities", description: "", amount: 0, expenseDate: new Date().toISOString().slice(0,10), vendor: "", notes: "" })

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])
  async function load() { setLoading(true); try { setItems(await listHotelExpenses()) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setLoading(false) } }

  async function handleSave() {
    if (!form.description.trim()) { toast({ title: "Description required", variant: "destructive" }); return }
    setSaving(true)
    try { await createHotelExpense(form); toast({ title: "Expense added" }); setDialogOpen(false); await load() }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setSaving(false) }
  }

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3"><Wallet className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Expenses</h1><span className="text-sm text-slate-500">({items.length})</span></div>
          <Button onClick={() => { setForm({ category: "Utilities", description: "", amount: 0, expenseDate: new Date().toISOString().slice(0,10), vendor: "", notes: "" }); setDialogOpen(true) }} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> Add Expense</Button>
        </div>
        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
          <Card><CardContent className="p-0"><table className="w-full text-sm"><thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">Date</th><th className="text-left p-3">Category</th><th className="text-left p-3">Description</th><th className="text-left p-3">Vendor</th><th className="text-right p-3">Amount</th><th className="text-left p-3">Status</th></tr></thead>
            <tbody>{items.map((e: any) => (<tr key={e.hotelExpenseId ?? e.hotelexpenseid} className="border-b hover:bg-slate-50"><td className="p-3">{(e.expenseDate ?? e.expensedate)?.slice?.(0,10) ?? "-"}</td><td className="p-3">{e.category}</td><td className="p-3">{e.description}</td><td className="p-3">{e.vendor ?? "-"}</td><td className="p-3 text-right font-semibold">{Number(e.amount).toFixed(2)}</td><td className="p-3"><Badge variant="outline">{e.status ?? "Draft"}</Badge></td></tr>))}
              {items.length === 0 && <tr><td colSpan={6} className="p-8 text-center text-slate-400">No expenses recorded yet.</td></tr>}
            </tbody></table></CardContent></Card>
        )}
        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}><DialogContent><DialogHeader><DialogTitle>Add Expense</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div><Label>Category</Label><Select value={form.category} onValueChange={(v) => setForm({...form, category: v})}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent>{CATEGORIES.map(c => <SelectItem key={c} value={c}>{c}</SelectItem>)}</SelectContent></Select></div>
            <div><Label>Description *</Label><Input value={form.description} onChange={(e) => setForm({...form, description: e.target.value})} /></div>
            <div className="grid grid-cols-2 gap-4"><div><Label>Amount</Label><Input type="number" step="0.01" value={form.amount} onChange={(e) => setForm({...form, amount: Number(e.target.value)})} /></div><div><Label>Date</Label><Input type="date" value={form.expenseDate} onChange={(e) => setForm({...form, expenseDate: e.target.value})} /></div></div>
            <div><Label>Vendor</Label><Input value={form.vendor} onChange={(e) => setForm({...form, vendor: e.target.value})} /></div>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setDialogOpen(false)}>Cancel</Button><Button onClick={handleSave} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}Add</Button></DialogFooter>
        </DialogContent></Dialog>
      </main></div></div>
  )
}
