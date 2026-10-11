// Admin portal pages in the SupportDesk-style layout: a filter toolbar
// (search + dropdown filters) over a table with avatar rows, status pills,
// row actions and a pagination footer.

import { useEffect, useMemo, useState } from "react"
import { farmApiBase, type FarmSummary } from "./api"
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
type FarmSort = "name-asc" | "name-desc" | "users-desc" | "staff-desc"

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
  const [sort, setSort] = useState<FarmSort>("name-asc")
  const [page, setPage] = useState(0)

  const filtered = useMemo(() => {
    let rows = farms
    const needle = q.trim().toLowerCase()
    if (needle) rows = rows.filter((f) => `${f.farmName || ""} ${f.farmId}`.toLowerCase().includes(needle))
    if (status === "paid") rows = rows.filter((f) => f.hasPaidSubscription === true)
    if (status === "unpaid") rows = rows.filter((f) => f.hasPaidSubscription !== true)
    const name = (f: FarmSummary) => (f.farmName || "").toLowerCase()
    rows = [...rows].sort((a, b) =>
      sort === "name-asc" ? name(a).localeCompare(name(b)) :
      sort === "name-desc" ? name(b).localeCompare(name(a)) :
      sort === "users-desc" ? b.totalUsers - a.totalUsers : b.staffCount - a.staffCount
    )
    return rows
  }, [farms, q, status, sort])

  useEffect(() => setPage(0), [q, status, sort])
  const visible = filtered.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE)

  return (
    <div className="card">
      <div className="page-filter-bar">
        <label className="filter-search">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg>
          <input type="search" placeholder="Search farm by name or ID…" value={q} onChange={(e) => setQ(e.target.value)} />
        </label>
        <select value={status} onChange={(e) => setStatus(e.target.value as typeof status)} aria-label="Subscription status">
          <option value="all">Status: All</option>
          <option value="paid">Subscribed</option>
          <option value="unpaid">Not subscribed</option>
        </select>
        <select value={sort} onChange={(e) => setSort(e.target.value as FarmSort)} aria-label="Sort">
          <option value="name-asc">Sort by: Name A–Z</option>
          <option value="name-desc">Name Z–A</option>
          <option value="users-desc">Most users</option>
          <option value="staff-desc">Most staff</option>
        </select>
      </div>
      {deleteErr && <div className="error">{deleteErr}</div>}
      <div style={{ overflowX: "auto" }}>
        <table>
          <thead>
            <tr><th>Farm</th><th>Status</th><th>Users</th><th>Staff</th><th>Actions</th></tr>
          </thead>
          <tbody>
            {visible.length === 0 ? (
              <tr><td colSpan={5} style={{ color: "#64748b" }}>No farms match this view.</td></tr>
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
