// VisibilityCore PLATFORM BILLING administration inside the developer portal
// (ADMIN APP spec): Overview · Markets · Profiles · Tier Rules · Price Books ·
// Presentation · Discounts & Promotions · Organizations · Audit.
// This portal CONFIGURES commercial rules; the shared billing backend
// calculates every amount shown here.

import { useCallback, useEffect, useState } from "react"
import { farmApiBase } from "./api"
import { billingConfig, billingGet, billingSend, moneyFmt, userIdFromJwt, type SendResult } from "./billing-api"

export type Section =
  | "overview" | "markets" | "profiles" | "tiers" | "prices"
  | "presentation" | "discounts" | "orgs" | "audit"

export const BILLING_SECTIONS: { key: Section; label: string }[] = [
  { key: "overview", label: "Overview" },
  { key: "markets", label: "Markets" },
  { key: "profiles", label: "Billing profiles" },
  { key: "tiers", label: "Tier rules" },
  { key: "prices", label: "Price books" },
  { key: "presentation", label: "Presentation" },
  { key: "discounts", label: "Discounts & promos" },
  { key: "orgs", label: "Organizations" },
  { key: "audit", label: "Billing audit" },
]

type AnyRow = Record<string, any>

export default function BillingAdmin({ token, actor, section, initialOwner }: { token: string; actor: string; section: Section; initialOwner?: string }) {
  const userId = userIdFromJwt(token) ?? ""
  const [cfg, setCfg] = useState<Record<string, AnyRow[]>>({})
  const [coverage, setCoverage] = useState<AnyRow | null>(null)
  const [perms, setPerms] = useState<string[]>([])
  const [err, setErr] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  const reload = useCallback(async () => {
    setLoading(true)
    setErr(null)
    try {
      const [c, cov, p] = await Promise.all([
        billingConfig(token, userId),
        billingGet<AnyRow>(token, userId, "coverage"),
        billingGet<string[]>(token, userId, "my-permissions"),
      ])
      setCfg(c)
      setCoverage(cov)
      setPerms(p)
    } catch (e) {
      setErr(e instanceof Error ? e.message : "Billing admin failed to load.")
    } finally {
      setLoading(false)
    }
  }, [token, userId])
  useEffect(() => { void reload() }, [reload])
  useEffect(() => { setNotice(null); setErr(null) }, [section])

  const act = useCallback(async (p: Promise<SendResult>, refresh = true): Promise<SendResult> => {
    const r = await p
    setNotice(r.ok ? r.message || "Saved." : null)
    setErr(r.ok ? null : r.problems?.join(" · ") || r.message || "Not saved.")
    if (r.ok && refresh) void reload()
    return r
  }, [reload])

  if (!userId) return <div className="card"><p className="error">This token has no user id claim — sign in again.</p></div>
  if (loading) return <div className="card"><p className="subtle-help">Loading billing configuration…</p></div>

  return (
    <div className="billing-admin">
      <div className="card">
        <div className="card-toolbar">
          <h2 className="card-toolbar-title">Billing — {BILLING_SECTIONS.find((x) => x.key === section)?.label ?? "Overview"}</h2>
          <span className="subtle-help">{actor} · {perms.join(", ") || "no billing permissions"}</span>
        </div>
        {err && <p className="error">{err}</p>}
        {notice && <p className="billing-notice">{notice}</p>}
      </div>

      {section === "overview" && <Overview coverage={coverage} act={act} token={token} userId={userId} />}
      {section === "markets" && <Markets cfg={cfg} act={act} token={token} userId={userId} />}
      {section === "profiles" && <Profiles cfg={cfg} />}
      {section === "tiers" && <Tiers cfg={cfg} act={act} token={token} userId={userId} />}
      {section === "prices" && <Prices cfg={cfg} act={act} token={token} userId={userId} />}
      {section === "presentation" && <Presentation act={act} token={token} userId={userId} />}
      {section === "discounts" && <Discounts cfg={cfg} act={act} token={token} userId={userId} />}
      {section === "orgs" && <Organizations act={act} token={token} userId={userId} initialOwner={initialOwner} />}
      {section === "audit" && <Audit token={token} userId={userId} />}
    </div>
  )
}

