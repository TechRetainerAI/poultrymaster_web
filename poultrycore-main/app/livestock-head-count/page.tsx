"use client"

// Head Count -- the poultry Batch Bird Count for livestock. Count the animals
// in each pen on a date; every difference from the records becomes a count
// correction dated that day, so what happened after the count stays.

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { ListChecks } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { useToast } from "@/hooks/use-toast"
import { getHeadCountSheet, postHeadCount, type HeadCountRow } from "@/lib/api/livestock"
import { useLivestockSpecies } from "@/hooks/use-livestock-species"
import { AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, fmtNum, todayIso } from "@/components/livestock/livestock-page"

const ALL = "__all"

export default function LivestockHeadCountPage() {
  const { toast } = useToast()
  const { kept } = useLivestockSpecies()
  const [date, setDate] = useState(todayIso())
  const [species, setSpecies] = useState(ALL)
  const [rows, setRows] = useState<HeadCountRow[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [counted, setCounted] = useState<Record<number, string>>({})
  const [notes, setNotes] = useState("")
  const [saving, setSaving] = useState(false)

  const load = useCallback(async () => {
    setError(null)
    try { setRows(await getHeadCountSheet(date, species === ALL ? undefined : species)); setCounted({}) }
    catch (e: any) { setError(e?.message ?? String(e)) }
  }, [date, species])
  useEffect(() => { load() }, [load])

  const changes = (rows ?? []).filter((r) => counted[r.groupId] !== undefined && counted[r.groupId] !== "" && Number(counted[r.groupId]) !== r.headOnDate)
  const save = async () => {
    setSaving(true)
    try {
      const res = await postHeadCount(date, (rows ?? []).filter((r) => counted[r.groupId] !== undefined && counted[r.groupId] !== "")
        .map((r) => ({ groupId: r.groupId, counted: Number(counted[r.groupId]) })), notes.trim() || null)
      toast({ title: "Counts saved", description: res.map((x) => `${x.name} ${x.change > 0 ? "+" : ""}${x.change}`).join(", ") })
      load()
    } catch (e: any) { toast({ title: "Not saved", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setSaving(false) }
  }

  return (
    <LivestockPage title="Head count" description="Count the animals in the pens and set the records to match." icon={ListChecks}>
      <div className="flex items-end gap-3 flex-wrap">
        <div><Label htmlFor="hc-date">Count date</Label><Input id="hc-date" type="date" className="w-40" max={todayIso()} value={date} onChange={(e) => setDate(e.target.value)} /></div>
        <Select value={species} onValueChange={setSpecies}>
          <SelectTrigger className="w-48"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>All animals</SelectItem>
            {kept.map((s) => <SelectItem key={s.speciesCode} value={s.speciesCode}>{s.name}</SelectItem>)}
          </SelectContent>
        </Select>
      </div>
      {error ? <LoadError message={error} onRetry={load} /> : !rows ? <Loading /> : rows.length === 0 ? <EmptyState title="No active groups on that date" /> : (
        <>
          <div className="rounded-md border bg-white overflow-x-auto">
            <Table>
              <TableHeader><TableRow><TableHead>Group</TableHead><TableHead>Pen</TableHead><TableHead className="text-right">Records say</TableHead><TableHead className="w-36">Counted</TableHead><TableHead className="text-right">Difference</TableHead><TableHead className="text-right">Now</TableHead></TableRow></TableHeader>
              <TableBody>
                {rows.map((r) => {
                  const c = counted[r.groupId]
                  const diff = c === undefined || c === "" ? null : Number(c) - r.headOnDate
                  return (
                    <TableRow key={r.groupId}>
                      <TableCell><Link className="text-amber-800 hover:underline" href={`/livestock-groups/${r.groupId}`}>{r.name}</Link> <span className="text-xs text-stone-500">{r.speciesName}</span></TableCell>
                      <TableCell>{r.penName ?? "—"}</TableCell>
                      <TableCell className="text-right">{fmtNum(r.headOnDate)}</TableCell>
                      <TableCell><Input type="number" min={r.tagged} inputMode="numeric" value={c ?? ""} onChange={(e) => setCounted((m) => ({ ...m, [r.groupId]: e.target.value }))} /></TableCell>
                      <TableCell className={`text-right font-medium ${diff == null || diff === 0 ? "" : diff < 0 ? "text-rose-700" : "text-emerald-700"}`}>{diff == null ? "" : diff > 0 ? `+${diff}` : diff}</TableCell>
                      <TableCell className="text-right text-stone-500">{fmtNum(r.headNow)}</TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          </div>
          <div className="flex items-end gap-3 flex-wrap justify-between">
            <div className="flex-1 min-w-64"><Label htmlFor="hc-notes">Notes</Label><Input id="hc-notes" value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Who counted, anything found" /></div>
            <Button className={AMBER_BUTTON} disabled={saving || changes.length === 0} onClick={save}>{saving ? "Saving…" : `Save ${changes.length} correction(s)`}</Button>
          </div>
        </>
      )}
    </LivestockPage>
  )
}
