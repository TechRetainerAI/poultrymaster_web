"use client"

/**
 * ReportEmailButton — "Email" beside the CSV / PDF / Print cluster on a report.
 *
 * Poultry has had this since its report view was built
 * (`components/poultry-reports/poultry-report-view.tsx` + `lib/utils/pdf-export.ts`),
 * and it is the pattern this component reproduces: type one or more addresses,
 * the report is rendered and uploaded to `POST /api/Email/Report`, and the
 * server mails it as an attachment.
 *
 * TWO THINGS IT DOES THAT THE POULTRY ONE DOES NOT
 *
 * 1. **The attachment can be CSV as well as PDF.** Poultry's `emailTableAsPdf`
 *    only ever sends a PDF. The backend takes whatever `file.ContentType` it is
 *    handed (`EmailController.SendReport` passes it straight to the notification
 *    service), so offering the choice needed no backend change at all — and the
 *    CSV is derived from the PDF config, which already carries `headers`,
 *    `rows` and `summaryCards`, so no report page needed changing either.
 *
 * 2. **The PDF is built lazily.** `getConfig` is a function, not a config, so
 *    nothing is rendered until Send is actually pressed. Report pages rebuild
 *    their config object on every render; taking the built config as a prop
 *    would have generated a PDF on every keystroke in the recipient box.
 *
 * WHY IT IS A COMPONENT AND NOT PART OF THE SHELL
 * `components/reports/module-report-shell.tsx` serves five modules (Hotel,
 * Restaurant, Generic, Poultry, Water), but sixteen hotel reports predate that
 * shell and render their own toolbars. A standalone button drops into both
 * without the shell growing a second code path, and without the fifteen-odd
 * non-hotel reports on the shell inheriting a feature nobody asked for.
 */

import { useState } from "react"
import { Mail, Loader2 } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { useToast } from "@/hooks/use-toast"
import { useAuthStore } from "@/lib/store/auth-store"
import { getPdfBlob, type PdfReportConfig } from "@/lib/utils/download-pdf"
import { sendReportEmail } from "@/lib/api/email"
import { cn } from "@/lib/utils"

/** Rows for the CSV attachment, in the shape the report already has them. */
export interface ReportEmailCsv {
  headers: string[]
  rows: (string | number | null | undefined)[][]
  /** Leading label/value lines (the KPI tiles), written above the table. */
  summaryCards?: { label: string; value: string | number }[]
}

export interface ReportEmailButtonProps {
  /** Built only when Send is pressed — see the note above. */
  getConfig: () => PdfReportConfig | null
  /** Report name, for the dialog title and the default subject. */
  title: string
  /** Base filename without extension or date, e.g. "bookings-report". */
  filename: string
  /**
   * The CSV attachment. Optional: when omitted it is derived from `getConfig`,
   * since a PdfReportConfig already carries `headers`, `rows` and
   * `summaryCards` — the same three things a CSV needs. That is what lets the
   * sixteen legacy hotel reports offer both formats without any of them being
   * refactored. Pass it explicitly only when the spreadsheet should differ from
   * the PDF.
   */
  getCsv?: () => ReportEmailCsv | null
  /** The period line, so the email body says what the report covers. */
  periodLabel?: string
  /** Shown as the sender's organisation in the default body. */
  propertyName?: string
  disabled?: boolean
  /**
   * Module palette for the Send button, the selected attachment tile and the
   * message box's focus ring. Defaults to violet because the sixteen legacy
   * hotel report pages were the first callers and pass nothing.
   */
  accent?: ReportEmailAccent
  className?: string
  /** Renders icon-only below `sm`, for crowded legacy toolbars. */
  compact?: boolean
}

type Attachment = "pdf" | "csv"

/**
 * Module palette. Declared here rather than imported from module-report-shell:
 * that file imports THIS one, so taking its `ReportAccent` back would be a
 * circular import. The two unions are kept in step by hand — there are two
 * members and both files name them in the same comment.
 */
export type ReportEmailAccent = "rose" | "violet"

