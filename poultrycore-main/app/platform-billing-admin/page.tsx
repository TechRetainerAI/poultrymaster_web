"use client"

// VisibilityCore PLATFORM BILLING ADMIN (ADMIN APP spec, 2026-10-05).
// Staff-only console with the spec's information architecture:
// Overview · Markets · Profiles · Tier Rules · Price Books · Presentation ·
// Discounts & Promotions · Organizations (inspector) · Invoices & Payments ·
// Audit. The admin app CONFIGURES commercial rules; every amount shown here
// is computed by the shared billing backend — never in this page's JS.

import { useCallback, useEffect, useState } from "react"
import { Inter } from "next/font/google"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs"
import { Input } from "@/components/ui/input"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { useToast } from "@/hooks/use-toast"
import { Loader2, ShieldAlert, RefreshCw } from "lucide-react"
import { farmApiUrl, getAuthHeaders, getUserContext } from "@/lib/api/config"
import {
  getAdminConfig,
  adminPutSetting,
  adminPostPrice,
  adminPutDiscounts,
  adminRunMaintenance,
} from "@/lib/api/platform-billing"

const inter = Inter({ subsets: ["latin"], display: "swap" })

// Small admin fetchers — every call carries the acting admin's userId and the
// backend enforces the per-permission gate (spec 29).
function uid() { return getUserContext().userId }
async function aget<T>(path: string): Promise<T> {
  const sep = path.includes("?") ? "&" : "?"
  const res = await fetch(farmApiUrl(`/PlatformBillingAdmin/${path}${sep}userId=${encodeURIComponent(uid())}`), { headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await res.text())
  return (await res.json()) as T
}
async function asend(method: string, path: string, body?: unknown): Promise<{ ok: boolean; message?: string; problems?: string[] }> {
  const payload = body ? { userId: uid(), ...(body as object) } : undefined
  const sep = path.includes("?") ? "&" : "?"
  const url = payload ? farmApiUrl(`/PlatformBillingAdmin/${path}`)
                      : farmApiUrl(`/PlatformBillingAdmin/${path}${sep}userId=${encodeURIComponent(uid())}`)
  const res = await fetch(url, {
    method,
    headers: getAuthHeaders(),
    body: payload ? JSON.stringify(payload) : undefined,
  })
  const data = await res.json().catch(() => ({}))
  if (!res.ok) return { ok: false, message: data?.message || data?.problems?.join(" ") || (typeof data === "string" ? data : `Failed (${res.status})`), problems: data?.problems }
  return { ok: data?.ok !== false, ...data }
}

function money(v: number | null | undefined, c: string) {
  return v == null ? "—" : `${c} ${Number(v).toLocaleString(undefined, { minimumFractionDigits: 2 })}`
}
function Th({ children }: { children?: React.ReactNode }) {
  return <th className="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">{children}</th>
}
function Td({ children, className = "", title }: { children?: React.ReactNode; className?: string; title?: string }) {
  return <td title={title} className={`px-3 py-2 text-sm text-slate-700 ${className}`}>{children}</td>
}

export default function PlatformBillingAdminPage() {
  const { toast } = useToast()
  const [denied, setDenied] = useState(false)
  const [loading, setLoading] = useState(true)
  const [cfg, setCfg] = useState<Record<string, any[]>>({})
  const [coverage, setCoverage] = useState<any | null>(null)
  const [perms, setPerms] = useState<string[]>([])

  const reload = useCallback(async () => {
    setLoading(true)
    try {
      const [c, cov, p] = await Promise.all([
        getAdminConfig() as Promise<Record<string, any[]>>,
        aget<any>("coverage"),
        aget<string[]>("my-permissions"),
      ])
      setCfg(c); setCoverage(cov); setPerms(p); setDenied(false)
    } catch {
      setDenied(true)
    } finally { setLoading(false) }
  }, [])
  useEffect(() => { void reload() }, [reload])

  const act = async (p: Promise<{ ok: boolean; message?: string; problems?: string[] }>, refresh = true) => {
    const r = await p
    toast({
      title: r.ok ? "Done" : "Not saved",
      description: r.problems?.join("; ") || r.message,
      variant: r.ok ? undefined : "destructive",
    })
    if (r.ok && refresh) void reload()
    return r.ok
  }

  if (loading) return <div className="flex min-h-screen items-center justify-center"><Loader2 className="h-6 w-6 animate-spin text-slate-400" /></div>
  if (denied)
    return (
      <div className={`mx-auto max-w-xl p-10 ${inter.className}`}>
        <Alert variant="destructive">
          <ShieldAlert className="h-4 w-4" />
          <AlertDescription>Platform billing administration is restricted to authorized VisibilityCore staff.</AlertDescription>
        </Alert>
      </div>
    )

  return (
    <div className={`min-h-screen bg-slate-50 ${inter.className}`}>
      <main className="mx-auto max-w-7xl space-y-5 p-4 sm:p-6">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div>
            <h1 className="text-xl font-semibold tracking-[-0.01em] text-slate-900">Billing administration</h1>
            <p className="text-sm text-slate-500">What should VisibilityCore charge? Configure it here — the customer app computes and explains the rest.</p>
          </div>
          <div className="flex items-center gap-2">
            <span className="rounded-full bg-slate-100 px-2.5 py-1 text-xs text-slate-600">{perms.join(", ") || "view only"}</span>
            <Button size="sm" variant="outline" onClick={() => void reload()}><RefreshCw className="mr-1.5 h-3.5 w-3.5" />Refresh</Button>
          </div>
        </div>

        <Tabs defaultValue="overview">
          <TabsList className="flex h-auto w-full flex-wrap justify-start gap-1">
            {["overview","markets","profiles","tiers","prices","presentation","discounts","orgs","audit"].map((k) => (
              <TabsTrigger key={k} value={k} className="capitalize">{k === "orgs" ? "Organizations" : k === "tiers" ? "Tier rules" : k === "prices" ? "Price books" : k}</TabsTrigger>
            ))}
          </TabsList>

          <TabsContent value="overview" className="pt-4"><Overview coverage={coverage} act={act} /></TabsContent>
          <TabsContent value="markets" className="pt-4"><Markets cfg={cfg} act={act} /></TabsContent>
          <TabsContent value="profiles" className="pt-4"><Profiles cfg={cfg} /></TabsContent>
          <TabsContent value="tiers" className="pt-4"><TierRules cfg={cfg} act={act} /></TabsContent>
          <TabsContent value="prices" className="pt-4"><PriceBooks cfg={cfg} act={act} /></TabsContent>
          <TabsContent value="presentation" className="pt-4"><Presentations act={act} /></TabsContent>
          <TabsContent value="discounts" className="pt-4"><Discounts cfg={cfg} act={act} /></TabsContent>
          <TabsContent value="orgs" className="pt-4"><Organizations act={act} /></TabsContent>
          <TabsContent value="audit" className="pt-4"><AuditLog /></TabsContent>
        </Tabs>
      </main>
    </div>
  )
}

// ---------------------------------------------------------------- overview
function Overview({ coverage, act }: { coverage: any; act: any }) {
  return (
    <div className="space-y-4">
      {(coverage?.pricingWarnings?.length ?? 0) > 0 && (
        <Card className="border-amber-200 bg-amber-50/60">
          <CardHeader className="py-3"><CardTitle className="text-sm text-amber-800">Pricing not configured (spec 34) — customers on these combinations cannot check out</CardTitle></CardHeader>
          <CardContent className="space-y-1 pb-4 text-sm text-amber-800">
            {coverage.pricingWarnings.map((w: string) => <p key={w}>• {w} — fix it under Price books</p>)}
          </CardContent>
        </Card>
      )}
      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader className="py-3"><CardTitle className="text-sm">Price coverage (spec 35)</CardTitle></CardHeader>
          <CardContent className="overflow-x-auto pb-4">
            <table className="w-full"><thead><tr><Th>Market</Th><Th>Profile</Th><Th>Tier</Th><Th>Monthly</Th><Th>Annual</Th></tr></thead>
              <tbody>
                {(coverage?.priceCoverage ?? []).map((r: any, i: number) => (
                  <tr key={i} className="border-t border-slate-100">
                    <Td>{r.marketCode}</Td><Td>{r.profileCode}</Td><Td className="capitalize">{r.tierCode}</Td>
                    <Td>{r.hasMonthly ? "✓" : <span className="font-medium text-amber-600">missing</span>}</Td>
                    <Td>{r.hasAnnual ? "✓" : <span className="text-slate-400">missing</span>}</Td>
                  </tr>
                ))}
              </tbody>
            </table>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="py-3"><CardTitle className="text-sm">Presentation completeness (spec 36)</CardTitle></CardHeader>
          <CardContent className="space-y-1 pb-4 text-sm text-slate-700">
            {(coverage?.presentationStatus ?? []).map((w: string) => (
              <p key={w} className={w.includes("MISSING") ? "font-medium text-amber-700" : ""}>{w}</p>
            ))}
            <div className="pt-3">
              <Button size="sm" variant="outline" onClick={() => void act(asend("POST", "run-maintenance", { key: "run" }), false)}>
                Run billing maintenance now
              </Button>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}

// ---------------------------------------------------------------- markets + settings
function Markets({ cfg, act }: { cfg: Record<string, any[]>; act: any }) {
  const [edits, setEdits] = useState<Record<string, string>>({})
  return (
    <div className="grid gap-4 lg:grid-cols-2">
      <Card>
        <CardHeader className="py-3"><CardTitle className="text-sm">Billing markets</CardTitle></CardHeader>
        <CardContent className="overflow-x-auto pb-4">
          <table className="w-full"><thead><tr><Th>Code</Th><Th>Name</Th><Th>Currency</Th><Th>Provider</Th><Th>Active</Th></tr></thead>
            <tbody>{(cfg.markets ?? []).map((m: any) => (
              <tr key={m.code} className="border-t border-slate-100">
                <Td>{m.code}</Td><Td>{m.name}</Td><Td>{m.currencycode}</Td><Td>{m.provider}</Td>
                <Td>{m.active ? "✓" : "—"}</Td>
              </tr>
            ))}</tbody>
          </table>
        </CardContent>
      </Card>
      <Card>
        <CardHeader className="py-3"><CardTitle className="text-sm">Platform settings</CardTitle></CardHeader>
        <CardContent className="space-y-2 pb-4">
          {(cfg.settings ?? []).map((s: any) => (
            <div key={s.key} className="flex items-center gap-2">
              <span className="w-56 truncate text-sm text-slate-600" title={s.description}>{s.key}</span>
              <Input className="h-8 w-36" value={edits[s.key] ?? s.value} onChange={(e) => setEdits({ ...edits, [s.key]: e.target.value })} />
              <Button size="sm" variant="outline" disabled={(edits[s.key] ?? s.value) === s.value}
                onClick={async () => { const ok = await adminPutSetting(s.key, edits[s.key]); void act(Promise.resolve({ ok: ok.ok, message: ok.ok ? `${s.key} saved` : "Save failed" })) }}>
                Save
              </Button>
            </div>
          ))}
        </CardContent>
      </Card>
    </div>
  )
}

// ---------------------------------------------------------------- profiles
function Profiles({ cfg }: { cfg: Record<string, any[]> }) {
  return (
    <Card>
      <CardHeader className="py-3"><CardTitle className="text-sm">Billing profiles (spec 3) — the metric each business type is priced on</CardTitle></CardHeader>
      <CardContent className="overflow-x-auto pb-4">
        <table className="w-full"><thead><tr><Th>Code</Th><Th>Name</Th><Th>Metric</Th><Th>Metric provider</Th><Th>Active</Th></tr></thead>
          <tbody>{(cfg.profiles ?? []).map((p: any) => (
            <tr key={p.code} className="border-t border-slate-100">
              <Td>{p.code}</Td><Td>{p.name}</Td><Td>{p.metrictype}</Td>
              <Td className="text-slate-500">{p.metrictype === "ManualScale" ? "Configured scale (admin)" : "Company operational data (read-only)"}</Td>
              <Td>{p.active ? "✓" : "—"}</Td>
            </tr>
          ))}</tbody>
        </table>
        <p className="mt-3 text-xs text-slate-500">
          Water bills by ACTIVE PRODUCTION LINES recorded by the water company itself (spec 7). Admin never types a
          company's metric — use a Manual Billing Override / Enterprise contract on the organization instead (spec 33).
        </p>
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------- tier rules
function TierRules({ cfg, act }: { cfg: Record<string, any[]>; act: any }) {
  const profiles: string[] = (cfg.profiles ?? []).map((p: any) => p.code)
  const [profile, setProfile] = useState<string>("POULTRY_BIRDS")
  const [rules, setRules] = useState<any[]>([])
  const [draft, setDraft] = useState<{ tierCode: string; minValue: string; maxValue: string }[]>([])
  const [effectiveFrom, setEffectiveFrom] = useState("")
  const [problems, setProblems] = useState<string[]>([])

  const load = useCallback(async (p: string) => {
    const all = await aget<any[]>(`tier-rules?profileCode=${encodeURIComponent(p)}`)
    setRules(all)
    setDraft(all.filter((r) => r.active).map((r) => ({
      tierCode: r.tierCode, minValue: String(r.minValue), maxValue: r.maxValue == null ? "" : String(r.maxValue),
    })))
    setProblems([])
  }, [])
  useEffect(() => { void load(profile) }, [profile, load])

  const save = async () => {
    const body = {
      profileCode: profile,
      effectiveFrom: effectiveFrom || undefined,
      rules: draft.map((d) => ({ tierCode: d.tierCode, minValue: Number(d.minValue), maxValue: d.maxValue === "" ? null : Number(d.maxValue) })),
    }
    const r = await asend("PUT", "tier-rules", body)
    if (!r.ok && r.problems) { setProblems(r.problems); return }
    setProblems([])
    if (await act(Promise.resolve(r), false)) void load(profile)
  }

  return (
    <div className="grid gap-4 lg:grid-cols-2">
      <Card>
        <CardHeader className="py-3">
          <div className="flex items-center justify-between">
            <CardTitle className="text-sm">Tier thresholds (spec 4/5) — effective-dated, history preserved</CardTitle>
            <select className="h-8 rounded-md border border-slate-200 px-2 text-sm" value={profile} onChange={(e) => setProfile(e.target.value)}>
              {profiles.map((p) => <option key={p}>{p}</option>)}
            </select>
          </div>
        </CardHeader>
        <CardContent className="space-y-2 pb-4">
          {problems.length > 0 && (
            <Alert variant="destructive"><AlertDescription>{problems.map((p) => <p key={p}>• {p}</p>)}</AlertDescription></Alert>
          )}
          {draft.map((d, i) => (
            <div key={i} className="flex items-center gap-2">
              <Input className="h-8 w-28" value={d.tierCode} onChange={(e) => setDraft(draft.map((x, j) => j === i ? { ...x, tierCode: e.target.value } : x))} />
              <Input className="h-8 w-24" placeholder="min" value={d.minValue} onChange={(e) => setDraft(draft.map((x, j) => j === i ? { ...x, minValue: e.target.value } : x))} />
              <Input className="h-8 w-24" placeholder="max (empty = ∞)" value={d.maxValue} onChange={(e) => setDraft(draft.map((x, j) => j === i ? { ...x, maxValue: e.target.value } : x))} />
              <Button size="sm" variant="ghost" className="text-slate-400" onClick={() => setDraft(draft.filter((_, j) => j !== i))}>✕</Button>
            </div>
          ))}
          <div className="flex items-center gap-2 pt-1">
            <Button size="sm" variant="outline" onClick={() => setDraft([...draft, { tierCode: "", minValue: "", maxValue: "" }])}>Add band</Button>
            <Input className="h-8 w-40" type="date" value={effectiveFrom} onChange={(e) => setEffectiveFrom(e.target.value)} title="Effective from (spec 39)" />
            <Button size="sm" onClick={() => void save()}>Validate & save</Button>
          </div>
          <p className="text-xs text-slate-500">Overlaps, gaps, max&lt;min and duplicate bands are rejected before saving (spec 6). Already-issued invoices never change (spec 39).</p>
        </CardContent>
      </Card>
      <Card>
        <CardHeader className="py-3"><CardTitle className="text-sm">Rule history — {profile}</CardTitle></CardHeader>
        <CardContent className="overflow-x-auto pb-4">
          <table className="w-full"><thead><tr><Th>Tier</Th><Th>Range</Th><Th>Effective</Th><Th>Active</Th></tr></thead>
            <tbody>{rules.map((r) => (
              <tr key={r.id} className={`border-t border-slate-100 ${r.active ? "" : "text-slate-400"}`}>
                <Td className="capitalize">{r.tierCode}</Td>
                <Td>{Number(r.minValue).toLocaleString()} – {r.maxValue == null ? "∞" : Number(r.maxValue).toLocaleString()}</Td>
                <Td>{String(r.effectiveFrom).slice(0, 10)} → {r.effectiveTo ? String(r.effectiveTo).slice(0, 10) : "…"}</Td>
                <Td>{r.active ? "✓" : "closed"}</Td>
              </tr>
            ))}</tbody>
          </table>
        </CardContent>
      </Card>
    </div>
  )
}

// ---------------------------------------------------------------- price books
function PriceBooks({ cfg, act }: { cfg: Record<string, any[]>; act: any }) {
  const [form, setForm] = useState({ marketCode: "GH", tierCode: "starter", profileCode: "", monthlyPrice: "", annualPrice: "" })
  const suggested = form.monthlyPrice ? (Number(form.monthlyPrice) * 10).toLocaleString() : null
  return (
    <div className="space-y-4">
      <Card>
        <CardHeader className="py-3"><CardTitle className="text-sm">Set a price (spec 8/10) — closes the current entry and creates a new effective-dated one</CardTitle></CardHeader>
        <CardContent className="flex flex-wrap items-end gap-2 pb-4">
          {(["marketCode", "tierCode", "profileCode"] as const).map((k) => (
            <div key={k}>
              <p className="mb-1 text-xs text-slate-500">{k === "profileCode" ? "profile (empty = any)" : k}</p>
              <Input className="h-8 w-36" value={form[k]} onChange={(e) => setForm({ ...form, [k]: e.target.value })} />
            </div>
          ))}
          <div>
            <p className="mb-1 text-xs text-slate-500">monthly</p>
            <Input className="h-8 w-28" value={form.monthlyPrice} onChange={(e) => setForm({ ...form, monthlyPrice: e.target.value })} />
          </div>
          <div>
            <p className="mb-1 text-xs text-slate-500">annual (explicit, spec 9{suggested ? ` — suggestion: ${suggested}` : ""})</p>
            <Input className="h-8 w-28" placeholder="never auto ×12" value={form.annualPrice} onChange={(e) => setForm({ ...form, annualPrice: e.target.value })} />
          </div>
          <Button size="sm" onClick={async () => {
            const r = await adminPostPrice({
              marketCode: form.marketCode, tierCode: form.tierCode,
              profileCode: form.profileCode || null,
              monthlyPrice: Number(form.monthlyPrice),
              annualPrice: form.annualPrice === "" ? null : Number(form.annualPrice),
            })
            void act(Promise.resolve({ ok: r.ok, message: r.message }))
          }}>Save price</Button>
        </CardContent>
      </Card>
      <Card>
        <CardHeader className="py-3"><CardTitle className="text-sm">Current price book entries</CardTitle></CardHeader>
        <CardContent className="overflow-x-auto pb-4">
          <table className="w-full"><thead><tr><Th>Book</Th><Th>Tier</Th><Th>Profile</Th><Th>Monthly</Th><Th>Annual</Th><Th>Effective</Th><Th>Active</Th></tr></thead>
            <tbody>{(cfg.priceentries ?? cfg.prices ?? []).map((e: any, i: number) => (
              <tr key={i} className={`border-t border-slate-100 ${e.active ? "" : "text-slate-400"}`}>
                <Td>{e.bookcode ?? e.pricebookid}</Td><Td className="capitalize">{e.tiercode}</Td><Td>{e.profilecode ?? "any"}</Td>
                <Td className="tabular-nums">{Number(e.monthlyprice).toLocaleString()}</Td>
                <Td className="tabular-nums">{e.annualprice == null ? "—" : Number(e.annualprice).toLocaleString()}</Td>
                <Td>{String(e.effectivefrom).slice(0, 10)} → {e.effectiveto ? String(e.effectiveto).slice(0, 10) : "…"}</Td>
                <Td>{e.active ? "✓" : "closed"}</Td>
              </tr>
            ))}</tbody>
          </table>
        </CardContent>
      </Card>
    </div>
  )
}

// ---------------------------------------------------------------- presentation
function Presentations({ act }: { act: any }) {
  const [list, setList] = useState<any[]>([])
  const [sel, setSel] = useState<any | null>(null)
  const load = useCallback(async () => setList(await aget<any[]>("presentations")), [])
  useEffect(() => { void load() }, [load])

  const save = async () => {
    const ok = await act(asend("PUT", "presentation", {
      billingProfileCode: sel.billingProfileCode,
      businessTemplateCode: sel.businessTemplateCode || null,
      displayName: sel.displayName, shortDescription: sel.shortDescription,
      metricDisplayName: sel.metricDisplayName, metricSingular: sel.metricSingular, metricPlural: sel.metricPlural,
      sortOrder: sel.sortOrder ?? 100, active: sel.active ?? true, tiers: sel.tiers ?? [],
    }), false)
    if (ok) { setSel(null); void load() }
  }

  return (
    <div className="grid gap-4 lg:grid-cols-2">
      <Card>
        <CardHeader className="py-3">
          <div className="flex items-center justify-between">
            <CardTitle className="text-sm">Pricing presentation (spec 11-16) — copy only, never amounts</CardTitle>
            <Button size="sm" variant="outline" onClick={() => setSel({ billingProfileCode: "GENERIC_STANDARD", businessTemplateCode: "", displayName: "", tiers: [] })}>New override</Button>
          </div>
        </CardHeader>
        <CardContent className="overflow-x-auto pb-4">
          <table className="w-full"><thead><tr><Th>Profile</Th><Th>Template</Th><Th>Display</Th><Th>Tiers</Th><Th></Th></tr></thead>
            <tbody>{list.map((p) => (
              <tr key={p.id} className="border-t border-slate-100">
                <Td>{p.billingProfileCode}</Td><Td>{p.businessTemplateCode ?? <span className="text-slate-400">default</span>}</Td>
                <Td>{p.displayName}</Td><Td>{p.tiers?.length ?? 0}</Td>
                <Td><Button size="sm" variant="ghost" onClick={() => setSel(JSON.parse(JSON.stringify(p)))}>Edit</Button></Td>
              </tr>
            ))}</tbody>
          </table>
          <p className="mt-2 text-xs text-slate-500">A Generic template with no override falls back to the profile default — a new template never breaks the pricing page (spec 16).</p>
        </CardContent>
      </Card>
      {sel && (
        <Card>
          <CardHeader className="py-3"><CardTitle className="text-sm">Edit — {sel.billingProfileCode}{sel.businessTemplateCode ? ` / ${sel.businessTemplateCode}` : " (default)"}</CardTitle></CardHeader>
          <CardContent className="space-y-2 pb-4">
            <div className="grid grid-cols-2 gap-2">
              <Input className="h-8" placeholder="Billing profile code" value={sel.billingProfileCode} onChange={(e) => setSel({ ...sel, billingProfileCode: e.target.value })} />
              <Input className="h-8" placeholder="Template (empty = default)" value={sel.businessTemplateCode ?? ""} onChange={(e) => setSel({ ...sel, businessTemplateCode: e.target.value })} />
              <Input className="h-8" placeholder="Display name" value={sel.displayName} onChange={(e) => setSel({ ...sel, displayName: e.target.value })} />
              <Input className="h-8" placeholder="Metric display name" value={sel.metricDisplayName ?? ""} onChange={(e) => setSel({ ...sel, metricDisplayName: e.target.value })} />
              <Input className="h-8" placeholder="Metric singular" value={sel.metricSingular ?? ""} onChange={(e) => setSel({ ...sel, metricSingular: e.target.value })} />
              <Input className="h-8" placeholder="Metric plural" value={sel.metricPlural ?? ""} onChange={(e) => setSel({ ...sel, metricPlural: e.target.value })} />
            </div>
            <Input className="h-8" placeholder="Short description" value={sel.shortDescription ?? ""} onChange={(e) => setSel({ ...sel, shortDescription: e.target.value })} />
            {(sel.tiers ?? []).map((t: any, i: number) => (
              <div key={i} className="rounded-lg border border-slate-200 p-2">
                <div className="flex items-center gap-2">
                  <Input className="h-8 w-28" placeholder="tier" value={t.tierCode} onChange={(e) => setSel({ ...sel, tiers: sel.tiers.map((x: any, j: number) => j === i ? { ...x, tierCode: e.target.value } : x) })} />
                  <Input className="h-8 flex-1" placeholder="Headline" value={t.headline ?? ""} onChange={(e) => setSel({ ...sel, tiers: sel.tiers.map((x: any, j: number) => j === i ? { ...x, headline: e.target.value } : x) })} />
                  <label className="flex items-center gap-1 text-xs text-slate-600">
                    <input type="checkbox" checked={!!t.isMostPopular} onChange={(e) => setSel({ ...sel, tiers: sel.tiers.map((x: any, j: number) => j === i ? { ...x, isMostPopular: e.target.checked } : x) })} />
                    popular
                  </label>
                </div>
                <textarea className="mt-1 w-full rounded-md border border-slate-200 p-2 text-sm" rows={3}
                  placeholder="Feature bullets — one per line"
                  value={t.featureBullets ?? ""}
                  onChange={(e) => setSel({ ...sel, tiers: sel.tiers.map((x: any, j: number) => j === i ? { ...x, featureBullets: e.target.value } : x) })} />
              </div>
            ))}
            <div className="flex gap-2">
              <Button size="sm" variant="outline" onClick={() => setSel({ ...sel, tiers: [...(sel.tiers ?? []), { tierCode: "", displayOrder: (sel.tiers?.length ?? 0) * 10 + 10 }] })}>Add tier copy</Button>
              <Button size="sm" onClick={() => void save()}>Save presentation</Button>
              <Button size="sm" variant="ghost" onClick={() => setSel(null)}>Cancel</Button>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  )
}

// ---------------------------------------------------------------- discounts & promotions
function Discounts({ cfg, act }: { cfg: Record<string, any[]>; act: any }) {
  const [ladder, setLadder] = useState("")
  const [promos, setPromos] = useState<any[]>([])
  const [promo, setPromo] = useState({ code: "", name: "", value: "", durationPeriods: "3", stackable: false })
  const [assign, setAssign] = useState({ code: "", ownerUserId: "" })
  const loadPromos = useCallback(async () => setPromos(await aget<any[]>("promotions")), [])
  useEffect(() => {
    void loadPromos()
    const rows = (cfg.discounts ?? []).filter((d: any) => d.active)
    setLadder(rows.map((d: any) => `${d.mincompanies}:${d.percent}`).join(", "))
  }, [cfg.discounts, loadPromos])

  return (
    <div className="grid gap-4 lg:grid-cols-2">
      <Card>
        <CardHeader className="py-3"><CardTitle className="text-sm">Automatic multi-company ladder (spec 18) — "2:5, 3:10, 5:15"</CardTitle></CardHeader>
        <CardContent className="space-y-2 pb-4">
          <div className="flex gap-2">
            <Input className="h-8" value={ladder} onChange={(e) => setLadder(e.target.value)} />
            <Button size="sm" onClick={async () => {
              const rules = ladder.split(",").map((p) => p.trim()).filter(Boolean).map((p) => {
                const [m, v] = p.split(":"); return { minCompanies: Number(m), percent: Number(v) }
              })
              const r = await adminPutDiscounts(rules)
              void act(Promise.resolve({ ok: r.ok, message: r.ok ? "Ladder saved (replaces the active set)." : "Save failed" }))
            }}>Save ladder</Button>
          </div>
          <p className="text-xs text-slate-500">
            Only ACTIVE, billed companies count (spec 19; setting <code>multicompanyeligibility</code>). An empty ladder turns the automatic discount off.
          </p>
        </CardContent>
      </Card>
      <Card>
        <CardHeader className="py-3"><CardTitle className="text-sm">Promotions (spec 20)</CardTitle></CardHeader>
        <CardContent className="space-y-3 pb-4">
          <div className="flex flex-wrap items-end gap-2">
            <Input className="h-8 w-28" placeholder="CODE" value={promo.code} onChange={(e) => setPromo({ ...promo, code: e.target.value })} />
            <Input className="h-8 w-40" placeholder="Name" value={promo.name} onChange={(e) => setPromo({ ...promo, name: e.target.value })} />
            <Input className="h-8 w-20" placeholder="%" value={promo.value} onChange={(e) => setPromo({ ...promo, value: e.target.value })} />
            <Input className="h-8 w-24" placeholder="periods" value={promo.durationPeriods} onChange={(e) => setPromo({ ...promo, durationPeriods: e.target.value })} />
            <label className="flex items-center gap-1 text-xs text-slate-600">
              <input type="checkbox" checked={promo.stackable} onChange={(e) => setPromo({ ...promo, stackable: e.target.checked })} /> stackable
            </label>
            <Button size="sm" onClick={async () => {
              const ok = await act(asend("POST", "promotion", {
                code: promo.code, name: promo.name, discountType: "Percentage",
                value: Number(promo.value), durationPeriods: Number(promo.durationPeriods), stackable: promo.stackable,
              }), false)
              if (ok) void loadPromos()
            }}>Create</Button>
          </div>
          <table className="w-full"><thead><tr><Th>Code</Th><Th>Value</Th><Th>Periods</Th><Th>Redeemed</Th><Th>Active</Th></tr></thead>
            <tbody>{promos.map((p) => (
              <tr key={p.id} className="border-t border-slate-100">
                <Td>{p.code}</Td><Td>{p.discountType === "Fixed" ? money(p.value, "GHS") : `${p.value}%`}</Td>
                <Td>{p.durationPeriods}</Td><Td>{p.redemptions}{p.maxRedemptions ? ` / ${p.maxRedemptions}` : ""}</Td>
                <Td>{p.active ? "✓" : "—"}</Td>
              </tr>
            ))}</tbody>
          </table>
          <div className="flex items-end gap-2 border-t border-slate-100 pt-3">
            <Input className="h-8 w-28" placeholder="CODE" value={assign.code} onChange={(e) => setAssign({ ...assign, code: e.target.value })} />
            <Input className="h-8 flex-1" placeholder="Organization owner userId" value={assign.ownerUserId} onChange={(e) => setAssign({ ...assign, ownerUserId: e.target.value })} />
            <Button size="sm" variant="outline" onClick={async () => {
              const ok = await act(asend("POST", "promotion-assign", assign), false)
              if (ok) void loadPromos()
            }}>Assign to organization</Button>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}

// ---------------------------------------------------------------- organizations inspector
function Organizations({ act }: { act: any }) {
  const [search, setSearch] = useState("")
  const [orgs, setOrgs] = useState<any[]>([])
  const [insp, setInsp] = useState<any | null>(null)
  const [busy, setBusy] = useState(false)
  const [disc, setDisc] = useState({ name: "", discountType: "Percentage", value: "", scope: "Organization", farmId: "", durationPeriods: "", stackable: true, reason: "" })
  const [preview, setPreview] = useState<any | null>(null)
  const [credit, setCredit] = useState({ amount: "", reason: "", reference: "" })

  const find = async () => setOrgs(await aget<any[]>(`organizations?search=${encodeURIComponent(search)}`))
  const open = async (ownerUserId: string) => {
    setBusy(true); setPreview(null)
    try { setInsp(await aget<any>(`organization?ownerUserId=${encodeURIComponent(ownerUserId)}`)) }
    finally { setBusy(false) }
  }
  const refresh = () => insp && void open(insp.account.ownerUserId ?? insp.account.OwnerUserId ?? orgs.find(o => o.accountId === insp.account.id)?.ownerUserId)

  const discBody = () => ({
    ownerUserId: insp.ownerUserIdRef,
    name: disc.name, discountType: disc.discountType, value: Number(disc.value),
    scope: disc.scope, farmId: disc.scope === "Company" ? disc.farmId : null,
    durationPeriods: disc.durationPeriods === "" ? null : Number(disc.durationPeriods),
    stackable: disc.stackable, reason: disc.reason,
  })

  return (
    <div className="space-y-4">
      <Card>
        <CardContent className="flex items-center gap-2 pt-4">
          <Input className="h-9" placeholder="Search organizations by email, name or org code" value={search}
            onChange={(e) => setSearch(e.target.value)} onKeyDown={(e) => e.key === "Enter" && void find()} />
          <Button size="sm" onClick={() => void find()}>Search</Button>
        </CardContent>
      </Card>
      {orgs.length > 0 && !insp && (
        <Card>
          <CardContent className="overflow-x-auto pt-4">
            <table className="w-full"><thead><tr><Th>Owner</Th><Th>Org</Th><Th>Market</Th><Th>Status</Th><Th>Companies</Th><Th></Th></tr></thead>
              <tbody>{orgs.map((o) => (
                <tr key={o.accountId} className="border-t border-slate-100">
                  <Td>{o.ownerName ?? o.ownerEmail ?? o.ownerUserId}</Td><Td>{o.orgCode ?? "—"}</Td>
                  <Td>{o.marketCode} · {o.currencyCode}</Td><Td>{o.status}</Td><Td>{o.companyCount}</Td>
                  <Td><Button size="sm" variant="outline" onClick={() => { void open(o.ownerUserId); (o as any)._sel = true }}>Inspect</Button></Td>
                </tr>
              ))}</tbody>
            </table>
          </CardContent>
        </Card>
      )}
      {busy && <div className="flex justify-center py-8"><Loader2 className="h-5 w-5 animate-spin text-slate-400" /></div>}
      {insp && (() => {
        const owner = orgs.find((o) => o.accountId === insp.account.id)?.ownerUserId ?? ""
        insp.ownerUserIdRef = owner
        const cur = insp.account.currencyCode
        return (
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="text-base font-semibold text-slate-900">
                {insp.ownerName ?? insp.ownerEmail} <span className="font-normal text-slate-500">· {insp.account.marketCode} · {cur} · {insp.account.billingCycle} · {insp.account.status}</span>
              </h2>
              <Button size="sm" variant="ghost" onClick={() => setInsp(null)}>← Back to results</Button>
            </div>

            <Card>
              <CardHeader className="py-3"><CardTitle className="text-sm">Companies (spec 31/32)</CardTitle></CardHeader>
              <CardContent className="overflow-x-auto pb-4">
                <table className="w-full"><thead><tr><Th>Company</Th><Th>Type</Th><Th>Profile</Th><Th>Metric</Th><Th>Tier</Th><Th>Monthly</Th><Th>Annual</Th><Th>Custom/GF</Th><Th>Status</Th></tr></thead>
                  <tbody>{insp.companies.map((c: any) => (
                    <tr key={c.farmId} className="border-t border-slate-100">
                      <Td>{c.companyName}</Td><Td>{c.businessType}</Td><Td>{c.billingProfileCode}</Td>
                      <Td title={c.metricSource}>{Number(c.metricValue).toLocaleString()} <span className="text-xs text-slate-400">({c.metricSource})</span></Td>
                      <Td className="capitalize">{c.tierName ?? "—"}</Td>
                      <Td className="tabular-nums">{money(c.monthlyAmount, cur)}</Td>
                      <Td className="tabular-nums">{money(c.annualPrice, cur)}</Td>
                      <Td className="tabular-nums">{c.customPrice != null ? `C ${c.customPrice}` : c.grandfatheredPrice != null ? `GF ${c.grandfatheredPrice}` : "—"}</Td>
                      <Td>{c.participationStatus} · {c.pricingStatus}</Td>
                    </tr>
                  ))}</tbody>
                </table>
              </CardContent>
            </Card>

            <div className="grid gap-4 lg:grid-cols-2">
              <Card>
                <CardHeader className="py-3"><CardTitle className="text-sm">Next invoice preview — backend-computed (spec 23)</CardTitle></CardHeader>
                <CardContent className="space-y-1 pb-4 text-sm">
                  <div className="flex justify-between"><span className="text-slate-500">Subtotal</span><span className="tabular-nums">{money(insp.preview.subtotal, cur)}</span></div>
                  {(insp.preview.discountBreakdown ?? []).map((d: any) => (
                    <div key={`${d.id}-${d.name}`} className="flex justify-between text-emerald-700"><span>{d.name}</span><span className="tabular-nums">-{money(d.amount, cur)}</span></div>
                  ))}
                  <div className="flex justify-between border-t border-slate-100 pt-1 font-medium"><span>Total</span><span className="tabular-nums">{money(insp.preview.total, cur)}</span></div>
                  {(insp.preview.estimatedCreditApplied ?? 0) > 0 && (
                    <>
                      <div className="flex justify-between text-emerald-700"><span>Credit applied</span><span className="tabular-nums">-{money(insp.preview.estimatedCreditApplied, cur)}</span></div>
                      <div className="flex justify-between font-semibold"><span>Amount due</span><span className="tabular-nums">{money(insp.preview.estimatedAmountDue, cur)}</span></div>
                    </>
                  )}
                  {preview && (
                    <Alert className="mt-2 border-indigo-200 bg-indigo-50/60">
                      <AlertDescription className="text-sm text-indigo-900">
                        With "{disc.name}": total {money(preview.withProposed.total, cur)}, due {money(preview.withProposed.estimatedAmountDue ?? preview.withProposed.total, cur)}
                        {" "}(now {money(preview.current.total, cur)}).
                      </AlertDescription>
                    </Alert>
                  )}
                </CardContent>
              </Card>

              <Card>
                <CardHeader className="py-3"><CardTitle className="text-sm">Assign a discount (spec 21/22, reason required)</CardTitle></CardHeader>
                <CardContent className="space-y-2 pb-4">
                  <div className="grid grid-cols-2 gap-2">
                    <Input className="h-8" placeholder="Name (e.g. Early adopter)" value={disc.name} onChange={(e) => setDisc({ ...disc, name: e.target.value })} />
                    <div className="flex gap-2">
                      <select className="h-8 flex-1 rounded-md border border-slate-200 px-2 text-sm" value={disc.discountType} onChange={(e) => setDisc({ ...disc, discountType: e.target.value })}>
                        <option>Percentage</option><option>Fixed</option>
                      </select>
                      <Input className="h-8 w-20" placeholder={disc.discountType === "Fixed" ? cur : "%"} value={disc.value} onChange={(e) => setDisc({ ...disc, value: e.target.value })} />
                    </div>
                    <select className="h-8 rounded-md border border-slate-200 px-2 text-sm" value={disc.scope} onChange={(e) => setDisc({ ...disc, scope: e.target.value })}>
                      <option>Organization</option><option>Company</option>
                    </select>
                    {disc.scope === "Company" ? (
                      <select className="h-8 rounded-md border border-slate-200 px-2 text-sm" value={disc.farmId} onChange={(e) => setDisc({ ...disc, farmId: e.target.value })}>
                        <option value="">— company —</option>
                        {insp.companies.map((c: any) => <option key={c.farmId} value={c.farmId}>{c.companyName}</option>)}
                      </select>
                    ) : (
                      <Input className="h-8" placeholder="Billing periods (empty = open)" value={disc.durationPeriods} onChange={(e) => setDisc({ ...disc, durationPeriods: e.target.value })} />
                    )}
                  </div>
                  <Input className="h-8" placeholder="Reason (required — audited)" value={disc.reason} onChange={(e) => setDisc({ ...disc, reason: e.target.value })} />
                  <div className="flex gap-2">
                    <Button size="sm" variant="outline" onClick={async () => {
                      const res = await fetch(farmApiUrl("/PlatformBillingAdmin/discount-preview"), {
                        method: "POST", headers: getAuthHeaders(),
                        body: JSON.stringify({ userId: uid(), ...discBody() }),
                      })
                      if (res.ok) setPreview(await res.json())
                    }}>Preview impact</Button>
                    <Button size="sm" onClick={async () => { if (await act(asend("POST", "discount", discBody()), false)) refresh() }}>Assign discount</Button>
                  </div>
                </CardContent>
              </Card>
            </div>

            <div className="grid gap-4 lg:grid-cols-2">
              <Card>
                <CardHeader className="py-3"><CardTitle className="text-sm">Active & past discounts (spec 25/28)</CardTitle></CardHeader>
                <CardContent className="overflow-x-auto pb-4">
                  <table className="w-full"><thead><tr><Th>Name</Th><Th>Value</Th><Th>Scope</Th><Th>Used / periods</Th><Th>Status</Th><Th></Th></tr></thead>
                    <tbody>{insp.discounts.map((d: any) => (
                      <tr key={d.id} className={`border-t border-slate-100 ${d.revokedBy ? "text-slate-400" : ""}`}>
                        <Td><span title={`${d.reason} — by ${d.createdBy}`}>{d.name}</span></Td>
                        <Td>{d.discountType === "Fixed" ? money(d.value, cur) : `${d.value}%`}</Td>
                        <Td>{d.scope}</Td>
                        <Td>{d.appliedCount}{d.durationPeriods ? ` / ${d.durationPeriods} (${d.remainingPeriods} left)` : ""}</Td>
                        <Td>{d.revokedBy ? "revoked" : d.active ? "active" : "ended"}</Td>
                        <Td>{!d.revokedBy && d.active && (
                          <Button size="sm" variant="ghost" className="text-red-600" onClick={async () => {
                            if (await act(asend("DELETE", `discount/${d.id}`), false)) refresh()
                          }}>Revoke</Button>
                        )}</Td>
                      </tr>
                    ))}</tbody>
                  </table>
                </CardContent>
              </Card>

              <Card>
                <CardHeader className="py-3"><CardTitle className="text-sm">Account credits (spec 26/27) — a credit is NOT a discount</CardTitle></CardHeader>
                <CardContent className="space-y-2 pb-4">
                  <div className="flex flex-wrap items-end gap-2">
                    <Input className="h-8 w-28" placeholder={`Amount (${cur})`} value={credit.amount} onChange={(e) => setCredit({ ...credit, amount: e.target.value })} />
                    <Input className="h-8 flex-1" placeholder="Reason (required)" value={credit.reason} onChange={(e) => setCredit({ ...credit, reason: e.target.value })} />
                    <Button size="sm" onClick={async () => {
                      if (!window.confirm(`Issue a credit of ${cur} ${credit.amount}? This will offset the organization's next invoice.`)) return
                      if (await act(asend("POST", "credit", { ownerUserId: owner, amount: Number(credit.amount), reason: credit.reason, reference: credit.reference || null }), false)) refresh()
                    }}>Issue credit</Button>
                  </div>
                  <table className="w-full"><thead><tr><Th>Issued</Th><Th>Used</Th><Th>Remaining</Th><Th>Reason</Th><Th>Invoices</Th><Th></Th></tr></thead>
                    <tbody>{insp.credits.map((c: any) => (
                      <tr key={c.id} className={`border-t border-slate-100 ${c.revokedBy ? "text-slate-400 line-through" : ""}`}>
                        <Td className="tabular-nums">{money(c.amount, c.currencyCode)}</Td>
                        <Td className="tabular-nums">{money(c.used, c.currencyCode)}</Td>
                        <Td className="tabular-nums font-medium">{money(c.remaining, c.currencyCode)}</Td>
                        <Td>{c.reason}</Td>
                        <Td>{c.appliedInvoices.join(", ") || "—"}</Td>
                        <Td>{!c.revokedBy && c.used === 0 && (
                          <Button size="sm" variant="ghost" className="text-red-600" onClick={async () => {
                            if (await act(asend("DELETE", `credit/${c.id}`), false)) refresh()
                          }}>Revoke</Button>
                        )}</Td>
                      </tr>
                    ))}</tbody>
                  </table>
                </CardContent>
              </Card>
            </div>

            <Card>
              <CardHeader className="py-3"><CardTitle className="text-sm">Invoices & payments (spec 31)</CardTitle></CardHeader>
              <CardContent className="grid gap-4 overflow-x-auto pb-4 lg:grid-cols-2">
                <table className="w-full self-start"><thead><tr><Th>Invoice</Th><Th>Period</Th><Th>Total</Th><Th>Credit</Th><Th>Balance</Th><Th>Status</Th></tr></thead>
                  <tbody>{insp.invoices.map((i: any) => (
                    <tr key={i.id} className="border-t border-slate-100">
                      <Td><span title={i.discountBreakdown ?? ""}>{i.invoiceNumber}</span></Td>
                      <Td>{String(i.periodStart).slice(0, 10)}</Td>
                      <Td className="tabular-nums">{money(i.totalAmount, i.currencyCode)}</Td>
                      <Td className="tabular-nums">{i.creditApplied ? money(i.creditApplied, i.currencyCode) : "—"}</Td>
                      <Td className="tabular-nums">{money(i.balance, i.currencyCode)}</Td>
                      <Td>{i.status}</Td>
                    </tr>
                  ))}</tbody>
                </table>
                <table className="w-full self-start"><thead><tr><Th>Payment ref</Th><Th>Provider</Th><Th>Amount</Th><Th>Status</Th></tr></thead>
                  <tbody>{insp.payments.map((p: any) => (
                    <tr key={p.id} className="border-t border-slate-100">
                      <Td className="max-w-48 truncate" >{p.externalReference ?? "—"}</Td>
                      <Td>{p.provider}</Td>
                      <Td className="tabular-nums">{money(p.amount, p.currencyCode)}</Td>
                      <Td>{p.status}</Td>
                    </tr>
                  ))}</tbody>
                </table>
              </CardContent>
            </Card>
          </div>
        )
      })()}
    </div>
  )
}

// ---------------------------------------------------------------- audit
function AuditLog() {
  const [events, setEvents] = useState<any[]>([])
  useEffect(() => { void aget<any[]>("events?limit=150").then(setEvents).catch(() => {}) }, [])
  return (
    <Card>
      <CardHeader className="py-3"><CardTitle className="text-sm">Billing audit trail (spec 28/36) — every commercial action, explainable</CardTitle></CardHeader>
      <CardContent className="overflow-x-auto pb-4">
        <table className="w-full"><thead><tr><Th>When (UTC)</Th><Th>Event</Th><Th>Account</Th><Th>Change</Th><Th>Actor</Th><Th>Ref / reason</Th></tr></thead>
          <tbody>{events.map((e) => (
            <tr key={e.id} className="border-t border-slate-100">
              <Td className="whitespace-nowrap">{String(e.atUtc).replace("T", " ").slice(0, 16)}</Td>
              <Td>{e.eventType}</Td>
              <Td>{e.accountId ?? "—"}</Td>
              <Td className="max-w-80 truncate">{[e.oldValue, e.newValue].filter(Boolean).join(" → ") || "—"}</Td>
              <Td className="max-w-40 truncate">{e.actor ?? "system"}</Td>
              <Td className="max-w-60 truncate">{e.notes ?? "—"}</Td>
            </tr>
          ))}</tbody>
        </table>
      </CardContent>
    </Card>
  )
}
