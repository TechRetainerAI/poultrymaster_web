"use client"

/**
 * Tills & Shifts — the cash drawer's day.
 *
 * Open a shift on a till with a float taken from the cash box; every cash sale,
 * cash refund and cash expense paid from that till posts to it while the shift
 * is open. Closing is the cash-up: count the drawer, the difference from what
 * the ledger expects is posted as over/short, and the takings can be dropped to
 * the safe or bank in the same step. All of it happens in one database call per
 * action (migration 323), so a half-closed shift cannot exist.
 */

import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Banknote, Calculator, Clock, DoorOpen, Loader2, Lock, Plus, Printer, Scale, FileText } from "lucide-react"
import { PageHeader } from "@/components/restaurant/page-header"
import { StatCard } from "@/components/restaurant/stat-card"
import { EmptyState } from "@/components/restaurant/empty-state"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import { useAuthStore } from "@/lib/store/auth-store"
import { usePermissions } from "@/hooks/use-permissions"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  listCashAccounts, createCashAccount, listShifts, openShift, closeShift, getZReport, todayIso,
  type CashAccount, type CashShift, type ZReportLine,
} from "@/lib/api/restaurant-finance"

const num = (s: string) => Math.round((parseFloat(s) || 0) * 100) / 100
const when = (s?: string | null) => (s ? new Date(s).toLocaleString() : "—")

function daysAgo(n: number) {
  const d = new Date(); d.setDate(d.getDate() - n)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
}

