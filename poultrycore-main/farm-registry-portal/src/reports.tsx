// Reports & Analytics + Dashboard content, SupportDesk-style: a KPI tile row,
// an activity trend line, a success/failure donut, top-actions bars and
// top-farms progress lists — all drawn with inline SVG from live data
// (dbo.AuditLogs platform feed + farm directory), no chart library.

import { useMemo } from "react"
import type { FarmAuditLogRow, FarmSummary } from "./api"

const TEAL = "#0f766e"
const DARK = "#0c3b3c"
const GREEN = "#059669"
const AMBER = "#d97706"
const RED = "#dc2626"

function dayKey(d: Date): string {
  return d.toISOString().slice(0, 10)
}

export function KpiTile({ label, value, note, tone = "teal", icon }: {
  label: string; value: string; note?: string; tone?: "teal" | "green" | "amber" | "red" | "slate"; icon: React.ReactNode
}) {
  return (
    <div className="kpi-tile">
      <span className={`kpi-chip chip-${tone}`}>{icon}</span>
      <div className="kpi-label">{label}</div>
      <div className="kpi-value">{value}</div>
      {note && <div className={`kpi-note note-${tone}`}>{note}</div>}
    </div>
  )
}

/** Area/line chart of audit events per day over the trailing `days`. */
export function TrendChart({ rows, days = 14 }: { rows: FarmAuditLogRow[]; days?: number }) {
  const { points, max, labels } = useMemo(() => {
    const counts = new Map<string, number>()
    const labels: string[] = []
    for (let i = days - 1; i >= 0; i--) {
      const d = new Date(Date.now() - i * 86400000)
      counts.set(dayKey(d), 0)
      labels.push(d.toLocaleDateString(undefined, { weekday: "short" }).slice(0, 2))
    }
    for (const r of rows) {
      if (!r.timestamp) continue
      const k = dayKey(new Date(r.timestamp))
      if (counts.has(k)) counts.set(k, (counts.get(k) || 0) + 1)
    }
    const vals = [...counts.values()]
    return { points: vals, max: Math.max(4, ...vals), labels }
  }, [rows, days])

  const W = 560, H = 150, PAD = 8
  const x = (i: number) => PAD + (i * (W - 2 * PAD)) / Math.max(1, points.length - 1)
  const y = (v: number) => H - PAD - (v * (H - 2 * PAD)) / max
  const line = points.map((v, i) => `${i === 0 ? "M" : "L"}${x(i).toFixed(1)},${y(v).toFixed(1)}`).join(" ")
  const area = `${line} L${x(points.length - 1).toFixed(1)},${H - PAD} L${x(0).toFixed(1)},${H - PAD} Z`
  return (
    <div>
      <svg viewBox={`0 0 ${W} ${H}`} width="100%" height="160" role="img" aria-label="Audit events per day">
        <defs>
          <linearGradient id="trendFill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={TEAL} stopOpacity="0.25" />
            <stop offset="100%" stopColor={TEAL} stopOpacity="0.02" />
          </linearGradient>
        </defs>
        {[0.25, 0.5, 0.75].map((f) => (
          <line key={f} x1={PAD} x2={W - PAD} y1={H * f} y2={H * f} stroke="#e2e8f0" strokeDasharray="3 4" />
        ))}
        <path d={area} fill="url(#trendFill)" />
        <path d={line} fill="none" stroke={TEAL} strokeWidth="2.5" strokeLinejoin="round" />
        {points.map((v, i) => <circle key={i} cx={x(i)} cy={y(v)} r="2.6" fill={DARK} />)}
      </svg>
      <div className="chart-x-labels">{labels.map((l, i) => <span key={i}>{l}</span>)}</div>
    </div>
  )
}

