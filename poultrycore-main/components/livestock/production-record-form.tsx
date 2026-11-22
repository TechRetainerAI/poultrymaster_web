"use client"

// A group's day -- laid out like the poultry Production Record form: one
// colour-coded section per subject (Group & Date, Egg Production, Egg Losses,
// Milk, Animals & Age, Feed, Medication, Notes, Summary), calculated boxes that
// cannot be typed into, and the totals checked before saving.
//
// The data is livestock's own: deaths and culls, eggs (laying birds), milk
// (milked animals), water, and feed and medicine lines taken out of stock at
// average cost. One record per group per day.
//
// Used by the full page (/livestock-production-records/new and /[id]/edit) and
// by the modal on the list. onSaved decides where to go next; without it the
// form opens the saved record.

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { AlertTriangle, CalendarDays, Copy, Droplets, Egg, FileText, Loader2, Milk, PawPrint, Pill, Plus, Scale, Wheat, X } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { FormSectionCard, CalcField, NumField } from "@/components/production/production-record-fields"
import { cn } from "@/lib/utils"
import { useToast } from "@/hooks/use-toast"
import {
  getProductionForm, listGroups, listItems, saveProductionRecord,
  type LivestockGroup, type LivestockItem, type ProductionForm, type ProductionInput, type ProductionLineInput, type ProductionRecord,
} from "@/lib/api/livestock"
import { useLivestockFeatures } from "@/hooks/use-livestock-species"
import { AMBER_BUTTON, fmtMoney, fmtNum, todayIso } from "./livestock-page"

type Line = { itemId: number | null; quantity: string; notes: string }
const emptyLine = (): Line => ({ itemId: null, quantity: "", notes: "" })
const ALL_BATCHES = "__all"
const EGGS_PER_CRATE = 30

const daysBetween = (from: string, to: string) =>
  Math.round((new Date(to + "T00:00:00").getTime() - new Date(from + "T00:00:00").getTime()) / 86_400_000)

