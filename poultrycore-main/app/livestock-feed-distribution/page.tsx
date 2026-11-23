"use client"

// Feed Many Groups -- the poultry Distribute Feed tool for livestock: one
// feed, one date, a quantity for each group. Each becomes a feed line on that
// group's daily record for the day (made if there is none yet).

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { Truck } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Card, CardContent } from "@/components/ui/card"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { useToast } from "@/hooks/use-toast"
import { distributeFeed, listGroups, listItems, type LivestockGroup, type LivestockItem } from "@/lib/api/livestock"
import { AMBER_BUTTON, EmptyState, LivestockPage, Loading, fmtMoney, fmtNum, todayIso } from "@/components/livestock/livestock-page"

export default function LivestockFeedDistributionPage() {
  const { toast } = useToast()
  const [groups, setGroups] = useState<LivestockGroup[] | null>(null)
  const [feeds, setFeeds] = useState<LivestockItem[]>([])
  const [itemId, setItemId] = useState(0)
  const [date, setDate] = useState(todayIso())
  const [qty, setQty] = useState<Record<number, string>>({})
  const [perHead, setPerHead] = useState("")
  const [saving, setSaving] = useState(false)

  const load = () => {
    listGroups().then(setGroups).catch(() => setGroups([]))
    listItems("Feed").then(setFeeds).catch(() => setFeeds([]))
  }
  useEffect(() => { load() }, [])

  const feed = feeds.find((f) => f.itemId === itemId)
  const usable = useMemo(() => (groups ?? []).filter((g) => !feed?.speciesCode || g.speciesCode === feed.speciesCode), [groups, feed])
  const total = usable.reduce((s, g) => s + (Number(qty[g.groupId]) || 0), 0)
  const over = feed ? total > feed.stock : false

  const fillPerHead = () => {
    const n = Number(perHead)
    if (!(n > 0)) return
    setQty(Object.fromEntries(usable.map((g) => [g.groupId, String(Math.round(n * g.head * 1000) / 1000)])))
  }

  const save = async () => {
    setSaving(true)
    try {
      const lines = usable.map((g) => ({ groupId: g.groupId, quantity: Number(qty[g.groupId]) || 0 })).filter((l) => l.quantity > 0)
      const res = await distributeFeed(date, itemId, lines)
      toast({ title: "Feed recorded", description: `${res.length} group(s) fed ${fmtNum(total)} ${feed?.unit} of ${feed?.name}.` })
      setQty({})
      load()
    } catch (e: any) {
      toast({ title: "Not recorded", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  return (
    <LivestockPage title="Feed many groups" description="Record one feed for several groups at once. Each goes onto that group's daily record." icon={Truck}>
      <Card>
        <CardContent className="p-4 grid grid-cols-1 sm:grid-cols-3 gap-3">
          <div>
            <Label>Feed</Label>
            <Select value={itemId ? String(itemId) : ""} onValueChange={(v) => { setItemId(Number(v)); setQty({}) }}>
              <SelectTrigger><SelectValue placeholder={feeds.length ? "Choose" : "No feed in stock"} /></SelectTrigger>
              <SelectContent>{feeds.map((f) => <SelectItem key={f.itemId} value={String(f.itemId)}>{f.name} · {fmtNum(f.stock)} {f.unit}</SelectItem>)}</SelectContent>
            </Select>
          </div>
          <div><Label htmlFor="fd-date">Date</Label><Input id="fd-date" type="date" max={todayIso()} value={date} onChange={(e) => setDate(e.target.value)} /></div>
          <div>
            <Label htmlFor="fd-ph">Same amount per animal{feed ? ` (${feed.unit})` : ""}</Label>
            <div className="flex gap-2">
              <Input id="fd-ph" type="number" min={0} step="any" value={perHead} onChange={(e) => setPerHead(e.target.value)} />
              <Button variant="outline" disabled={!feed || !(Number(perHead) > 0)} onClick={fillPerHead}>Fill</Button>
            </div>
          </div>
        </CardContent>
      </Card>

      {!groups ? <Loading /> : !feed ? <EmptyState title="Choose a feed" /> : usable.length === 0 ? (
        <EmptyState title="No active groups for this feed" />
      ) : (
        <>
          <div className="rounded-md border bg-white overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow><TableHead>Group</TableHead><TableHead className="text-right">Animals</TableHead><TableHead className="w-44">Fed ({feed.unit})</TableHead></TableRow>
              </TableHeader>
              <TableBody>
                {usable.map((g) => (
                  <TableRow key={g.groupId}>
                    <TableCell><Link className="text-amber-800 hover:underline" href={`/livestock-groups/${g.groupId}`}>{g.name}</Link><span className="text-xs text-stone-500 ml-1">{g.speciesName}</span></TableCell>
                    <TableCell className="text-right">{fmtNum(g.head)}</TableCell>
                    <TableCell><Input type="number" min={0} step="any" value={qty[g.groupId] ?? ""} onChange={(e) => setQty((q) => ({ ...q, [g.groupId]: e.target.value }))} /></TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
          <div className="flex items-center justify-between gap-3">
            <span className={`text-sm ${over ? "text-rose-700 font-medium" : "text-stone-600"}`}>
              Total {fmtNum(total)} of {fmtNum(feed.stock)} {feed.unit} in stock
              {feed.avgCost != null && total > 0 && ` · about ${fmtMoney(total * feed.avgCost)}`}
            </span>
            <Button className={AMBER_BUTTON} disabled={saving || total <= 0 || over} onClick={save}>{saving ? "Saving…" : "Record feed"}</Button>
          </div>
        </>
      )}
    </LivestockPage>
  )
}