function Overview({ coverage, act, token, userId }: AnyRow) {
  return (
    <>
      {(coverage?.pricingWarnings?.length ?? 0) > 0 && (
        <div className="card billing-warn">
          <div className="card-toolbar"><h3 className="card-toolbar-title">Pricing not configured — checkout is blocked for these</h3></div>
          {coverage.pricingWarnings.map((w: string) => <p key={w} className="billing-warn-line">• {w}</p>)}
        </div>
      )}
      <div className="card">
        <div className="card-toolbar">
          <h3 className="card-toolbar-title">Price coverage</h3>
          <button type="button" className="primary primary-inline" onClick={() => void act(billingSend(token, userId, "POST", "run-maintenance", { key: "run" }), false)}>
            Run maintenance
          </button>
        </div>
        <table><thead><tr><th>Market</th><th>Profile</th><th>Tier</th><th>Monthly</th><th>Annual</th></tr></thead>
          <tbody>{(coverage?.priceCoverage ?? []).map((r: AnyRow, i: number) => (
            <tr key={i}><td>{r.marketCode}</td><td>{r.profileCode}</td><td>{r.tierCode}</td>
              <td>{r.hasMonthly ? "✓" : <span className="badge badge-no">missing</span>}</td>
              <td>{r.hasAnnual ? "✓" : <span className="subtle-help">missing</span>}</td></tr>
          ))}</tbody>
        </table>
      </div>
      <div className="card">
        <div className="card-toolbar"><h3 className="card-toolbar-title">Presentation completeness</h3></div>
        {(coverage?.presentationStatus ?? []).map((w: string) => (
          <p key={w} className={w.includes("MISSING") ? "billing-warn-line" : "billing-ok-line"}>{w}</p>
        ))}
      </div>
    </>
  )
}

// ---------------------------------------------------------------- markets + settings
function Markets({ cfg, act, token, userId }: AnyRow) {
  const [edits, setEdits] = useState<Record<string, string>>({})
  return (
    <>
      <div className="card">
        <div className="card-toolbar"><h3 className="card-toolbar-title">Billing markets</h3></div>
        <table><thead><tr><th>Code</th><th>Name</th><th>Currency</th><th>Provider</th><th>Active</th></tr></thead>
          <tbody>{(cfg.markets ?? []).map((m: AnyRow) => (
            <tr key={m.code}><td className="mono">{m.code}</td><td>{m.name}</td><td>{m.currencycode}</td><td>{m.provider}</td>
              <td>{m.active ? <span className="badge badge-yes">active</span> : <span className="badge badge-no">off</span>}</td></tr>
          ))}</tbody>
        </table>
      </div>
      <div className="card">
        <div className="card-toolbar"><h3 className="card-toolbar-title">Platform settings</h3></div>
        {(cfg.settings ?? []).map((s: AnyRow) => (
          <div key={s.key} className="billing-setting-row" title={s.description}>
            <span className="mono">{s.key}</span>
            <input className="audit-filter-input" value={edits[s.key] ?? String(s.value)} onChange={(e) => setEdits({ ...edits, [s.key]: e.target.value })} />
            <button type="button" className="primary primary-inline" disabled={(edits[s.key] ?? String(s.value)) === String(s.value)}
              onClick={() => void act(billingSend(token, userId, "PUT", "setting", { key: s.key, value: edits[s.key] }))}>
              Save
            </button>
          </div>
        ))}
      </div>
    </>
  )
}

// ---------------------------------------------------------------- profiles
function Profiles({ cfg }: AnyRow) {
  return (
    <div className="card">
      <div className="card-toolbar"><h3 className="card-toolbar-title">Billing profiles — the metric each business type is priced on</h3></div>
      <table><thead><tr><th>Code</th><th>Name</th><th>Metric</th><th>Metric provider</th><th>Active</th></tr></thead>
        <tbody>{(cfg.profiles ?? []).map((p: AnyRow) => (
          <tr key={p.code}><td className="mono">{p.code}</td><td>{p.name}</td><td>{p.metrictype}</td>
            <td className="subtle-help">{p.metrictype === "ManualScale" ? "Configured scale" : "Company operational data (read-only)"}</td>
            <td>{p.active ? "✓" : "—"}</td></tr>
        ))}</tbody>
      </table>
      <p className="subtle-help">
        Water bills by ACTIVE PRODUCTION LINES the water company itself records. Admin never types a company's
        metric — use a company custom price / enterprise contract on the organization instead.
      </p>
    </div>
  )
}

