// PROMPT 2: Executive platform operations dashboard. Answers at a glance:
// how many organizations/companies exist, who is active, which verticals are
// growing, who has gone quiet, who is in trial / paying / past due.
// Data comes exclusively from the Prompt 1 activity foundation (aggregates +
// daily snapshots) — never raw audit rows.

import { useEffect, useMemo, useState } from "react"
import { Donut, KpiTile } from "./reports"
import {
  FAMILIES,
  describeActivity,
  fetchAttentionQueue,
  fetchGoingQuiet,
  fetchModuleAdoption,
  fetchNewCustomers,
  fetchOverview,
  fetchRecent,
  fetchTimeSeries,
  timeAgo,
  type GoingQuietRow,
  type ModuleAdoptionRow,
  type NewCustomerRow,
  type AttentionItem,
  type Overview,
  type OrganizationSummary,
  type RecentActivity,
  type TimePoint,
} from "./platform-activity-api"

const TEAL = "#0f766e"
const DARK = "#0c3b3c"

function ic(d: string) {
  return <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d={d} /></svg>
}

function TrendBadge({ status, pct }: { status: string; pct: number | null }) {
  const cls = status === "Increasing" || status === "NewActivity" ? "badge badge-yes"
    : status === "Declining" || status === "Inactive" ? "badge badge-no"
    : "badge"
  const text = status === "NewActivity" ? "New"
    : pct === null ? status
    : `${pct > 0 ? "+" : ""}${pct}%`
  return <span className={cls} title={status}>{text}</span>
}

/** Meaningful-activity line over the window, drawn from daily snapshots. */
function ActivityTrendChart({ points, days }: { points: TimePoint[]; days: number }) {
  const { vals, max, labels } = useMemo(() => {
    const byDate = new Map(points.map((p) => [p.businessDate.slice(0, 10), p.meaningfulCount]))
    const vals: number[] = []
    const labels: string[] = []
    for (let i = days - 1; i >= 0; i--) {
      const d = new Date(Date.now() - i * 86400000)
      const k = d.toISOString().slice(0, 10)
      vals.push(byDate.get(k) || 0)
      labels.push(days <= 7
        ? d.toLocaleDateString(undefined, { weekday: "short" }).slice(0, 2)
        : d.getDate() === 1 || i === days - 1 || i === 0
          ? d.toLocaleDateString(undefined, { month: "short", day: "numeric" })
          : "")
    }
    return { vals, max: Math.max(4, ...vals), labels }
  }, [points, days])

  const W = 560, H = 150, PAD = 8
  const x = (i: number) => PAD + (i * (W - 2 * PAD)) / Math.max(1, vals.length - 1)
  const y = (v: number) => H - PAD - (v * (H - 2 * PAD)) / max
  const line = vals.map((v, i) => `${i === 0 ? "M" : "L"}${x(i).toFixed(1)},${y(v).toFixed(1)}`).join(" ")
  const area = `${line} L${x(vals.length - 1).toFixed(1)},${H - PAD} L${x(0).toFixed(1)},${H - PAD} Z`
  const total = vals.reduce((a, b) => a + b, 0)
  if (total === 0) {
    return <p className="subtle-help">No meaningful activity in this window yet. New customer actions will appear here as they happen.</p>
  }
  return (
    <div>
      <svg viewBox={`0 0 ${W} ${H}`} width="100%" height="160" role="img" aria-label="Meaningful activity per day">
        <defs>
          <linearGradient id="paTrendFill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={TEAL} stopOpacity="0.25" />
            <stop offset="100%" stopColor={TEAL} stopOpacity="0.02" />
          </linearGradient>
        </defs>
        {[0.25, 0.5, 0.75].map((f) => (
          <line key={f} x1={PAD} x2={W - PAD} y1={H * f} y2={H * f} stroke="#e2e8f0" strokeDasharray="3 4" />
        ))}
        <path d={area} fill="url(#paTrendFill)" />
        <path d={line} fill="none" stroke={TEAL} strokeWidth="2.5" strokeLinejoin="round" />
        {vals.length <= 40 && vals.map((v, i) => <circle key={i} cx={x(i)} cy={y(v)} r="2.4" fill={DARK} />)}
      </svg>
      <div className="chart-x-labels">{labels.map((l, i) => <span key={i}>{l}</span>)}</div>
    </div>
  )
}

