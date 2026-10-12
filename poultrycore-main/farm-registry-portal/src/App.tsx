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
import BillingAdmin, { BILLING_SECTIONS, type Section as BillingSection } from "./BillingAdmin"
import { CustomersPage, FarmsPage, SettingsPage } from "./pages"
import { ReportsPage } from "./reports"
import { PlatformDashboard } from "./platform-dashboard"
import { CustomerIntelligencePage } from "./customer-intelligence"
import { CustomerSuccessPage } from "./customer-success"
import { AnalyticsPage } from "./analytics"
import { RevenuePage } from "./revenue"
import { OperationsPage } from "./operations"
import { fetchRevenueDashboard, type RevenueDashboard } from "./platform-activity-api"
import { fetchOrganizations, type OrganizationSummary } from "./platform-activity-api"
import { appendActivity, clearActivityLog, readActivityLog, type DeveloperActivity } from "./activity-log"

type DevPage = "dashboard" | "intel" | "success" | "analytics" | "revenue" | "operations" | "farms" | "customers" | "audit" | "reports" | "billing" | "settings"

const DEV_PAGES: DevPage[] = ["dashboard", "intel", "success", "analytics", "revenue", "operations", "farms", "customers", "audit", "reports", "billing", "settings"]

/** Deep links: #/page?k=v so dashboards, directory focus and audit filters survive reload/sharing. */
function readHash(): { page: DevPage | null; params: URLSearchParams } {
  if (typeof window === "undefined") return { page: null, params: new URLSearchParams() }
  const h = window.location.hash.replace(/^#\/?/, "")
  const [p, qs] = h.split("?")
  const page = (DEV_PAGES as string[]).includes(p) ? (p as DevPage) : null
  return { page, params: new URLSearchParams(qs || "") }
}
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
  const [activity, setActivity] = useState<DeveloperActivity[]>([])
  const [farmAuditRows, setFarmAuditRows] = useState<FarmAuditLogRow[]>([])
  const [farmAuditErr, setFarmAuditErr] = useState<string | null>(null)
  const [farmAuditLoading, setFarmAuditLoading] = useState(false)
  const [devPage, setDevPage] = useState<DevPage>(() => readHash().page ?? "dashboard")
  const [orgs, setOrgs] = useState<OrganizationSummary[]>([])
  const [orgsLoading, setOrgsLoading] = useState(false)
  const [orgsErr, setOrgsErr] = useState<string | null>(null)
  const [intelView, setIntelView] = useState<"orgs" | "companies">(() => (readHash().params.get("view") === "companies" ? "companies" : "orgs"))
  const [intelFocusOrg, setIntelFocusOrg] = useState<string | null>(() => readHash().params.get("org"))
  const [intelFocusCompany, setIntelFocusCompany] = useState<string | null>(() => readHash().params.get("company"))
  const [auditFamily, setAuditFamily] = useState("")
  const [revenue, setRevenue] = useState<RevenueDashboard | null>(null)
  const [auditOrg, setAuditOrg] = useState("")
  /** Owner picked on the Customers page; opens pre-loaded in Billing → Organizations. */
  const [billingOwner, setBillingOwner] = useState<string | null>(null)
  const [billingSection, setBillingSection] = useState<BillingSection>("overview")
  /** When set, audit table shows only rows for this farmId; null = all farms. */
  const [selectedAuditFarmId, setSelectedAuditFarmId] = useState<string | null>(() => readHash().params.get("farm"))
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
      setFarmAuditErr(e instanceof Error ? e.message : "Failed to load the platform audit log")
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

  const loadOrganizations = useCallback(async (t: string) => {
    if (!farmApiBase()) return
    setOrgsLoading(true)
    try {
      setOrgs(await fetchOrganizations(t))
      setOrgsErr(null)
    } catch (e) {
      setOrgsErr(e instanceof Error ? e.message : "Failed to load customer intelligence")
    } finally {
      setOrgsLoading(false)
    }
  }, [])

  useEffect(() => {
    if (token) void loadOrganizations(token)
  }, [token, loadOrganizations])

  // Revenue intelligence is loaded lazily (it evaluates billing for every
  // account) the first time a page that shows money opens, then cached.
  useEffect(() => {
    if (!token || revenue !== null) return
    if (devPage !== "revenue" && devPage !== "intel") return
    let gone = false
    fetchRevenueDashboard(token)
      .then((r) => { if (!gone) setRevenue(r) })
      .catch(() => { /* the Revenue page surfaces its own error on open */ })
    return () => { gone = true }
  }, [token, devPage, revenue])

  // Keep the URL hash in sync so every admin view is a shareable deep link.
  useEffect(() => {
    if (!token) return
    const params = new URLSearchParams()
    if (devPage === "intel") {
      if (intelView !== "orgs") params.set("view", intelView)
      if (intelFocusOrg) params.set("org", intelFocusOrg)
      if (intelFocusCompany) params.set("company", intelFocusCompany)
    }
    if (devPage === "audit" && selectedAuditFarmId) params.set("farm", selectedAuditFarmId)
    const qs = params.toString()
    const next = `#/${devPage}${qs ? `?${qs}` : ""}`
    if (window.location.hash !== next) window.history.replaceState(null, "", next)
  }, [token, devPage, intelView, intelFocusOrg, intelFocusCompany, selectedAuditFarmId])

  useEffect(() => {
    const onHash = () => {
      const { page, params } = readHash()
      if (page) {
        setDevPage(page)
        if (page === "intel") {
          setIntelView(params.get("view") === "companies" ? "companies" : "orgs")
          setIntelFocusOrg(params.get("org"))
          setIntelFocusCompany(params.get("company"))
        }
        if (page === "audit") setSelectedAuditFarmId(params.get("farm"))
      }
    }
    window.addEventListener("hashchange", onHash)
    return () => window.removeEventListener("hashchange", onHash)
  }, [])


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
      void loadOrganizations(token)
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
    setDevPage("dashboard")
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

  const companyMetaById = useMemo(() => {
    const m = new Map<string, { family: string | null; orgId: string | null }>()
    for (const o of orgs) for (const c of o.companies) {
      m.set(c.companyId.trim().toLowerCase(), { family: c.companyFamily ?? null, orgId: o.organizationId })
    }
    return m
  }, [orgs])

  const filteredAuditRows = useMemo(() => {
    let rows = farmAuditRows

    if (auditFamily) {
      rows = rows.filter((r) => companyMetaById.get((r.farmId || "").trim().toLowerCase())?.family === auditFamily)
    }
    if (auditOrg) {
      rows = rows.filter((r) => companyMetaById.get((r.farmId || "").trim().toLowerCase())?.orgId === auditOrg)
    }
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
    auditFamily,
    auditOrg,
    companyMetaById,
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
          <h1>VisibilityCore - Platform Admin</h1>
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
              <h1>VisibilityCore - Platform Admin</h1>
              <p>Operations, customer intelligence and billing for the whole platform</p>
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

  const pageMeta: Record<DevPage, { title: string; sub: string }> = {
    dashboard: { title: "Platform Operations", sub: "VisibilityCore executive overview" },
    intel: { title: "Customer Intelligence", sub: "Organizations and companies across every vertical" },
    success: { title: "Customer Success", sub: "Needs Attention queue - explainable health, assignments and follow-ups" },
    analytics: { title: "Analytics", sub: "Onboarding & activation, feature adoption and retention cohorts" },
    revenue: { title: "Revenue", sub: "MRR, movement, trials, renewals, discounts, credits and revenue at risk - per currency" },
    operations: { title: "Operations", sub: "Briefs, error intelligence, security review, feature flags, releases and system health" },
    farms: { title: "Companies", sub: "Every registered company across the platform" },
    customers: { title: "Customers", sub: "Billed organizations and their subscription state" },
    audit: { title: "Platform Activity Audit", sub: "Raw cross-tenant audit trail - deep investigation" },
    reports: { title: "Reports & Analytics", sub: "Performance and activity analytics" },
    billing: { title: "Billing", sub: "Markets, tiers, prices, discounts & organizations" },
    settings: { title: "Settings", sub: "Platform-wide operational switches" },
  }

  return (
    <div className="admin-shell">
      <aside className="admin-sidebar" aria-label="Developer navigation">
        <div className="admin-brand">
          <span className="admin-brand-badge" aria-hidden>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M14.7 6.3a4 4 0 1 0-5.4 5.4L3 18v3h3l6.3-6.3a4 4 0 0 0 5.4-5.4l-2.8 2.8-2.1-2.1 2.9-2.7z"/></svg>
          </span>
          <div>
            <div className="admin-brand-name">VisibilityCore</div>
            <div className="admin-brand-sub">Platform Admin</div>
          </div>
        </div>
        <nav className="admin-nav">
          <button type="button" className={devPage === "dashboard" ? "active" : ""} onClick={() => setDevPage("dashboard")}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/></svg>
            Dashboard
          </button>
          <button type="button" className={devPage === "intel" ? "active" : ""} onClick={() => setDevPage("intel")}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/><path d="M8 11h6M11 8v6"/></svg>
            Customer Intelligence
          </button>
          <button type="button" className={devPage === "success" ? "active" : ""} onClick={() => setDevPage("success")}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M22 11.1V12a10 10 0 1 1-5.9-9.1"/><path d="M22 4 12 14l-3-3"/></svg>
            Customer Success
          </button>
          <button type="button" className={devPage === "analytics" ? "active" : ""} onClick={() => setDevPage("analytics")}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M3 3v18h18"/><path d="M7 13l3-3 4 4 5-6"/></svg>
            Analytics
          </button>
          <button type="button" className={devPage === "revenue" ? "active" : ""} onClick={() => setDevPage("revenue")}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M12 1v22"/><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/></svg>
            Revenue
          </button>
          <button type="button" className={devPage === "operations" ? "active" : ""} onClick={() => setDevPage("operations")}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/></svg>
            Operations
          </button>
          <button type="button" className={devPage === "farms" ? "active" : ""} onClick={() => setDevPage("farms")}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M3 21V8l9-5 9 5v13"/><path d="M9 21v-6h6v6"/></svg>
            Companies
          </button>
          <button type="button" className={devPage === "customers" ? "active" : ""} onClick={() => setDevPage("customers")}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="9" cy="8" r="4"/><path d="M2 21c0-4 3-6 7-6s7 2 7 6"/><path d="M17 11a4 4 0 1 0-2-7.5"/><path d="M22 21c0-3-1.5-5-4-5.6"/></svg>
            Customers
          </button>
          <button type="button" className={devPage === "audit" ? "active" : ""} onClick={() => setDevPage("audit")}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M12 8v4l3 3"/><circle cx="12" cy="12" r="9"/></svg>
            Activity Audit
          </button>
          <button type="button" className={devPage === "reports" ? "active" : ""} onClick={() => setDevPage("reports")}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M3 3v18h18"/><path d="M7 15v3M12 10v8M17 6v12"/></svg>
            Reports
          </button>
          <button type="button" className={devPage === "billing" ? "active" : ""}
            onClick={() => {
              if (devPage !== "billing") { setBillingOwner(null); setBillingSection("overview") }
              setDevPage("billing")
            }}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><rect x="2" y="5" width="20" height="14" rx="2"/><path d="M2 10h20"/></svg>
            Billing
            <svg className={`admin-caret${devPage === "billing" ? " open" : ""}`} width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="m6 9 6 6 6-6"/></svg>
          </button>
          {devPage === "billing" && (
            <div className="admin-subnav">
              {BILLING_SECTIONS.map((sec) => (
                <button key={sec.key} type="button" className={billingSection === sec.key ? "active" : ""}
                  onClick={() => { setBillingOwner(null); setBillingSection(sec.key) }}>
                  {sec.label}
                </button>
              ))}
            </div>
          )}
          <button type="button" className={devPage === "settings" ? "active" : ""} onClick={() => setDevPage("settings")}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09a1.65 1.65 0 0 0 1.51-1 1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33h.01a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82v.01a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>
            Settings
          </button>
        </nav>
        {devPage === "audit" && <>
          <div className="dev-sidebar-section">Companies — audit filter</div>
          <button
            type="button"
            className={`dev-farm-btn${selectedAuditFarmId === null ? " active" : ""}`}
            onClick={() => selectFarmForAudit(null)}
          >
            <span className="name">All companies</span>
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
                <span className="id">{f.totalUsers} user{f.totalUsers === 1 ? "" : "s"} · {f.staffCount} staff</span>
              </button>
            ))}
          </div>
        </>}
        <div className="admin-user">
          <span className="admin-avatar">{(username || localStorage.getItem("lastDeveloperUser") || "DV").slice(0, 2).toUpperCase()}</span>
          <div>
            <div className="admin-user-name">{username || localStorage.getItem("lastDeveloperUser") || "Developer"}</div>
            <div className="admin-user-role">Platform admin</div>
          </div>
        </div>
      </aside>

      <div className="admin-main">
        <header className="admin-topbar">
          <div>
            <h1>{pageMeta[devPage].title}</h1>
            <p>{pageMeta[devPage].sub} · {loginApiBase().replace("https://", "")}</p>
          </div>
          <div className="admin-topbar-actions">
            <button type="button" className="admin-btn-ghost" onClick={() => void refresh()} disabled={busy}>
              {busy ? "Loading…" : "Refresh"}
            </button>
            <button type="button" className="admin-btn-primary" onClick={logout}>Log out</button>
          </div>
        </header>
        <div className="admin-content">
          {devPage === "billing" ? (
            <BillingAdmin
              token={token!}
              actor={username || localStorage.getItem("lastDeveloperUser") || "developer"}
              section={billingSection}
              initialOwner={billingOwner ?? undefined}
            />
          ) : devPage === "farms" ? (
            <FarmsPage farms={farmsSorted} onAudit={selectFarmForAudit} token={token!} onDeleted={() => void refresh()} />
          ) : devPage === "customers" ? (
            <CustomersPage token={token!} onInspect={(owner) => { setBillingOwner(owner); setBillingSection("orgs"); setDevPage("billing") }} />
          ) : devPage === "settings" ? (
            <SettingsPage token={token!} actor={username || localStorage.getItem("lastDeveloperUser") || "developer"} roles={rolesFromJwt(token!)} />
          ) : devPage === "reports" ? (
            <ReportsPage farms={farms} rows={farmAuditRows} resolveFarmName={resolveFarmName} />
          ) : devPage === "dashboard" ? (
            <PlatformDashboard
              token={token!}
              organizations={orgs}
              onOpenIntel={(opts) => {
                if (opts?.view) setIntelView(opts.view)
                setIntelFocusOrg(opts?.org ?? null)
                setIntelFocusCompany(null)
                setDevPage("intel")
              }}
              onOpenAudit={(companyId) => selectFarmForAudit(companyId ?? null)}
            />
          ) : devPage === "analytics" ? (
            <AnalyticsPage token={token!} />
          ) : devPage === "operations" ? (
            <OperationsPage token={token!} onNavigate={(page) => setDevPage(page as DevPage)} />
          ) : devPage === "revenue" ? (
            <RevenuePage
              token={token!}
              revenue={revenue}
              onLoaded={setRevenue}
              onOpenOrg={(orgId) => { setIntelFocusCompany(null); setIntelFocusOrg(orgId); setDevPage("intel") }}
            />
          ) : devPage === "success" ? (
            <CustomerSuccessPage token={token!} organizations={orgs} />
          ) : devPage === "intel" ? (
            <CustomerIntelligencePage
              token={token!}
              organizations={orgs}
              loading={orgsLoading && orgs.length === 0}
              error={orgsErr}
              view={intelView}
              onViewChange={setIntelView}
              focusOrg={intelFocusOrg}
              onFocusOrg={(org) => { setIntelFocusOrg(org); if (org) setIntelFocusCompany(null) }}
              focusCompany={intelFocusCompany}
              onFocusCompany={(companyId) => { setIntelFocusCompany(companyId); if (companyId) setIntelFocusOrg(null) }}
              onDrillAudit={(companyId) => selectFarmForAudit(companyId || null)}
              onOpenBilling={(owner) => { setBillingOwner(owner); setBillingSection("orgs"); setDevPage("billing") }}
              revenueByOrg={revenue ? new Map(revenue.organizations.map((o) => [o.organizationId, o])) : null}
            />
          ) : (
            <div className="card">
              <div className="card-toolbar">
                <h2 className="card-toolbar-title">Platform Activity Audit</h2>
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
                    Company type
                    <select className="audit-filter-input" value={auditFamily} onChange={(e) => setAuditFamily(e.target.value)}>
                      <option value="">All</option>
                      {["Poultry", "Water", "Hotel", "Restaurant", "Generic"].map((f) => <option key={f} value={f}>{f}</option>)}
                    </select>
                  </label>
                  <label className="audit-filter-label">
                    Organization
                    <select className="audit-filter-input" value={auditOrg} onChange={(e) => setAuditOrg(e.target.value)}>
                      <option value="">All</option>
                      {orgs.map((o) => <option key={o.organizationId} value={o.organizationId}>{o.organizationName || o.organizationId}</option>)}
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
                        setAuditFamily("")
                        setAuditOrg("")
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
