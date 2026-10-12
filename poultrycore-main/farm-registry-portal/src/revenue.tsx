// PROMPT 6: Revenue intelligence page. Everything is per currency/market —
// GHS, NGN and USD are never summed together and no FX rate is invented.

import { useEffect, useState } from "react"
import { KpiTile } from "./reports"
import { HealthBadge } from "./customer-success"
import {
  fetchRevenueDashboard,
  money,
  timeAgo,
  type MoneyByCurrency,
  type RevenueDashboard,
} from "./platform-activity-api"

function ic(d: string) {
  return <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d={d} /></svg>
}

function MoneyList({ rows }: { rows: MoneyByCurrency[] }) {
  if (rows.length === 0) return <span className="subtle-inline">—</span>
  return <>{rows.map((r) => <span key={r.currencyCode} className="badge" style={{ marginRight: 4 }}>{money(r.currencyCode, r.amount)}</span>)}</>
}

export function RevenuePage({ token, revenue, onLoaded, onOpenOrg }: {
  token: string
  revenue: RevenueDashboard | null
  onLoaded: (r: RevenueDashboard) => void
  onOpenOrg: (orgId: string) => void
}) {
  const [err, setErr] = useState<string | null>(null)
  const [loading, setLoading] = useState(!revenue)

  useEffect(() => {
    if (revenue) return
    let gone = false
    setLoading(true)
    fetchRevenueDashboard(token)
      .then((r) => { if (!gone) { onLoaded(r); setErr(null) } })
      .catch((e) => { if (!gone) setErr(e instanceof Error ? e.message : "Failed to load revenue intelligence") })
      .finally(() => { if (!gone) setLoading(false) })
    return () => { gone = true }
  }, [token, revenue, onLoaded])

  if (loading && !revenue) return <div className="card"><p className="subtle-help">Evaluating billing for every organization…</p></div>
  if (err) return <div className="error">{err}</div>
  if (!revenue) return null
  const r = revenue

  return (
    <>
      {r.byCurrency.length === 0 ? (
        <div className="card"><p className="subtle-help">No billing accounts exist yet — revenue intelligence fills in once organizations enter billing.</p></div>
      ) : r.byCurrency.map((b) => (
        <div key={b.currencyCode}>
          <div className="kpi-group-title">{b.marketCode} market — {b.currencyCode} (amounts never mixed across currencies)</div>
          <div className="kpi-row">
            <KpiTile label="MRR" value={money(b.currencyCode, b.mrr)} tone="green" note={`gross ${money(b.currencyCode, b.grossMrr)}`} icon={ic("M12 1v22M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6")} />
            <KpiTile label="ARR" value={money(b.currencyCode, b.arr)} note="12 × MRR" icon={ic("M3 3v18h18")} />
            <KpiTile label="Paying orgs / companies" value={`${b.payingOrganizations} / ${b.payingCompanies}`} icon={ic("M3 21h18M5 21V7l7-4 7 4v14")} />
            <KpiTile label="ARPO" value={b.arpo === null ? "—" : money(b.currencyCode, b.arpo)} note={b.arpc === null ? "" : `per company ${money(b.currencyCode, b.arpc)}`} icon={ic("M9 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM2 21c0-4 3-6 7-6s7 2 7 6")} />
            <KpiTile label="Past due" value={money(b.currencyCode, b.pastDueAmount)} tone={b.pastDueAmount > 0 ? "red" : "slate"} note="open overdue balances" icon={ic("M12 9v4M12 17h.01M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18z")} />
            <KpiTile label="Failed payments 30d" value={String(b.failedPaymentsCount30d)} tone={b.failedPaymentsCount30d > 0 ? "red" : "slate"} note={money(b.currencyCode, b.failedPaymentsAmount30d)} icon={ic("M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z")} />
          </div>
          <div className="kpi-row">
            <KpiTile label="New MRR" value={money(b.currencyCode, b.newMrr)} tone="green" note="vs last month" icon={ic("M12 5v14M5 12h14")} />
            <KpiTile label="Expansion" value={money(b.currencyCode, b.expansionMrr)} tone="teal" icon={ic("M7 17 17 7M7 7h10v10")} />
            <KpiTile label="Contraction" value={money(b.currencyCode, b.contractionMrr)} tone={b.contractionMrr > 0 ? "amber" : "slate"} icon={ic("M17 7 7 17M17 17H7V7")} />
            <KpiTile label="Churned MRR" value={money(b.currencyCode, b.churnedMrr)} tone={b.churnedMrr > 0 ? "red" : "slate"} icon={ic("M18.4 5.6a9 9 0 1 0 .1 12.7")} />
            <KpiTile label="Discounts this month" value={money(b.currencyCode, b.discountsGrantedThisMonth)} note="invoice discounts" icon={ic("M9 9h.01M15 15h.01M19 5 5 19M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18z")} />
            <KpiTile label="Credit outstanding" value={money(b.currencyCode, b.creditsIssuedOutstanding)} note={`trials potential ${money(b.currencyCode, b.trialPotentialMrr)}`} icon={ic("M21 12V7H5a2 2 0 0 1 0-4h14v4M3 5v14a2 2 0 0 0 2 2h16v-5")} />
          </div>
        </div>
      ))}
      <p className="subtle-help">{r.mrrDefinition}</p>

      <div className="report-grid">
        <div className="card report-wide">
          <div className="card-toolbar"><h3 className="card-toolbar-title">Revenue at risk — engaged billing, disengaging customers</h3></div>
          <p className="subtle-help">Internal prioritization (never a churn claim): paying MRR where health is At Risk/Inactive, payments are troubled, or cancellation is scheduled.</p>
          {r.revenueAtRisk.length === 0 ? <p className="subtle-help">No paying revenue is currently at risk.</p> : (
            <table>
              <thead><tr><th>Organization</th><th>MRR</th><th>Health</th><th>Why</th><th>Last activity</th></tr></thead>
              <tbody>
                {r.revenueAtRisk.map((o) => (
                  <tr key={o.organizationId} className="row-click" onClick={() => onOpenOrg(o.organizationId)}>
                    <td style={{ fontWeight: 600 }}>{o.organizationName || o.organizationId}</td>
                    <td className="mono" style={{ fontWeight: 700 }}>{money(o.currencyCode, o.revenueAtRisk)}</td>
                    <td><HealthBadge health={o.health} /></td>
                    <td>{o.riskReasons.join(" · ")}</td>
                    <td>{timeAgo(o.lastMeaningfulActivityAtUtc)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
        <div className="card">
          <div className="card-toolbar"><h3 className="card-toolbar-title">Revenue by vertical</h3></div>
          {r.byVertical.length === 0 ? <p className="subtle-help">No paying companies yet.</p> : (
            <table>
              <thead><tr><th>Vertical</th><th>MRR</th><th>Cos</th><th>Avg</th><th>Share</th></tr></thead>
              <tbody>
                {r.byVertical.map((v, i) => (
                  <tr key={i}>
                    <td style={{ fontWeight: 600 }}>{v.companyFamily}{v.businessTemplate ? ` · ${v.businessTemplate}` : ""}</td>
                    <td className="mono">{money(v.currencyCode, v.mrr)}</td>
                    <td className="mono">{v.companies}</td>
                    <td className="mono">{v.averagePrice === null ? "—" : money(v.currencyCode, v.averagePrice)}</td>
                    <td className="mono">{v.shareOfCurrencyMrr}%</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      <div className="report-grid">
        <div className="card">
          <div className="card-toolbar"><h3 className="card-toolbar-title">Trial intelligence</h3></div>
          <div className="family-stats" style={{ marginBottom: 10 }}>
            <span>In trial <strong>{r.trials.organizationsInTrial}</strong></span>
            <span>Ending 7d <strong>{r.trials.trialEnding7d}</strong></span>
            <span>Ending 30d <strong>{r.trials.trialEnding30d}</strong></span>
            <span>Converted this month <strong>{r.trials.convertedThisMonth}</strong></span>
            <span>Conversion rate <strong>{r.trials.trialToPaidConversionRate === null ? "—" : `${r.trials.trialToPaidConversionRate}%`}</strong></span>
            <span>Avg days to convert <strong>{r.trials.averageDaysToConversion ?? "—"}</strong></span>
          </div>
          <div className="kpi-label" style={{ marginBottom: 4 }}>Highly engaged trials, not paid (sales opportunities)</div>
          {r.trials.highEngagementTrialsNotPaid.length === 0 ? <p className="subtle-help">None right now.</p> :
            r.trials.highEngagementTrialsNotPaid.map((o) => (
              <div key={o.organizationId} className="recent-row row-click" onClick={() => onOpenOrg(o.organizationId)}>
                <div><div className="recent-name">{o.organizationName || o.organizationId}</div>
                  <div className="recent-sub">potential {money(o.currencyCode, o.netMrr)}/mo · {o.payingCompanies} companies</div></div>
                <span className="recent-ago">{timeAgo(o.lastMeaningfulActivityAtUtc)}</span>
              </div>
            ))}
          <div className="kpi-label" style={{ margin: "10px 0 4px" }}>Low-engagement trials ending soon</div>
          {r.trials.lowEngagementTrialsEndingSoon.length === 0 ? <p className="subtle-help">None right now.</p> :
            r.trials.lowEngagementTrialsEndingSoon.map((o) => (
              <div key={o.organizationId} className="recent-row row-click" onClick={() => onOpenOrg(o.organizationId)}>
                <div><div className="recent-name">{o.organizationName || o.organizationId}</div>
                  <div className="recent-sub">{o.marketCode} · {o.accountStatus}</div></div>
                <span className="recent-ago">{timeAgo(o.lastMeaningfulActivityAtUtc)}</span>
              </div>
            ))}
        </div>
        <div className="card report-wide">
          <div className="card-toolbar"><h3 className="card-toolbar-title">Upcoming renewals (30 days)</h3></div>
          {r.renewals30d.length === 0 ? <p className="subtle-help">No renewals in the next 30 days.</p> : (
            <table>
              <thead><tr><th>Organization</th><th>Renews</th><th>Cycle</th><th>Amount</th><th>Health</th><th>Payment state</th></tr></thead>
              <tbody>
                {r.renewals30d.map((x) => (
                  <tr key={x.organizationId} className="row-click" onClick={() => onOpenOrg(x.organizationId)}>
                    <td style={{ fontWeight: 600 }}>{x.organizationName || x.organizationId}</td>
                    <td>{new Date(x.renewalAtUtc).toLocaleDateString()}</td>
                    <td>{x.billingCycle}</td>
                    <td className="mono">{money(x.currencyCode, x.amount)}</td>
                    <td><HealthBadge health={x.health} /></td>
                    <td>{x.paymentState}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
          <div className="card-toolbar" style={{ marginTop: 12 }}><h3 className="card-toolbar-title">Recovered payments (30d)</h3></div>
          <MoneyList rows={r.recoveredPayments30d} />
        </div>
      </div>

      <div className="report-grid">
        <div className="card">
          <div className="card-toolbar"><h3 className="card-toolbar-title">Discount intelligence</h3></div>
          <div className="family-stats" style={{ marginBottom: 8 }}>
            <span>This month <MoneyList rows={r.discounts.grantedThisMonth} /></span>
            <span>Last 90d <MoneyList rows={r.discounts.grantedLast90d} /></span>
          </div>
          <div className="family-stats" style={{ marginBottom: 8 }}>
            <span>Auto multi-company <strong>{r.discounts.activeAutomaticMultiCompany}</strong></span>
            <span>Promotional <strong>{r.discounts.activePromotionalDiscounts}</strong></span>
            <span>Customer-specific <strong>{r.discounts.activeCustomerSpecificDiscounts}</strong></span>
          </div>
          {r.discounts.largestDiscountAccounts.length > 0 && (
            <>
              <div className="kpi-label" style={{ marginBottom: 4 }}>Largest discounts</div>
              {r.discounts.largestDiscountAccounts.map((x, i) => (
                <div key={i} className="recent-row" style={{ cursor: "default" }}>
                  <div><div className="recent-name">{x.organizationName || x.organizationId}</div>
                    <div className="recent-sub">{x.name} · {x.discountType} {x.value}{x.lastInvoicePercent != null ? ` · last invoice ${x.lastInvoicePercent}%` : ""}</div></div>
                  <span className="recent-ago">{x.endDate ? `ends ${new Date(x.endDate).toLocaleDateString()}` : "no end"}</span>
                </div>
              ))}
            </>
          )}
          {r.discounts.expiringDiscounts.length > 0 && (
            <p className="subtle-help">{r.discounts.expiringDiscounts.length} discount(s) expiring within 30 days.</p>
          )}
          <p className="subtle-help">Account credits are never counted as discounts.</p>
        </div>
        <div className="card">
          <div className="card-toolbar"><h3 className="card-toolbar-title">Credit intelligence</h3></div>
          <div className="family-stats" style={{ marginBottom: 8 }}>
            <span>Issued <MoneyList rows={r.credits.issued} /></span>
            <span>Consumed <MoneyList rows={r.credits.consumed} /></span>
            <span>Outstanding <MoneyList rows={r.credits.outstanding} /></span>
          </div>
          {r.credits.byReason.length === 0 ? <p className="subtle-help">No credits issued.</p> : (
            <table>
              <thead><tr><th>Reason</th><th>Amount</th><th>#</th></tr></thead>
              <tbody>
                {r.credits.byReason.map((x, i) => (
                  <tr key={i}><td>{x.reason}</td><td className="mono">{money(x.currencyCode, x.amount)}</td><td className="mono">{x.count}</td></tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
        <div className="card">
          <div className="card-toolbar"><h3 className="card-toolbar-title">Billing exceptions</h3></div>
          {r.exceptions.length === 0 ? <p className="subtle-help">No billing exceptions — pricing, scale, providers and invoices all look consistent.</p> : (
            <div className="recent-list">
              {r.exceptions.map((x, i) => (
                <div key={i} className="recent-row row-click" onClick={() => onOpenOrg(x.organizationId)}>
                  <div>
                    <div className="recent-name">{x.kind}{x.companyName ? ` — ${x.companyName}` : ""}</div>
                    <div className="recent-sub">{x.organizationName || x.organizationId} · {x.detail}</div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </>
  )
}
