"use client"

// =============================================================================
// PoultryReportView — the shared engine behind all 20 Advanced Poultry Reports.
// Each report page renders <PoultryReportView slug="..." />; this component
// gates to Poultry farms, loads filter data, fetches the report, and renders
// the summary cards, detail table, states, and CSV / PDF / email export.
// =============================================================================

import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { ArrowLeft, AlertTriangle } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useFmt, useFarmSettingsStore } from "@/lib/currency"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { getUserContext } from "@/lib/api/config"
import { getFlocks, type Flock } from "@/lib/api/flock"
import { getCustomers } from "@/lib/api/customer"
import { defaultReportRange, rangeToPeriod, PERIOD_GROUPS } from "@/lib/date-ranges"
import { fetchPoultryReport, type PoultryReportResponse, type PoultryReportSlug } from "@/lib/api/poultry-reports"
import { POULTRY_REPORT_DEFS, type FmtCtx, type Accent } from "@/lib/reports/poultry-report-defs"
import {
  PoultryReportFilter, type PoultryReportFilterValue,
} from "@/components/poultry-reports/poultry-report-filter"
import {
  PoultryReportSummaryCards, PoultryReportTable, PoultryReportBreakdown, PoultryReportExportButtons,
  PoultryReportLoadingState, PoultryReportEmptyState, PoultryReportErrorState,
  type SummaryCard,
} from "@/components/poultry-reports/poultry-report-ui"
import { exportTableToPdf, emailTableAsPdf, type PdfExportOptions } from "@/lib/utils/pdf-export"

