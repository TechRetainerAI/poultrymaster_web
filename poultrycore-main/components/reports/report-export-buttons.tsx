"use client"

// Shared CSV / Email / PDF export buttons for generic report pages.
// Drop-in component: pass the data and it handles all three exports.

import { useState } from "react"
import { Button } from "@/components/ui/button"
import { FileText, Mail, Download, Loader2 } from "lucide-react"
import { exportTableToPdf, emailTableAsPdf, type PdfExportOptions } from "@/lib/utils/pdf-export"
import { downloadCsv } from "@/lib/utils/download-csv"
import { useToast } from "@/hooks/use-toast"

export interface ReportExportProps {
  /** PDF export options — also used to derive CSV columns. */
  pdf: PdfExportOptions
  /** CSV filename (without extension). Defaults to pdf.title kebab-cased. */
  csvFilename?: string
  /** Disable all buttons (e.g. while data is loading). */
  disabled?: boolean
}

export function ReportExportButtons({ pdf, csvFilename, disabled }: ReportExportProps) {
  const { toast } = useToast()
  const [emailing, setEmailing] = useState(false)

  const filename = csvFilename ?? pdf.title?.toLowerCase().replace(/[^a-z0-9]+/g, "-") ?? "report"

  function onCsv() {
    if (!pdf.columns || !pdf.rows) return
    const headers = pdf.columns.map((c) => c.header)
    const rows = pdf.rows.map((row: any) =>
      pdf.columns!.map((col) => {
        const val = col.key ? row[col.key] : undefined
        return val == null ? "" : val
      }),
    )
    downloadCsv(filename, headers, rows)
  }

  async function onEmail() {
    setEmailing(true)
    try {
      await emailTableAsPdf(pdf)
      toast({ title: "Report emailed", description: "Check your inbox." })
    } catch (e: any) {
      toast({ title: "Could not email report", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setEmailing(false)
    }
  }

  function onPdf() {
    exportTableToPdf(pdf)
  }

  const noData = !pdf.rows || pdf.rows.length === 0

  return (
    <div className="flex items-center gap-2">
      <Button size="sm" variant="outline" onClick={onCsv} disabled={disabled || noData}>
        <FileText className="h-4 w-4 mr-1" /> CSV
      </Button>
      <Button size="sm" variant="outline" onClick={onEmail} disabled={disabled || noData || emailing}>
        {emailing ? <Loader2 className="h-4 w-4 mr-1 animate-spin" /> : <Mail className="h-4 w-4 mr-1" />} Email
      </Button>
      <Button size="sm" onClick={onPdf} disabled={disabled || noData}>
        <Download className="h-4 w-4 mr-1" /> PDF
      </Button>
    </div>
  )
}
