"use client"

// Losses -- the poultry Loss & Damage page for livestock: stock that was
// spoiled, expired, spilled, stolen or damaged (and what it was worth), and
// the animals that died or were culled, by group.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { PackageMinus, Plus } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { useToast } from "@/hooks/use-toast"
import { getLosses, listItems, recordLoss, type LivestockItem, type LossReason, type Losses } from "@/lib/api/livestock"
import { LOSS_REASON_LABEL } from "@/components/livestock/labels"
import { AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, StatCard, fmtDate, fmtMoney, fmtNum, todayIso } from "@/components/livestock/livestock-page"

const daysAgo = (n: number) => { const d = new Date(); d.setDate(d.getDate() - n); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}` }

export default function LivestockLossesPage() {
  const [data, setData] = useState<Losses | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [from, setFrom] = useState(daysAgo(30))
  const [to, setTo] = useState(todayIso())
  const [adding, setAdding] = useState(false)

  const load = useCallback(async () => {
    setError(null)
    try { setData(await getLosses(from, to)) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [from, to])
  useEffect(() => { load() }, [load])

  const deaths = (data?.animals ?? []).reduce((s, a) => s + a.deaths, 0)
  const culls = (data?.animals ?? []).reduce((s, a) => s + a.culls, 0)

  const stockPg = usePagination(data?.stock ?? [], 10)
  const animalsPg = usePagination(data?.animals ?? [], 10)
  return (
    <LivestockPage title="Losses" description="Stock lost or damaged, and animals that died or were culled." icon={PackageMinus}
      actions={<Button className={AMBER_BUTTON} onClick={() => setAdding(true)}><Plus className="h-4 w-4 mr-1" /> Record stock loss</Button>}>
      <div className="flex items-center gap-2">
        <Input type="date" className="w-40" value={from} max={to} onChange={(e) => setFrom(e.target.value)} aria-label="From" />
        <span className="text-sm text-stone-500">to</span>
        <Input type="date" className="w-40" value={to} min={from} max={todayIso()} onChange={(e) => setTo(e.target.value)} aria-label="To" />
      </div>
      {error ? <LoadError message={error} onRetry={load} /> : !data ? <Loading /> : (
        <>
          <div className="grid grid-cols-2 lg:grid-cols-3 gap-3">
            <StatCard label="Stock lost (value)" value={fmtMoney(data.stockValue)} tone={data.stockValue > 0 ? "rose" : "stone"} />
            <StatCard label="Animals died" value={fmtNum(deaths)} tone={deaths ? "rose" : "stone"} />
            <StatCard label="Animals culled" value={fmtNum(culls)} />
          </div>
          <Card>
            <CardHeader className="pb-2"><CardTitle className="text-base">Stock lost</CardTitle></CardHeader>
            <CardContent>
              {data.stock.length === 0 ? <p className="text-sm text-stone-500">No stock lost in these dates.</p> : (
                <>
                <Table>
                  <TableHeader><TableRow><TableHead>Date</TableHead><TableHead>Item</TableHead><TableHead>Why</TableHead><TableHead className="text-right">Quantity</TableHead><TableHead className="text-right">Value</TableHead></TableRow></TableHeader>
                  <TableBody>
                    {stockPg.pageItems.map((s) => (
                      <TableRow key={s.movementId} className={s.reversedAt ? "opacity-50" : undefined}>
                        <TableCell>{fmtDate(s.date)}</TableCell>
                        <TableCell><Link className="text-amber-800 hover:underline" href={`/livestock-items/${s.itemId}`}>{s.itemName}</Link></TableCell>
                        <TableCell>{LOSS_REASON_LABEL[s.reason]}{s.notes && <span className="text-stone-500"> · {s.notes}</span>}{s.reversedAt && <Badge variant="outline" className="ml-2">Reversed</Badge>}</TableCell>
                        <TableCell className="text-right">{fmtNum(s.quantity)} {s.unit}</TableCell>
                        <TableCell className="text-right">{fmtMoney(s.value)}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
                <DataPagination {...stockPg.paginationProps} variant="records" />
                </>
              )}
            </CardContent>
          </Card>
          <Card>
            <CardHeader className="pb-2"><CardTitle className="text-base">Animals lost, by group</CardTitle></CardHeader>
            <CardContent>
              {data.animals.length === 0 ? <EmptyState title="No animals lost in these dates" /> : (
                <>
                <Table>
                  <TableHeader><TableRow><TableHead>Group</TableHead><TableHead className="text-right">Died</TableHead><TableHead className="text-right">Culled</TableHead><TableHead className="text-right">Of placed</TableHead></TableRow></TableHeader>
                  <TableBody>
                    {animalsPg.pageItems.map((a) => (
                      <TableRow key={a.groupId}>
                        <TableCell><Link className="text-amber-800 hover:underline" href={`/livestock-groups/${a.groupId}`}>{a.groupName}</Link> <span className="text-xs text-stone-500">{a.speciesName}</span></TableCell>
                        <TableCell className="text-right">{fmtNum(a.deaths)}</TableCell>
                        <TableCell className="text-right">{fmtNum(a.culls)}</TableCell>
                        <TableCell className="text-right">{a.placed > 0 ? `${(((a.deaths + a.culls) / a.placed) * 100).toFixed(1)}%` : "—"}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
                <DataPagination {...animalsPg.paginationProps} variant="records" />
                </>
              )}
            </CardContent>
          </Card>
        </>
      )}
      {adding && <LossDialog onClose={() => setAdding(false)} onDone={() => { setAdding(false); load() }} />}
    </LivestockPage>
  )
}

function LossDialog({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const { toast } = useToast()
  const [items, setItems] = useState<LivestockItem[]>([])
  const [itemId, setItemId] = useState(0)
  const [date, setDate] = useState(todayIso())
  const [qty, setQty] = useState("")
  const [reason, setReason] = useState<LossReason>("Spoiled")
  const [notes, setNotes] = useState("")
  const [saving, setSaving] = useState(false)
  useEffect(() => { listItems().then((xs) => setItems(xs.filter((x) => x.stock > 0))).catch(() => setItems([])) }, [])
  const it = items.find((x) => x.itemId === itemId)
  const save = async () => {
    setSaving(true)
    try { await recordLoss({ itemId, date, quantity: Number(qty), reason, notes: notes.trim() || null }); toast({ title: "Loss recorded" }); onDone() }
    catch (e: any) { toast({ title: "Not recorded", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setSaving(false) }
  }
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader><DialogTitle>Record stock lost or damaged</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <div>
            <Label>Item</Label>
            <Select value={itemId ? String(itemId) : ""} onValueChange={(v) => setItemId(Number(v))}>
              <SelectTrigger><SelectValue placeholder="Choose" /></SelectTrigger>
              <SelectContent>{items.map((x) => <SelectItem key={x.itemId} value={String(x.itemId)}>{x.name} · {fmtNum(x.stock)} {x.unit}</SelectItem>)}</SelectContent>
            </Select>
          </div>
          <div className="grid grid-cols-3 gap-3">
            <div><Label htmlFor="ls-qty">How much{it ? ` (${it.unit})` : ""}</Label><Input id="ls-qty" type="number" min={0} step="any" value={qty} onChange={(e) => setQty(e.target.value)} /></div>
            <div>
              <Label>Why</Label>
              <Select value={reason} onValueChange={(v) => setReason(v as LossReason)}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{(Object.keys(LOSS_REASON_LABEL) as LossReason[]).map((r) => <SelectItem key={r} value={r}>{LOSS_REASON_LABEL[r]}</SelectItem>)}</SelectContent>
              </Select>
            </div>
            <div><Label htmlFor="ls-date">Date</Label><Input id="ls-date" type="date" max={todayIso()} value={date} onChange={(e) => setDate(e.target.value)} /></div>
          </div>
          <div><Label htmlFor="ls-notes">{reason === "Other" ? "What happened (required)" : "Notes"}</Label><Textarea id="ls-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} /></div>
          {it?.avgCost != null && Number(qty) > 0 && <p className="text-sm text-stone-600">Worth about {fmtMoney(it.avgCost * Number(qty))}.</p>}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button className={AMBER_BUTTON} disabled={saving || !itemId || !(Number(qty) > 0) || (reason === "Other" && !notes.trim())} onClick={save}>{saving ? "Saving…" : "Record"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
