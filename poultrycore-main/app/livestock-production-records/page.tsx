"use client"

// Production Records for livestock -- laid out like the poultry Production
// Records page: Log Production (modal) / View by Day / exports at the top, a
// filter bar (search, period, dates, animal, batch, group, month, year), stat tiles,
// a sortable table with a totals row, paging, and a summary footer.
//
// Each row is one group's day: produce (eggs / milk, by species), deaths and
// culls, and the feed and medicine taken out of stock.

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import jsPDF from "jspdf"
import autoTable from "jspdf-autotable"
import { CalendarDays, ChevronLeft, ChevronRight, ClipboardList, Download, Loader2, Mail, Plus, RefreshCw, Search } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/components/ui/confirm-delete-dialog"
import { Pagination, PaginationContent, PaginationEllipsis, PaginationItem, PaginationLink, PaginationNext, PaginationPrevious } from "@/components/ui/pagination"
import { SortableHeader, sortData, toggleSort, type SortDirection } from "@/components/ui/sortable-header"
import { PeriodSelect } from "@/components/ui/period-select"
import { rangeToPeriod, type DateRange, type PeriodKey } from "@/lib/date-ranges"
import { sendReportEmail } from "@/lib/api/email"
import { downloadCsv } from "@/lib/utils/download-csv"
import { cn } from "@/lib/utils"
import { useToast } from "@/hooks/use-toast"
import { useLivestockFeatures } from "@/hooks/use-livestock-species"
import {
  deleteProductionRecord, listGroups, listProductionRecords, type LivestockGroup, type ProductionRecord,
} from "@/lib/api/livestock"
import { LivestockProductionRecordModal } from "@/components/livestock/production-record-modal"
import { AMBER_BUTTON, LivestockPage, LoadError, StatCard, fmtDate, fmtMoney, fmtNum, todayIso } from "@/components/livestock/livestock-page"

const ALL = "ALL"
const EGGS_PER_CRATE = 30
const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

type Row = ProductionRecord & {
  batchCode: string
  ageDays: number | null
  headStart: number
  layRate: number | null
  meds: string
  feedTotal: number
}

const daysBetween = (from: string, to: string) =>
  Math.round((new Date(to + "T00:00:00").getTime() - new Date(from + "T00:00:00").getTime()) / 86_400_000)
const fmtAge = (d: number | null) => (d == null ? "—" : `${Math.floor(d / 7)}w ${d % 7}d`)
const crates = (n: number) => `${Math.floor(n / EGGS_PER_CRATE)}c + ${n % EGGS_PER_CRATE}p`

