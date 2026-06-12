import { format, parseISO, startOfMonth, endOfMonth, eachMonthOfInterval, isValid } from "date-fns"
import { formatCurrency } from "@/lib/utils/currency"

export type MonthKey = string

function expenseDate(e: Record<string, unknown>): Date {
  const raw = (e.expenseDate ?? e.expense_date) as string
  const d = raw ? parseISO(String(raw).slice(0, 10)) : new Date(0)
  return isValid(d) ? d : new Date(0)
}

function saleDate(s: Record<string, unknown>): Date {
  const raw = (s.saleDate ?? s.sale_date) as string
  const d = raw ? parseISO(String(raw).slice(0, 10)) : new Date(0)
  return isValid(d) ? d : new Date(0)
}

function monthKey(d: Date): MonthKey {
  return format(d, "yyyy-MM")
}

/** Heuristic: direct flock / input costs vs overhead (tweak keywords to match your chart of accounts). */
export function isLikelyCogsCategory(category: string): boolean {
  const c = (category || "").toLowerCase()
  if (!c.trim()) return false
  const keys = [
    "feed",
    "transport",
    "freight",
    "logistics",
    "labor",
    "labour",
    "wage",
    "payroll",
    "batch",
    "chick",
    "doc",
    "day-old",
    "vaccin",
    "medic",
    "vet",
    "supplement",
    "flock",
    "bird",
    "egg pack",
    "packaging",
    "processing",
  ]
  return keys.some((k) => c.includes(k))
}

export function formatAccountingCell(amount: number, currencyCode: string, forCsv = false): string {
  const n = Number(amount) || 0
  if (forCsv) {
    const s = formatCurrency(Math.abs(n), currencyCode).replace(/[₵$,]/g, "").trim()
    return n < 0 ? `(${s})` : s
  }
  const s = formatCurrency(Math.abs(n), currencyCode)
  return n < 0 ? `(${s})` : s
}

export function formatPercentCell(ratio: number): string {
  if (!Number.isFinite(ratio)) return "—"
  return `${(ratio * 100).toFixed(1)}%`
}

export interface FinancialStatementMonth {
  key: MonthKey
  labelRow1: string
  labelRow2: string
  calendarYear: number
}

export type StatementRowKind = "section" | "line" | "subtotal" | "highlight" | "percent"

export interface FinancialStatementRow {
  kind: StatementRowKind
  label: string
  /** One value per month column, same order as `months` */
  values: number[]
  /** Gross margin % etc. */
  isPercent?: boolean
  /** e.g. weighted GM% = total GM / total revenue */
  totalOverride?: number | null
}

export interface MonthlyFinancialStatement {
  months: FinancialStatementMonth[]
  currencyCode: string
  rows: FinancialStatementRow[]
  /** Column totals: sum of revenue months, etc. — same length as months */
  revenueByMonth: number[]
  periodLabel: string
}

function sum(arr: number[]): number {
  return arr.reduce((a, b) => a + b, 0)
}

function addVectors(a: number[], b: number[]): number[] {
  return a.map((v, i) => v + (b[i] ?? 0))
}

export function buildMonthRange(
  dateFrom: string,
  dateTo: string,
  sales: Record<string, unknown>[],
  expenses: Record<string, unknown>[],
): { start: Date; end: Date } {
  const candidates: Date[] = []
  if (dateFrom) {
    const d = parseISO(dateFrom)
    if (isValid(d)) candidates.push(startOfMonth(d))
  }
  if (dateTo) {
    const d = parseISO(dateTo)
    if (isValid(d)) candidates.push(endOfMonth(d))
  }
  sales.forEach((s) => {
    const d = saleDate(s)
    if (d.getTime() > 0) candidates.push(d)
  })
  expenses.forEach((e) => {
    const d = expenseDate(e)
    if (d.getTime() > 0) candidates.push(d)
  })

  if (candidates.length === 0) {
    const now = new Date()
    return { start: startOfMonth(now), end: endOfMonth(now) }
  }

  let start = candidates.reduce((min, d) => (d < min ? d : min), candidates[0])
  let end = candidates.reduce((max, d) => (d > max ? d : max), candidates[0])
  if (dateFrom) {
    const d = parseISO(dateFrom)
    if (isValid(d)) start = startOfMonth(d)
  }
  if (dateTo) {
    const d = parseISO(dateTo)
    if (isValid(d)) end = endOfMonth(d)
  }
  if (start > end) [start, end] = [end, start]
  return { start: startOfMonth(start), end: endOfMonth(end) }
}

