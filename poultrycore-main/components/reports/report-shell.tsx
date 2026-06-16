"use client"

/**
 * Shared scaffolding for Water Company reports (Prompt 2 §16).
 *
 * Each report page renders a <ReportShell> with:
 *   - The company name + report title (printable)
 *   - A date range picker (optional, can be hidden)
 *   - Custom filter UI via the `filters` slot
 *   - Summary cards via the `summary` slot
 *   - A table via the `children` slot
 *   - An Export PDF button (uses window.print() against a print-friendly layout)
 *
 * The header + sidebar are hidden in print via `print:hidden` so the PDF
 * contains just the report.
 */

import { ReactNode, useState } from "react"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Loader2, ArrowLeft, Printer, AlertCircle, Mail } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useFarmSettingsStore } from "@/lib/currency"
import { useLogout } from "@/hooks/use-logout"
import { PeriodSelect } from "@/components/ui/period-select"
import { rangeToPeriod } from "@/lib/date-ranges"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { useToast } from "@/hooks/use-toast"
import { exportTableToPdf, emailTableAsPdf, type PdfExportOptions } from "@/lib/utils/pdf-export"

export interface ReportShellProps {
  title: string
  description?: string
  busy?: boolean
  error?: string | null
  onClearError?: () => void
  // Date-range filter — usually present, omit when the report is point-in-time.
  fromDate?: string
  toDate?: string
  onFromDateChange?: (v: string) => void
  onToDateChange?: (v: string) => void
  onRefresh?: () => void
  // Free-form filters rendered to the right of the date range.
  filters?: ReactNode
  // Summary tiles rendered above the table.
  summary?: ReactNode
  children: ReactNode

  // Prompt 2 Part 3 §2/§3 — capture the active filter selections so the PDF
  // shows "Filters used: …" and the future email log can replay the query.
  // Pass an object with simple key→value entries (e.g. { Customer: "Acme",
  // "Payment method": "MoMo" }). Empty / falsy values are skipped.
  filterSummary?: Record<string, string | number | null | undefined>

  // Vector-PDF definition for this report (columns + rows + summary lines).
  // When provided, "Export PDF" downloads it and "Email report" sends it via
  // the single POST /api/Email/Report endpoint (lib/utils/pdf-export.ts). May
  // be a getter so the latest filtered data is captured at click time. When
  // omitted, Export falls back to window.print() and Email is disabled.
  pdf?: PdfExportOptions | (() => PdfExportOptions)
}

