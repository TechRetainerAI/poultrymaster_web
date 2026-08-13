"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Badge } from "@/components/ui/badge"
import { Plus, Loader2, FileText, CheckCircle2, XCircle, Eye, Trash2, Pencil, Undo2, RefreshCw } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterDailyClosings, getWaterDailyClosing, createWaterDailyClosing,
  submitWaterDailyClosing, emailWaterDailyClosing, approveWaterDailyClosing, rejectWaterDailyClosing,
  deleteWaterDailyClosing, updateWaterDailyClosingNotes,
  reopenWaterDailyClosing, linkSupersededWaterDailyClosing, recreateWaterDailyClosing,
  type WaterDailyClosing,
} from "@/lib/api/water"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { fmtMoney } from "@/lib/currency"

const gh = (n: number | null | undefined) => fmtMoney(n)

const STATUS_COLORS: Record<string, string> = {
  Draft: "bg-slate-100 text-slate-700",
  Submitted: "bg-blue-100 text-blue-700",
  Approved: "bg-green-100 text-green-700",
  Rejected: "bg-rose-100 text-rose-700",
  // Migration 068 — closings can be reopened so a fresh one can supersede.
  Reopened: "bg-amber-100 text-amber-700",
  Superseded: "bg-slate-100 text-slate-500",
}