export function PlatformDashboard({ token, organizations, onOpenIntel, onOpenAudit }: {
  token: string
  organizations: OrganizationSummary[]
  /** Open Customer Intelligence (optionally focused on one organization/company view). */
  onOpenIntel: (opts?: { view?: "orgs" | "companies"; org?: string }) => void
  /** Open the Platform Activity Audit, optionally pre-filtered to one company. */
  onOpenAudit: (companyId?: string | null) => void
}) {
  const [overview, setOverview] = useState<Overview | null>(null)
  const [recent, setRecent] = useState<RecentActivity[]>([])
  const [quiet, setQuiet] = useState<GoingQuietRow[]>([])
  const [newCustomers, setNewCustomers] = useState<NewCustomerRow[]>([])
  const [adoption, setAdoption] = useState<ModuleAdoptionRow[]>([])
  const [attention, setAttention] = useState<AttentionItem[]>([])
  const [trendPoints, setTrendPoints] = useState<TimePoint[]>([])
  const [trendDays, setTrendDays] = useState<7 | 30 | 90>(30)
  const [trendFamily, setTrendFamily] = useState<string>("")
  const [err, setErr] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let gone = false
    setLoading(true)
    Promise.all([
      fetchOverview(token, 30),
      fetchRecent(token, 10),
      fetchGoingQuiet(token),
      fetchNewCustomers(token, 31),
      fetchModuleAdoption(token, 30),
      fetchAttentionQueue(token, undefined, true),
    ])
      .then(([ov, rec, gq, nc, ad, at]) => {
        if (gone) return
        setOverview(ov); setRecent(rec); setQuiet(gq); setNewCustomers(nc); setAdoption(ad)
        setAttention(at as AttentionItem[]); setErr(null)
      })
      .catch((e) => { if (!gone) setErr(e instanceof Error ? e.message : "Failed to load dashboard") })
      .finally(() => { if (!gone) setLoading(false) })
    return () => { gone = true }
  }, [token])

  useEffect(() => {
    let gone = false
    fetchTimeSeries(token, trendDays, trendFamily || null)
      .then((p) => { if (!gone) setTrendPoints(p) })
      .catch(() => { if (!gone) setTrendPoints([]) })
    return () => { gone = true }
  }, [token, trendDays, trendFamily])

  // Per-family breakdown from the (already loaded) organization directory.
  const families = useMemo(() => {
    const companies = organizations.flatMap((o) => o.companies)
    const monthStart = new Date(); monthStart.setDate(1); monthStart.setHours(0, 0, 0, 0)
    return FAMILIES.map((fam) => {
      const of = companies.filter((c) => c.companyFamily === fam)
      const active7 = of.filter((c) => c.activityStatus === "ActiveToday" || c.activityStatus === "Active7Days").length
      const active30 = active7 + of.filter((c) => c.activityStatus === "Active30Days").length
      const newMonth = of.filter((c) => c.createdAtUtc && new Date(c.createdAtUtc) >= monthStart).length
      const templates = fam === "Generic"
        ? [...of.reduce((m, c) => {
            const t = c.businessTemplateCode || "Unspecified"
            m.set(t, (m.get(t) || 0) + 1)
            return m
          }, new Map<string, number>()).entries()].sort((a, b) => b[1] - a[1])
        : []
      return { fam, total: of.length, active7, active30, newMonth, templates }
    })
  }, [organizations])

  const healthCounts = useMemo(() => {
    const counts = { Healthy: 0, "Needs Attention": 0, "At Risk": 0, Inactive: 0, New: 0 }
    for (const o of organizations) {
      const h = (o.health || "") as keyof typeof counts
      if (h in counts) counts[h]++
    }
    return counts
  }, [organizations])

  const adoptionMatrix = useMemo(() => {
    const cats = [...new Set(adoption.map((a) => a.category))].sort()
    const map = new Map(adoption.map((a) => [`${a.category}|${a.companyFamily}`, a]))
    return { cats, map }
  }, [adoption])

  if (loading && !overview) return <div className="card"><p className="subtle-help">Loading platform overview…</p></div>

  return (
    <>
      {err && <div className="error">{err}</div>}

      {overview && (
        <>
          <div className="kpi-group-title">Customers</div>
          <div className="kpi-row">
            <KpiTile label="Organizations" value={String(overview.totalOrganizations)} icon={ic("M3 21h18M5 21V7l7-4 7 4v14M9 9h1M9 13h1M14 9h1M14 13h1")} />
            <KpiTile label="Companies" value={String(overview.totalCompanies)} icon={ic("M3 21V8l9-5 9 5v13M9 21v-6h6v6")} />
            <KpiTile label="New orgs this month" value={String(overview.newOrganizationsThisMonth)} tone="teal" note="first company created" icon={ic("M12 5v14M5 12h14")} />
            <KpiTile label="Trial" value={String(overview.trialOrganizations)} tone="amber" note="organizations" icon={ic("M12 8v4l3 3M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0")} />
            <KpiTile label="Paying" value={String(overview.payingOrganizations)} tone="green" note="active subscriptions" icon={ic("M20 6 9 17l-5-5")} />
            <KpiTile label="Past due" value={String(overview.pastDueOrganizations)} tone={overview.pastDueOrganizations > 0 ? "red" : "slate"} note={overview.pastDueOrganizations > 0 ? "needs follow-up" : "all clear"} icon={ic("M12 9v4M12 17h.01M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z")} />
          </div>

          <div className="kpi-group-title">Customer health</div>
          <div className="kpi-row">
            <KpiTile label="Healthy" value={String(healthCounts.Healthy)} tone="green" note="organizations" icon={ic("M20 6 9 17l-5-5")} />
            <KpiTile label="Needs attention" value={String(healthCounts["Needs Attention"])} tone="amber" note="organizations" icon={ic("M12 9v4M12 17h.01M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18z")} />
            <KpiTile label="At risk" value={String(healthCounts["At Risk"])} tone={healthCounts["At Risk"] > 0 ? "red" : "slate"} note="organizations" icon={ic("M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0zM12 9v4M12 17h.01")} />
            <KpiTile label="Inactive" value={String(healthCounts.Inactive)} tone={healthCounts.Inactive > 0 ? "red" : "slate"} note="organizations" icon={ic("M18.4 5.6a9 9 0 1 0 .1 12.7M12 8v4l2 2")} />
            <KpiTile label="New" value={String(healthCounts.New)} tone="teal" note="too early to judge" icon={ic("M12 5v14M5 12h14")} />
            <KpiTile label="Open attention items" value={String(attention.length)} tone={attention.some((a) => a.severity === "High") ? "red" : "slate"} note={attention.some((a) => a.severity === "High") ? "high severity present" : "queue"} icon={ic("M13 2 3 14h7l-1 8 10-12h-7l1-8z")} />
          </div>

          <div className="kpi-group-title">Usage (meaningful activity)</div>
          <div className="kpi-row">
            <KpiTile label="Active today" value={String(overview.companiesActiveToday)} tone="green" note="companies" icon={ic("M13 2 3 14h7l-1 8 10-12h-7l1-8z")} />
            <KpiTile label="Active 7 days" value={String(overview.companiesActive7d)} tone="teal" note="companies" icon={ic("M8 2v4M16 2v4M3 10h18M5 4h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z")} />
            <KpiTile label="Active 30 days" value={String(overview.companiesActive30d)} note="companies" icon={ic("M3 3v18h18M7 15v3M12 10v8M17 6v12")} />
            <KpiTile label="Inactive 30+" value={String(overview.companiesInactive30Plus)} tone={overview.companiesInactive30Plus > 0 ? "red" : "slate"} note="incl. never active" icon={ic("M18.4 5.6a9 9 0 1 0 .1 12.7M12 8v4l2 2")} />
            <KpiTile label="Active users 7d" value={String(overview.activeUsers7d)} tone="teal" icon={ic("M9 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM2 21c0-4 3-6 7-6s7 2 7 6")} />
            <KpiTile label="Active users 30d" value={String(overview.activeUsers30d)} icon={ic("M9 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM2 21c0-4 3-6 7-6s7 2 7 6M17 11a4 4 0 1 0-2-7.5M22 21c0-3-1.5-5-4-5.6")} />
          </div>
        </>
      )}

      <div className="report-grid">
        <div className="card report-wide">
          <div className="card-toolbar">
            <h3 className="card-toolbar-title">Platform meaningful activity</h3>
            <div className="trend-controls">
              <select value={trendFamily} onChange={(e) => setTrendFamily(e.target.value)} aria-label="Vertical">
                <option value="">All verticals</option>
                {FAMILIES.map((f) => <option key={f} value={f}>{f}</option>)}
              </select>
              {([7, 30, 90] as const).map((d) => (
                <button key={d} type="button" className={`seg-btn${trendDays === d ? " active" : ""}`} onClick={() => setTrendDays(d)}>{d}d</button>
              ))}
            </div>
          </div>
          <ActivityTrendChart points={trendPoints} days={trendDays} />
        </div>
        <div className="card">
          <div className="card-toolbar">
            <h3 className="card-toolbar-title">Recently active</h3>
            <button type="button" className="link-btn" onClick={() => onOpenIntel()}>Directory</button>
          </div>
          {recent.length === 0 ? (
            <p className="subtle-help">No meaningful activity recorded yet today — this fills in as customers work.</p>
          ) : (
            <div className="recent-list">
              {recent.map((r) => (
                <button type="button" key={r.id} className="recent-row" onClick={() => onOpenAudit(r.companyId)}>
                  <div>
                    <div className="recent-name">{r.companyName || r.organizationId || "Organization-level"}</div>
                    <div className="recent-sub">{describeActivity(r.activityType)}{r.companyFamily ? ` · ${r.companyFamily}` : ""}</div>
                  </div>
                  <span className="recent-ago">{timeAgo(r.occurredAtUtc)}</span>
                </button>
              ))}
            </div>
          )}
        </div>
      </div>

      <div className="card">
        <div className="card-toolbar"><h3 className="card-toolbar-title">Companies by business type</h3></div>
        <div className="family-grid">
          {families.map((f) => (
            <div key={f.fam} className="family-card">
              <div className="family-head">
                <span className="family-name">{f.fam}</span>
                <span className="family-total">{f.total}</span>
              </div>
              {f.total === 0 ? (
                <p className="subtle-help">No {f.fam} companies yet.</p>
              ) : (
                <>
                  <div className="family-stats">
                    <span>Active 7d <strong>{f.active7}</strong></span>
                    <span>Active 30d <strong>{f.active30}</strong></span>
                    <span>New this month <strong>{f.newMonth}</strong></span>
                  </div>
                  {f.templates.length > 0 && (
                    <div className="family-templates">
                      {f.templates.map(([t, n]) => <span key={t} className="badge">{t} · {n}</span>)}
                    </div>
                  )}
                </>
              )}
            </div>
          ))}
        </div>
      </div>

      <div className="report-grid">
        <div className="card report-wide">
          <div className="card-toolbar"><h3 className="card-toolbar-title">Module adoption — meaningful activity (30d)</h3></div>
          {adoption.length === 0 ? (
            <p className="subtle-help">No module activity in the last 30 days.</p>
          ) : (
            <div style={{ overflowX: "auto" }}>
              <table className="matrix">
                <thead>
                  <tr><th>Module</th>{FAMILIES.map((f) => <th key={f}>{f}</th>)}<th>Total</th></tr>
                </thead>
                <tbody>
                  {adoptionMatrix.cats.map((cat) => {
                    const rowTotal = FAMILIES.reduce((a, f) => a + (adoptionMatrix.map.get(`${cat}|${f}`)?.meaningfulCount || 0), 0)
                    return (
                      <tr key={cat}>
                        <td style={{ fontWeight: 600 }}>{cat}</td>
                        {FAMILIES.map((f) => {
                          const cell = adoptionMatrix.map.get(`${cat}|${f}`)
                          return <td key={f} className="mono">{cell ? cell.meaningfulCount.toLocaleString() : "—"}</td>
                        })}
                        <td className="mono" style={{ fontWeight: 700 }}>{rowTotal.toLocaleString()}</td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>
        <div className="card">
          <div className="card-toolbar"><h3 className="card-toolbar-title">Going quiet</h3></div>
          <p className="subtle-help">Previously active, nearly silent in the last 14 days. Not churn — worth a check-in.</p>
          {quiet.length === 0 ? (
            <p className="subtle-help">Nobody is going quiet right now.</p>
          ) : (
            <div className="recent-list">
              {quiet.slice(0, 8).map((q) => (
                <button type="button" key={q.companyId} className="recent-row" onClick={() => onOpenAudit(q.companyId)}>
                  <div>
                    <div className="recent-name">{q.companyName}</div>
                    <div className="recent-sub">{q.companyFamily || "—"} · was {q.baselineMeaningfulCount}, now {q.recentMeaningfulCount}</div>
                  </div>
                  <span className="recent-ago">{timeAgo(q.lastMeaningfulActivityAtUtc)}</span>
                </button>
              ))}
            </div>
          )}
        </div>
      </div>

      <div className="report-grid">
        <div className="card report-wide">
          <div className="card-toolbar"><h3 className="card-toolbar-title">Top attention items</h3></div>
          {attention.length === 0 ? (
            <p className="subtle-help">Nothing needs attention right now - all clear.</p>
          ) : (
            <table>
              <thead><tr><th>Customer</th><th>Company</th><th>Why</th><th>Severity</th><th>Detected</th></tr></thead>
              <tbody>
                {attention.slice(0, 6).map((a) => (
                  <tr key={a.id}>
                    <td style={{ fontWeight: 600 }}>{a.organizationName || a.organizationId}</td>
                    <td>{a.companyName || "Organization"}</td>
                    <td style={{ maxWidth: 340 }} title={a.reason}>{a.title}</td>
                    <td><span className={`badge${a.severity === "High" ? " badge-no" : ""}`}>{a.severity}</span></td>
                    <td>{timeAgo(a.lastDetectedAtUtc)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
        <div className="card">
          <div className="card-toolbar"><h3 className="card-toolbar-title">Health split</h3></div>
          <Donut
            segments={[
              { value: healthCounts.Healthy, color: "#059669", label: "Healthy" },
              { value: healthCounts["Needs Attention"], color: "#d97706", label: "Needs attention" },
              { value: healthCounts["At Risk"], color: "#dc2626", label: "At risk" },
              { value: healthCounts.Inactive, color: "#64748b", label: "Inactive" },
              { value: healthCounts.New, color: "#0ea5e9", label: "New" },
            ].filter((s) => s.value > 0)}
            center={String(organizations.length)} sub="orgs"
          />
        </div>
      </div>

      <div className="card">
        <div className="card-toolbar">
          <h3 className="card-toolbar-title">New organizations (last 31 days)</h3>
          <button type="button" className="link-btn" onClick={() => onOpenIntel({ view: "orgs" })}>Customer Intelligence</button>
        </div>
        {newCustomers.length === 0 ? (
          <p className="subtle-help">No new organizations this month yet.</p>
        ) : (
          <div style={{ overflowX: "auto" }}>
            <table>
              <thead>
                <tr><th>Organization</th><th>Registered</th><th>First company</th><th>Business type</th><th>Setup</th><th>First meaningful activity</th><th>Trial</th></tr>
              </thead>
              <tbody>
                {newCustomers.map((n) => (
                  <tr key={n.organizationId} className="row-click" onClick={() => onOpenIntel({ org: n.organizationId })}>
                    <td style={{ fontWeight: 600 }}>{n.organizationName || n.organizationId}</td>
                    <td>{n.registeredAtUtc ? new Date(n.registeredAtUtc).toLocaleDateString() : "—"}</td>
                    <td>{n.firstCompanyName || "—"}</td>
                    <td>{n.firstCompanyFamily || "—"}</td>
                    <td className="mono">{n.setupPercent}%</td>
                    <td>{n.firstMeaningfulActivityAtUtc ? timeAgo(n.firstMeaningfulActivityAtUtc) : <span className="badge badge-no">none yet</span>}</td>
                    <td>{n.subscriptionStatus === "Trial"
                      ? <span className="badge">Trial{n.trialEndUtc ? ` → ${new Date(n.trialEndUtc).toLocaleDateString()}` : ""}</span>
                      : n.subscriptionStatus}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </>
  )
}

export { TrendBadge }