// ---------------------------------------------------------------- tier rules
function Tiers({ cfg, act, token, userId }: AnyRow) {
  const profiles: string[] = (cfg.profiles ?? []).map((p: AnyRow) => p.code)
  const [profile, setProfile] = useState("POULTRY_BIRDS")
  const [rules, setRules] = useState<AnyRow[]>([])
  const [draft, setDraft] = useState<{ tierCode: string; minValue: string; maxValue: string }[]>([])
  const [effectiveFrom, setEffectiveFrom] = useState("")
  const [problems, setProblems] = useState<string[]>([])

  const load = useCallback(async (p: string) => {
    const all = await billingGet<AnyRow[]>(token, userId, `tier-rules?profileCode=${encodeURIComponent(p)}`)
    setRules(all)
    setDraft(all.filter((r) => r.active).map((r) => ({
      tierCode: r.tierCode, minValue: String(r.minValue), maxValue: r.maxValue == null ? "" : String(r.maxValue),
    })))
    setProblems([])
  }, [token, userId])
  useEffect(() => { void load(profile) }, [profile, load])

  return (
    <>
      <div className="card">
        <div className="card-toolbar">
          <h3 className="card-toolbar-title">Tier thresholds — effective-dated, history preserved</h3>
          <select className="audit-filter-input" value={profile} onChange={(e) => setProfile(e.target.value)}>
            {profiles.map((p: string) => <option key={p}>{p}</option>)}
          </select>
        </div>
        {problems.map((p) => <p key={p} className="error">• {p}</p>)}
        {draft.map((d, i) => (
          <div key={i} className="billing-setting-row">
            <input className="audit-filter-input" placeholder="tier" value={d.tierCode}
              onChange={(e) => setDraft(draft.map((x, j) => j === i ? { ...x, tierCode: e.target.value } : x))} />
            <input className="audit-filter-input" placeholder="min" value={d.minValue}
              onChange={(e) => setDraft(draft.map((x, j) => j === i ? { ...x, minValue: e.target.value } : x))} />
            <input className="audit-filter-input" placeholder="max (empty = no limit)" value={d.maxValue}
              onChange={(e) => setDraft(draft.map((x, j) => j === i ? { ...x, maxValue: e.target.value } : x))} />
            <button type="button" className="audit-filter-reset" onClick={() => setDraft(draft.filter((_, j) => j !== i))}>remove</button>
          </div>
        ))}
        <div className="billing-setting-row">
          <button type="button" className="audit-filter-reset" onClick={() => setDraft([...draft, { tierCode: "", minValue: "", maxValue: "" }])}>Add band</button>
          <input className="audit-filter-input" type="date" value={effectiveFrom} onChange={(e) => setEffectiveFrom(e.target.value)} title="Effective from" />
          <button type="button" className="primary primary-inline" onClick={async () => {
            const r = await billingSend(token, userId, "PUT", "tier-rules", {
              profileCode: profile,
              effectiveFrom: effectiveFrom || undefined,
              rules: draft.map((d) => ({ tierCode: d.tierCode, minValue: Number(d.minValue), maxValue: d.maxValue === "" ? null : Number(d.maxValue) })),
            })
            if (!r.ok && r.problems) { setProblems(r.problems); return }
            setProblems([])
            await act(Promise.resolve(r), false)
            void load(profile)
          }}>Validate & save</button>
        </div>
        <p className="subtle-help">Overlaps, gaps, max&lt;min and duplicates are rejected before saving. Issued invoices never change.</p>
      </div>
      <div className="card">
        <div className="card-toolbar"><h3 className="card-toolbar-title">Rule history — {profile}</h3></div>
        <table><thead><tr><th>Tier</th><th>Range</th><th>Effective</th><th>Status</th></tr></thead>
          <tbody>{rules.map((r) => (
            <tr key={r.id} className={r.active ? "" : "billing-muted"}>
              <td>{r.tierCode}</td>
              <td className="mono">{Number(r.minValue).toLocaleString()} – {r.maxValue == null ? "∞" : Number(r.maxValue).toLocaleString()}</td>
              <td className="mono">{String(r.effectiveFrom).slice(0, 10)} → {r.effectiveTo ? String(r.effectiveTo).slice(0, 10) : "…"}</td>
              <td>{r.active ? "active" : "closed"}</td></tr>
          ))}</tbody>
        </table>
      </div>
    </>
  )
}

// ---------------------------------------------------------------- price books
function Prices({ cfg, act, token, userId }: AnyRow) {
  const [f, setF] = useState({ marketCode: "GH", tierCode: "starter", profileCode: "", monthlyPrice: "", annualPrice: "" })
  const suggested = f.monthlyPrice ? (Number(f.monthlyPrice) * 10).toLocaleString() : null
  const entries: AnyRow[] = cfg.priceentries ?? cfg.prices ?? []
  return (
    <>
      <div className="card">
        <div className="card-toolbar"><h3 className="card-toolbar-title">Set a price — closes the current entry, creates a new effective-dated one</h3></div>
        <div className="billing-setting-row billing-wrap">
          <input className="audit-filter-input" placeholder="market (GH)" value={f.marketCode} onChange={(e) => setF({ ...f, marketCode: e.target.value })} />
          <input className="audit-filter-input" placeholder="tier (starter)" value={f.tierCode} onChange={(e) => setF({ ...f, tierCode: e.target.value })} />
          <input className="audit-filter-input" placeholder="profile (empty = any)" value={f.profileCode} onChange={(e) => setF({ ...f, profileCode: e.target.value })} />
          <input className="audit-filter-input" placeholder="monthly" value={f.monthlyPrice} onChange={(e) => setF({ ...f, monthlyPrice: e.target.value })} />
          <input className="audit-filter-input" placeholder={suggested ? `annual (suggest ${suggested})` : "annual — explicit, never ×12"} value={f.annualPrice} onChange={(e) => setF({ ...f, annualPrice: e.target.value })} />
          <button type="button" className="primary primary-inline" onClick={() => void act(billingSend(token, userId, "POST", "price", {
            marketCode: f.marketCode, tierCode: f.tierCode,
            profileCode: f.profileCode || null,
            monthlyPrice: Number(f.monthlyPrice),
            annualPrice: f.annualPrice === "" ? null : Number(f.annualPrice),
          }))}>Save price</button>
        </div>
        <p className="subtle-help">Annual is explicit commercial configuration; the suggestion is display-only.</p>
      </div>
      <div className="card">
        <div className="card-toolbar"><h3 className="card-toolbar-title">Current price book entries</h3></div>
        <table><thead><tr><th>Tier</th><th>Profile</th><th>Monthly</th><th>Annual</th><th>Effective</th><th>Status</th></tr></thead>
          <tbody>{entries.map((e: AnyRow, i: number) => (
            <tr key={i} className={e.active ? "" : "billing-muted"}>
              <td>{e.tiercode}</td><td>{e.profilecode ?? "any"}</td>
              <td className="mono">{Number(e.monthlyprice).toLocaleString()}</td>
              <td className="mono">{e.annualprice == null ? "—" : Number(e.annualprice).toLocaleString()}</td>
              <td className="mono">{String(e.effectivefrom).slice(0, 10)} → {e.effectiveto ? String(e.effectiveto).slice(0, 10) : "…"}</td>
              <td>{e.active ? "active" : "closed"}</td></tr>
          ))}</tbody>
        </table>
      </div>
    </>
  )
}

