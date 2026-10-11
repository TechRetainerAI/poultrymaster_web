// PROMPT 4: Analytics section — Onboarding & Activation, Feature Adoption,
// Retention cohorts. All data from api/PlatformAnalytics (Prompt 1 foundation;
// no raw audit scans).

import { useEffect, useMemo, useState } from "react"
import {
  FAMILIES,
  fetchFeatureAdoption,
  fetchFeatureUsage,
  fetchFunnel,
  fetchMilestones,
  fetchOnboarding,
  fetchRetention,
  timeAgo,
  type CompanySummary,
  type FeatureAdoptionRow,
  type FeatureUsageRow,
  type FunnelStage,
  type Milestone,
  type RetentionCohort,
} from "./platform-activity-api"

type Tab = "onboarding" | "adoption" | "retention"

export function AnalyticsPage({ token }: { token: string }) {
  const [tab, setTab] = useState<Tab>("onboarding")
  return (
    <>
      <div className="card" style={{ paddingBottom: 10 }}>
        <div className="trend-controls">
          <button type="button" className={`seg-btn${tab === "onboarding" ? " active" : ""}`} onClick={() => setTab("onboarding")}>Onboarding &amp; Activation</button>
          <button type="button" className={`seg-btn${tab === "adoption" ? " active" : ""}`} onClick={() => setTab("adoption")}>Feature Adoption</button>
          <button type="button" className={`seg-btn${tab === "retention" ? " active" : ""}`} onClick={() => setTab("retention")}>Retention</button>
        </div>
      </div>
      {tab === "onboarding" && <OnboardingTab token={token} />}
      {tab === "adoption" && <AdoptionTab token={token} />}
      {tab === "retention" && <RetentionTab token={token} />}
    </>
  )
}

