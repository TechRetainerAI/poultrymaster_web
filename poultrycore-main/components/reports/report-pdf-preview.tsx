"use client"

/**
 * View-then-download PDF preview for the Restaurant and Hotel report shell.
 *
 * WHY NOT REUSE components/reports/pdf-preview-dialog.tsx
 * That one already serves several hotel and water report PAGES and is left
 * alone. It also hardcodes a violet button, and — more importantly — previews
 * from a `data:` URI, which Firefox refuses to render in an iframe and Safari
 * handles unreliably. This one uses a `blob:` URL, takes the module accent, and
 * always offers a working escape hatch when the inline viewer cannot render.
 *
 * THE MOBILE PROBLEM, STATED PLAINLY
 * Phone browsers largely do not render PDFs inside an iframe — iOS Safari and
 * most Android Chrome builds show a blank box or silently offer a download
 * instead. There is no CSS fix for that. So on small screens this does not
 * pretend: it leads with "Open PDF" (which hands the file to the phone's own
 * viewer, and always works) and keeps Download beside it, while still rendering
 * the iframe underneath for the browsers that can manage it.
 */

import { useEffect, useState } from "react"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Download, ExternalLink, Loader2, FileWarning } from "lucide-react"
import { downloadPdf, getPdfPreviewBlobUrl, type PdfReportConfig } from "@/lib/utils/download-pdf"

export interface ReportPdfPreviewProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  config: PdfReportConfig | null
  /** Tailwind classes for the primary Download button, from the module palette. */
  accentButtonClass?: string
}

export function ReportPdfPreview({
  open, onOpenChange, config, accentButtonClass = "bg-rose-600 hover:bg-rose-700",
}: ReportPdfPreviewProps) {
  const [url, setUrl] = useState<string | null>(null)
  const [building, setBuilding] = useState(false)
  const [failed, setFailed] = useState(false)

  useEffect(() => {
    if (!open || !config) {
      setUrl(null)
      setFailed(false)
      return
    }
    setBuilding(true)
    setFailed(false)
    let made: string | null = null

    // Deferred a frame so the dialog paints before jsPDF blocks the main thread
    // on a long report; otherwise the modal appears already-frozen.
    const t = setTimeout(() => {
      try {
        made = getPdfPreviewBlobUrl(config)
        setUrl(made)
      } catch {
        setFailed(true)
        setUrl(null)
      } finally {
        setBuilding(false)
      }
    }, 50)

    return () => {
      clearTimeout(t)
      // Revoke on close, or the document stays in memory for the life of the tab.
      // Safe for a tab already opened via the Open button: that document has
      // finished loading by then, and revoking only stops NEW reads of the URL.
      if (made) URL.revokeObjectURL(made)
    }
  }, [open, config])

  const title = config?.title ?? "PDF preview"

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      {/*
        sm:max-w-*, never a bare max-w-*. The Dialog primitive sets
        `max-w-[calc(100%-2rem)]` for the phone gutter, and tailwind-merge only
        drops a conflicting class under the SAME modifier — an unprefixed
        max-w-* would therefore eat that gutter and glue the modal to both
        screen edges. The comment in components/ui/dialog.tsx records this.
      */}
      {/*
        Height stays inside the primitive's own `max-h-[90vh]` rather than
        fighting it, and `overflow-hidden` keeps the iframe pane the only
        scroller — the primitive sets `overflow-y-auto`, and two nested
        scrollers on a phone means the page scrolls when you meant to scroll the
        document. `flex` also intentionally overrides the primitive's `grid`.
      */}
      <DialogContent className="w-full sm:max-w-5xl h-[85vh] sm:h-[88vh] flex flex-col gap-3 p-4 sm:p-6 overflow-hidden">
        <DialogHeader className="space-y-0 shrink-0">
          <DialogTitle className="text-base sm:text-lg pr-8 leading-snug">
            {title}
            {config?.hotelName && (
              <span className="block text-xs font-normal text-slate-500 mt-0.5 truncate">
                {config.hotelName}
              </span>
            )}
          </DialogTitle>
        </DialogHeader>

        {/* Actions sit under the title, not beside it: on a phone a title plus
            two buttons on one row truncates the title to nothing. */}
        <div className="flex items-center gap-2 shrink-0">
          <Button
            size="sm"
            className={`h-9 flex-1 sm:flex-none ${accentButtonClass}`}
            disabled={!url}
            onClick={() => { if (config) downloadPdf(config) }}
          >
            <Download className="h-4 w-4 mr-1.5" /> Download
          </Button>
          <Button
            size="sm"
            variant="outline"
            className="h-9 flex-1 sm:flex-none"
            disabled={!url}
            onClick={() => { if (url) window.open(url, "_blank", "noopener,noreferrer") }}
          >
            <ExternalLink className="h-4 w-4 mr-1.5" /> Open
          </Button>
          <Button
            size="sm"
            variant="ghost"
            className="h-9 hidden sm:inline-flex"
            onClick={() => onOpenChange(false)}
          >
            Close
          </Button>
        </div>

        <p className="text-[11px] text-slate-500 sm:hidden shrink-0">
          Some phone browsers cannot show a PDF inline. If the preview below is blank, use
          <span className="font-medium"> Open</span>.
        </p>

        <div className="flex-1 min-h-0 rounded-lg border bg-slate-100 overflow-hidden">
          {building ? (
            <div className="flex items-center justify-center h-full gap-2 text-slate-500">
              <Loader2 className="h-6 w-6 animate-spin" />
              <span className="text-sm">Building preview…</span>
            </div>
          ) : failed ? (
            <div className="flex flex-col items-center justify-center h-full gap-2 p-6 text-center">
              <FileWarning className="h-8 w-8 text-slate-400" />
              <p className="text-sm text-slate-600">
                The preview could not be generated. Download still works.
              </p>
            </div>
          ) : url ? (
            <iframe src={url} className="w-full h-full border-0" title={`${title} preview`} />
          ) : (
            <div className="flex items-center justify-center h-full text-slate-400 text-sm">
              Nothing to preview.
            </div>
          )}
        </div>
      </DialogContent>
    </Dialog>
  )
}