// ---------------------------------------------------------------- presentation
function Presentation({ act, token, userId }: AnyRow) {
  const [list, setList] = useState<AnyRow[]>([])
  const [sel, setSel] = useState<AnyRow | null>(null)
  const load = useCallback(async () => setList(await billingGet<AnyRow[]>(token, userId, "presentations")), [token, userId])
  useEffect(() => { void load() }, [load])

  return (
    <>
      <div className="card">
        <div className="card-toolbar">
          <h3 className="card-toolbar-title">Pricing presentation — copy only, never amounts</h3>
          <button type="button" className="primary primary-inline"
            onClick={() => setSel({ billingProfileCode: "GENERIC_STANDARD", businessTemplateCode: "", displayName: "", tiers: [] })}>
            New override
          </button>
        </div>
        <table><thead><tr><th>Profile</th><th>Template</th><th>Display</th><th>Tiers</th><th></th></tr></thead>
          <tbody>{list.map((p) => (
            <tr key={p.id}><td className="mono">{p.billingProfileCode}</td><td>{p.businessTemplateCode ?? <span className="subtle-help">default</span>}</td>
              <td>{p.displayName}</td><td>{p.tiers?.length ?? 0}</td>
              <td><button type="button" className="audit-filter-reset" onClick={() => setSel(JSON.parse(JSON.stringify(p)))}>Edit</button></td></tr>
          ))}</tbody>
        </table>
        <p className="subtle-help">A Generic template with no override falls back to the profile default — new templates never break the pricing page.</p>
      </div>
      {sel && (
        <div className="card">
          <div className="card-toolbar"><h3 className="card-toolbar-title">Edit — {sel.billingProfileCode}{sel.businessTemplateCode ? ` / ${sel.businessTemplateCode}` : " (default)"}</h3></div>
          <div className="billing-setting-row billing-wrap">
            <input className="audit-filter-input" placeholder="Profile code" value={sel.billingProfileCode} onChange={(e) => setSel({ ...sel, billingProfileCode: e.target.value })} />
            <input className="audit-filter-input" placeholder="Template (empty = default)" value={sel.businessTemplateCode ?? ""} onChange={(e) => setSel({ ...sel, businessTemplateCode: e.target.value })} />
            <input className="audit-filter-input" placeholder="Display name" value={sel.displayName} onChange={(e) => setSel({ ...sel, displayName: e.target.value })} />
            <input className="audit-filter-input" placeholder="Metric display" value={sel.metricDisplayName ?? ""} onChange={(e) => setSel({ ...sel, metricDisplayName: e.target.value })} />
            <input className="audit-filter-input" placeholder="Metric singular" value={sel.metricSingular ?? ""} onChange={(e) => setSel({ ...sel, metricSingular: e.target.value })} />
            <input className="audit-filter-input" placeholder="Metric plural" value={sel.metricPlural ?? ""} onChange={(e) => setSel({ ...sel, metricPlural: e.target.value })} />
          </div>
          <input className="audit-filter-input billing-full" placeholder="Short description" value={sel.shortDescription ?? ""} onChange={(e) => setSel({ ...sel, shortDescription: e.target.value })} />
          {(sel.tiers ?? []).map((t: AnyRow, i: number) => (
            <div key={i} className="billing-tier-edit">
              <div className="billing-setting-row">
                <input className="audit-filter-input" placeholder="tier (starter…)" value={t.tierCode}
                  onChange={(e) => setSel({ ...sel, tiers: sel.tiers.map((x: AnyRow, j: number) => j === i ? { ...x, tierCode: e.target.value } : x) })} />
                <input className="audit-filter-input billing-grow" placeholder="Headline" value={t.headline ?? ""}
                  onChange={(e) => setSel({ ...sel, tiers: sel.tiers.map((x: AnyRow, j: number) => j === i ? { ...x, headline: e.target.value } : x) })} />
                <label className="subtle-help"><input type="checkbox" checked={!!t.isMostPopular}
                  onChange={(e) => setSel({ ...sel, tiers: sel.tiers.map((x: AnyRow, j: number) => j === i ? { ...x, isMostPopular: e.target.checked } : x) })} /> popular</label>
              </div>
              <textarea className="billing-textarea" rows={3} placeholder="Feature bullets — one per line" value={t.featureBullets ?? ""}
                onChange={(e) => setSel({ ...sel, tiers: sel.tiers.map((x: AnyRow, j: number) => j === i ? { ...x, featureBullets: e.target.value } : x) })} />
            </div>
          ))}
          <div className="billing-setting-row">
            <button type="button" className="audit-filter-reset" onClick={() => setSel({ ...sel, tiers: [...(sel.tiers ?? []), { tierCode: "", displayOrder: (sel.tiers?.length ?? 0) * 10 + 10 }] })}>Add tier copy</button>
            <button type="button" className="primary primary-inline" onClick={async () => {
              const r = await act(billingSend(token, userId, "PUT", "presentation", {
                billingProfileCode: sel.billingProfileCode,
                businessTemplateCode: sel.businessTemplateCode || null,
                displayName: sel.displayName, shortDescription: sel.shortDescription,
                metricDisplayName: sel.metricDisplayName, metricSingular: sel.metricSingular, metricPlural: sel.metricPlural,
                sortOrder: sel.sortOrder ?? 100, active: sel.active ?? true, tiers: sel.tiers ?? [],
              }), false)
              if (r.ok) { setSel(null); void load() }
            }}>Save presentation</button>
            <button type="button" className="audit-filter-reset" onClick={() => setSel(null)}>Cancel</button>
          </div>
        </div>
      )}
    </>
  )
}

