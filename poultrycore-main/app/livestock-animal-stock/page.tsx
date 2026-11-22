"use client"

// Animal Stock -- the poultry Birds on Hand / stock movements for livestock:
// for each group over a period, what it started with, every way animals came
// and went, and what it ended with. Opening + in - out = closing on every row.

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { Layers } from "lucide-react"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableFooter, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { getAnimalStock, type AnimalStockRow } from "@/lib/api/livestock"
import { useLivestockSpecies } from "@/hooks/use-livestock-species"
import { EmptyState, LivestockPage, LoadError, Loading, fmtNum, todayIso } from "@/components/livestock/livestock-page"

const ALL = "__all"
const firstOfMonth = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-01` }
const COLS: { key: keyof AnimalStockRow; label: string; out?: boolean }[] = [
  { key: "opening", label: "Opening" }, { key: "cameIn", label: "Came in" }, { key: "born", label: "Born" },
  { key: "movedIn", label: "Moved in" }, { key: "movedOut", label: "Moved out", out: true }, { key: "died", label: "Died", out: true },
  { key: "culled", label: "Culled", out: true }, { key: "sold", label: "Sold", out: true }, { key: "corrections", label: "Count corrections" },
  { key: "closing", label: "Closing" },
]

export default function LivestockAnimalStockPage() {
  const { kept } = useLivestockSpecies()
  const [from, setFrom] = useState(firstOfMonth())
  const [to, setTo] = useState(todayIso())
  const [species, setSpecies] = useState(ALL)
  const [rows, setRows] = useState<AnimalStockRow[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const load = useCallback(async () => {
    setError(null)
    try { setRows(await getAnimalStock(from, to, species === ALL ? undefined : species)) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [from, to, species])
  useEffect(() => { load() }, [load])
  const totals = useMemo(() => Object.fromEntries(COLS.map((c) => [c.key, (rows ?? []).reduce((s, r) => s + (r[c.key] as number), 0)])), [rows])

  return (
    <LivestockPage title="Animal stock" description="Animals in, born, out and on hand over a period." icon={Layers}>
      <div className="flex items-center gap-2 flex-wrap">
        <Input type="date" className="w-40" value={from} max={to} onChange={(e) => setFrom(e.target.value)} aria-label="From" />
        <span className="text-sm text-stone-500">to</span>
        <Input type="date" className="w-40" value={to} min={from} max={todayIso()} onChange={(e) => setTo(e.target.value)} aria-label="To" />
        <Select value={species} onValueChange={setSpecies}>
          <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value={ALL}>All animals</SelectItem>
            {kept.map((s) => <SelectItem key={s.speciesCode} value={s.speciesCode}>{s.name}</SelectItem>)}
          </SelectContent>
        </Select>
      </div>
      {error ? <LoadError message={error} onRetry={load} /> : !rows ? <Loading /> : rows.length === 0 ? <EmptyState title="No groups in these dates" /> : (
        <div className="rounded-md border bg-white overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow><TableHead>Group</TableHead>{COLS.map((c) => <TableHead key={c.key} className="text-right">{c.label}</TableHead>)}</TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((r) => (
                <TableRow key={r.groupId}>
                  <TableCell><Link className="text-amber-800 hover:underline" href={`/livestock-groups/${r.groupId}`}>{r.groupName}</Link><div className="text-xs text-stone-500">{r.speciesName}{r.status === "Closed" ? " · closed" : ""}</div></TableCell>
                  {COLS.map((c) => {
                    const v = r[c.key] as number
                    return <TableCell key={c.key} className={`text-right ${c.key === "closing" || c.key === "opening" ? "font-medium" : ""} ${v && c.out ? "text-rose-700" : ""}`}>{v ? fmtNum(v) : "—"}</TableCell>
                  })}
                </TableRow>
              ))}
            </TableBody>
            <TableFooter>
              <TableRow><TableCell className="font-semibold">All</TableCell>{COLS.map((c) => <TableCell key={c.key} className="text-right font-semibold">{fmtNum(totals[c.key])}</TableCell>)}</TableRow>
            </TableFooter>
          </Table>
        </div>
      )}
    </LivestockPage>
  )
}
