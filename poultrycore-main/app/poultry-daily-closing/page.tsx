"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Badge } from "@/components/ui/badge"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { useIsMobile } from "@/hooks/use-mobile"
import { cn } from "@/lib/utils"
import { Plus, Loader2, CheckCircle2, XCircle, Eye, Trash2, Pencil, RotateCcw, RefreshCw, ChevronDown, ChevronUp } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  listPoultryDailyClosings, createPoultryDailyClosing, getPoultryDailyClosing, submitPoultryDailyClosing,
  approvePoultryDailyClosing, rejectPoultryDailyClosing, deletePoultryDailyClosing,
  reopenPoultryDailyClosing, recreatePoultryDailyClosing, savePoultryDailyClosingNotes,
  type PoultryDailyClosing,
} from "@/lib/api/poultry-inventory"

const STATUS_COLORS: Record<string, string> = { Draft: "bg-slate-100 text-slate-700", Submitted: "bg-blue-100 text-blue-700", Approved: "bg-green-100 text-green-700", Rejected: "bg-red-100 text-red-700" }

function Tile({ label, value, accent }: { label: string; value: string; accent?: "green" | "rose" }) {
  const color = accent === "green" ? "text-emerald-700" : accent === "rose" ? "text-rose-700" : "text-slate-900"
  return (
    <div className="rounded-lg border border-slate-200 bg-white px-3 py-2">
      <div className="text-[11px] uppercase tracking-wide text-slate-500">{label}</div>
      <div className={`font-semibold tabular-nums ${color}`}>{value}</div>
    </div>
  )
}

