// PROMPT 2: Customer Intelligence directory — organization-level and
// company-level views over the activity foundation, with filters, global
// search and drill-down placeholders (Organization/Company 360 land in
// Prompt 5; Health lands in Prompt 3).

import { useMemo, useState } from "react"
import {
  FAMILIES,
  timeAgo,
  type ActivityStatus,
  type OrganizationSummary,
} from "./platform-activity-api"
import { TrendBadge } from "./platform-dashboard"
import { HealthBadge } from "./customer-success"
import { Company360, Organization360 } from "./customer-360"
import { money, type OrgRevenueRow } from "./platform-activity-api"

type View = "orgs" | "companies"
type ActivityFilter = "" | "today" | "7d" | "30d" | "inactive" | "newmonth"
type BillingFilter = "" | "Trial" | "Active" | "PastDue" | "None"

function isNewThisMonth(iso?: string | null): boolean {
  if (!iso) return false
  const d = new Date(iso)
  const m = new Date(); m.setDate(1); m.setHours(0, 0, 0, 0)
  return d >= m
}

export function CustomerIntelligencePage({ token, organizations, loading, error, view, onViewChange, focusOrg, onFocusOrg, focusCompany, onFocusCompany, onDrillAudit, onOpenBilling, revenueByOrg }: {
  token: string
  organizations: OrganizationSummary[]
  loading: boolean
  error: string | null
  view: View
  onViewChange: (v: View) => void
  /** Deep-linkable Organization 360. */
  focusOrg: string | null
  onFocusOrg: (org: string | null) => void
  /** Deep-linkable Company 360. */
  focusCompany: string | null
  onFocusCompany: (companyId: string | null) => void
  onDrillAudit: (companyId: string) => void
  onOpenBilling: (ownerId: string) => void
  /** Per-org revenue rows once the Revenue dashboard has been loaded (lazy). */
  revenueByOrg?: Map<string, OrgRevenueRow> | null
}) {
  const [q, setQ] = useState("")
  const [family, setFamily] = useState("")
  const [template, setTemplate] = useState("")
  const [country, setCountry] = useState("")
  const [billing, setBilling] = useState<BillingFilter>("")
  const [activity, setActivity] = useState<ActivityFilter>("")
  const [plan, setPlan] = useState("")
  const [healthFilter, setHealthFilter] = useState("")

  const companies = useMemo(
    () => organizations.flatMap((o) => o.companies.map((c) => ({ ...c, org: o }))),
    [organizations]
  )

  const templates = useMemo(
    () => [...new Set(companies.map((c) => c.businessTemplateCode).filter((t): t is string => !!t))].sort(),
    [companies]
  )
  const countries = useMemo(
    () => [...new Set(organizations.map((o) => o.countryCode).filter((c): c is string => !!c))].sort(),
    [organizations]
  )
  const plans = useMemo(
    () => [...new Set(companies.map((c) => c.planCode).filter((p): p is string => !!p))].sort(),
    [companies]
  )

  function matchActivity(status: ActivityStatus, createdAt?: string | null): boolean {
    switch (activity) {
      case "today": return status === "ActiveToday"
      case "7d": return status === "ActiveToday" || status === "Active7Days"
      case "30d": return status === "ActiveToday" || status === "Active7Days" || status === "Active30Days"
      case "inactive": return status === "Inactive30Plus" || status === "NoActivity"
      case "newmonth": return isNewThisMonth(createdAt)
      default: return true
    }
  }

  const needle = q.trim().toLowerCase()
  function orgMatchesSearch(o: OrganizationSummary): boolean {
    if (!needle) return true
    const blob = [
      o.organizationName, o.orgCode, o.ownerEmail, o.countryCode,
      ...o.companies.flatMap((c) => [c.companyName, c.companyFamily, c.businessTemplateCode]),
    ].filter(Boolean).join(" ").toLowerCase()
    return blob.includes(needle)
  }

  const filteredOrgs = useMemo(() => organizations.filter((o) => {
    if (!orgMatchesSearch(o)) return false
    if (family && !o.companies.some((c) => c.companyFamily === family)) return false
    if (template && !o.companies.some((c) => c.businessTemplateCode === template)) return false
    if (country && o.countryCode !== country) return false
    if (billing && (billing === "None" ? o.subscriptionStatus !== "None" : o.subscriptionStatus !== billing)) return false
    if (plan && !o.companies.some((c) => c.planCode === plan)) return false
    if (activity && !matchActivity(o.activityStatus, o.firstCompanyCreatedAtUtc)) return false
    if (healthFilter && o.health !== healthFilter) return false
    return true
  }), [organizations, needle, family, template, country, billing, plan, activity, healthFilter])

  const filteredCompanies = useMemo(() => companies.filter((c) => {
    if (needle) {
      const blob = [c.companyName, c.companyFamily, c.businessTemplateCode, c.planCode,
        c.org.organizationName, c.org.orgCode, c.org.ownerEmail]
        .filter(Boolean).join(" ").toLowerCase()
      if (!blob.includes(needle)) return false
    }
    if (family && c.companyFamily !== family) return false
    if (template && c.businessTemplateCode !== template) return false
    if (country && c.org.countryCode !== country) return false
    if (billing && (billing === "None" ? c.org.subscriptionStatus !== "None" : c.org.subscriptionStatus !== billing)) return false
    if (plan && c.planCode !== plan) return false
    if (activity && !matchActivity(c.activityStatus, c.createdAtUtc)) return false
    if (healthFilter && c.health !== healthFilter) return false
    return true
  }), [companies, needle, family, template, country, billing, plan, activity, healthFilter])

  const focused = focusOrg ? organizations.find((o) => o.organizationId === focusOrg) : null
  const focusedCompany = focusCompany ? companies.find((c) => c.companyId === focusCompany) : null

  if (loading) return <div className="card"><p className="subtle-help">Loading customer intelligence…</p></div>

  // Full-page 360 views (Prompt 5) replace the directory while focused.
  if (focusedCompany) {
    return (
      <Company360
        token={token}
        org={focusedCompany.org}
        company={focusedCompany}
        onBack={() => { onFocusCompany(null); onFocusOrg(focusedCompany.org.organizationId) }}
        onOpenAudit={(companyId) => onDrillAudit(companyId)}
      />
    )
  }
  if (focused) {
    return (
      <Organization360
        token={token}
        org={focused}
        onBack={() => onFocusOrg(null)}
        onOpenCompany={(companyId) => { onFocusOrg(null); onFocusCompany(companyId) }}
        onOpenBilling={() => onOpenBilling(focused.organizationId)}
        onOpenAudit={(companyId) => onDrillAudit(companyId ?? "")}
      />
    )
  }

  return (
    <>
      {error && <div className="error">{error}</div>}

      <div className="card">
        <div className="card-toolbar">
          <h2 className="card-toolbar-title">Customer Intelligence</h2>
          <div className="trend-controls">
            <button type="button" className={`seg-btn${view === "orgs" ? " active" : ""}`} onClick={() => onViewChange("orgs")}>Organizations</button>
            <button type="button" className={`seg-btn${view === "companies" ? " active" : ""}`} onClick={() => onViewChange("companies")}>Companies</button>
          </div>
        </div>

        <div className="audit-filters" aria-label="Directory filters">
          <div className="audit-filters-row">
            <label className="audit-filter-label">Search
              <input type="search" className="audit-filter-input" placeholder="Organization, org code, company, email, type, template…"
                value={q} onChange={(e) => setQ(e.target.value)} />
            </label>
            <label className="audit-filter-label">Business type
              <select className="audit-filter-input" value={family} onChange={(e) => setFamily(e.target.value)}>
                <option value="">All</option>
                {FAMILIES.map((f) => <option key={f} value={f}>{f}</option>)}
              </select>
            </label>
            <label className="audit-filter-label">Template
              <select className="audit-filter-input" value={template} onChange={(e) => setTemplate(e.target.value)}>
                <option value="">All</option>
                {templates.map((t) => <option key={t} value={t}>{t}</option>)}
              </select>
            </label>
            <label className="audit-filter-label">Country / market
              <select className="audit-filter-input" value={country} onChange={(e) => setCountry(e.target.value)}>
                <option value="">All</option>
                {countries.map((c) => <option key={c} value={c}>{c}</option>)}
              </select>
            </label>
          </div>
          <div className="audit-filters-row">
            <label className="audit-filter-label">Subscription
              <select className="audit-filter-input" value={billing} onChange={(e) => setBilling(e.target.value as BillingFilter)}>
                <option value="">All</option>
                <option value="Trial">Trial</option>
                <option value="Active">Paying</option>
                <option value="PastDue">Past due</option>
                <option value="None">Not billed</option>
              </select>
            </label>
            <label className="audit-filter-label">Activity
              <select className="audit-filter-input" value={activity} onChange={(e) => setActivity(e.target.value as ActivityFilter)}>
                <option value="">All</option>
                <option value="today">Active today</option>
                <option value="7d">Active 7d</option>
                <option value="30d">Active 30d</option>
                <option value="inactive">Inactive 30+</option>
                <option value="newmonth">New this month</option>
              </select>
            </label>
            <label className="audit-filter-label">Health
              <select className="audit-filter-input" value={healthFilter} onChange={(e) => setHealthFilter(e.target.value)}>
                <option value="">All</option>
                {["Healthy", "Needs Attention", "At Risk", "Inactive", "New"].map((h) => <option key={h} value={h}>{h}</option>)}
              </select>
            </label>
            <label className="audit-filter-label">Plan / tier
              <select className="audit-filter-input" value={plan} onChange={(e) => setPlan(e.target.value)}>
                <option value="">All</option>
                {plans.map((p) => <option key={p} value={p}>{p}</option>)}
              </select>
            </label>
            <div className="audit-filter-actions">
              <button type="button" className="audit-filter-reset"
                onClick={() => { setQ(""); setFamily(""); setTemplate(""); setCountry(""); setBilling(""); setActivity(""); setPlan(""); setHealthFilter("") }}>
                Reset filters
              </button>
            </div>
          </div>
          <p className="audit-filter-meta subtle-help" style={{ marginBottom: 0 }}>
            {view === "orgs"
              ? `Showing ${filteredOrgs.length} of ${organizations.length} organization${organizations.length === 1 ? "" : "s"}.`
              : `Showing ${filteredCompanies.length} of ${companies.length} compan${companies.length === 1 ? "y" : "ies"}.`}
          </p>
        </div>

        {view === "orgs" ? (
          <div style={{ overflowX: "auto" }}>
            <table>
              <thead>
                <tr>
                  <th>Organization</th><th>Country</th><th>Companies</th><th>Last meaningful activity</th>
                  <th>Active companies</th><th>30d activity</th><th>Trend</th><th>Setup %</th>
                  <th>Subscription</th><th>MRR</th><th>At-risk MRR</th><th>Health</th><th>Attention</th>
                </tr>
              </thead>
              <tbody>
                {filteredOrgs.length === 0 ? (
                  <tr><td colSpan={13} style={{ color: "#64748b" }}>
                    {organizations.length === 0
                      ? "No organizations registered yet — new signups appear here."
                      : "No organizations match these filters."}
                  </td></tr>
                ) : filteredOrgs.map((o) => (
                  <tr key={o.organizationId} className="row-click" onClick={() => onFocusOrg(o.organizationId)}>
                    <td style={{ fontWeight: 600 }}>
                      {o.organizationName || o.organizationId}
                      {o.orgCode && <span className="subtle-inline"> · {o.orgCode}</span>}
                    </td>
                    <td>{o.countryCode || "—"}</td>
                    <td className="mono">{o.companyCount}</td>
                    <td>{timeAgo(o.lastMeaningfulActivityAtUtc)}</td>
                    <td className="mono">{o.activeCompanies30d}/{o.companyCount}</td>
                    <td className="mono">{o.meaningfulActivityCount30d}</td>
                    <td><TrendBadge status={o.trend.status} pct={o.trend.percentChange} /></td>
                    <td className="mono">{o.setupPercent}%</td>
                    <td>{o.subscriptionStatus === "PastDue"
                      ? <span className="badge badge-no">Past due</span>
                      : o.subscriptionStatus === "Active"
                        ? <span className="badge badge-yes">Paying</span>
                        : o.subscriptionStatus}</td>
                    <td className="mono">{(() => {
                      const rev = revenueByOrg?.get(o.organizationId)
                      return rev ? money(rev.currencyCode, rev.netMrr) : "—"
                    })()}</td>
                    <td className="mono">{(() => {
                      const rev = revenueByOrg?.get(o.organizationId)
                      return rev && rev.revenueAtRisk > 0
                        ? <span style={{ color: "#b91c1c", fontWeight: 700 }}>{money(rev.currencyCode, rev.revenueAtRisk)}</span>
                        : "—"
                    })()}</td>
                    <td><HealthBadge health={o.health} reasons={o.healthReasons} /></td>
                    <td>{o.attention.length === 0 ? "—" : o.attention.map((a) => (
                      <span key={a} className={`badge${a === "PastDue" || a === "Inactive30Plus" ? " badge-no" : ""}`} style={{ marginRight: 4 }}>{a}</span>
                    ))}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div style={{ overflowX: "auto" }}>
            <table>
              <thead>
                <tr>
                  <th>Company</th><th>Organization</th><th>Business type</th><th>Template</th>
                  <th>Last activity</th><th>Active users (30d)</th><th>Activity 30d</th>
                  <th>Plan</th><th>Subscription</th><th></th>
                </tr>
              </thead>
              <tbody>
                {filteredCompanies.length === 0 ? (
                  <tr><td colSpan={10} style={{ color: "#64748b" }}>
                    {companies.length === 0
                      ? "No companies registered yet."
                      : "No companies match these filters."}
                  </td></tr>
                ) : filteredCompanies.map((c) => (
                  <tr key={c.companyId} className="row-click" onClick={() => onFocusCompany(c.companyId)}>
                    <td style={{ fontWeight: 600 }}>{c.companyName || c.companyId}</td>
                    <td>{c.org.organizationName || "—"}</td>
                    <td>{c.companyFamily || "—"}</td>
                    <td>{c.businessTemplateCode || "—"}</td>
                    <td>{timeAgo(c.lastActivityAtUtc || c.lastMeaningfulActivityAtUtc)}</td>
                    <td className="mono">{c.activeUsers30d}</td>
                    <td className="mono">{c.meaningfulActivityCount30d}</td>
                    <td>{c.planCode || "—"}</td>
                    <td>{c.org.subscriptionStatus === "PastDue"
                      ? <span className="badge badge-no">Past due</span>
                      : c.org.subscriptionStatus === "Active"
                        ? <span className="badge badge-yes">Paying</span>
                        : c.org.subscriptionStatus}</td>
                    <td><button type="button" className="link-btn" onClick={(e) => { e.stopPropagation(); onDrillAudit(c.companyId) }}>Audit</button></td>
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
