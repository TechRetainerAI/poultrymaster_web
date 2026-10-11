// PROMPT 7: Platform Operations console — management briefs, customer-impact
// error intelligence, security review queue, feature flags (with audit),
// releases and system health. Prioritizes actionable exceptions over cards.

import { useCallback, useEffect, useState } from "react"
import {
  createFlag,
  exportUrl,
  fetchBrief,
  fetchErrorDashboard,
  fetchFlagAudit,
  fetchFlags,
  fetchReleases,
  fetchSecurityEvents,
  fetchSystemHealth,
  generateBrief,
  removeFlagRule,
  setFlagEnabled,
  setFlagRule,
  timeAgo,
  type ErrorDashboard,
  type FeatureFlag,
  type FlagAudit,
  type ManagementBrief,
  type Release,
  type SecurityEvent,
  type SystemHealth,
} from "./platform-activity-api"
import { KpiTile } from "./reports"

type Tab = "briefs" | "errors" | "security" | "flags" | "releases"
const SCOPES = ["Global", "Market", "CompanyFamily", "BusinessTemplate", "Organization", "Company", "User"]

function ic(d: string) {
  return <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d={d} /></svg>
}

export function OperationsPage({ token, onNavigate }: {
  token: string
  onNavigate: (page: string) => void
}) {
  const [tab, setTab] = useState<Tab>("briefs")
  return (
    <>
      <div className="card" style={{ paddingBottom: 10 }}>
        <div className="trend-controls">
          {([["briefs", "Management Briefs"], ["errors", "Errors"], ["security", "Security"], ["flags", "Feature Flags"], ["releases", "Releases & Health"]] as [Tab, string][]).map(([k, label]) => (
            <button key={k} type="button" className={`seg-btn${tab === k ? " active" : ""}`} onClick={() => setTab(k)}>{label}</button>
          ))}
          <a className="seg-btn" href="#" onClick={async (e) => {
            e.preventDefault()
            const res = await fetch(exportUrl("organizations"), { headers: { Authorization: `Bearer ${token}` } })
            const blob = await res.blob()
            const url = URL.createObjectURL(blob)
            const a = document.createElement("a"); a.href = url; a.download = "visibilitycore-organizations.csv"; a.click()
            URL.revokeObjectURL(url)
          }}>Export CSV (audited)</a>
        </div>
      </div>
      {tab === "briefs" && <BriefsTab token={token} onNavigate={onNavigate} />}
      {tab === "errors" && <ErrorsTab token={token} />}
      {tab === "security" && <SecurityTab token={token} />}
      {tab === "flags" && <FlagsTab token={token} />}
      {tab === "releases" && <ReleasesTab token={token} />}
    </>
  )
}

// ---------------------------------------------------------------- briefs
function BriefsTab({ token, onNavigate }: { token: string; onNavigate: (page: string) => void }) {
  const [type, setType] = useState<"Daily" | "Weekly">("Daily")
  const [brief, setBrief] = useState<ManagementBrief | null>(null)
  const [err, setErr] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const load = useCallback(async (t: "Daily" | "Weekly") => {
    setErr(null)
    try { setBrief(await fetchBrief(token, t)) }
    catch { setBrief(null) }
  }, [token])
  useEffect(() => { void load(type) }, [load, type])

  async function regen() {
    setBusy(true)
    setErr(null)
    try { setBrief(await generateBrief(token, type)) }
    catch (e) { setErr(e instanceof Error ? e.message : "Failed to generate brief") }
    finally { setBusy(false) }
  }

  const linkTarget: Record<string, string> = {
    intel: "intel", intelOrg: "intel", success: "success", revenue: "revenue", analytics: "analytics", audit: "audit",
  }

  return (
    <div className="card">
      <div className="card-toolbar">
        <h3 className="card-toolbar-title">{type} brief</h3>
        <div className="trend-controls">
          <button type="button" className={`seg-btn${type === "Daily" ? " active" : ""}`} onClick={() => setType("Daily")}>Daily</button>
          <button type="button" className={`seg-btn${type === "Weekly" ? " active" : ""}`} onClick={() => setType("Weekly")}>Weekly</button>
          <button type="button" className="seg-btn" onClick={() => void regen()} disabled={busy}>
            {busy ? "Generating…" : "Generate now"}
          </button>
        </div>
      </div>
      <p className="subtle-help">
        Deterministic metrics from the trusted analytics services — stored with the brief, nothing invented.
        No AI summarizer exists on this platform, so the data brief IS the brief (it stays fully useful without one).
      </p>
      {err && <div className="error">{err}</div>}
      {!brief ? (
        <p className="subtle-help">No {type.toLowerCase()} brief generated yet — click “Generate now”.</p>
      ) : (
        <>
          <p className="subtle-help">
            {brief.briefDate} · generated {timeAgo(brief.generatedAtUtc)} by {brief.generatedBy}
          </p>
          <div className="family-grid">
            {brief.sections.map((s) => (
              <div key={s.title} className="family-card">
                <div className="family-head"><span className="family-name">{s.title}</span></div>
                {s.entries.map((e2) => (
                  <div key={e2.label} className="brief-entry">
                    <span className="brief-label">{e2.label}</span>
                    {e2.linkKind !== "none" && linkTarget[e2.linkKind] ? (
                      <button type="button" className="link-btn" onClick={() => onNavigate(linkTarget[e2.linkKind])}>
                        {e2.value}
                      </button>
                    ) : <strong>{e2.value}</strong>}
                  </div>
                ))}
              </div>
            ))}
          </div>
        </>
      )}
    </div>
  )
}

