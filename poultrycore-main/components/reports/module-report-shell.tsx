"use client"

/**
 * The chrome every Restaurant report sits inside: page header, the date control
 * the report asked for, and the three export buttons.
 *
 * WHY A SHELL RATHER THAN 24 PAGES
 * The old /restaurant-reports was one 554-line file holding seven tabs. Six of
 * them rebuilt the same date toolbar by hand and each wired its own Download
 * button; the seventh (Trends) was simply forgotten and shipped with no export
 * at all. That is the failure mode this component exists to remove -- a report
 * cannot forget to offer PDF or CSV here, because it never implements them.
 *
 * HOW A REPORT TALKS TO IT
 * A report renders its own body and calls `setExport` with the flat table it
 * wants exported. The shell turns that single description into PDF, CSV and
 * print. One definition, three outputs, so the spreadsheet can never disagree
 * with the PDF.
 */

import Link from "next/link"
import { useEffect, useMemo, useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import {
  ArrowLeft, ChevronLeft, ChevronRight, Eye, FileSpreadsheet, Printer, Loader2,
} from "lucide-react"
import type { PdfReportConfig } from "@/lib/utils/download-pdf"
import { ReportPdfPreview } from "@/components/reports/report-pdf-preview"
import { downloadCsv } from "@/lib/utils/download-csv"
import { ReportEmailButton } from "@/components/reports/report-email-dialog"
import { printReport } from "@/lib/utils/print-report"
import type { LucideIcon } from "lucide-react"

/**
 * The shell describes what it needs STRUCTURALLY rather than importing a
 * module's catalog type. It used to import RestaurantReport directly, which
 * would have made Hotel depend on the Restaurant config to render a hotel
 * report. Both modules' catalog entries satisfy these shapes as they are, so
 * neither has to know about the other.
 */
export type ReportDateMode = "range" | "single" | "none"

export interface ShellReport {
  slug: string
  title: string
  description: string
  icon: LucideIcon
  dateMode: ReportDateMode
}

export interface ShellGroup {
  label: string
  /** Tailwind background class for the icon chip, e.g. "bg-violet-600". */
  color: string
}

/**
 * Module accents. Exports arrive in the colour the operator clicked in, rather
 * than in whichever module's palette the PDF helper was originally written for.
 *
 * This file started life under components/restaurant/. It was moved to
 * components/reports/ when Hotel needed the same shell, so it is now module-
 * agnostic: everything module-specific arrives through props.
 */
/** Paired with ReportEmailAccent in components/reports/report-email-dialog.tsx. */
export type ReportAccent = "rose" | "violet"

const ACCENTS: Record<ReportAccent, { pdf: [number, number, number]; button: string }> = {
  rose:   { pdf: [225, 29, 72],  button: "bg-rose-600 hover:bg-rose-700" },    // Restaurant
  violet: { pdf: [109, 40, 217], button: "bg-violet-600 hover:bg-violet-700" }, // Hotel
}

/** @deprecated Kept so existing imports keep working; prefer the `accent` prop. */
export const RESTAURANT_PDF_ACCENT: [number, number, number] = ACCENTS.rose.pdf

/** What a report hands the shell so it can be exported. */
export interface ReportExport {
  headers: string[]
  rows: (string | number | null | undefined)[][]
  /** Optional KPI strip reproduced at the top of the PDF and the printout. */
  summaryCards?: { label: string; value: string }[]
}

export interface ReportRange {
  from: string
  to: string
  /** The single-day value, for reports whose dateMode is "single". */
  date: string
}

export interface ReportBodyProps {
  range: ReportRange
  setExport: (e: ReportExport | null) => void
  /** Currency code from the property's profile, e.g. "GHS". */
  currency: string
}

function iso(d: Date): string {
  return d.toISOString().slice(0, 10)
}

function shiftDays(from: Date, days: number): Date {
  const d = new Date(from)
  d.setDate(d.getDate() + days)
  return d
}

/** The presets that replaced the old Daily / Weekly / Monthly report pages. */
const PRESETS: { label: string; compute: () => { from: string; to: string } }[] = [
  { label: "Today",      compute: () => ({ from: iso(new Date()), to: iso(new Date()) }) },
  { label: "7 days",     compute: () => ({ from: iso(shiftDays(new Date(), -6)), to: iso(new Date()) }) },
  { label: "30 days",    compute: () => ({ from: iso(shiftDays(new Date(), -29)), to: iso(new Date()) }) },
  {
    label: "This month",
    compute: () => {
      const n = new Date()
      return { from: iso(new Date(n.getFullYear(), n.getMonth(), 1)), to: iso(n) }
    },
  },
  {
    label: "Last month",
    compute: () => {
      const n = new Date()
      return {
        from: iso(new Date(n.getFullYear(), n.getMonth() - 1, 1)),
        to: iso(new Date(n.getFullYear(), n.getMonth(), 0)),
      }
    },
  },
]

export interface ReportShellProps {
  report: ShellReport
  group: ShellGroup
  range: ReportRange
  onRangeChange: (r: ReportRange) => void
  loading: boolean
  exportData: ReportExport | null
  /** Property name for the export header — the restaurant's or the hotel's. */
  propertyName: string
  propertyAddress?: string
  propertyPhone?: string
  currency: string
  /** Module palette. Defaults to rose so Restaurant's existing callers are unchanged. */
  accent?: ReportAccent
  /** Where the "All reports" crumb goes. Defaults to the Restaurant catalog. */
  indexHref?: string
  /**
   * Adds an "Email" button that sends this report as a PDF or CSV attachment.
   *
   * OPT-IN ON PURPOSE. This shell is used by Hotel, Restaurant, Generic, Poultry
   * and Water. Email was asked for on Hotel; defaulting it on would have put a
   * new button on roughly thirty reports across four other modules that nobody
   * requested. Turning it on elsewhere is this one prop.
   */
  enableEmail?: boolean
  children: React.ReactNode
}

export function ReportShell({
  report, group, range, onRangeChange, loading, exportData,
  propertyName, propertyAddress, propertyPhone, currency,
  accent = "rose", indexHref = "/restaurant-reports", enableEmail = false, children,
}: ReportShellProps) {
  const theme = ACCENTS[accent]
  const Icon = report.icon
  const [pdfOpen, setPdfOpen] = useState(false)

  // The period line printed on every export. A single-date report says the day,
  // a rangeless one says nothing rather than inventing a period it did not use.
  const periodLabel = useMemo(() => {
    if (report.dateMode === "single") return range.date
    if (report.dateMode === "none") return ""
    return `${range.from} to ${range.to}`
  }, [report.dateMode, range])

  const exportBase = useMemo(() => ({
    title: report.title,
    subtitle: periodLabel ? `${report.title} — ${periodLabel}` : report.title,
    hotelName: propertyName,
    hotelAddress: propertyAddress,
    hotelPhone: propertyPhone,
    currency,
    accent: theme.pdf,
    ...(report.dateMode === "range" ? { dateRange: { from: range.from, to: range.to } } : {}),
  }), [report, periodLabel, propertyName, propertyAddress, propertyPhone, currency, range])

  // The filename carries the period, so a folder of downloads stays sortable
  // and two exports of the same report never overwrite each other.
  const filename = useMemo(() => {
    const suffix =
      report.dateMode === "single" ? range.date
      : report.dateMode === "none" ? "current"
      : `${range.from}_${range.to}`
    return `${report.slug}-${suffix}`
  }, [report.slug, report.dateMode, range])

  const canExport = !!exportData && exportData.rows.length > 0

  // The PDF is no longer written to disk on click. The button builds the same
  // config and opens the preview, and Download lives inside that dialog -- so
  // nobody ends up with a folder of PDFs they had to open one by one to find
  // the one they wanted.
  const pdfConfig: PdfReportConfig | null = useMemo(() => {
    if (!exportData) return null
    return {
      ...exportBase,
      filename,
      headers: exportData.headers,
      rows: exportData.rows,
      summaryCards: exportData.summaryCards,
    }
  }, [exportBase, filename, exportData])

  function doCsv() {
    if (!exportData) return
    // The summary cards go in as leading label/value rows. A spreadsheet has no
    // concept of a KPI tile, and dropping them would mean the CSV quietly told a
    // smaller story than the PDF built from the very same object.
    const rows: (string | number | null | undefined)[][] = []
    if (exportData.summaryCards?.length) {
      for (const c of exportData.summaryCards) rows.push([c.label, c.value])
      rows.push([])
    }
    rows.push(exportData.headers)
    rows.push(...exportData.rows)
    downloadCsv(filename, [report.title, periodLabel || "Current position"], rows)
  }

  function doPrint() {
    if (!exportData) return
    printReport({
      hotelName: propertyName,
      hotelAddress: propertyAddress,
      hotelPhone: propertyPhone,
      title: report.title,
      currency,
      ...(report.dateMode === "range" ? { dateRange: { from: range.from, to: range.to } } : {}),
      summaryCards: exportData.summaryCards,
      headers: exportData.headers,
      rows: exportData.rows,
    })
  }

  return (
    <div className="mx-auto w-full max-w-7xl space-y-4">
      {/* Back to the catalog */}
      <Button asChild variant="ghost" size="sm" className="-ml-2 h-8 text-slate-600">
        <Link href={indexHref}>
          <ArrowLeft className="h-4 w-4 mr-1" /> All reports
        </Link>
      </Button>

      {/* Header. The group chip carries the group colour so a report is
          recognisable as Money / Sales / Operations at a glance. */}
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div className="flex items-start gap-3 min-w-0">
          <div className={`rounded-xl p-2.5 shrink-0 ${group.color}`}>
            <Icon className="h-6 w-6 text-white" />
          </div>
          <div className="min-w-0">
            <div className="flex items-center gap-2 flex-wrap">
              <h1 className="text-xl sm:text-2xl font-semibold text-slate-900">{report.title}</h1>
              <Badge variant="outline" className="text-[10px] uppercase tracking-wide">{group.label}</Badge>
            </div>
            <p className="mt-0.5 text-sm text-slate-500">{report.description}</p>
          </div>
        </div>

        {/* Export cluster. Disabled rather than hidden when there is nothing to
            export, so the buttons never move around under the pointer.
            On a phone they stretch to fill the row rather than huddling at one
            edge, and Print is dropped -- a phone has nowhere to print to, and
            three buttons on a 360px screen leaves each too narrow to hit. */}
        <div className="flex items-center gap-2 shrink-0">
          <Button
            variant="outline" size="sm" className="h-9 flex-1 sm:flex-none"
            disabled={!canExport} onClick={() => setPdfOpen(true)}
          >
            <Eye className="h-4 w-4 mr-1.5" /> View PDF
          </Button>
          <Button
            variant="outline" size="sm" className="h-9 flex-1 sm:flex-none"
            disabled={!canExport} onClick={doCsv}
          >
            <FileSpreadsheet className="h-4 w-4 mr-1.5" /> CSV
          </Button>
          {enableEmail && (
            <ReportEmailButton
              className="h-9 flex-1 sm:flex-none"
              disabled={!canExport}
              getConfig={() => pdfConfig}
              getCsv={() => exportData
                ? { headers: exportData.headers, rows: exportData.rows, summaryCards: exportData.summaryCards }
                : null}
              title={report.title}
              filename={filename}
              periodLabel={periodLabel}
              propertyName={propertyName}
              accent={accent}
            />
          )}
          <Button
            variant="outline" size="sm" className="h-9 hidden sm:inline-flex"
            disabled={!canExport} onClick={doPrint}
          >
            <Printer className="h-4 w-4 mr-1.5" /> Print
          </Button>
        </div>
      </div>

      {/* Date controls, chosen by the report's declared dateMode. */}
      {report.dateMode === "range" && (
        <Card>
          <CardContent className="p-3 flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
            <div className="flex flex-col sm:flex-row sm:items-center gap-2">
              <div className="flex items-center gap-2">
                <span className="text-xs font-medium text-slate-500 w-8 shrink-0">From</span>
                <Input
                  type="date" className="h-9 flex-1 sm:w-[150px] min-w-0"
                  value={range.from}
                  onChange={(e) => onRangeChange({ ...range, from: e.target.value })}
                />
              </div>
              <div className="flex items-center gap-2">
                <span className="text-xs font-medium text-slate-500 w-8 shrink-0">To</span>
                <Input
                  type="date" className="h-9 flex-1 sm:w-[150px] min-w-0"
                  value={range.to}
                  onChange={(e) => onRangeChange({ ...range, to: e.target.value })}
                />
              </div>
            </div>
            <div className="flex items-center gap-1.5 flex-wrap">
              {PRESETS.map((p) => {
                const v = p.compute()
                const active = v.from === range.from && v.to === range.to
                return (
                  <Button
                    key={p.label}
                    variant={active ? "default" : "outline"}
                    size="sm"
                    className={`h-8 text-xs ${active ? theme.button : ""}`}
                    onClick={() => onRangeChange({ ...range, from: v.from, to: v.to })}
                  >
                    {p.label}
                  </Button>
                )
              })}
            </div>
          </CardContent>
        </Card>
      )}

      {report.dateMode === "single" && (
        <Card>
          <CardContent className="p-3 flex items-center gap-2 flex-nowrap sm:flex-wrap">
            <Button
              variant="outline" size="icon" className="h-9 w-9 shrink-0"
              aria-label="Previous day"
              onClick={() => onRangeChange({ ...range, date: iso(shiftDays(new Date(range.date), -1)) })}
            >
              <ChevronLeft className="h-4 w-4" />
            </Button>
            <Input
              type="date" className="h-9 flex-1 sm:flex-none sm:w-[160px] min-w-0"
              value={range.date}
              onChange={(e) => onRangeChange({ ...range, date: e.target.value })}
            />
            <Button
              variant="outline" size="icon" className="h-9 w-9 shrink-0"
              aria-label="Next day"
              onClick={() => onRangeChange({ ...range, date: iso(shiftDays(new Date(range.date), 1)) })}
            >
              <ChevronRight className="h-4 w-4" />
            </Button>
            <Button
              variant="outline" size="sm" className="h-9"
              onClick={() => onRangeChange({ ...range, date: iso(new Date()) })}
            >
              Today
            </Button>
          </CardContent>
        </Card>
      )}

      {report.dateMode === "none" && (
        <p className="text-xs text-slate-500">
          This report shows the current position, so it has no date filter.
        </p>
      )}

      {/* Body */}
      {loading ? (
        <Card>
          <CardContent className="p-12 flex items-center justify-center gap-2 text-slate-500">
            <Loader2 className="h-5 w-5 animate-spin" />
            <span className="text-sm">Loading {report.title.toLowerCase()}…</span>
          </CardContent>
        </Card>
      ) : (
        children
      )}

      {/* View-then-download. Mounted always, opened by the View PDF button; the
          dialog builds nothing until `open` is true, so an unopened preview
          costs a closed <Dialog> and no PDF work. */}
      <ReportPdfPreview
        open={pdfOpen}
        onOpenChange={setPdfOpen}
        config={pdfConfig}
        accentButtonClass={theme.button}
      />
    </div>
  )
}

/** Sensible starting range: the last 30 days, with today as the single date. */
export function defaultReportRange(): ReportRange {
  return {
    from: iso(shiftDays(new Date(), -29)),
    to: iso(new Date()),
    date: iso(new Date()),
  }
}