// ---------------------------------------------------------------- discounts & promotions
function Discounts({ cfg, act, token, userId }: AnyRow) {
  const [ladder, setLadder] = useState("")
  const [promos, setPromos] = useState<AnyRow[]>([])
  const [promo, setPromo] = useState({ code: "", name: "", value: "", durationPeriods: "3", stackable: false })
  const [assign, setAssign] = useState({ code: "", ownerUserId: "" })
  const loadPromos = useCallback(async () => setPromos(await billingGet<AnyRow[]>(token, userId, "promotions")), [token, userId])
  useEffect(() => {
    void loadPromos()
    setLadder((cfg.discounts ?? []).filter((d: AnyRow) => d.active).map((d: AnyRow) => `${d.mincompanies}:${d.percent}`).join(", "))
  }, [cfg.discounts, loadPromos])

  return (
    <>
      <div className="card">
        <div className="card-toolbar"><h3 className="card-toolbar-title">Automatic multi-company ladder — "2:5, 3:10, 5:15"</h3></div>
        <div className="billing-setting-row">
          <input className="audit-filter-input billing-grow" value={ladder} onChange={(e) => setLadder(e.target.value)} />
          <button type="button" className="primary primary-inline" onClick={() => {
            const rules = ladder.split(",").map((p) => p.trim()).filter(Boolean).map((p) => {
              const [m, v] = p.split(":"); return { minCompanies: Number(m), percent: Number(v) }
            })
            void act(billingSend(token, userId, "PUT", "discounts", { rules }))
          }}>Save ladder</button>
        </div>
        <p className="subtle-help">Only active, billed companies count. An empty ladder turns the automatic discount off.</p>
      </div>
      <div className="card">
        <div className="card-toolbar"><h3 className="card-toolbar-title">Promotions</h3></div>
        <div className="billing-setting-row billing-wrap">
          <input className="audit-filter-input" placeholder="CODE" value={promo.code} onChange={(e) => setPromo({ ...promo, code: e.target.value })} />
          <input className="audit-filter-input" placeholder="Name" value={promo.name} onChange={(e) => setPromo({ ...promo, name: e.target.value })} />
          <input className="audit-filter-input" placeholder="%" value={promo.value} onChange={(e) => setPromo({ ...promo, value: e.target.value })} />
          <input className="audit-filter-input" placeholder="periods" value={promo.durationPeriods} onChange={(e) => setPromo({ ...promo, durationPeriods: e.target.value })} />
          <label className="subtle-help"><input type="checkbox" checked={promo.stackable} onChange={(e) => setPromo({ ...promo, stackable: e.target.checked })} /> stackable</label>
          <button type="button" className="primary primary-inline" onClick={async () => {
            const r = await act(billingSend(token, userId, "POST", "promotion", {
              code: promo.code, name: promo.name, discountType: "Percentage",
              value: Number(promo.value), durationPeriods: Number(promo.durationPeriods), stackable: promo.stackable,
            }), false)
            if (r.ok) void loadPromos()
          }}>Create</button>
        </div>
        <table><thead><tr><th>Code</th><th>Value</th><th>Periods</th><th>Redeemed</th><th>Active</th></tr></thead>
          <tbody>{promos.map((p) => (
            <tr key={p.id}><td className="mono">{p.code}</td><td>{p.discountType === "Fixed" ? moneyFmt(p.value, "GHS") : `${p.value}%`}</td>
              <td>{p.durationPeriods}</td><td>{p.redemptions}{p.maxRedemptions ? ` / ${p.maxRedemptions}` : ""}</td>
              <td>{p.active ? "✓" : "—"}</td></tr>
          ))}</tbody>
        </table>
        <div className="billing-setting-row">
          <input className="audit-filter-input" placeholder="CODE" value={assign.code} onChange={(e) => setAssign({ ...assign, code: e.target.value })} />
          <input className="audit-filter-input billing-grow" placeholder="Organization owner userId" value={assign.ownerUserId} onChange={(e) => setAssign({ ...assign, ownerUserId: e.target.value })} />
          <button type="button" className="primary primary-inline" onClick={async () => {
            const r = await act(billingSend(token, userId, "POST", "promotion-assign", assign), false)
            if (r.ok) void loadPromos()
          }}>Assign to organization</button>
        </div>
      </div>
    </>
  )
}

