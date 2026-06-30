"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Badge } from "@/components/ui/badge"
import { Plus, Loader2, CheckCircle2, XCircle, Eye } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  listPoultryDailyClosings, createPoultryDailyClosing, getPoultryDailyClosing, submitPoultryDailyClosing,
  approvePoultryDailyClosing, rejectPoultryDailyClosing, type PoultryDailyClosing,
} from "@/lib/api/poultry-inventory"

const STATUS_COLORS: Record<string, string> = { Draft: "bg-slate-100 text-slate-700", Submitted: "bg-blue-100 text-blue-700", Approved: "bg-green-100 text-green-700", Rejected: "bg-red-100 text-red-700" }

export default function PoultryDailyClosingPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const gh = useFmt()
  const [rows, setRows] = useState<PoultryDailyClosing[]>([])
  const [loading, setLoading] = useState(true)
  const [newOpen, setNewOpen] = useState(false)
  const [newDate, setNewDate] = useState(new Date().toISOString().split("T")[0])
  const [view, setView] = useState<PoultryDailyClosing | null>(null)
  const [actualCash, setActualCash] = useState(0)
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try { setRows(await listPoultryDailyClosings()) }
    catch (e: any) { toast({ title: "Could not load closings", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  async function createNew() {
    setBusy(true)
    try { await createPoultryDailyClosing({ closingDate: newDate }); toast({ title: "Draft closing created" }); setNewOpen(false); await load() }
    catch (e: any) { toast({ title: "Could not create", description: e?.message, variant: "destructive" }) }
    finally { setBusy(false) }
  }
  async function openView(id: number) {
    try { const c = await getPoultryDailyClosing(id); setView(c); setActualCash(c.actualCashCounted || 0) }
    catch (e: any) { toast({ title: "Could not load", description: e?.message, variant: "destructive" }) }
  }
  async function submit() {
    if (!view) return; setBusy(true)
    try { await submitPoultryDailyClosing(view.poultryDailyClosingId, { actualCashCounted: actualCash }); toast({ title: "Submitted" }); setView(null); await load() }
    catch (e: any) { toast({ title: "Submit failed", description: e?.message, variant: "destructive" }) }
    finally { setBusy(false) }
  }
  async function approve(id: number) { try { await approvePoultryDailyClosing(id); toast({ title: "Approved" }); setView(null); await load() } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }
  async function reject(id: number) { try { await rejectPoultryDailyClosing(id, "Rejected"); toast({ title: "Rejected" }); setView(null); await load() } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }

  return (
    <div className="flex min-h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 p-4 sm:p-6 space-y-4">
          <div className="flex items-center justify-between">
            <div><h1 className="text-2xl font-bold">Daily Closing</h1><p className="text-sm text-slate-500">End-of-day production, loss and stock snapshot.</p></div>
            <Button onClick={() => setNewOpen(true)}><Plus className="w-4 h-4 mr-1" /> New closing</Button>
          </div>
          <Card><CardContent className="p-4">
            {loading ? <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div> : (
              <Table>
                <TableHeader><TableRow><TableHead>Date</TableHead><TableHead className="text-right">Produced</TableHead><TableHead className="text-right">Damaged</TableHead><TableHead className="text-right">Prod. cost</TableHead><TableHead className="text-right">Closing stock</TableHead><TableHead>Status</TableHead><TableHead className="text-right">Actions</TableHead></TableRow></TableHeader>
                <TableBody>
                  {rows.length === 0 ? <TableRow><TableCell colSpan={7} className="text-center text-slate-500 py-6">No closings yet.</TableCell></TableRow>
                    : rows.map((c) => (
                      <TableRow key={c.poultryDailyClosingId}>
                        <TableCell className="font-medium">{(c.closingDate || "").split("T")[0]}</TableCell>
                        <TableCell className="text-right">{c.quantityProduced.toLocaleString()}</TableCell>
                        <TableCell className="text-right">{c.quantityDamaged.toLocaleString()}</TableCell>
                        <TableCell className="text-right">{gh(c.totalProductionCost)}</TableCell>
                        <TableCell className="text-right">{c.closingStock.toLocaleString()}</TableCell>
                        <TableCell><Badge className={STATUS_COLORS[c.status] ?? "bg-gray-100"}>{c.status}</Badge></TableCell>
                        <TableCell className="text-right"><Button variant="ghost" size="sm" onClick={() => openView(c.poultryDailyClosingId)}><Eye className="w-4 h-4" /></Button></TableCell>
                      </TableRow>
                    ))}
                </TableBody>
              </Table>
            )}
          </CardContent></Card>
        </main>
      </div>

      <Dialog open={newOpen} onOpenChange={setNewOpen}>
        <DialogContent className="max-w-sm">
          <DialogHeader><DialogTitle>New daily closing</DialogTitle></DialogHeader>
          <FormSection title="Date" color="blue"><FormField label="Closing date"><Input type="date" value={newDate} onChange={(e) => setNewDate(e.target.value)} /></FormField></FormSection>
          <div className="flex justify-end gap-2"><Button variant="outline" onClick={() => setNewOpen(false)}>Cancel</Button><Button onClick={createNew} disabled={busy}>{busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Create"}</Button></div>
        </DialogContent>
      </Dialog>

      <Dialog open={!!view} onOpenChange={(o) => !o && setView(null)}>
        <DialogContent className="max-w-lg">
          <DialogHeader><DialogTitle>Closing — {(view?.closingDate || "").split("T")[0]}</DialogTitle></DialogHeader>
          {view && (
            <>
              <FormSection title="Computed figures" color="indigo">
                <FormField label="Produced (good)"><Input readOnly tabIndex={-1} className="bg-slate-100 pointer-events-none" value={view.quantityProduced.toLocaleString()} /></FormField>
                <FormField label="Damaged"><Input readOnly tabIndex={-1} className="bg-slate-100 pointer-events-none" value={view.quantityDamaged.toLocaleString()} /></FormField>
                <FormField label="Production cost"><Input readOnly tabIndex={-1} className="bg-slate-100 pointer-events-none" value={gh(view.totalProductionCost)} /></FormField>
                <FormField label="Closing stock"><Input readOnly tabIndex={-1} className="bg-slate-100 pointer-events-none" value={view.closingStock.toLocaleString()} /></FormField>
              </FormSection>
              {view.status === "Draft" && (
                <FormSection title="Submit" color="emerald">
                  <FormField label="Actual cash counted"><NumberInput min={0} step="0.01" value={actualCash} onChange={(e) => setActualCash(Number(e.target.value) || 0)} /></FormField>
                </FormSection>
              )}
              <div className="flex justify-end gap-2">
                {view.status === "Draft" && <Button onClick={submit} disabled={busy}>{busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Submit"}</Button>}
                {view.status === "Submitted" && <>
                  <Button variant="outline" onClick={() => reject(view.poultryDailyClosingId)}><XCircle className="w-4 h-4 mr-1" /> Reject</Button>
                  <Button onClick={() => approve(view.poultryDailyClosingId)}><CheckCircle2 className="w-4 h-4 mr-1" /> Approve</Button>
                </>}
                <Button variant="outline" onClick={() => setView(null)}>Close</Button>
              </div>
            </>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}
