// PROMPT 5: Organization 360 + Company 360 — one page per customer with the
// whole relationship: header + summary cards, company list, activity rollup,
// significant-event timeline, vertical support context, internal notes /
// contact history / follow-ups, product feedback and cancellation reasons.
// Everything internal-only; no secrets are ever fetched or shown.

import { useEffect, useState } from "react"
import {
  CANCELLATION_REASONS,
  CONTACT_TYPES,
  NOTE_CATEGORIES,
  addCancellationReason,
  addCrmFeedback,
  addCrmNote,
  fetchCancellationReasons,
  fetchCrmFeedback,
  fetchCrmNotes,
  fetchMilestones,
  fetchFeatureUsage,
  fetchOrgActivitySummary,
  fetchRecent,
  fetchTimeline,
  fetchVerticalSummary,
  describeActivity,
  timeAgo,
  type CancellationReason,
  type CompanySummary,
  type CrmNote,
  type FeatureUsageRow,
  type Milestone,
  type OrgActivitySummary,
  type OrganizationSummary,
  type ProductFeedback,
  type RecentActivity,
  type TimelineEvent,
  type VerticalSummary,
} from "./platform-activity-api"
import { HealthBadge } from "./customer-success"
import { fetchCompanyErrors, type CompanyErrors } from "./platform-activity-api"
import { TrendBadge } from "./platform-dashboard"

const KIND_ICONS: Record<string, string> = {
  Registered: "🏁", CompanyCreated: "🏢", FirstMeaningful: "⚡", FirstSale: "💰",
  TrialEnds: "⏳", Billing: "🧾", InvoicePaid: "✅", PaymentFailed: "⚠️",
  HealthChanged: "❤️", Attention: "🔔", Reactivated: "🔄", Note: "📝", Contacted: "📞",
}

function Timeline({ events }: { events: TimelineEvent[] }) {
  if (events.length === 0) return <p className="subtle-help">No significant events recorded yet.</p>
  return (
    <div className="timeline">
      {events.map((e, i) => (
        <div key={i} className="timeline-row">
          <span className="timeline-icon" aria-hidden>{KIND_ICONS[e.kind] || "•"}</span>
          <div className="timeline-body">
            <div className="timeline-title">
              {e.title}
              {e.companyName && !e.title.includes(e.companyName) && <span className="subtle-inline"> · {e.companyName}</span>}
            </div>
            {e.detail && <div className="timeline-detail">{e.detail}</div>}
            <div className="timeline-when">{timeAgo(e.atUtc)}{e.actor ? ` · ${e.actor}` : ""}</div>
          </div>
        </div>
      ))}
    </div>
  )
}

