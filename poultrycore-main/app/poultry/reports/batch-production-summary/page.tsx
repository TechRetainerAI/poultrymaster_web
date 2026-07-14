"use client"

// =============================================================================
// Batch Production Summary (/poultry/reports/batch-production-summary)
//
// Rolls up daily production records to the flock-batch level: for each batch it
// aggregates every production record whose flock belongs to that batch (eggs,
// feed, deaths, laying %, etc.). Aggregation is done client-side from the
// existing production-records / flocks / batches endpoints, so there is no new
// backend. Surfaced in the Reports mega-menu under Production.
// =============================================================================

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Boxes, ArrowLeft, Search, RefreshCw } from "lucide-react"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useAuthStore } from "@/lib/store/auth-store"
import { getUserContext } from "@/lib/utils/user-context"
import { getProductionRecords, type ProductionRecord } from "@/lib/api/production-record"
import { getFlocks, type Flock } from "@/lib/api/flock"
import { getFlockBatches, type FlockBatch } from "@/lib/api/flock-batch"
import { sumLatestBirdsLeftByFlock } from "@/lib/utils/production-records"
import { toLocalDateKey } from "@/lib/utils/date-key"
import { cn } from "@/lib/utils"
import { exportTableToPdf, emailTableAsPdf, type PdfExportColumn, type PdfExportOptions } from "@/lib/utils/pdf-export"
import { PoultryReportExportButtons } from "@/components/poultry-reports/poultry-report-ui"

const EGGS_PER_CRATE = 30

interface BatchRow {
  batchId: number
  batchName: string
  batchCode: string
  breed: string
  status: string
  flockCount: number
  birdsPlaced: number
  currentBirds: number
  totalEggs: number
  broken: number
  avgDaily: number
  peakDaily: number
  prodPct: number | null
  feedKg: number
  deaths: number
  records: number
}

const num = (n: number) => Math.round(n).toLocaleString()
const pct = (v: number | null) => (v == null ? "—" : `${v.toFixed(1)}%`)