// ---------------------------------------------------------------- errors
function ErrorsTab({ token }: { token: string }) {
  const [hours, setHours] = useState(24)
  const [data, setData] = useState<ErrorDashboard | null>(null)
  const [err, setErr] = useState<string | null>(null)

  useEffect(() => {
    let gone = false
    fetchErrorDashboard(token, hours)
      .then((d) => { if (!gone) { setData(d); setErr(null) } })
      .catch((e) => { if (!gone) setErr(e instanceof Error ? e.message : "Failed to load errors") })
    return () => { gone = true }
  }, [token, hours])

  if (err) return <div className="error">{err}</div>
  if (!data) return <div className="card"><p className="subtle-help">Loading error intelligence…</p></div>

  return (
    <>
      <div className="kpi-row">
        <KpiTile label={`Errors ${hours}h`} value={String(data.totalErrors)} tone={data.totalErrors > 0 ? "amber" : "green"} icon={ic("M12 9v4M12 17h.01M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18z")} />
        <KpiTile label="Failed business ops" value={String(data.failedBusinessOperations)} tone={data.failedBusinessOperations > 0 ? "red" : "green"} note="critical operations only" icon={ic("M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z")} />
        <KpiTile label="Affected orgs" value={String(data.affectedOrganizations)} icon={ic("M3 21h18M5 21V7l7-4 7 4v14")} />
        <KpiTile label="Affected companies" value={String(data.affectedCompanies)} icon={ic("M3 21V8l9-5 9 5v13")} />
      </div>
      <div className="card">
        <div className="card-toolbar">
          <h3 className="card-toolbar-title">Top failing operations</h3>
          <div className="trend-controls">
            {[24, 72, 168].map((h) => (
              <button key={h} type="button" className={`seg-btn${hours === h ? " active" : ""}`} onClick={() => setHours(h)}>{h}h</button>
            ))}
          </div>
        </div>
        <p className="subtle-help">Derived from the audit trail’s failed requests; deep technical logs live in GCP Cloud Logging.</p>
        {data.topErrorTypes.length === 0 ? <p className="subtle-help">No errors in this window — all clear.</p> : (
          <table>
            <thead><tr><th>Operation</th><th>Module</th><th>Count</th><th>Companies</th><th>Critical?</th></tr></thead>
            <tbody>
              {data.topErrorTypes.map((t, i) => (
                <tr key={i}>
                  <td style={{ fontWeight: 600 }}>{t.operation}</td>
                  <td>{t.module}</td>
                  <td className="mono">{t.count}</td>
                  <td className="mono">{t.affectedCompanies}</td>
                  <td>{t.isCriticalOperation ? <span className="badge badge-no">business-critical</span> : <span className="subtle-inline">—</span>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
        {data.byRelease.length > 0 && (
          <>
            <div className="card-toolbar" style={{ marginTop: 12 }}><h3 className="card-toolbar-title">Failures by release (72h after each deploy)</h3></div>
            <div className="family-templates">
              {data.byRelease.map((rel) => (
                <span key={rel.key} className="badge" title={`${rel.meaningfulCount} failed of ${rel.totalCount} ops`}>
                  {rel.key.length > 30 ? `…${rel.key.slice(-26)}` : rel.key}: {rel.totalCount > 0 ? `${((Number(rel.meaningfulCount) / Number(rel.totalCount)) * 100).toFixed(1)}%` : "n/a"}
                </span>
              ))}
            </div>
          </>
        )}
      </div>
    </>
  )
}

// ---------------------------------------------------------------- security
function SecurityTab({ token }: { token: string }) {
  const [events, setEvents] = useState<SecurityEvent[]>([])
  const [err, setErr] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let gone = false
    setLoading(true)
    fetchSecurityEvents(token, true)
      .then((e) => { if (!gone) { setEvents(e); setErr(null) } })
      .catch((e) => { if (!gone) setErr(e instanceof Error ? e.message : "Failed to load security events") })
      .finally(() => { if (!gone) setLoading(false) })
    return () => { gone = true }
  }, [token])

  return (
    <div className="card">
      <div className="card-toolbar"><h3 className="card-toolbar-title">Security review queue</h3></div>
      <p className="subtle-help">Deterministic detections flagged FOR REVIEW — never an automatic fraud claim. Severity: Info / Warning / Critical.</p>
      {err && <div className="error">{err}</div>}
      {loading && events.length === 0 ? <p className="subtle-help">Scanning…</p>
        : events.length === 0 ? <p className="subtle-help">No security events detected.</p> : (
        <table>
          <thead><tr><th>Severity</th><th>Event</th><th>Detail</th><th>Occurrences</th><th>Last seen</th></tr></thead>
          <tbody>
            {events.map((e) => (
              <tr key={e.id}>
                <td><span className={`badge${e.severity === "Critical" ? " badge-no" : e.severity === "Warning" ? " badge-warn" : ""}`}>{e.severity}</span></td>
                <td style={{ fontWeight: 600 }}>{e.title}</td>
                <td style={{ maxWidth: 420 }}>{e.detail}</td>
                <td className="mono">{e.occurrences}</td>
                <td>{timeAgo(e.lastSeenAtUtc)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  )
}

// ---------------------------------------------------------------- flags
function FlagsTab({ token }: { token: string }) {
  const [flags, setFlags] = useState<FeatureFlag[]>([])
  const [audit, setAudit] = useState<FlagAudit[]>([])
  const [err, setErr] = useState<string | null>(null)
  const [key, setKey] = useState("")
  const [name, setName] = useState("")
  const [busy, setBusy] = useState(false)

  const load = useCallback(async () => {
    try {
      setFlags(await fetchFlags(token))
      setAudit(await fetchFlagAudit(token))
      setErr(null)
    } catch (e) { setErr(e instanceof Error ? e.message : "Failed to load flags") }
  }, [token])
  useEffect(() => { void load() }, [load])

  async function act(fn: () => Promise<unknown>) {
    setBusy(true)
    setErr(null)
    try { await fn(); await load() }
    catch (e) { setErr(e instanceof Error ? e.message : "Flag action failed") }
    finally { setBusy(false) }
  }

  function addRule(flagKey: string) {
    const scope = window.prompt(`Scope (${SCOPES.join(" | ")}):`, "Organization")
    if (!scope) return
    const value = scope === "Global" ? "" : (window.prompt(`${scope} value (e.g. org id, farm id, GH, Poultry, School):`) ?? "")
    if (scope !== "Global" && !value.trim()) return
    const on = window.confirm("Enable for this scope? OK = on, Cancel = off")
    const reason = window.prompt("Reason (audited):") ?? undefined
    void act(() => setFlagRule(token, flagKey, { scopeType: scope, scopeValue: value.trim(), enabled: on, reason }))
  }

  return (
    <>
      <div className="card">
        <div className="card-toolbar"><h3 className="card-toolbar-title">Feature flags</h3></div>
        <p className="subtle-help">
          Rollout scopes: Global → Market → CompanyFamily → BusinessTemplate → Organization → Company → User (most specific wins).
          Product rollout ONLY — never used to bypass authorization, payment validation or financial integrity.
        </p>
        {err && <div className="error">{err}</div>}
        <form className="note-form" onSubmit={(e) => {
          e.preventDefault()
          if (!key.trim() || !name.trim()) return
          void act(() => createFlag(token, { flagKey: key.trim(), name: name.trim(), defaultOn: false }))
          setKey(""); setName("")
        }}>
          <div className="note-form-row">
            <input placeholder="flag-key (e.g. daily-closing-v2)" value={key} onChange={(e) => setKey(e.target.value)} />
            <input className="note-input" placeholder="Name" value={name} onChange={(e) => setName(e.target.value)} />
            <button type="submit" className="admin-btn-primary" disabled={busy || !key.trim() || !name.trim()}>Create flag</button>
          </div>
        </form>
        {flags.length === 0 ? <p className="subtle-help">No flags yet.</p> : flags.map((f) => (
          <div key={f.id} className="family-card" style={{ marginBottom: 10 }}>
            <div className="family-head">
              <span className="family-name">{f.name} <code className="mono subtle-inline">{f.flagKey}</code></span>
              <span>
                <button type="button" className={`seg-btn${f.enabled ? " active" : ""}`} disabled={busy}
                  onClick={() => {
                    const reason = window.prompt("Reason (audited):") ?? undefined
                    void act(() => setFlagEnabled(token, f.flagKey, !f.enabled, reason))
                  }}>
                  {f.enabled ? "Enabled" : "Disabled"}
                </button>
              </span>
            </div>
            <div className="family-templates">
              {f.rules.length === 0 ? <span className="subtle-inline">No scoped rules — default {f.defaultOn ? "ON" : "OFF"} when enabled.</span>
                : f.rules.map((rule, i) => (
                  <span key={i} className={`badge${rule.enabled ? " badge-yes" : " badge-no"}`}>
                    {rule.scopeType}{rule.scopeValue ? `=${rule.scopeValue}` : ""}: {rule.enabled ? "on" : "off"}
                    <button type="button" className="link-btn link-danger" style={{ marginLeft: 4 }} disabled={busy}
                      onClick={() => void act(() => removeFlagRule(token, f.flagKey, rule.scopeType, rule.scopeValue))}>×</button>
                  </span>
                ))}
              <button type="button" className="link-btn" disabled={busy} onClick={() => addRule(f.flagKey)}>+ rule</button>
            </div>
          </div>
        ))}
      </div>
      <div className="card">
        <div className="card-toolbar"><h3 className="card-toolbar-title">Flag audit trail</h3></div>
        {audit.length === 0 ? <p className="subtle-help">No flag changes recorded.</p> : (
          <table>
            <thead><tr><th>When</th><th>Flag</th><th>Action</th><th>Scope</th><th>New value</th><th>By</th><th>Reason</th></tr></thead>
            <tbody>
              {audit.map((a, i) => (
                <tr key={i}>
                  <td>{timeAgo(a.atUtc)}</td>
                  <td className="mono">{a.flagKey}</td>
                  <td>{a.action}</td>
                  <td>{a.scopeType ? `${a.scopeType}${a.scopeValue ? `=${a.scopeValue}` : ""}` : "—"}</td>
                  <td>{a.newValue ?? "—"}</td>
                  <td>{a.changedBy}</td>
                  <td>{a.reason ?? "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </>
  )
}

// ---------------------------------------------------------------- releases + health
function ReleasesTab({ token }: { token: string }) {
  const [releases, setReleases] = useState<Release[]>([])
  const [health, setHealth] = useState<SystemHealth | null>(null)
  const [err, setErr] = useState<string | null>(null)

  useEffect(() => {
    let gone = false
    Promise.all([fetchReleases(token), fetchSystemHealth(token)])
      .then(([r, h]) => { if (!gone) { setReleases(r); setHealth(h); setErr(null) } })
      .catch((e) => { if (!gone) setErr(e instanceof Error ? e.message : "Failed to load releases") })
    return () => { gone = true }
  }, [token])

  const pct = (failed?: number | null, total?: number | null) =>
    total && total > 0 ? `${(((failed ?? 0) / total) * 100).toFixed(1)}%` : "n/a"

  return (
    <>
      {err && <div className="error">{err}</div>}
      <div className="card">
        <div className="card-toolbar"><h3 className="card-toolbar-title">System health</h3></div>
        {!health ? <p className="subtle-help">Checking…</p> : (
          <>
            <div className="family-stats">
              <span>Database <strong>{health.databaseOk ? "OK" : "DOWN"}</strong></span>
              <span>Requests 24h <strong>{health.totalRequests24h}</strong></span>
              <span>Failed 24h <strong>{health.failedRequests24h}</strong></span>
              <span>Failed payments 24h <strong>{health.failedPayments24h}</strong></span>
              <span>Last payment webhook <strong>{health.lastWebhookAtUtc ? timeAgo(health.lastWebhookAtUtc) : "never"}</strong></span>
            </div>
            {health.notes.map((n, i) => <p key={i} className="subtle-help">{n}</p>)}
          </>
        )}
      </div>
      <div className="card">
        <div className="card-toolbar"><h3 className="card-toolbar-title">Releases</h3></div>
        <p className="subtle-help">
          Each API registers its Cloud Run revision at startup; impact compares failed vs total operations in the
          72 hours before/after first seen. Nothing is shown for services that have not registered.
        </p>
        {releases.length === 0 ? (
          <p className="subtle-help">No releases registered yet — the next deployment will appear here automatically.</p>
        ) : (
          <table>
            <thead><tr><th>Service</th><th>Version</th><th>First seen</th><th>Failure rate before</th><th>after</th><th>Affected companies</th></tr></thead>
            <tbody>
              {releases.map((rel, i) => (
                <tr key={i}>
                  <td style={{ fontWeight: 600 }}>{rel.service}</td>
                  <td className="mono" style={{ maxWidth: 220, overflow: "hidden", textOverflow: "ellipsis" }}>{rel.version}</td>
                  <td>{new Date(rel.firstSeenAtUtc).toLocaleString()}</td>
                  <td className="mono">{pct(rel.failedOpsBefore, rel.totalOpsBefore)}</td>
                  <td className="mono">{pct(rel.failedOpsAfter, rel.totalOpsAfter)}</td>
                  <td className="mono">{rel.affectedCompaniesAfter ?? "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </>
  )
}
