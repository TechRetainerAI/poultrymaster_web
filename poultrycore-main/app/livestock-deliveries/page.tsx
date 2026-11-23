"use client"

// Deliveries -- send sales out with a driver, and take in what the driver
// collected when they come back (each amount is paid against its sale). The
// driver report shows what each driver collected and what is short.

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { Plus, Truck } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Checkbox } from "@/components/ui/checkbox"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { useToast } from "@/hooks/use-toast"
import {
  cancelDelivery, getDeliveryOptions, getDriverReport, listDeliveries, listFleet, returnDelivery, sendOutDelivery,
  type Delivery, type DeliveryOption, type DriverReportRow, type FleetItem,
} from "@/lib/api/livestock"
import { AccountSelect, PeriodPicker, daysAgo, useCashAccounts } from "@/components/livestock/money-bits"
import { AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, fmtDate, fmtMoney, todayIso } from "@/components/livestock/livestock-page"

const NONE = "__none"

export default function LivestockDeliveriesPage() {
  const { toast } = useToast()
  const [rows, setRows] = useState<Delivery[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [sending, setSending] = useState(false)
  const [returning, setReturning] = useState<Delivery | null>(null)
  const [from, setFrom] = useState(daysAgo(30))
  const [to, setTo] = useState(todayIso())
  const [report, setReport] = useState<DriverReportRow[]>([])

  const load = useCallback(async () => {
    setError(null)
    try {
      const [d, r] = await Promise.all([listDeliveries({ from, to }), getDriverReport(from, to)])
      setRows(d); setReport(r)
    } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [from, to])
  useEffect(() => { load() }, [load])
  const out = (rows ?? []).filter((d) => d.status === "Out")
  const pg = usePagination(rows ?? [], 10)

  return (
    <LivestockPage title="Deliveries" description="Sales out with a driver, and what they bring back." icon={Truck}
      actions={
        <>
          <Button asChild variant="outline"><Link href="/livestock-delivery-setup">Drivers & vehicles</Link></Button>
          <Button className={AMBER_BUTTON} onClick={() => setSending(true)}><Plus className="h-4 w-4 mr-1" /> Send out</Button>
        </>
      }>
      <PeriodPicker from={from} to={to} onChange={(a, b) => { setFrom(a); setTo(b) }} />
      {error ? <LoadError message={error} onRetry={load} /> : !rows ? <Loading /> : (
        <Tabs defaultValue="deliveries">
          <TabsList><TabsTrigger value="deliveries">Deliveries ({out.length} out)</TabsTrigger><TabsTrigger value="drivers">Driver report</TabsTrigger></TabsList>
          <TabsContent value="deliveries" className="pt-3">
            {rows.length === 0 ? <EmptyState title="No deliveries in these dates" /> : (
              <div className="rounded-md border bg-white overflow-x-auto">
                <Table>
                  <TableHeader><TableRow><TableHead>Date</TableHead><TableHead>Driver</TableHead><TableHead>Vehicle / route</TableHead><TableHead>Customers</TableHead><TableHead className="text-right">To collect</TableHead><TableHead className="text-right">Collected</TableHead><TableHead>Status</TableHead><TableHead /></TableRow></TableHeader>
                  <TableBody>
                    {pg.pageItems.map((d) => (
                      <TableRow key={d.deliveryId} className={d.status === "Cancelled" ? "opacity-50" : undefined}>
                        <TableCell>{fmtDate(d.date)}</TableCell>
                        <TableCell className="font-medium">{d.driverName}</TableCell>
                        <TableCell className="text-sm">{[d.vehicle, d.routeName].filter(Boolean).join(" · ") || "—"}</TableCell>
                        <TableCell className="text-sm text-stone-600 max-w-xs truncate">{d.sales.map((s) => s.customerName).join(", ")}</TableCell>
                        <TableCell className="text-right">{fmtMoney(d.expected)}</TableCell>
                        <TableCell className={`text-right ${(d.shortage ?? 0) > 0 ? "text-rose-700" : ""}`}>{d.collected != null ? fmtMoney(d.collected) : "—"}{(d.shortage ?? 0) > 0 && <div className="text-xs">short {fmtMoney(d.shortage)}</div>}</TableCell>
                        <TableCell><Badge className={d.status === "Out" ? "bg-amber-600" : d.status === "Returned" ? "bg-emerald-600" : "bg-stone-400"}>{d.status === "Out" ? "Out" : d.status === "Returned" ? "Back" : "Cancelled"}</Badge></TableCell>
                        <TableCell className="text-right whitespace-nowrap">
                          {d.status === "Out" && <Button size="sm" className={AMBER_BUTTON} onClick={() => setReturning(d)}>Driver back</Button>}
                          {d.status === "Out" && <Button size="sm" variant="ghost" onClick={async () => { try { await cancelDelivery(d.deliveryId); load() } catch (e: any) { toast({ title: "Not cancelled", description: e?.message, variant: "destructive" }) } }}>Cancel</Button>}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
                <DataPagination {...pg.paginationProps} variant="records" />
              </div>
            )}
          </TabsContent>
          <TabsContent value="drivers" className="pt-3">
            {report.length === 0 ? <EmptyState title="No drivers yet" /> : (
              <Card>
                <CardHeader className="pb-2"><CardTitle className="text-base">What each driver collected</CardTitle></CardHeader>
                <CardContent>
                  <Table>
                    <TableHeader><TableRow><TableHead>Driver</TableHead><TableHead className="text-right">Deliveries</TableHead><TableHead className="text-right">Still out</TableHead><TableHead className="text-right">To collect</TableHead><TableHead className="text-right">Collected</TableHead><TableHead className="text-right">Short</TableHead></TableRow></TableHeader>
                    <TableBody>
                      {report.map((r) => (
                        <TableRow key={r.driverId}>
                          <TableCell className="font-medium">{r.name}</TableCell><TableCell className="text-right">{r.deliveries}</TableCell>
                          <TableCell className="text-right">{r.stillOut || ""}</TableCell><TableCell className="text-right">{fmtMoney(r.expected)}</TableCell>
                          <TableCell className="text-right">{fmtMoney(r.collected)}</TableCell>
                          <TableCell className={`text-right ${r.short > 0 ? "text-rose-700 font-medium" : ""}`}>{r.short ? fmtMoney(r.short) : "—"}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </CardContent>
              </Card>
            )}
          </TabsContent>
        </Tabs>
      )}
      {sending && <SendDialog onClose={() => setSending(false)} onDone={() => { setSending(false); load() }} />}
      {returning && <ReturnDialog delivery={returning} onClose={() => setReturning(null)} onDone={() => { setReturning(null); load() }} />}
    </LivestockPage>
  )
}

function SendDialog({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const { toast } = useToast()
  const [opts, setOpts] = useState<DeliveryOption[]>([])
  const [drivers, setDrivers] = useState<FleetItem[]>([])
  const [vehicles, setVehicles] = useState<FleetItem[]>([])
  const [routes, setRoutes] = useState<FleetItem[]>([])
  const [driverId, setDriverId] = useState<number | null>(null)
  const [vehicleId, setVehicleId] = useState<number | null>(null)
  const [routeId, setRouteId] = useState<number | null>(null)
  const [date, setDate] = useState(todayIso())
  const [picked, setPicked] = useState<Set<number>>(new Set())
  const [notes, setNotes] = useState("")
  const [saving, setSaving] = useState(false)
  useEffect(() => {
    getDeliveryOptions().then(setOpts).catch(() => setOpts([]))
    listFleet("drivers").then(setDrivers).catch(() => setDrivers([]))
    listFleet("vehicles").then(setVehicles).catch(() => setVehicles([]))
    listFleet("routes").then(setRoutes).catch(() => setRoutes([]))
  }, [])
  const total = useMemo(() => opts.filter((o) => picked.has(o.saleId)).reduce((s, o) => s + o.owed, 0), [opts, picked])
  const save = async () => {
    setSaving(true)
    try { await sendOutDelivery({ date, driverId: driverId!, vehicleId, routeId, notes: notes.trim() || null, saleIds: [...picked] }); toast({ title: "Sent out" }); onDone() }
    catch (e: any) { toast({ title: "Not sent", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setSaving(false) }
  }
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-2xl">
        <DialogHeader><DialogTitle>Send out a delivery</DialogTitle></DialogHeader>
        <div className="space-y-3 max-h-[70vh] overflow-y-auto pr-1">
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <div>
              <Label>Driver</Label>
              <Select value={driverId ? String(driverId) : ""} onValueChange={(v) => setDriverId(Number(v))}>
                <SelectTrigger><SelectValue placeholder={drivers.length ? "Choose" : "Add a driver"} /></SelectTrigger>
                <SelectContent>{drivers.map((d) => <SelectItem key={d.id} value={String(d.id)}>{d.name}</SelectItem>)}</SelectContent>
              </Select>
            </div>
            <div>
              <Label>Vehicle</Label>
              <Select value={vehicleId ? String(vehicleId) : NONE} onValueChange={(v) => setVehicleId(v === NONE ? null : Number(v))}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent><SelectItem value={NONE}>None</SelectItem>{vehicles.map((d) => <SelectItem key={d.id} value={String(d.id)}>{d.name}</SelectItem>)}</SelectContent>
              </Select>
            </div>
            <div>
              <Label>Route</Label>
              <Select value={routeId ? String(routeId) : NONE} onValueChange={(v) => setRouteId(v === NONE ? null : Number(v))}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent><SelectItem value={NONE}>None</SelectItem>{routes.map((d) => <SelectItem key={d.id} value={String(d.id)}>{d.name}</SelectItem>)}</SelectContent>
              </Select>
            </div>
            <div><Label htmlFor="dl-date">Date</Label><Input id="dl-date" type="date" max={todayIso()} value={date} onChange={(e) => setDate(e.target.value)} /></div>
          </div>
          <div>
            <Label>Sales going out</Label>
            {opts.length === 0 ? <p className="text-sm text-stone-500 mt-1">No customer sales to deliver. Record the sales first.</p> : (
              <div className="rounded-md border mt-1 divide-y">
                {opts.map((o) => (
                  <label key={o.saleId} className="flex items-center justify-between gap-3 px-3 py-2 text-sm">
                    <span className="flex items-center gap-2">
                      <Checkbox checked={picked.has(o.saleId)} onCheckedChange={(c) => setPicked((p) => { const n = new Set(p); if (c) n.add(o.saleId); else n.delete(o.saleId); return n })} />
                      {o.customerName}{o.customerPhone ? ` · ${o.customerPhone}` : ""} <span className="text-stone-500">{fmtDate(o.date)}</span>
                    </span>
                    <span>{o.owed > 0 ? `${fmtMoney(o.owed)} to collect` : "paid"}</span>
                  </label>
                ))}
              </div>
            )}
            {picked.size > 0 && <p className="text-sm mt-1">Driver should bring back <strong>{fmtMoney(total)}</strong>.</p>}
          </div>
          <div><Label htmlFor="dl-notes">Notes</Label><Textarea id="dl-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} /></div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || !driverId || picked.size === 0} onClick={save}>{saving ? "Sending…" : "Send out"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function ReturnDialog({ delivery, onClose, onDone }: { delivery: Delivery; onClose: () => void; onDone: () => void }) {
  const { toast } = useToast()
  const { accounts, defaultId } = useCashAccounts()
  const [accountId, setAccountId] = useState<number | null>(null)
  const [amounts, setAmounts] = useState<Record<number, string>>(() => Object.fromEntries(delivery.sales.map((s) => [s.saleId, s.owedNow > 0 ? String(s.owedNow) : ""])))
  const [notes, setNotes] = useState("")
  const [saving, setSaving] = useState(false)
  useEffect(() => { if (!accountId && defaultId) setAccountId(defaultId) }, [defaultId, accountId])
  const total = delivery.sales.reduce((s, x) => s + (Number(amounts[x.saleId]) || 0), 0)
  const short = delivery.expected - total
  const save = async () => {
    setSaving(true)
    try {
      await returnDelivery(delivery.deliveryId, { accountId: total > 0 ? accountId : null, notes: notes.trim() || null,
        collections: delivery.sales.map((s) => ({ saleId: s.saleId, amount: Number(amounts[s.saleId]) || 0 })) })
      toast({ title: `${delivery.driverName} handed in ${fmtMoney(total)}` }); onDone()
    } catch (e: any) { toast({ title: "Not saved", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setSaving(false) }
  }
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-xl">
        <DialogHeader><DialogTitle>{delivery.driverName} is back</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <Table>
            <TableHeader><TableRow><TableHead>Customer</TableHead><TableHead className="text-right">Owed</TableHead><TableHead className="w-32">Collected</TableHead></TableRow></TableHeader>
            <TableBody>
              {delivery.sales.map((s) => (
                <TableRow key={s.saleId}>
                  <TableCell><Link className="text-amber-800 hover:underline" href={`/livestock-sales/${s.saleId}`}>{s.customerName}</Link></TableCell>
                  <TableCell className="text-right">{fmtMoney(s.owedNow)}</TableCell>
                  <TableCell><Input type="number" min={0} max={s.owedNow} step="0.01" disabled={s.owedNow <= 0} value={amounts[s.saleId] ?? ""}
                    onChange={(e) => setAmounts((a) => ({ ...a, [s.saleId]: e.target.value }))} /></TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
          <p className="text-sm">Handed in <strong>{fmtMoney(total)}</strong> of {fmtMoney(delivery.expected)}{short > 0 && <span className="text-rose-700"> · short {fmtMoney(short)}</span>}</p>
          {total > 0 && <AccountSelect label="Money went into" value={accountId} onChange={setAccountId} accounts={accounts} />}
          <div><Label htmlFor="rt-notes">{short > 0 ? "What happened to the rest (required)" : "Notes"}</Label><Textarea id="rt-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} /></div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || (total > 0 && !accountId) || (short > 0 && !notes.trim())} onClick={save}>{saving ? "Saving…" : "Save"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