// ---------------------------------------------------------------- onboarding
function OnboardingTab({ token }: { token: string }) {
  const [rows, setRows] = useState<CompanySummary[]>([])
  const [funnel, setFunnel] = useState<FunnelStage[]>([])
  const [family, setFamily] = useState("")
  const [month, setMonth] = useState("")
  const [err, setErr] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [openCompany, setOpenCompany] = useState<string | null>(null)
  const [milestones, setMilestones] = useState<Milestone[]>([])

  useEffect(() => {
    let gone = false
    setLoading(true)
    Promise.all([
      fetchOnboarding(token, family || undefined),
      fetchFunnel(token, month || undefined, family || undefined),
    ])
      .then(([r, f]) => { if (!gone) { setRows(r); setFunnel(f); setErr(null) } })
      .catch((e) => { if (!gone) setErr(e instanceof Error ? e.message : "Failed to load onboarding analytics") })
      .finally(() => { if (!gone) setLoading(false) })
    return () => { gone = true }
  }, [token, family, month])

  useEffect(() => {
    if (!openCompany) { setMilestones([]); return }
    let gone = false
    fetchMilestones(token, openCompany)
      .then((m) => { if (!gone) setMilestones(m) })
      .catch(() => { if (!gone) setMilestones([]) })
    return () => { gone = true }
  }, [token, openCompany])

  const maxCount = Math.max(1, ...funnel.map((s) => s.count))
  const months = useMemo(() => {
    const out: string[] = []
    const d = new Date()
    for (let i = 0; i < 12; i++) {
      out.push(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`)
      d.setMonth(d.getMonth() - 1)
    }
    return out
  }, [])

  if (loading && rows.length === 0 && funnel.length === 0)
    return <div className="card"><p className="subtle-help">Loading onboarding analytics…</p></div>

  return (
    <>
      {err && <div className="error">{err}</div>}
      <div className="card">
        <div className="card-toolbar">
          <h3 className="card-toolbar-title">Activation funnel</h3>
          <div className="trend-controls">
            <select value={month} onChange={(e) => setMonth(e.target.value)} aria-label="Signup month">
              <option value="">All signup months</option>
              {months.map((m) => <option key={m} value={m}>{m}</option>)}
            </select>
            <select value={family} onChange={(e) => setFamily(e.target.value)} aria-label="Business type">
              <option value="">All types</option>
              {FAMILIES.map((f) => <option key={f} value={f}>{f}</option>)}
            </select>
          </div>
        </div>
        {funnel.every((s) => s.count === 0) ? (
          <p className="subtle-help">No organizations match this filter yet.</p>
        ) : (
          <div className="funnel">
            {funnel.map((s) => (
              <div key={s.key} className="funnel-row">
                <span className="funnel-label">{s.label}</span>
                <div className="funnel-track">
                  <div className="funnel-fill" style={{ width: `${(s.count / maxCount) * 100}%` }} />
                </div>
                <span className="funnel-count mono">{s.count}</span>
                <span className="funnel-pct">
                  {s.percentOfPrevious === null ? "—" : `${s.percentOfPrevious}% of prev`} · {s.percentOfTop}% of top
                </span>
              </div>
            ))}
          </div>
        )}
      </div>

      <div className="card">
        <div className="card-toolbar"><h3 className="card-toolbar-title">Setup completion by company</h3></div>
        <p className="subtle-help">
          Weighted, company-type-aware milestones (Generic templates may override). Click a row for the full checklist.
          Activated = essential setup complete + first meaningful transaction.
        </p>
        <div style={{ overflowX: "auto" }}>
          <table>
            <thead>
              <tr><th>Company</th><th>Type</th><th>Template</th><th>Setup %</th><th>Missing</th><th>Activated</th><th>Time to activation</th><th>First meaningful</th></tr>
            </thead>
            <tbody>
              {rows.length === 0 ? (
                <tr><td colSpan={8} style={{ color: "#64748b" }}>No companies match this filter.</td></tr>
              ) : rows.map((c) => (
                <>
                  <tr key={c.companyId} className="row-click" onClick={() => setOpenCompany(openCompany === c.companyId ? null : c.companyId)}>
                    <td style={{ fontWeight: 600 }}>{c.companyName || c.companyId}</td>
                    <td>{c.companyFamily || "—"}</td>
                    <td>{c.businessTemplateCode || "—"}</td>
                    <td>
                      <div className="setup-cell">
                        <div className="bar-track"><div className="bar-fill" style={{ width: `${c.setupPercent}%`, background: c.setupPercent >= 80 ? "#059669" : c.setupPercent >= 40 ? "#0f766e" : "#d97706" }} /></div>
                        <span className="mono">{c.setupPercent}%</span>
                      </div>
                    </td>
                    <td style={{ maxWidth: 260 }} title={c.missingMilestones.join(", ")}>
                      {c.missingMilestones.length === 0 ? <span className="badge badge-yes">Complete</span>
                        : <span className="subtle-inline">{c.missingMilestones.slice(0, 3).join(", ")}{c.missingMilestones.length > 3 ? ` +${c.missingMilestones.length - 3}` : ""}</span>}
                    </td>
                    <td>{c.activated ? <span className="badge badge-yes">Yes</span> : <span className="badge">Not yet</span>}</td>
                    <td className="mono">{c.timeToActivationDays != null ? `${c.timeToActivationDays} d` : "—"}</td>
                    <td>{timeAgo(c.firstMeaningfulActivityAtUtc)}</td>
                  </tr>
                  {openCompany === c.companyId && (
                    <tr key={`${c.companyId}-m`}>
                      <td colSpan={8} style={{ background: "#f8fafc" }}>
                        {milestones.length === 0 ? <span className="subtle-inline">Loading checklist…</span> : (
                          <div className="milestone-list">
                            {milestones.map((m) => (
                              <span key={m.code} className={`badge${m.complete ? " badge-yes" : ""}`}>
                                {m.complete ? "✓ " : "○ "}{m.title}{m.required ? " *" : ""}
                              </span>
                            ))}
                            <span className="subtle-inline">* = required for activation</span>
                          </div>
                        )}
                      </td>
                    </tr>
                  )}
                </>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </>
  )
}

// ---------------------------------------------------------------- adoption
function AdoptionTab({ token }: { token: string }) {
  const [rows, setRows] = useState<FeatureAdoptionRow[]>([])
  const [usage, setUsage] = useState<FeatureUsageRow[]>([])
  const [days, setDays] = useState(90)
  const [err, setErr] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let gone = false
    setLoading(true)
    Promise.all([fetchFeatureAdoption(token, days), fetchFeatureUsage(token)])
      .then(([a, u]) => { if (!gone) { setRows(a); setUsage(u); setErr(null) } })
      .catch((e) => { if (!gone) setErr(e instanceof Error ? e.message : "Failed to load feature adoption") })
      .finally(() => { if (!gone) setLoading(false) })
    return () => { gone = true }
  }, [token, days])

  const features = useMemo(() => [...new Set(rows.map((r) => r.feature))], [rows])
  const cell = useMemo(() => new Map(rows.map((r) => [`${r.feature}|${r.companyFamily}`, r])), [rows])

  const depth = useMemo(() => {
    const byFeature = new Map<string, { companies: number; usage: number; days: number }>()
    for (const u of usage) {
      const v = byFeature.get(u.feature) || { companies: 0, usage: 0, days: 0 }
      v.companies++; v.usage += u.usageCount; v.days += u.activeDaysUsingFeature
      byFeature.set(u.feature, v)
    }
    return [...byFeature.entries()].sort((a, b) => b[1].usage - a[1].usage)
  }, [usage])

  if (loading && rows.length === 0) return <div className="card"><p className="subtle-help">Loading feature adoption…</p></div>

  return (
    <>
      {err && <div className="error">{err}</div>}
      <div className="card">
        <div className="card-toolbar">
          <h3 className="card-toolbar-title">Feature adoption matrix — % of applicable companies</h3>
          <div className="trend-controls">
            {[30, 90, 365].map((d) => (
              <button key={d} type="button" className={`seg-btn${days === d ? " active" : ""}`} onClick={() => setDays(d)}>{d}d</button>
            ))}
          </div>
        </div>
        <p className="subtle-help">Derived from meaningful transactions (never page views). “—” means the feature does not apply to that vertical.</p>
        {rows.length === 0 ? (
          <p className="subtle-help">No meaningful activity in this window yet.</p>
        ) : (
          <div style={{ overflowX: "auto" }}>
            <table className="matrix">
              <thead><tr><th>Feature</th>{FAMILIES.map((f) => <th key={f}>{f}</th>)}</tr></thead>
              <tbody>
                {features.map((f) => (
                  <tr key={f}>
                    <td style={{ fontWeight: 600 }}>{f}</td>
                    {FAMILIES.map((fam) => {
                      const r = cell.get(`${f}|${fam}`)
                      if (!r) return <td key={fam} className="mono subtle-inline">—</td>
                      const tone = r.percent >= 60 ? "#059669" : r.percent >= 25 ? "#0f766e" : "#d97706"
                      return (
                        <td key={fam} className="mono" title={`${r.companiesUsed} of ${r.companiesTotal} companies`}>
                          <span style={{ color: tone, fontWeight: 700 }}>{r.percent}%</span>
                          <span className="subtle-inline"> {r.companiesUsed}/{r.companiesTotal}</span>
                        </td>
                      )
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div className="card">
        <div className="card-toolbar"><h3 className="card-toolbar-title">Adoption depth (all time)</h3></div>
        {depth.length === 0 ? (
          <p className="subtle-help">No feature usage recorded yet.</p>
        ) : (
          <div style={{ overflowX: "auto" }}>
            <table>
              <thead><tr><th>Feature</th><th>Companies using</th><th>Total uses</th><th>Active feature-days</th></tr></thead>
              <tbody>
                {depth.map(([f, v]) => (
                  <tr key={f}>
                    <td style={{ fontWeight: 600 }}>{f}</td>
                    <td className="mono">{v.companies}</td>
                    <td className="mono">{v.usage.toLocaleString()}</td>
                    <td className="mono">{v.days.toLocaleString()}</td>
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

// ---------------------------------------------------------------- retention
function RetentionTab({ token }: { token: string }) {
  const [rows, setRows] = useState<RetentionCohort[]>([])
  const [scope, setScope] = useState<"org" | "company">("org")
  const [cohortBy, setCohortBy] = useState("signupMonth")
  const [family, setFamily] = useState("")
  const [err, setErr] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let gone = false
    setLoading(true)
    fetchRetention(token, scope, cohortBy, family || undefined)
      .then((r) => { if (!gone) { setRows(r); setErr(null) } })
      .catch((e) => { if (!gone) setErr(e instanceof Error ? e.message : "Failed to load retention") })
      .finally(() => { if (!gone) setLoading(false) })
    return () => { gone = true }
  }, [token, scope, cohortBy, family])

  const windows = ["D1", "D7", "D30", "D60", "D90"]

  return (
    <div className="card">
      <div className="card-toolbar">
        <h3 className="card-toolbar-title">Retention cohorts</h3>
        <div className="trend-controls">
          <select value={scope} onChange={(e) => setScope(e.target.value as "org" | "company")}>
            <option value="org">Organizations</option>
            <option value="company">Companies</option>
          </select>
          <select value={cohortBy} onChange={(e) => setCohortBy(e.target.value)}>
            <option value="signupMonth">By signup month</option>
            <option value="signupWeek">By signup week</option>
            <option value="activationMonth">By activation month</option>
          </select>
          <select value={family} onChange={(e) => setFamily(e.target.value)}>
            <option value="">All types</option>
            {FAMILIES.map((f) => <option key={f} value={f}>{f}</option>)}
          </select>
        </div>
      </div>
      <p className="subtle-help">
        Retained at Day N = meaningful activity within the window D1 [1–6], D7 [7–29], D30 [30–59], D60 [60–89], D90 [90–119] days
        after {cohortBy === "activationMonth" ? "first meaningful activity" : "signup"}. Product inactivity is NOT subscription churn —
        billing status lives in Customer Intelligence. “—” = window not reached yet.
      </p>
      {err && <div className="error">{err}</div>}
      {loading && rows.length === 0 ? (
        <p className="subtle-help">Loading cohorts…</p>
      ) : rows.length === 0 ? (
        <p className="subtle-help">No cohorts yet for this filter.</p>
      ) : (
        <div style={{ overflowX: "auto" }}>
          <table className="matrix">
            <thead><tr><th>Cohort</th><th>{scope === "org" ? "Orgs" : "Companies"}</th>{windows.map((w) => <th key={w}>{w}</th>)}</tr></thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.cohort}>
                  <td style={{ fontWeight: 600 }}>{r.cohort}</td>
                  <td className="mono">{r.subjects}</td>
                  {windows.map((w, i) => {
                    const pct = r.percent[i]
                    if (pct === null || pct === undefined) return <td key={w} className="mono subtle-inline">—</td>
                    const bg = pct >= 60 ? "#d1fae5" : pct >= 30 ? "#e0f2f1" : pct > 0 ? "#fef3c7" : "#fee2e2"
                    return <td key={w} className="mono" style={{ background: bg }} title={`${r.retained[i]} retained`}>{pct}%</td>
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
