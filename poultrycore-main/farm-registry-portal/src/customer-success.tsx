// PROMPT 3: Customer Success → Needs Attention queue. Every row explains WHY
// it exists (rule + data-backed reason); actions: assign to me / assign user,
// mark contacted, internal notes, follow-up date, resolve, dismiss with
// reason. Opening the page runs the health sweep so the queue is current.

import { useCallback, useEffect, useMemo, useState } from "react"
import {
  attentionAssign,
  attentionContacted,
  attentionDismiss,
  attentionFollowUp,
  attentionNote,
  attentionResolve,
  fetchAttentionQueue,
  healthTone,
  timeAgo,
  type AttentionItem,
  type OrganizationSummary,
} from "./platform-activity-api"

type QueueTab = "live" | "Resolved" | "Dismissed" | "All"

export function HealthBadge({ health, reasons }: { health?: string | null; reasons?: string[] }) {
  if (!health) return <span className="subtle-inline">—</span>
  const tone = healthTone(health)
  const cls = tone === "green" ? "badge badge-yes" : tone === "red" ? "badge badge-no" : tone === "amber" ? "badge badge-warn" : "badge"
  return <span className={cls} title={reasons?.length ? reasons.join("\n") : undefined}>{health}</span>
}

export function CustomerSuccessPage({ token, organizations }: {
  token: string
  organizations: OrganizationSummary[]
}) {
  const [items, setItems] = useState<AttentionItem[]>([])
  const [tab, setTab] = useState<QueueTab>("live")
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)
  const [busyId, setBusyId] = useState<number | null>(null)
  const [openId, setOpenId] = useState<number | null>(null)
  const [fAssignee, setFAssignee] = useState("")
  const [fHealth, setFHealth] = useState("")
  const [fFamily, setFFamily] = useState("")
  const [fFollowUpBy, setFFollowUpBy] = useState("")
  const [highValueFirst, setHighValueFirst] = useState(false)

  const load = useCallback(async (which: QueueTab, sweep: boolean) => {
    setLoading(true)
    setErr(null)
    try {
      setItems(await fetchAttentionQueue(token, which === "live" ? undefined : which, sweep))
    } catch (e) {
      setErr(e instanceof Error ? e.message : "Failed to load the attention queue")
    } finally {
      setLoading(false)
    }
  }, [token])

  useEffect(() => { void load(tab, tab === "live") }, [load, tab])

  const orgById = useMemo(() => new Map(organizations.map((o) => [o.organizationId, o])), [organizations])
  const companyById = useMemo(() => {
    const m = new Map<string, { health?: string | null; last?: string | null }>()
    for (const o of organizations) for (const c of o.companies)
      m.set(c.companyId, { health: c.health, last: c.lastMeaningfulActivityAtUtc })
    return m
  }, [organizations])

  const companyFamilyById = useMemo(() => {
    const m = new Map<string, string>()
    for (const o of organizations) for (const c of o.companies)
      if (c.companyFamily) m.set(c.companyId, c.companyFamily)
    return m
  }, [organizations])

  const visibleItems = useMemo(() => items.filter((i) => {
    if (fAssignee && !(i.assignedToName || "").toLowerCase().includes(fAssignee.toLowerCase())) return false
    if (fFamily) {
      const fam = i.companyId ? companyFamilyById.get(i.companyId) : undefined
      if (fam !== fFamily) return false
    }
    if (fHealth) {
      const org = orgById.get(i.organizationId)
      const h = i.companyId
        ? org?.companies.find((c) => c.companyId === i.companyId)?.health
        : org?.health
      if (h !== fHealth) return false
    }
    if (fFollowUpBy) {
      if (!i.followUpAtUtc) return false
      if (new Date(i.followUpAtUtc) > new Date(`${fFollowUpBy}T23:59:59Z`)) return false
    }
    return true
  }).sort((a, b) => {
    if (highValueFirst) {
      const d = (b.revenueAtRisk ?? 0) - (a.revenueAtRisk ?? 0)
      if (d !== 0) return d
    }
    return 0  // keep server order (severity, recency) otherwise
  }), [items, fAssignee, fFamily, fHealth, fFollowUpBy, highValueFirst, companyFamilyById, orgById])

  async function act(id: number, fn: () => Promise<AttentionItem>) {
    setBusyId(id)
    setErr(null)
    try {
      const updated = await fn()
      setItems((prev) => {
        const next = prev.map((i) => (i.id === id ? updated : i))
        // live tab: closed items drop out
        return tab === "live" ? next.filter((i) => ["Open", "Assigned", "Contacted"].includes(i.status)) : next
      })
    } catch (e) {
      setErr(e instanceof Error ? e.message : "Action failed")
    } finally {
      setBusyId(null)
    }
  }

  function askNote(id: number) {
    const note = window.prompt("Internal note:")
    if (note?.trim()) void act(id, () => attentionNote(token, id, note.trim()))
  }
  function askFollowUp(id: number) {
    const v = window.prompt("Follow-up date (YYYY-MM-DD, empty to clear):")
    if (v === null) return
    const iso = v.trim() ? new Date(`${v.trim()}T09:00:00Z`).toISOString() : null
    if (v.trim() && Number.isNaN(+new Date(iso!))) { setErr("Invalid date."); return }
    void act(id, () => attentionFollowUp(token, id, iso))
  }
  function askResolve(id: number) {
    const note = window.prompt("Resolution note (optional):")
    if (note === null) return
    void act(id, () => attentionResolve(token, id, note.trim() || undefined))
  }
  function askDismiss(id: number) {
    const reason = window.prompt("Dismissal reason (required):")
    if (!reason?.trim()) return
    void act(id, () => attentionDismiss(token, id, reason.trim()))
  }
  function askAssignUser(id: number) {
    const name = window.prompt("Assign to (name or email):")
    if (!name?.trim()) return
    void act(id, () => attentionAssign(token, id, name.trim(), name.trim()))
  }

  return (
    <div className="card">
      <div className="card-toolbar">
        <h2 className="card-toolbar-title">Needs Attention</h2>
        <div className="trend-controls">
          {(["live", "Resolved", "Dismissed", "All"] as QueueTab[]).map((t) => (
            <button key={t} type="button" className={`seg-btn${tab === t ? " active" : ""}`} onClick={() => setTab(t)}>
              {t === "live" ? "Open queue" : t}
            </button>
          ))}
          <button type="button" className="seg-btn" onClick={() => void load(tab, true)} disabled={loading}>
            {loading ? "Refreshing…" : "Re-evaluate"}
          </button>
        </div>
      </div>
      <p className="subtle-help">
        Deterministic health rules over real usage and billing data — every item says why it exists.
        Opening this page re-runs the evaluation, so reactivated customers auto-resolve.
      </p>
      {err && <div className="error">{err}</div>}

      <div className="audit-filters" aria-label="Queue filters">
        <div className="audit-filters-row">
          <label className="audit-filter-label">Assignee
            <input className="audit-filter-input" placeholder="Anyone" value={fAssignee} onChange={(e) => setFAssignee(e.target.value)} />
          </label>
          <label className="audit-filter-label">Health
            <select className="audit-filter-input" value={fHealth} onChange={(e) => setFHealth(e.target.value)}>
              <option value="">All</option>
              {["Healthy", "Needs Attention", "At Risk", "Inactive", "New"].map((h) => <option key={h} value={h}>{h}</option>)}
            </select>
          </label>
          <label className="audit-filter-label">Company type
            <select className="audit-filter-input" value={fFamily} onChange={(e) => setFFamily(e.target.value)}>
              <option value="">All</option>
              {["Poultry", "Water", "Hotel", "Restaurant", "Generic"].map((f) => <option key={f} value={f}>{f}</option>)}
            </select>
          </label>
          <label className="audit-filter-label">Follow-up by
            <input className="audit-filter-input" type="date" value={fFollowUpBy} onChange={(e) => setFFollowUpBy(e.target.value)} />
          </label>
          <label className="audit-filter-label">Priority
            <select className="audit-filter-input" value={highValueFirst ? "value" : "severity"}
              onChange={(e) => setHighValueFirst(e.target.value === "value")}>
              <option value="severity">Severity first</option>
              <option value="value">High MRR at risk first</option>
            </select>
          </label>
          <div className="audit-filter-actions">
            <button type="button" className="audit-filter-reset"
              onClick={() => { setFAssignee(""); setFHealth(""); setFFamily(""); setFFollowUpBy(""); setHighValueFirst(false) }}>Reset</button>
          </div>
        </div>
        <p className="audit-filter-meta subtle-help" style={{ marginBottom: 0 }}>
          Showing {visibleItems.length} of {items.length} item{items.length === 1 ? "" : "s"}.
        </p>
      </div>

      {loading && items.length === 0 ? (
        <p className="subtle-help">Evaluating customer health…</p>
      ) : visibleItems.length === 0 ? (
        <p className="subtle-help">
          {items.length === 0
            ? (tab === "live" ? "Nothing needs attention right now — all clear." : "No items with this status.")
            : "No items match these filters."}
        </p>
      ) : (
        <div style={{ overflowX: "auto" }}>
          <table>
            <thead>
              <tr>
                <th>Customer</th><th>Company</th><th>Health</th><th>Reason</th><th>Last activity</th>
                <th>Subscription</th><th>Assignee</th><th>Follow-up</th><th>Status</th><th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {visibleItems.map((i) => {
                const org = orgById.get(i.organizationId)
                const companyMeta = i.companyId ? companyById.get(i.companyId) : null
                const health = i.companyId ? companyMeta?.health : org?.health
                const last = i.companyId ? companyMeta?.last : org?.lastMeaningfulActivityAtUtc
                const busy = busyId === i.id
                const live = ["Open", "Assigned", "Contacted"].includes(i.status)
                return (
                  <>
                    <tr key={i.id} className="row-click" onClick={() => setOpenId(openId === i.id ? null : i.id)}>
                      <td style={{ fontWeight: 600 }}>
                        {i.organizationName || i.organizationId}
                        {(i.revenueAtRisk ?? 0) > 0 && <div className="subtle-inline">MRR at risk: {(i.revenueAtRisk ?? 0).toLocaleString()}</div>}
                      </td>
                      <td>{i.companyName || (i.companyId ? i.companyId : "Organization")}</td>
                      <td><HealthBadge health={health} reasons={i.companyId ? undefined : org?.healthReasons} /></td>
                      <td style={{ maxWidth: 320 }}>
                        <div style={{ fontWeight: 600, fontSize: 13 }}>{i.title}</div>
                        <div className="subtle-inline" title={i.reason}>{i.reason}</div>
                      </td>
                      <td>{timeAgo(last)}</td>
                      <td>{org?.subscriptionStatus === "PastDue"
                        ? <span className="badge badge-no">Past due</span>
                        : org?.subscriptionStatus === "Active"
                          ? <span className="badge badge-yes">Paying</span>
                          : org?.subscriptionStatus || "—"}</td>
                      <td>{i.assignedToName || "—"}</td>
                      <td>{i.followUpAtUtc ? new Date(i.followUpAtUtc).toLocaleDateString() : "—"}</td>
                      <td><span className={`badge${i.severity === "High" && live ? " badge-no" : ""}`}>{i.status}</span></td>
                      <td onClick={(e) => e.stopPropagation()}>
                        {live ? (
                          <div className="action-btns">
                            <button type="button" className="link-btn" disabled={busy}
                              onClick={() => void act(i.id, () => attentionAssign(token, i.id))}>Assign to me</button>
                            <button type="button" className="link-btn" disabled={busy} onClick={() => askAssignUser(i.id)}>Assign…</button>
                            <button type="button" className="link-btn" disabled={busy}
                              onClick={() => void act(i.id, () => attentionContacted(token, i.id))}>Contacted</button>
                            <button type="button" className="link-btn" disabled={busy} onClick={() => askNote(i.id)}>Note</button>
                            <button type="button" className="link-btn" disabled={busy} onClick={() => askFollowUp(i.id)}>Follow-up</button>
                            <button type="button" className="link-btn" disabled={busy} onClick={() => askResolve(i.id)}>Resolve</button>
                            <button type="button" className="link-btn link-danger" disabled={busy} onClick={() => askDismiss(i.id)}>Dismiss</button>
                          </div>
                        ) : (
                          <span className="subtle-inline">{i.resolvedBy ? `${i.resolvedBy}${i.resolutionNote ? `: ${i.resolutionNote}` : ""}` : "—"}</span>
                        )}
                      </td>
                    </tr>
                    {openId === i.id && (
                      <tr key={`${i.id}-notes`}>
                        <td colSpan={10} style={{ background: "#f8fafc" }}>
                          <div className="subtle-help" style={{ marginBottom: 4 }}>
                            Rule <code className="mono">{i.sourceRule}</code> · severity {i.severity} ·
                            first detected {timeAgo(i.detectedAtUtc)} · last confirmed {timeAgo(i.lastDetectedAtUtc)}
                          </div>
                          {i.notes.length === 0 ? (
                            <span className="subtle-inline">No internal notes yet.</span>
                          ) : i.notes.map((n) => (
                            <div key={n.id} style={{ fontSize: 13, padding: "2px 0" }}>
                              <strong>{n.createdBy}</strong> <span className="subtle-inline">{timeAgo(n.createdAtUtc)}</span> — {n.note}
                            </div>
                          ))}
                        </td>
                      </tr>
                    )}
                  </>
                )
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