/** Donut with a center figure; segments = [{value,color,label}]. */
export function Donut({ segments, center, sub }: {
  segments: { value: number; color: string; label: string }[]; center: string; sub?: string
}) {
  const total = Math.max(1, segments.reduce((a, s) => a + s.value, 0))
  const R = 54, C = 2 * Math.PI * R
  let acc = 0
  return (
    <div className="donut-wrap">
      <svg viewBox="0 0 140 140" width="150" height="150" role="img" aria-label={sub || center}>
        <circle cx="70" cy="70" r={R} fill="none" stroke="#eef2f6" strokeWidth="15" />
        {segments.map((s, i) => {
          const frac = s.value / total
          const el = (
            <circle key={i} cx="70" cy="70" r={R} fill="none" stroke={s.color} strokeWidth="15"
              strokeDasharray={`${(frac * C).toFixed(1)} ${C.toFixed(1)}`}
              strokeDashoffset={(-acc * C).toFixed(1)}
              transform="rotate(-90 70 70)" strokeLinecap="butt" />
          )
          acc += frac
          return el
        })}
        <text x="70" y="67" textAnchor="middle" fontSize="22" fontWeight="700" fill="#0f172a">{center}</text>
        {sub && <text x="70" y="86" textAnchor="middle" fontSize="9" fill="#64748b">{sub.toUpperCase()}</text>}
      </svg>
      <div className="donut-legend">
        {segments.map((s) => (
          <div key={s.label}><span className="dot" style={{ background: s.color }} />{s.label}
            <strong>{total ? Math.round((s.value / Math.max(1, segments.reduce((a, x) => a + x.value, 0))) * 100) : 0}%</strong></div>
        ))}
      </div>
    </div>
  )
}

export function BarList({ items, color = TEAL }: { items: { label: string; value: number }[]; color?: string }) {
  const max = Math.max(1, ...items.map((i) => i.value))
  return (
    <div className="bar-list">
      {items.map((i) => (
        <div key={i.label} className="bar-row">
          <span className="bar-label" title={i.label}>{i.label}</span>
          <span className="bar-value">{i.value.toLocaleString()}</span>
          <div className="bar-track"><div className="bar-fill" style={{ width: `${(i.value / max) * 100}%`, background: color }} /></div>
        </div>
      ))}
      {items.length === 0 && <p className="subtle-help">No data yet.</p>}
    </div>
  )
}

function topBy(rows: FarmAuditLogRow[], key: (r: FarmAuditLogRow) => string, n: number) {
  const m = new Map<string, number>()
  for (const r of rows) {
    const k = key(r)
    if (k) m.set(k, (m.get(k) || 0) + 1)
  }
  return [...m.entries()].sort((a, b) => b[1] - a[1]).slice(0, n).map(([label, value]) => ({ label, value }))
}

