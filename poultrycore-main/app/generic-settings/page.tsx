"use client"

// Company settings for a Generic business (migration 251).
//
// Two things live here, and they are different questions:
//
//   Modules   which parts of the system this company has at all. Twelve
//             switches, and the menu is built from them.
//   Defaults  how those parts behave -- what a new subscription is prefilled
//             with, whether a billing run posts what it raises, which cards the
//             dashboard shows.
//
// What is NOT here is as deliberate as what is. 251 stores every setting the
// spec lists, but several are not read by anything yet -- grace periods,
// overpayment rules, expense thresholds. A switch that changes nothing is worse
// than no switch, because someone will set it and believe it, so those are
// stored and left off this page until the code that honours them exists.
//
// Separate from /generic-setup, which is the company PROFILE -- name, currency,
// opening cash, business type. That page answers "who is this company"; this
// one answers "how does it work".

import { useEffect, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Loader2, Settings, Save, ArrowLeft } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  getModuleSettings, saveModuleSettings, getBusinessSettings, saveBusinessSettings,
  type GenericModuleSettings, type GenericBusinessSettings,
} from "@/lib/api/generic-subscriptions"
import { invalidateGenericModules, useGenericModules } from "@/hooks/use-generic-modules"
import { BILLING_FREQUENCIES, FREQUENCY_LABELS } from "@/lib/generic/billing-schedule"

type ModuleKey = keyof Omit<GenericModuleSettings, "farmId">