export default function PoultryDailyClosingPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const gh = useFmt()
  const n = (v?: number) => (v ?? 0).toLocaleString()
  const isMobile = useIsMobile()
  // Mobile opens on scorecards; "View table format" flips to the wide table
  // (same pattern as /production-records).
  const [showTableMobile, setShowTableMobile] = useState(false)
  const [rows, setRows] = useState<PoultryDailyClosing[]>([])
  const pg = usePagination(rows)
  const [loading, setLoading] = useState(true)
  const [newOpen, setNewOpen] = useState(false)
  const [newDate, setNewDate] = useState(new Date().toISOString().split("T")[0])
  const [view, setView] = useState<PoultryDailyClosing | null>(null)
  const [actualCash, setActualCash] = useState(0)
  const [notes, setNotes] = useState("")
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
    try { const c = await getPoultryDailyClosing(id); setView(c); setActualCash(c.actualCashCounted || 0); setNotes(c.managerNotes || "") }
    catch (e: any) { toast({ title: "Could not load", description: e?.message, variant: "destructive" }) }
  }
  async function submit() {
    if (!view) return; setBusy(true)
    try { await submitPoultryDailyClosing(view.poultryDailyClosingId, { actualCashCounted: actualCash, managerNotes: notes || null }); toast({ title: view.status === "Rejected" ? "Resubmitted" : "Submitted" }); setView(null); await load() }
    catch (e: any) { toast({ title: "Submit failed", description: e?.message, variant: "destructive" }) }
    finally { setBusy(false) }
  }
  async function saveNotesOnly() {
    if (!view) return; setBusy(true)
    try { await savePoultryDailyClosingNotes(view.poultryDailyClosingId, { actualCashCounted: actualCash, managerNotes: notes || null }); toast({ title: "Saved" }); await openView(view.poultryDailyClosingId); await load() }
    catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setBusy(false) }
  }
  async function act(fn: () => Promise<any>, ok: string) {
    setBusy(true)
    try { await fn(); toast({ title: ok }); setView(null); await load() }
    catch (e: any) { toast({ title: "Action failed", description: e?.message, variant: "destructive" }) }
    finally { setBusy(false) }
  }

  const v = view
  const variance = v ? actualCash - (v.cashAtHand ?? 0) : 0

  return (
    <div className="flex min-h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 p-4 sm:p-6 space-y-4">
          <div className="flex items-center justify-between">
            <div><h1 className="text-2xl font-bold">Daily Closing</h1><p className="text-sm text-slate-500">End-of-day production, sales, cash and stock snapshot.</p></div>
            <Button onClick={() => setNewOpen(true)}><Plus className="w-4 h-4 mr-1" /> New closing</Button>
          </div>
          {/* Mobile defaults to scorecards; "View table format" flips to the table. */}
          {loading ? <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div>
            : rows.length === 0 ? <Card><CardContent className="p-8 text-center text-slate-500">No closings yet.</CardContent></Card>
            : isMobile && !showTableMobile ? (
            <div className="space-y-3">
              {pg.pageItems.map((c, idx) => {
                const net = (c.totalIncome ?? 0) - (c.totalExpenses ?? 0)
                return (
                <Collapsible
                  key={c.poultryDailyClosingId}
                  defaultOpen
                  className={cn("group w-full rounded-xl border shadow-sm overflow-hidden",
                    idx % 2 === 0 ? "bg-amber-100 border-amber-300" : "bg-white border-slate-200")}
                >
                  <div className={cn("px-2.5 py-3 transition-colors", idx % 2 === 0 ? "active:bg-black/10" : "active:bg-black/5")}>
                    <CollapsibleTrigger asChild>
                      <div className="relative cursor-pointer">
                        <ChevronDown className="absolute right-0 top-0 h-4 w-4 text-slate-400 shrink-0 transition-transform group-data-[state=open]:rotate-180" />
                        <div className="min-w-0">
                          <div className="pr-6 flex flex-wrap items-center gap-2">
                            <span className="font-semibold text-slate-900">{(c.closingDate || "").split("T")[0]}</span>
                            <Badge className={STATUS_COLORS[c.status] ?? "bg-gray-100"}>{c.status}</Badge>
                          </div>
                          <div className="mt-3 grid grid-cols-2 gap-2">
                            <div className="rounded-lg bg-emerald-100 border border-emerald-300 px-3 py-2 shadow-sm">
                              <p className="text-[11px] font-semibold uppercase tracking-wide text-emerald-900">Produced</p>
                              <p className="text-xl font-extrabold leading-tight text-emerald-800">{n(c.quantityProduced)}</p>
                            </div>
                            <div className="rounded-lg bg-blue-100 border border-blue-300 px-3 py-2 shadow-sm">
                              <p className="text-[11px] font-semibold uppercase tracking-wide text-blue-900">Sold</p>
                              <p className="text-xl font-extrabold leading-tight text-blue-800">{n(c.eggsSold)}</p>
                            </div>
                            <div className="col-span-2 rounded-lg bg-violet-100 border border-violet-300 px-3 py-2 shadow-sm">
                              <p className="text-[11px] font-semibold uppercase tracking-wide text-violet-900">Cash at hand</p>
                              <p className="text-xl font-extrabold leading-tight text-violet-900">{gh(c.cashAtHand)}</p>
                            </div>
                          </div>
                        </div>
                      </div>
                    </CollapsibleTrigger>
                    <CollapsibleContent>
                      <div className="mt-4 pt-4 border-t border-slate-200/70 space-y-2 text-sm">
                        <div className="grid grid-cols-2 gap-2">
                          <div><span className="text-slate-500">Income</span> <span className="font-medium text-emerald-700">{gh(c.totalIncome ?? 0)}</span></div>
                          <div><span className="text-slate-500">Expenses</span> <span className="font-medium text-rose-700">{gh(c.totalExpenses ?? 0)}</span></div>
                          <div><span className="text-slate-500">Net</span> <span className={cn("font-medium", net < 0 ? "text-rose-700" : "text-emerald-700")}>{gh(net)}</span></div>
                          <div><span className="text-slate-500">Closing stock</span> <span className="font-medium">{n(c.closingStock)}</span></div>
                        </div>
                        <div className="flex gap-2 pt-2">
                          <Button variant="outline" size="sm" className="h-10 flex-1 bg-white" onClick={(e) => { e.stopPropagation(); void openView(c.poultryDailyClosingId) }}>
                            <Eye className="h-4 w-4 mr-2" /> Open closing
                          </Button>
                        </div>
                      </div>
                    </CollapsibleContent>
                  </div>
                </Collapsible>
                )
              })}
              <DataPagination {...pg.paginationProps} />
              <div className="rounded-lg border bg-slate-50/60 px-4 py-2">
                <Button variant="ghost" size="sm" className="w-full text-slate-600" onClick={() => setShowTableMobile(true)}>
                  View table format <ChevronDown className="h-4 w-4 ml-1" />
                </Button>
              </div>
            </div>
            ) : (
            <Card><CardContent className="p-4">
              {isMobile && (
                <div className="-mx-4 -mt-4 mb-3 flex items-center justify-between gap-2 border-b bg-slate-50 px-4 py-2">
                  <span className="text-xs text-slate-600">Table view • Scroll → for more</span>
                  <Button variant="ghost" size="sm" onClick={() => setShowTableMobile(false)}>
                    <ChevronUp className="h-4 w-4 mr-1" /> Cards
                  </Button>
                </div>
              )}
              <div className="overflow-x-auto">
              <Table>
                <TableHeader><TableRow>
                  <TableHead>Date</TableHead><TableHead className="text-right">Produced</TableHead><TableHead className="text-right">Sold</TableHead>
                  <TableHead className="text-right">Income</TableHead><TableHead className="text-right">Expenses</TableHead>
                  <TableHead className="text-right">Cash at hand</TableHead><TableHead className="text-right">Closing stock</TableHead>
                  <TableHead>Status</TableHead><TableHead className="text-right">Actions</TableHead>
                </TableRow></TableHeader>
                <TableBody>
                  {rows.length === 0 ? <TableRow><TableCell colSpan={9} className="text-center text-slate-500 py-6">No closings yet.</TableCell></TableRow>
                    : pg.pageItems.map((c) => (
                      <TableRow key={c.poultryDailyClosingId}>
                        <TableCell className="font-medium">{(c.closingDate || "").split("T")[0]}</TableCell>
                        <TableCell className="text-right">{n(c.quantityProduced)}</TableCell>
                        <TableCell className="text-right">{n(c.eggsSold)}</TableCell>
                        <TableCell className="text-right">{gh(c.totalIncome ?? 0)}</TableCell>
                        <TableCell className="text-right">{gh(c.totalExpenses ?? 0)}</TableCell>
                        <TableCell className="text-right">{gh(c.cashAtHand)}</TableCell>
                        <TableCell className="text-right">{n(c.closingStock)}</TableCell>
                        <TableCell><Badge className={STATUS_COLORS[c.status] ?? "bg-gray-100"}>{c.status}</Badge></TableCell>
                        <TableCell className="text-right"><Button variant="ghost" size="sm" onClick={() => openView(c.poultryDailyClosingId)}><Eye className="w-4 h-4" /></Button></TableCell>
                      </TableRow>
                    ))}
                </TableBody>
              </Table>
              </div>
              <DataPagination {...pg.paginationProps} />
            </CardContent></Card>
            )}
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
        <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader><DialogTitle className="flex items-center gap-2">Closing — {(v?.closingDate || "").split("T")[0]} {v && <Badge className={STATUS_COLORS[v.status]}>{v.status}</Badge>}</DialogTitle></DialogHeader>
          {v && (
            <div className="space-y-4">
              <div>
                <div className="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-2">Production</div>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
                  <Tile label="Eggs produced" value={n(v.quantityProduced)} />
                  <Tile label="Sold" value={n(v.eggsSold)} />
                  <Tile label="Returned" value={n(v.eggsReturned)} />
                  <Tile label="Damaged" value={n(v.quantityDamaged)} />
                  <Tile label="Mortality" value={n(v.mortality)} />
                  <Tile label="Feed used" value={n(v.feedUsedQty)} />
                  <Tile label="Medication used" value={n(v.medUsedQty)} />
                  <Tile label="Production cost" value={gh(v.totalProductionCost)} accent="rose" />
                  <Tile label="Closing stock" value={n(v.closingStock)} />
                </div>
              </div>
              <div>
                <div className="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-2">Money</div>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
                  <Tile label="Total income" value={gh(v.totalIncome ?? 0)} accent="green" />
                  <Tile label="Total expenses" value={gh(v.totalExpenses ?? 0)} accent="rose" />
                  <Tile label="Cash at hand" value={gh(v.cashAtHand)} />
                  <Tile label="Credit sales" value={gh(v.creditSales ?? 0)} />
                  <Tile label="Customer collections" value={gh(v.customerCollections ?? 0)} />
                  <Tile label="Cash balance" value={gh(v.cashBalance ?? 0)} />
                  <Tile label="MoMo balance" value={gh(v.moMoBalance ?? 0)} />
                  <Tile label="Bank balance" value={gh(v.bankBalance ?? 0)} />
                </div>
                <p className="mt-2 text-xs text-slate-500">Cash at hand = (Total income − Credit sales) + Customer collections − Total expenses. It is the cash that should physically be on hand from today's activity.</p>
              </div>

              {(v.status === "Draft" || v.status === "Rejected") && (
                <div className="border-t pt-4 space-y-3 bg-slate-50 -mx-6 px-6 py-4">
                  <div className="font-semibold text-slate-700">{v.status === "Draft" ? "Submit for approval" : "Address feedback and re-submit"}</div>
                  {v.rejectionReason && <div className="rounded border border-rose-200 bg-rose-50 px-3 py-2 text-sm text-rose-800"><strong>Rejected:</strong> {v.rejectionReason}</div>}
                  <div className="grid grid-cols-2 gap-3">
                    <div><Label>Actual cash counted (physical)</Label><NumberInput min={0} step="0.01" value={actualCash} onChange={(e) => setActualCash(Number(e.target.value) || 0)} /></div>
                    <div className="flex flex-col justify-end">
                      <div className="text-xs text-slate-500">Cash at hand (expected)</div>
                      <div className="font-semibold tabular-nums">{gh(v.cashAtHand)}</div>
                      {actualCash > 0 && <div className={`text-xs mt-1 ${Math.abs(variance) < 0.01 ? "text-emerald-700" : "text-amber-700"}`}>Variance: {gh(variance)}</div>}
                    </div>
                    <div className="col-span-2"><Label>Manager notes</Label><Textarea rows={3} value={notes} onChange={(e) => setNotes(e.target.value)} /></div>
                  </div>
                  <div className="flex flex-wrap justify-end gap-2 pt-2 border-t mt-2">
                    <Button size="sm" variant="ghost" className="text-rose-600 hover:bg-rose-50 mr-auto" onClick={() => act(() => deletePoultryDailyClosing(v.poultryDailyClosingId), "Deleted")}><Trash2 className="h-4 w-4 mr-1" /> Delete</Button>
                    <Button size="sm" variant="outline" onClick={saveNotesOnly} disabled={busy}><Pencil className="h-4 w-4 mr-1" /> Save notes only</Button>
                    <Button onClick={submit} disabled={busy}>{busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <><CheckCircle2 className="h-4 w-4 mr-1" /> {v.status === "Rejected" ? "Resubmit" : "Submit"}</>}</Button>
                  </div>
                </div>
              )}

              {v.status === "Submitted" && (
                <div className="border-t pt-4 flex flex-wrap justify-end gap-2">
                  <Button size="sm" variant="ghost" className="text-amber-700 hover:bg-amber-50 mr-auto" onClick={() => act(() => reopenPoultryDailyClosing(v.poultryDailyClosingId), "Reopened")}><RotateCcw className="h-4 w-4 mr-1" /> Reopen</Button>
                  <Button variant="outline" className="text-rose-600 hover:bg-rose-50 border-rose-200" onClick={() => act(() => rejectPoultryDailyClosing(v.poultryDailyClosingId, "Rejected"), "Rejected")}><XCircle className="h-4 w-4 mr-1" /> Reject</Button>
                  <Button onClick={() => act(() => approvePoultryDailyClosing(v.poultryDailyClosingId), "Approved")} className="bg-emerald-600 hover:bg-emerald-700"><CheckCircle2 className="h-4 w-4 mr-1" /> Approve &amp; lock</Button>
                </div>
              )}

              {v.status === "Approved" && (
                <div className="border-t pt-4 flex flex-wrap justify-end gap-2">
                  {v.managerNotes && <div className="mr-auto text-sm text-slate-600"><span className="font-medium">Notes:</span> {v.managerNotes}</div>}
                  <Button size="sm" variant="outline" className="text-amber-700 border-amber-200" onClick={() => act(() => reopenPoultryDailyClosing(v.poultryDailyClosingId), "Reopened")}><RotateCcw className="h-4 w-4 mr-1" /> Reopen</Button>
                  <Button size="sm" variant="outline" onClick={() => act(() => recreatePoultryDailyClosing(v.poultryDailyClosingId), "Recreated")}><RefreshCw className="h-4 w-4 mr-1" /> Recreate</Button>
                </div>
              )}

              <div className="flex justify-end"><Button variant="outline" onClick={() => setView(null)}>Close</Button></div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}
