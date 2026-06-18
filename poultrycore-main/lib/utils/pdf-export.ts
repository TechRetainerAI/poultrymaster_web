export interface PdfExportColumn {
  header: string
  align?: "left" | "right" | "center"
  width?: number
}

export interface PdfExportFilter {
  label: string
  value: string
}

export interface PdfExportSummaryCard {
  label: string
  value: string
  /** Accent colour for the card's left bar + value, matching the on-screen SumTile. */
  accent?: "green" | "rose" | "indigo"
}

export interface PdfExportOptions {
  title: string
  filename: string
  farmName?: string
  /** Optional explicit subtitle line. When omitted, a "Generated … | Records …" line is built. */
  subtitle?: string
  /**
   * KPI summary, rendered as branded card boxes (matching the on-screen tiles).
   * Prefer this over `summaryLines` — it carries the accent colour. When only
   * `summaryLines` is supplied, each "Label: value" line is parsed into a
   * neutral card so existing callers still get cards without code changes.
   */
  summaryCards?: PdfExportSummaryCard[]
  summaryLines?: string[]
  columns: PdfExportColumn[]
  rows: (string | number | null | undefined)[][]
  totalsRow?: (string | number | null | undefined)[]
  orientation?: "portrait" | "landscape"
  /** Override the table header fill (defaults to the brand colour). */
  headFillColor?: [number, number, number]

  // ---- Branded letterhead metadata (populated by ReportShell; all optional) ----
  /** Reporting period, rendered as "From → To" in the letterhead. */
  fromDate?: string
  toDate?: string
  /** Who generated the report (username/email) — for the audit trail. */
  generatedBy?: string
  /** Currency label, e.g. "GHS (GHC)". */
  currencyLabel?: string
  /** Active filter selections, rendered as "Filters: a = x; b = y". */
  filtersUsed?: PdfExportFilter[]
  /** Brand colour for the letterhead band + table header. Defaults to emerald. */
  brandColor?: [number, number, number]
}

// Brand palette (emerald — matches the app accent). RGB tuples for jsPDF.
const BRAND_EMERALD: [number, number, number] = [5, 150, 105] // emerald-600
const BAND_EMERALD: [number, number, number] = [4, 120, 87] // emerald-700
const ZEBRA: [number, number, number] = [236, 253, 245] // emerald-50
const TOTALS_BG: [number, number, number] = [209, 250, 229] // emerald-100
const INK: [number, number, number] = [15, 23, 42] // slate-900
const MUTED: [number, number, number] = [100, 116, 139] // slate-500
const RULE: [number, number, number] = [226, 232, 240] // slate-200

// Accent palette for summary cards (mirrors SumTile in report-shell.tsx).
const ACCENT_GREEN: [number, number, number] = [4, 120, 87] // emerald-700
const ACCENT_ROSE: [number, number, number] = [190, 18, 60] // rose-700
const ACCENT_INDIGO: [number, number, number] = [67, 56, 202] // indigo-700
const ACCENT_NEUTRAL: [number, number, number] = [203, 213, 225] // slate-300

function accentColor(accent?: "green" | "rose" | "indigo"): [number, number, number] {
  if (accent === "green") return ACCENT_GREEN
  if (accent === "rose") return ACCENT_ROSE
  if (accent === "indigo") return ACCENT_INDIGO
  return ACCENT_NEUTRAL
}

// Coerce a caller's summary into structured cards: prefer explicit
// `summaryCards`, otherwise split each "Label: value" line into a neutral card.
function resolveSummaryCards(opts: PdfExportOptions): PdfExportSummaryCard[] {
  if (opts.summaryCards && opts.summaryCards.length > 0) return opts.summaryCards
  return (opts.summaryLines ?? []).map((line) => {
    const idx = line.indexOf(":")
    if (idx === -1) return { label: "", value: line.trim() }
    return { label: line.slice(0, idx).trim(), value: line.slice(idx + 1).trim() }
  })
}

const MARGIN = 14

function readFarmName(): string {
  if (typeof window === "undefined") return ""
  try {
    return localStorage.getItem("farmName") || ""
  } catch {
    return ""
  }
}

