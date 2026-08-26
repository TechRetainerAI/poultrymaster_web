/**
 * Professional print report — opens a new window with branded, print-ready HTML.
 */

export interface PrintReportConfig {
  hotelName: string
  hotelAddress?: string
  hotelPhone?: string
  hotelEmail?: string
  title: string
  dateRange?: { from: string; to: string }
  summaryCards?: { label: string; value: string }[]
  headers: string[]
  rows: (string | number | null | undefined)[][]
  currency?: string
}

export function printReport(config: PrintReportConfig) {
  const cur = config.currency ?? "GH₵"
  const now = new Date().toLocaleString()
  const contact = [config.hotelAddress, config.hotelPhone, config.hotelEmail].filter(Boolean).join("  •  ")
  const accentColors = ["#10b981", "#ef4444", "#6366f1", "#f59e0b"]

  const summaryHtml = config.summaryCards?.length
    ? `<div style="display:grid;grid-template-columns:repeat(${Math.min(config.summaryCards.length, 4)},1fr);gap:12px;margin:20px 0">
        ${config.summaryCards.map((c, i) => `
          <div style="border:1px solid #e2e8f0;border-radius:8px;padding:14px 16px;background:#fff;border-left:4px solid ${accentColors[i % 4]};position:relative">
            <div style="font-size:10px;text-transform:uppercase;letter-spacing:0.08em;color:#64748b;margin-bottom:4px;font-weight:600">${c.label}</div>
            <div style="font-size:22px;font-weight:800;color:#0f172a;letter-spacing:-0.02em">${c.value}</div>
          </div>
        `).join("")}
      </div>`
    : ""

  const tableHtml = `
    <table style="width:100%;border-collapse:collapse;font-size:11px;margin-top:16px">
      <thead>
        <tr>${config.headers.map((h) => `
          <th style="text-align:left;padding:10px 8px;background:#6d28d9;color:white;font-size:10px;text-transform:uppercase;letter-spacing:0.05em;font-weight:700">${h}</th>
        `).join("")}</tr>
      </thead>
      <tbody>
        ${config.rows.map((row, i) => `
          <tr style="background:${i % 2 === 0 ? "#fff" : "#f8fafc"}">
            ${row.map((v) => `<td style="padding:8px;border-bottom:1px solid #e2e8f0;font-size:11px">${v ?? ""}</td>`).join("")}
          </tr>
        `).join("")}
      </tbody>
    </table>
  `

  const html = `<!DOCTYPE html>
<html>
<head>
  <title>${config.title} — ${config.hotelName}</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: 'Segoe UI', system-ui, -apple-system, sans-serif; color: #0f172a; max-width: 1100px; margin: 0 auto; padding: 0; }
    @media print { @page { size: landscape; margin: 8mm; } }
  </style>
</head>
<body>
  <!-- Accent bar -->
  <div style="height:6px;background:#6d28d9;width:100%"></div>

  <!-- Header -->
  <div style="padding:24px 28px 16px;display:flex;justify-content:space-between;align-items:flex-start">
    <div>
      <h1 style="font-size:26px;color:#6d28d9;font-weight:800;margin:0;letter-spacing:-0.02em">${config.hotelName}</h1>
      ${contact ? `<div style="font-size:10px;color:#94a3b8;margin-top:3px">${contact}</div>` : ""}
    </div>
    <div style="text-align:right;background:#f8fafc;border:1px solid #e2e8f0;border-radius:8px;padding:10px 14px">
      <div style="font-size:8px;text-transform:uppercase;letter-spacing:0.08em;color:#94a3b8;font-weight:600">Generated</div>
      <div style="font-size:11px;color:#334155;font-weight:600">${now}</div>
      ${config.dateRange ? `
        <div style="font-size:8px;text-transform:uppercase;letter-spacing:0.08em;color:#94a3b8;font-weight:600;margin-top:4px">Period</div>
        <div style="font-size:11px;color:#334155;font-weight:600">${config.dateRange.from}  —  ${config.dateRange.to}</div>
      ` : ""}
    </div>
  </div>

  <!-- Divider -->
  <div style="margin:0 28px;height:1px;background:#e2e8f0"></div>

  <!-- Report Title Section -->
  <div style="padding:16px 28px">
    <h2 style="font-size:22px;font-weight:800;color:#1e293b;margin:0">${config.title}</h2>
    <div style="display:inline-block;margin-top:6px;background:#6d28d9;color:white;font-size:10px;font-weight:700;padding:3px 10px;border-radius:10px;letter-spacing:0.05em">${config.rows.length} RECORDS</div>
    <span style="font-size:10px;color:#94a3b8;margin-left:8px">Currency: ${cur}</span>
  </div>

  <!-- Summary Cards -->
  <div style="padding:0 28px">
    ${summaryHtml}
  </div>

  <!-- Data Table -->
  <div style="padding:0 28px 20px">
    ${tableHtml}
  </div>

  <!-- Footer -->
  <div style="padding:12px 28px;border-top:2px solid #6d28d9;display:flex;justify-content:space-between;font-size:9px;color:#94a3b8">
    <span>${config.hotelName}  |  ${config.title}</span>
    <span>Page 1 of 1  |  ${cur}</span>
  </div>

  <script>window.onload = function() { setTimeout(function() { window.print(); }, 300); }</script>
</body>
</html>`

  const win = window.open("", "_blank")
  if (win) {
    win.document.write(html)
    win.document.close()
  }
}
