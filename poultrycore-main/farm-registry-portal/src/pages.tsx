// Admin portal pages in the SupportDesk-style layout: a filter toolbar
// (search + dropdown filters) over a table with avatar rows, status pills,
// row actions and a pagination footer.

import { useEffect, useMemo, useState } from "react"
import { farmApiBase, fetchFarmDetail, setUserTwoFactor, type FarmDetail, type FarmPerson, type FarmSummary } from "./api"
import { billingConfig, billingGet, billingSend, userIdFromJwt } from "./billing-api"

const PAGE_SIZE = 10

export function initials(name?: string | null): string {
  const v = (name || "").trim()
  if (!v) return "–"
  const parts = v.split(/\s+/)
  return ((parts[0]?.[0] || "") + (parts[1]?.[0] || parts[0]?.[1] || "")).toUpperCase()
}

function Pager({ page, total, onPage }: { page: number; total: number; onPage: (p: number) => void }) {
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE))
  const from = total === 0 ? 0 : page * PAGE_SIZE + 1
  const to = Math.min(total, (page + 1) * PAGE_SIZE)
  const nums: number[] = []
  for (let i = Math.max(0, page - 1); i < Math.min(pages, Math.max(3, page + 2)); i++) nums.push(i)
  return (
    <div className="pager">
      <span className="pager-info">Showing {from} to {to} of {total}</span>
      <div className="pager-controls">
        <button type="button" disabled={page === 0} onClick={() => onPage(page - 1)} aria-label="Previous page">‹</button>
        {nums.map((n) => (
          <button key={n} type="button" className={n === page ? "active" : ""} onClick={() => onPage(n)}>{n + 1}</button>
        ))}
        <button type="button" disabled={page >= pages - 1} onClick={() => onPage(page + 1)} aria-label="Next page">›</button>
      </div>
    </div>
  )
}

// ---------------------------------------------------------------- Farms
type SortKey = "name" | "email" | "phone" | "joined" | "users" | "staff"
type SortDir = "asc" | "desc"

function joinedTime(f: FarmSummary): number {
  const t = f.createdAt ? Date.parse(f.createdAt) : NaN
  return Number.isNaN(t) ? 0 : t
}
function joinedLabel(f: FarmSummary): string {
  const t = joinedTime(f)
  if (!t) return "—"
  const d = new Date(t)
  const days = Math.floor((Date.now() - t) / 86400000)
  const ago = days <= 0 ? "today" : days === 1 ? "1 day ago" : days < 30 ? `${days} days ago` : days < 365 ? `${Math.floor(days / 30)} mo ago` : `${Math.floor(days / 365)} yr ago`
  return `${d.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" })} · ${ago}`
}