// Builds the jsPDF document (shared by exportTableToPdf and emailTableAsPdf)
// so PDF generation logic lives in exactly one place.
async function buildPdfDoc(opts: PdfExportOptions) {
  const [{ default: jsPDF }, { default: autoTable }] = await Promise.all([
    import("jspdf"),
    import("jspdf-autotable"),
  ])

  const orientation = opts.orientation ?? (opts.columns.length > 7 ? "landscape" : "portrait")
  const doc = new jsPDF({ orientation, unit: "mm", format: "a4" })
  const farmName = opts.farmName ?? readFarmName()
  const brand = opts.brandColor ?? BRAND_EMERALD

  const pageW = doc.internal.pageSize.getWidth()
  const contentW = pageW - MARGIN * 2
  const generated = new Date().toLocaleString()

  // ---- Letterhead band (page 1) ----
  const BAND_H = 22
  doc.setFillColor(...(opts.brandColor ? brand : BAND_EMERALD))
  doc.rect(0, 0, pageW, BAND_H, "F")

  doc.setTextColor(255, 255, 255)
  doc.setFont("helvetica", "bold")
  doc.setFontSize(15)
  doc.text(farmName || "Report", MARGIN, 10)

  doc.setFont("helvetica", "normal")
  doc.setFontSize(11)
  doc.text(opts.title, MARGIN, 17, { maxWidth: contentW - 55 })

  // Generated timestamp, right-aligned inside the band.
  doc.setFontSize(8)
  doc.text(generated, pageW - MARGIN, 10, { align: "right" })

  // ---- Meta block (below the band) ----
  let y = BAND_H + 8
  doc.setTextColor(...MUTED)
  doc.setFontSize(9)

  const meta: string[] = []
  if (opts.fromDate && opts.toDate) meta.push(`Period:  ${opts.fromDate}  to  ${opts.toDate}`)
  if (opts.currencyLabel) meta.push(`Currency:  ${opts.currencyLabel}`)
  meta.push(`Records:  ${opts.rows.length.toLocaleString()}`)
  if (opts.generatedBy) meta.push(`Generated by:  ${opts.generatedBy}`)

  for (const line of meta) {
    doc.text(line, MARGIN, y)
    y += 5
  }

  if (opts.filtersUsed && opts.filtersUsed.length > 0) {
    const text = "Filters:  " + opts.filtersUsed.map((f) => `${f.label} = ${f.value}`).join("   ·   ")
    const wrapped = doc.splitTextToSize(text, contentW)
    doc.text(wrapped, MARGIN, y)
    y += wrapped.length * 5
  }

  // Legacy explicit subtitle (kept for callers that still pass one).
  if (opts.subtitle) {
    doc.setTextColor(...MUTED)
    doc.text(doc.splitTextToSize(opts.subtitle, contentW), MARGIN, y)
    y += 5
  }

  // ---- Summary cards (KPI tiles, mirroring the on-screen SumTile boxes) ----
  const cards = resolveSummaryCards(opts)
  if (cards.length > 0) {
    y += 2
    const perRow = Math.min(4, cards.length)
    const gap = 3
    const cardW = (contentW - gap * (perRow - 1)) / perRow
    const cardH = 16
    const radius = 1.5

    cards.forEach((card, i) => {
      const col = i % perRow
      const row = Math.floor(i / perRow)
      const x = MARGIN + col * (cardW + gap)
      const cy = y + row * (cardH + gap)

      // Card surface: white fill, subtle slate border.
      doc.setFillColor(255, 255, 255)
      doc.setDrawColor(...RULE)
      doc.setLineWidth(0.2)
      doc.roundedRect(x, cy, cardW, cardH, radius, radius, "FD")

      // Accent bar down the left edge (inset to sit inside the rounded corners).
      const accent = accentColor(card.accent)
      doc.setFillColor(...accent)
      doc.rect(x + 0.3, cy + radius, 1.2, cardH - radius * 2, "F")

      // Label (small, uppercase, muted).
      doc.setTextColor(...MUTED)
      doc.setFont("helvetica", "normal")
      doc.setFontSize(7)
      doc.text(doc.splitTextToSize(card.label.toUpperCase(), cardW - 7)[0] ?? "", x + 4.5, cy + 6)

      // Value (bold, tinted by accent).
      doc.setTextColor(...(card.accent ? accent : INK))
      doc.setFont("helvetica", "bold")
      doc.setFontSize(11)
      doc.text(doc.splitTextToSize(card.value, cardW - 7)[0] ?? "", x + 4.5, cy + 12)
    })

    const rowCount = Math.ceil(cards.length / perRow)
    y += rowCount * cardH + (rowCount - 1) * gap + 3
    doc.setFont("helvetica", "normal")
  }

  y += 2

  // ---- Table ----
  const head = [opts.columns.map((c) => c.header)]
  const body: string[][] = opts.rows.map((r) => r.map((c) => (c == null ? "" : String(c))))
  if (opts.totalsRow) {
    body.push(opts.totalsRow.map((c) => (c == null ? "" : String(c))))
  }

  const columnStyles: Record<number, Record<string, unknown>> = {}
  opts.columns.forEach((c, i) => {
    const styles: Record<string, unknown> = {}
    if (c.align) styles.halign = c.align
    if (c.width) styles.cellWidth = c.width
    if (Object.keys(styles).length > 0) columnStyles[i] = styles
  })

  autoTable(doc, {
    startY: y,
    head,
    body,
    showHead: "everyPage", // repeat column headers on each page
    styles: { fontSize: 8, cellPadding: 2.2, overflow: "linebreak", textColor: INK, lineColor: RULE, lineWidth: 0.1 },
    headStyles: {
      fillColor: opts.headFillColor ?? brand,
      textColor: 255,
      fontStyle: "bold",
      fontSize: 8,
    },
    alternateRowStyles: { fillColor: ZEBRA },
    columnStyles,
    didParseCell: (data) => {
      if (opts.totalsRow && data.section === "body" && data.row.index === body.length - 1) {
        data.cell.styles.fontStyle = "bold"
        data.cell.styles.fillColor = TOTALS_BG
        data.cell.styles.textColor = INK
      }
    },
    // Reserve room top (pages 2+) and bottom (footer).
    margin: { top: MARGIN, left: MARGIN, right: MARGIN, bottom: 16 },
  })

  // ---- Footer on every page (page numbers + running title) ----
  const total = doc.getNumberOfPages()
  const pageH = doc.internal.pageSize.getHeight()
  for (let i = 1; i <= total; i++) {
    doc.setPage(i)
    doc.setDrawColor(...RULE)
    doc.setLineWidth(0.1)
    doc.line(MARGIN, pageH - 11, pageW - MARGIN, pageH - 11)
    doc.setFont("helvetica", "normal")
    doc.setFontSize(8)
    doc.setTextColor(...MUTED)
    const running = farmName ? `${farmName} — ${opts.title}` : opts.title
    doc.text(doc.splitTextToSize(running, contentW - 30)[0], MARGIN, pageH - 6)
    doc.text(`Page ${i} of ${total}`, pageW - MARGIN, pageH - 6, { align: "right" })
  }

  return { doc, farmName }
}