export function buildMonthlyFinancialStatement(
  sales: Record<string, unknown>[],
  expenses: Record<string, unknown>[],
  dateFrom: string,
  dateTo: string,
  currencyCode: string,
): MonthlyFinancialStatement {
  const { start, end } = buildMonthRange(dateFrom, dateTo, sales, expenses)
  const interval = eachMonthOfInterval({ start, end })
  const months: FinancialStatementMonth[] = interval.map((d) => ({
    key: monthKey(d),
    labelRow1: format(d, "MMM-yy"),
    labelRow2: format(d, "MMM yyyy"),
    calendarYear: d.getFullYear(),
  }))

  const monthIndex = (key: MonthKey) => months.findIndex((m) => m.key === key)
  const n = months.length
  const zeros = () => new Array(n).fill(0)

  const revenueByMonth = zeros()
  sales.forEach((s) => {
    const d = saleDate(s)
    if (d.getTime() <= 0) return
    const key = monthKey(d)
    const idx = monthIndex(key)
    if (idx < 0) return
    revenueByMonth[idx] += Number(s.totalAmount ?? s.TotalAmount ?? 0)
  })

  const cogsByCategory = new Map<string, number[]>()
  const opexByCategory = new Map<string, number[]>()

  expenses.forEach((e) => {
    const d = expenseDate(e)
    if (d.getTime() <= 0) return
    const key = monthKey(d)
    const idx = monthIndex(key)
    if (idx < 0) return
    const cat = String(e.category ?? e.Category ?? "Uncategorized").trim() || "Uncategorized"
    const amt = Number(e.amount ?? e.Amount ?? 0)
    const map = isLikelyCogsCategory(cat) ? cogsByCategory : opexByCategory
    const row = map.get(cat) ?? zeros()
    row[idx] += amt
    map.set(cat, row)
  })

  const rows: FinancialStatementRow[] = []

  rows.push({ kind: "section", label: "REVENUE", values: zeros() })
  rows.push({
    kind: "line",
    label: "Total sales revenue",
    values: [...revenueByMonth],
  })
  rows.push({
    kind: "subtotal",
    label: "Total revenue",
    values: [...revenueByMonth],
  })

  rows.push({ kind: "section", label: "COST OF GOODS SOLD", values: zeros() })
  const cogsCategories = [...cogsByCategory.keys()].sort((a, b) => a.localeCompare(b))
  let cogsTotals = zeros()
  if (cogsCategories.length === 0) {
    rows.push({
      kind: "line",
      label: "No COGS-classified expenses (see Operating)",
      values: zeros(),
    })
  } else {
    cogsCategories.forEach((cat) => {
      const v = cogsByCategory.get(cat)!
      rows.push({ kind: "line", label: cat, values: [...v] })
      cogsTotals = addVectors(cogsTotals, v)
    })
  }
  rows.push({ kind: "subtotal", label: "Total COGS", values: [...cogsTotals] })

  const grossMargin = revenueByMonth.map((r, i) => r - (cogsTotals[i] ?? 0))
  rows.push({ kind: "highlight", label: "Gross margin", values: [...grossMargin] })
  const gmPct = revenueByMonth.map((r, i) => (r > 0 ? grossMargin[i] / r : NaN))
  const totalRevAll = sum(revenueByMonth)
  const totalGmAll = sum(grossMargin)
  const weightedGmPct = totalRevAll > 0 ? totalGmAll / totalRevAll : NaN
  rows.push({
    kind: "percent",
    label: "Gross margin %",
    values: gmPct.map((x) => (Number.isFinite(x) ? x : NaN)),
    isPercent: true,
    totalOverride: Number.isFinite(weightedGmPct) ? weightedGmPct : null,
  })

  rows.push({ kind: "section", label: "OPERATING EXPENSES", values: zeros() })
  const opexCategories = [...opexByCategory.keys()].sort((a, b) => a.localeCompare(b))
  let opexTotals = zeros()
  if (opexCategories.length === 0) {
    rows.push({ kind: "line", label: "No operating expenses in period", values: zeros() })
  } else {
    opexCategories.forEach((cat) => {
      const v = opexByCategory.get(cat)!
      rows.push({ kind: "line", label: cat, values: [...v] })
      opexTotals = addVectors(opexTotals, v)
    })
  }
  rows.push({ kind: "subtotal", label: "Total operating expenses", values: [...opexTotals] })

  const ebit = grossMargin.map((g, i) => g - (opexTotals[i] ?? 0))
  rows.push({ kind: "highlight", label: "Operating profit (EBIT)", values: [...ebit] })

  const interest = zeros()
  rows.push({ kind: "line", label: "Interest expense", values: interest })

  const ebt = ebit.map((x, i) => x - (interest[i] ?? 0))
  rows.push({ kind: "highlight", label: "Earnings before taxes (EBT)", values: [...ebt] })

  const periodLabel =
    months.length > 0
      ? `${months[0].labelRow2} – ${months[months.length - 1].labelRow2}`
      : "—"

  return {
    months,
    currencyCode,
    rows,
    revenueByMonth,
    periodLabel,
  }
}