export function ProductionRecordForm({ record, presetGroupId, presetDate, onSaved, onCancel }: {
  /** Edit when given. */
  record?: ProductionRecord | null
  presetGroupId?: number | null
  presetDate?: string | null
  /** After a save. Default: open the saved record. */
  onSaved?: (recordId: number) => void
  /** Default: go back. */
  onCancel?: () => void
}) {
  const router = useRouter()
  const { toast } = useToast()
  const features = useLivestockFeatures()
  const isEdit = !!record
  const [groups, setGroups] = useState<LivestockGroup[]>([])
  const [items, setItems] = useState<LivestockItem[]>([])
  const [batchFilter, setBatchFilter] = useState(ALL_BATCHES)
  const [groupId, setGroupId] = useState<number | null>(record?.groupId ?? presetGroupId ?? null)
  const [date, setDate] = useState(record?.date ?? presetDate ?? todayIso())
  const [form, setForm] = useState<ProductionForm | null>(null)
  const [formLoading, setFormLoading] = useState(false)
  const [deaths, setDeaths] = useState(record ? String(record.deaths) : "")
  const [deathCause, setDeathCause] = useState(record?.deathCause ?? "")
  const [culls, setCulls] = useState(record ? String(record.culls) : "")
  const [eggCrates, setEggCrates] = useState(() => (record?.eggsCollected != null ? String(Math.floor(record.eggsCollected / EGGS_PER_CRATE)) : ""))
  const [eggPieces, setEggPieces] = useState(() => (record?.eggsCollected != null ? String(record.eggsCollected % EGGS_PER_CRATE) : ""))
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
    setFormLoading(true)
    getProductionForm(groupId, date)
      .then((f) => { if (live) setForm(f) })
      .catch(() => { if (live) setForm(null) })
      .finally(() => { if (live) setFormLoading(false) })
    return () => { live = false }
  }, [groupId, date])

  // Batch narrows the group list, as Batch narrows Flock on the poultry form.
  const batchOptions = useMemo(() => {
    const m = new Map<number, string>()
    for (const g of groups) if (g.batchId && g.batchCode) m.set(g.batchId, g.batchCode)
    return [...m.entries()].sort((a, b) => a[1].localeCompare(b[1]))
  }, [groups])
  const groupsForSelect = useMemo(
    () => groups.filter((g) => batchFilter === ALL_BATCHES || String(g.batchId) === batchFilter || g.groupId === groupId),
    [groups, batchFilter, groupId])

  const group = groups.find((g) => g.groupId === groupId)
  const speciesCode = form?.speciesCode ?? group?.speciesCode
  const usable = (cats: string[]) => items.filter((i) => cats.includes(i.category) && (!i.speciesCode || i.speciesCode === speciesCode))
  const feedItems = useMemo(() => usable(["Feed"]), [items, speciesCode]) // eslint-disable-line react-hooks/exhaustive-deps
  const medItems = useMemo(() => usable(["Medication", "Vaccine"]), [items, speciesCode]) // eslint-disable-line react-hooks/exhaustive-deps
  const itemOf = (id: number | null) => items.find((i) => i.itemId === id)

  // On a new record, an existing one for that group and day is opened instead.
  const clash = !isEdit && form?.existingRecordId ? form.existingRecordId : null
  const editClash = isEdit && form?.existingRecordId && form.existingRecordId !== record!.recordId ? form.existingRecordId : null

  // ---- Calculated figures --------------------------------------------------
  const dead = Number(deaths) || 0
  const culled = Number(culls) || 0
  const headStart = form?.headStartOfDay ?? null
  // The whole form shows from the start, as on poultry. Until a group is
  // chosen, the egg / milk sections follow what the farm keeps; once chosen,
  // what that group's species gives.
  const showEggs = form ? form.producesEggs : features.eggs
  const showMilk = form ? form.producesMilk : features.milk
  const headLeft = headStart == null ? null : headStart - dead - culled
  const eggsTotal = (Number(eggCrates) || 0) * EGGS_PER_CRATE + (Number(eggPieces) || 0)
  const eggsEntered = eggCrates !== "" || eggPieces !== ""
  const brokenNum = Number(broken) || 0
  const goodEggs = Math.max(eggsTotal - brokenNum, 0)
  const layRate = headStart && eggsTotal ? (eggsTotal / headStart) * 100 : null
  const ageDays = group && date ? (group.ageAtStartDays ?? 0) + Math.max(daysBetween(group.startDate, date), 0) : null

  // What this record already took out of stock goes back before the check.
  const ownQty = (itemId: number) => (isEdit ? record!.lines.filter((x) => x.itemId === itemId).reduce((s, x) => s + x.quantity, 0) : 0)
  const lineCost = (l: Line) => {
    const it = itemOf(l.itemId)
    return it?.avgCost != null && Number(l.quantity) > 0 ? it.avgCost * Number(l.quantity) : 0
  }
  const feedCost = feed.reduce((s, l) => s + lineCost(l), 0)
  const medCost = meds.reduce((s, l) => s + lineCost(l), 0)
  // Same rule as the saved record (459 feedKg): quantity × the item's kg per unit.
  const kgPer = (it?: LivestockItem) => it?.kgPerUnit ?? (it?.unit?.toLowerCase() === "kg" ? 1 : 0)
  const feedKg = feed.reduce((s, l) => s + (Number(l.quantity) || 0) * kgPer(itemOf(l.itemId)), 0)
  const medQty = meds.reduce((s, l) => s + (Number(l.quantity) || 0), 0)
  const overStock = [...feed, ...meds].some((l) => { const it = itemOf(l.itemId); return it && Number(l.quantity) > it.stock + ownQty(it.itemId) })

  const copyLast = () => {
    const last = form?.lastRecord
    if (!last) return
    const f = toLines("Feed", last); const m = toLines("Medication", last)
    setFeed(f.length ? f : [emptyLine()]); setMeds(m)
    if (form?.producesMilk && last.milkLitres != null) setMilk(String(last.milkLitres))
    if (last.waterLitres != null) setWater(String(last.waterLitres))
  }

  const problem =
    !groupId ? "Choose a group."
      : headLeft != null && headLeft < 0 ? `Only ${fmtNum(headStart!)} animals at the start of the day.`
        : brokenNum > eggsTotal ? "Broken eggs cannot be more than the eggs collected."
          : overStock ? "A feed or medicine line uses more than is in stock."
            : null

  const save = async () => {
    if (!groupId || problem) { if (problem) toast({ title: "Check the form", description: problem, variant: "destructive" }); return }
    setSaving(true)
    const lines = (ls: Line[]): ProductionLineInput[] =>
      ls.filter((l) => l.itemId || l.quantity).map((l) => ({ itemId: l.itemId as number, quantity: Number(l.quantity), notes: l.notes.trim() || null }))
    const input: ProductionInput = {
      groupId, date, deaths: dead, deathCause: deathCause.trim() || null, culls: culled,
      eggsCollected: form?.producesEggs && eggsEntered ? eggsTotal : null,
      eggsBroken: form?.producesEggs && broken !== "" ? brokenNum : null,
      milkLitres: form?.producesMilk && milk !== "" ? Number(milk) : null,
      waterLitres: water !== "" ? Number(water) : null,
      notes: notes.trim() || null, feedLines: lines(feed), medicationLines: lines(meds),
    }
    try {
      const res = await saveProductionRecord(input, record?.recordId)
      toast({ title: isEdit ? "Record updated" : "Record saved" })
      if (onSaved) onSaved(res.recordId)
      else router.push(`/livestock-production-records/${res.recordId}`)
    } catch (e: any) {
      toast({ title: "Not saved", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSaving(false) }
  }

  // A plain render function, not a component: defined inside the form, a
  // component would be a new type every render and its inputs would lose focus.
  const renderLines = (lines: Line[], setLines: (f: (ls: Line[]) => Line[]) => void, choices: LivestockItem[], addLabel: string) => (
    <div className="space-y-2">
      {lines.length === 0 && <p className="text-sm text-stone-500">None used.</p>}
      {lines.length > 0 && (
        <div className="hidden sm:grid grid-cols-[1fr_8rem_7rem_7rem_auto] gap-2 text-xs font-medium text-slate-500 px-0.5">
          <span>Item</span><span>Quantity</span><span>Unit cost</span><span>Line cost</span><span />
        </div>
      )}
      {lines.map((l, i) => {
        const it = itemOf(l.itemId)
        const over = it && Number(l.quantity) > it.stock + ownQty(it.itemId)
        return (
          <div key={i} className="grid grid-cols-1 sm:grid-cols-[1fr_8rem_7rem_7rem_auto] gap-2 items-start">
            <div>
              <Select value={l.itemId ? String(l.itemId) : ""} onValueChange={(v) => setLines((ls) => ls.map((x, j) => (j === i ? { ...x, itemId: Number(v) } : x)))}>
                <SelectTrigger><SelectValue placeholder={choices.length ? "Choose" : "Nothing in stock yet — buy it first"} /></SelectTrigger>
                <SelectContent>
                  {choices.map((c) => <SelectItem key={c.itemId} value={String(c.itemId)}>{c.name} · {fmtNum(c.stock)} {c.unit} left</SelectItem>)}
                </SelectContent>
              </Select>
              {over && <p className="text-xs text-rose-700 mt-1">Only {fmtNum(it!.stock + ownQty(it!.itemId))} {it!.unit} in stock.</p>}
            </div>
            <Input type="number" min={0} step="any" placeholder={it?.unit ?? "Qty"} value={l.quantity} className="tabular-nums"
              onChange={(e) => setLines((ls) => ls.map((x, j) => (j === i ? { ...x, quantity: e.target.value } : x)))} />
            <output className="flex h-9 items-center rounded-md border border-dashed border-slate-300 bg-slate-50 px-3 text-sm tabular-nums text-slate-700">
              {it?.avgCost != null ? fmtMoney(it.avgCost) : "—"}
            </output>
            <output className="flex h-9 items-center rounded-md border border-dashed border-slate-300 bg-slate-50 px-3 text-sm tabular-nums text-slate-700">
              {lineCost(l) > 0 ? fmtMoney(lineCost(l)) : "—"}
            </output>
            <Button variant="ghost" size="icon" aria-label="Remove line" onClick={() => setLines((ls) => ls.filter((_, j) => j !== i))}><X className="h-4 w-4" /></Button>
          </div>
        )
      })}
      <Button variant="outline" size="sm" onClick={() => setLines((ls) => [...ls, emptyLine()])}><Plus className="h-4 w-4 mr-1" />{addLabel}</Button>
    </div>
  )

  return (
    <div className="space-y-4">
      {(clash || editClash) && (
        <Alert className="border-amber-200 bg-amber-50">
          <AlertDescription className="text-amber-900">
            {form!.groupName} already has a record for this day. One record per group per day.{" "}
            <Link className="underline font-medium" href={`/livestock-production-records/${clash ?? editClash}`}>Open that record instead</Link>
          </AlertDescription>
        </Alert>
      )}

      {/* ------------------------------------------------ Group & Date */}
      <FormSectionCard title="Group & Date" description="Which group this record is for, and the day it covers." accent="sky" icon={CalendarDays}>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <div className="space-y-1.5">
            <Label>Batch</Label>
            <Select value={batchFilter} onValueChange={setBatchFilter} disabled={isEdit}>
              <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value={ALL_BATCHES}>All batches</SelectItem>
                {batchOptions.map(([id, code]) => <SelectItem key={id} value={String(id)}>{code}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label>Group <span className="text-red-500">*</span></Label>
            <Select value={groupId ? String(groupId) : ""} disabled={isEdit} onValueChange={(v) => setGroupId(Number(v))}>
              <SelectTrigger className="w-full"><SelectValue placeholder={groups.length ? "Choose a group" : "No groups yet"} /></SelectTrigger>
              <SelectContent>
                {groupsForSelect.map((g) => <SelectItem key={g.groupId} value={String(g.groupId)}>{g.name} · {g.speciesName} · {fmtNum(g.head)} head</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="pr-date">Date <span className="text-red-500">*</span></Label>
            <Input id="pr-date" type="date" min={form?.startDate} max={todayIso()} value={date} onChange={(e) => setDate(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label>Same as last record</Label>
            <Button variant="outline" className="w-full justify-start" disabled={!form?.lastRecord} onClick={copyLast}
              title={form?.lastRecord ? "Copies the feed, medicine, milk and water of the last record" : "No earlier record for this group"}>
              <Copy className="h-4 w-4 mr-2" />
              {form?.lastRecord ? `Copy feed from ${new Date(form.lastRecord.date + "T00:00:00").toLocaleDateString()}` : "No earlier record"}
            </Button>
          </div>
        </div>
        {formLoading && <p className="mt-2 text-xs text-slate-500 flex items-center gap-1"><Loader2 className="h-3 w-3 animate-spin" /> Loading the group's day…</p>}
      </FormSectionCard>

      {!clash && (
        <>
          {/* --------------------------------------------- Egg Production */}
          {showEggs && (
            <>
              <FormSectionCard title="Egg Production" description={`Total = crates × ${EGGS_PER_CRATE} + pieces`}
                badge={`${eggsTotal.toLocaleString()} eggs`} accent="amber" icon={Egg}>
                <div className="grid grid-cols-3 items-end gap-2 rounded-lg border border-amber-200 bg-amber-50 px-3 py-2.5 sm:max-w-xl">
                  <NumField label="Crates" value={eggCrates} onChange={(v) => setEggCrates(String(v))} text />
                  <NumField label="Pieces" value={eggPieces} onChange={(v) => setEggPieces(String(v))} text max={EGGS_PER_CRATE - 1} />
                  <CalcField label="Total eggs" value={eggsTotal.toLocaleString()} />
                </div>
                <div className="mt-3 flex flex-wrap items-center gap-x-6 gap-y-1 rounded-md border border-amber-200 bg-amber-100/70 px-3 py-2 text-sm">
                  <span className="text-slate-500">Total eggs <b className="ml-1 text-slate-900 tabular-nums">{eggsTotal.toLocaleString()}</b></span>
                  <span className="text-slate-500">Lay rate <b className="ml-1 text-slate-900 tabular-nums">{layRate != null ? `${layRate.toFixed(1)}%` : "—"}</b></span>
                </div>
                {headStart != null && eggsTotal > headStart && (
                  <div className="mt-2 flex items-start gap-2 rounded-md border border-red-300 bg-red-50 px-3 py-2 text-xs font-medium text-red-700">
                    <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
                    <span>More eggs ({eggsTotal.toLocaleString()}) than animals at the start of the day ({headStart.toLocaleString()}). Check the count.</span>
                  </div>
                )}
              </FormSectionCard>

              <FormSectionCard title="Egg Losses / Quality" description="Eggs that cannot be sold. Good eggs = total collected − broken."
                badge={brokenNum > 0 ? `${brokenNum.toLocaleString()} lost` : undefined} accent="rose" icon={AlertTriangle}>
                <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
                  <NumField label="Broken eggs" value={broken} onChange={(v) => setBroken(String(v))} text max={eggsTotal} />
                  <CalcField label="Good eggs" value={goodEggs.toLocaleString()} tone="good" />
                </div>
              </FormSectionCard>
            </>
          )}

          {/* ------------------------------------------------------ Milk */}
          {showMilk && (
            <FormSectionCard title="Milk" description="Litres milked from this group today." badge={milk ? `${milk} L` : undefined} accent="sky" icon={Milk}>
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
                <NumField label="Milk (litres)" value={milk} onChange={(v) => setMilk(String(v))} text />
                <CalcField label="Per animal (litres)" value={headStart && Number(milk) ? (Number(milk) / headStart).toFixed(2) : "—"} />
              </div>
            </FormSectionCard>
          )}

          {/* --------------------------------------------- Animals & Age */}
          <FormSectionCard title="Animals & Age"
            description={form?.lastRecord ? `Last record (${new Date(form.lastRecord.date + "T00:00:00").toLocaleDateString()}) ended with ${fmtNum(form.lastRecord.headEndOfDay)}` : "Animals at the start of the day come from the group's head count."}
            accent="emerald" icon={PawPrint}>
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
              <CalcField label="Animals at start" value={fmtNum(headStart ?? 0)} />
              <NumField label="Died" value={deaths} onChange={(v) => setDeaths(String(v))} text />
              <NumField label="Culled / removed" value={culls} onChange={(v) => setCulls(String(v))} text />
              <CalcField label="Animals left" value={fmtNum(headLeft ?? 0)} tone={headLeft != null && headLeft < 0 ? "bad" : undefined} />
              <CalcField label="Age (weeks)" value={ageDays != null ? String(Math.floor(ageDays / 7)) : "—"} />
              <CalcField label="Age (days)" value={ageDays != null ? String(ageDays) : "—"} />
            </div>
            <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2">
              <div className="space-y-1">
                <Label htmlFor="pr-cause" className="text-xs text-slate-600">Cause of death</Label>
                <Input id="pr-cause" value={deathCause} disabled={!dead} placeholder={dead ? "e.g. heat, disease, predator" : "Only when some died"} onChange={(e) => setDeathCause(e.target.value)} />
              </div>
            </div>
            {(group?.tagged ?? 0) > 0 && (
              <p className="mt-2 text-xs text-stone-500">A tagged animal that died is recorded on the animal itself, so its record stays complete.</p>
            )}
          </FormSectionCard>

          {/* ------------------------------------------------------ Feed */}
          <FormSectionCard title="Feed" description="Feed taken out of stock for this group today, at average cost."
            badge={feedCost > 0 ? `Cost ${fmtMoney(feedCost)}` : undefined} accent="orange" icon={Wheat}>
            {renderLines(feed, setFeed, feedItems, "Add feed line")}
            <div className="mt-3 grid grid-cols-1 gap-3 border-t pt-3 sm:grid-cols-3">
              <CalcField label="Total feed (kg)" value={feedKg.toLocaleString(undefined, { maximumFractionDigits: 2 })} />
              <CalcField label="Feed per animal (kg)" value={headStart && feedKg ? (feedKg / headStart).toFixed(3) : "—"} />
              <CalcField label="Total feed cost" value={fmtMoney(feedCost)} />
            </div>
          </FormSectionCard>

          {/* ------------------------------------------------ Medication */}
          <FormSectionCard title="Medication" description="Medicine and vaccines taken out of stock for this group today."
            badge={medCost > 0 ? `Cost ${fmtMoney(medCost)}` : undefined} accent="violet" icon={Pill}>
            {renderLines(meds, setMeds, medItems, "Add medication line")}
            <div className="mt-3 grid grid-cols-1 gap-3 border-t pt-3 sm:grid-cols-3">
              <CalcField label="Total medication used" value={medQty.toLocaleString(undefined, { maximumFractionDigits: 2 })} />
              <CalcField label="Total medication cost" value={fmtMoney(medCost)} />
            </div>
          </FormSectionCard>

          {/* --------------------------------------------- Water & Notes */}
          <FormSectionCard title="Water & Notes" description="Anything worth remembering about this day." accent="slate" icon={FileText}>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-4">
              <div className="space-y-1">
                <Label htmlFor="pr-water" className="text-xs text-slate-600 flex items-center gap-1"><Droplets className="h-3 w-3" /> Water (litres, optional)</Label>
                <Input id="pr-water" type="number" min={0} step="0.1" className="h-9 tabular-nums" value={water} onChange={(e) => setWater(e.target.value)} />
              </div>
              <div className="sm:col-span-3 space-y-1">
                <Label htmlFor="pr-notes" className="text-xs text-slate-600">Notes</Label>
                <Textarea id="pr-notes" rows={3} placeholder="Optional" value={notes} onChange={(e) => setNotes(e.target.value)} />
              </div>
            </div>
          </FormSectionCard>

          {/* --------------------------------------------------- Summary */}
          <FormSectionCard title="Summary" description="Check these before saving." accent="indigo" icon={Scale}>
            <div className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-3 lg:grid-cols-4">
              {showEggs && <>
                <SummaryItem label="Total eggs" value={eggsTotal.toLocaleString()} />
                <SummaryItem label="Broken" value={brokenNum.toLocaleString()} />
                <SummaryItem label="Good eggs" value={goodEggs.toLocaleString()} />
                <SummaryItem label="Lay rate" value={layRate != null ? `${layRate.toFixed(1)}%` : "—"} />
              </>}
              {showMilk && <SummaryItem label="Milk" value={milk ? `${milk} L` : "—"} />}
              <SummaryItem label="Animals at start" value={fmtNum(headStart ?? 0)} />
              <SummaryItem label="Died" value={fmtNum(dead)} />
              <SummaryItem label="Culled" value={fmtNum(culled)} />
              <SummaryItem label="Animals left" value={fmtNum(headLeft ?? 0)} />
              <SummaryItem label="Feed (kg)" value={feedKg.toLocaleString(undefined, { maximumFractionDigits: 2 })} />
              <SummaryItem label="Feed cost" value={fmtMoney(feedCost)} />
              <SummaryItem label="Medication cost" value={fmtMoney(medCost)} />
              <SummaryItem label="Total production cost" value={fmtMoney(feedCost + medCost)} strong />
            </div>
            <p className="mt-2 text-xs text-slate-500">Costs are at today's average stock cost; the saved record keeps the cost at the time.</p>
          </FormSectionCard>

          <div className="flex flex-wrap items-center justify-end gap-2 border-t pt-4">
            {problem && groupId && <span className="mr-auto text-sm text-rose-700">{problem}</span>}
            <Button variant="outline" onClick={() => (onCancel ? onCancel() : router.back())} disabled={saving}>Cancel</Button>
            <Button className={AMBER_BUTTON} disabled={saving || !form || !!editClash || !!problem} onClick={save}>
              {saving && <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />}
              {isEdit ? "Update Production Record" : "Save Production Record"}
            </Button>
          </div>
        </>
      )}
    </div>
  )
}

function SummaryItem({ label, value, strong }: { label: string; value: string; strong?: boolean }) {
  return (
    <div className="flex items-baseline justify-between gap-2 border-b border-dashed border-slate-200 pb-1">
      <span className="text-slate-500">{label}</span>
      <span className={cn("tabular-nums", strong ? "font-semibold text-slate-900" : "text-slate-800")}>{value}</span>
    </div>
  )
}
