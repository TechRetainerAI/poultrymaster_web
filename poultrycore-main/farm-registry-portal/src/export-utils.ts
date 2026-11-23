// Dependency-free data export for the admin tables.
//
//   * downloadCsv   — builds a UTF-8 CSV (with a BOM so Excel reads accents
//                     correctly) and saves it via a Blob download.
//   * printableTable — opens a clean, print-ready window and triggers the
//                     browser's print dialog, where "Save as PDF" produces the
//                     PDF. No jsPDF/bundle cost; prints paginate automatically.
//
// Both take the SAME column definition, so a page describes its columns once
// and gets CSV and PDF from it. Pass the full filtered/sorted row set (not just
// the visible page) so the export is the whole current view.

export type Column<T> = { header: string; value: (row: T) => string | number | null | undefined }

function cell(v: string | number | null | undefined): string {
  return v === null || v === undefined ? "" : String(v)
}

/** Today as YYYY-MM-DD, for filenames / titles. */
export function todayStamp(): string {
  const d = new Date()
  const p = (n: number) => String(n).padStart(2, "0")
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`
}

function csvEscape(s: string): string {
  return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
}

export function downloadCsv<T>(baseName: string, columns: Column<T>[], rows: T[]): void {
  const head = columns.map((c) => csvEscape(c.header)).join(",")
  const body = rows.map((r) => columns.map((c) => csvEscape(cell(c.value(r)))).join(",")).join("\r\n")
  const csv = "﻿" + head + "\r\n" + body
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" })
  const url = URL.createObjectURL(blob)
  const a = document.createElement("a")
  a.href = url
  a.download = baseName.endsWith(".csv") ? baseName : `${baseName}.csv`
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}

function htmlEscape(s: string): string {
  const map: Record<string, string> = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }
  return s.replace(/[&<>"']/g, (c) => map[c])
}

export function printableTable<T>(opts: {
  title: string
  subtitle?: string
  columns: Column<T>[]
  rows: T[]
}): void {
  const { title, subtitle, columns, rows } = opts
  const when = new Date().toLocaleString(undefined, {
    year: "numeric", month: "short", day: "numeric", hour: "2-digit", minute: "2-digit",
  })
  const thead = columns.map((c) => `<th>${htmlEscape(c.header)}</th>`).join("")
  const tbody = rows.length === 0
    ? `<tr><td colspan="${columns.length}" class="empty">No rows in the current view.</td></tr>`
    : rows.map((r) => `<tr>${columns.map((c) => `<td>${htmlEscape(cell(c.value(r)))}</td>`).join("")}</tr>`).join("")

  const docTitle = `${title} — ${todayStamp()}`
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8">
<title>${htmlEscape(docTitle)}</title>
<style>
  * { box-sizing: border-box; }
  body { font-family: -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; color: #0f172a; margin: 24px; }
  header { border-bottom: 2px solid #0c3b3c; padding-bottom: 10px; margin-bottom: 14px; }
  h1 { font-size: 18px; margin: 0 0 4px; color: #0c3b3c; }
  .meta { font-size: 11px; color: #475569; }
  table { width: 100%; border-collapse: collapse; font-size: 11px; }
  th, td { text-align: left; padding: 6px 8px; border-bottom: 1px solid #cbd5e1; vertical-align: top; }
  th { background: #f1f5f9; border-bottom: 2px solid #94a3b8; font-size: 10px; text-transform: uppercase; letter-spacing: .03em; color: #334155; }
  tr:nth-child(even) td { background: #f8fafc; }
  td.empty { color: #64748b; text-align: center; padding: 24px; }
  @page { margin: 14mm; }
  @media print {
    body { margin: 0; }
    thead { display: table-header-group; }
    tr { break-inside: avoid; }
  }
</style></head>
<body>
  <header>
    <h1>${htmlEscape(title)}</h1>
    <div class="meta">${htmlEscape(subtitle ? subtitle + " · " : "")}${rows.length} row${rows.length === 1 ? "" : "s"} · Generated ${htmlEscape(when)}</div>
  </header>
  <table><thead><tr>${thead}</tr></thead><tbody>${tbody}</tbody></table>
  <script>
    window.onload = function () { setTimeout(function () { window.focus(); window.print(); }, 150); };
    window.onafterprint = function () { window.close(); };
  </script>
</body></html>`

  const w = window.open("", "_blank", "width=1100,height=800")
  if (!w) {
    alert("Pop-up blocked. Allow pop-ups for this site to export a PDF, or use Export CSV instead.")
    return
  }
  w.document.open()
  w.document.write(html)
  w.document.close()
}