export function statementRowTotals(row: Pick<FinancialStatementRow, "values" | "isPercent" | "totalOverride">): number {
  if (row.totalOverride != null && Number.isFinite(row.totalOverride)) return row.totalOverride
  if (row.isPercent) {
    const finite = row.values.filter((x) => Number.isFinite(x))
    return finite.length ? finite.reduce((a, b) => a + b, 0) / finite.length : NaN
  }
  return sum(row.values.map((v) => (Number.isFinite(v) ? v : 0)))
}

/** CSV with UTF-8 BOM for Excel */
export function financialStatementToCsv(statement: MonthlyFinancialStatement, farmName?: string): string {
  const { months, currencyCode, rows, periodLabel } = statement
  const unit = `[${currencyCode}]`
  const lines: string[][] = []

  lines.push(["Monthly Financial Statement"])
  if (farmName) lines.push(["Farm", farmName])
  lines.push(["Period", periodLabel])
  lines.push([])
  const header = ["Line item", "Unit", ...months.map((m) => m.labelRow2), "Total"]
  lines.push(header)

  const esc = (s: string) => {
    if (s.includes('"') || s.includes(",") || s.includes("\n")) return `"${s.replace(/"/g, '""')}"`
    return s
  }

  rows.forEach((r) => {
    if (r.kind === "section") {
      lines.push([r.label, ...Array(months.length + 2).fill("")])
      return
    }
    const totals = statementRowTotals(r)
    const cells = r.values.map((v) =>
      r.isPercent ? formatPercentCell(v) : formatAccountingCell(v, currencyCode, true),
    )
    const totalCell = r.isPercent ? formatPercentCell(totals) : formatAccountingCell(totals, currencyCode, true)
    lines.push([r.label, unit, ...cells, totalCell])
  })

  return "\uFEFF" + lines.map((row) => row.map(esc).join(",")).join("\r\n")
}

export async function downloadFinancialStatementPdf(
  statement: MonthlyFinancialStatement,
  farmName?: string,
): Promise<void> {
  const [{ default: jsPDF }, { default: autoTable }] = await Promise.all([
    import("jspdf"),
    import("jspdf-autotable"),
  ])

  const { months, currencyCode, rows, periodLabel } = statement
  const unit = `[${currencyCode}]`
  const landscape = months.length > 6

  const doc = new jsPDF({ orientation: landscape ? "landscape" : "portrait", unit: "mm", format: "a4" })
  let y = 12
  doc.setFontSize(14)
  doc.text("Monthly Financial Statement", 14, y)
  y += 7
  doc.setFontSize(9)
  if (farmName) {
    doc.text(`Farm: ${farmName}`, 14, y)
    y += 5
  }
  doc.text(`Period: ${periodLabel}`, 14, y)
  y += 6

  const head = [["Line item", "Unit", ...months.map((m) => m.labelRow1), "Total"]]

  const body: string[][] = []
  rows.forEach((r) => {
    if (r.kind === "section") {
      body.push([r.label, ...new Array(months.length + 1).fill("")])
      return
    }
    const totals = statementRowTotals(r)
    const cells = r.values.map((v) =>
      r.isPercent ? formatPercentCell(v) : formatAccountingCell(v, currencyCode),
    )
    const totalCell = r.isPercent ? formatPercentCell(totals) : formatAccountingCell(totals, currencyCode)
    body.push([r.label, unit, ...cells, totalCell])
  })

  autoTable(doc, {
    startY: y,
    head: head,
    body: body,
    styles: { fontSize: landscape ? 6 : 7, cellPadding: 1.5 },
    headStyles: { fillColor: [219, 234, 254], textColor: [30, 41, 59], fontStyle: "bold" },
    bodyStyles: { textColor: [15, 23, 42] },
    didParseCell: (data) => {
      if (data.section !== "body") return
      const idx = data.row.index
      if (idx < 0 || idx >= rows.length) return
      const row = rows[idx]
      if (row.kind === "section") {
        data.cell.styles.fontStyle = "bold"
        data.cell.styles.fillColor = [241, 245, 249]
      }
      if (row.kind === "subtotal") {
        data.cell.styles.fontStyle = "bold"
        data.cell.styles.fillColor = [248, 250, 252]
      }
      if (row.kind === "highlight") {
        data.cell.styles.fillColor = [220, 252, 231]
        data.cell.styles.fontStyle = "bold"
      }
    },
    margin: { left: 14, right: 14 },
  })

  doc.save(`monthly-financial-statement-${format(new Date(), "yyyy-MM-dd")}.pdf`)
}