export function PoultryReportView({ slug, chrome = "page" }: { slug: PoultryReportSlug; chrome?: "page" | "embedded" }) {
  const def = POULTRY_REPORT_DEFS[slug]
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const farmName = useAuthStore((s) => s.activeFarmName)
  const user = useAuthStore((s) => s.user)
  const companyEmail = useAuthStore((s) => s.companies.find((c) => c.farmId === s.activeFarmId)?.email)
  const settings = useFarmSettingsStore((s) => s.settings)
  const fmtMoney = useFmt()
  const logout = useLogout()
  const { toast } = useToast()

  const initialRange = useMemo(() => defaultReportRange(), [])
  const [filter, setFilter] = useState<PoultryReportFilterValue>({
    fromDate: initialRange.from,
    toDate: initialRange.to,
    flockId: null,
    customerName: null,
    supplierName: null,
    includeClosedFlocks: false,
  })

  const [flocks, setFlocks] = useState<Flock[]>([])
  const [customers, setCustomers] = useState<string[]>([])
  const [data, setData] = useState<PoultryReportResponse | null>(null)
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [downloading, setDownloading] = useState(false)
  const [emailOpen, setEmailOpen] = useState(false)
  const [recipient, setRecipient] = useState("")
  const [sending, setSending] = useState(false)
  const [generatedAt, setGeneratedAt] = useState("")
  useEffect(() => { setGeneratedAt(new Date().toLocaleString()) }, [])

  // Gate: these reports only exist inside a poultry company context.
  const isWrongFarm = !!activeFarmType && activeFarmType !== "Poultry"
  useEffect(() => {
    if (isWrongFarm) router.replace("/dashboard")
  }, [isWrongFarm, router])

  // Load filter dropdown data once.
  useEffect(() => {
    if (isWrongFarm) return
    const { farmId, userId } = getUserContext()
    if (def.filters.flock) {
      getFlocks(userId, farmId)
        .then((res) => setFlocks((res.data ?? []).filter((f) => f && f.flockId != null)))
        .catch(() => setFlocks([]))
    }
    if (def.filters.customer) {
      getCustomers(userId, farmId)
        .then((res: any) => {
          const list = (res?.data ?? []) as { name?: string }[]
          setCustomers(Array.from(new Set(list.map((c) => c.name).filter(Boolean) as string[])).sort())
        })
        .catch(() => setCustomers([]))
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isWrongFarm])

  const load = useCallback(async () => {
    if (isWrongFarm) return
    setBusy(true)
    setError(null)
    try {
      const res = await fetchPoultryReport(slug, {
        startDate: filter.fromDate,
        endDate: filter.toDate,
        datePreset: rangeToPeriod(filter.fromDate, filter.toDate),
        flockId: def.filters.flock ? filter.flockId : undefined,
        customerName: def.filters.customer ? filter.customerName : undefined,
        supplierName: def.filters.supplier ? filter.supplierName : undefined,
        includeClosedFlocks: def.filters.includeClosedFlocks ? filter.includeClosedFlocks : undefined,
      })
      setData(res)
    } catch (e: any) {
      setError(e?.message ?? "Could not load the report.")
      setData(null)
    } finally {
      setBusy(false)
    }
  }, [slug, def, filter, isWrongFarm])

  // Refetch whenever the filter changes (debounced a touch for date typing).
  const firstRun = useRef(true)
  useEffect(() => {
    const t = setTimeout(load, firstRun.current ? 0 : 250)
    firstRun.current = false
    return () => clearTimeout(t)
  }, [load])

  // Formatting context handed to the column / card definitions.
  //
  // Two flavours, differing only in money: TABLE cells print bare numbers (the
  // currency is stated once in the report header — repeating "GHC" down every
  // column is noise), while SCORECARDS keep the symbol so a headline figure
  // reads as money on its own.
  const baseCtx = useMemo(() => ({
    num: (n: number | null | undefined) => (n == null ? "N/A" : Number(n).toLocaleString(undefined, { maximumFractionDigits: 2 })),
    pct: (n: number | null | undefined) => (n == null ? "N/A" : `${Number(n).toFixed(1)}%`),
    date: (s: string | null | undefined) => (s ? String(s).slice(0, 10) : "—"),
    text: (s: unknown) => (s == null || String(s).trim() === "" ? "—" : String(s)),
  }), [])

  const ctx: FmtCtx = useMemo(() => ({
    ...baseCtx,
    money: (n) => (n == null ? "N/A" : fmtMoney(Number(n), { showSymbol: false })),
  }), [baseCtx, fmtMoney])

  const cardCtx: FmtCtx = useMemo(() => ({
    ...baseCtx,
    money: (n) => (n == null ? "N/A" : fmtMoney(Number(n))),
  }), [baseCtx, fmtMoney])

  const cards: SummaryCard[] = useMemo(() => {
    if (!data?.summary) return []
    return def.cards.map((c) => ({
      label: c.label,
      value: c.value(data.summary, cardCtx),
      accent: typeof c.accent === "function" ? c.accent(data.summary) : c.accent,
    }))
  }, [data, def, cardCtx])

  const rows = data?.rows ?? []
  const currencyLabel = `${settings?.currencyCode ?? "GHS"} (${settings?.currencySymbol ?? "GHC"})`

  // For Profit & Loss reports (def.tableAsCards) render each row as TWO
  // scorecards — a Revenue card and an Expenses & Profit card — each with a
  // headline figure and its line items inside. Multi-row reports (e.g. by
  // flock) label each pair with def.cardRowLabel's column value.
  const cardRows = useMemo(() => {
    if (!def.tableAsCards || rows.length === 0) return null
    const labelHeader = def.cardRowLabel
    const isRevenue = (h: string) => h.includes("rev") || h.includes("sales")
    const cols = def.columns.filter((c) => c.header !== labelHeader)
    const pick = (arr: { label: string; value: string }[], kw: string) => {
      const i = arr.findIndex((x) => x.label.toLowerCase().includes(kw))
      const idx = i === -1 ? arr.length - 1 : i
      return { headline: arr[idx], items: arr.filter((_, n) => n !== idx) }
    }
    return rows.map((row, ri) => {
      // These render as scorecards, not a table — keep the currency symbol.
      const build = (keep: (h: string) => boolean) =>
        cols.filter((c) => keep(c.header.toLowerCase())).map((c) => ({ label: c.header, value: c.cell(row, cardCtx) }))
      return {
        key: ri,
        label: labelHeader ? (def.columns.find((c) => c.header === labelHeader)?.cell(row, cardCtx) ?? null) : null,
        revenue: pick(build(isRevenue), "total revenue"),
        // "Expenses details" headlines the total expenses (Total cost). Net
        // profit is excluded entirely — it already shows in the KPI strip.
        expense: pick(build((h) => !isRevenue(h) && !h.includes("net profit")), "total cost"),
      }
    })
  }, [def, rows, cardCtx])

  // The selections the user actually made, in the words they saw on screen.
  // (The API echoes an `appliedFilters` dictionary, but it carries the raw
  // FlockId, the preset *slug*, and a date range that already has its own line
  // in the PDF header — so it read as gibberish on the export.)
  const filtersUsed = useMemo(() => {
    const out: { label: string; value: string }[] = []
    const preset = rangeToPeriod(filter.fromDate, filter.toDate)
    const presetLabel = PERIOD_GROUPS.flatMap((g) => g.options).find((o) => o.value === preset)?.label
    if (presetLabel && preset !== "custom") out.push({ label: "Period", value: presetLabel })
    if (def.filters.flock && filter.flockId != null) {
      const f = flocks.find((x) => x.flockId === filter.flockId)
      out.push({ label: "Flock", value: f?.name || `#${filter.flockId}` })
    }
    if (def.filters.customer && filter.customerName) out.push({ label: "Customer", value: filter.customerName })
    if (def.filters.supplier && filter.supplierName) out.push({ label: "Supplier", value: filter.supplierName })
    if (def.filters.includeClosedFlocks && filter.includeClosedFlocks) out.push({ label: "Closed flocks", value: "Included" })
    return out
  }, [def, filter, flocks])

  // --- exports ---------------------------------------------------------------
  const buildPdfOptions = useCallback((): PdfExportOptions => ({
    title: def.title,
    filename: `poultry-${slug}`,
    farmName: farmName ?? undefined,
    fromDate: filter.fromDate,
    toDate: filter.toDate,
    generatedBy: user?.username || user?.email || undefined,
    currencyLabel,
    orientation: def.columns.length > 8 ? "landscape" : "portrait",
    summaryCards: cards.map((c) => ({ label: c.label, value: c.value, accent: c.accent as ("green" | "rose" | "indigo" | undefined) })),
    filtersUsed,
    columns: def.columns.map((c) => ({ header: c.header, align: c.align })),
    rows: rows.map((row) => def.columns.map((c) => c.cell(row, ctx))),
  }), [def, slug, farmName, filter, user, currencyLabel, cards, filtersUsed, rows, ctx])

  const onPdf = useCallback(async () => {
    setDownloading(true)
    try {
      await exportTableToPdf(buildPdfOptions())
    } catch (e: any) {
      toast({ title: "Export failed", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setDownloading(false)
    }
  }, [buildPdfOptions, toast])

  const onCsv = useCallback(() => {
    const esc = (v: string) => `"${String(v).replace(/"/g, '""')}"`
    const header = def.columns.map((c) => esc(c.header)).join(",")
    const body = rows.map((row) => def.columns.map((c) => esc(c.cell(row, ctx))).join(",")).join("\n")
    const meta = `${esc(def.title)}\n${esc(`Farm: ${farmName ?? "—"}`)},${esc(`Period: ${filter.fromDate} to ${filter.toDate}`)}\n\n`
    const csv = meta + header + "\n" + body
    const blob = new Blob(["﻿" + csv], { type: "text/csv;charset=utf-8;" })
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = `poultry-${slug}-${filter.fromDate}_${filter.toDate}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }, [def, rows, ctx, slug, filter, farmName])

  const onEmail = useCallback(() => {
    setRecipient(companyEmail || user?.email || "")
    setEmailOpen(true)
  }, [companyEmail, user])

  const sendEmail = useCallback(async () => {
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
  }, [recipient, buildPdfOptions, toast])

  const resetFilters = () => setFilter({
    fromDate: initialRange.from, toDate: initialRange.to,
    flockId: null, customerName: null, supplierName: null, includeClosedFlocks: false,
  })

  const hasData = !!data && rows.length > 0
  const embedded = chrome === "embedded"

  // The report body (toolbar + white card). Shared by the standalone page and
  // the embedded-in-Reports-tab mode.
  const body = (
    <>
      <div className="mb-4 flex items-center justify-between gap-2 flex-wrap print:hidden">
        {embedded ? <div /> : (
          <Button asChild variant="outline" size="sm">
            <Link href="/poultry/reports"><ArrowLeft className="h-4 w-4 mr-1" /> Poultry reports</Link>
          </Button>
        )}
        <PoultryReportExportButtons
          onCsv={onCsv} onPdf={onPdf} onEmail={onEmail}
          busy={downloading} disabled={busy || !hasData}
        />
      </div>

      <div className="bg-white rounded-xl border border-slate-200 shadow-sm overflow-hidden print:border-0 print:shadow-none">
        <div className="h-1.5 bg-gradient-to-r from-amber-500 to-amber-400 print:hidden" />
        <div className="p-4 sm:p-6 print:p-0">
          <header className="mb-4 border-b border-slate-200 pb-4">
            <div className="text-xs font-semibold uppercase tracking-wider text-amber-700">{farmName ?? "Poultry farm"}</div>
            <h1 className="text-2xl font-semibold text-slate-900 mt-0.5">{def.title}</h1>
            <p className="text-sm text-slate-500 mt-1">{def.description}</p>
            <div className="mt-3 grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-1 text-sm text-slate-500">
              <div><span className="font-medium text-slate-600">Period:</span> {filter.fromDate} → {filter.toDate}</div>
              <div><span className="font-medium text-slate-600">Currency:</span> {currencyLabel}</div>
              <div><span className="font-medium text-slate-600">Generated:</span> {generatedAt}</div>
              <div><span className="font-medium text-slate-600">Records:</span> {rows.length.toLocaleString()}</div>
            </div>
          </header>

          <PoultryReportFilter
            value={filter}
            onChange={setFilter}
            onReset={resetFilters}
            show={def.filters}
            flocks={flocks}
            customers={customers}
          />

          {/* Data-availability notices from the backend (graceful degradation). */}
          {data?.warnings && data.warnings.length > 0 && (
            <div className="mb-4 rounded-md bg-amber-50 border border-amber-200 px-3 py-2 text-xs text-amber-800 space-y-1">
              {data.warnings.map((w, i) => (
                <div key={i} className="flex items-start gap-2">
                  <AlertTriangle className="h-3.5 w-3.5 mt-0.5 shrink-0" />
                  <span className="min-w-0 break-words">{w}</span>
                </div>
              ))}
            </div>
          )}

          {error && <div className="mb-4"><PoultryReportErrorState message={error} onRetry={load} /></div>}

          {busy ? (
            <PoultryReportLoadingState />
          ) : !hasData ? (
            <PoultryReportEmptyState />
          ) : (
            <>
              {/* KPI summary strip — shown for every report, including the P&L
                  card reports (Total revenue / expenses / Gross & Net profit /
                  margin) that used to hide it under tableAsCards. */}
              {cards.length > 0 && <PoultryReportSummaryCards cards={cards} />}
              {def.tableAsCards && cardRows ? (
                <div className="space-y-5">
                  {cardRows.map((cr) => (
                    <div key={cr.key}>
                      {cr.label && (
                        <div className="mb-2 text-sm font-semibold text-slate-800">{cr.label}</div>
                      )}
                      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                        {/* Revenue card */}
                        <div className="relative overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm print:border print:shadow-none">
                          <div className="absolute inset-y-0 left-0 w-1 bg-emerald-500" />
                          <div className="p-4 pl-5">
                            <div className="text-xs uppercase tracking-wider text-slate-500">Revenue Details</div>
                            <div className="text-2xl font-semibold tabular-nums mt-1 text-emerald-700 break-words">{cr.revenue.headline?.value ?? "—"}</div>
                            <div className="mt-3 space-y-1.5 border-t border-slate-100 pt-3">
                              {cr.revenue.items.map((it) => (
                                <div key={it.label} className="flex items-center justify-between gap-3 text-sm">
                                  <span className="text-slate-500">{it.label}</span>
                                  <span className="tabular-nums font-medium text-slate-800">{it.value}</span>
                                </div>
                              ))}
                            </div>
                          </div>
                        </div>

                        {/* Expenses & Profit card */}
                        <div className="relative overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm print:border print:shadow-none">
                          <div className="absolute inset-y-0 left-0 w-1 bg-rose-500" />
                          <div className="p-4 pl-5">
                            <div className="text-xs uppercase tracking-wider text-slate-500">Expenses details</div>
                            <div className="text-2xl font-semibold tabular-nums mt-1 text-slate-900 break-words">{cr.expense.headline?.value ?? "—"}</div>
                            <div className="mt-3 space-y-1.5 border-t border-slate-100 pt-3">
                              {cr.expense.items.map((it) => (
                                <div key={it.label} className="flex items-center justify-between gap-3 text-sm">
                                  <span className="text-slate-500">{it.label}</span>
                                  <span className="tabular-nums font-medium text-slate-800">{it.value}</span>
                                </div>
                              ))}
                            </div>
                          </div>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <PoultryReportTable columns={def.columns} rows={rows} ctx={ctx} />
              )}
              {/* Card-style summary panel, not the data table — keeps the symbol. */}
              {def.breakdown && data?.summary && !def.tableAsCards && (
                <PoultryReportBreakdown groups={def.breakdown} summary={data.summary} ctx={cardCtx} />
              )}
            </>
          )}
        </div>
      </div>
    </>
  )

  const emailDialog = (
    <Dialog open={emailOpen} onOpenChange={(o) => { if (!sending) setEmailOpen(o) }}>
      <DialogContent className="print:hidden">
        <DialogHeader><DialogTitle>Email “{def.title}”</DialogTitle></DialogHeader>
        <div className="space-y-2">
          <Label htmlFor="poultry-report-email" className="text-xs">Recipient email(s)</Label>
          <Input
            id="poultry-report-email"
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
  )

  // Embedded mode (inside the Reports page tabs): render just the body — the
  // page already provides the sidebar, header and slate background.
  if (embedded) {
    return <>{body}{emailDialog}</>
  }

  return (
    <div className="flex min-h-screen bg-slate-50 print:bg-white">
      <div className="print:hidden"><DashboardSidebar onLogout={logout} /></div>
      <div className="flex-1 flex flex-col min-w-0">
        <div className="print:hidden"><DashboardHeader /></div>
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 print:p-0 min-w-0">
          {body}
        </main>
      </div>
      {emailDialog}
    </div>
  )
}
