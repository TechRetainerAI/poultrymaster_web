"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger } from "@/components/ui/alert-dialog"
import { Check, FileText, Loader2, Plus, RefreshCw } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  approveDailyClosing, createDailyClosing, getDailyClosings, submitDailyClosing,
  type GenericDailyClosing,
} from "@/lib/api/generic"

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}

function badgeClass(s: string) {
  switch (s) {
    case "Approved":  return "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"
    case "Rejected":  return "bg-rose-100 text-rose-800 hover:bg-rose-100"
    case "Submitted": return "bg-sky-100 text-sky-800 hover:bg-sky-100"
    default:          return "bg-slate-100 text-slate-800 hover:bg-slate-100"
  }
}

export default function GenericDailyClosingsPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()

  const [rows, setRows] = useState<GenericDailyClosing[]>([])
  const [loading, setLoading] = useState(true)
  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)

  const [form, setForm] = useState({
    closingDate: new Date().toISOString().slice(0, 10),
    openingCash: "",
    actualCashCounted: "0",
    managerNotes: "",
    differenceReason: "",
  })

  const load = async () => {
    setLoading(true)
    try { setRows(await getDailyClosings()) }
    catch (e: any) { toast({ title: "Could not load closings", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router])

  const onCreate = async () => {
    setSaving(true)
    try {
      const created = await createDailyClosing({
        closingDate: form.closingDate,
        openingCash: form.openingCash === "" ? null : Number(form.openingCash),
        actualCashCounted: Number(form.actualCashCounted) || 0,
        managerNotes: form.managerNotes || null,
        differenceReason: form.differenceReason || null,
      })
      if (created) {
        // Auto-submit so totals get aggregated immediately.
        await submitDailyClosing(created.genericDailyClosingId)
        toast({ title: `Closing #${created.genericDailyClosingId} created and submitted.`, description: "Totals aggregated automatically. Review and approve." })
        setOpen(false)
        setForm({ closingDate: new Date().toISOString().slice(0, 10), openingCash: "", actualCashCounted: "0", managerNotes: "", differenceReason: "" })
        await load()
      }
    } catch (e: any) {
      toast({ title: "Could not create closing", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  const onApprove = async (id: number) => {
    try {
      await approveDailyClosing(id)
      toast({ title: `Closing #${id} approved and locked.` })
      await load()
    } catch (e: any) {
      toast({ title: "Approve failed", description: e?.message ?? String(e), variant: "destructive" })
    }
  }

  const onResubmit = async (id: number) => {
    try {
      await submitDailyClosing(id)
      toast({ title: `Closing #${id} re-submitted with fresh totals.` })
      await load()
    } catch (e: any) {
      toast({ title: "Re-submit failed", description: e?.message ?? String(e), variant: "destructive" })
    }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <FileText className="h-6 w-6 text-slate-700" /> Daily closings
              </h1>
              <p className="text-sm text-slate-500">{rows.length} closing(s) — totals are auto-aggregated; you just count cash.</p>
            </div>
            <Dialog open={open} onOpenChange={setOpen}>
              <DialogTrigger asChild>
                <Button><Plus className="h-4 w-4 mr-1" />Close today</Button>
              </DialogTrigger>
              <DialogContent>
                <DialogHeader>
                  <DialogTitle>Daily closing</DialogTitle>
                  <DialogDescription>Enter only the cash you counted. Sales, expenses, payments and expected cash are computed automatically from the immutable ledgers.</DialogDescription>
                </DialogHeader>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                  <div>
                    <Label>Closing date</Label>
                    <Input type="date" value={form.closingDate} onChange={(e) => setForm((f) => ({ ...f, closingDate: e.target.value }))} />
                  </div>
                  <div>
                    <Label>Opening cash (optional)</Label>
                    <Input type="number" step="0.01" value={form.openingCash} onChange={(e) => setForm((f) => ({ ...f, openingCash: e.target.value }))} placeholder="auto" />
                  </div>
                  <div className="md:col-span-2">
                    <Label>Actual cash counted *</Label>
                    <Input type="number" step="0.01" min="0" value={form.actualCashCounted} onChange={(e) => setForm((f) => ({ ...f, actualCashCounted: e.target.value }))} />
                  </div>
                  <div className="md:col-span-2">
                    <Label>Manager notes</Label>
                    <Textarea rows={2} value={form.managerNotes} onChange={(e) => setForm((f) => ({ ...f, managerNotes: e.target.value }))} maxLength={2000} />
                  </div>
                  <div className="md:col-span-2">
                    <Label>Reason for any cash difference</Label>
                    <Textarea rows={2} value={form.differenceReason} onChange={(e) => setForm((f) => ({ ...f, differenceReason: e.target.value }))} maxLength={500} />
                  </div>
                </div>
                <DialogFooter>
                  <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
                  <Button onClick={onCreate} disabled={saving}>{saving && <Loader2 className="h-4 w-4 animate-spin mr-2" />}Create &amp; submit</Button>
                </DialogFooter>
              </DialogContent>
            </Dialog>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : rows.length === 0 ? (
            <Card><CardContent className="py-8 text-center text-slate-500">
              No daily closings yet. Click <strong>Close today</strong> to count cash and submit your first one.
            </CardContent></Card>
          ) : (
            <Card>
              <CardContent className="p-0">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Date</TableHead>
                      <TableHead className="text-right">Sales</TableHead>
                      <TableHead className="text-right">Expenses</TableHead>
                      <TableHead className="text-right">Expected cash</TableHead>
                      <TableHead className="text-right">Actual cash</TableHead>
                      <TableHead className="text-right">Difference</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead></TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {rows.map((c) => (
                      <TableRow key={c.genericDailyClosingId}>
                        <TableCell>{new Date(c.closingDate).toLocaleDateString()}</TableCell>
                        <TableCell className="text-right">{fmt(c.totalSales)}</TableCell>
                        <TableCell className="text-right">{fmt(c.totalExpenses)}</TableCell>
                        <TableCell className="text-right">{fmt(c.expectedCash)}</TableCell>
                        <TableCell className="text-right">{fmt(c.actualCashCounted)}</TableCell>
                        <TableCell className={`text-right ${c.cashDifference !== 0 ? "text-rose-700 font-semibold" : ""}`}>{fmt(c.cashDifference)}</TableCell>
                        <TableCell><Badge className={badgeClass(c.status)}>{c.status}</Badge></TableCell>
                        <TableCell className="flex gap-1">
                          {c.status === "Submitted" && (
                            <>
                              <AlertDialog>
                                <AlertDialogTrigger asChild>
                                  <Button size="sm" variant="default" className="bg-emerald-600 hover:bg-emerald-700"><Check className="h-3 w-3 mr-1" />Approve</Button>
                                </AlertDialogTrigger>
                                <AlertDialogContent>
                                  <AlertDialogHeader>
                                    <AlertDialogTitle>Approve and lock?</AlertDialogTitle>
                                    <AlertDialogDescription>Once approved, this closing becomes a frozen snapshot of the day.</AlertDialogDescription>
                                  </AlertDialogHeader>
                                  <AlertDialogFooter>
                                    <AlertDialogCancel>Cancel</AlertDialogCancel>
                                    <AlertDialogAction onClick={() => onApprove(c.genericDailyClosingId)}>Approve</AlertDialogAction>
                                  </AlertDialogFooter>
                                </AlertDialogContent>
                              </AlertDialog>
                              <Button size="sm" variant="outline" title="Refresh totals" onClick={() => onResubmit(c.genericDailyClosingId)}><RefreshCw className="h-3 w-3" /></Button>
                            </>
                          )}
                          {c.status === "Draft" && (
                            <Button size="sm" onClick={() => onResubmit(c.genericDailyClosingId)}>Submit</Button>
                          )}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </CardContent>
            </Card>
          )}
        </main>
      </div>
    </div>
  )
}