export default function BatchProductionSummaryReport() {
  const router = useRouter()
  const logout = useLogout()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const user = useAuthStore((s) => s.user)
  const companyEmail = useAuthStore((s) => s.companies.find((c) => c.farmId === s.activeFarmId)?.email)

  const [records, setRecords] = useState<ProductionRecord[]>([])
  const [flocks, setFlocks] = useState<Flock[]>([])
  const [batches, setBatches] = useState<FlockBatch[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")

  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")

  // Export / email state — mirrors the other advanced poultry reports.
  const [downloading, setDownloading] = useState(false)
  const [emailOpen, setEmailOpen] = useState(false)
  const [sending, setSending] = useState(false)
  const [recipient, setRecipient] = useState("")

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  const load = async () => {
    setLoading(true)
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      setError("User context not found. Please log in again.")
      setLoading(false)
      return
    }
    const [recRes, flockRes, batchRes] = await Promise.all([
      getProductionRecords(userId, farmId),
      getFlocks(userId, farmId),
      getFlockBatches(userId, farmId),
    ])
    if (recRes.success && recRes.data) { setRecords(recRes.data); setError("") }
    else setError(recRes.message || "Failed to load production records")
    if (flockRes.success && flockRes.data) setFlocks(flockRes.data)
    if (batchRes.success && batchRes.data) setBatches(batchRes.data)
    setLoading(false)
  }

  // Records → flock → batch aggregation.
  const rows = useMemo<BatchRow[]>(() => {
    let recs = records.slice()
    if (dateFrom) recs = recs.filter((r) => toLocalDateKey(r.date) >= dateFrom)
    if (dateTo) recs = recs.filter((r) => toLocalDateKey(r.date) <= dateTo)

    const batchIdByFlockId = new Map<number, number | null>()
    const flocksByBatch = new Map<number, Set<number>>()
    for (const f of flocks) {
      batchIdByFlockId.set(f.flockId, f.batchId ?? null)
      if (f.batchId != null) {
        if (!flocksByBatch.has(f.batchId)) flocksByBatch.set(f.batchId, new Set())
        flocksByBatch.get(f.batchId)!.add(f.flockId)
      }
    }

    const out: BatchRow[] = batches.map((b) => {
      const recsForBatch = recs.filter((r: any) => r.flockId != null && batchIdByFlockId.get(r.flockId) === b.batchId)
      const totalEggs = recsForBatch.reduce((s, r) => s + (Number(r.totalProduction) || 0), 0)
      const broken = recsForBatch.reduce((s, r) => s + (Number((r as any).brokenEggs) || 0), 0)
      const feedKg = recsForBatch.reduce((s, r) => s + (Number(r.feedKg) || 0), 0)
      const deaths = recsForBatch.reduce((s, r) => s + (Number(r.mortality) || 0), 0)
      const sumBirds = recsForBatch.reduce((s, r) => s + (Number(r.noOfBirds) || 0), 0)
      const byDate = new Map<string, number>()
      for (const r of recsForBatch) {
        const k = toLocalDateKey(r.date)
        byDate.set(k, (byDate.get(k) || 0) + (Number(r.totalProduction) || 0))
      }
      const days = byDate.size
      return {
        batchId: b.batchId,
        batchName: b.batchName || `Batch #${b.batchId}`,
        batchCode: b.batchCode || "",
        breed: b.breed || "",
        status: b.status || "active",
        flockCount: flocksByBatch.get(b.batchId)?.size ?? 0,
        birdsPlaced: Number(b.numberOfBirds) || 0,
        currentBirds: sumLatestBirdsLeftByFlock(recsForBatch),
        totalEggs,
        broken,
        avgDaily: days ? totalEggs / days : 0,
        peakDaily: days ? Math.max(...byDate.values()) : 0,
        prodPct: sumBirds > 0 ? (totalEggs / sumBirds) * 100 : null,
        feedKg,
        deaths,
        records: recsForBatch.length,
      }
    })

    const q = search.trim().toLowerCase()
    const filtered = q
      ? out.filter((r) => r.batchName.toLowerCase().includes(q) || r.batchCode.toLowerCase().includes(q) || r.breed.toLowerCase().includes(q))
      : out
    return filtered.sort((a, b) => b.totalEggs - a.totalEggs || a.batchName.localeCompare(b.batchName))
  }, [records, flocks, batches, dateFrom, dateTo, search])

  const summary = useMemo(() => {
    const withProd = rows.filter((r) => r.records > 0).length
    const totalEggs = rows.reduce((s, r) => s + r.totalEggs, 0)
    const birdsPlaced = rows.reduce((s, r) => s + r.birdsPlaced, 0)
    const feedKg = rows.reduce((s, r) => s + r.feedKg, 0)
    const deaths = rows.reduce((s, r) => s + r.deaths, 0)
    const pcts = rows.map((r) => r.prodPct).filter((x): x is number => x != null)
    const avgPct = pcts.length ? pcts.reduce((a, b) => a + b, 0) / pcts.length : null
    return { withProd, totalBatches: rows.length, totalEggs, birdsPlaced, feedKg, deaths, avgPct }
  }, [rows])

  const clearFilters = () => { setSearch(""); setDateFrom(""); setDateTo("") }

  // Summary cards — semantic accent (green/rose) drives both the on-screen tile
  // colour and the accent bar in the exported PDF cards.
  const cards: { label: string; value: string; sub: string; accent?: "green" | "rose" }[] = [
    { label: "Batches", value: `${summary.withProd}`, sub: `of ${summary.totalBatches} with production` },
    { label: "Total Eggs", value: num(summary.totalEggs), sub: `${Math.floor(summary.totalEggs / EGGS_PER_CRATE)}c + ${summary.totalEggs % EGGS_PER_CRATE}p`, accent: "green" },
    { label: "Birds Placed", value: num(summary.birdsPlaced), sub: "across all batches" },
    { label: "Avg Production %", value: pct(summary.avgPct), sub: "eggs ÷ birds logged", accent: "green" },
    { label: "Feed (kg)", value: summary.feedKg.toFixed(2), sub: "total consumed" },
    { label: "Deaths", value: num(summary.deaths), sub: "in selected range", accent: "rose" },
  ]
  const accentText = (a?: "green" | "rose") => (a === "green" ? "text-emerald-600" : a === "rose" ? "text-red-600" : "text-slate-900")

  // --- Exports (mirror the other advanced reports: shared pdf-export util) -----
  const PDF_COLUMNS: PdfExportColumn[] = [
    { header: "Batch" }, { header: "Code" }, { header: "Breed" },
    { header: "Flocks", align: "right" }, { header: "Birds placed", align: "right" },
    { header: "Current birds", align: "right" }, { header: "Total eggs", align: "right" },
    { header: "Avg daily", align: "right" }, { header: "Peak daily", align: "right" },
    { header: "Broken", align: "right" }, { header: "Prod %", align: "right" },
    { header: "Feed (kg)", align: "right" }, { header: "Deaths", align: "right" },
  ]
  const rowToCells = (r: BatchRow): (string | number)[] => [
    r.batchName, r.batchCode || "—", r.breed || "—", r.flockCount, num(r.birdsPlaced), num(r.currentBirds),
    num(r.totalEggs), num(r.avgDaily), num(r.peakDaily), num(r.broken), pct(r.prodPct), r.feedKg.toFixed(2), num(r.deaths),
  ]
  const totalsCells: (string | number)[] = [
    "Totals", "", "", rows.reduce((s, r) => s + r.flockCount, 0), num(summary.birdsPlaced),
    num(rows.reduce((s, r) => s + r.currentBirds, 0)), num(summary.totalEggs), "", "",
    num(rows.reduce((s, r) => s + r.broken, 0)), pct(summary.avgPct), summary.feedKg.toFixed(2), num(summary.deaths),
  ]

  const buildPdfOptions = (): PdfExportOptions => ({
    title: "Batch Production Summary",
    filename: "poultry-batch-production-summary",
    fromDate: dateFrom || undefined,
    toDate: dateTo || undefined,
    generatedBy: user?.username || user?.email || undefined,
    orientation: "landscape",
    summaryCards: cards.map((c) => ({ label: c.label, value: c.value, accent: c.accent })),
    filtersUsed: search.trim() ? [{ label: "Search", value: search.trim() }] : [],
    columns: PDF_COLUMNS,
    rows: rows.map(rowToCells),
    totalsRow: rows.length ? totalsCells : undefined,
  })

  const onPdf = async () => {
    setDownloading(true)
    try {
      await exportTableToPdf(buildPdfOptions())
    } catch (e: any) {
      toast({ title: "Export failed", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setDownloading(false)
    }
  }

  const onCsv = () => {
    const esc = (v: string) => `"${String(v).replace(/"/g, '""')}"`
    const farmName = typeof window !== "undefined" ? localStorage.getItem("farmName") : null
    const header = PDF_COLUMNS.map((c) => esc(c.header)).join(",")
    const body = rows.map((r) => rowToCells(r).map((v) => esc(String(v))).join(",")).join("\n")
    const period = `Period: ${dateFrom || "all"} to ${dateTo || "all"}`
    const meta = `${esc("Batch Production Summary")}\n${esc(`Farm: ${farmName ?? "—"}`)},${esc(period)}\n\n`
    const csv = meta + header + "\n" + body
    const blob = new Blob(["﻿" + csv], { type: "text/csv;charset=utf-8;" })
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = `poultry-batch-production-summary-${dateFrom || "all"}_${dateTo || "all"}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  const onEmail = () => {
    setRecipient(companyEmail || user?.email || "")
    setEmailOpen(true)
  }

  const sendEmail = async () => {
    const recipients = recipient.split(/[,;\n]/).map((s) => s.trim()).filter(Boolean)
    const emailRe = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
    if (recipients.length === 0 || recipients.some((e) => !emailRe.test(e))) {
      toast({ title: "Enter a valid email address", variant: "destructive" })
      return
    }
    setSending(true)
    try {
      const res = await emailTableAsPdf(buildPdfOptions(), { to: recipients.join(",") })
      if (res.success) {
        toast({ title: "Report emailed", description: `Sent to ${recipients.length === 1 ? recipients[0] : `${recipients.length} recipients`}.` })
        setEmailOpen(false)
      } else {
        toast({ title: "Email failed", description: res.message ?? "Could not send.", variant: "destructive" })
      }
    } catch (e: any) {
      toast({ title: "Email failed", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSending(false)
    }
  }

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-x-hidden px-2 py-4 sm:p-6 pb-20 lg:pb-4">
          <div className="space-y-4 sm:space-y-6 min-w-0 w-full">
            {/* Header */}
            <div className="flex items-start gap-3 min-w-0">
              <Button variant="ghost" size="icon" onClick={() => router.push("/poultry/reports")} className="shrink-0">
                <ArrowLeft className="w-5 h-5" />
              </Button>
              <div className="w-10 h-10 shrink-0 bg-emerald-100 rounded-lg flex items-center justify-center">
                <Boxes className="w-5 h-5 text-emerald-600" />
              </div>
              <div className="min-w-0">
                <h1 className="text-xl sm:text-2xl font-bold text-slate-900 truncate">Batch Production Summary</h1>
                <p className="text-sm text-slate-600">Production performance rolled up per flock batch.</p>
              </div>
            </div>

            {error && <Alert variant="destructive"><AlertDescription>{error}</AlertDescription></Alert>}

            {/* Filters */}
            <div className="flex flex-row flex-wrap items-center gap-2 p-2 bg-white rounded-lg border">
              <div className="relative w-[240px] min-w-0">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                <Input placeholder="Search batch, code, breed…" value={search} onChange={(e) => setSearch(e.target.value)} className="pl-9" />
              </div>
              <Input type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} className="w-[150px]" />
              <Input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} className="w-[150px]" />
              <div className="ml-auto flex items-center gap-2">
                <Button variant="outline" size="sm" onClick={clearFilters}><RefreshCw className="h-4 w-4 mr-2" /> Reset</Button>
                <PoultryReportExportButtons
                  onCsv={onCsv} onPdf={onPdf} onEmail={onEmail}
                  busy={downloading} disabled={loading || rows.length === 0}
                />
              </div>
            </div>

            {/* Summary cards */}
            {!loading && (
              <div className="grid grid-cols-2 sm:grid-cols-3 xl:grid-cols-6 gap-3">
                {cards.map((c) => (
                  <div key={c.label} className="p-4 bg-white rounded-xl border border-slate-200 shadow-sm">
                    <div className="text-xs font-medium text-slate-500 uppercase tracking-wider">{c.label}</div>
                    <div className={cn("text-xl font-bold mt-1 tabular-nums", accentText(c.accent))}>{c.value}</div>
                    <div className="text-xs text-slate-400 mt-0.5">{c.sub}</div>
                  </div>
                ))}
              </div>
            )}

            {/* Table */}
            {loading ? (
              <Card className="bg-white"><CardContent className="py-6">
                <div className="space-y-3">{[...Array(5)].map((_, i) => <div key={i} className="h-10 w-full bg-slate-50 animate-pulse rounded" />)}</div>
              </CardContent></Card>
            ) : (
              <Card className="bg-white overflow-hidden">
                <CardContent className="p-0">
                  <div className="overflow-x-auto">
                    <Table className="min-w-[1100px]">
                      <TableHeader className="sticky top-0 bg-emerald-50 z-10">
                        <TableRow className="border-b border-emerald-200">
                          <TableHead className="px-3 py-2 min-w-[160px]">Batch</TableHead>
                          <TableHead className="px-3 py-2">Code</TableHead>
                          <TableHead className="px-3 py-2">Breed</TableHead>
                          <TableHead className="px-3 py-2 text-right">Flocks</TableHead>
                          <TableHead className="px-3 py-2 text-right">Birds placed</TableHead>
                          <TableHead className="px-3 py-2 text-right">Current birds</TableHead>
                          <TableHead className="px-3 py-2 text-right">Total eggs</TableHead>
                          <TableHead className="px-3 py-2 text-right">Avg daily</TableHead>
                          <TableHead className="px-3 py-2 text-right">Peak daily</TableHead>
                          <TableHead className="px-3 py-2 text-right">Broken</TableHead>
                          <TableHead className="px-3 py-2 text-right">Prod %</TableHead>
                          <TableHead className="px-3 py-2 text-right">Feed (kg)</TableHead>
                          <TableHead className="px-3 py-2 text-right">Deaths</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {rows.length === 0 ? (
                          <TableRow><TableCell colSpan={13} className="py-12 text-center text-slate-500">No batches found for the selected filters.</TableCell></TableRow>
                        ) : rows.map((r, idx) => (
                          <TableRow key={r.batchId} className={cn("hover:bg-slate-50/60", idx % 2 === 0 ? "bg-white" : "bg-slate-50/40")}>
                            <TableCell className="px-3 py-2 font-medium text-slate-800">{r.batchName}</TableCell>
                            <TableCell className="px-3 py-2 text-slate-600">{r.batchCode || "—"}</TableCell>
                            <TableCell className="px-3 py-2 text-slate-600">{r.breed || "—"}</TableCell>
                            <TableCell className="px-3 py-2 text-right">{r.flockCount}</TableCell>
                            <TableCell className="px-3 py-2 text-right">{num(r.birdsPlaced)}</TableCell>
                            <TableCell className="px-3 py-2 text-right">{num(r.currentBirds)}</TableCell>
                            <TableCell className="px-3 py-2 text-right font-semibold text-emerald-700">{num(r.totalEggs)}</TableCell>
                            <TableCell className="px-3 py-2 text-right">{num(r.avgDaily)}</TableCell>
                            <TableCell className="px-3 py-2 text-right">{num(r.peakDaily)}</TableCell>
                            <TableCell className="px-3 py-2 text-right text-red-700">{num(r.broken)}</TableCell>
                            <TableCell className="px-3 py-2 text-right">{pct(r.prodPct)}</TableCell>
                            <TableCell className="px-3 py-2 text-right">{r.feedKg.toFixed(2)}</TableCell>
                            <TableCell className="px-3 py-2 text-right">
                              <span className={cn("px-2 py-0.5 rounded text-xs", r.deaths > 0 ? "bg-red-50 text-red-700" : "bg-slate-50 text-slate-600")}>{num(r.deaths)}</span>
                            </TableCell>
                          </TableRow>
                        ))}
                        {rows.length > 0 && (
                          <TableRow className="bg-slate-50/60 font-semibold">
                            <TableCell className="px-3 py-2">Totals</TableCell>
                            <TableCell /><TableCell />
                            <TableCell className="px-3 py-2 text-right">{rows.reduce((s, r) => s + r.flockCount, 0)}</TableCell>
                            <TableCell className="px-3 py-2 text-right">{num(summary.birdsPlaced)}</TableCell>
                            <TableCell className="px-3 py-2 text-right">{num(rows.reduce((s, r) => s + r.currentBirds, 0))}</TableCell>
                            <TableCell className="px-3 py-2 text-right text-emerald-700">{num(summary.totalEggs)}</TableCell>
                            <TableCell /><TableCell />
                            <TableCell className="px-3 py-2 text-right text-red-700">{num(rows.reduce((s, r) => s + r.broken, 0))}</TableCell>
                            <TableCell className="px-3 py-2 text-right">{pct(summary.avgPct)}</TableCell>
                            <TableCell className="px-3 py-2 text-right">{summary.feedKg.toFixed(2)}</TableCell>
                            <TableCell className="px-3 py-2 text-right text-red-700">{num(summary.deaths)}</TableCell>
                          </TableRow>
                        )}
                      </TableBody>
                    </Table>
                  </div>
                </CardContent>
              </Card>
            )}
          </div>
        </main>
      </div>

      {/* Email dialog — mirrors the other advanced poultry reports. */}
      <Dialog open={emailOpen} onOpenChange={(o) => { if (!sending) setEmailOpen(o) }}>
        <DialogContent>
          <DialogHeader><DialogTitle>Email “Batch Production Summary”</DialogTitle></DialogHeader>
          <div className="space-y-2">
            <Label htmlFor="batch-report-email" className="text-xs">Recipient email(s)</Label>
            <Input
              id="batch-report-email"
              value={recipient}
              onChange={(e) => setRecipient(e.target.value)}
              placeholder="owner@example.com, accountant@example.com"
            />
            <p className="text-xs text-slate-500">Separate multiple addresses with commas. A PDF of this report is generated and sent.</p>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setEmailOpen(false)} disabled={sending}>Cancel</Button>
            <Button onClick={sendEmail} disabled={sending}>{sending ? "Sending…" : "Send"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