// ---------------------------------------------------------------- organizations inspector
function Organizations({ act, token, userId, initialOwner }: AnyRow) {
  const [search, setSearch] = useState("")
  const [orgs, setOrgs] = useState<AnyRow[]>([])
  const [insp, setInsp] = useState<AnyRow | null>(null)
  const [owner, setOwner] = useState("")
  const [disc, setDisc] = useState({ name: "", discountType: "Percentage", value: "", scope: "Organization", farmId: "", durationPeriods: "", stackable: true, reason: "" })
  const [preview, setPreview] = useState<AnyRow | null>(null)
  const [credit, setCredit] = useState({ amount: "", reason: "", reference: "" })

  const find = async () => setOrgs(await billingGet<AnyRow[]>(token, userId, `organizations?search=${encodeURIComponent(search)}`))
  const open = async (o: string) => {
    setOwner(o); setPreview(null)
    setInsp(await billingGet<AnyRow>(token, userId, `organization?ownerUserId=${encodeURIComponent(o)}`))
  }
  const refresh = () => owner && void open(owner)
  useEffect(() => { if (initialOwner) void open(initialOwner) }, []) // eslint-disable-line react-hooks/exhaustive-deps
  const discBody = () => ({
    ownerUserId: owner,
    name: disc.name, discountType: disc.discountType, value: Number(disc.value),
    scope: disc.scope, farmId: disc.scope === "Company" ? disc.farmId : null,
    durationPeriods: disc.durationPeriods === "" ? null : Number(disc.durationPeriods),
    stackable: disc.stackable, reason: disc.reason,
  })

  return (
    <>
      <div className="card">
        <div className="billing-setting-row">
          <input className="audit-filter-input billing-grow" placeholder="Search organizations by email, name or org code"
            value={search} onChange={(e) => setSearch(e.target.value)} onKeyDown={(e) => e.key === "Enter" && void find()} />
          <button type="button" className="primary primary-inline" onClick={() => void find()}>Search</button>
          {insp && <button type="button" className="audit-filter-reset" onClick={() => setInsp(null)}>← Results</button>}
        </div>
        {orgs.length > 0 && !insp && (
          <table><thead><tr><th>Owner</th><th>Org</th><th>Market</th><th>Status</th><th>Companies</th><th></th></tr></thead>
            <tbody>{orgs.map((o) => (
              <tr key={o.accountId}><td>{o.ownerName ?? o.ownerEmail ?? o.ownerUserId}</td><td>{o.orgCode ?? "—"}</td>
                <td>{o.marketCode} · {o.currencyCode}</td><td>{o.status}</td><td>{o.companyCount}</td>
                <td><button type="button" className="audit-filter-reset" onClick={() => void open(o.ownerUserId)}>Inspect</button></td></tr>
            ))}</tbody>
          </table>
        )}
      </div>

      {insp && (() => {
        const cur = insp.account.currencyCode
        return (
          <>
            <div className="card">
              <div className="card-toolbar">
                <h3 className="card-toolbar-title">{insp.ownerName ?? insp.ownerEmail}</h3>
                <span className="subtle-help">{insp.account.marketCode} · {cur} · {insp.account.billingCycle} · {insp.account.status}</span>
              </div>
              <table><thead><tr><th>Company</th><th>Type</th><th>Profile</th><th>Metric</th><th>Tier</th><th>Monthly</th><th>Annual</th><th>Custom/GF</th><th>Status</th></tr></thead>
                <tbody>{insp.companies.map((c: AnyRow) => (
                  <tr key={c.farmId}>
                    <td>{c.companyName}</td><td>{c.businessType}</td><td className="mono">{c.billingProfileCode}</td>
                    <td title={c.metricSource}>{Number(c.metricValue).toLocaleString()} <span className="subtle-help">({c.metricSource})</span></td>
                    <td>{c.tierName ?? "—"}</td>
                    <td className="mono">{moneyFmt(c.monthlyAmount, cur)}</td>
                    <td className="mono">{moneyFmt(c.annualPrice, cur)}</td>
                    <td className="mono">{c.customPrice != null ? `C ${c.customPrice}` : c.grandfatheredPrice != null ? `GF ${c.grandfatheredPrice}` : "—"}</td>
                    <td>{c.participationStatus} · {c.pricingStatus}</td></tr>
                ))}</tbody>
              </table>
            </div>

            <div className="card">
              <div className="card-toolbar"><h3 className="card-toolbar-title">Next invoice preview — backend-computed</h3></div>
              <p>Subtotal <span className="mono">{moneyFmt(insp.preview.subtotal, cur)}</span></p>
              {(insp.preview.discountBreakdown ?? []).map((d: AnyRow) => (
                <p key={`${d.id}-${d.name}`} className="billing-ok-line">{d.name}: -{moneyFmt(d.amount, cur)}</p>
              ))}
              <p><strong>Total {moneyFmt(insp.preview.total, cur)}</strong>
                {insp.preview.estimatedCreditApplied > 0 && (
                  <> · credit -{moneyFmt(insp.preview.estimatedCreditApplied, cur)} · due <strong>{moneyFmt(insp.preview.estimatedAmountDue, cur)}</strong></>
                )}</p>
              {preview && (
                <p className="billing-notice">
                  With "{disc.name}": total {moneyFmt(preview.withProposed.total, cur)} (now {moneyFmt(preview.current.total, cur)}).
                </p>
              )}
            </div>

            <div className="card">
              <div className="card-toolbar"><h3 className="card-toolbar-title">Assign a discount — reason required, audited</h3></div>
              <div className="billing-setting-row billing-wrap">
                <input className="audit-filter-input" placeholder="Name (Early adopter…)" value={disc.name} onChange={(e) => setDisc({ ...disc, name: e.target.value })} />
                <select className="audit-filter-input" value={disc.discountType} onChange={(e) => setDisc({ ...disc, discountType: e.target.value })}>
                  <option>Percentage</option><option>Fixed</option>
                </select>
                <input className="audit-filter-input" placeholder={disc.discountType === "Fixed" ? cur : "%"} value={disc.value} onChange={(e) => setDisc({ ...disc, value: e.target.value })} />
                <select className="audit-filter-input" value={disc.scope} onChange={(e) => setDisc({ ...disc, scope: e.target.value })}>
                  <option>Organization</option><option>Company</option>
                </select>
                {disc.scope === "Company" ? (
                  <select className="audit-filter-input" value={disc.farmId} onChange={(e) => setDisc({ ...disc, farmId: e.target.value })}>
                    <option value="">— company —</option>
                    {insp.companies.map((c: AnyRow) => <option key={c.farmId} value={c.farmId}>{c.companyName}</option>)}
                  </select>
                ) : (
                  <input className="audit-filter-input" placeholder="Billing periods (empty = open)" value={disc.durationPeriods} onChange={(e) => setDisc({ ...disc, durationPeriods: e.target.value })} />
                )}
                <input className="audit-filter-input billing-grow" placeholder="Reason (required)" value={disc.reason} onChange={(e) => setDisc({ ...disc, reason: e.target.value })} />
                <button type="button" className="audit-filter-reset" onClick={async () => {
                  try { setPreview(await billingGetPreview()) } catch { setPreview(null) }
                }}>Preview impact</button>
                <button type="button" className="primary primary-inline" onClick={async () => {
                  const r = await act(billingSend(token, userId, "POST", "discount", discBody()), false)
                  if (r.ok) refresh()
                }}>Assign</button>
              </div>
              <table><thead><tr><th>Name</th><th>Value</th><th>Scope</th><th>Used / periods</th><th>Status</th><th></th></tr></thead>
                <tbody>{insp.discounts.map((d: AnyRow) => (
                  <tr key={d.id} className={d.revokedBy ? "billing-muted" : ""}>
                    <td title={`${d.reason} — by ${d.createdBy}`}>{d.name}</td>
                    <td>{d.discountType === "Fixed" ? moneyFmt(d.value, cur) : `${d.value}%`}</td>
                    <td>{d.scope}</td>
                    <td>{d.appliedCount}{d.durationPeriods ? ` / ${d.durationPeriods} (${d.remainingPeriods} left)` : ""}</td>
                    <td>{d.revokedBy ? "revoked" : d.active ? "active" : "ended"}</td>
                    <td>{!d.revokedBy && d.active && (
                      <button type="button" className="audit-filter-reset" onClick={async () => {
                        const r = await act(billingSend(token, userId, "DELETE", `discount/${d.id}`), false)
                        if (r.ok) refresh()
                      }}>Revoke</button>
                    )}</td></tr>
                ))}</tbody>
              </table>
            </div>

            <div className="card">
              <div className="card-toolbar"><h3 className="card-toolbar-title">Account credits — a credit is NOT a discount</h3></div>
              <div className="billing-setting-row billing-wrap">
                <input className="audit-filter-input" placeholder={`Amount (${cur})`} value={credit.amount} onChange={(e) => setCredit({ ...credit, amount: e.target.value })} />
                <input className="audit-filter-input billing-grow" placeholder="Reason (required)" value={credit.reason} onChange={(e) => setCredit({ ...credit, reason: e.target.value })} />
                <button type="button" className="primary primary-inline" onClick={async () => {
                  if (!window.confirm(`Issue a credit of ${cur} ${credit.amount}? It will offset the next invoice.`)) return
                  const r = await act(billingSend(token, userId, "POST", "credit", { ownerUserId: owner, amount: Number(credit.amount), reason: credit.reason, reference: credit.reference || null }), false)
                  if (r.ok) refresh()
                }}>Issue credit</button>
              </div>
              <table><thead><tr><th>Issued</th><th>Used</th><th>Remaining</th><th>Reason</th><th>Invoices</th><th></th></tr></thead>
                <tbody>{insp.credits.map((c: AnyRow) => (
                  <tr key={c.id} className={c.revokedBy ? "billing-muted" : ""}>
                    <td className="mono">{moneyFmt(c.amount, c.currencyCode)}</td>
                    <td className="mono">{moneyFmt(c.used, c.currencyCode)}</td>
                    <td className="mono"><strong>{moneyFmt(c.remaining, c.currencyCode)}</strong></td>
                    <td>{c.reason}</td><td className="mono">{c.appliedInvoices.join(", ") || "—"}</td>
                    <td>{!c.revokedBy && c.used === 0 && (
                      <button type="button" className="audit-filter-reset" onClick={async () => {
                        const r = await act(billingSend(token, userId, "DELETE", `credit/${c.id}`), false)
                        if (r.ok) refresh()
                      }}>Revoke</button>
                    )}</td></tr>
                ))}</tbody>
              </table>
            </div>

            <div className="card">
              <div className="card-toolbar"><h3 className="card-toolbar-title">Invoices & payments</h3></div>
              <table><thead><tr><th>Invoice</th><th>Period</th><th>Total</th><th>Credit</th><th>Balance</th><th>Status</th></tr></thead>
                <tbody>{insp.invoices.map((i: AnyRow) => (
                  <tr key={i.id}><td className="mono" title={i.discountBreakdown ?? ""}>{i.invoiceNumber}</td>
                    <td className="mono">{String(i.periodStart).slice(0, 10)}</td>
                    <td className="mono">{moneyFmt(i.totalAmount, i.currencyCode)}</td>
                    <td className="mono">{i.creditApplied ? moneyFmt(i.creditApplied, i.currencyCode) : "—"}</td>
                    <td className="mono">{moneyFmt(i.balance, i.currencyCode)}</td>
                    <td>{i.status}</td></tr>
                ))}</tbody>
              </table>
              <table><thead><tr><th>Payment ref</th><th>Provider</th><th>Amount</th><th>Status</th></tr></thead>
                <tbody>{insp.payments.map((p: AnyRow) => (
                  <tr key={p.id}><td className="mono">{p.externalReference ?? "—"}</td><td>{p.provider}</td>
                    <td className="mono">{moneyFmt(p.amount, p.currencyCode)}</td><td>{p.status}</td></tr>
                ))}</tbody>
              </table>
            </div>
          </>
        )

        async function billingGetPreview(): Promise<AnyRow> {
          const res = await fetch(`${farmApiBase()}/api/PlatformBillingAdmin/discount-preview`, {
            method: "POST",
            headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
            body: JSON.stringify({ userId, ...discBody() }),
          })
          if (!res.ok) throw new Error(await res.text())
          return (await res.json()) as AnyRow
        }
      })()}
    </>
  )
}

// ---------------------------------------------------------------- audit
function Audit({ token, userId }: AnyRow) {
  const [events, setEvents] = useState<AnyRow[]>([])
  useEffect(() => { void billingGet<AnyRow[]>(token, userId, "events?limit=150").then(setEvents).catch(() => {}) }, [token, userId])
  return (
    <div className="card">
      <div className="card-toolbar"><h3 className="card-toolbar-title">Billing audit trail — every commercial action, explainable</h3></div>
      <table><thead><tr><th>When (UTC)</th><th>Event</th><th>Account</th><th>Change</th><th>Actor</th><th>Ref / reason</th></tr></thead>
        <tbody>{events.map((e) => (
          <tr key={e.id}><td className="mono">{String(e.atUtc).replace("T", " ").slice(0, 16)}</td>
            <td>{e.eventType}</td><td className="mono">{e.accountId ?? "—"}</td>
            <td>{[e.oldValue, e.newValue].filter(Boolean).join(" → ") || "—"}</td>
            <td className="mono">{e.actor ?? "system"}</td>
            <td>{e.notes ?? "—"}</td></tr>
        ))}</tbody>
      </table>
    </div>
  )
}