export default function LivestockProductionRecordsPage() {
  const { toast } = useToast()
  const features = useLivestockFeatures()
  const [groups, setGroups] = useState<LivestockGroup[]>([])
  const [records, setRecords] = useState<ProductionRecord[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [species, setSpecies] = useState(ALL)
  const [batchId, setBatchId] = useState(ALL)
  const [groupId, setGroupId] = useState(ALL)
  const [month, setMonth] = useState(ALL)
  const [year, setYear] = useState(ALL)
  const [sortKey, setSortKey] = useState<string | null>(null)
  const [sortDirection, setSortDirection] = useState<SortDirection>(null)
  const [page, setPage] = useState(1)
  const [perPage, setPerPage] = useState(10)
  const [formOpen, setFormOpen] = useState(false)
  const [editingId, setEditingId] = useState<number | null>(null)
  const [presetGroupId, setPresetGroupId] = useState<number | null>(null)
  const [dayOpen, setDayOpen] = useState(false)
  const [deleting, setDeleting] = useState<Row | null>(null)
  const [emailing, setEmailing] = useState(false)

  const load = useCallback(async () => {
    setError(null)
    try {
      const [rs, gs] = await Promise.all([listProductionRecords(), listGroups(true)])
      setRecords(rs); setGroups(gs)
    } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [])
  useEffect(() => { load() }, [load])

  const groupById = useMemo(() => new Map(groups.map((g) => [g.groupId, g])), [groups])
  const rows: Row[] = useMemo(() => (records ?? []).map((r) => {
    const g = groupById.get(r.groupId)
    const headStart = r.headEndOfDay + r.deaths + r.culls
    const feedTotal = r.feedKg ?? r.feedQuantity ?? 0
    return {
      ...r,
      batchCode: g?.batchCode ?? "—",
      ageDays: g ? (g.ageAtStartDays ?? 0) + Math.max(daysBetween(g.startDate, r.date), 0) : null,
      headStart,
      layRate: r.eggsCollected != null && headStart > 0 ? (r.eggsCollected / headStart) * 100 : null,
      meds: [...new Set(r.lines.filter((l) => l.lineType === "Medication").map((l) => l.itemName))].join(", "),
      feedTotal,
    }
  }), [records, groupById])

  // ---- Filters ---------------------------------------------------------------
  // Animals that have groups here; batch and group lists follow the animal chosen.
  const speciesOptions = useMemo(() => {
    const m = new Map<string, string>()
    for (const g of groups) m.set(g.speciesCode, g.speciesName)
    return [...m.entries()].sort((a, b) => a[1].localeCompare(b[1]))
  }, [groups])
  const groupsOfSpecies = useMemo(() => groups.filter((g) => species === ALL || g.speciesCode === species), [groups, species])
  const batchOptions = useMemo(() => {
    const m = new Map<string, string>()
    for (const g of groupsOfSpecies) if (g.batchId && g.batchCode) m.set(String(g.batchId), g.batchCode)
    return [...m.entries()].sort((a, b) => a[1].localeCompare(b[1]))
  }, [groupsOfSpecies])
  const groupsForBatch = useMemo(() => groupsOfSpecies.filter((g) => batchId === ALL || String(g.batchId) === batchId), [groupsOfSpecies, batchId])
  const years = useMemo(() => [...new Set(rows.map((r) => r.date.slice(0, 4)))].sort().reverse(), [rows])
  const months = useMemo(() => [...new Set(rows.map((r) => r.date.slice(5, 7)))].sort(), [rows])

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase()
    return rows.filter((r) =>
      (!dateFrom || r.date >= dateFrom) && (!dateTo || r.date <= dateTo)
      && (species === ALL || r.speciesCode === species)
      && (batchId === ALL || String(groupById.get(r.groupId)?.batchId) === batchId)
      && (groupId === ALL || String(r.groupId) === groupId)
      && (month === ALL || r.date.slice(5, 7) === month)
      && (year === ALL || r.date.slice(0, 4) === year)
      && (!q || [r.groupName, r.speciesName, r.batchCode, r.meds, r.deathCause, r.notes, r.grazingPlace, r.date].some((v) => v?.toLowerCase().includes(q))))
  }, [rows, search, dateFrom, dateTo, species, batchId, groupId, month, year, groupById])
  const sorted = useMemo(() => {
    const base = [...filtered].sort((a, b) => b.date.localeCompare(a.date) || a.groupName.localeCompare(b.groupName))
    return sortData(base, sortKey, sortDirection)
  }, [filtered, sortKey, sortDirection])
  useEffect(() => { setPage(1) }, [search, dateFrom, dateTo, species, batchId, groupId, month, year, perPage])
  const totalPages = Math.max(1, Math.ceil(sorted.length / perPage))
  const paged = sorted.slice((page - 1) * perPage, page * perPage)

  const onSort = (k: string) => { const s = toggleSort(k, sortKey, sortDirection); setSortKey(s.key); setSortDirection(s.direction) }
  const periodOf = (from: string, to: string): PeriodKey => (!from && !to ? "allTime" : rangeToPeriod(from, to))
  const applyPeriod = (p: PeriodKey, rg: DateRange | null) => {
    if (p === "allTime") { setDateFrom(""); setDateTo("") } else if (rg) { setDateFrom(rg.from); setDateTo(rg.to) }
  }
  const clearFilters = () => { setSearch(""); setDateFrom(""); setDateTo(""); setSpecies(ALL); setBatchId(ALL); setGroupId(ALL); setMonth(ALL); setYear(ALL) }

  // ---- Totals ------------------------------------------------------------------
  const t = useMemo(() => {
    const eggRows = filtered.filter((r) => r.eggsCollected != null)
    const rates = filtered.map((r) => r.layRate).filter((v): v is number => v != null)
    return {
      eggs: filtered.reduce((s, r) => s + (r.eggsCollected ?? 0), 0),
      broken: filtered.reduce((s, r) => s + (r.eggsBroken ?? 0), 0),
      eggRecords: eggRows.length,
      avgLay: rates.length ? rates.reduce((a, b) => a + b, 0) / rates.length : null,
      milk: filtered.reduce((s, r) => s + (r.milkLitres ?? 0), 0),
      feed: filtered.reduce((s, r) => s + r.feedTotal, 0),
      deaths: filtered.reduce((s, r) => s + r.deaths, 0),
      culls: filtered.reduce((s, r) => s + r.culls, 0),
      cost: filtered.reduce((s, r) => s + r.feedCost + r.medicationCost, 0),
    }
  }, [filtered])
  const avgEggs = t.eggRecords ? Math.round(t.eggs / t.eggRecords) : 0
  const activeGroups = groups.filter((g) => g.status === "Active")
  const placed = activeGroups.reduce((s, g) => s + g.placed, 0)
  const headNow = activeGroups.reduce((s, g) => s + g.head, 0)
  const allDeaths = rows.reduce((s, r) => s + r.deaths, 0)

  // Groups with no record today, so the morning's work is one click away.
  const missingToday = useMemo(() => {
    const done = new Set(rows.filter((r) => r.date === todayIso()).map((r) => r.groupId))
    return activeGroups.filter((g) => !done.has(g.groupId))
  }, [rows, activeGroups])

  const openNew = (gid: number | null = null) => { setEditingId(null); setPresetGroupId(gid); setFormOpen(true) }
  const openEdit = (id: number) => { setEditingId(id); setPresetGroupId(null); setFormOpen(true) }

  // ---- Exports -----------------------------------------------------------------
  const headers = [
    "Date", "Group", "Species", "Batch", "Age",
    ...(features.eggs ? ["Eggs", "Broken", "Lay %"] : []),
    ...(features.milk ? ["Milk (L)"] : []),
    "Feed", "Animals", "Died", "Culled", "Left", "Medication", "Cost",
  ]
  const exportRow = (r: Row) => [
    r.date, r.groupName, r.speciesName, r.batchCode, fmtAge(r.ageDays),
    ...(features.eggs ? [r.eggsCollected ?? "", r.eggsBroken ?? "", r.layRate != null ? r.layRate.toFixed(1) : ""] : []),
    ...(features.milk ? [r.milkLitres ?? ""] : []),
    r.feedTotal, r.headStart, r.deaths, r.culls, r.headEndOfDay, r.meds, (r.feedCost + r.medicationCost).toFixed(2),
  ]
  const exportCsv = () => {
    if (!filtered.length) { toast({ title: "Nothing to export", description: "Adjust your filters and try again.", variant: "destructive" }); return }
    downloadCsv("livestock-production", headers, sorted.map(exportRow))
  }
  const buildPdf = () => {
    const doc = new jsPDF({ orientation: "landscape", unit: "mm", format: "a4" })
    const farmName = localStorage.getItem("farmName") || "Farm"
    doc.setFontSize(16); doc.text(`${farmName} - Production Records`, 14, 18)
    doc.setFontSize(10); doc.setTextColor(100, 100, 100)
    doc.text(`Generated: ${new Date().toLocaleDateString()}  |  Records: ${filtered.length}`, 14, 25)
    doc.setFontSize(9)
    doc.text([
      features.eggs ? `Eggs: ${t.eggs.toLocaleString()} (${crates(t.eggs)})` : null,
      features.milk ? `Milk: ${fmtNum(t.milk)} L` : null,
      `Feed: ${fmtNum(t.feed)}`, `Died: ${t.deaths}`, `Culled: ${t.culls}`, `Animals left: ${headNow}`,
    ].filter(Boolean).join("  |  "), 14, 31)
    const body = sorted.map(exportRow).map((r) => r.map((v) => String(v)))
    body.push(headers.map((h) => ({
      Date: "TOTALS", Eggs: String(t.eggs), Broken: String(t.broken), "Milk (L)": String(t.milk), Feed: fmtNum(t.feed),
      Died: String(t.deaths), Culled: String(t.culls), Cost: t.cost.toFixed(2),
    } as Record<string, string>)[h] ?? ""))
    autoTable(doc, {
      startY: 35, head: [headers], body,
      styles: { fontSize: 7, cellPadding: 1.5 },
      headStyles: { fillColor: [146, 64, 14], textColor: 255, fontStyle: "bold", fontSize: 7 },
      alternateRowStyles: { fillColor: [250, 248, 245] },
      didParseCell: (d: any) => { if (d.section === "body" && d.row.index === body.length - 1) { d.cell.styles.fontStyle = "bold"; d.cell.styles.fillColor = [231, 229, 228] } },
    })
    return { doc, farmName }
  }
  const exportPdf = () => {
    if (!filtered.length) { toast({ title: "Nothing to export", description: "Adjust your filters and try again.", variant: "destructive" }); return }
    buildPdf().doc.save(`livestock-production-${todayIso()}.pdf`)
  }
  const emailReport = async () => {
    if (!filtered.length) { toast({ title: "Nothing to email", description: "Adjust your filters and try again.", variant: "destructive" }); return }
    const to = (localStorage.getItem("username") || "").trim()
    if (!to.includes("@")) { toast({ title: "No recipient email", description: "Sign in with an email address to receive the report.", variant: "destructive" }); return }
    setEmailing(true)
    try {
      const { doc, farmName } = buildPdf()
      const res = await sendReportEmail({ blob: doc.output("blob") as Blob, filename: `livestock-production-${todayIso()}.pdf`, to, farmName, reportTitle: "Production Records" })
      if (res.success) toast({ title: "Report emailed", description: `Sent to ${to}.` })
      else toast({ title: "Email failed", description: res.message || "Unknown error.", variant: "destructive" })
    } finally { setEmailing(false) }
  }

  const head = (label: string, key: string, cls?: string) => (
    <SortableHeader label={label} sortKey={key} currentSort={sortKey} currentDirection={sortDirection} onSort={onSort} className={cn("px-2 py-1.5 whitespace-nowrap", cls)} />
  )

  return (
    <LivestockPage
      title="Production Records"
      description="Each group's day: produce, deaths and culls, and the feed and medicine used."
      icon={ClipboardList}
      actions={
        <>
          <Button className={AMBER_BUTTON} onClick={() => openNew()}><Plus className="h-4 w-4 mr-1" /> Log Production</Button>
          <Button variant="outline" onClick={() => setDayOpen(true)}><CalendarDays className="h-4 w-4 mr-1" /> View by Day</Button>
          <Button variant="outline" onClick={exportCsv}><Download className="h-4 w-4 mr-1" /> Export CSV</Button>
          <Button variant="outline" onClick={exportPdf}><Download className="h-4 w-4 mr-1" /> Export PDF</Button>
          <Button variant="outline" onClick={emailReport} disabled={emailing}>
            {emailing ? <Loader2 className="h-4 w-4 mr-1 animate-spin" /> : <Mail className="h-4 w-4 mr-1" />} Email Report
          </Button>
        </>
      }
    >
      {records && missingToday.length > 0 && (
        <div className="rounded-md border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900">
          No record yet today for{" "}
          {missingToday.map((g, i) => (
            <span key={g.groupId}>{i > 0 && ", "}
              <button type="button" className="underline font-medium" onClick={() => openNew(g.groupId)}>{g.name}</button>
            </span>
          ))}.
        </div>
      )}

      {/* Filters */}
      <div className="flex flex-wrap items-center gap-2 rounded-lg border bg-white p-2">
        <div className="relative min-w-[160px] flex-[1.6]">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
          <Input placeholder="Search..." value={search} onChange={(e) => setSearch(e.target.value)} className="pl-9" />
        </div>
        <PeriodSelect label={null} className="w-40" value={periodOf(dateFrom, dateTo)} onChange={applyPeriod} />
        <Input type="date" value={dateFrom} max={dateTo || todayIso()} onChange={(e) => setDateFrom(e.target.value)} className="w-[140px]" aria-label="From" />
        <Input type="date" value={dateTo} min={dateFrom} max={todayIso()} onChange={(e) => setDateTo(e.target.value)} className="w-[140px]" aria-label="To" />
        <Select value={species} onValueChange={(v) => { setSpecies(v); setBatchId(ALL); setGroupId(ALL) }}>
          <SelectTrigger className="w-36"><SelectValue placeholder="Animal" /></SelectTrigger>
          <SelectContent><SelectItem value={ALL}>All Animals</SelectItem>{speciesOptions.map(([code, name]) => <SelectItem key={code} value={code}>{name}</SelectItem>)}</SelectContent>
        </Select>
        <Select value={batchId} onValueChange={(v) => { setBatchId(v); setGroupId(ALL) }}>
          <SelectTrigger className="w-36"><SelectValue placeholder="Batch" /></SelectTrigger>
          <SelectContent><SelectItem value={ALL}>All Batches</SelectItem>{batchOptions.map(([id, code]) => <SelectItem key={id} value={id}>{code}</SelectItem>)}</SelectContent>
        </Select>
        <Select value={groupId} onValueChange={setGroupId}>
          <SelectTrigger className="w-44"><SelectValue placeholder="Group" /></SelectTrigger>
          <SelectContent><SelectItem value={ALL}>All Groups</SelectItem>{groupsForBatch.map((g) => <SelectItem key={g.groupId} value={String(g.groupId)}>{g.name} ({fmtNum(g.head)} head)</SelectItem>)}</SelectContent>
        </Select>
        <Select value={month} onValueChange={setMonth}>
          <SelectTrigger className="w-32"><SelectValue placeholder="Month" /></SelectTrigger>
          <SelectContent><SelectItem value={ALL}>All Months</SelectItem>{months.map((m) => <SelectItem key={m} value={m}>{MONTHS[Number(m) - 1]}</SelectItem>)}</SelectContent>
        </Select>
        <Select value={year} onValueChange={setYear}>
          <SelectTrigger className="w-24"><SelectValue placeholder="Year" /></SelectTrigger>
          <SelectContent><SelectItem value={ALL}>All</SelectItem>{years.map((y) => <SelectItem key={y} value={y}>{y}</SelectItem>)}</SelectContent>
        </Select>
        <Button variant="outline" size="sm" onClick={clearFilters} className="h-9"><RefreshCw className="h-4 w-4 mr-1.5" /> Reset</Button>
      </div>

      {error ? <LoadError message={error} onRetry={load} /> : !records ? (
        <div className="space-y-3">{[...Array(5)].map((_, i) => <div key={i} className="h-10 w-full animate-pulse rounded bg-stone-100" />)}</div>
      ) : (
        <>
          {/* Metrics */}
          <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
            {features.eggs && <StatCard label="Total Eggs" value={t.eggs.toLocaleString()} hint={crates(t.eggs)} tone="amber" />}
            {features.eggs && <StatCard label="Avg Eggs / Record" value={avgEggs.toLocaleString()} />}
            {features.milk && <StatCard label="Milk (litres)" value={fmtNum(Math.round(t.milk * 10) / 10)} tone="amber" />}
            <StatCard label="Feed" value={fmtNum(Math.round(t.feed * 100) / 100)} hint={`Cost ${fmtMoney(t.cost)}`} />
            <StatCard label="Recorded Deaths" value={t.deaths.toLocaleString()} tone={t.deaths ? "rose" : "stone"}
              hint={<>Culled {t.culls.toLocaleString()} · All logs {allDeaths.toLocaleString()}</>} />
            <StatCard label="Animals Placed" value={placed.toLocaleString()} hint="In active groups" />
            <StatCard label="Animals Left" value={headNow.toLocaleString()} tone="emerald" hint="Head in active groups now" />
          </div>

          {/* Table */}
          <div className="overflow-x-auto rounded-md border bg-white">
            <Table className="min-w-[1100px] text-xs">
              <TableHeader className="sticky top-0 z-10 bg-amber-50">
                <TableRow className="border-b border-amber-200">
                  {head("Date", "date", "min-w-[96px]")}
                  {head("Group", "groupName", "min-w-[130px]")}
                  {head("Batch", "batchCode")}
                  {head("Age", "ageDays")}
                  {features.eggs && <>
                    {head("Eggs", "eggsCollected", "text-right bg-amber-100 text-amber-900 font-semibold")}
                    {head("Broken", "eggsBroken", "text-right bg-red-50 text-red-800 font-semibold")}
                    {head("Lay %", "layRate", "text-right")}
                  </>}
                  {features.milk && head("Milk (L)", "milkLitres", "text-right bg-sky-100 text-sky-900 font-semibold")}
                  {head("Feed", "feedTotal", "text-right")}
                  {head("Animals", "headStart", "text-right")}
                  {head("Died", "deaths", "text-right")}
                  {head("Culled", "culls", "text-right")}
                  {head("Left", "headEndOfDay", "text-right")}
                  {head("Meds", "meds", "min-w-[100px]")}
                  {head("Cost", "feedCost", "text-right")}
                  <TableHead className="px-2 py-1.5">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {paged.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={18} className="py-12 text-center text-slate-500">
                      No records found for the selected filters.
                      <Button variant="link" className="ml-1 text-amber-800" onClick={() => openNew()}>Log one now</Button>
                    </TableCell>
                  </TableRow>
                ) : paged.map((r, idx) => (
                  <TableRow key={r.recordId} className={cn("hover:bg-amber-50/60", idx % 2 ? "bg-stone-50/40" : "bg-white")}>
                    <TableCell className="px-2 py-1.5 whitespace-nowrap">{fmtDate(r.date)}</TableCell>
                    <TableCell className="px-2 py-1.5 font-medium">
                      <Link className="text-stone-900 hover:text-amber-800 hover:underline" href={`/livestock-production-records/${r.recordId}`}>{r.groupName}</Link>
                      <div className="text-[11px] font-normal text-stone-500">{r.speciesName}</div>
                    </TableCell>
                    <TableCell className="px-2 py-1.5 text-stone-600">{r.batchCode}</TableCell>
                    <TableCell className="px-2 py-1.5 whitespace-nowrap">{fmtAge(r.ageDays)}</TableCell>
                    {features.eggs && <>
                      <TableCell className="px-2 py-1.5 text-right bg-amber-50/40 text-amber-800 font-semibold">{r.eggsCollected ?? "—"}</TableCell>
                      <TableCell className="px-2 py-1.5 text-right bg-red-50/40 text-red-700">{r.eggsBroken ?? "—"}</TableCell>
                      <TableCell className="px-2 py-1.5 text-right">{r.layRate != null ? `${r.layRate.toFixed(1)}%` : "—"}</TableCell>
                    </>}
                    {features.milk && <TableCell className="px-2 py-1.5 text-right bg-sky-50/40 text-sky-800">{r.milkLitres ?? "—"}</TableCell>}
                    <TableCell className="px-2 py-1.5 text-right">
                      {r.feedTotal ? `${fmtNum(r.feedTotal)}${r.feedKg != null ? " kg" : ""}` : "—"}
                      {/* 494: grazing is not weighed -- shown next to the feed. */}
                      {r.grazed && <div className="text-xs text-emerald-700" title={r.grazingPlace ?? undefined}>+ grazed{r.grazingHours ? ` ${r.grazingHours} h` : ""}</div>}
                    </TableCell>
                    <TableCell className="px-2 py-1.5 text-right">{fmtNum(r.headStart)}</TableCell>
                    <TableCell className="px-2 py-1.5 text-right">
                      <span className={cn("rounded px-2 py-0.5", r.deaths > 0 ? "bg-red-50 text-red-700" : "bg-slate-50 text-slate-600")}>{r.deaths}</span>
                    </TableCell>
                    <TableCell className="px-2 py-1.5 text-right">{r.culls}</TableCell>
                    <TableCell className="px-2 py-1.5 text-right">{fmtNum(r.headEndOfDay)}</TableCell>
                    <TableCell className="px-2 py-1.5">{r.meds || "-"}</TableCell>
                    <TableCell className="px-2 py-1.5 text-right whitespace-nowrap">{fmtMoney(r.feedCost + r.medicationCost)}</TableCell>
                    <TableCell className="px-2 py-1.5 whitespace-nowrap">
                      <Button variant="ghost" size="sm" className="h-7 px-2 text-xs" onClick={() => openEdit(r.recordId)}>Edit</Button>
                      <Button variant="ghost" size="sm" className="h-7 px-2 text-xs text-red-600" onClick={() => setDeleting(r)}>Delete</Button>
                    </TableCell>
                  </TableRow>
                ))}
                {filtered.length > 0 && (
                  <TableRow className="bg-stone-50/80 font-semibold">
                    <TableCell className="px-2 py-1.5">Totals</TableCell>
                    <TableCell /><TableCell /><TableCell />
                    {features.eggs && <>
                      <TableCell className="px-2 py-1.5 text-right text-amber-800">{t.eggs.toLocaleString()}<div className="text-[11px] font-normal text-amber-700">{crates(t.eggs)}</div></TableCell>
                      <TableCell className="px-2 py-1.5 text-right text-red-700">{t.broken.toLocaleString()}</TableCell>
                      <TableCell />
                    </>}
                    {features.milk && <TableCell className="px-2 py-1.5 text-right text-sky-800">{fmtNum(Math.round(t.milk * 10) / 10)}</TableCell>}
                    <TableCell className="px-2 py-1.5 text-right">{fmtNum(Math.round(t.feed * 100) / 100)}</TableCell>
                    <TableCell />
                    <TableCell className="px-2 py-1.5 text-right text-red-700">{t.deaths.toLocaleString()}</TableCell>
                    <TableCell className="px-2 py-1.5 text-right">{t.culls.toLocaleString()}</TableCell>
                    <TableCell /><TableCell />
                    <TableCell className="px-2 py-1.5 text-right whitespace-nowrap">{fmtMoney(t.cost)}</TableCell>
                    <TableCell />
                  </TableRow>
                )}
              </TableBody>
            </Table>
          </div>

          {/* Pagination */}
          {sorted.length > 0 && (
            <div className="flex flex-col items-center justify-between gap-4 sm:flex-row">
              <div className="flex items-center gap-4">
                <span className="text-sm text-slate-600">Showing {(page - 1) * perPage + 1} to {Math.min(page * perPage, sorted.length)} of {sorted.length} records</span>
                <Select value={String(perPage)} onValueChange={(v) => setPerPage(Number(v))}>
                  <SelectTrigger className="h-8 w-auto min-w-[120px] gap-2 whitespace-nowrap"><SelectValue /></SelectTrigger>
                  <SelectContent>{[10, 25, 50, 100].map((n) => <SelectItem key={n} value={String(n)}>{n} / page</SelectItem>)}</SelectContent>
                </Select>
              </div>
              <Pagination className="mx-0 w-auto">
                <PaginationContent>
                  <PaginationItem><PaginationPrevious onClick={() => setPage((p) => Math.max(1, p - 1))} className={page === 1 ? "pointer-events-none opacity-50" : "cursor-pointer"} /></PaginationItem>
                  {pageNumbers(page, totalPages).map((p, i) => (
                    <PaginationItem key={i}>
                      {p === "…" ? <PaginationEllipsis /> : <PaginationLink isActive={p === page} className="cursor-pointer" onClick={() => setPage(p)}>{p}</PaginationLink>}
                    </PaginationItem>
                  ))}
                  <PaginationItem><PaginationNext onClick={() => setPage((p) => Math.min(totalPages, p + 1))} className={page === totalPages ? "pointer-events-none opacity-50" : "cursor-pointer"} /></PaginationItem>
                </PaginationContent>
              </Pagination>
            </div>
          )}

          {/* Summary footer */}
          <div className="hidden gap-2 md:grid md:grid-cols-5">
            {features.eggs && <Summary label="Average Lay %" value={t.avgLay != null ? `${t.avgLay.toFixed(1)}%` : "—"} tone="text-emerald-700" />}
            {features.eggs && <Summary label="Avg Eggs / Record" value={avgEggs.toLocaleString()} />}
            {features.eggs && <Summary label="Total Crates" value={Math.floor(t.eggs / EGGS_PER_CRATE).toLocaleString()} />}
            {features.milk && <Summary label="Total Milk" value={`${fmtNum(Math.round(t.milk * 10) / 10)} L`} />}
            <Summary label="Deaths (filtered)" value={t.deaths.toLocaleString()} tone="text-red-600" />
            <Summary label="Feed & medicine cost" value={fmtMoney(t.cost)} />
          </div>
        </>
      )}

      <LivestockProductionRecordModal open={formOpen} onOpenChange={setFormOpen} recordId={editingId} presetGroupId={presetGroupId} onSaved={load} />

      <DayRecords open={dayOpen} onOpenChange={setDayOpen} rows={rows} eggs={features.eggs} milk={features.milk}
        onEdit={(id) => { setDayOpen(false); openEdit(id) }}
        onShowInTable={(d) => { setDateFrom(d); setDateTo(d); setDayOpen(false) }} />

      <ConfirmDeleteDialog
        open={!!deleting}
        onOpenChange={(o) => !o && setDeleting(null)}
        title="Delete this record?"
        description={deleting ? `${deleting.groupName}, ${fmtDate(deleting.date)}. Its deaths and culls go back onto the group, and its feed and medicine go back into stock.` : ""}
        successTitle="Record deleted"
        errorTitle="Not deleted"
        onConfirm={() => deleteProductionRecord(deleting!.recordId)}
        onSuccess={() => { setDeleting(null); load() }}
      />
    </LivestockPage>
  )
}