export default function WaterDailyClosingPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmName = useAuthStore((s) => s.activeFarmName)
  // Company email = where the owner receives the closing report on submit.
  const companyEmail = useAuthStore((s) => s.companies.find((c) => c.farmId === s.activeFarmId)?.email)
  const logout = useLogout()

  const [closings, setClosings] = useState<WaterDailyClosing[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [loading, setLoading] = useState(true)

  const visibleClosings = useMemo(
    () => filterByDateAndSearch(closings, {
      search, dateFrom, dateTo,
      searchKeys: ["status"],
      dateKey: "closingDate",
    }),
    [closings, search, dateFrom, dateTo],
  )

  // Client-side paging: the whole list is already in memory, so this is a
  // slice. Feed the SAME slice to the cards and the desktop table.
  const pg = usePagination(visibleClosings)

  const [newDlg, setNewDlg] = useState(false)
  const [newDate, setNewDate] = useState(new Date().toISOString().split("T")[0])

  const [view, setView] = useState<WaterDailyClosing | null>(null)
  const [submitForm, setSubmitForm] = useState({ actualCashCounted: 0, managerNotes: "" })
  // Reject dialog state — replaces window.prompt so the layout matches the rest of the app.
  const [rejectDlg, setRejectDlg] = useState<{ id: number; reason: string } | null>(null)
  // Delete confirmation
  const [deleteTarget, setDeleteTarget] = useState<WaterDailyClosing | null>(null)
  // Migration 068 — reopen/resubmit dialogs.
  const [reopenTarget, setReopenTarget] = useState<WaterDailyClosing | null>(null)

  // After Reopen succeeds, "Recreate Closing" inserts a new Draft for the same
  // date and links it back to the reopened (predecessor) row in a single
  // transactional call (migration 079 — spWaterDailyClosing_Recreate). The
  // returned Draft surfaces live aggregates through GetById's "Status='Draft' →
  // use live totals" path (migration 058), so the user reviews up-to-date
  // sales/production/expense numbers before submitting.
  async function resubmitFor(c: WaterDailyClosing) {
    try {
      const { closing, waterDailyClosingId } = await recreateWaterDailyClosing({
        closingDate: c.closingDate.split("T")[0],
        predecessorClosingId: c.waterDailyClosingId,
        actualCashCounted: c.actualCashCounted ?? 0,
        managerNotes: c.managerNotes ?? null,
      })
      toast({
        title: "Closing recalculated",
        description: "New draft created from current data — review and submit.",
      })
      await load()
      // Prefer the closing returned by the endpoint so we don't pay for an
      // extra GetById round-trip.
      setView(closing ?? (waterDailyClosingId ? await getWaterDailyClosing(waterDailyClosingId) : null))
    } catch (e: any) {
      toast({ title: "Could not recreate closing", description: e?.message, variant: "destructive" })
    }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try { setClosings(await listWaterDailyClosings()) }
    catch (e: any) { toast({ title: "Could not load daily closings", description: e?.message ?? String(e), variant: "destructive" }) }
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
      const closingId = view.waterDailyClosingId
      const updated = await submitWaterDailyClosing(closingId, submitForm)
      setView(updated); await load()
      toast({ title: "Closing submitted", description: "Waiting for owner approval." })

      // Email the closing report to the company (owner) — fire-and-forget so a
      // mail problem never masks a successful submit.
      if (companyEmail) {
        emailWaterDailyClosing(closingId, companyEmail, activeFarmName ?? undefined)
          .then(() => toast({ title: "Closing report emailed", description: `Sent to ${companyEmail}.` }))
          .catch((e: any) => toast({ title: "Closing submitted, but email failed", description: e?.message, variant: "destructive" }))
      } else {
        toast({
          title: "No company email set",
          description: "Add a company email in setup to receive closing reports by email.",
        })
      }
    } catch (e: any) { toast({ title: "Submit failed", description: e?.message, variant: "destructive" }) }
  }

  async function approve(id: number) {
    try { await approveWaterDailyClosing(id); toast({ title: "Closing approved + locked" }); setView(null); await load() }
    catch (e: any) { toast({ title: "Approve failed", description: e?.message, variant: "destructive" }) }
  }

  async function reject(id: number) {
    // Open the reject dialog instead of using window.prompt — the prompt looks like a system dialog
    // and operators were closing it by accident.
    setRejectDlg({ id, reason: "" })
  }

  async function confirmReject() {
    if (!rejectDlg || !rejectDlg.reason.trim()) {
      toast({ title: "Reason required", description: "Tell the manager what to fix.", variant: "destructive" })
      return
    }
    try {
      await rejectWaterDailyClosing(rejectDlg.id, rejectDlg.reason.trim())
      toast({ title: "Closing rejected" })
      setRejectDlg(null); setView(null); await load()
    } catch (e: any) {
      toast({ title: "Reject failed", description: e?.message, variant: "destructive" })
    }
  }

  async function deleteClosing(c: WaterDailyClosing) {
    try {
      await deleteWaterDailyClosing(c.waterDailyClosingId)
      toast({ title: "Closing deleted", description: `${c.closingDate.split("T")[0]} removed.` })
      setDeleteTarget(null); setView(null); await load()
    } catch (e: any) {
      toast({ title: "Delete failed", description: e?.message, variant: "destructive" })
    }
  }

  async function saveNotesEdit() {
    if (!view) return
    try {
      await updateWaterDailyClosingNotes(view.waterDailyClosingId, submitForm.managerNotes ?? null)
      toast({ title: "Notes saved" })
      // Refresh the open closing so the new notes appear without closing the dialog.
      const fresh = await getWaterDailyClosing(view.waterDailyClosingId)
      setView(fresh); await load()
    } catch (e: any) {
      toast({ title: "Save failed", description: e?.message, variant: "destructive" })
    }
  }

  const todayClosing = closings.find(c => c.closingDate?.startsWith(new Date().toISOString().slice(0, 10)))

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <FileText className="h-6 w-6 text-sky-600" /> Daily closing
            </h1>
            <Button onClick={() => { setNewDate(new Date().toISOString().split("T")[0]); setNewDlg(true) }} className="w-full sm:w-auto h-11 sm:h-10">
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

          <ListFilters
            search={search} setSearch={setSearch}
            dateFrom={dateFrom} setDateFrom={setDateFrom}
            dateTo={dateTo} setDateTo={setDateTo}
            searchPlaceholder="Search status"
          />

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : closings.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No daily closings yet. Start today's above.</div>
              ) : (
                <MobileCardList
                  items={pg.pageItems}
                  pagination={pg.paginationProps}
                  getKey={(c) => c.waterDailyClosingId}
                  primary={(c) => c.closingDate.split("T")[0]}
                  secondary={(c) => (
                    <>
                      <span>Cash {gh(c.cashAtHand)}</span>
                      <Badge className={STATUS_COLORS[c.status] ?? ""}>{c.status}</Badge>
                    </>
                  )}
                  details={(c) => [
                    { label: "Date", value: c.closingDate.split("T")[0] },
                    { label: "Bags produced", value: c.bagsProduced ?? 0 },
                    { label: "Bags sold", value: c.bagsSold ?? 0 },
                    { label: "Income", value: gh(c.totalIncome) },
                    { label: "Expenses", value: gh(c.totalExpenses) },
                    { label: "Cash at hand", value: gh(c.cashAtHand) },
                    { label: "Status", value: c.status },
                  ]}
                  actions={(c) => (
                    <>
                      <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openView(c)}>
                        <Eye className="h-4 w-4 mr-1" /> View
                      </Button>
                      {(c.status === "Draft" || c.status === "Rejected") && (
                        <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => setDeleteTarget(c)}>
                          <Trash2 className="h-4 w-4 mr-1" /> Delete
                        </Button>
                      )}
                      {/* Prompt 2 §12 — Submitted/Approved can be reopened so
                          today's late corrections can flow into a fresh
                          closing. The old row stays in history. */}
                      {(c.status === "Submitted" || c.status === "Approved") && (
                        <Button size="sm" variant="outline" className="flex-1 h-10 text-amber-700 border-amber-200"
                          onClick={() => setReopenTarget(c)}>
                          <Undo2 className="h-4 w-4 mr-1" /> Reopen
                        </Button>
                      )}
                      {c.status === "Reopened" && (
                        <Button size="sm" variant="outline" className="flex-1 h-10"
                          onClick={() => resubmitFor(c)}>
                          <RefreshCw className="h-4 w-4 mr-1" /> Recreate closing
                        </Button>
                      )}
                    </>
                  )}
                  desktopTable={
                    <div className="overflow-x-auto">
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
                        {pg.pageItems.map((c) => (
                          <TableRow key={c.waterDailyClosingId}>
                            <TableCell className="font-medium">{c.closingDate.split("T")[0]}</TableCell>
                            <TableCell className="text-right tabular-nums">{c.bagsProduced ?? 0}</TableCell>
                            <TableCell className="text-right tabular-nums">{c.bagsSold ?? 0}</TableCell>
                            <TableCell className="text-right tabular-nums">{gh(c.totalIncome)}</TableCell>
                            <TableCell className="text-right tabular-nums">{gh(c.totalExpenses)}</TableCell>
                            <TableCell className="text-right tabular-nums">{gh(c.cashAtHand)}</TableCell>
                            <TableCell><Badge className={STATUS_COLORS[c.status] ?? ""}>{c.status}</Badge></TableCell>
                            <TableCell className="text-right">
                              <div className="inline-flex gap-1">
                                <Button size="sm" variant="ghost" onClick={() => openView(c)} title="View"><Eye className="h-4 w-4" /></Button>
                                {(c.status === "Draft" || c.status === "Rejected") && (
                                  <Button
                                    size="sm"
                                    variant="ghost"
                                    className="text-rose-600 hover:text-rose-700 hover:bg-rose-50"
                                    onClick={() => setDeleteTarget(c)}
                                    title="Delete (Draft/Rejected only)"
                                  >
                                    <Trash2 className="h-4 w-4" />
                                  </Button>
                                )}
                                {(c.status === "Submitted" || c.status === "Approved") && (
                                  <Button size="sm" variant="ghost" onClick={() => setReopenTarget(c)} title="Reopen">
                                    <Undo2 className="h-4 w-4 text-amber-600" />
                                  </Button>
                                )}
                                {c.status === "Reopened" && (
                                  <Button size="sm" variant="ghost" onClick={() => resubmitFor(c)} title="Recreate closing">
                                    <RefreshCw className="h-4 w-4 text-sky-600" />
                                  </Button>
                                )}
                              </div>
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                    </div>
                  }
                />
              )}
            </CardContent>
          </Card>
        </main>
      </div>

      {/* New closing */}
      <Dialog open={newDlg} onOpenChange={setNewDlg}>
        <DialogContent>
          <DialogHeader><DialogTitle>Start daily closing{activeFarmName ? ` — ${activeFarmName}` : ""}</DialogTitle></DialogHeader>
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

      {/* View / submit / approve — wider modal so the 12 summary tiles + form fit without scrolling. */}
      <Dialog open={!!view} onOpenChange={(v) => { if (!v) setView(null) }}>
        <DialogContent className="w-[95vw] max-w-[1600px] max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              {view && (
                <>
                  <FileText className="h-5 w-5 text-sky-600" />
                  <span>Closing: {view.closingDate.split("T")[0]}{activeFarmName ? ` — ${activeFarmName}` : ""}</span>
                  <Badge className={STATUS_COLORS[view.status]}>{view.status}</Badge>
                </>
              )}
            </DialogTitle>
          </DialogHeader>
          {view && (
            <div className="space-y-4">
              {/* Production tiles */}
              <div>
                <div className="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-2">Production</div>
                <div className="grid grid-cols-2 md:grid-cols-5 gap-3 text-sm">
                  <Tile label="Bags produced" value={String(view.bagsProduced ?? 0)} />
                  <Tile label="Bags sold" value={String(view.bagsSold ?? 0)} />
                  <Tile label="Bags returned" value={String(view.bagsReturned ?? 0)} />
                  <Tile label="Bags damaged" value={String(view.bagsDamaged ?? 0)} />
                  <Tile label="Closing stock" value={String(view.closingStockBags ?? view.closingStock ?? 0)} />
                </div>
              </div>
              {/* Money tiles */}
              <div>
                <div className="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-2">Money</div>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
                  <Tile label="Total income" value={gh(view.totalIncome)} accent="green" />
                  <Tile label="Total expenses" value={gh(view.totalExpenses)} accent="rose" />
                  <Tile label="Cash at hand" value={gh(view.cashAtHand)} />
                  <Tile label="MoMo balance" value={gh(view.moMoBalance)} />
                  <Tile label="Bank balance" value={gh(view.bankBalance)} />
                  <Tile label="Credit sales" value={gh(view.creditSales)} />
                  {/* Walk-in / customer cash received that is NOT part of Total
                      income; surfaced so Cash at hand visibly adds up. */}
                  <Tile label="Customer collections" value={gh(view.customerCollections ?? 0)} />
                  <Tile label="Driver shortages" value={gh(view.driverShortagesTotal ?? view.driverShortages)} accent={(view.driverShortagesTotal ?? view.driverShortages) ? "rose" : undefined} />
                </div>
                {/* N11: explain how Cash at hand is derived. */}
                <p className="mt-2 text-xs text-slate-500">
                  Cash at hand = (Total income − Credit sales) + Customer collections − Total expenses.
                  It is the cash that should physically be on hand from today's activity.
                </p>
              </div>

              {/* Submit form is now reachable from BOTH Draft and Rejected. Operators were stuck on
                  rejected closings with no way to address the manager's feedback and resubmit. */}
              {(view.status === "Draft" || view.status === "Rejected") && (
                <div className="border-t pt-4 space-y-3 bg-slate-50 -mx-6 px-6 py-4">
                  <div className="font-semibold text-slate-700">
                    {view.status === "Draft" ? "Submit for approval" : "Address feedback and re-submit"}
                  </div>
                  {view.rejectionReason && (
                    <div className="rounded border border-rose-200 bg-rose-50 px-3 py-2 text-sm text-rose-800">
                      <strong>Rejected:</strong> {view.rejectionReason}
                    </div>
                  )}
                  <div className="grid grid-cols-2 gap-3">
                    <div><Label>Actual cash counted (physical)</Label>
                      <NumberInput min={0} step="0.01" value={submitForm.actualCashCounted} onChange={(e) => setSubmitForm({ ...submitForm, actualCashCounted: Number(e.target.value) || 0 })} /></div>
                    <div className="flex flex-col justify-end">
                      <div className="text-xs text-slate-500">Cash at hand (expected)</div>
                      <div className="font-semibold tabular-nums">{gh(view.cashAtHand)}</div>
                      {submitForm.actualCashCounted > 0 && (
                        <div className={`text-xs mt-1 ${Math.abs(submitForm.actualCashCounted - (view.cashAtHand ?? 0)) < 0.01 ? "text-emerald-700" : "text-amber-700"}`}>
                          Variance: {gh(submitForm.actualCashCounted - (view.cashAtHand ?? 0))}
                        </div>
                      )}
                    </div>
                    <div className="col-span-2"><Label>Manager notes</Label>
                      <Textarea rows={3} value={submitForm.managerNotes} onChange={(e) => setSubmitForm({ ...submitForm, managerNotes: e.target.value })} /></div>
                  </div>
                  {/* N11: all actions grouped at the bottom (were stranded mid-page). */}
                  <div className="flex flex-wrap justify-end gap-2 pt-2 border-t mt-2">
                    <Button size="sm" variant="ghost" className="text-rose-600 hover:bg-rose-50 mr-auto" onClick={() => setDeleteTarget(view)}>
                      <Trash2 className="h-4 w-4 mr-1" /> Delete
                    </Button>
                    <Button size="sm" variant="outline" onClick={saveNotesEdit}>
                      <Pencil className="h-4 w-4 mr-1" /> Save notes only
                    </Button>
                    <Button onClick={submitClosing}>
                      <CheckCircle2 className="h-4 w-4 mr-1" />
                      {view.status === "Rejected" ? "Resubmit for approval" : "Submit for approval"}
                    </Button>
                  </div>
                </div>
              )}

              {view.status === "Submitted" && (
                <div className="border-t pt-4 flex justify-end gap-2">
                  <Button variant="outline" className="text-rose-600 hover:bg-rose-50 border-rose-200" onClick={() => reject(view.waterDailyClosingId)}>
                    <XCircle className="h-4 w-4 mr-1" /> Reject
                  </Button>
                  <Button onClick={() => approve(view.waterDailyClosingId)} className="bg-emerald-600 hover:bg-emerald-700">
                    <CheckCircle2 className="h-4 w-4 mr-1" /> Approve &amp; lock
                  </Button>
                </div>
              )}

              {view.status === "Approved" && view.managerNotes && (
                <div className="border-t pt-2 text-sm">
                  <span className="text-slate-500">Manager notes:</span> {view.managerNotes}
                </div>
              )}
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* Reject dialog — proper modal replacing window.prompt. */}
      <Dialog open={!!rejectDlg} onOpenChange={(v) => { if (!v) setRejectDlg(null) }}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2 text-rose-700">
              <XCircle className="h-5 w-5" /> Reject closing
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-3">
            <p className="text-sm text-slate-600">
              The manager will see this reason when they reopen the closing to fix it.
              Be specific (e.g. "cash variance ¢200 over — recount the till").
            </p>
            <div>
              <Label>Rejection reason</Label>
              <Textarea
                rows={4}
                value={rejectDlg?.reason ?? ""}
                onChange={(e) => setRejectDlg(rejectDlg ? { ...rejectDlg, reason: e.target.value } : null)}
                placeholder="Why are you rejecting this closing?"
              />
            </div>
          </div>
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="ghost" onClick={() => setRejectDlg(null)}>Cancel</Button>
            <Button variant="destructive" onClick={confirmReject}>
              <XCircle className="h-4 w-4 mr-1" /> Reject
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Delete confirmation. */}
      <ConfirmDeleteDialog
        open={!!deleteTarget}
        onOpenChange={(v) => { if (!v) setDeleteTarget(null) }}
        title="Delete daily closing?"
        description={deleteTarget ? `Closing for ${deleteTarget.closingDate.split("T")[0]} (status: ${deleteTarget.status}) will be permanently removed. This cannot be undone.` : ""}
        onConfirm={() => deleteTarget && deleteClosing(deleteTarget)}
      />

      {/* Migration 068 — Reopen with reason. The reopened closing stays in
          history (IsActive=0). The user can then create a new draft via
          Resubmit for the same date. */}
      <PromptDialog
        open={!!reopenTarget}
        onOpenChange={(v) => { if (!v) setReopenTarget(null) }}
        title="Reopen this closing?"
        description={reopenTarget
          ? <>The closing for <span className="font-medium">{reopenTarget.closingDate.split("T")[0]}</span> will be marked Reopened and stay in history. After reopening, click <span className="font-medium">Recreate closing</span> on the row to recalculate using current sales, expenses, production, payroll and cash for the same date.</>
          : undefined}
        label="Reason for reopening"
        placeholder="e.g. late expenses entered after closing"
        confirmLabel="Reopen"
        confirmVariant="destructive"
        onSubmit={async (reason) => {
          if (!reopenTarget) return
          try {
            await reopenWaterDailyClosing(reopenTarget.waterDailyClosingId, reason)
            toast({ title: "Closing reopened — click Resubmit to start a fresh one." })
            setReopenTarget(null); await load()
          } catch (e: any) {
            toast({ title: "Reopen failed", description: e?.message, variant: "destructive" })
          }
        }}
      />
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