const ACCENT: Record<ReportEmailAccent, { button: string; tile: string; ring: string }> = {
  // Restaurant
  rose: {
    button: "bg-rose-600 hover:bg-rose-700",
    tile: "border-rose-600 bg-rose-50 text-rose-700",
    ring: "focus-visible:ring-rose-500",
  },
  // Hotel
  violet: {
    button: "bg-violet-600 hover:bg-violet-700",
    tile: "border-violet-600 bg-violet-50 text-violet-700",
    ring: "focus-visible:ring-violet-500",
  },
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

/** Same escaping as lib/utils/download-csv.ts, but producing a Blob to upload. */
function buildCsvBlob(csv: ReportEmailCsv, title: string, periodLabel?: string): Blob {
  const escape = (v: unknown) => {
    const s = v == null ? "" : String(v)
    return s.includes(",") || s.includes('"') || s.includes("\n") ? `"${s.replace(/"/g, '""')}"` : s
  }
  const lines: (string | number | null | undefined)[][] = []
  if (csv.summaryCards?.length) {
    for (const c of csv.summaryCards) lines.push([c.label, c.value])
    lines.push([])
  }
  lines.push(csv.headers)
  lines.push(...csv.rows)

  const body = [
    [title, periodLabel || "Current position"].map(escape).join(","),
    ...lines.map((r) => r.map(escape).join(",")),
  ].join("\n")

  // The BOM is what makes Excel open a UTF-8 CSV without mangling accents.
  return new Blob(["﻿" + body], { type: "text/csv;charset=utf-8;" })
}

export function ReportEmailButton({
  getConfig, title, filename, getCsv, periodLabel, propertyName,
  disabled, accent = "violet", className, compact = false,
}: ReportEmailButtonProps) {
  const tone = ACCENT[accent]
  const { toast } = useToast()
  const user = useAuthStore((s) => s.user)
  const companyEmail = useAuthStore((s) => s.companies.find((c) => c.farmId === s.activeFarmId)?.email)

  const [open, setOpen] = useState(false)
  const [recipient, setRecipient] = useState("")
  const [note, setNote] = useState("")
  const [attachment, setAttachment] = useState<Attachment>("pdf")
  const [sending, setSending] = useState(false)

  function openDialog() {
    // Prefilled the way Poultry does it: the company's address first, the
    // signed-in user's as the fallback. Still editable — it is a starting point,
    // not a decision.
    setRecipient(companyEmail || user?.email || "")
    setAttachment("pdf")
    setNote("")
    setOpen(true)
  }

  async function send() {
    const recipients = recipient.split(/[,;\n]/).map((s) => s.trim()).filter(Boolean)
    if (recipients.length === 0 || recipients.some((e) => !EMAIL_RE.test(e))) {
      toast({ title: "Enter a valid email address", description: "Separate several with commas.", variant: "destructive" })
      return
    }

    setSending(true)
    try {
      let blob: Blob
      let attachmentName: string

      if (attachment === "csv") {
        const config = getConfig()
        const csv = getCsv?.()
          ?? (config
            ? { headers: config.headers, rows: config.rows, summaryCards: config.summaryCards }
            : null)
        if (!csv) { toast({ title: "Nothing to send", variant: "destructive" }); return }
        blob = buildCsvBlob(csv, title, periodLabel)
        attachmentName = `${filename}-${new Date().toISOString().slice(0, 10)}.csv`
      } else {
        const config = getConfig()
        if (!config) { toast({ title: "Nothing to send", variant: "destructive" }); return }
        const built = getPdfBlob(config)
        blob = built.blob
        attachmentName = built.filename
      }

      const period = periodLabel ? ` (${periodLabel})` : ""
      const res = await sendReportEmail({
        blob,
        filename: attachmentName,
        to: recipients.join(","),
        subject: `${title}${period}`,
        // Left undefined when the operator typed nothing, so the server's own
        // template is used rather than an empty body overriding it.
        body: note.trim() || undefined,
        farmName: propertyName,
        reportTitle: title,
        senderName: user?.username || user?.email || undefined,
      })

      if (res.success) {
        toast({
          title: "Report emailed",
          description: `${attachment.toUpperCase()} sent to ${recipients.length === 1 ? recipients[0] : `${recipients.length} recipients`}.`,
        })
        setOpen(false)
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
    <>
      <Button
        variant="outline" size="sm"
        // No height of its own: the shell's cluster is h-9, the legacy hotel
        // toolbars use size="sm"'s natural height, and forcing one here would
        // leave this button a different size from the ones beside it.
        className={className}
        disabled={disabled}
        onClick={openDialog}
      >
        <Mail className={cn("h-4 w-4", compact ? "sm:mr-1.5" : "mr-1.5")} />
        <span className={compact ? "hidden sm:inline" : undefined}>Email</span>
      </Button>

      {/* Not closable mid-send: dismissing it would leave the upload running
          with nothing to report the outcome to. */}
      <Dialog open={open} onOpenChange={(o) => { if (!sending) setOpen(o) }}>
        <DialogContent className="max-w-md print:hidden">
          <DialogHeader><DialogTitle className="text-base">Email “{title}”</DialogTitle></DialogHeader>

          <div className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="report-email-to" className="text-xs">Recipient email(s)</Label>
              <Input
                id="report-email-to"
                className="h-10"
                value={recipient}
                onChange={(e) => setRecipient(e.target.value)}
                placeholder="owner@example.com, accountant@example.com"
                // Enter sends, but only from the address box — pressing it in the
                // note box should make a new line, not submit.
                onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); send() } }}
              />
              <p className="text-xs text-slate-500">Separate multiple addresses with commas.</p>
            </div>

            <div className="space-y-2">
              <Label className="text-xs">Attach as</Label>
              <div className="grid grid-cols-2 gap-2">
                {(["pdf", "csv"] as Attachment[]).map((a) => (
                  <button
                    key={a}
                    type="button"
                    onClick={() => setAttachment(a)}
                    className={cn(
                      "h-10 rounded-md border text-sm font-medium transition-colors",
                      attachment === a
                        ? tone.tile
                        : "border-slate-200 text-slate-600 hover:bg-slate-50",
                    )}
                  >
                    {a.toUpperCase()}
                    <span className="ml-1 text-xs font-normal text-slate-400">
                      {a === "pdf" ? "formatted" : "spreadsheet"}
                    </span>
                  </button>
                ))}
              </div>
            </div>

            <div className="space-y-2">
              <Label htmlFor="report-email-note" className="text-xs">Message (optional)</Label>
              <textarea
                id="report-email-note"
                rows={3}
                value={note}
                onChange={(e) => setNote(e.target.value)}
                placeholder="Leave blank to use the standard message."
                className={cn("w-full rounded-md border border-slate-200 p-2 text-sm focus-visible:outline-none focus-visible:ring-2", tone.ring)}
              />
            </div>
          </div>

          <DialogFooter className="gap-2 sm:gap-0">
            <Button variant="outline" onClick={() => setOpen(false)} disabled={sending}>Cancel</Button>
            <Button onClick={send} disabled={sending} className={tone.button}>
              {sending
                ? <><Loader2 className="h-4 w-4 mr-1.5 animate-spin" /> Sending…</>
                : <><Mail className="h-4 w-4 mr-1.5" /> Send</>}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  )
}
