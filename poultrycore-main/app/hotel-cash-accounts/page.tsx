"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { Loader2, Wallet, Plus } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listHotelCashAccounts, createHotelCashAccount, type HotelCashAccount } from "@/lib/api/hotel"

export default function HotelCashAccountsPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [items, setItems] = useState<HotelCashAccount[]>([]); const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false); const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({ accountName: "", accountType: "Cash", openingBalance: 0 })

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])
  async function load() { setLoading(true); try { setItems(await listHotelCashAccounts()) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setLoading(false) } }

  async function handleSave() {
    if (!form.accountName.trim()) { toast({ title: "Name required", variant: "destructive" }); return }
    setSaving(true)
    try { await createHotelCashAccount(form); toast({ title: "Account created" }); setDialogOpen(false); await load() }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setSaving(false) }
  }

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3"><Wallet className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Cash Accounts</h1></div>
          <Button onClick={() => { setForm({ accountName: "", accountType: "Cash", openingBalance: 0 }); setDialogOpen(true) }} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> Add Account</Button>
        </div>
        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {items.map((a: any) => (
              <Card key={a.hotelCashAccountId ?? a.hotelcashaccountid}>
                <CardContent className="p-4 space-y-2">
                  <div className="font-semibold text-lg">{a.accountName ?? a.accountname}</div>
                  <div className="text-sm text-slate-500">{a.accountType ?? a.accounttype}</div>
                  <div className="text-2xl font-bold text-violet-700">{Number(a.currentBalance ?? a.currentbalance ?? 0).toFixed(2)}</div>
                  <div className="text-xs text-slate-400">Opening: {Number(a.openingBalance ?? a.openingbalance ?? 0).toFixed(2)}</div>
                </CardContent>
              </Card>
            ))}
            {items.length === 0 && <div className="col-span-full text-center py-12 text-slate-400">No cash accounts. Add one to track your hotel finances.</div>}
          </div>
        )}
        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}><DialogContent><DialogHeader><DialogTitle>Add Cash Account</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div><Label>Account Name *</Label><Input value={form.accountName} onChange={(e) => setForm({...form, accountName: e.target.value})} placeholder="e.g. Front Desk Cash" /></div>
            <div><Label>Type</Label><Select value={form.accountType} onValueChange={(v) => setForm({...form, accountType: v})}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent><SelectItem value="Cash">Cash</SelectItem><SelectItem value="Bank">Bank</SelectItem><SelectItem value="MobileMoney">Mobile Money</SelectItem></SelectContent></Select></div>
            <div><Label>Opening Balance</Label><Input type="number" step="0.01" value={form.openingBalance} onChange={(e) => setForm({...form, openingBalance: Number(e.target.value)})} /></div>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setDialogOpen(false)}>Cancel</Button><Button onClick={handleSave} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}Create</Button></DialogFooter>
        </DialogContent></Dialog>
      </main></div></div>
  )
}
