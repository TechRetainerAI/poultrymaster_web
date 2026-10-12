"use client"

// Egg stock by class + one coherent ledger (Egg Tracker, migrations 341-343).
//
// Every egg class -- Unsorted / General and each size -- is a product in the
// same stock ledger, so this reads the ledger rows directly: production into
// Unsorted, sorting out of Unsorted and into sizes, sales and internal use out
// of the class they used, reversals, adjustments. One running balance per
// class. Hidden for a farm that has never set up sizes (it has one class).

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { Loader2, PackageMinus } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Textarea } from "@/components/ui/textarea"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { useEggsPerCrate } from "@/hooks/use-eggs-per-crate"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { cn } from "@/lib/utils"
import {
  EggSortingConflictError,
  adjustEggClass,
  getEggClasses,
  getEggLedger,
  type AdjustmentKind,
  type EggClass,
  type EggLedgerRow,
} from "@/lib/api/egg-sorting"
import { TXN_LABEL, cratesText, fmtCount } from "@/lib/production/egg-sorting"
import { formatLongDate } from "@/lib/closing/daily-closing"

const TYPE_FILTERS: { key: string; label: string; match: (t: string) => boolean }[] = [
  { key: "all", label: "All movements", match: () => true },
  { key: "production", label: "Production", match: (t) => t === "Production" },
  { key: "sorting", label: "Sorting", match: (t) => t.startsWith("Sorting") },
  { key: "sale", label: "Sales", match: (t) => t === "Sale" || t === "Sale Reversal" || t.startsWith("Driver") || t.startsWith("Delivery") },
  { key: "internal", label: "Internal use", match: (t) => t === "InternalUse" },
  { key: "adjustment", label: "Adjustments & losses", match: (t) => /adjust|increase|decrease|opening|restock|egg loss/i.test(t) },
]

const KINDS: { key: AdjustmentKind; label: string; hint: string }[] = [
  { key: "Breakage", label: "Breakage", hint: "Eggs broken in the store or on the way — taken out." },
  { key: "Loss", label: "Loss", hint: "Eggs missing, spoiled or thrown away — taken out." },
  { key: "Stocktake", label: "Stock-take", hint: "Counted stock differs: + found, − missing." },
  { key: "Correction", label: "Correction", hint: "Fix a recording mistake: + or −." },
]

