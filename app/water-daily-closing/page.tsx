"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Badge } from "@/components/ui/badge"
import { Plus, Loader2, FileText, AlertCircle, CheckCircle2, XCircle, Eye } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterDailyClosings, getWaterDailyClosing, createWaterDailyClosing,
  submitWaterDailyClosing, approveWaterDailyClosing, rejectWaterDailyClosing,
  type WaterDailyClosing,
} from "@/lib/api/water"

function gh(n: number | null | undefined) {
  const v = n ?? 0
  return `GHC ${v.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}

const STATUS_COLORS: Record<string, string> = {
  Draft: "bg-slate-100 text-slate-700",
  Submitted: "bg-blue-100 text-blue-700",
  Approved: "bg-green-100 text-green-700",
  Rejected: "bg-rose-100 text-rose-700",
}

export default function WaterDailyClosingPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [closings, setClosings] = useState<WaterDailyClosing[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const [newDlg, setNewDlg] = useState(false)
  const [newDate, setNewDate] = useState(new Date().toISOString().split("T")[0])

  const [view, setView] = useState<WaterDailyClosing | null>(null)
  const [submitForm, setSubmitForm] = useState({ actualCashCounted: 0, managerNotes: "" })

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true); setError(null)
    try { setClosings(await listWaterDailyClosings()) }
    catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setLoading(false) }
  }

  async function createNew() {
    if (!newDate) return toast({ title: "Pick a closing date", variant: "destructive" })
    try {
      const c = await createWaterDailyClosing({ closingDate: newDate })
      toast({ title: "Closing draft created", description: "Submit it with actual cash counted." })
      setNewDlg(false)
      // Auto-open the view so the user can fill in the count + submit
      if (c) {
        const full = await getWaterDailyClosing(c.waterDailyClosingId)
        setView(full)
        setSubmitForm({ actualCashCounted: 0, managerNotes: "" })
      }
      await load()
    } catch (e: any) { toast({ title: "Create failed", description: e?.message, variant: "destructive" }) }
  }

  async function openView(c: WaterDailyClosing) {
    try {
      const full = await getWaterDailyClosing(c.waterDailyClosingId)
      setView(full); setSubmitForm({ actualCashCounted: 0, managerNotes: full.managerNotes ?? "" })
    } catch (e: any) { toast({ title: "Load failed", description: e?.message, variant: "destructive" }) }
  }

  async function submitClosing() {
    if (!view) return
    try {
      const updated = await submitWaterDailyClosing(view.waterDailyClosingId, submitForm)
      setView(updated); await load()
      toast({ title: "Closing submitted", description: "Waiting for owner approval." })
    } catch (e: any) { toast({ title: "Submit failed", description: e?.message, variant: "destructive" }) }
  }

  async function approve(id: number) {
    try { await approveWaterDailyClosing(id); toast({ title: "Closing approved + locked" }); setView(null); await load() }
    catch (e: any) { toast({ title: "Approve failed", description: e?.message, variant: "destructive" }) }
  }

  async function reject(id: number) {
    const reason = window.prompt("Rejection reason?")
    if (!reason) return
    try { await rejectWaterDailyClosing(id, reason); toast({ title: "Closing rejected" }); setView(null); await load() }
    catch (e: any) { toast({ title: "Reject failed", description: e?.message, variant: "destructive" }) }
  }

  const todayClosing = closings.find(c => c.closingDate?.startsWith(new Date().toISOString().slice(0, 10)))

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <FileText className="h-6 w-6 text-sky-600" /> Daily closing
            </h1>
            <Button onClick={() => { setNewDate(new Date().toISOString().split("T")[0]); setNewDlg(true) }}>
              <Plus className="h-4 w-4 mr-1" /> Start today's closing
            </Button>
          </div>

          {todayClosing && (
            <Card className={`mb-4 ${todayClosing.status === "Approved" ? "border-green-200 bg-green-50" : "border-amber-200 bg-amber-50"}`}>
              <CardContent className="p-3 flex items-center justify-between gap-2">
                <div className="text-sm">
                  Today's closing exists — status: <Badge className={STATUS_COLORS[todayClosing.status]}>{todayClosing.status}</Badge>
                </div>
                <Button size="sm" variant="outline" onClick={() => openView(todayClosing)}>Open</Button>
              </CardContent>
            </Card>
          )}

          {error && (
            <Card className="border-red-200 bg-red-50 mb-4">
              <CardContent className="flex items-center gap-2 p-3 text-red-700"><AlertCircle className="h-4 w-4" /> {error}</CardContent>
            </Card>
          )}

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : closings.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No daily closings yet. Start today's above.</div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Date</TableHead>
                      <TableHead className="text-right">Bags produced</TableHead>
                      <TableHead className="text-right">Bags sold</TableHead>
                      <TableHead className="text-right">Income</TableHead>
                      <TableHead className="text-right">Expenses</TableHead>
                      <TableHead className="text-right">Cash at hand</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead className="text-right">Actions</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {closings.map((c) => (
                      <TableRow key={c.waterDailyClosingId}>
                        <TableCell className="font-medium">{c.closingDate.split("T")[0]}</TableCell>
                        <TableCell className="text-right tabular-nums">{c.bagsProduced ?? 0}</TableCell>
                        <TableCell className="text-right tabular-nums">{c.bagsSold ?? 0}</TableCell>
                        <TableCell className="text-right tabular-nums">{gh(c.totalIncome)}</TableCell>
                        <TableCell className="text-right tabular-nums">{gh(c.totalExpenses)}</TableCell>
                        <TableCell className="text-right tabular-nums">{gh(c.cashAtHand)}</TableCell>
                        <TableCell><Badge className={STATUS_COLORS[c.status] ?? ""}>{c.status}</Badge></TableCell>
                        <TableCell className="text-right">
                          <Button size="sm" variant="ghost" onClick={() => openView(c)}><Eye className="h-4 w-4" /></Button>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>
        </main>
      </div>

      {/* New closing */}
      <Dialog open={newDlg} onOpenChange={setNewDlg}>
        <DialogContent>
          <DialogHeader><DialogTitle>Start daily closing</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <p className="text-sm text-slate-600">
              Creates a draft pulling today's production, sales, expenses, cash, and driver returns.
              You'll be asked to count the actual cash + submit it for owner approval.
            </p>
            <div><Label>Closing date</Label>
              <Input type="date" value={newDate} onChange={(e) => setNewDate(e.target.value)} /></div>
          </div>
          <div className="flex justify-end gap-2 pt-3">
            <Button variant="ghost" onClick={() => setNewDlg(false)}>Cancel</Button>
            <Button onClick={createNew}>Create draft</Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* View / submit / approve */}
      <Dialog open={!!view} onOpenChange={(v) => { if (!v) setView(null) }}>
        <DialogContent className="max-w-3xl">
          <DialogHeader>
            <DialogTitle>
              {view && (<>Closing: {view.closingDate.split("T")[0]} <Badge className={STATUS_COLORS[view.status]}>{view.status}</Badge></>)}
            </DialogTitle>
          </DialogHeader>
          {view && (
            <div className="space-y-3">
              <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
                <Tile label="Bags produced" value={String(view.bagsProduced ?? 0)} />
                <Tile label="Bags sold" value={String(view.bagsSold ?? 0)} />
                <Tile label="Bags returned" value={String(view.bagsReturned ?? 0)} />
                <Tile label="Bags damaged" value={String(view.bagsDamaged ?? 0)} />
                <Tile label="Closing stock" value={String(view.closingStock ?? 0)} />
                <Tile label="Total income" value={gh(view.totalIncome)} accent="green" />
                <Tile label="Total expenses" value={gh(view.totalExpenses)} accent="rose" />
                <Tile label="Cash at hand" value={gh(view.cashAtHand)} />
                <Tile label="MoMo balance" value={gh(view.moMoBalance)} />
                <Tile label="Bank balance" value={gh(view.bankBalance)} />
                <Tile label="Credit sales" value={gh(view.creditSales)} />
                <Tile label="Driver shortages" value={gh(view.driverShortages)} />
              </div>

              {view.status === "Draft" && (
                <div className="border-t pt-3 space-y-2">
                  <div className="font-medium text-slate-700">Submit for approval</div>
                  <div className="grid grid-cols-2 gap-3">
                    <div><Label>Actual cash counted (physical)</Label>
                      <Input type="number" min={0} step="0.01" value={submitForm.actualCashCounted} onChange={(e) => setSubmitForm({ ...submitForm, actualCashCounted: Number(e.target.value) || 0 })} /></div>
                    <div className="col-span-2"><Label>Manager notes</Label>
                      <Textarea value={submitForm.managerNotes} onChange={(e) => setSubmitForm({ ...submitForm, managerNotes: e.target.value })} /></div>
                  </div>
                  <div className="flex justify-end gap-2 pt-2">
                    <Button onClick={submitClosing}>Submit for approval</Button>
                  </div>
                </div>
              )}

              {view.status === "Submitted" && (
                <div className="border-t pt-3 flex justify-end gap-2">
                  <Button variant="outline" onClick={() => reject(view.waterDailyClosingId)}><XCircle className="h-4 w-4 mr-1" /> Reject</Button>
                  <Button onClick={() => approve(view.waterDailyClosingId)}><CheckCircle2 className="h-4 w-4 mr-1" /> Approve &amp; lock</Button>
                </div>
              )}

              {view.managerNotes && (
                <div className="border-t pt-2 text-sm">
                  <span className="text-slate-500">Manager notes:</span> {view.managerNotes}
                </div>
              )}
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}

function Tile({ label, value, accent }: { label: string; value: string; accent?: "green" | "rose" }) {
  const color = accent === "green" ? "text-green-700" : accent === "rose" ? "text-rose-600" : "text-slate-900"
  return (
    <div className="rounded border p-2">
      <div className="text-xs text-slate-500">{label}</div>
      <div className={`font-semibold tabular-nums ${color}`}>{value}</div>
    </div>
  )
}
