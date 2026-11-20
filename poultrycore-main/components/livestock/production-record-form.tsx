"use client"

// A group's day: deaths and culls, eggs (laying birds), milk (milked animals),
// water, and the feed and medicine used -- taken out of stock at average cost.
// The poultry production record for livestock; one per group per day.

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { Copy, Plus, X } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { useToast } from "@/hooks/use-toast"
import {
  getProductionForm, listGroups, listItems, saveProductionRecord,
  type LivestockGroup, type LivestockItem, type ProductionForm, type ProductionInput, type ProductionLineInput, type ProductionRecord,
} from "@/lib/api/livestock"
import { AMBER_BUTTON, fmtMoney, fmtNum, todayIso } from "./livestock-page"

type Line = { itemId: number | null; quantity: string; notes: string }
const emptyLine = (): Line => ({ itemId: null, quantity: "", notes: "" })

export function ProductionRecordForm({ record, presetGroupId, presetDate }: {
  /** Edit when given. */
  record?: ProductionRecord | null
  presetGroupId?: number | null
  presetDate?: string | null
}) {
  const router = useRouter()
  const { toast } = useToast()
  const isEdit = !!record
  const [groups, setGroups] = useState<LivestockGroup[]>([])
  const [items, setItems] = useState<LivestockItem[]>([])
  const [groupId, setGroupId] = useState<number | null>(record?.groupId ?? presetGroupId ?? null)
  const [date, setDate] = useState(record?.date ?? presetDate ?? todayIso())
  const [form, setForm] = useState<ProductionForm | null>(null)
  const [deaths, setDeaths] = useState(String(record?.deaths ?? ""))
  const [deathCause, setDeathCause] = useState(record?.deathCause ?? "")
  const [culls, setCulls] = useState(String(record?.culls ?? ""))
  const [eggs, setEggs] = useState(record?.eggsCollected?.toString() ?? "")
  const [broken, setBroken] = useState(record?.eggsBroken?.toString() ?? "")
  const [milk, setMilk] = useState(record?.milkLitres?.toString() ?? "")
  const [water, setWater] = useState(record?.waterLitres?.toString() ?? "")
  const [notes, setNotes] = useState(record?.notes ?? "")
  const toLines = (t: "Feed" | "Medication", r?: ProductionRecord | null): Line[] =>
    r?.lines.filter((l) => l.lineType === t).map((l) => ({ itemId: l.itemId, quantity: String(l.quantity), notes: l.notes ?? "" })) ?? []
  const [feed, setFeed] = useState<Line[]>(() => (record ? toLines("Feed", record) : [emptyLine()]))
  const [meds, setMeds] = useState<Line[]>(() => toLines("Medication", record))
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    listGroups(isEdit).then(setGroups).catch(() => setGroups([]))
    listItems(undefined, isEdit).then(setItems).catch(() => setItems([]))
  }, [isEdit])

  useEffect(() => {
    if (!groupId || !date) { setForm(null); return }
    let live = true
    getProductionForm(groupId, date).then((f) => { if (live) setForm(f) }).catch(() => { if (live) setForm(null) })
    return () => { live = false }
  }, [groupId, date])

  const group = groups.find((g) => g.groupId === groupId)
  const speciesCode = form?.speciesCode ?? group?.speciesCode
  const usable = (cats: string[]) => items.filter((i) => cats.includes(i.category) && (!i.speciesCode || i.speciesCode === speciesCode))
  const feedItems = useMemo(() => usable(["Feed"]), [items, speciesCode]) // eslint-disable-line react-hooks/exhaustive-deps
  const medItems = useMemo(() => usable(["Medication", "Vaccine"]), [items, speciesCode]) // eslint-disable-line react-hooks/exhaustive-deps
  const itemOf = (id: number | null) => items.find((i) => i.itemId === id)

  // On a new record, an existing one for that group and day is opened instead.
  const clash = !isEdit && form?.existingRecordId ? form.existingRecordId : null
  const editClash = isEdit && form?.existingRecordId && form.existingRecordId !== record!.recordId ? form.existingRecordId : null

  const dead = Number(deaths) || 0
  const culled = Number(culls) || 0
  const headStart = form?.headStartOfDay ?? null
  const headEnd = headStart == null ? null : headStart - dead - culled

  const lineCost = (l: Line) => {
    const it = itemOf(l.itemId)
    return it?.avgCost != null && Number(l.quantity) > 0 ? it.avgCost * Number(l.quantity) : 0
  }
  const estCost = [...feed, ...meds].reduce((s, l) => s + lineCost(l), 0)

  const copyLast = () => {
    const last = form?.lastRecord
    if (!last) return
    const f = toLines("Feed", last); const m = toLines("Medication", last)
    setFeed(f.length ? f : [emptyLine()]); setMeds(m)
    if (form?.producesMilk && last.milkLitres != null) setMilk(String(last.milkLitres))
    if (last.waterLitres != null) setWater(String(last.waterLitres))
  }

  const save = async () => {
    if (!groupId) return
    setSaving(true)
    const lines = (ls: Line[]): ProductionLineInput[] =>
      ls.filter((l) => l.itemId || l.quantity).map((l) => ({ itemId: l.itemId as number, quantity: Number(l.quantity), notes: l.notes.trim() || null }))
    const input: ProductionInput = {
      groupId, date, deaths: dead, deathCause: deathCause.trim() || null, culls: culled,
      eggsCollected: form?.producesEggs && eggs !== "" ? Number(eggs) : null,
      eggsBroken: form?.producesEggs && broken !== "" ? Number(broken) : null,
      milkLitres: form?.producesMilk && milk !== "" ? Number(milk) : null,
      waterLitres: water !== "" ? Number(water) : null,
      notes: notes.trim() || null, feedLines: lines(feed), medicationLines: lines(meds),
    }
    try {
      const res = await saveProductionRecord(input, record?.recordId)
      toast({ title: isEdit ? "Record updated" : "Record saved" })
      router.push(`/livestock-production-records/${res.recordId}`)
    } catch (e: any) {
      toast({ title: "Not saved", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  // A plain render function, not a component: defined inside the form, a
  // component would be a new type every render and its inputs would lose focus.
  const renderLines = (title: string, lines: Line[], setLines: (f: (ls: Line[]) => Line[]) => void, choices: LivestockItem[]) => (
    <Card>
      <CardHeader className="pb-2 flex-row items-center justify-between space-y-0">
        <CardTitle className="text-base">{title}</CardTitle>
        <Button variant="outline" size="sm" onClick={() => setLines((ls) => [...ls, emptyLine()])}><Plus className="h-4 w-4 mr-1" />Add line</Button>
      </CardHeader>
      <CardContent className="space-y-2">
        {lines.length === 0 && <p className="text-sm text-stone-500">None used.</p>}
        {lines.map((l, i) => {
          const it = itemOf(l.itemId)
          const over = it && Number(l.quantity) > it.stock + (isEdit ? (record!.lines.filter((x) => x.itemId === it.itemId).reduce((s, x) => s + x.quantity, 0)) : 0)
          return (
            <div key={i} className="grid grid-cols-[1fr_8rem_auto] gap-2 items-start">
              <div>
                <Select value={l.itemId ? String(l.itemId) : ""} onValueChange={(v) => setLines((ls) => ls.map((x, j) => (j === i ? { ...x, itemId: Number(v) } : x)))}>
                  <SelectTrigger><SelectValue placeholder={choices.length ? "Choose" : "No items in stock yet"} /></SelectTrigger>
                  <SelectContent>
                    {choices.map((c) => <SelectItem key={c.itemId} value={String(c.itemId)}>{c.name} · {fmtNum(c.stock)} {c.unit} left</SelectItem>)}
                  </SelectContent>
                </Select>
                {over && <p className="text-xs text-rose-700 mt-1">Only {fmtNum(it!.stock)} {it!.unit} in stock.</p>}
              </div>
              <div>
                <Input type="number" min={0} step="any" placeholder={it?.unit ?? "Qty"} value={l.quantity}
                  onChange={(e) => setLines((ls) => ls.map((x, j) => (j === i ? { ...x, quantity: e.target.value } : x)))} />
                {lineCost(l) > 0 && <p className="text-xs text-stone-500 mt-1">≈ {fmtMoney(lineCost(l))}</p>}
              </div>
              <Button variant="ghost" size="icon" aria-label="Remove line" onClick={() => setLines((ls) => ls.filter((_, j) => j !== i))}><X className="h-4 w-4" /></Button>
            </div>
          )
        })}
      </CardContent>
    </Card>
  )

  return (
    <div className="space-y-4 max-w-3xl">
      <Card>
        <CardContent className="p-4 grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div>
            <Label>Group</Label>
            <Select value={groupId ? String(groupId) : ""} disabled={isEdit} onValueChange={(v) => setGroupId(Number(v))}>
              <SelectTrigger><SelectValue placeholder="Choose a group" /></SelectTrigger>
              <SelectContent>
                {groups.map((g) => <SelectItem key={g.groupId} value={String(g.groupId)}>{g.name} · {g.speciesName} · {g.head} head</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div>
            <Label htmlFor="pr-date">Date</Label>
            <Input id="pr-date" type="date" min={form?.startDate} max={todayIso()} value={date} onChange={(e) => setDate(e.target.value)} />
          </div>
          {form && (
            <div className="sm:col-span-2 text-sm text-stone-600 flex flex-wrap items-center gap-x-4 gap-y-1">
              <span>Animals at start of day: <strong>{fmtNum(form.headStartOfDay)}</strong></span>
              {headEnd != null && (dead > 0 || culled > 0) && <span>After this record: <strong>{fmtNum(headEnd)}</strong></span>}
              {form.lastRecord && (
                <Button variant="link" size="sm" className="h-auto p-0 text-amber-800" onClick={copyLast}>
                  <Copy className="h-3.5 w-3.5 mr-1" />Same feed as {new Date(form.lastRecord.date + "T00:00:00").toLocaleDateString()}
                </Button>
              )}
            </div>
          )}
          {(clash || editClash) && (
            <div className="sm:col-span-2 rounded-md border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900">
              {form!.groupName} already has a record for this day.{" "}
              <Link className="underline font-medium" href={`/livestock-production-records/${clash ?? editClash}`}>Open it</Link>
            </div>
          )}
        </CardContent>
      </Card>

      {form && !clash && (
        <>
          <Card>
            <CardHeader className="pb-2"><CardTitle className="text-base">Animals</CardTitle></CardHeader>
            <CardContent className="grid grid-cols-1 sm:grid-cols-3 gap-3">
              <div>
                <Label htmlFor="pr-deaths">Died</Label>
                <Input id="pr-deaths" type="number" min={0} inputMode="numeric" value={deaths} onChange={(e) => setDeaths(e.target.value)} />
              </div>
              <div>
                <Label htmlFor="pr-cause">Cause</Label>
                <Input id="pr-cause" value={deathCause} disabled={!dead} onChange={(e) => setDeathCause(e.target.value)} />
              </div>
              <div>
                <Label htmlFor="pr-culls">Culled / removed</Label>
                <Input id="pr-culls" type="number" min={0} inputMode="numeric" value={culls} onChange={(e) => setCulls(e.target.value)} />
              </div>
              {(group?.tagged ?? 0) > 0 && (
                <p className="sm:col-span-3 text-xs text-stone-500">A tagged animal that died is recorded on the animal itself, so its record stays complete.</p>
              )}
            </CardContent>
          </Card>

          {(form.producesEggs || form.producesMilk) && (
            <Card>
              <CardHeader className="pb-2"><CardTitle className="text-base">Produce</CardTitle></CardHeader>
              <CardContent className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                {form.producesEggs && (
                  <>
                    <div>
                      <Label htmlFor="pr-eggs">Eggs collected</Label>
                      <Input id="pr-eggs" type="number" min={0} inputMode="numeric" value={eggs} onChange={(e) => setEggs(e.target.value)} />
                    </div>
                    <div>
                      <Label htmlFor="pr-broken">Of which broken</Label>
                      <Input id="pr-broken" type="number" min={0} inputMode="numeric" value={broken} onChange={(e) => setBroken(e.target.value)} />
                    </div>
                  </>
                )}
                {form.producesMilk && (
                  <div>
                    <Label htmlFor="pr-milk">Milk (litres)</Label>
                    <Input id="pr-milk" type="number" min={0} step="0.1" value={milk} onChange={(e) => setMilk(e.target.value)} />
                  </div>
                )}
              </CardContent>
            </Card>
          )}

          {renderLines("Feed", feed, setFeed, feedItems)}
          {renderLines("Medicine & vaccines", meds, setMeds, medItems)}

          <Card>
            <CardContent className="p-4 grid grid-cols-1 sm:grid-cols-3 gap-3">
              <div>
                <Label htmlFor="pr-water">Water (litres, optional)</Label>
                <Input id="pr-water" type="number" min={0} step="0.1" value={water} onChange={(e) => setWater(e.target.value)} />
              </div>
              <div className="sm:col-span-2">
                <Label htmlFor="pr-notes">Notes</Label>
                <Textarea id="pr-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
              </div>
            </CardContent>
          </Card>

          <div className="flex items-center justify-between gap-3">
            <span className="text-sm text-stone-600">{estCost > 0 && <>Feed and medicine ≈ <strong>{fmtMoney(estCost)}</strong> at today's average cost</>}</span>
            <div className="flex gap-2">
              <Button variant="outline" onClick={() => router.back()}>Cancel</Button>
              <Button className={AMBER_BUTTON} disabled={saving || !!editClash || (headEnd != null && headEnd < 0)} onClick={save}>
                {saving ? "Saving…" : isEdit ? "Save changes" : "Save record"}
              </Button>
            </div>
          </div>
        </>
      )}
    </div>
  )
}