export default function GenericSettingsPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const logout = useLogout()
  const { toast } = useToast()
  const { labels, isSubscriptionBusiness } = useGenericModules()

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [modules, setModules] = useState<GenericModuleSettings | null>(null)
  const [settings, setSettings] = useState<GenericBusinessSettings | null>(null)

  useEffect(() => {
    if (!activeFarmType) return
    if (activeFarmType !== "Generic") {
      router.replace("/dashboard")
      return
    }
    let cancelled = false
    ;(async () => {
      // allSettled: one failing must not leave the other section blank with no
      // explanation of which half went wrong.
      const [m, s] = await Promise.allSettled([getModuleSettings(), getBusinessSettings()])
      if (cancelled) return
      if (m.status === "fulfilled") setModules(m.value)
      else toast({ title: "Could not load modules", description: String(m.reason?.message ?? m.reason), variant: "destructive" })
      if (s.status === "fulfilled") setSettings(s.value)
      else toast({ title: "Could not load settings", description: String(s.reason?.message ?? s.reason), variant: "destructive" })
      setLoading(false)
    })()
    return () => { cancelled = true }
  }, [activeFarmType, router, toast])

  const save = async () => {
    if (!modules || !settings) return
    setSaving(true)
    try {
      const [m, s] = await Promise.all([
        saveModuleSettings(modules),
        saveBusinessSettings(settings),
      ])
      if (m) setModules(m)
      if (s) setSettings(s)
      // The sidebar, top nav, mobile bar and dashboard all read the cached
      // copy. Without this the menu keeps the old toggles until a reload.
      invalidateGenericModules(activeFarmId ?? undefined)
      toast({ title: "Settings saved" })
    } catch (e: any) {
      toast({ title: "Could not save", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  const mod = (key: ModuleKey, value: boolean) =>
    setModules((m) => (m ? { ...m, [key]: value } : m))
  const set = <K extends keyof GenericBusinessSettings>(key: K, value: GenericBusinessSettings[K]) =>
    setSettings((s) => (s ? { ...s, [key]: value } : s))

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <Link href="/generic-setup" className="inline-flex items-center text-sm text-slate-500 hover:text-slate-700 mb-2">
            <ArrowLeft className="h-3 w-3 mr-1" /> Company setup
          </Link>
          <div className="mb-4 flex items-end justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <Settings className="h-6 w-6 text-slate-700" /> Settings
              </h1>
              <p className="text-sm text-slate-500">Which modules this company has, and how they behave.</p>
            </div>
            <Button onClick={save} disabled={saving || loading || !modules || !settings}>
              {saving ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <Save className="h-4 w-4 mr-2" />}
              Save changes
            </Button>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : (
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
              {/* ---- modules ------------------------------------------------ */}
              <Card className="lg:col-span-2">
                <CardHeader className="pb-2">
                  <CardTitle className="text-base">Modules</CardTitle>
                  <CardDescription>
                    Turning a module off hides its menu items. It never deletes anything —
                    a gym that starts selling towels turns Products back on and its old stock is still there.
                  </CardDescription>
                </CardHeader>
                <CardContent>
                  {!modules ? (
                    <p className="text-sm text-slate-500">Modules could not be loaded.</p>
                  ) : (
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-x-8">
                      <Group title="Selling">
                        <Toggle label={labels.subscriptionPlural} hint="Plans, subscriptions and billing runs"
                                checked={modules.enableSubscriptions} onChange={(v) => mod("enableSubscriptions", v)} />
                        <Toggle label={labels.invoicePlural} hint="The invoices a billing run raises"
                                checked={modules.enableInvoices} onChange={(v) => mod("enableInvoices", v)} />
                        <Toggle label={labels.customerBalance} hint="Who owes you, aged, with statements"
                                checked={modules.enableCustomerBalances} onChange={(v) => mod("enableCustomerBalances", v)} />
                      </Group>

                      <Group title="Buying &amp; paying">
                        <Toggle label="Purchases" hint="Buying stock from suppliers"
                                checked={modules.enablePurchases} onChange={(v) => mod("enablePurchases", v)} />
                        <Toggle label="Supplier balances" hint="What you owe vendors — from expenses as well as purchases"
                                checked={modules.enableSupplierBalances} onChange={(v) => mod("enableSupplierBalances", v)} />
                        <Toggle label="Recurring expenses" hint="Templates that raise a bill when it falls due"
                                checked={modules.enableRecurringExpenses} onChange={(v) => mod("enableRecurringExpenses", v)} />
                        <Toggle label="Staff payments" hint="Paying a contractor without a full payroll run"
                                checked={modules.enableStaffPayments} onChange={(v) => mod("enableStaffPayments", v)} />
                      </Group>

                      <Group title="Stock">
                        <Toggle label="Products" hint="A catalogue of things you sell"
                                checked={modules.enableProducts} onChange={(v) => mod("enableProducts", v)} />
                        <Toggle label="Inventory" hint="Stock levels and valuation"
                                checked={modules.enableInventory} onChange={(v) => mod("enableInventory", v)} />
                        <Toggle label="Stock adjustments" hint="Correcting a count"
                                checked={modules.enableStockAdjustments} onChange={(v) => mod("enableStockAdjustments", v)} />
                        <Toggle label="Internal use" hint="Stock consumed by the business itself"
                                checked={modules.enableInternalUse} onChange={(v) => mod("enableInternalUse", v)} />
                      </Group>

                      <Group title="Money">
                        <Toggle label="Cash accounts" hint="Tills, bank accounts and mobile money"
                                checked={modules.enableCashAccounts} onChange={(v) => mod("enableCashAccounts", v)} />
                      </Group>
                    </div>
                  )}
                </CardContent>
              </Card>

              {/* ---- billing defaults --------------------------------------- */}
              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="text-base">{labels.subscription} defaults</CardTitle>
                  <CardDescription>
                    What a new {labels.subscription.toLowerCase()} is prefilled with, and what a billing run does with
                    what it raises.
                  </CardDescription>
                </CardHeader>
                <CardContent className="space-y-4">
                  {!settings ? (
                    <p className="text-sm text-slate-500">Settings could not be loaded.</p>
                  ) : (
                    <>
                      <div>
                        <Label>Billing frequency</Label>
                        <Select value={settings.defaultBillingFrequency}
                                onValueChange={(v) => set("defaultBillingFrequency", v)}>
                          <SelectTrigger><SelectValue /></SelectTrigger>
                          <SelectContent>
                            {BILLING_FREQUENCIES.map((f) => (
                              <SelectItem key={f} value={f}>{FREQUENCY_LABELS[f]}</SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </div>

                      <div>
                        <Label>Payment due after (days)</Label>
                        <NumberInput
                          value={settings.defaultPaymentDueDays}
                          onChange={(e) => set("defaultPaymentDueDays", Math.max(0, Number(e.target.value) || 0))}
                          min={0}
                        />
                        <p className="text-xs text-slate-500 mt-1">
                          0 means due on the day it is raised. An {labels.invoice.toLowerCase()} is overdue the day
                          after its due date.
                        </p>
                      </div>

                      <Toggle
                        label={`Bill new ${labels.subscriptionPlural.toLowerCase()} automatically`}
                        hint="Sets the auto-generate flag on a new subscription. It can still be changed per subscription."
                        checked={settings.autoGenerateInvoices}
                        onChange={(v) => set("autoGenerateInvoices", v)}
                      />

                      <Toggle
                        label={`Approve ${labels.invoicePlural.toLowerCase()} as they are raised`}
                        hint={
                          settings.autoPostInvoices
                            ? `A billing run posts straight to the ${labels.customer.toLowerCase()}'s account — no one reviews it first.`
                            : `A billing run leaves drafts for someone to approve. Nothing is owed until they do.`
                        }
                        checked={settings.autoPostInvoices}
                        onChange={(v) => set("autoPostInvoices", v)}
                      />
                    </>
                  )}
                </CardContent>
              </Card>

              {/* ---- dashboard cards --------------------------------------- */}
              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="text-base">Dashboard cards</CardTitle>
                  <CardDescription>
                    Which numbers the dashboard leads with.
                    {!isSubscriptionBusiness && " This company is not on a subscription template, so it sees the standard dashboard and these have no effect yet."}
                  </CardDescription>
                </CardHeader>
                <CardContent>
                  {!settings ? (
                    <p className="text-sm text-slate-500">Settings could not be loaded.</p>
                  ) : (
                    <div className="space-y-1">
                      <Toggle label="Monthly recurring revenue" checked={settings.showMrr} onChange={(v) => set("showMrr", v)} />
                      <Toggle label="Burn rate" hint="Shown under the monthly spend"
                              checked={settings.showBurnRate} onChange={(v) => set("showBurnRate", v)} />
                      <Toggle label={`Break-even ${labels.customerPlural.toLowerCase()}`}
                              checked={settings.showBreakEvenCustomers} onChange={(v) => set("showBreakEvenCustomers", v)} />
                      <Toggle label={labels.customerBalance} checked={settings.showCustomerBalances} onChange={(v) => set("showCustomerBalances", v)} />
                      <Toggle label="Supplier balances" checked={settings.showSupplierBalances} onChange={(v) => set("showSupplierBalances", v)} />
                      <Toggle label="Cash at hand" checked={settings.showCalculatedCashAtHand} onChange={(v) => set("showCalculatedCashAtHand", v)} />
                      <Toggle label="Stock value" hint="Only meaningful with Products on"
                              checked={settings.showInventoryCards} onChange={(v) => set("showInventoryCards", v)} />
                    </div>
                  )}
                </CardContent>
              </Card>
            </div>
          )}
        </main>
      </div>
    </div>
  )
}

function Group({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="py-2">
      <h3 className="text-xs uppercase tracking-wide text-slate-500 mb-1">{title}</h3>
      <div className="space-y-1">{children}</div>
    </div>
  )
}

function Toggle({
  label, hint, checked, onChange,
}: {
  label: string
  hint?: string
  checked: boolean
  onChange: (v: boolean) => void
}) {
  return (
    <div className="flex items-start justify-between gap-3 py-1.5">
      <div className="min-w-0">
        <div className="text-sm text-slate-900">{label}</div>
        {hint && <div className="text-xs text-slate-500">{hint}</div>}
      </div>
      <Switch checked={checked} onCheckedChange={onChange} className="mt-0.5 shrink-0" />
    </div>
  )
}