// ---------------------------------------------------------------- Reports page
export function ReportsPage({ farms, rows, resolveFarmName }: {
  farms: FarmSummary[]; rows: FarmAuditLogRow[]; resolveFarmName: (id?: string | null) => string
}) {
  const ok = rows.filter((r) => (r.status || "").toLowerCase() === "success").length
  const failed = rows.length - ok
  const today = rows.filter((r) => r.timestamp && dayKey(new Date(r.timestamp)) === dayKey(new Date())).length
  const subscribed = farms.filter((f) => f.hasPaidSubscription === true).length
  const activeFarms = new Set(rows.map((r) => (r.farmId || "").toLowerCase()).filter(Boolean)).size
  const topActions = topBy(rows, (r) => r.action || "", 4)
  const topFarms = topBy(rows, (r) => resolveFarmName(r.farmId), 5)

  return (
    <>
      <div className="kpi-row">
        <KpiTile label="Registered farms" value={String(farms.length)} note={`${activeFarms} active in log`} icon={ic("M3 21V8l9-5 9 5v13M9 21v-6h6v6")} />
        <KpiTile label="Subscribed" value={String(subscribed)} tone="green" note={`${farms.length ? Math.round((subscribed / farms.length) * 100) : 0}% of farms`} icon={ic("M20 6 9 17l-5-5")} />
        <KpiTile label="Audit events" value={rows.length.toLocaleString()} tone="slate" note="loaded window" icon={ic("M12 8v4l3 3M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0")} />
        <KpiTile label="Events today" value={String(today)} note="since midnight" icon={ic("M8 2v4M16 2v4M3 10h18M5 4h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z")} />
        <KpiTile label="Success rate" value={`${rows.length ? ((ok / rows.length) * 100).toFixed(1) : "—"}%`} tone="green" note="of audit events" icon={ic("M22 11.1V12a10 10 0 1 1-5.9-9.1M22 4 12 14l-3-3")} />
        <KpiTile label="Failed events" value={String(failed)} tone={failed > 0 ? "red" : "slate"} note={failed > 0 ? "needs attention" : "all clear"} icon={ic("M12 9v4M12 17h.01M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z")} />
      </div>

      <div className="report-grid">
        <div className="card report-wide">
          <div className="card-toolbar"><h3 className="card-toolbar-title">Platform activity — last 14 days</h3></div>
          <TrendChart rows={rows} />
        </div>
        <div className="card">
          <div className="card-toolbar"><h3 className="card-toolbar-title">Outcome split</h3></div>
          <Donut
            segments={[{ value: ok, color: GREEN, label: "Success" }, { value: failed, color: RED, label: "Failed" }]}
            center={rows.length.toLocaleString()} sub="events"
          />
        </div>
      </div>

      <div className="report-grid">
        <div className="card">
          <div className="card-toolbar"><h3 className="card-toolbar-title">Top actions</h3></div>
          <BarList items={topActions} />
        </div>
        <div className="card report-wide">
          <div className="card-toolbar"><h3 className="card-toolbar-title">Most active farms</h3></div>
          <BarList items={topFarms} color={DARK} />
        </div>
      </div>
    </>
  )
}

// ---------------------------------------------------------------- Dashboard content
export function DashboardPage({ farms, rows, resolveFarmName, onOpenReports, onOpenAudit }: {
  farms: FarmSummary[]; rows: FarmAuditLogRow[]; resolveFarmName: (id?: string | null) => string
  onOpenReports: () => void; onOpenAudit: () => void
}) {
  const recent = rows.slice(0, 8)
  const subscribed = farms.filter((f) => f.hasPaidSubscription === true).length
  return (
    <div className="report-grid">
      <div className="card report-wide">
        <div className="card-toolbar">
          <h3 className="card-toolbar-title">Recent platform activity</h3>
          <button type="button" className="link-btn" onClick={onOpenAudit}>View all</button>
        </div>
        <table>
          <thead><tr><th>Time</th><th>User</th><th>Action</th><th>Farm</th><th>Status</th></tr></thead>
          <tbody>
            {recent.length === 0 ? (
              <tr><td colSpan={5} style={{ color: "#64748b" }}>No audit activity loaded yet.</td></tr>
            ) : recent.map((r) => (
              <tr key={r.id}>
                <td className="mono">{r.timestamp ? new Date(r.timestamp).toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" }) : "—"}</td>
                <td>{r.userName}</td>
                <td>{r.action}</td>
                <td>{resolveFarmName(r.farmId)}</td>
                <td>{(r.status || "").toLowerCase() === "success"
                  ? <span className="badge badge-yes">Success</span>
                  : <span className="badge badge-no">{r.status || "—"}</span>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div className="card">
        <div className="card-toolbar">
          <h3 className="card-toolbar-title">Subscription share</h3>
          <button type="button" className="link-btn" onClick={onOpenReports}>Reports</button>
        </div>
        <Donut
          segments={[
            { value: subscribed, color: GREEN, label: "Subscribed" },
            { value: Math.max(0, farms.length - subscribed), color: AMBER, label: "Not subscribed" },
          ]}
          center={String(farms.length)} sub="farms"
        />
      </div>
    </div>
  )
}

function ic(d: string) {
  return <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d={d} /></svg>
}
