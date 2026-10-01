"use client"

// Platform billing administration (spec Part 27) — SystemAdmin/PlatformOwner
// only; everyone else gets the API's 403 and sees the denial, not the data.
// This console exists so pricing, discounts and per-company billing state
// change through configuration, never through a deployment.

import { useEffect, useState } from "react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { useToast } from "@/hooks/use-toast"
import { Loader2, ShieldAlert } from "lucide-react"
import {
  getAdminConfig,
  adminPutSetting,
  adminPostPrice,
  adminPutDiscounts,
  adminPutCompanyState,
  adminCreditNote,
  adminRunMaintenance,
} from "@/lib/api/platform-billing"

type Row = Record<string, unknown>

export default function PlatformBillingAdminPage() {
  const { toast } = useToast()
  const [cfg, setCfg] = useState<Record<string, Row[]> | null>(null)
  const [denied, setDenied] = useState(false)
  const [loading, setLoading] = useState(true)

  // Small form states — deliberately plain: this is an operator console.
  const [price, setPrice] = useState({ marketCode: "GH", tierCode: "starter", profileCode: "", monthlyPrice: "", annualPrice: "" })
  const [discounts, setDiscounts] = useState("2:5, 3:10, 5:15")
  const [companyState, setCompanyState] = useState({ farmId: "", participationStatus: "", manualScaleValue: "", customMonthlyPrice: "" })
  const [credit, setCredit] = useState({ invoiceNumber: "", amount: "", reason: "" })
  const [busy, setBusy] = useState(false)

  const reload = async () => {
    setLoading(true)
    try {
      setCfg((await getAdminConfig()) as Record<string, Row[]>)
      setDenied(false)
    } catch {
      setDenied(true)
    } finally {
      setLoading(false)
    }
  }
  useEffect(() => {
    void reload()
  }, [])

  const run = async (fn: () => Promise<{ ok: boolean; message?: string }>, done: string) => {
    setBusy(true)
    try {
      const r = await fn()
      toast({
        title: r.ok ? done : "Failed",
        description: r.message,
        variant: r.ok ? undefined : "destructive",
      })
      if (r.ok) void reload()
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar />
      <div className="flex-1 min-w-0 lg:ml-64">
        <DashboardHeader />
        <main className="p-4 sm:p-6 pb-16 lg:pb-6 space-y-6">
          <div>
            <h1 className="text-xl sm:text-3xl font-bold text-slate-900">Platform Billing Admin</h1>
            <p className="text-sm text-slate-600 mt-1">
              Markets, tiers, prices, discounts and per-company billing state — configuration, not code.
            </p>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-600 py-12 justify-center">
              <Loader2 className="h-5 w-5 animate-spin" /> Loading…
            </div>
          ) : denied ? (
            <Alert variant="destructive">
              <ShieldAlert className="h-4 w-4" />
              <AlertDescription>
                Platform administrators only (SystemAdmin / PlatformOwner). Your account does not have this role.
              </AlertDescription>
            </Alert>
          ) : cfg ? (
            <>
              {/* Live configuration, read straight from the tables */}
              <div className="grid lg:grid-cols-2 gap-4">
                <Card>
                  <CardHeader className="pb-2"><CardTitle className="text-base">Price book entries</CardTitle></CardHeader>
                  <CardContent className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Market</TableHead><TableHead>Tier</TableHead><TableHead>Profile</TableHead>
                          <TableHead className="text-right">Monthly</TableHead><TableHead>Effective</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {(cfg.priceEntries ?? []).map((e, i) => (
                          <TableRow key={i} className={e.effectiveto ? "opacity-50" : ""}>
                            <TableCell>{String(e.marketcode)}</TableCell>
                            <TableCell>{String(e.tiercode)}</TableCell>
                            <TableCell>{String(e.profilecode ?? "any")}</TableCell>
                            <TableCell className="text-right">{String(e.currencycode)} {Number(e.monthlyprice).toLocaleString()}</TableCell>
                            <TableCell className="text-xs">
                              {new Date(String(e.effectivefrom)).toLocaleDateString()}
                              {e.effectiveto ? ` → ${new Date(String(e.effectiveto)).toLocaleDateString()}` : " →"}
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </CardContent>
                </Card>

                <Card>
                  <CardHeader className="pb-2"><CardTitle className="text-base">Settings & discounts</CardTitle></CardHeader>
                  <CardContent className="space-y-2 text-sm">
                    {(cfg.settings ?? []).map((s, i) => (
                      <div key={i} className="flex items-center justify-between gap-2">
                        <span className="text-slate-600">{String(s.key)}</span>
                        <SettingEditor
                          k={String(s.key)}
                          value={String(s.value)}
                          onSave={(v) => void run(() => adminPutSetting(String(s.key), v).then((r) => ({ ok: r.ok })), "Setting saved")}
                        />
                      </div>
                    ))}
                    <div className="pt-2 border-t">
                      <p className="text-slate-600 mb-1">Discount ladder (min:percent, comma-separated)</p>
                      <div className="flex gap-2">
                        <Input value={discounts} onChange={(e) => setDiscounts(e.target.value)} />
                        <Button
                          size="sm"
                          disabled={busy}
                          onClick={() =>
                            void run(async () => {
                              const rules = discounts.split(",").map((p) => {
                                const [n, pc] = p.split(":").map((x) => x.trim())
                                return { minCompanies: Number(n), percent: Number(pc) }
                              }).filter((r) => r.minCompanies > 0 && r.percent >= 0)
                              const r = await adminPutDiscounts(rules)
                              return { ok: r.ok }
                            }, "Discount rules replaced")
                          }
                        >
                          Save
                        </Button>
                      </div>
                      <p className="text-xs text-slate-500 mt-1">
                        Active now:{" "}
                        {(cfg.discounts ?? []).filter((d) => d.active).map((d) => `${d.mincompanies}+ → ${d.percent}%`).join(", ") || "none (0%)"}
                      </p>
                    </div>
                  </CardContent>
                </Card>
              </div>

              {/* Configure a price — closes the old entry, inserts effective-dated new one */}
              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="text-base">Configure a price</CardTitle>
                  <CardDescription>Never edits history: the current entry is closed and a new effective-dated one is created.</CardDescription>
                </CardHeader>
                <CardContent className="flex flex-wrap items-end gap-2">
                  <Labeled label="Market"><Input className="w-20" value={price.marketCode} onChange={(e) => setPrice({ ...price, marketCode: e.target.value.toUpperCase() })} /></Labeled>
                  <Labeled label="Tier"><Input className="w-28" value={price.tierCode} onChange={(e) => setPrice({ ...price, tierCode: e.target.value })} /></Labeled>
                  <Labeled label="Profile (blank = any)"><Input className="w-48" value={price.profileCode} onChange={(e) => setPrice({ ...price, profileCode: e.target.value })} /></Labeled>
                  <Labeled label="Monthly"><Input className="w-28" type="number" value={price.monthlyPrice} onChange={(e) => setPrice({ ...price, monthlyPrice: e.target.value })} /></Labeled>
                  <Labeled label="Annual (optional)"><Input className="w-28" type="number" value={price.annualPrice} onChange={(e) => setPrice({ ...price, annualPrice: e.target.value })} /></Labeled>
                  <Button
                    disabled={busy || !price.monthlyPrice}
                    onClick={() =>
                      void run(() => adminPostPrice({
                        marketCode: price.marketCode,
                        tierCode: price.tierCode,
                        profileCode: price.profileCode || null,
                        monthlyPrice: Number(price.monthlyPrice),
                        annualPrice: price.annualPrice ? Number(price.annualPrice) : null,
                      }), "Price configured")
                    }
                  >
                    Save price
                  </Button>
                </CardContent>
              </Card>

              {/* Per-company state: participation, manual scale, custom price */}
              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="text-base">Company billing state</CardTitle>
                  <CardDescription>Exempt/archive a company, set a manual scale for profiles without a metric, or a custom (enterprise) price.</CardDescription>
                </CardHeader>
                <CardContent className="flex flex-wrap items-end gap-2">
                  <Labeled label="Farm ID"><Input className="w-72 font-mono text-xs" value={companyState.farmId} onChange={(e) => setCompanyState({ ...companyState, farmId: e.target.value })} /></Labeled>
                  <Labeled label="Status (blank = keep)"><Input className="w-32" placeholder="Active/Archived/Exempt" value={companyState.participationStatus} onChange={(e) => setCompanyState({ ...companyState, participationStatus: e.target.value })} /></Labeled>
                  <Labeled label="Manual scale"><Input className="w-24" type="number" value={companyState.manualScaleValue} onChange={(e) => setCompanyState({ ...companyState, manualScaleValue: e.target.value })} /></Labeled>
                  <Labeled label="Custom price"><Input className="w-24" type="number" value={companyState.customMonthlyPrice} onChange={(e) => setCompanyState({ ...companyState, customMonthlyPrice: e.target.value })} /></Labeled>
                  <Button
                    disabled={busy || !companyState.farmId}
                    onClick={() =>
                      void run(() => adminPutCompanyState({
                        farmId: companyState.farmId,
                        participationStatus: companyState.participationStatus || null,
                        manualScaleValue: companyState.manualScaleValue ? Number(companyState.manualScaleValue) : null,
                        customMonthlyPrice: companyState.customMonthlyPrice ? Number(companyState.customMonthlyPrice) : null,
                        clearCustomPrice: false,
                        clearGrandfatheredPrice: false,
                      }), "Company state saved")
                    }
                  >
                    Save
                  </Button>
                </CardContent>
              </Card>

              {/* Credit note + maintenance */}
              <div className="grid lg:grid-cols-2 gap-4">
                <Card>
                  <CardHeader className="pb-2">
                    <CardTitle className="text-base">Credit note</CardTitle>
                    <CardDescription>Reduces an invoice&apos;s balance as a new record; the invoice itself is never rewritten.</CardDescription>
                  </CardHeader>
                  <CardContent className="flex flex-wrap items-end gap-2">
                    <Labeled label="Invoice #"><Input className="w-40 font-mono text-xs" value={credit.invoiceNumber} onChange={(e) => setCredit({ ...credit, invoiceNumber: e.target.value })} /></Labeled>
                    <Labeled label="Amount"><Input className="w-24" type="number" value={credit.amount} onChange={(e) => setCredit({ ...credit, amount: e.target.value })} /></Labeled>
                    <Labeled label="Reason"><Input className="w-48" value={credit.reason} onChange={(e) => setCredit({ ...credit, reason: e.target.value })} /></Labeled>
                    <Button
                      disabled={busy || !credit.invoiceNumber || !credit.amount || !credit.reason}
                      onClick={() => void run(() => adminCreditNote(credit.invoiceNumber, Number(credit.amount), credit.reason), "Credit applied")}
                    >
                      Apply credit
                    </Button>
                  </CardContent>
                </Card>

                <Card>
                  <CardHeader className="pb-2">
                    <CardTitle className="text-base">Maintenance</CardTitle>
                    <CardDescription>Runs the same pass the scheduler runs: market changes, dunning statuses, cancellations, auto-invoices.</CardDescription>
                  </CardHeader>
                  <CardContent>
                    <Button
                      variant="outline"
                      disabled={busy}
                      onClick={async () => {
                        setBusy(true)
                        try {
                          const r = await adminRunMaintenance()
                          toast({ title: "Maintenance run", description: r.report })
                          void reload()
                        } finally {
                          setBusy(false)
                        }
                      }}
                    >
                      Run now
                    </Button>
                  </CardContent>
                </Card>
              </div>
            </>
          ) : null}
        </main>
      </div>
    </div>
  )
}

function Labeled({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="text-xs text-slate-600 space-y-1">
      <span>{label}</span>
      {children}
    </label>
  )
}

function SettingEditor({ k, value, onSave }: { k: string; value: string; onSave: (v: string) => void }) {
  const [v, setV] = useState(value)
  return (
    <span className="flex items-center gap-1">
      <Input className="h-7 w-24 text-xs" value={v} onChange={(e) => setV(e.target.value)} />
      {v !== value && (
        <Button size="sm" className="h-7 px-2 text-xs" onClick={() => onSave(v)}>
          Save
        </Button>
      )}
    </span>
  )
}
