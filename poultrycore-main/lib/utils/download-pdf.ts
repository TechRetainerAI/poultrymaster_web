/**
 * Professional PDF report generator using jsPDF + autoTable.
 * Produces branded reports with hotel name, summary cards, and clean tables.
 */
import jsPDF from "jspdf"
import autoTable from "jspdf-autotable"

export interface PdfReportConfig {
  title: string
  subtitle?: string
  filename: string
  headers: string[]
  rows: (string | number | null | undefined)[][]
  summaryCards?: { label: string; value: string }[]
  dateRange?: { from: string; to: string }
  currency?: string
  hotelName?: string
  hotelAddress?: string
  hotelPhone?: string
  /**
   * Brand accent as an [r, g, b] triple. Defaults to violet-600, which is what
   * every existing caller (hotel, water, poultry) rendered before this option
   * existed -- so omitting it reproduces the previous output byte for byte.
   *
   * Restaurant passes rose-600 so an exported report matches the rose UI the
   * operator just clicked Download in, rather than arriving in another module's
   * colour.
   */
  accent?: [number, number, number]
}

function buildPdf(config: PdfReportConfig): jsPDF {
  const doc = new jsPDF({ orientation: "landscape", unit: "mm", format: "a4" })
  const pw = doc.internal.pageSize.getWidth()
  const ph = doc.internal.pageSize.getHeight()
  const now = new Date().toLocaleString()
  const name = config.hotelName ?? "Hotel"
  const accent: [number, number, number] = config.accent ?? [109, 40, 217] // violet-600
  const contact = [config.hotelAddress, config.hotelPhone].filter(Boolean).join("  |  ")

  // === PAGE 1: COVER + SUMMARY ===

  // Top accent bar
  doc.setFillColor(...accent)
  doc.rect(0, 0, pw, 4, "F")

  // Hotel name (large, bold)
  doc.setTextColor(...accent)
  doc.setFontSize(24)
  doc.setFont("helvetica", "bold")
  doc.text(name, 20, 22)

  // Contact line
  if (contact) {
    doc.setFontSize(8)
    doc.setFont("helvetica", "normal")
    doc.setTextColor(148, 163, 184) // slate-400
    doc.text(contact, 20, 28)
  }

  // Divider line
  doc.setDrawColor(226, 232, 240) // slate-200
  doc.setLineWidth(0.5)
  doc.line(20, 32, pw - 20, 32)

  // Report title
  doc.setTextColor(15, 23, 42) // slate-900
  doc.setFontSize(20)
  doc.setFont("helvetica", "bold")
  doc.text(config.title, 20, 44)

  // Subtitle / report type
  doc.setFontSize(10)
  doc.setFont("helvetica", "normal")
  doc.setTextColor(100, 116, 139) // slate-500
  // Left as "Hotel Management Report" deliberately. It is only reached when a
  // caller passes no subtitle, and every such caller today is a hotel report;
  // generalising the wording would change those PDFs for no gain. Restaurant
  // always passes its own subtitle, so it never sees this default.
  const subtitleText = config.subtitle ?? "Hotel Management Report"
  doc.text(subtitleText.toUpperCase(), 20, 50)

  // Right side: metadata box
  const metaX = pw - 80
  doc.setFillColor(248, 250, 252) // slate-50
  doc.roundedRect(metaX, 36, 60, 24, 2, 2, "F")
  doc.setDrawColor(226, 232, 240)
  doc.roundedRect(metaX, 36, 60, 24, 2, 2, "S")

  doc.setFontSize(7)
  doc.setTextColor(100, 116, 139)
  doc.text("GENERATED", metaX + 4, 42)
  doc.setFontSize(8)
  doc.setTextColor(15, 23, 42)
  doc.setFont("helvetica", "bold")
  doc.text(now, metaX + 4, 47)

  if (config.dateRange) {
    doc.setFontSize(7)
    doc.setTextColor(100, 116, 139)
    doc.setFont("helvetica", "normal")
    doc.text("PERIOD", metaX + 4, 53)
    doc.setFontSize(8)
    doc.setTextColor(15, 23, 42)
    doc.setFont("helvetica", "bold")
    doc.text(`${config.dateRange.from}  —  ${config.dateRange.to}`, metaX + 4, 58)
  }

  let y = 68

  // Summary cards (professional grid)
  if (config.summaryCards && config.summaryCards.length > 0) {
    const cards = config.summaryCards
    const gap = 6
    const totalGap = (cards.length - 1) * gap
    const cardW = (pw - 40 - totalGap) / cards.length
    const cardH = 22

    cards.forEach((card, i) => {
      const cx = 20 + i * (cardW + gap)

      // Card background
      doc.setFillColor(255, 255, 255)
      doc.setDrawColor(226, 232, 240)
      doc.roundedRect(cx, y, cardW, cardH, 2, 2, "FD")

      // Left accent bar
      const colors: [number, number, number][] = [
        [16, 185, 129],  // emerald-500
        [239, 68, 68],   // red-500
        [99, 102, 241],  // indigo-500
        [245, 158, 11],  // amber-500
      ]
      const accentColor = colors[i % colors.length]
      doc.setFillColor(...accentColor)
      doc.rect(cx, y, 3, cardH, "F")
      // Round the left corners
      doc.setFillColor(255, 255, 255)
      doc.rect(cx + 0.3, y, 2.7, 2, "F")
      doc.rect(cx + 0.3, y + cardH - 2, 2.7, 2, "F")
      doc.setFillColor(...accentColor)
      doc.roundedRect(cx, y, 3, cardH, 2, 0, "F")

      // Label
      doc.setFontSize(7)
      doc.setFont("helvetica", "normal")
      doc.setTextColor(100, 116, 139)
      doc.text(card.label.toUpperCase(), cx + 7, y + 8)

      // Value
      doc.setFontSize(14)
      doc.setFont("helvetica", "bold")
      doc.setTextColor(15, 23, 42)
      doc.text(card.value, cx + 7, y + 17)
    })

    y += cardH + 10
  }

  // Record count badge
  doc.setFillColor(...accent)
  doc.roundedRect(20, y, 36, 7, 1.5, 1.5, "F")
  doc.setFontSize(7)
  doc.setFont("helvetica", "bold")
  doc.setTextColor(255, 255, 255)
  doc.text(`${config.rows.length} RECORDS`, 22, y + 5)
  y += 12

  // === DATA TABLE ===
  autoTable(doc, {
    startY: y,
    head: [config.headers],
    body: config.rows.map((row) => row.map((v) => (v == null ? "" : String(v)))),
    styles: {
      fontSize: 7.5,
      cellPadding: { top: 2.5, right: 3, bottom: 2.5, left: 3 },
      lineColor: [226, 232, 240],
      lineWidth: 0.3,
    },
    headStyles: {
      fillColor: accent,
      textColor: 255,
      fontStyle: "bold",
      fontSize: 7,
      cellPadding: { top: 3, right: 3, bottom: 3, left: 3 },
    },
    alternateRowStyles: { fillColor: [248, 250, 252] },
    margin: { left: 20, right: 20 },
    tableLineColor: [226, 232, 240],
    tableLineWidth: 0.3,
    didDrawPage: (data: any) => {
      const pageNum = (doc as any).internal.getCurrentPageInfo().pageNumber
      const totalPages = doc.getNumberOfPages()

      // Top accent bar on subsequent pages
      if (pageNum > 1) {
        doc.setFillColor(...accent)
        doc.rect(0, 0, pw, 3, "F")
        doc.setFontSize(9)
        doc.setFont("helvetica", "bold")
        doc.setTextColor(...accent)
        doc.text(name, 20, 10)
        doc.setFontSize(8)
        doc.setFont("helvetica", "normal")
        doc.setTextColor(100, 116, 139)
        doc.text(config.title, 20, 15)
      }

      // Footer
      doc.setFontSize(7)
      doc.setTextColor(148, 163, 184)
      doc.setFont("helvetica", "normal")

      // Footer line
      doc.setDrawColor(226, 232, 240)
      doc.setLineWidth(0.3)
      doc.line(20, ph - 12, pw - 20, ph - 12)

      doc.text(`${name}  |  ${config.title}`, 20, ph - 8)
      doc.text(`Page ${pageNum} of ${totalPages}`, pw - 20, ph - 8, { align: "right" })
      if (config.currency) doc.text(`Currency: ${config.currency}`, pw / 2, ph - 8, { align: "center" })
    },
  })

  return doc
}

export function downloadPdf(config: PdfReportConfig) {
  const doc = buildPdf(config)
  doc.save(`${config.filename}-${new Date().toISOString().slice(0, 10)}.pdf`)
}

export function getPdfPreviewUrl(config: PdfReportConfig): string {
  const doc = buildPdf(config)
  return doc.output("dataurlstring")
}

/**
 * Same PDF as a blob: URL rather than a data: URL.
 *
 * WHY BOTH EXIST. `getPdfPreviewUrl` above returns a `data:` URI, and several
 * hotel and water report pages already rely on it, so it is left exactly as it
 * was. But a `data:` URI carries the whole document in the URL string, and
 * browsers treat it as an opaque foreign origin: Firefox blocks it outright in
 * an iframe, Safari is unreliable, and a large report can exceed the URL length
 * a browser will accept. A `blob:` URL is same-origin and streams from memory,
 * so it previews in far more places and costs nothing extra to make.
 *
 * The caller owns the returned URL and MUST call URL.revokeObjectURL on it when
 * the preview closes, or the document stays in memory for the life of the tab.
 */
export function getPdfPreviewBlobUrl(config: PdfReportConfig): string {
  const doc = buildPdf(config)
  return URL.createObjectURL(doc.output("blob"))
}