export function EggClassLedger() {
  useEggsPerCrate()   // re-render crate figures when the farm's crate size loads
  const { toast } = useToast()
  const permissions = usePermissions()
  const canAdjust = permissions.can("poultry.egg-sorting.edit") || permissions.canEdit
  const [adjOpen, setAdjOpen] = useState(false)
  const [adjClass, setAdjClass] = useState<string>("")
  const [adjKind, setAdjKind] = useState<AdjustmentKind>("Breakage")
  const [adjQty, setAdjQty] = useState("")
  const [adjReason, setAdjReason] = useState("")
  const [adjBusy, setAdjBusy] = useState(false)
  const [reloadKey, setReloadKey] = useState(0)
  const [classes, setClasses] = useState<EggClass[] | null>(null)
  const [rows, setRows] = useState<EggLedgerRow[] | null>(null)
  const [classFilter, setClassFilter] = useState("all")
  const [typeFilter, setTypeFilter] = useState("all")
  const [from, setFrom] = useState("")
  const [to, setTo] = useState("")
  const [flock, setFlock] = useState("all")

  const loadClasses = useCallback(() => {
    getEggClasses({ includeInactive: true }).then(setClasses).catch(() => setClasses([]))
  }, [])
  useEffect(() => { loadClasses() }, [loadClasses, reloadKey])
  const multiClass = (classes ?? []).some((c) => c.classKind === "Size")

  useEffect(() => {
    if (!multiClass) return
    setRows(null)
    getEggLedger({ fromDate: from || undefined, toDate: to || undefined, productId: classFilter === "all" ? null : Number(classFilter) })
      .then(setRows).catch(() => setRows([]))
  }, [multiClass, from, to, classFilter, reloadKey])

  const flocks = useMemo(() => {
    const m = new Map<number, string>()
    for (const r of rows ?? []) if (r.flockId) m.set(r.flockId, r.flockName ?? `Flock ${r.flockId}`)
    return [...m.entries()].sort((a, b) => a[1].localeCompare(b[1]))
  }, [rows])

  const shown = useMemo(() => {
    const f = TYPE_FILTERS.find((x) => x.key === typeFilter) ?? TYPE_FILTERS[0]
    return (rows ?? []).filter((r) => f.match(r.txnType) && (flock === "all" || String(r.flockId) === flock))
  }, [rows, typeFilter, flock])

  if (!classes || !multiClass) return null

  const adjQtyN = Number(adjQty)
  const outOnly = adjKind === "Breakage" || adjKind === "Loss"
  const adjValid = Number.isInteger(adjQtyN) && adjQtyN !== 0 && (!outOnly || adjQtyN > 0) && adjClass !== "" && adjReason.trim() !== ""
  const adjTarget = classes.find((c) => String(c.poultryProductId) === adjClass)
  const adjDelta = outOnly ? -Math.abs(adjQtyN) : adjQtyN

  const submitAdjust = async () => {
    if (!adjTarget) return
    setAdjBusy(true)
    try {
      await adjustEggClass({ poultryProductId: adjTarget.poultryProductId, kind: adjKind, quantity: adjQtyN, reason: adjReason.trim() })
      toast({
        title: "Egg stock adjusted",
        description: `${adjTarget.classKind === "Unsorted" ? "Unsorted / General" : adjTarget.name}: ${adjDelta > 0 ? "+" : "−"}${fmtCount(Math.abs(adjDelta))} eggs.`,
      })
      setAdjOpen(false)
      setReloadKey((k) => k + 1)
    } catch (e) {
      toast({ title: e instanceof EggSortingConflictError ? "Not enough eggs" : "Not adjusted", description: e instanceof Error ? e.message : "", variant: "destructive" })
    } finally {
      setAdjBusy(false)
    }
  }

  const unsorted = classes.find((c) => c.classKind === "Unsorted")
  const sizes = classes.filter((c) => c.classKind === "Size" && (c.isActive || c.onHand !== 0))
  const sizedTotal = sizes.reduce((s, c) => s + c.onHand, 0)

  return (
    <div className="space-y-4">
      <Card className="bg-white">
        <CardHeader className="pb-2">
          <div className="flex flex-wrap items-start justify-between gap-2">
            <CardTitle className="text-base">Egg stock by class</CardTitle>
            {canAdjust && (
              <Button size="sm" variant="outline" onClick={() => { setAdjClass(""); setAdjKind("Breakage"); setAdjQty(""); setAdjReason(""); setAdjOpen(true) }}>
                <PackageMinus className="mr-1.5 h-4 w-4" /> Record loss / adjustment
              </Button>
            )}
          </div>
          <CardDescription>
            Production adds to Unsorted. The <Link href="/poultry-egg-sorting" className="text-amber-700 underline">Egg Sorting Workspace</Link> moves
            Unsorted eggs into sizes; sales and internal use take from the class they name.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-5">
            <ClassTile label="Unsorted / General" eggs={unsorted?.onHand ?? 0} highlight />
            {sizes.map((c) => <ClassTile key={c.poultryProductId} label={c.name} eggs={c.onHand} muted={!c.isActive} />)}
            <ClassTile label="Total saleable" eggs={(unsorted?.onHand ?? 0) + sizedTotal} strong />
          </div>
        </CardContent>
      </Card>

      <Card className="bg-white">
        <CardHeader className="pb-2">
          <CardTitle className="text-base">Egg ledger by class</CardTitle>
          <CardDescription>Every stock movement of every egg class, with a running balance per class. Nothing is deleted: reversals appear as their own rows.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-5">
            <div className="space-y-1">
              <Label className="text-xs text-slate-500">Class</Label>
              <Select value={classFilter} onValueChange={setClassFilter}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All classes</SelectItem>
                  {classes.map((c) => (
                    <SelectItem key={c.poultryProductId} value={String(c.poultryProductId)}>
                      {c.classKind === "Unsorted" ? "Unsorted / General" : c.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label className="text-xs text-slate-500">Movement</Label>
              <Select value={typeFilter} onValueChange={setTypeFilter}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{TYPE_FILTERS.map((t) => <SelectItem key={t.key} value={t.key}>{t.label}</SelectItem>)}</SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label className="text-xs text-slate-500">Flock</Label>
              <Select value={flock} onValueChange={setFlock}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All flocks</SelectItem>
                  {flocks.map(([id, name]) => <SelectItem key={id} value={String(id)}>{name}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label className="text-xs text-slate-500">Recorded from</Label>
              <Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
            </div>
            <div className="space-y-1">
              <Label className="text-xs text-slate-500">Recorded to</Label>
              <Input type="date" value={to} onChange={(e) => setTo(e.target.value)} />
            </div>
          </div>

          {!rows ? (
            <p className="flex items-center gap-2 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading ledger…</p>
          ) : (
            <div className="max-h-[32rem] overflow-auto rounded-lg border border-slate-200">
              <table className="w-full min-w-[56rem] text-sm">
                <thead className="sticky top-0 bg-slate-50 text-left text-xs uppercase tracking-wider text-slate-500">
                  <tr>
                    <th className="px-3 py-2 font-medium">Business date</th>
                    <th className="px-3 py-2 font-medium">Movement</th>
                    <th className="px-3 py-2 font-medium">Class</th>
                    <th className="px-3 py-2 text-right font-medium">In</th>
                    <th className="px-3 py-2 text-right font-medium">Out</th>
                    <th className="px-3 py-2 text-right font-medium">Balance</th>
                    <th className="px-3 py-2 font-medium">Flock</th>
                    <th className="px-3 py-2 font-medium">Reference</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {shown.length === 0 && <tr><td colSpan={8} className="px-3 py-4 text-slate-500">No movements match.</td></tr>}
                  {shown.slice(0, 500).map((r) => (
                    <tr key={r.transactionId}>
                      <td className="whitespace-nowrap px-3 py-1.5">{formatLongDate(r.businessDate.slice(0, 10))}</td>
                      <td className="px-3 py-1.5">
                        {TXN_LABEL[r.txnType] ?? r.txnType}
                        {r.pickNumbers && <span className="ml-1 text-xs text-slate-500">({r.pickNumbers})</span>}
                      </td>
                      <td className="px-3 py-1.5">{r.classKind === "Unsorted" ? "Unsorted" : r.className}</td>
                      <td className="px-3 py-1.5 text-right tabular-nums text-emerald-700">{r.quantityIn ? fmtCount(r.quantityIn) : ""}</td>
                      <td className="px-3 py-1.5 text-right tabular-nums text-rose-700">{r.quantityOut ? fmtCount(r.quantityOut) : ""}</td>
                      <td className="px-3 py-1.5 text-right font-medium tabular-nums">{fmtCount(r.runningBalance)}</td>
                      <td className="px-3 py-1.5">{r.flockName ?? ""}</td>
                      <td className="px-3 py-1.5 text-xs text-slate-600">
                        {r.reference ?? ""}{r.customerName ? ` · ${r.customerName}` : ""}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
              {shown.length > 500 && <p className="px-3 py-2 text-xs text-slate-500">Showing the latest 500 of {shown.length.toLocaleString()} movements — narrow the dates to see older ones.</p>}
            </div>
          )}
        </CardContent>
      </Card>

      <Dialog open={adjOpen} onOpenChange={(v) => { if (!adjBusy) setAdjOpen(v) }}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Record egg loss or adjustment</DialogTitle>
            <DialogDescription>
              Against one egg class. Eggs lost while grading belong on the sorting itself, not here.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            <div className="space-y-1">
              <Label className="text-xs text-slate-500">Egg class</Label>
              <Select value={adjClass} onValueChange={setAdjClass}>
                <SelectTrigger><SelectValue placeholder="Choose a class" /></SelectTrigger>
                <SelectContent>
                  {classes.filter((c) => c.classKind === "Unsorted" || c.isActive || c.onHand !== 0).map((c) => (
                    <SelectItem key={c.poultryProductId} value={String(c.poultryProductId)}>
                      {c.classKind === "Unsorted" ? "Unsorted / General" : c.name} — {fmtCount(c.onHand)} on hand
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label className="text-xs text-slate-500">What happened</Label>
              <Select value={adjKind} onValueChange={(v) => setAdjKind(v as AdjustmentKind)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{KINDS.map((k) => <SelectItem key={k.key} value={k.key}>{k.label}</SelectItem>)}</SelectContent>
              </Select>
              <p className="text-xs text-slate-500">{KINDS.find((k) => k.key === adjKind)?.hint}</p>
            </div>
            <div className="space-y-1">
              <Label htmlFor="adj-qty" className="text-xs text-slate-500">{outOnly ? "Eggs lost" : "Eggs (+ found / − missing)"}</Label>
              <Input id="adj-qty" inputMode="numeric" value={adjQty} placeholder={outOnly ? "e.g. 30" : "e.g. -12"}
                onChange={(e) => setAdjQty(e.target.value.replace(outOnly ? /[^\d]/g : /[^\d-]/g, ""))} />
              {adjTarget && Number.isInteger(adjQtyN) && adjQtyN !== 0 && (
                <p className="text-xs text-slate-500">
                  {fmtCount(adjTarget.onHand)} → {fmtCount(adjTarget.onHand + adjDelta)} eggs
                  {adjTarget.onHand + adjDelta < 0 && <span className="text-rose-700"> — more than is in stock</span>}
                </p>
              )}
            </div>
            <div className="space-y-1">
              <Label htmlFor="adj-reason" className="text-xs text-slate-500">Reason *</Label>
              <Textarea id="adj-reason" rows={2} value={adjReason} onChange={(e) => setAdjReason(e.target.value)} placeholder="e.g. tray dropped in the store" />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setAdjOpen(false)} disabled={adjBusy}>Cancel</Button>
            <Button onClick={() => void submitAdjust()} disabled={!adjValid || adjBusy}>
              {adjBusy && <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />} Record
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

function ClassTile({ label, eggs, highlight, strong, muted }: { label: string; eggs: number; highlight?: boolean; strong?: boolean; muted?: boolean }) {
  return (
    <div className={cn("rounded-lg border px-3 py-2", highlight ? "border-amber-200 bg-amber-50" : strong ? "border-emerald-200 bg-emerald-50" : "border-slate-200 bg-white", muted && "opacity-60")}>
      <div className="text-[11px] uppercase tracking-wide text-slate-500">{label}</div>
      <div className={cn("tabular-nums", strong ? "text-lg font-bold" : "font-semibold")}>{fmtCount(eggs)}</div>
      <div className="text-[11px] text-slate-500">{cratesText(eggs)}</div>
    </div>
  )
}
