"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Loader2, ScrollText, Plus, CheckCircle2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listShiftHandovers, createShiftHandover, acknowledgeShiftHandover } from "@/lib/api/hotel"

const SHIFT_TYPES = ["Morning", "Afternoon", "Night"]
const STATUS_COLORS: Record<string, string> = { Draft: "bg-slate-100 text-slate-700", Submitted: "bg-blue-100 text-blue-700", Acknowledged: "bg-emerald-100 text-emerald-700" }

export default function HotelShiftHandoverPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const username = useAuthStore((s) => s.username) ?? ""
  const [items, setItems] = useState<any[]>([]); const [loading, setLoading] = useState(true)
  const [open, setOpen] = useState(false); const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({ shiftDate: new Date().toISOString().slice(0, 10), shiftType: "Night", handoverBy: "", keyMessages: "", pendingItems: "", vipGuests: "", incidents: "", cashBalance: 0 })
  const [ackTarget, setAckTarget] = useState<any>(null)

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])
  async function load() { setLoading(true); try { setItems(await listShiftHandovers()) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setLoading(false) } }

  async function handleSave() {
    if (!form.handoverBy.trim()) { toast({ title: "Handover by is required", variant: "destructive" }); return }
    setSaving(true)
    try { await createShiftHandover({ ...form, cashBalance: form.cashBalance || undefined }); toast({ title: "Shift handover submitted" }); setOpen(false); await load() }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setSaving(false) }
  }

  async function handleAcknowledge() {
    if (!ackTarget) return
    try { await acknowledgeShiftHandover(ackTarget.hotelshifthandoverid, username || "Staff"); toast({ title: "Handover acknowledged" }); setAckTarget(null); await load() }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center justify-between mb-6"><div className="flex items-center gap-3"><ScrollText className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Shift Handover</h1></div>
          <Button onClick={() => { setForm({ shiftDate: new Date().toISOString().slice(0, 10), shiftType: "Night", handoverBy: username, keyMessages: "", pendingItems: "", vipGuests: "", incidents: "", cashBalance: 0 }); setOpen(true) }} className="bg-violet-600 hover:bg-violet-700"><Plus className="h-4 w-4 mr-1" /> New Handover</Button></div>

        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
          <div className="space-y-4">
            {items.map((h: any, i: number) => (
              <Card key={h.hotelshifthandoverid ?? i} className={`border-l-4 ${h.status === "Acknowledged" ? "border-l-emerald-500" : "border-l-blue-500"}`}>
                <CardContent className="p-4">
                  <div className="flex items-center justify-between mb-3">
                    <div className="flex items-center gap-3">
                      <div>
                        <span className="font-bold text-lg">{(h.shiftdate ?? "").slice(0, 10)}</span>
                        <Badge variant="outline" className="ml-2">{h.shifttype} Shift</Badge>
                        <Badge className={`ml-2 ${STATUS_COLORS[h.status] ?? ""}`}>{h.status}</Badge>
                      </div>
                    </div>
                    <div className="text-sm text-slate-500">
                      By: <strong>{h.handoverby}</strong>
                      {h.receivedby && <span> → <strong>{h.receivedby}</strong></span>}
                    </div>
                  </div>
                  <div className="grid md:grid-cols-2 gap-4 text-sm">
                    {h.keymessages && <div><div className="text-xs font-semibold text-slate-400 mb-1">Key Messages</div><div className="bg-slate-50 p-2 rounded whitespace-pre-wrap">{h.keymessages}</div></div>}
                    {h.pendingitems && <div><div className="text-xs font-semibold text-slate-400 mb-1">Pending Items</div><div className="bg-amber-50 p-2 rounded whitespace-pre-wrap">{h.pendingitems}</div></div>}
                    {h.vipguests && <div><div className="text-xs font-semibold text-slate-400 mb-1">VIP Guests</div><div className="bg-violet-50 p-2 rounded whitespace-pre-wrap">{h.vipguests}</div></div>}
                    {h.incidents && <div><div className="text-xs font-semibold text-slate-400 mb-1">Incidents</div><div className="bg-red-50 p-2 rounded whitespace-pre-wrap">{h.incidents}</div></div>}
                  </div>
                  {h.cashbalance != null && <div className="mt-3 text-sm">Cash Balance: <strong className="text-violet-700">{Number(h.cashbalance).toFixed(2)}</strong></div>}
                  {h.status === "Submitted" && (
                    <div className="mt-3"><Button size="sm" onClick={() => setAckTarget(h)} className="bg-emerald-600 hover:bg-emerald-700"><CheckCircle2 className="h-4 w-4 mr-1" /> Acknowledge</Button></div>
                  )}
                  {h.acknowledgedat && <div className="mt-2 text-xs text-slate-400">Acknowledged at {new Date(h.acknowledgedat).toLocaleString()}</div>}
                </CardContent>
              </Card>
            ))}
            {items.length === 0 && <div className="text-center py-12 text-slate-400">No shift handovers yet. Create one to pass notes to the next shift.</div>}
          </div>
        )}

        <Dialog open={open} onOpenChange={setOpen}><DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto"><DialogHeader><DialogTitle>New Shift Handover</DialogTitle><DialogDescription>Pass notes and pending items to the incoming shift</DialogDescription></DialogHeader>
          <div className="space-y-4">
            <FormSection title="Shift Info" color="indigo">
              <FormField label="Date"><Input type="date" value={form.shiftDate} onChange={(e) => setForm({ ...form, shiftDate: e.target.value })} /></FormField>
              <FormField label="Shift"><Select value={form.shiftType} onValueChange={(v) => setForm({ ...form, shiftType: v })}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent>{SHIFT_TYPES.map(s => <SelectItem key={s} value={s}>{s}</SelectItem>)}</SelectContent></Select></FormField>
            </FormSection>
            <FormSection title="Handover Details" color="amber" columns={1}>
              <FormField label="Handover By *"><Input value={form.handoverBy} onChange={(e) => setForm({ ...form, handoverBy: e.target.value })} placeholder="Your name" /></FormField>
              <FormField label="Key Messages"><Textarea value={form.keyMessages} onChange={(e) => setForm({ ...form, keyMessages: e.target.value })} placeholder="Important things the next shift needs to know" rows={3} /></FormField>
              <FormField label="Pending Items"><Textarea value={form.pendingItems} onChange={(e) => setForm({ ...form, pendingItems: e.target.value })} placeholder="Tasks not completed that need follow-up" rows={2} /></FormField>
              <FormField label="VIP Guests"><Textarea value={form.vipGuests} onChange={(e) => setForm({ ...form, vipGuests: e.target.value })} placeholder="VIP arrivals/departures, special treatment" rows={2} /></FormField>
              <FormField label="Incidents"><Textarea value={form.incidents} onChange={(e) => setForm({ ...form, incidents: e.target.value })} placeholder="Any incidents or issues" rows={2} /></FormField>
            </FormSection>
            <FormSection title="Cash" color="green" columns={1}>
              <FormField label="Cash Balance"><Input type="number" step="0.01" value={form.cashBalance || ""} onChange={(e) => setForm({ ...form, cashBalance: Number(e.target.value) || 0 })} placeholder="Cash on hand at end of shift" /></FormField>
            </FormSection>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button><Button onClick={handleSave} disabled={saving} className="bg-violet-600 hover:bg-violet-700">{saving && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}Submit Handover</Button></DialogFooter>
        </DialogContent></Dialog>

        <Dialog open={!!ackTarget} onOpenChange={(v) => { if (!v) setAckTarget(null) }}><DialogContent><DialogHeader><DialogTitle>Acknowledge Handover</DialogTitle></DialogHeader>
          <p className="text-sm text-slate-600">You are acknowledging receipt of the {ackTarget?.shifttype} shift handover from <strong>{ackTarget?.handoverby}</strong> on {(ackTarget?.shiftdate ?? "").slice(0, 10)}.</p>
          <DialogFooter><Button variant="outline" onClick={() => setAckTarget(null)}>Cancel</Button><Button onClick={handleAcknowledge} className="bg-emerald-600 hover:bg-emerald-700"><CheckCircle2 className="h-4 w-4 mr-1" />Acknowledge</Button></DialogFooter></DialogContent></Dialog>
      </main></div></div>
  )
}
