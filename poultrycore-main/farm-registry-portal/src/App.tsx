import { useCallback, useEffect, useMemo, useState } from "react"
import {
  farmApiBase,
  fetchFarms,
  fetchPlatformAuditLogs,
  login,
  loginApiBase,
  rolesFromJwt,
  type FarmAuditLogRow,
  type FarmSummary,
} from "./api"
import { hasPlatformDirectoryAccess } from "./platform-roles"
import { appendActivity, clearActivityLog, readActivityLog, type DeveloperActivity } from "./activity-log"

type Tab = "all" | "paid" | "unpaid"
type DevPage = "directory" | "audit"
type AuditSort = "time-desc" | "time-asc" | "farm-asc" | "farm-desc" | "action-asc"

const TOKEN_KEY = "frp_token"

function syncPathForAuth(hasToken: boolean) {
  if (typeof window === "undefined") return
  const path = window.location.pathname.replace(/\/$/, "") || "/"
  if (hasToken) {
    if (path === "/login") window.history.replaceState(null, "", "/")
  } else {
    if (path !== "/login") window.history.replaceState(null, "", "/login")
  }
}

export default function App() {
  const [username, setUsername] = useState("")
  const [password, setPassword] = useState("")
  const [token, setToken] = useState(() => (typeof localStorage !== "undefined" ? localStorage.getItem(TOKEN_KEY) : null))
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [farms, setFarms] = useState<FarmSummary[]>([])
  const [tab, setTab] = useState<Tab>("all")
  const [activity, setActivity] = useState<DeveloperActivity[]>([])
  const [farmAuditRows, setFarmAuditRows] = useState<FarmAuditLogRow[]>([])
  const [farmAuditErr, setFarmAuditErr] = useState<string | null>(null)
  const [farmAuditLoading, setFarmAuditLoading] = useState(false)
  const [devPage, setDevPage] = useState<DevPage>("directory")
  /** When set, audit table shows only rows for this farmId; null = all farms. */
  const [selectedAuditFarmId, setSelectedAuditFarmId] = useState<string | null>(null)
  const [auditSearch, setAuditSearch] = useState("")
  const [auditStatus, setAuditStatus] = useState<"all" | "Success" | "Failed">("all")
  const [auditActionQ, setAuditActionQ] = useState("")
  const [auditResourceQ, setAuditResourceQ] = useState("")
  const [auditDateFrom, setAuditDateFrom] = useState("")
  const [auditDateTo, setAuditDateTo] = useState("")
  const [auditSort, setAuditSort] = useState<AuditSort>("time-desc")

  useEffect(() => {
    setActivity(readActivityLog())
  }, [])

  async function loadFarmAudit(t: string) {
    if (!farmApiBase()) {
      setFarmAuditErr(null)
      setFarmAuditRows([])
      return
    }
    setFarmAuditLoading(true)
    setFarmAuditErr(null)
    try {
      const rows = await fetchPlatformAuditLogs(t)
      setFarmAuditRows(rows)
    } catch (e) {
      setFarmAuditRows([])
      setFarmAuditErr(e instanceof Error ? e.message : "Failed to load PoultryMaster audit log")
    } finally {
      setFarmAuditLoading(false)
    }
  }

  useEffect(() => {
    if (!token) return
    let cancelled = false
    ;(async () => {
      try {
        const roles = rolesFromJwt(token)
        if (!hasPlatformDirectoryAccess(roles)) {
          if (!cancelled) {
            setErr(
              "This account is not a platform developer login. Use one Identity user that has SystemAdmin or PlatformOwner (farm app accounts cannot open this site)."
            )
            appendActivity({
              actor: username || "unknown",
              action: "ACCESS_DENIED",
              details: "Token lacks SystemAdmin/PlatformOwner role.",
            })
            setActivity(readActivityLog())
            localStorage.removeItem(TOKEN_KEY)
            setToken(null)
            setFarms([])
          }
          return
        }
        const list = await fetchFarms(token)
        if (!cancelled) {
          setFarms(list)
          appendActivity({
            actor: username || localStorage.getItem("lastDeveloperUser") || "developer",
            action: "SESSION_RESTORED",
            details: `Loaded ${list.length} farms.`,
          })
          setActivity(readActivityLog())
          void loadFarmAudit(token)
        }
      } catch (e) {
        if (!cancelled) {
          const msg = e instanceof Error ? e.message : "Request failed"
          if (/401|403|Not authorized|Unauthorized|expired/i.test(msg)) {
            localStorage.removeItem(TOKEN_KEY)
            setToken(null)
          }
          setErr(msg)
          appendActivity({
            actor: username || localStorage.getItem("lastDeveloperUser") || "developer",
            action: "LOAD_FAILED",
            details: msg,
          })
          setActivity(readActivityLog())
        }
      }
    })()
    return () => {
      cancelled = true
    }
  }, [token])

  useEffect(() => {
    syncPathForAuth(!!token)
  }, [token])

  const paid = useMemo(() => farms.filter((f) => f.hasPaidSubscription === true), [farms])
  const unpaid = useMemo(() => farms.filter((f) => f.hasPaidSubscription !== true), [farms])
  const rows = tab === "paid" ? paid : tab === "unpaid" ? unpaid : farms

  async function handleLogin(e: React.FormEvent) {
    e.preventDefault()
    setErr(null)
    setBusy(true)
    try {
      const { token: t } = await login(username.trim(), password)
      const roles = rolesFromJwt(t)
      if (!hasPlatformDirectoryAccess(roles)) {
        setErr(
          "This site is only for the platform developer. Your account needs SystemAdmin or PlatformOwner on the Login API — not a normal farm owner or staff login."
        )
        appendActivity({
          actor: username.trim() || "unknown",
          action: "LOGIN_DENIED",
          details: "User authenticated but has no platform developer role.",
        })
        setActivity(readActivityLog())
        return
      }
      localStorage.setItem(TOKEN_KEY, t)
      localStorage.setItem("lastDeveloperUser", username.trim())
      setToken(t)
      setPassword("")
      const list = await fetchFarms(t)
      setFarms(list)
      appendActivity({
        actor: username.trim() || "developer",
        action: "LOGIN_SUCCESS",
        details: `Signed in and loaded ${list.length} farms.`,
      })
      setActivity(readActivityLog())
      void loadFarmAudit(t)
    } catch (e) {
      const msg = e instanceof Error ? e.message : "Login failed"
      setErr(msg)
      appendActivity({
        actor: username.trim() || "unknown",
        action: "LOGIN_FAILED",
        details: msg,
      })
      setActivity(readActivityLog())
    } finally {
      setBusy(false)
    }
  }

  async function refresh() {
    if (!token) return
    setErr(null)
    setBusy(true)
    try {
      const list = await fetchFarms(token)
      setFarms(list)
      appendActivity({
        actor: localStorage.getItem("lastDeveloperUser") || "developer",
        action: "REFRESH_DIRECTORY",
        details: `Fetched ${list.length} farms.`,
      })
      setActivity(readActivityLog())
      void loadFarmAudit(token)
    } catch (e) {
      const msg = e instanceof Error ? e.message : "Failed to load farms"
      setErr(msg)
      appendActivity({
        actor: localStorage.getItem("lastDeveloperUser") || "developer",
        action: "REFRESH_FAILED",
        details: msg,
      })
      setActivity(readActivityLog())
    } finally {
      setBusy(false)
    }
  }

  function logout() {
    appendActivity({
      actor: localStorage.getItem("lastDeveloperUser") || "developer",
      action: "LOGOUT",
      details: "Signed out from developer registry.",
    })
    setActivity(readActivityLog())
    localStorage.removeItem(TOKEN_KEY)
    setToken(null)
    setFarms([])
    setFarmAuditRows([])
    setFarmAuditErr(null)
    setTab("all")
    setDevPage("directory")
    setSelectedAuditFarmId(null)
    setAuditSearch("")
    setAuditStatus("all")
    setAuditActionQ("")
    setAuditResourceQ("")
    setAuditDateFrom("")
    setAuditDateTo("")
    setAuditSort("time-desc")
  }

  const farmsSorted = useMemo(
    () => [...farms].sort((a, b) => (a.farmName || "").localeCompare(b.farmName || "", undefined, { sensitivity: "base" })),
    [farms]
  )

  const farmNameById = useMemo(() => {
    const m = new Map<string, string>()
    for (const f of farms) {
      if (f.farmId) m.set(f.farmId.trim().toLowerCase(), (f.farmName && f.farmName.trim()) || f.farmId)
    }
    return m
  }, [farms])

  const resolveFarmName = useCallback((farmId?: string | null) => {
    if (!farmId) return "—"
    const key = farmId.trim().toLowerCase()
    return farmNameById.get(key) || "Unknown farm"
  }, [farmNameById])

  const filteredAuditRows = useMemo(() => {
    let rows = farmAuditRows
    if (selectedAuditFarmId) {
      const want = selectedAuditFarmId.trim().toLowerCase()
      rows = rows.filter((r) => (r.farmId || "").trim().toLowerCase() === want)
    }

    const q = auditSearch.trim().toLowerCase()
    if (q) {
      rows = rows.filter((r) => {
        const farmLabel = resolveFarmName(r.farmId)
        const blob = [r.userName, r.userId, r.action, r.resource, r.details, r.farmId, farmLabel]
          .filter(Boolean)
          .join(" ")
          .toLowerCase()
        return blob.includes(q)
      })
    }

    if (auditStatus !== "all") {
      rows = rows.filter((r) => (r.status || "").toLowerCase() === auditStatus.toLowerCase())
    }

    const aq = auditActionQ.trim().toLowerCase()
    if (aq) rows = rows.filter((r) => (r.action || "").toLowerCase().includes(aq))

    const rq = auditResourceQ.trim().toLowerCase()
    if (rq) rows = rows.filter((r) => (r.resource || "").toLowerCase().includes(rq))

    if (auditDateFrom) {
      const from = new Date(`${auditDateFrom}T00:00:00`)
      if (!Number.isNaN(from.getTime())) {
        rows = rows.filter((r) => {
          if (!r.timestamp) return false
          return new Date(r.timestamp) >= from
        })
      }
    }
    if (auditDateTo) {
      const to = new Date(`${auditDateTo}T23:59:59.999`)
      if (!Number.isNaN(to.getTime())) {
        rows = rows.filter((r) => {
          if (!r.timestamp) return false
          return new Date(r.timestamp) <= to
        })
      }
    }

    const sorted = [...rows]
    const farmCmp = (a: FarmAuditLogRow, b: FarmAuditLogRow) =>
      resolveFarmName(a.farmId).localeCompare(resolveFarmName(b.farmId), undefined, { sensitivity: "base" })
    if (auditSort === "time-desc") sorted.sort((a, b) => +new Date(b.timestamp || 0) - +new Date(a.timestamp || 0))
    else if (auditSort === "time-asc") sorted.sort((a, b) => +new Date(a.timestamp || 0) - +new Date(b.timestamp || 0))
    else if (auditSort === "farm-asc") sorted.sort(farmCmp)
    else if (auditSort === "farm-desc") sorted.sort((a, b) => farmCmp(b, a))
    else if (auditSort === "action-asc")
      sorted.sort((a, b) =>
        (a.action || "").localeCompare(b.action || "", undefined, { sensitivity: "base" })
      )

    return sorted
  }, [
    farmAuditRows,
    selectedAuditFarmId,
    auditSearch,
    auditStatus,
    auditActionQ,
    auditResourceQ,
    auditDateFrom,
    auditDateTo,
    auditSort,
    resolveFarmName,
  ])

  function selectFarmForAudit(farmId: string | null) {
    setSelectedAuditFarmId(farmId)
    setDevPage("audit")
  }

  let envHint: string | null = null
  try {
    loginApiBase()
  } catch {
    envHint = "Create farm-registry-portal/.env with VITE_LOGIN_API_URL=https://your-login-api.run.app"
  }

  if (envHint) {
    return (
      <div className="app-shell">
        <div className="hero">
          <h1>Developer farm registry</h1>
          <p>{envHint}</p>
        </div>
      </div>
    )
  }

  if (!token) {
    return (
      <div className="app-shell login-shell">
        <div className="login-split">
          <div className="login-illustration-panel">
            <div className="login-illustration-inner">
              <h1>Developer Registry</h1>
              <p>Farm directory and subscription tracking</p>
              <img src="/farmer-illustration.png" alt="Developer portal illustration" />
            </div>
          </div>
          <div className="login-form-panel">
            <div className="login-form-inner">
              <h2>Sign In</h2>
              <p className="login-api mono">{loginApiBase()}</p>
            <form onSubmit={handleLogin}>
              <label className="label" htmlFor="u">
                Username
              </label>
              <input id="u" autoComplete="username" value={username} onChange={(e) => setUsername(e.target.value)} />
              <label className="label" htmlFor="p">
                Password
              </label>
              <input
                id="p"
                type="password"
                autoComplete="current-password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
              />
              {err ? <div className="error">{err}</div> : null}
              <button className="primary login-primary" type="submit" disabled={busy}>
                {busy ? "Logging in..." : "Log in"}
              </button>
            </form>
            </div>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="app-shell app-shell-dashboard">
      <div className="hero page-header">
        <div>
          <h1>PoultryMaster — Developer</h1>
          <p>Farm directory &amp; audit — Login API: {loginApiBase()}</p>
        </div>
        <div className="hero-actions">
          <button type="button" className="ghost" onClick={logout}>
            Log out
          </button>
        </div>
      </div>

      <div className="stats">
        <div className="stat">
          <div className="label">Registered</div>
          <div className="value">{farms.length}</div>
        </div>
        <div className="stat paid">
          <div className="label">Subscribed</div>
          <div className="value">{paid.length}</div>
        </div>
        <div className="stat unpaid">
          <div className="label">Not subscribed</div>
          <div className="value">{unpaid.length}</div>
        </div>
      </div>

      <div className="dashboard-grid">
        <aside className="dev-sidebar" aria-label="Developer navigation">
          <div className="dev-sidebar-brand">PoultryMaster</div>
          <div className="dev-sidebar-sub">Platform developer tools — pick a page, then a farm to filter audit activity.</div>
          <nav className="dev-nav">
            <button type="button" className={devPage === "directory" ? "active" : ""} onClick={() => setDevPage("directory")}>
              Directory
            </button>
            <button type="button" className={devPage === "audit" ? "active" : ""} onClick={() => setDevPage("audit")}>
              Activity audit
            </button>
          </nav>
          <div className="dev-sidebar-section">Farms — audit filter</div>
          <button
            type="button"
            className={`dev-farm-btn${selectedAuditFarmId === null ? " active" : ""}`}
            onClick={() => selectFarmForAudit(null)}
          >
            <span className="name">All farms</span>
            <span className="id">Show every audit row</span>
          </button>
          <div className="dev-farm-list">
            {farmsSorted.map((f) => (
              <button
                key={f.farmId}
                type="button"
                className={`dev-farm-btn${selectedAuditFarmId === f.farmId ? " active" : ""}`}
                onClick={() => selectFarmForAudit(f.farmId)}
              >
                <span className="name">{f.farmName?.trim() || "Unnamed farm"}</span>
                <span className="id">{f.farmId}</span>
              </button>
            ))}
          </div>
        </aside>

        <div className="dashboard-main">
          {devPage === "directory" ? (
            <div className="card">
              <div className="card-toolbar">
                <h2 className="card-toolbar-title">Farm directory</h2>
                <button type="button" className="primary primary-inline" onClick={() => void refresh()} disabled={busy}>
                  {busy ? "Loading…" : "Refresh"}
                </button>
              </div>
              {err ? <div className="error">{err}</div> : null}
              <div className="tabs">
                <button type="button" className={tab === "all" ? "active" : ""} onClick={() => setTab("all")}>
                  All ({farms.length})
                </button>
                <button
                  type="button"
                  className={tab === "paid" ? "active" : ""}
                  onClick={() => {
                    setTab("paid")
                    appendActivity({
                      actor: localStorage.getItem("lastDeveloperUser") || "developer",
                      action: "TAB_CHANGE",
                      details: "Switched to Paid tab.",
                    })
                    setActivity(readActivityLog())
                  }}
                >
                  Paid ({paid.length})
                </button>
                <button
                  type="button"
                  className={tab === "unpaid" ? "active" : ""}
                  onClick={() => {
                    setTab("unpaid")
                    appendActivity({
                      actor: localStorage.getItem("lastDeveloperUser") || "developer",
                      action: "TAB_CHANGE",
                      details: "Switched to Unpaid tab.",
                    })
                    setActivity(readActivityLog())
                  }}
                >
                  Unpaid ({unpaid.length})
                </button>
              </div>
              <p className="subtle-help">Click a farm in the sidebar to jump to Activity audit filtered to that farm.</p>
              <div style={{ overflowX: "auto" }}>
                <table>
                  <thead>
                    <tr>
                      <th>Farm</th>
                      <th>Farm ID</th>
                      <th>Subscription</th>
                      <th>Users</th>
                      <th>Staff</th>
                      <th />
                    </tr>
                  </thead>
                  <tbody>
                    {rows.length === 0 ? (
                      <tr>
                        <td colSpan={6} style={{ color: "#64748b" }}>
                          No farms in this view.
                        </td>
                      </tr>
                    ) : (
                      rows.map((f) => (
                        <tr key={f.farmId}>
                          <td style={{ fontWeight: 600 }}>{f.farmName || "—"}</td>
                          <td className="mono">{f.farmId}</td>
                          <td>
                            {f.hasPaidSubscription === true ? (
                              <span className="badge badge-yes">Subscribed</span>
                            ) : (
                              <span className="badge badge-no">Not subscribed</span>
                            )}
                          </td>
                          <td>{f.totalUsers}</td>
                          <td>{f.staffCount}</td>
                          <td>
                            <button type="button" className="primary primary-inline" onClick={() => selectFarmForAudit(f.farmId)}>
                              Audit
                            </button>
                          </td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          ) : (
            <div className="card">
              <div className="card-toolbar">
                <h2 className="card-toolbar-title">PoultryMaster activity</h2>
                <button
                  type="button"
                  className="primary primary-inline"
                  onClick={() => token && void loadFarmAudit(token)}
                  disabled={busy || farmAuditLoading || !farmApiBase()}
                >
                  {farmAuditLoading ? "Loading…" : "Refresh audit"}
                </button>
              </div>
              <p className="subtle-help">
                {selectedAuditFarmId ? (
                  <>
                    Showing audit for: <strong>{resolveFarmName(selectedAuditFarmId)}</strong>
                    <span className="mono"> ({selectedAuditFarmId})</span>
                  </>
                ) : (
                  <>Showing audit for <strong>all farms</strong>.</>
                )}{" "}
                Live <code className="mono">dbo.AuditLogs</code> via Farm API. Requires <code className="mono">VITE_FARM_API_URL</code> and{" "}
                <strong>SystemAdmin</strong> or <strong>PlatformOwner</strong>.
              </p>
              {!farmApiBase() ? (
                <p className="subtle-help" style={{ marginTop: 8 }}>
                  Set <code className="mono">VITE_FARM_API_URL</code> on build, redeploy the portal, and sign in again.
                </p>
              ) : null}
              {farmAuditErr ? <div className="error">{farmAuditErr}</div> : null}

              <div className="audit-filters" aria-label="Audit log filters and sort">
                <div className="audit-filters-row">
                  <label className="audit-filter-label">
                    Search
                    <input
                      type="search"
                      className="audit-filter-input"
                      placeholder="User, action, resource, details, farm…"
                      value={auditSearch}
                      onChange={(e) => setAuditSearch(e.target.value)}
                    />
                  </label>
                  <label className="audit-filter-label">
                    Status
                    <select className="audit-filter-input" value={auditStatus} onChange={(e) => setAuditStatus(e.target.value as typeof auditStatus)}>
                      <option value="all">All</option>
                      <option value="Success">Success</option>
                      <option value="Failed">Failed</option>
                    </select>
                  </label>
                  <label className="audit-filter-label">
                    Sort
                    <select className="audit-filter-input" value={auditSort} onChange={(e) => setAuditSort(e.target.value as AuditSort)}>
                      <option value="time-desc">Newest first</option>
                      <option value="time-asc">Oldest first</option>
                      <option value="farm-asc">Farm A–Z</option>
                      <option value="farm-desc">Farm Z–A</option>
                      <option value="action-asc">Action A–Z</option>
                    </select>
                  </label>
                </div>
                <div className="audit-filters-row">
                  <label className="audit-filter-label">
                    Action contains
                    <input
                      className="audit-filter-input"
                      placeholder="e.g. POST"
                      value={auditActionQ}
                      onChange={(e) => setAuditActionQ(e.target.value)}
                    />
                  </label>
                  <label className="audit-filter-label">
                    Resource contains
                    <input
                      className="audit-filter-input"
                      placeholder="e.g. Sale"
                      value={auditResourceQ}
                      onChange={(e) => setAuditResourceQ(e.target.value)}
                    />
                  </label>
                  <label className="audit-filter-label">
                    From date
                    <input className="audit-filter-input" type="date" value={auditDateFrom} onChange={(e) => setAuditDateFrom(e.target.value)} />
                  </label>
                  <label className="audit-filter-label">
                    To date
                    <input className="audit-filter-input" type="date" value={auditDateTo} onChange={(e) => setAuditDateTo(e.target.value)} />
                  </label>
                  <div className="audit-filter-actions">
                    <button
                      type="button"
                      className="audit-filter-reset"
                      onClick={() => {
                        setAuditSearch("")
                        setAuditStatus("all")
                        setAuditActionQ("")
                        setAuditResourceQ("")
                        setAuditDateFrom("")
                        setAuditDateTo("")
                        setAuditSort("time-desc")
                      }}
                    >
                      Reset filters
                    </button>
                  </div>
                </div>
                <p className="audit-filter-meta subtle-help" style={{ marginBottom: 0 }}>
                  {farmAuditLoading
                    ? "Loading…"
                    : `Showing ${filteredAuditRows.length} of ${farmAuditRows.length} loaded row${farmAuditRows.length === 1 ? "" : "s"}.`}
                </p>
              </div>

              <div style={{ overflowX: "auto" }}>
                <table>
                  <thead>
                    <tr>
                      <th>Time (UTC)</th>
                      <th>Farm</th>
                      <th>Farm ID</th>
                      <th>User</th>
                      <th>Action</th>
                      <th>Resource</th>
                      <th>Status</th>
                      <th>Details</th>
                    </tr>
                  </thead>
                  <tbody>
                    {farmAuditLoading && farmAuditRows.length === 0 ? (
                      <tr>
                        <td colSpan={8} style={{ color: "#64748b" }}>
                          Loading audit log…
                        </td>
                      </tr>
                    ) : filteredAuditRows.length === 0 ? (
                      <tr>
                        <td colSpan={8} style={{ color: "#64748b" }}>
                          {farmApiBase()
                            ? selectedAuditFarmId
                              ? "No audit rows for this farm yet (or none in the last fetch)."
                              : farmAuditRows.length === 0
                                ? "No rows returned."
                                : "No rows match this filter."
                            : "—"}
                        </td>
                      </tr>
                    ) : (
                      filteredAuditRows.map((r) => (
                        <tr key={r.id}>
                          <td className="mono">
                            {r.timestamp ? new Date(r.timestamp).toISOString().replace("T", " ").slice(0, 19) : "—"}
                          </td>
                          <td style={{ fontWeight: 600 }}>{resolveFarmName(r.farmId)}</td>
                          <td className="mono" style={{ maxWidth: 100, overflow: "hidden", textOverflow: "ellipsis" }}>
                            {r.farmId || "—"}
                          </td>
                          <td>{r.userName || r.userId || "—"}</td>
                          <td>{r.action}</td>
                          <td>{r.resource}</td>
                          <td>{r.status}</td>
                          <td style={{ maxWidth: 240, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                            {r.details || "—"}
                          </td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          <div className="card">
        <div className="card-toolbar">
          <h2 className="card-toolbar-title">Developer Activity Log</h2>
          <button
            type="button"
            className="primary primary-inline"
            onClick={() => {
              clearActivityLog()
              setActivity([])
            }}
            disabled={activity.length === 0}
          >
            Clear
          </button>
        </div>
        <p className="subtle-help">
          Local audit trail for this browser session history on your developer account.
        </p>
        <div style={{ overflowX: "auto" }}>
          <table>
            <thead>
              <tr>
                <th>Time</th>
                <th>Actor</th>
                <th>Action</th>
                <th>Details</th>
              </tr>
            </thead>
            <tbody>
              {activity.length === 0 ? (
                <tr>
                  <td colSpan={4} style={{ color: "#64748b" }}>
                    No developer activity yet.
                  </td>
                </tr>
              ) : (
                activity.map((item) => (
                  <tr key={item.id}>
                    <td className="mono">{new Date(item.at).toLocaleString()}</td>
                    <td>{item.actor}</td>
                    <td>{item.action}</td>
                    <td>{item.details || "—"}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
          </div>
        </div>
      </div>
    </div>
  )
}
