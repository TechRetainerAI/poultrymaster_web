export interface PdfExportColumn {
  header: string
  align?: "left" | "right" | "center"
  width?: number
}

export interface PdfExportOptions {
  title: string
  filename: string
  farmName?: string
  subtitle?: string
  summaryLines?: string[]
  columns: PdfExportColumn[]
  rows: (string | number | null | undefined)[][]
  totalsRow?: (string | number | null | undefined)[]
  orientation?: "portrait" | "landscape"
  headFillColor?: [number, number, number]
}

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

  let y = 14
  doc.setFontSize(16)
  doc.setTextColor(33, 37, 41)
  const titleLine = farmName ? `${farmName} — ${opts.title}` : opts.title
  doc.text(titleLine, 14, y)
  y += 6

  doc.setFontSize(9)
  doc.setTextColor(100, 100, 100)
  const generated = new Date().toLocaleString()
  doc.text(opts.subtitle ?? `Generated: ${generated}  |  Records: ${opts.rows.length}`, 14, y)
  y += 6

  if (opts.summaryLines && opts.summaryLines.length > 0) {
    doc.setFontSize(9)
    doc.setTextColor(33, 37, 41)
    for (const line of opts.summaryLines) {
      doc.text(line, 14, y)
      y += 5
    }
    y += 1
  }

  const head = [opts.columns.map((c) => c.header)]
  const body: string[][] = opts.rows.map((r) =>
    r.map((c) => (c == null ? "" : String(c))),
  )
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
    styles: { fontSize: 8, cellPadding: 2 },
    headStyles: {
      fillColor: opts.headFillColor ?? [37, 99, 235],
      textColor: 255,
      fontStyle: "bold",
      fontSize: 8,
    },
    alternateRowStyles: { fillColor: [248, 250, 252] },
    columnStyles,
    didParseCell: (data) => {
      if (
        opts.totalsRow &&
        data.section === "body" &&
        data.row.index === body.length - 1
      ) {
        data.cell.styles.fontStyle = "bold"
        data.cell.styles.fillColor = [226, 232, 240]
      }
    },
    margin: { left: 14, right: 14 },
  })

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
  })
  return { success: res.success, message: res.message, recipient }
}
