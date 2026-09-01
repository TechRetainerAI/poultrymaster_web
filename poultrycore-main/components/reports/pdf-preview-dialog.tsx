"use client"

import { useEffect, useState } from "react"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Download, Loader2 } from "lucide-react"
import { downloadPdf, getPdfPreviewUrl, type PdfReportConfig } from "@/lib/utils/download-pdf"

interface PdfPreviewDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  config: PdfReportConfig | null
}

export function PdfPreviewDialog({ open, onOpenChange, config }: PdfPreviewDialogProps) {
  const [previewUrl, setPreviewUrl] = useState<string | null>(null)
  const [generating, setGenerating] = useState(false)

  // Generate preview whenever dialog opens with a config
  useEffect(() => {
    if (open && config) {
      setGenerating(true)
      setPreviewUrl(null)
      const timer = setTimeout(() => {
        try {
          const url = getPdfPreviewUrl(config)
          setPreviewUrl(url)
        } catch { setPreviewUrl(null) }
        finally { setGenerating(false) }
      }, 200)
      return () => clearTimeout(timer)
    } else {
      setPreviewUrl(null)
    }
  }, [open, config])

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="w-[95vw] max-w-[1200px] h-[90vh] flex flex-col">
        <DialogHeader className="flex-row items-center justify-between gap-4">
          <DialogTitle>{config?.hotelName ? `${config.hotelName} — ` : ""}{config?.title ?? "PDF Preview"}</DialogTitle>
          <Button
            size="sm"
            className="bg-violet-600 hover:bg-violet-700"
            onClick={() => { if (config) downloadPdf(config) }}
          >
            <Download className="h-4 w-4 mr-1" />
            Download PDF
          </Button>
        </DialogHeader>
        <div className="flex-1 min-h-0 rounded-lg border border-slate-200 bg-slate-100 overflow-hidden">
          {generating ? (
            <div className="flex items-center justify-center h-full">
              <Loader2 className="h-8 w-8 animate-spin text-violet-600" />
              <span className="ml-2 text-slate-500">Generating preview...</span>
            </div>
          ) : previewUrl ? (
            <iframe src={previewUrl} className="w-full h-full border-0" title="PDF Preview" />
          ) : (
            <div className="flex items-center justify-center h-full text-slate-400">
              No preview available
            </div>
          )}
        </div>
      </DialogContent>
    </Dialog>
  )
}