function Summary({ label, value, tone }: { label: string; value: string; tone?: string }) {
  return (
    <div className="rounded border bg-stone-50 p-2">
      <div className="text-xs text-stone-600">{label}</div>
      <div className={cn("text-lg font-bold", tone)}>{value}</div>
    </div>
  )
}

function pageNumbers(page: number, total: number): (number | "…")[] {
  if (total <= 7) return Array.from({ length: total }, (_, i) => i + 1)
  const out: (number | "…")[] = [1]
  if (page > 3) out.push("…")
  for (let p = Math.max(2, page - 1); p <= Math.min(total - 1, page + 1); p++) out.push(p)
  if (page < total - 2) out.push("…")
  out.push(total)
  return out
}

/** Every record on one day, across all groups -- the page filters do not apply. */
function DayRecords({ open, onOpenChange, rows, eggs, milk, onEdit, onShowInTable }: {
  open: boolean
  onOpenChange: (o: boolean) => void
  rows: Row[]
  eggs: boolean
  milk: boolean
  onEdit: (recordId: number) => void
  onShowInTable: (day: string) => void
}) {
  const latest = useMemo(() => rows.reduce((m, r) => (r.date > m ? r.date : m), ""), [rows])
  const [day, setDay] = useState("")
  useEffect(() => { if (open) setDay(latest || todayIso()) }, [open, latest])
  const shift = (n: number) => {
    const d = new Date(day + "T00:00:00"); d.setDate(d.getDate() + n)
    setDay(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`)
  }
  const list = rows.filter((r) => r.date === day).sort((a, b) => a.groupName.localeCompare(b.groupName))
  const sum = (f: (r: Row) => number) => list.reduce((s, r) => s + f(r), 0)
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-4xl sm:max-w-4xl">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2"><CalendarDays className="h-5 w-5 text-amber-700" /> Records by day</DialogTitle>
          <DialogDescription>Every production record logged on the chosen day, for all groups.</DialogDescription>
        </DialogHeader>
        <div className="flex flex-wrap items-center gap-2">
          <Button variant="outline" size="icon" aria-label="Day before" onClick={() => shift(-1)}><ChevronLeft className="h-4 w-4" /></Button>
          <Input type="date" className="w-44" value={day} max={todayIso()} onChange={(e) => setDay(e.target.value)} />
          <Button variant="outline" size="icon" aria-label="Day after" disabled={day >= todayIso()} onClick={() => shift(1)}><ChevronRight className="h-4 w-4" /></Button>
          <span className="text-sm font-medium text-stone-700">{day && new Date(day + "T00:00:00").toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric", year: "numeric" })}</span>
          <Button variant="link" className="ml-auto text-amber-800" disabled={!list.length} onClick={() => onShowInTable(day)}>Show in table</Button>
        </div>
        {list.length === 0 ? <p className="py-8 text-center text-sm text-stone-500">No records on this day.</p> : (
          <div className="max-h-[60vh] overflow-auto rounded-md border">
            <Table className="text-xs">
              <TableHeader>
                <TableRow>
                  <TableHead>Group</TableHead><TableHead>Batch</TableHead>
                  {eggs && <><TableHead className="text-right">Eggs</TableHead><TableHead className="text-right">Broken</TableHead></>}
                  {milk && <TableHead className="text-right">Milk (L)</TableHead>}
                  <TableHead className="text-right">Feed</TableHead><TableHead className="text-right">Animals</TableHead>
                  <TableHead className="text-right">Died</TableHead><TableHead className="text-right">Culled</TableHead><TableHead className="text-right">Left</TableHead><TableHead />
                </TableRow>
              </TableHeader>
              <TableBody>
                {list.map((r) => (
                  <TableRow key={r.recordId}>
                    <TableCell className="font-medium">{r.groupName}</TableCell><TableCell>{r.batchCode}</TableCell>
                    {eggs && <><TableCell className="text-right">{r.eggsCollected ?? "—"}</TableCell><TableCell className="text-right">{r.eggsBroken ?? "—"}</TableCell></>}
                    {milk && <TableCell className="text-right">{r.milkLitres ?? "—"}</TableCell>}
                    <TableCell className="text-right">{fmtNum(r.feedTotal)}</TableCell><TableCell className="text-right">{fmtNum(r.headStart)}</TableCell>
                    <TableCell className="text-right">{r.deaths}</TableCell><TableCell className="text-right">{r.culls}</TableCell><TableCell className="text-right">{fmtNum(r.headEndOfDay)}</TableCell>
                    <TableCell className="text-right"><Button variant="ghost" size="sm" className="h-7 px-2 text-xs" onClick={() => onEdit(r.recordId)}>Edit</Button></TableCell>
                  </TableRow>
                ))}
                <TableRow className="bg-stone-50 font-semibold">
                  <TableCell>Totals</TableCell><TableCell />
                  {eggs && <><TableCell className="text-right">{sum((r) => r.eggsCollected ?? 0).toLocaleString()}</TableCell><TableCell className="text-right">{sum((r) => r.eggsBroken ?? 0)}</TableCell></>}
                  {milk && <TableCell className="text-right">{fmtNum(sum((r) => r.milkLitres ?? 0))}</TableCell>}
                  <TableCell className="text-right">{fmtNum(sum((r) => r.feedTotal))}</TableCell><TableCell className="text-right">{fmtNum(sum((r) => r.headStart))}</TableCell>
                  <TableCell className="text-right">{sum((r) => r.deaths)}</TableCell><TableCell className="text-right">{sum((r) => r.culls)}</TableCell><TableCell className="text-right">{fmtNum(sum((r) => r.headEndOfDay))}</TableCell><TableCell />
                </TableRow>
              </TableBody>
            </Table>
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}