export default function RestaurantTillsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const gh = useFmt()
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const canView = permissions.isAdmin || permissions.featureAccess.canViewRestaurantPOS || permissions.featureAccess.canViewCashLedger

  const [loading, setLoading] = useState(true)
  const [accounts, setAccounts] = useState<CashAccount[]>([])
  const [shifts, setShifts] = useState<CashShift[]>([])
  const [from, setFrom] = useState(daysAgo(13))
  const [to, setTo] = useState(todayIso())
  const [saving, setSaving] = useState(false)

  // dialogs
  const [newTillOpen, setNewTillOpen] = useState(false)
  const [newTillName, setNewTillName] = useState("")
  const [openFor, setOpenFor] = useState<CashAccount | null>(null)
  const [floatAmt, setFloatAmt] = useState("")
  const [floatFrom, setFloatFrom] = useState<string>("")
  const [openNotes, setOpenNotes] = useState("")
  const [closeFor, setCloseFor] = useState<CashShift | null>(null)
  const [counted, setCounted] = useState("")
  const [dropAmt, setDropAmt] = useState("")
  const [dropTo, setDropTo] = useState<string>("")
  const [closeNotes, setCloseNotes] = useState("")
  const [zFor, setZFor] = useState<CashShift | null>(null)
  const [zLines, setZLines] = useState<ZReportLine[]>([])

  const load = useCallback(async () => {
    try {
      const [accts, open, recent] = await Promise.all([
        listCashAccounts(), listShifts("Open"), listShifts(undefined, from, to),
      ])
      setAccounts(accts)
      const seen = new Set(open.map((s) => s.shiftId))
      setShifts([...open, ...recent.filter((s) => !seen.has(s.shiftId))])
    } catch (e: any) {
      toast({ title: "Could not load tills", description: e?.message, variant: "destructive" })
    } finally { setLoading(false) }
  }, [from, to, toast])

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    if (!activeFarmId) return
    void load()
  }, [activeFarmType, activeFarmId, router, load])

  const tills = accounts.filter((a) => a.accountType === "Till" && a.isActive)
  const sources = accounts.filter((a) => a.accountType !== "Till" && a.isActive)
  const openShifts = shifts.filter((s) => s.status === "Open")
  const closedShifts = shifts.filter((s) => s.status === "Closed")
  const today = todayIso()
  const todayVariance = closedShifts
    .filter((s) => (s.closedAt ?? "").slice(0, 10) === today)
    .reduce((t, s) => t + (s.variance ?? 0), 0)

  async function createTill() {
    if (!newTillName.trim()) return
    setSaving(true)
    try {
      await createCashAccount({ name: newTillName.trim(), accountType: "Till" })
      toast({ title: `${newTillName.trim()} created` })
      setNewTillOpen(false); setNewTillName(""); await load()
    } catch (e: any) { toast({ title: "Could not create the till", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  function startOpen(till: CashAccount) {
    setOpenFor(till); setFloatAmt(""); setOpenNotes("")
    const box = sources.find((a) => a.defaultFor === "Cash") ?? sources[0]
    setFloatFrom(box ? String(box.cashAccountId) : "")
  }

  async function submitOpen() {
    if (!openFor) return
    const fl = num(floatAmt)
    if (fl > 0 && !floatFrom) { toast({ title: "Choose where the float comes from", variant: "destructive" }); return }
    setSaving(true)
    try {
      await openShift({ tillAccountId: openFor.cashAccountId, openingFloat: fl, floatFromAccountId: fl > 0 ? Number(floatFrom) : null, notes: openNotes || null })
      toast({ title: `Shift opened on ${openFor.name}` })
      setOpenFor(null); await load()
    } catch (e: any) { toast({ title: "Could not open the shift", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  function startClose(s: CashShift) {
    setCloseFor(s); setCounted(""); setDropAmt(""); setCloseNotes("")
    const box = sources.find((a) => a.defaultFor === "Cash") ?? sources[0]
    setDropTo(box ? String(box.cashAccountId) : "")
  }

  const expected = closeFor?.currentBalance ?? 0
  const countedNum = num(counted)
  const variance = counted === "" ? 0 : Math.round((countedNum - expected) * 100) / 100
  const dropNum = num(dropAmt)

  async function submitClose() {
    if (!closeFor) return
    if (counted === "") { toast({ title: "Enter the cash counted", variant: "destructive" }); return }
    if (dropNum > countedNum) { toast({ title: "You cannot drop more than you counted", variant: "destructive" }); return }
    if (dropNum > 0 && !dropTo) { toast({ title: "Choose where the drop goes", variant: "destructive" }); return }
    setSaving(true)
    try {
      const r = await closeShift(closeFor.shiftId, { countedCash: countedNum, dropAmount: dropNum, dropToAccountId: dropNum > 0 ? Number(dropTo) : null, notes: closeNotes || null })
      toast({
        title: `${closeFor.shiftNumber} closed`,
        description: r.variance === 0 ? "The drawer balanced." : `${r.variance > 0 ? "Over" : "Short"} by ${gh(Math.abs(r.variance))}. ${gh(r.closingBalance)} left in the till.`,
      })
      const closed = closeFor
      setCloseFor(null); await load()
      void showZ({ ...closed, status: "Closed" })
    } catch (e: any) { toast({ title: "Could not close the shift", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function showZ(s: CashShift) {
    setZFor(s); setZLines([])
    try { setZLines(await getZReport(s.shiftId)) }
    catch (e: any) { toast({ title: "Could not load the Z-report", description: e?.message, variant: "destructive" }) }
  }

  // The Z-report is read off the refreshed list so a just-closed shift shows its counted figures.
  const zShift = useMemo(() => (zFor ? shifts.find((s) => s.shiftId === zFor.shiftId) ?? zFor : null), [zFor, shifts])

  function printZ() {
    const el = document.getElementById("z-report")
    if (!el) return
    const w = window.open("", "_blank", "width=360,height=640")
    if (!w) return
    w.document.write(`<html><head><title>Z-report</title><style>body{font-family:'Courier New',monospace;font-size:12px;width:300px;margin:0 auto;padding:10px}.row{display:flex;justify-content:space-between;margin:2px 0}h2{font-size:15px;margin:0 0 4px;text-align:center}.sec{font-weight:bold;margin-top:8px;border-top:1px dashed #000;padding-top:4px}</style></head><body>${el.innerHTML}</body></html>`)
    w.document.close(); w.print()
  }

  if (!canView) return (
    <div className="flex h-screen bg-gray-50"><DashboardSidebar /><div className="flex-1 flex flex-col overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-y-auto p-4 md:p-6"><Card><CardContent className="py-12 text-center text-slate-600">You do not have access to Tills & Shifts.</CardContent></Card></main>
    </div></div>
  )
  if (loading) return <PageSkeleton statCards={3} listRows={5} />

  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 md:p-6 pb-24 lg:pb-6">
          <div className="max-w-7xl mx-auto space-y-6">
            <PageHeader icon={Calculator} title="Tills & Shifts" subtitle="Open the drawer with a float, cash up at the end, see the Z-report">
              <Button variant="outline" onClick={() => setNewTillOpen(true)}><Plus className="h-4 w-4 mr-1" /> New till</Button>
            </PageHeader>

            <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
              <StatCard label="Open shifts" value={openShifts.length} icon={DoorOpen} color="green" />
              <StatCard label="Cash in open tills" value={gh(openShifts.reduce((t, s) => t + s.currentBalance, 0))} icon={Banknote} color="blue" />
              <StatCard label="Over / short closed today" value={gh(todayVariance)} icon={Scale} color={todayVariance < 0 ? "red" : "amber"} />
            </div>

            {tills.length === 0 ? (
              <Card><CardContent className="pt-6">
                <EmptyState icon={Calculator} title="No tills yet" description="A till is a cash drawer. Create one for each drawer at the counter; cash sales then go into whichever till has a shift open."
                  actionLabel="Create a till" onAction={() => setNewTillOpen(true)} />
              </CardContent></Card>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
                {tills.map((till) => {
                  const s = openShifts.find((x) => x.cashAccountId === till.cashAccountId)
                  return (
                    <Card key={till.cashAccountId} className={s ? "border-green-300" : ""}>
                      <CardContent className="p-4 space-y-3">
                        <div className="flex items-start justify-between gap-2">
                          <div className="min-w-0">
                            <div className="font-semibold truncate">{till.name}</div>
                            {s ? <div className="text-xs text-muted-foreground">{s.shiftNumber} · opened {when(s.openedAt)}{s.openedBy ? ` by ${s.openedBy}` : ""}</div>
                               : <div className="text-xs text-muted-foreground">No shift open</div>}
                          </div>
                          {s ? <Badge className="bg-green-600">Open</Badge> : <Badge variant="outline"><Lock className="h-3 w-3 mr-1" />Closed</Badge>}
                        </div>
                        <div className="grid grid-cols-2 gap-2 text-sm">
                          <div className="rounded-lg bg-gray-50 p-2"><div className="text-xs text-muted-foreground">In the drawer</div><div className="font-semibold">{gh(till.currentBalance)}</div></div>
                          {s && <div className="rounded-lg bg-gray-50 p-2"><div className="text-xs text-muted-foreground">Cash sales this shift</div><div className="font-semibold">{gh(s.cashSales)}</div></div>}
                          {s && <div className="rounded-lg bg-gray-50 p-2"><div className="text-xs text-muted-foreground">Opening float</div><div className="font-semibold">{gh(s.openingFloat)}</div></div>}
                        </div>
                        <div className="flex gap-2">
                          {s ? (
                            <>
                              <Button className="flex-1 bg-rose-600 hover:bg-rose-700" onClick={() => startClose(s)}>Close & count</Button>
                              <Button variant="outline" onClick={() => showZ(s)}><FileText className="h-4 w-4 mr-1" />X-read</Button>
                            </>
                          ) : (
                            <Button className="flex-1 bg-green-600 hover:bg-green-700" onClick={() => startOpen(till)}><DoorOpen className="h-4 w-4 mr-1" />Open shift</Button>
                          )}
                        </div>
                      </CardContent>
                    </Card>
                  )
                })}
              </div>
            )}

            <Card>
              <CardHeader className="pb-2">
                <div className="flex flex-col sm:flex-row sm:items-end sm:justify-between gap-3">
                  <CardTitle className="text-base">Shift history</CardTitle>
                  <div className="flex flex-wrap items-end gap-2">
                    <Input type="date" className="h-9 w-40" value={from} onChange={(e) => setFrom(e.target.value)} />
                    <Input type="date" className="h-9 w-40" value={to} onChange={(e) => setTo(e.target.value)} />
                    <Button variant="outline" size="sm" className="h-9" onClick={() => void load()}>Show</Button>
                  </div>
                </div>
              </CardHeader>
              <CardContent className="p-0">
                {closedShifts.length === 0 ? (
                  <p className="p-6 text-sm text-center text-muted-foreground">No closed shifts in this period.</p>
                ) : (
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm min-w-[760px]">
                      <thead className="bg-gray-50 border-b"><tr>
                        <th className="text-left p-3">Shift</th><th className="text-left p-3">Till</th><th className="text-left p-3">Opened</th>
                        <th className="text-left p-3">Closed</th><th className="text-right p-3">Expected</th><th className="text-right p-3">Counted</th>
                        <th className="text-right p-3">Over / short</th><th className="text-right p-3">Dropped</th><th className="text-right p-3"></th>
                      </tr></thead>
                      <tbody>
                        {closedShifts.map((s) => (
                          <tr key={s.shiftId} className="border-b">
                            <td className="p-3 font-medium">{s.shiftNumber}</td>
                            <td className="p-3">{s.tillName}</td>
                            <td className="p-3 text-xs">{when(s.openedAt)}<div className="text-muted-foreground">{s.openedBy}</div></td>
                            <td className="p-3 text-xs">{when(s.closedAt)}<div className="text-muted-foreground">{s.closedBy}</div></td>
                            <td className="p-3 text-right">{gh(s.expectedCash ?? 0)}</td>
                            <td className="p-3 text-right">{gh(s.countedCash ?? 0)}</td>
                            <td className={`p-3 text-right font-semibold ${(s.variance ?? 0) < 0 ? "text-red-600" : (s.variance ?? 0) > 0 ? "text-amber-600" : "text-green-700"}`}>{gh(s.variance ?? 0)}</td>
                            <td className="p-3 text-right">{gh(s.dropAmount)}</td>
                            <td className="p-3 text-right"><Button variant="outline" size="sm" onClick={() => showZ(s)}>Z-report</Button></td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </CardContent>
            </Card>
          </div>
        </main>
      </div>

      {/* New till */}
      <Dialog open={newTillOpen} onOpenChange={setNewTillOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader><DialogTitle>New till</DialogTitle><DialogDescription>A cash drawer at the counter, e.g. "Front Till" or "Bar Till".</DialogDescription></DialogHeader>
          <div className="space-y-1.5"><Label>Name</Label><Input value={newTillName} onChange={(e) => setNewTillName(e.target.value)} className="h-10" placeholder="Front Till" /></div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setNewTillOpen(false)}>Cancel</Button>
            <Button className="bg-rose-600 hover:bg-rose-700" disabled={saving || !newTillName.trim()} onClick={createTill}>Create</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Open shift */}
      <Dialog open={!!openFor} onOpenChange={(o) => { if (!o) setOpenFor(null) }}>
        <DialogContent className="sm:max-w-md max-h-[92vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Open shift — {openFor?.name}</DialogTitle>
            <DialogDescription>The drawer already holds {gh(openFor?.currentBalance ?? 0)}. Add a float if the cashier needs change.</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div className="space-y-1.5"><Label>Float to add</Label>
                <Input type="number" inputMode="decimal" step="0.01" min={0} value={floatAmt} onChange={(e) => setFloatAmt(e.target.value)} className="h-10" placeholder="0.00" /></div>
              <div className="space-y-1.5"><Label>Taken from</Label>
                <Select value={floatFrom} onValueChange={setFloatFrom} disabled={num(floatAmt) <= 0}>
                  <SelectTrigger className="h-10"><SelectValue placeholder="Account" /></SelectTrigger>
                  <SelectContent>{sources.map((a) => <SelectItem key={a.cashAccountId} value={String(a.cashAccountId)}>{a.name} — {gh(a.currentBalance)}</SelectItem>)}</SelectContent>
                </Select></div>
            </div>
            <div className="space-y-1.5"><Label>Notes</Label><Input value={openNotes} onChange={(e) => setOpenNotes(e.target.value)} className="h-10" /></div>
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setOpenFor(null)}>Cancel</Button>
            <Button className="bg-green-600 hover:bg-green-700" disabled={saving} onClick={submitOpen}>{saving && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}Open shift</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Close shift */}
      <Dialog open={!!closeFor} onOpenChange={(o) => { if (!o) setCloseFor(null) }}>
        <DialogContent className="sm:max-w-md max-h-[92vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Close & count — {closeFor?.tillName}</DialogTitle>
            <DialogDescription>Count every note and coin in the drawer. Any difference from what the system expects is recorded as over or short.</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="rounded-lg bg-gray-50 p-3 flex justify-between text-sm"><span>System expects</span><b>{gh(expected)}</b></div>
            <div className="space-y-1.5"><Label>Cash counted</Label>
              <Input type="number" inputMode="decimal" step="0.01" min={0} value={counted} onChange={(e) => setCounted(e.target.value)} className="h-12 text-lg font-bold text-center" /></div>
            {counted !== "" && (
              <div className={`rounded-lg p-3 text-sm text-center font-medium ${variance === 0 ? "bg-green-50 text-green-800" : variance > 0 ? "bg-amber-50 text-amber-800" : "bg-red-50 text-red-800"}`}>
                {variance === 0 ? "The drawer balances." : `${variance > 0 ? "Over" : "Short"} by ${gh(Math.abs(variance))}`}
              </div>
            )}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div className="space-y-1.5"><Label>Drop to safe / bank</Label>
                <Input type="number" inputMode="decimal" step="0.01" min={0} value={dropAmt} onChange={(e) => setDropAmt(e.target.value)} className="h-10" placeholder="0.00" />
                {counted !== "" && closeFor && <button type="button" className="text-xs text-rose-700 underline" onClick={() => setDropAmt(Math.max(0, countedNum - closeFor.openingFloat).toFixed(2))}>Leave the float ({gh(closeFor.openingFloat)}) in the till</button>}
              </div>
              <div className="space-y-1.5"><Label>Drop into</Label>
                <Select value={dropTo} onValueChange={setDropTo} disabled={dropNum <= 0}>
                  <SelectTrigger className="h-10"><SelectValue placeholder="Account" /></SelectTrigger>
                  <SelectContent>{sources.map((a) => <SelectItem key={a.cashAccountId} value={String(a.cashAccountId)}>{a.name}</SelectItem>)}</SelectContent>
                </Select></div>
            </div>
            <div className="space-y-1.5"><Label>Notes</Label><Input value={closeNotes} onChange={(e) => setCloseNotes(e.target.value)} className="h-10" placeholder={variance < 0 ? "Why is it short?" : ""} /></div>
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setCloseFor(null)}>Cancel</Button>
            <Button className="bg-rose-600 hover:bg-rose-700" disabled={saving || counted === ""} onClick={submitClose}>{saving && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}Close shift</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Z-report (X-read while open) */}
      <Dialog open={!!zFor} onOpenChange={(o) => { if (!o) setZFor(null) }}>
        <DialogContent className="sm:max-w-md max-h-[92vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{zShift?.status === "Open" ? "X-read (shift still open)" : "Z-report"}</DialogTitle>
            <DialogDescription>{zShift?.tillName} · {zShift?.shiftNumber}</DialogDescription>
          </DialogHeader>
          {zShift && (
            <div id="z-report" className="font-mono text-xs border rounded-lg p-3 bg-white">
              <h2 style={{ textAlign: "center", fontWeight: "bold" }}>{zShift.tillName} — {zShift.shiftNumber}</h2>
              <div className="row flex justify-between"><span>Opened</span><span>{when(zShift.openedAt)}</span></div>
              <div className="row flex justify-between"><span>By</span><span>{zShift.openedBy ?? "—"}</span></div>
              {zShift.closedAt && <div className="row flex justify-between"><span>Closed</span><span>{when(zShift.closedAt)}</span></div>}
              <div className="sec mt-2 border-t border-dashed pt-1 font-bold">DRAWER</div>
              {zLines.filter((l) => l.section === "Drawer").map((l) => (
                <div key={l.label} className="row flex justify-between"><span>{l.label} ({l.txnCount})</span><span>{gh(l.amount)}</span></div>
              ))}
              <div className="sec mt-2 border-t border-dashed pt-1 font-bold">CASH-UP</div>
              <div className="row flex justify-between"><span>Opening float</span><span>{gh(zShift.openingFloat)}</span></div>
              {zShift.status === "Closed" ? (
                <>
                  <div className="row flex justify-between"><span>Expected</span><span>{gh(zShift.expectedCash ?? 0)}</span></div>
                  <div className="row flex justify-between"><span>Counted</span><span>{gh(zShift.countedCash ?? 0)}</span></div>
                  <div className="row flex justify-between font-bold"><span>Over / short</span><span>{gh(zShift.variance ?? 0)}</span></div>
                  <div className="row flex justify-between"><span>Dropped</span><span>{gh(zShift.dropAmount)}</span></div>
                  <div className="row flex justify-between"><span>Left in till</span><span>{gh(zShift.closingBalance ?? 0)}</span></div>
                </>
              ) : (
                <div className="row flex justify-between"><span>In drawer now</span><span>{gh(zShift.currentBalance)}</span></div>
              )}
              <div className="sec mt-2 border-t border-dashed pt-1 font-bold">TAKINGS WHILE OPEN (ALL METHODS)</div>
              {zLines.filter((l) => l.section === "Takings").length === 0 && <div className="text-muted-foreground">None</div>}
              {zLines.filter((l) => l.section === "Takings").map((l) => (
                <div key={l.label} className="row flex justify-between"><span>{l.label} ({l.txnCount})</span><span>{gh(l.amount)}</span></div>
              ))}
            </div>
          )}
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setZFor(null)}>Close</Button>
            <Button className="bg-rose-600 hover:bg-rose-700" onClick={printZ}><Printer className="h-4 w-4 mr-1" />Print</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