export function pdfDownloadFilename(filename: string): string {
  return `${filename}-${new Date().toISOString().slice(0, 10)}.pdf`
}

export async function exportTableToPdf(opts: PdfExportOptions): Promise<void> {
  const { doc } = await buildPdfDoc(opts)
  doc.save(pdfDownloadFilename(opts.filename))
}

export async function generatePdfBlob(opts: PdfExportOptions): Promise<{ blob: Blob; filename: string; farmName: string }> {
  const { doc, farmName } = await buildPdfDoc(opts)
  const blob = doc.output("blob") as Blob
  return { blob, filename: pdfDownloadFilename(opts.filename), farmName }
}

function readUserEmailFromStorage(): string {
  if (typeof window === "undefined") return ""
  try {
    return localStorage.getItem("username") || ""
  } catch {
    return ""
  }
}

export interface EmailReportResult {
  success: boolean
  message?: string
  recipient: string
}

// Generates the PDF from `opts` (same shape as exportTableToPdf) and emails it
// via POST /api/Email/Report. Recipient defaults to the logged-in user's
// username (the login email stored on sign-in).
export async function emailTableAsPdf(
  opts: PdfExportOptions,
  options?: { to?: string; subject?: string; body?: string }
): Promise<EmailReportResult> {
  const recipient = (options?.to ?? readUserEmailFromStorage()).trim()
  if (!recipient || !recipient.includes("@")) {
    return {
      success: false,
      recipient,
      message: "No recipient email found. Sign in with an email address or pass an explicit `to`.",
    }
  }

  const { blob, filename, farmName } = await generatePdfBlob(opts)
  // Lazy-import the API helper to avoid pulling fetch config into pages that
  // only ever download PDFs locally.
  const { sendReportEmail } = await import("@/lib/api/email")
  const res = await sendReportEmail({
    blob,
    filename,
    to: recipient,
    subject: options?.subject,
    body: options?.body,
    farmName: farmName || undefined,
    reportTitle: opts.title,
    // The signed-in user is the one sharing the report — ReportShell puts them on
    // `generatedBy`. Fall back to the stored login so the body can name the sender.
    senderName: opts.generatedBy || readUserEmailFromStorage() || undefined,
  })
  return { success: res.success, message: res.message, recipient }
}