export function ReportShell({
  title, description, busy, error, onClearError,
  fromDate, toDate, onFromDateChange, onToDateChange, onRefresh,
  filters, summary, children, filterSummary, pdf,
}: ReportShellProps) {
  const farmName = useAuthStore((s) => s.activeFarmName)
  const user = useAuthStore((s) => s.user)
  const companyEmail = useAuthStore((s) => s.companies.find((c) => c.farmId === s.activeFarmId)?.email)
  const settings = useFarmSettingsStore((s) => s.settings)
  const logout = useLogout()
  const { toast } = useToast()

  const [emailOpen, setEmailOpen] = useState(false)
  const [recipient, setRecipient] = useState("")
  const [sending, setSending] = useState(false)
  const [downloading, setDownloading] = useState(false)

  const resolvePdf = (): PdfExportOptions | undefined => (typeof pdf === "function" ? pdf() : pdf)

  async function exportPdf() {
    const opts = resolvePdf()
    if (!opts) { window.print(); return }   // fallback for pages not yet converted
    setDownloading(true)
    try {
      await exportTableToPdf(opts)
    } catch (e: any) {
      toast({ title: "Export failed", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setDownloading(false)
    }
  }

  function openEmail() {
    setRecipient(companyEmail || user?.email || "")
    setEmailOpen(true)
  }

  async function sendEmail() {
    const opts = resolvePdf()
    if (!opts) return
    if (!recipient || !recipient.includes("@")) {
      toast({ title: "Enter a valid email", variant: "destructive" })
      return
    }
    setSending(true)
    try {
      const res = await emailTableAsPdf(opts, { to: recipient })
      if (res.success) {
        toast({ title: "Report emailed", description: `Sent to ${recipient}.` })
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

  const generatedBy = user?.username || user?.email || "—"
  const activeFilters = Object.entries(filterSummary ?? {})
    .filter(([, v]) => v != null && String(v).trim().length > 0 && String(v).trim().toUpperCase() !== "ALL")

  return (
    <div className="flex min-h-screen bg-slate-50 print:bg-white">
      <div className="print:hidden"><DashboardSidebar onLogout={logout} /></div>
      <div className="flex-1 flex flex-col min-w-0">
        <div className="print:hidden"><DashboardHeader /></div>

        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 print:p-0 min-w-0">
          <div className="mb-4 flex items-center justify-between gap-2 flex-wrap print:hidden">
            <Button asChild variant="outline" size="sm">
              <Link href="/water-reports"><ArrowLeft className="h-4 w-4 mr-1" /> Reports</Link>
            </Button>
            <div className="flex items-center gap-2">
              {/* Emails a PDF of this report (generated client-side from the same
                  data) to the entered address, via POST /api/Email/Report. */}
              <Button
                size="sm"
                variant="outline"
                onClick={openEmail}
                disabled={!pdf}
                title={pdf ? "Email this report as a PDF" : "Email not available for this report"}
                className="gap-1"
              >
                <Mail className="h-4 w-4" /> Email report
              </Button>
              <Button onClick={exportPdf} disabled={downloading} size="sm" className="gap-1">
                {downloading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Printer className="h-4 w-4" />}
                Export PDF
              </Button>
            </div>
          </div>

          <div className="bg-white rounded-xl border border-slate-200 p-4 sm:p-6 print:border-0 print:p-0">
            <header className="mb-4 border-b pb-4 print:pb-3">
              <h1 className="text-2xl font-semibold text-slate-900">{title}</h1>
              {description && <p className="text-sm text-slate-500 mt-1">{description}</p>}
              <div className="text-sm text-slate-500 mt-2">
                <div><span className="font-medium">Company:</span> {farmName ?? "—"}</div>
                {fromDate && toDate && (
                  <div><span className="font-medium">Date range:</span> {fromDate} → {toDate}</div>
                )}
                <div><span className="font-medium">Currency:</span> {settings?.currencyCode ?? "GHS"} ({settings?.currencySymbol ?? "GHC"})</div>
                <div><span className="font-medium">Generated:</span> {typeof window !== "undefined" ? new Date().toLocaleString() : ""}</div>
                {/* Prompt 2 Part 3 §2 — track WHO produced the report so the
                    printed copy is auditable. */}
                <div><span className="font-medium">Generated by:</span> {generatedBy}</div>
                {/* Active filter values rendered into the PDF so the
                    recipient sees exactly which slice they're looking at. */}
                {activeFilters.length > 0 && (
                  <div className="break-words">
                    <span className="font-medium">Filters used:</span>{" "}
                    {activeFilters.map(([k, v], i) => (
                      <span key={k}>{i > 0 ? "; " : ""}<span className="text-slate-700">{k}</span> = <span className="font-mono">{String(v)}</span></span>
                    ))}
                  </div>
                )}
              </div>
            </header>

            {/* Filters row — hidden in print to keep the PDF tight. */}
            {(onFromDateChange || filters || onRefresh) && (
              <div className="print:hidden mb-4 flex items-end gap-2 flex-wrap">
                {onFromDateChange && onToDateChange && (
                  <PeriodSelect
                    value={rangeToPeriod(fromDate ?? "", toDate ?? "")}
                    onChange={(_p, range) => {
                      if (range) { onFromDateChange(range.from); onToDateChange(range.to) }
                    }}
                  />
                )}
                {onFromDateChange && (
                  <div>
                    <Label className="text-xs">From</Label>
                    <Input type="date" value={fromDate ?? ""} onChange={(e) => onFromDateChange(e.target.value)} className="w-40" />
                  </div>
                )}
                {onToDateChange && (
                  <div>
                    <Label className="text-xs">To</Label>
                    <Input type="date" value={toDate ?? ""} onChange={(e) => onToDateChange(e.target.value)} className="w-40" />
                  </div>
                )}
                {filters}
                {onRefresh && (
                  <Button variant="outline" size="sm" onClick={onRefresh} disabled={busy}>Refresh</Button>
                )}
              </div>
            )}

            {error && (
              <div className="mb-4 rounded-md bg-rose-50 border border-rose-200 px-3 py-2 text-sm text-rose-800 flex items-start gap-2">
                <AlertCircle className="h-4 w-4 mt-0.5 shrink-0" />
                <div className="min-w-0 break-words flex-1">{error}</div>
                {onClearError && (
                  <button onClick={onClearError} className="text-rose-500 hover:text-rose-700 text-xs ml-auto shrink-0 print:hidden">dismiss</button>
                )}
              </div>
            )}

            {busy ? (
              <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
            ) : (
              <>
                {summary && <div className="mb-4 grid grid-cols-2 md:grid-cols-4 gap-3 print:gap-2">{summary}</div>}
                {children}
              </>
            )}
          </div>
        </main>
      </div>

      {/* Email report dialog (hidden in print). */}
      <Dialog open={emailOpen} onOpenChange={(o) => { if (!sending) setEmailOpen(o) }}>
        <DialogContent className="print:hidden">
          <DialogHeader>
            <DialogTitle>Email “{title}”</DialogTitle>
          </DialogHeader>
          <div className="space-y-2">
            <Label htmlFor="report-email-to" className="text-xs">Recipient email</Label>
            <Input
              id="report-email-to"
              type="email"
              value={recipient}
              onChange={(e) => setRecipient(e.target.value)}
              placeholder="owner@example.com"
            />
            <p className="text-xs text-slate-500">
              A PDF of this report (current date range and filters) will be generated and sent.
            </p>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setEmailOpen(false)} disabled={sending}>Cancel</Button>
            <Button onClick={sendEmail} disabled={sending} className="gap-1">
              {sending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Mail className="h-4 w-4" />}
              {sending ? "Sending…" : "Send"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

import { Card, CardContent } from "@/components/ui/card"

export function SumTile({ label, value, accent }: { label: string; value: string; accent?: "green" | "rose" | "indigo" }) {
  const cls =
    accent === "green"  ? "text-emerald-700" :
    accent === "rose"   ? "text-rose-700"   :
    accent === "indigo" ? "text-indigo-700" : ""
  return (
    <Card className="print:border print:shadow-none">
      <CardContent className="p-4 print:p-3">
        <div className="text-xs uppercase tracking-wider text-slate-500">{label}</div>
        <div className={`text-lg sm:text-xl font-semibold tabular-nums mt-1 ${cls}`}>{value}</div>
      </CardContent>
    </Card>
  )
}