export function FarmsPage({ farms, onAudit, token, onDeleted }: {
  farms: FarmSummary[]; onAudit: (farmId: string) => void; token: string; onDeleted: () => void
}) {
  const [deleting, setDeleting] = useState<string | null>(null)
  const [deleteErr, setDeleteErr] = useState<string | null>(null)

  async function deleteFarm(f: FarmSummary) {
    const name = (f.farmName || "").trim()
    const typed = window.prompt(
      `PERMANENTLY delete "${name || "this farm"}" and ALL of its data (sales, stock, employees' access, billing state)?

` +
      `This cannot be undone. Type the exact farm name to confirm:`
    )
    if (typed === null) return
    setDeleteErr(null)
    setDeleting(f.farmId)
    try {
      const res = await fetch(
        `${farmApiBase()}/api/PlatformFarms/${encodeURIComponent(f.farmId)}?confirmName=${encodeURIComponent(typed.trim())}`,
        { method: "DELETE", headers: { Authorization: `Bearer ${token}`, Accept: "application/json" } }
      )
      const data = (await res.json().catch(() => ({}))) as { ok?: boolean; message?: string }
      if (!res.ok || data.ok === false) {
        setDeleteErr(data.message || `Delete failed (${res.status}).`)
        return
      }
      onDeleted()
    } catch (e) {
      setDeleteErr(e instanceof Error ? e.message : "Delete failed.")
    } finally {
      setDeleting(null)
    }
  }

  const [q, setQ] = useState("")
  const [status, setStatus] = useState<"all" | "paid" | "unpaid">("all")
  const [contact, setContact] = useState<"all" | "has-email" | "has-phone" | "missing">("all")
  const [signedUp, setSignedUp] = useState<"all" | "7" | "30" | "90">("all")
  const [sortKey, setSortKey] = useState<SortKey>("name")
  const [sortDir, setSortDir] = useState<SortDir>("asc")
  const [page, setPage] = useState(0)

  function toggleSort(k: SortKey) {
    if (k === sortKey) { setSortDir((d) => (d === "asc" ? "desc" : "asc")); return }
    setSortKey(k)
    setSortDir(k === "users" || k === "staff" || k === "joined" ? "desc" : "asc")
  }

  // "Most recent signups": one click sorts the whole list newest-first.
  function showNewest() { setSortKey("joined"); setSortDir("desc") }

  const filtered = useMemo(() => {
    let rows = farms
    const needle = q.trim().toLowerCase()
    if (needle) rows = rows.filter((f) => `${f.farmName || ""} ${f.farmId} ${f.email || ""} ${f.phoneNumber || ""}`.toLowerCase().includes(needle))
    if (status === "paid") rows = rows.filter((f) => f.hasPaidSubscription === true)
    if (status === "unpaid") rows = rows.filter((f) => f.hasPaidSubscription !== true)
    const hasEmail = (f: FarmSummary) => !!(f.email && f.email.trim())
    const hasPhone = (f: FarmSummary) => !!(f.phoneNumber && f.phoneNumber.trim())
    if (contact === "has-email") rows = rows.filter(hasEmail)
    if (contact === "has-phone") rows = rows.filter(hasPhone)
    if (contact === "missing") rows = rows.filter((f) => !hasEmail(f) || !hasPhone(f))
    if (signedUp !== "all") {
      const cutoff = Date.now() - Number(signedUp) * 86400000
      rows = rows.filter((f) => joinedTime(f) >= cutoff)
    }
    const s = (v?: string | null) => (v || "").toLowerCase()
    const cmp = (a: FarmSummary, b: FarmSummary) => {
      let r = 0
      if (sortKey === "name") r = s(a.farmName).localeCompare(s(b.farmName))
      else if (sortKey === "email") r = s(a.email).localeCompare(s(b.email))
      else if (sortKey === "phone") r = s(a.phoneNumber).localeCompare(s(b.phoneNumber))
      else if (sortKey === "joined") r = joinedTime(a) - joinedTime(b)
      else if (sortKey === "users") r = a.totalUsers - b.totalUsers
      else r = a.staffCount - b.staffCount
      return sortDir === "asc" ? r : -r
    }
    return [...rows].sort(cmp)
  }, [farms, q, status, contact, signedUp, sortKey, sortDir])

  useEffect(() => setPage(0), [q, status, contact, signedUp, sortKey, sortDir])
  const visible = filtered.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE)
  const arrow = (k: SortKey) => (sortKey === k ? (sortDir === "asc" ? " ▲" : " ▼") : "")

  return (
    <div className="card">
      <div className="page-filter-bar">
        <label className="filter-search">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg>
          <input type="search" placeholder="Search name, ID, email or phone…" value={q} onChange={(e) => setQ(e.target.value)} />
        </label>
        <select value={status} onChange={(e) => setStatus(e.target.value as typeof status)} aria-label="Subscription status">
          <option value="all">Status: All</option>
          <option value="paid">Subscribed</option>
          <option value="unpaid">Not subscribed</option>
        </select>
        <select value={contact} onChange={(e) => setContact(e.target.value as typeof contact)} aria-label="Contact details">
          <option value="all">Contact: All</option>
          <option value="has-email">Has email</option>
          <option value="has-phone">Has phone</option>
          <option value="missing">Missing contact</option>
        </select>
        <select value={signedUp} onChange={(e) => setSignedUp(e.target.value as typeof signedUp)} aria-label="Signed up">
          <option value="all">Signed up: Any time</option>
          <option value="7">Last 7 days</option>
          <option value="30">Last 30 days</option>
          <option value="90">Last 90 days</option>
        </select>
        <button type="button" className="link-btn" onClick={showNewest} title="Sort by newest signups">↓ Newest signups</button>
      </div>
      {deleteErr && <div className="error">{deleteErr}</div>}
      <div style={{ overflowX: "auto" }}>
        <table>
          <thead>
            <tr>
              <th onClick={() => toggleSort("name")} style={{ cursor: "pointer", userSelect: "none" }} title="Click to sort">Farm{arrow("name")}</th>
              <th onClick={() => toggleSort("email")} style={{ cursor: "pointer", userSelect: "none" }} title="Click to sort">Email{arrow("email")}</th>
              <th onClick={() => toggleSort("phone")} style={{ cursor: "pointer", userSelect: "none" }} title="Click to sort">Phone{arrow("phone")}</th>
              <th onClick={() => toggleSort("joined")} style={{ cursor: "pointer", userSelect: "none" }} title="Click to sort by signup date">Joined{arrow("joined")}</th>
              <th>Status</th>
              <th onClick={() => toggleSort("users")} style={{ cursor: "pointer", userSelect: "none" }} title="Click to sort">Users{arrow("users")}</th>
              <th onClick={() => toggleSort("staff")} style={{ cursor: "pointer", userSelect: "none" }} title="Click to sort">Staff{arrow("staff")}</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {visible.length === 0 ? (
              <tr><td colSpan={8} style={{ color: "#64748b" }}>No farms match this view.</td></tr>
            ) : visible.map((f) => (
              <tr key={f.farmId}>
                <td>
                  <div className="row-entity">
                    <span className="row-avatar">{initials(f.farmName)}</span>
                    <div>
                      <div className="row-name">{f.farmName || "Unnamed farm"}</div>
                      <div className="row-sub">{f.hasPaidSubscription ? "Subscribed" : "Free account"}</div>
                    </div>
                  </div>
                </td>
                <td>{f.email ? <a href={`mailto:${f.email}`}>{f.email}</a> : <span style={{ color: "#94a3b8" }}>—</span>}</td>
                <td>{f.phoneNumber ? <a href={`tel:${f.phoneNumber}`}>{f.phoneNumber}</a> : <span style={{ color: "#94a3b8" }}>—</span>}</td>
                <td style={{ whiteSpace: "nowrap", color: "#475569" }}>{joinedLabel(f)}</td>
                <td>{f.hasPaidSubscription === true
                  ? <span className="badge badge-yes">Subscribed</span>
                  : <span className="badge badge-no">Unpaid</span>}</td>
                <td>{f.totalUsers}</td>
                <td>{f.staffCount}</td>
                <td>
                  <button type="button" className="link-btn" onClick={() => onAudit(f.farmId)}>Audit</button>
                  <button type="button" className="link-btn link-danger" disabled={deleting === f.farmId}
                    onClick={() => void deleteFarm(f)}>
                    {deleting === f.farmId ? "Deleting…" : "Delete"}
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <Pager page={page} total={filtered.length} onPage={setPage} />
    </div>
  )
}

// ---------------------------------------------------------------- Farm audit detail
function fullName(p: FarmPerson): string {
  const n = `${p.firstName || ""} ${p.lastName || ""}`.trim()
  return n || p.userName || p.email || "—"
}

/**
 * Developer-side audit panel for one farm: farm fields, the owner account and
 * every employee — each with their two-factor state and a one-click override to
 * switch 2FA off (e.g. a customer who turned it on and can no longer receive the
 * OTP email). Shown above the raw audit trail when a farm is selected.
 */
export function FarmDetailPanel({ token, farmId }: { token: string; farmId: string }) {
  const [detail, setDetail] = useState<FarmDetail | null>(null)
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)
  const [busyUser, setBusyUser] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)

  async function load() {
    setLoading(true)
    setErr(null)
    try {
      setDetail(await fetchFarmDetail(token, farmId))
    } catch (e) {
      setErr(e instanceof Error ? e.message : "Failed to load farm detail.")
    } finally {
      setLoading(false)
    }
  }
  useEffect(() => { void load() }, [token, farmId]) // eslint-disable-line react-hooks/exhaustive-deps

  async function toggle2fa(p: FarmPerson, enabled: boolean) {
    setNotice(null)
    setErr(null)
    setBusyUser(p.userId)
    try {
      const result = await setUserTwoFactor(token, p.userId, enabled)
      setDetail((d) => {
        if (!d) return d
        const apply = (x: FarmPerson): FarmPerson => (x.userId === p.userId ? { ...x, twoFactorEnabled: result } : x)
        return { ...d, owner: d.owner ? apply(d.owner) : d.owner, employees: d.employees.map(apply) }
      })
      setNotice(`Two-factor ${result ? "enabled" : "turned off"} for ${p.userName || fullName(p)}.`)
    } catch (e) {
      setErr(e instanceof Error ? e.message : "Failed to update 2FA.")
    } finally {
      setBusyUser(null)
    }
  }

  function Pill({ on }: { on: boolean }) {
    return <span className={on ? "badge badge-yes" : "badge badge-no"}>{on ? "2FA ON" : "2FA off"}</span>
  }

  function ToggleBtn({ p }: { p: FarmPerson }) {
    const busy = busyUser === p.userId
    return p.twoFactorEnabled ? (
      <button type="button" className="link-btn link-danger" disabled={busy} onClick={() => void toggle2fa(p, false)}>
        {busy ? "Saving…" : "Turn off 2FA"}
      </button>
    ) : (
      <button type="button" className="link-btn" disabled={busy} onClick={() => void toggle2fa(p, true)}>
        {busy ? "Saving…" : "Turn on 2FA"}
      </button>
    )
  }

  return (
    <div className="card">
      <div className="card-toolbar">
        <h2 className="card-toolbar-title">Farm detail</h2>
        <button type="button" className="primary primary-inline" onClick={() => void load()} disabled={loading}>
          {loading ? "Loading…" : "Refresh"}
        </button>
      </div>

      {err && <div className="error">{err}</div>}
      {notice && <p className="billing-notice">{notice}</p>}

      {loading && !detail ? (
        <p className="subtle-help">Loading farm detail…</p>
      ) : !detail ? (
        <p className="subtle-help">No detail available.</p>
      ) : (
        <>
          <div className="settings-grid">
            <div className="setting-tile"><div className="setting-name">Farm</div><div className="setting-desc">{detail.farmName || "Unnamed farm"}</div></div>
            <div className="setting-tile"><div className="setting-name">Type</div><div className="setting-desc">{detail.type || "—"}</div></div>
            <div className="setting-tile"><div className="setting-name">Contact email</div><div className="setting-desc">{detail.email || "—"}</div></div>
            <div className="setting-tile"><div className="setting-name">Phone</div><div className="setting-desc">{detail.phoneNumber || "—"}</div></div>
            <div className="setting-tile"><div className="setting-name">Farm ID</div><div className="setting-desc mono">{detail.farmId}</div></div>
          </div>

          <h3 className="card-toolbar-title" style={{ marginTop: 18 }}>Owner</h3>
          {detail.owner ? (
            <div className="row-entity" style={{ justifyContent: "space-between", flexWrap: "wrap", gap: 12 }}>
              <div className="row-entity">
                <span className="row-avatar">{initials(fullName(detail.owner))}</span>
                <div>
                  <div className="row-name">{fullName(detail.owner)} <span className="mono" style={{ color: "#64748b" }}>@{detail.owner.userName || "—"}</span></div>
                  <div className="row-sub">{detail.owner.email || "no email on file"}{detail.owner.emailConfirmed ? "" : " · email unconfirmed"}</div>
                </div>
              </div>
              <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                <Pill on={detail.owner.twoFactorEnabled} />
                <ToggleBtn p={detail.owner} />
              </div>
            </div>
          ) : (
            <p className="subtle-help">No owner account found for this farm.</p>
          )}

          <h3 className="card-toolbar-title" style={{ marginTop: 18 }}>Employees ({detail.employees.length})</h3>
          <div style={{ overflowX: "auto" }}>
            <table>
              <thead>
                <tr><th>Name</th><th>Username</th><th>Email</th><th>Role</th><th>2FA</th><th>Actions</th></tr>
              </thead>
              <tbody>
                {detail.employees.length === 0 ? (
                  <tr><td colSpan={6} style={{ color: "#64748b" }}>No employees under this farm.</td></tr>
                ) : detail.employees.map((e) => (
                  <tr key={e.userId}>
                    <td style={{ fontWeight: 600 }}>{fullName(e)}</td>
                    <td className="mono">{e.userName || "—"}</td>
                    <td>{e.email || "—"}{e.emailConfirmed ? "" : <span className="row-sub"> (unconfirmed)</span>}</td>
                    <td>{e.role}</td>
                    <td><Pill on={e.twoFactorEnabled} /></td>
                    <td><ToggleBtn p={e} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
    </div>
  )
}

// ---------------------------------------------------------------- Customers (billing organizations)
type OrgRow = {
  accountId: number
  ownerUserId: string
  ownerName?: string | null
  ownerEmail?: string | null
  orgCode?: string | null
  marketCode: string
  currencyCode: string
  status: string
  companyCount: number
}

export function CustomersPage({ token, onInspect }: { token: string; onInspect: (ownerUserId: string) => void }) {
  const userId = userIdFromJwt(token) ?? ""
  const [q, setQ] = useState("")
  const [rows, setRows] = useState<OrgRow[]>([])
  const [err, setErr] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [page, setPage] = useState(0)

  async function load(search: string) {
    setLoading(true)
    setErr(null)
    try {
      setRows(await billingGet<OrgRow[]>(token, userId, `organizations?search=${encodeURIComponent(search)}`))
    } catch (e) {
      setErr(e instanceof Error ? e.message : "Failed to load organizations.")
    } finally {
      setLoading(false)
    }
  }
  useEffect(() => { void load("") }, []) // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => setPage(0), [rows])

  const visible = rows.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE)
  const statusPill = (s: string) =>
    s === "Active" ? "badge badge-yes" : s === "Trial" ? "badge badge-trial" : "badge badge-no"

  return (
    <div className="card">
      <div className="page-filter-bar">
        <label className="filter-search">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg>
          <input
            type="search" placeholder="Search by owner email, name or org code…" value={q}
            onChange={(e) => setQ(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && void load(q)}
          />
        </label>
        <button type="button" className="admin-btn-ghost" onClick={() => void load(q)} disabled={loading}>
          {loading ? "Loading…" : "Search"}
        </button>
      </div>
      {err && <div className="error">{err}</div>}
      <div style={{ overflowX: "auto" }}>
        <table>
          <thead>
            <tr><th>Organization</th><th>Org code</th><th>Market</th><th>Companies</th><th>Status</th><th>Actions</th></tr>
          </thead>
          <tbody>
            {visible.length === 0 ? (
              <tr><td colSpan={6} style={{ color: "#64748b" }}>{loading ? "Loading organizations…" : "No billed organizations found."}</td></tr>
            ) : visible.map((o) => (
              <tr key={o.accountId}>
                <td>
                  <div className="row-entity">
                    <span className="row-avatar">{initials(o.ownerName || o.ownerEmail)}</span>
                    <div>
                      <div className="row-name">{o.ownerName || "—"}</div>
                      <div className="row-sub">{o.ownerEmail || "no email on file"}</div>
                    </div>
                  </div>
                </td>
                <td className="mono">{o.orgCode || "—"}</td>
                <td>{o.marketCode} · {o.currencyCode}</td>
                <td>{o.companyCount}</td>
                <td><span className={statusPill(o.status)}>{o.status}</span></td>
                <td><button type="button" className="link-btn" onClick={() => onInspect(o.ownerUserId)}>Billing</button></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <Pager page={page} total={rows.length} onPage={setPage} />
    </div>
  )
}

// ---------------------------------------------------------------- Settings
type SettingRow = { key: string; value: unknown; description?: string }

function SectionHead({ icon, title }: { icon: React.ReactNode; title: string }) {
  return (
    <div className="section-head">
      <span className="section-chip">{icon}</span>
      <h3>{title}</h3>
    </div>
  )
}

function Toggle({ on, onChange, disabled }: { on: boolean; onChange: (v: boolean) => void; disabled?: boolean }) {
  return (
    <button type="button" role="switch" aria-checked={on} disabled={disabled}
      className={`toggle${on ? " on" : ""}`} onClick={() => onChange(!on)}>
      <span className="knob" />
    </button>
  )
}

function isBoolish(v: string): boolean {
  return v === "true" || v === "false" || v === "1" || v === "0"
}
function asBool(v: string): boolean {
  return v === "true" || v === "1"
}

export function SettingsPage({ token, actor, roles }: { token: string; actor: string; roles: string[] }) {
  const userId = userIdFromJwt(token) ?? ""
  const [settings, setSettings] = useState<SettingRow[]>([])
  const [edits, setEdits] = useState<Record<string, string>>({})
  const [err, setErr] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  async function load() {
    setLoading(true)
    setErr(null)
    try {
      const cfg = await billingConfig(token, userId)
      setSettings((cfg.settings ?? []) as unknown as SettingRow[])
      setEdits({})
    } catch (e) {
      setErr(e instanceof Error ? e.message : "Failed to load settings.")
    } finally {
      setLoading(false)
    }
  }
  useEffect(() => { void load() }, []) // eslint-disable-line react-hooks/exhaustive-deps

  async function save(key: string, value: string) {
    setNotice(null)
    const r = await billingSend(token, userId, "PUT", "setting", { key, value })
    if (r.ok) { setNotice(r.message || `Saved ${key}.`); void load() } else setErr(r.message || "Not saved.")
  }

  const toggles = settings.filter((s) => isBoolish(String(s.value)))
  const texts = settings.filter((s) => !isBoolish(String(s.value)))

  return (
    <>
      <div className="card">
        <SectionHead title="Account"
          icon={<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="8" r="4"/><path d="M4 21c0-4 3.6-6 8-6s8 2 8 6"/></svg>} />
        <div className="settings-grid">
          <div className="setting-tile">
            <div className="setting-name">Signed in as</div>
            <div className="setting-desc">{actor}</div>
          </div>
          <div className="setting-tile">
            <div className="setting-name">Roles</div>
            <div className="setting-desc">{roles.join(", ") || "—"}</div>
          </div>
        </div>
      </div>

      <div className="card">
        <SectionHead title="Platform switches"
          icon={<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3"/><path d="M1 14h6M9 8h6M17 16h6"/></svg>} />
        {err && <div className="error">{err}</div>}
        {notice && <p className="billing-notice">{notice}</p>}
        <div className="settings-grid">
          {toggles.map((s) => (
            <div key={s.key} className="setting-tile">
              <div>
                <div className="setting-name mono">{s.key}</div>
                {s.description && <div className="setting-desc">{s.description}</div>}
              </div>
              <Toggle on={asBool(String(s.value))} disabled={loading}
                onChange={(v) => void save(s.key, v ? "true" : "false")} />
            </div>
          ))}
          {toggles.length === 0 && <p className="subtle-help">{loading ? "Loading…" : "No boolean switches configured."}</p>}
        </div>
      </div>

      <div className="card">
        <SectionHead title="Platform values"
          icon={<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/></svg>} />
        <div style={{ overflowX: "auto" }}>
          <table>
            <thead><tr><th>Setting</th><th>Value</th><th>Actions</th></tr></thead>
            <tbody>
              {texts.length === 0 ? (
                <tr><td colSpan={3} style={{ color: "#64748b" }}>{loading ? "Loading…" : "No value settings."}</td></tr>
              ) : texts.map((s) => {
                const current = edits[s.key] ?? String(s.value)
                const dirty = current !== String(s.value)
                return (
                  <tr key={s.key}>
                    <td>
                      <div className="row-name mono">{s.key}</div>
                      {s.description && <div className="row-sub">{s.description}</div>}
                    </td>
                    <td><input className="audit-filter-input" value={current}
                      onChange={(e) => setEdits({ ...edits, [s.key]: e.target.value })} /></td>
                    <td><button type="button" className="link-btn" disabled={!dirty} onClick={() => void save(s.key, current)}>Save</button></td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      </div>
    </>
  )
}