function NotesPanel({ token, organizationId, companyId, onChanged }: {
  token: string; organizationId: string; companyId?: string; onChanged?: () => void
}) {
  const [notes, setNotes] = useState<CrmNote[]>([])
  const [err, setErr] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [category, setCategory] = useState("General")
  const [contactType, setContactType] = useState("")
  const [text, setText] = useState("")
  const [followUp, setFollowUp] = useState("")
  const [assignee, setAssignee] = useState("")

  async function load() {
    try { setNotes(await fetchCrmNotes(token, organizationId, companyId)) }
    catch (e) { setErr(e instanceof Error ? e.message : "Failed to load notes") }
  }
  useEffect(() => { void load() }, [token, organizationId, companyId])

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!text.trim()) return
    setBusy(true)
    setErr(null)
    try {
      await addCrmNote(token, {
        organizationId,
        companyId,
        category,
        contactType: contactType || undefined,
        note: text.trim(),
        followUpAtUtc: followUp ? new Date(`${followUp}T09:00:00Z`).toISOString() : null,
        assignedToName: assignee.trim() || undefined,
      })
      setText(""); setFollowUp(""); setAssignee(""); setContactType("")
      await load()
      onChanged?.()
    } catch (e2) {
      setErr(e2 instanceof Error ? e2.message : "Failed to save note")
    } finally {
      setBusy(false)
    }
  }

  return (
    <div>
      <p className="subtle-help">Internal only — customers never see these. Author and date are recorded.</p>
      {err && <div className="error">{err}</div>}
      <form onSubmit={submit} className="note-form">
        <div className="note-form-row">
          <select value={category} onChange={(e) => setCategory(e.target.value)} aria-label="Category">
            {NOTE_CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
          </select>
          <select value={contactType} onChange={(e) => setContactType(e.target.value)} aria-label="Interaction">
            <option value="">Note (no contact)</option>
            {CONTACT_TYPES.map((c) => <option key={c} value={c}>{c}</option>)}
          </select>
          <input type="date" value={followUp} onChange={(e) => setFollowUp(e.target.value)} aria-label="Follow-up date" title="Follow-up date" />
          <input placeholder="Assigned to…" value={assignee} onChange={(e) => setAssignee(e.target.value)} />
        </div>
        <div className="note-form-row">
          <input className="note-input" placeholder={contactType ? `What happened on the ${contactType.toLowerCase()}?` : "Add an internal note…"}
            value={text} onChange={(e) => setText(e.target.value)} />
          <button type="submit" className="admin-btn-primary" disabled={busy || !text.trim()}>
            {busy ? "Saving…" : "Add"}
          </button>
        </div>
      </form>
      {notes.length === 0 ? <p className="subtle-help">No notes yet.</p> : (
        <div className="recent-list">
          {notes.map((n) => (
            <div key={n.id} className="recent-row" style={{ cursor: "default" }}>
              <div>
                <div className="recent-name">
                  {n.contactType ? `${n.contactType} — ` : ""}{n.note}
                </div>
                <div className="recent-sub">
                  {n.category} · {n.createdBy}
                  {n.companyName ? ` · ${n.companyName}` : ""}
                  {n.assignedToName ? ` · assigned: ${n.assignedToName}` : ""}
                  {n.followUpAtUtc ? ` · follow-up ${new Date(n.followUpAtUtc).toLocaleDateString()}` : ""}
                  {n.outcome ? ` · outcome: ${n.outcome}` : ""}
                </div>
              </div>
              <span className="recent-ago">{timeAgo(n.createdAtUtc)}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

function FeedbackPanel({ token, org, companies }: {
  token: string; org: OrganizationSummary; companies: CompanySummary[]
}) {
  const [rows, setRows] = useState<ProductFeedback[]>([])
  const [err, setErr] = useState<string | null>(null)
  const [title, setTitle] = useState("")
  const [category, setCategory] = useState("FeatureRequest")
  const [severity, setSeverity] = useState("Medium")
  const [module, setModule] = useState("")
  const [companyId, setCompanyId] = useState("")
  const [busy, setBusy] = useState(false)

  async function load() {
    try { setRows(await fetchCrmFeedback(token, org.organizationId)) }
    catch (e) { setErr(e instanceof Error ? e.message : "Failed to load feedback") }
  }
  useEffect(() => { void load() }, [token, org.organizationId])

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!title.trim()) return
    setBusy(true)
    try {
      const company = companies.find((c) => c.companyId === companyId)
      await addCrmFeedback(token, {
        organizationId: org.organizationId,
        companyId: companyId || undefined,
        companyFamily: company?.companyFamily ?? undefined,
        category, severity, module: module.trim() || undefined, title: title.trim(),
      })
      setTitle(""); setModule("")
      await load()
    } catch (e2) {
      setErr(e2 instanceof Error ? e2.message : "Failed to save feedback")
    } finally { setBusy(false) }
  }

  return (
    <div>
      {err && <div className="error">{err}</div>}
      <form onSubmit={submit} className="note-form">
        <div className="note-form-row">
          <select value={category} onChange={(e) => setCategory(e.target.value)}>
            {["FeatureRequest", "Problem", "Praise", "Other"].map((c) => <option key={c} value={c}>{c}</option>)}
          </select>
          <select value={severity} onChange={(e) => setSeverity(e.target.value)}>
            {["Low", "Medium", "High"].map((c) => <option key={c} value={c}>{c}</option>)}
          </select>
          <input placeholder="Module (e.g. Daily Closing)" value={module} onChange={(e) => setModule(e.target.value)} />
          <select value={companyId} onChange={(e) => setCompanyId(e.target.value)}>
            <option value="">Organization-wide</option>
            {companies.map((c) => <option key={c.companyId} value={c.companyId}>{c.companyName || c.companyId}</option>)}
          </select>
        </div>
        <div className="note-form-row">
          <input className="note-input" placeholder="Feedback / requested feature / problem…" value={title} onChange={(e) => setTitle(e.target.value)} />
          <button type="submit" className="admin-btn-primary" disabled={busy || !title.trim()}>{busy ? "Saving…" : "Record"}</button>
        </div>
      </form>
      {rows.length === 0 ? <p className="subtle-help">No product feedback recorded.</p> : (
        <div className="recent-list">
          {rows.map((f) => (
            <div key={f.id} className="recent-row" style={{ cursor: "default" }}>
              <div>
                <div className="recent-name">{f.title}</div>
                <div className="recent-sub">{f.category} · {f.severity}{f.module ? ` · ${f.module}` : ""}{f.companyName ? ` · ${f.companyName}` : ""} · {f.status} · {f.createdBy}</div>
              </div>
              <span className="recent-ago">{timeAgo(f.createdAtUtc)}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

function CancellationPanel({ token, org }: { token: string; org: OrganizationSummary }) {
  const [rows, setRows] = useState<CancellationReason[]>([])
  const [code, setCode] = useState("Other")
  const [note, setNote] = useState("")
  const [err, setErr] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  async function load() {
    try { setRows(await fetchCancellationReasons(token, org.organizationId)) }
    catch (e) { setErr(e instanceof Error ? e.message : "Failed to load") }
  }
  useEffect(() => { void load() }, [token, org.organizationId])

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    setBusy(true)
    try {
      await addCancellationReason(token, { organizationId: org.organizationId, reasonCode: code, note: note.trim() || undefined })
      setNote("")
      await load()
    } catch (e2) { setErr(e2 instanceof Error ? e2.message : "Failed to save") }
    finally { setBusy(false) }
  }

  return (
    <div>
      <p className="subtle-help">Structured reason when a subscription is cancelled or paused.</p>
      {err && <div className="error">{err}</div>}
      <form onSubmit={submit} className="note-form">
        <div className="note-form-row">
          <select value={code} onChange={(e) => setCode(e.target.value)}>
            {CANCELLATION_REASONS.map((c) => <option key={c} value={c}>{c.replace(/([a-z])([A-Z])/g, "$1 $2")}</option>)}
          </select>
          <input className="note-input" placeholder="Optional note…" value={note} onChange={(e) => setNote(e.target.value)} />
          <button type="submit" className="admin-btn-primary" disabled={busy}>Record</button>
        </div>
      </form>
      {rows.length > 0 && (
        <div className="recent-list">
          {rows.map((r) => (
            <div key={r.id} className="recent-row" style={{ cursor: "default" }}>
              <div>
                <div className="recent-name">{r.reasonCode.replace(/([a-z])([A-Z])/g, "$1 $2")}</div>
                <div className="recent-sub">{r.note || "—"} · {r.createdBy}</div>
              </div>
              <span className="recent-ago">{timeAgo(r.createdAtUtc)}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

// ---------------------------------------------------------------- Org 360
export function Organization360({ token, org, onBack, onOpenCompany, onOpenBilling, onOpenAudit }: {
  token: string
  org: OrganizationSummary
  onBack: () => void
  onOpenCompany: (companyId: string) => void
  onOpenBilling: () => void
  onOpenAudit: (companyId?: string | null) => void
}) {
  const [timeline, setTimeline] = useState<TimelineEvent[]>([])
  const [activity, setActivity] = useState<OrgActivitySummary | null>(null)
  const [err, setErr] = useState<string | null>(null)

  useEffect(() => {
    let gone = false
    Promise.all([fetchTimeline(token, org.organizationId), fetchOrgActivitySummary(token, org.organizationId)])
      .then(([t, a]) => { if (!gone) { setTimeline(t); setActivity(a); setErr(null) } })
      .catch((e) => { if (!gone) setErr(e instanceof Error ? e.message : "Failed to load 360 data") })
    return () => { gone = true }
  }, [token, org.organizationId])

  return (
    <>
      <div className="card">
        <div className="card-toolbar">
          <h2 className="card-toolbar-title">
            <button type="button" className="link-btn" onClick={onBack}>← Directory</button>{" "}
            {org.organizationName || org.organizationId} — Organization 360
          </h2>
          <div className="trend-controls">
            <button type="button" className="seg-btn" onClick={onOpenBilling}>Billing &amp; invoices</button>
            <button type="button" className="seg-btn" onClick={() => onOpenAudit(null)}>Activity audit</button>
          </div>
        </div>
        <div className="family-stats" style={{ marginBottom: 12 }}>
          <span>OrgCode <strong>{org.orgCode || "—"}</strong></span>
          <span>Country / market <strong>{org.countryCode || "—"}</strong></span>
          <span>Subscription <strong>{org.subscriptionStatus}</strong></span>
          <span>Health <HealthBadge health={org.health} reasons={org.healthReasons} /></span>
          <span>Last meaningful <strong>{timeAgo(org.lastMeaningfulActivityAtUtc)}</strong></span>
          <span>Owner <strong>{org.ownerEmail || "—"}</strong></span>
        </div>
        <div className="kpi-row" style={{ marginBottom: 0 }}>
          <div className="kpi-tile"><div className="kpi-label">Companies</div><div className="kpi-value">{org.companyCount}</div></div>
          <div className="kpi-tile"><div className="kpi-label">Active companies (30d)</div><div className="kpi-value">{org.activeCompanies30d}</div></div>
          <div className="kpi-tile"><div className="kpi-label">Active users 30d</div><div className="kpi-value">{org.activeUsers30d}</div></div>
          <div className="kpi-tile"><div className="kpi-label">Setup completion</div><div className="kpi-value">{org.setupPercent}%</div></div>
          <div className="kpi-tile"><div className="kpi-label">Trial / paid</div><div className="kpi-value" style={{ fontSize: 18 }}>{org.subscriptionStatus === "Active" ? "Paid" : org.subscriptionStatus}</div>
            {org.trialEndUtc && <div className="kpi-note">trial ends {new Date(org.trialEndUtc).toLocaleDateString()}</div>}</div>
          <div className="kpi-tile"><div className="kpi-label">Next billing</div><div className="kpi-value" style={{ fontSize: 18 }}>
            {activity?.nextBillingUtc ? new Date(activity.nextBillingUtc).toLocaleDateString() : "—"}</div></div>
        </div>
        {org.healthReasons.length > 0 && (
          <p className="subtle-help" style={{ marginTop: 10 }}>Why this health: {org.healthReasons.join(" · ")}</p>
        )}
      </div>
      {err && <div className="error">{err}</div>}

      <div className="card">
        <div className="card-toolbar"><h3 className="card-toolbar-title">Companies</h3></div>
        <div style={{ overflowX: "auto" }}>
          <table>
            <thead><tr><th>Company</th><th>Type</th><th>Template</th><th>Plan</th><th>Setup</th><th>Last activity</th><th>Trend</th><th>Health</th><th>Billing participation</th><th></th></tr></thead>
            <tbody>
              {org.companies.map((c) => (
                <tr key={c.companyId} className="row-click" onClick={() => onOpenCompany(c.companyId)}>
                  <td style={{ fontWeight: 600 }}>{c.companyName || c.companyId}</td>
                  <td>{c.companyFamily || "—"}</td>
                  <td>{c.businessTemplateCode || "—"}</td>
                  <td>{c.planCode || "—"}</td>
                  <td className="mono">{c.setupPercent}%</td>
                  <td>{timeAgo(c.lastActivityAtUtc || c.lastMeaningfulActivityAtUtc)}</td>
                  <td><TrendBadge status={c.trend.status} pct={c.trend.percentChange} /></td>
                  <td><HealthBadge health={c.health} reasons={c.healthReasons} /></td>
                  <td>{c.billingParticipation || "—"}</td>
                  <td><button type="button" className="link-btn" onClick={(e) => { e.stopPropagation(); onOpenAudit(c.companyId) }}>Audit</button></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      <div className="report-grid">
        <div className="card">
          <div className="card-toolbar"><h3 className="card-toolbar-title">Activity summary</h3></div>
          {activity === null ? <p className="subtle-help">Loading…</p> : (
            <>
              <table>
                <thead><tr><th>Window</th><th>Meaningful</th><th>Active days</th><th>Active users</th></tr></thead>
                <tbody>
                  {activity.windows.map((w) => (
                    <tr key={w.days}>
                      <td style={{ fontWeight: 600 }}>{w.days}d</td>
                      <td className="mono">{w.meaningfulCount}</td>
                      <td className="mono">{w.activeDays}</td>
                      <td className="mono">{w.activeUsers}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
              <div style={{ marginTop: 10 }}>
                <div className="kpi-label" style={{ marginBottom: 6 }}>Most-used categories (90d)</div>
                {activity.topCategories.length === 0 ? <p className="subtle-help">No activity yet.</p> : (
                  <div className="family-templates">
                    {activity.topCategories.map((c) => <span key={c.key} className="badge">{c.key} · {c.meaningfulCount}</span>)}
                  </div>
                )}
              </div>
              <div style={{ marginTop: 10 }}>
                <span className="kpi-label">Usage trend </span><TrendBadge status={org.trend.status} pct={org.trend.percentChange} />
              </div>
            </>
          )}
        </div>
        <div className="card report-wide">
          <div className="card-toolbar"><h3 className="card-toolbar-title">Customer success timeline</h3></div>
          <Timeline events={timeline} />
        </div>
      </div>

      <div className="report-grid">
        <div className="card report-wide">
          <div className="card-toolbar"><h3 className="card-toolbar-title">Internal notes, contacts &amp; follow-ups</h3></div>
          <NotesPanel token={token} organizationId={org.organizationId} />
        </div>
        <div className="card">
          <div className="card-toolbar"><h3 className="card-toolbar-title">Cancellation reasons</h3></div>
          <CancellationPanel token={token} org={org} />
        </div>
      </div>

      <div className="card">
        <div className="card-toolbar"><h3 className="card-toolbar-title">Product feedback</h3></div>
        <FeedbackPanel token={token} org={org} companies={org.companies} />
      </div>
    </>
  )
}

// ---------------------------------------------------------------- Company 360
export function Company360({ token, org, company, onBack, onOpenAudit }: {
  token: string
  org: OrganizationSummary
  company: CompanySummary
  onBack: () => void
  onOpenAudit: (companyId: string) => void
}) {
  const [vertical, setVertical] = useState<VerticalSummary | null>(null)
  const [milestones, setMilestones] = useState<Milestone[]>([])
  const [features, setFeatures] = useState<FeatureUsageRow[]>([])
  const [recent, setRecent] = useState<RecentActivity[]>([])
  const [errors, setErrors] = useState<CompanyErrors | null>(null)
  const [err, setErr] = useState<string | null>(null)

  useEffect(() => {
    let gone = false
    Promise.all([
      fetchVerticalSummary(token, company.companyId),
      fetchMilestones(token, company.companyId),
      fetchFeatureUsage(token, company.companyId),
      fetchRecent(token, 10).then((r) => r.filter((x) => x.companyId === company.companyId)),
      fetchCompanyErrors(token, company.companyId).catch(() => null),
    ])
      .then(([v, m, f, r, e]) => { if (!gone) { setVertical(v); setMilestones(m); setFeatures(f); setRecent(r); setErrors(e); setErr(null) } })
      .catch((e) => { if (!gone) setErr(e instanceof Error ? e.message : "Failed to load Company 360") })
    return () => { gone = true }
  }, [token, company.companyId])

  return (
    <>
      <div className="card">
        <div className="card-toolbar">
          <h2 className="card-toolbar-title">
            <button type="button" className="link-btn" onClick={onBack}>← {org.organizationName || "Organization"}</button>{" "}
            {company.companyName || company.companyId} — Company 360
          </h2>
          <div className="trend-controls">
            <button type="button" className="seg-btn" onClick={() => onOpenAudit(company.companyId)}>Filtered audit</button>
          </div>
        </div>
        <div className="family-stats">
          <span>Organization <strong>{org.organizationName || "—"}</strong></span>
          <span>Type <strong>{company.companyFamily || "—"}</strong></span>
          <span>Template <strong>{company.businessTemplateCode || "—"}</strong></span>
          <span>Plan <strong>{company.planCode || "—"}</strong></span>
          <span>Billing participation <strong>{company.billingParticipation || "—"}</strong></span>
          <span>Health <HealthBadge health={company.health} reasons={company.healthReasons} /></span>
          <span>Last activity <strong>{timeAgo(company.lastActivityAtUtc || company.lastMeaningfulActivityAtUtc)}</strong></span>
        </div>
        {company.healthReasons.length > 0 && (
          <p className="subtle-help" style={{ marginTop: 8 }}>Why this health: {company.healthReasons.join(" · ")}</p>
        )}
      </div>
      {err && <div className="error">{err}</div>}

      <div className="report-grid">
        <div className="card">
          <div className="card-toolbar"><h3 className="card-toolbar-title">Usage</h3></div>
          <div className="family-stats">
            <span>Meaningful today <strong>{company.meaningfulActivityCountToday}</strong></span>
            <span>7d <strong>{company.meaningfulActivityCount7d}</strong></span>
            <span>30d <strong>{company.meaningfulActivityCount30d}</strong></span>
            <span>Active days 30d <strong>{company.activeDays30d}</strong></span>
            <span>Active users 30d <strong>{company.activeUsers30d}</strong></span>
            <span>Trend <TrendBadge status={company.trend.status} pct={company.trend.percentChange} /></span>
            <span>Activated <strong>{company.activated ? "Yes" : "Not yet"}</strong></span>
            {company.timeToActivationDays != null && <span>Time to activation <strong>{company.timeToActivationDays}d</strong></span>}
          </div>
          <div className="card-toolbar" style={{ marginTop: 14 }}><h3 className="card-toolbar-title">{company.companyFamily || "Business"} summary</h3></div>
          {vertical === null ? <p className="subtle-help">Loading…</p>
            : vertical.items.length === 0 ? <p className="subtle-help">No vertical summary available for this business type.</p> : (
              <div className="family-stats">
                {vertical.items.map((i) => <span key={i.label}>{i.label} <strong>{i.value}</strong></span>)}
              </div>
            )}
          <div className="card-toolbar" style={{ marginTop: 14 }}><h3 className="card-toolbar-title">Errors</h3></div>
          {errors === null ? (
            <p className="subtle-help">No error data available for this role.</p>
          ) : (
            <>
              <div className="family-stats" style={{ marginBottom: 8 }}>
                <span>24h <strong>{errors.errors24h}</strong></span>
                <span>7d <strong>{errors.errors7d}</strong></span>
                <span>Failed operations 7d <strong>{errors.failedOperations7d}</strong></span>
              </div>
              {errors.recent.length > 0 && (
                <div className="recent-list" style={{ maxHeight: 200, overflowY: "auto" }}>
                  {errors.recent.map((e2) => (
                    <div key={e2.correlationId} className="recent-row" style={{ cursor: "default" }}>
                      <div>
                        <div className="recent-name">{e2.operation} {e2.resource}</div>
                        <div className="recent-sub" title={e2.summary}>#{e2.correlationId} · {e2.summary}</div>
                      </div>
                      <span className="recent-ago">{timeAgo(e2.occurredAtUtc)}</span>
                    </div>
                  ))}
                </div>
              )}
              <p className="subtle-help">{errors.deepLogsHint}</p>
            </>
          )}
        </div>
        <div className="card report-wide">
          <div className="card-toolbar"><h3 className="card-toolbar-title">Setup — {company.setupPercent}% complete</h3></div>
          <div className="milestone-list">
            {milestones.map((m) => (
              <span key={m.code} className={`badge${m.complete ? " badge-yes" : ""}`}>
                {m.complete ? "✓ " : "○ "}{m.title}{m.required ? " *" : ""}
              </span>
            ))}
          </div>
          <div className="card-toolbar" style={{ marginTop: 14 }}><h3 className="card-toolbar-title">Feature adoption</h3></div>
          {features.length === 0 ? <p className="subtle-help">No feature usage recorded yet.</p> : (
            <div style={{ overflowX: "auto" }}>
              <table>
                <thead><tr><th>Feature</th><th>First used</th><th>Last used</th><th>Uses</th><th>Active days</th></tr></thead>
                <tbody>
                  {features.map((f) => (
                    <tr key={f.feature}>
                      <td style={{ fontWeight: 600 }}>{f.feature}</td>
                      <td>{timeAgo(f.firstUsedAtUtc)}</td>
                      <td>{timeAgo(f.lastUsedAtUtc)}</td>
                      <td className="mono">{f.usageCount}</td>
                      <td className="mono">{f.activeDaysUsingFeature}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          <div className="card-toolbar" style={{ marginTop: 14 }}><h3 className="card-toolbar-title">Recent meaningful activity</h3></div>
          {recent.length === 0 ? <p className="subtle-help">No recent meaningful activity.</p> : (
            <div className="recent-list">
              {recent.map((r) => (
                <div key={r.id} className="recent-row" style={{ cursor: "default" }}>
                  <div>
                    <div className="recent-name">{describeActivity(r.activityType)}</div>
                    <div className="recent-sub">{r.category}</div>
                  </div>
                  <span className="recent-ago">{timeAgo(r.occurredAtUtc)}</span>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      <div className="card">
        <div className="card-toolbar"><h3 className="card-toolbar-title">Customer success notes — this company</h3></div>
        <NotesPanel token={token} organizationId={org.organizationId} companyId={company.companyId} />
      </div>
    </>
  )
}
