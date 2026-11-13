"use client"

// Generic Customer Credits — deep copy of poultry customer-credits visual structure.
// Matches poultry's header, KPI cards, styled tabs with icons/counts, search beside
// tabs, and card padding. The generic backend has simpler data (no events/refunds),
// so we match the visual design with available data.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Badge } from "@/components/ui/badge"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { tabCountCls, tabListCls, tabTriggerCls } from "@/lib/ui/tab-styles"
import { PiggyBank, Plus, Loader2, Search, RefreshCw, Users } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { getCustomerCredits, createCustomerCredit, getCustomers, type GenericCustomerCredit, type GenericCustomer } from "@/lib/api/generic"
import { fmtDateTime } from "@/lib/utils/company-datetime"


const CREDIT_TYPES = ["Overpayment", "Advance", "CreditNote", "Refund"]
const TYPE_COLORS: Record<string, string> = {
  Overpayment: "border-blue-300 text-blue-700",
  Advance: "border-emerald-300 text-emerald-700",
  CreditNote: "border-amber-300 text-amber-700",
  Refund: "border-violet-300 text-violet-700",
}
const STATUS_COLORS: Record<string, string> = {
  Active: "border-blue-300 text-blue-700",
  Used: "border-slate-300 text-slate-500",
  Expired: "border-amber-300 text-amber-700",
}

type Tab = "credits" | "summary"

export default function GenericCustomerCreditsPage() {
  const router = useRouter()
  const logout = useLogout()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const gh = useFmt()

  const [tab, setTab] = useState<Tab>("credits")
  const [rows, setRows] = useState<GenericCustomerCredit[]>([])
  const [customers, setCustomers] = useState<GenericCustomer[]>([])
  const [loading, setLoading] = useState(true)
  const [createOpen, setCreateOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [search, setSearch] = useState("")
  const [form, setForm] = useState({ genericCustomerId: 0, creditType: "Overpayment", amount: 0, creditDate: new Date().toISOString().split("T")[0], notes: "" })

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const [credits, custs] = await Promise.all([getCustomerCredits(), getCustomers()])
      setRows(credits); setCustomers(custs)
    } catch (e: any) { toast({ title: "Could not load", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  const totals = useMemo(() => {
    let total = 0, active = 0, used = 0
    for (const c of rows) { total += c.amount; if (c.status === "Active") active += c.remainingBalance; else used += c.amount - c.remainingBalance }
    return { total, active, used, count: rows.length }
  }, [rows])

  const customerSummary = useMemo(() => {
    const map = new Map<string, { name: string; total: number; active: number; count: number }>()
    for (const c of rows) {
      const key = c.customerName ?? "Unknown"
      const existing = map.get(key) ?? { name: key, total: 0, active: 0, count: 0 }
      existing.total += c.amount
      existing.count++
      if (c.status === "Active") existing.active += c.remainingBalance
      map.set(key, existing)
    }
    return Array.from(map.values()).sort((a, b) => b.active - a.active)
  }, [rows])

  const filteredRows = useMemo(() => {
    if (!search) return rows
    const q = search.toLowerCase()
    return rows.filter((c) => (c.customerName ?? "").toLowerCase().includes(q) || c.creditType.toLowerCase().includes(q) || (c.notes ?? "").toLowerCase().includes(q))
  }, [rows, search])

  const pg = usePagination(filteredRows)
  const summaryPg = usePagination(customerSummary)

  async function doCreate() {
    if (!form.genericCustomerId) { toast({ title: "Select a customer", variant: "destructive" }); return }
    if (form.amount <= 0) { toast({ title: "Amount must be > 0", variant: "destructive" }); return }
    setSaving(true)
    try {
      await createCustomerCredit(form)
      toast({ title: "Credit recorded" })
      setCreateOpen(false)
      setForm({ genericCustomerId: 0, creditType: "Overpayment", amount: 0, creditDate: new Date().toISOString().split("T")[0], notes: "" })
      await load()
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6 space-y-4">
          {/* Header — matching poultry customer-credits */}
          <div className="flex flex-wrap items-start justify-between gap-2">
            <div>
              <h1 className="flex items-center gap-2 text-2xl font-semibold text-slate-900">
                <PiggyBank className="h-6 w-6 text-blue-600" /> Customer Credits
              </h1>
              <p className="max-w-2xl text-sm text-slate-600">
                Advances, overpayments and credit notes held for customers. Use it on their next sale or refund it.
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              <Button onClick={() => setCreateOpen(true)} className="h-10 bg-blue-600 hover:bg-blue-700">
                <Plus className="mr-1 h-4 w-4" /> Add credit
              </Button>
              <Button variant="outline" onClick={load} disabled={loading} className="h-10">
                <RefreshCw className={loading ? "mr-1 h-4 w-4 animate-spin" : "mr-1 h-4 w-4"} /> Refresh
              </Button>
            </div>
          </div>

          {/* KPI tiles — matching poultry style */}
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <Card><CardContent className="p-4">
              <div className="text-xs text-slate-500">Available credit</div>
              <div className="text-2xl font-semibold tabular-nums text-blue-700">{gh(totals.active)}</div>
            </CardContent></Card>
            <Card><CardContent className="p-4">
              <div className="text-xs text-slate-500">Customers with credit</div>
              <div className="text-2xl font-semibold tabular-nums">{customerSummary.length}</div>
            </CardContent></Card>
            <Card><CardContent className="p-4">
              <div className="text-xs text-slate-500">Total credited</div>
              <div className="text-2xl font-semibold tabular-nums">{gh(totals.total)}</div>
            </CardContent></Card>
            <Card><CardContent className="p-4">
              <div className="text-xs text-slate-500">Used</div>
              <div className="text-2xl font-semibold tabular-nums">{gh(totals.used)}</div>
            </CardContent></Card>
          </div>

          {/* Tabs — matching poultry styled tabs with icons and counts */}
          <Tabs value={tab} onValueChange={(v) => setTab(v as Tab)} className="space-y-3">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <TabsList className={tabListCls}>
                <TabsTrigger value="credits" className={tabTriggerCls}>
                  <PiggyBank className="h-4 w-4" /> Credits
                  <span className={tabCountCls}>{rows.length}</span>
                </TabsTrigger>
                <TabsTrigger value="summary" className={tabTriggerCls}>
                  <Users className="h-4 w-4" /> By Customer
                  <span className={tabCountCls}>{customerSummary.length}</span>
                </TabsTrigger>
              </TabsList>
              <div className="relative w-full sm:w-72">
                <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
                <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search customer" className="h-10 pl-9" />
              </div>
            </div>

            <TabsContent value="credits">
              <Card><CardContent className="p-0 sm:p-0">
                {loading ? (
                  <div className="flex items-center gap-2 p-8 text-sm text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
                ) : (
                  <MobileCardList defaultOpen striped stripeAccent="blue"
                    items={pg.pageItems} pagination={pg.paginationProps}
                    getKey={(c: any) => c.genericCustomerCreditId}
                    primary={(c: any) => c.customerName ?? "Unknown"}
                    secondary={(c: any) => fmtDateTime(c.creditDate, c)}
                    trailing={(c: any) => <Badge variant="outline" className={STATUS_COLORS[c.status] ?? ""}>{c.status}</Badge>}
                    highlights={(c: any) => [
                      { label: "Amount", value: gh(c.amount), accent: "blue" as const },
                      { label: "Remaining", value: gh(c.remainingBalance), accent: c.remainingBalance > 0 ? "emerald" as const : "slate" as const },
                    ]}
                    details={(c: any) => [
                      { label: "Type", value: c.creditType },
                      { label: "Notes", value: c.notes ?? "—" },
                    ]}
                    emptyState={
                      <div className="p-8 text-center text-sm text-slate-500">
                        {search ? "No customer matches." : "No customer has credit. Nothing is being held for anyone."}
                      </div>
                    }
                    desktopTable={
                      <div className="overflow-x-auto"><Table>
                        <TableHeader><TableRow>
                          <TableHead>Date</TableHead><TableHead>Customer</TableHead><TableHead>Type</TableHead>
                          <TableHead className="text-right">Amount</TableHead><TableHead className="text-right">Remaining</TableHead>
                          <TableHead>Status</TableHead><TableHead>Notes</TableHead>
                        </TableRow></TableHeader>
                        <TableBody>
                          {filteredRows.length === 0 ? <TableRow><TableCell colSpan={7} className="text-center text-slate-500 py-6">{search ? "No customer matches." : "No credits."}</TableCell></TableRow>
                          : pg.pageItems.map((c: any) => (
                            <TableRow key={c.genericCustomerCreditId}>
                              <TableCell className="whitespace-nowrap">{fmtDateTime(c.creditDate, c)}</TableCell>
                              <TableCell className="font-medium">{c.customerName ?? "—"}</TableCell>
                              <TableCell><Badge variant="outline" className={TYPE_COLORS[c.creditType] ?? ""}>{c.creditType}</Badge></TableCell>
                              <TableCell className="text-right tabular-nums">{gh(c.amount)}</TableCell>
                              <TableCell className="text-right tabular-nums font-semibold">{gh(c.remainingBalance)}</TableCell>
                              <TableCell><Badge variant="outline" className={STATUS_COLORS[c.status] ?? ""}>{c.status}</Badge></TableCell>
                              <TableCell className="text-sm text-slate-600 max-w-xs truncate">{c.notes ?? "—"}</TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table></div>
                    }
                  />
                )}
              </CardContent></Card>
            </TabsContent>

            <TabsContent value="summary">
              <Card><CardContent className="p-0 sm:p-0">
                <MobileCardList defaultOpen striped stripeAccent="blue"
                  items={summaryPg.pageItems} pagination={summaryPg.paginationProps}
                  getKey={(s: any) => s.name}
                  primary={(s: any) => s.name}
                  secondary={(s: any) => `${s.count} credit(s)`}
                  trailing={(s: any) => <span className="font-semibold tabular-nums text-blue-700">{gh(s.active)}</span>}
                  highlights={(s: any) => [
                    { label: "Total", value: gh(s.total), accent: "blue" as const },
                    { label: "Active", value: gh(s.active), accent: s.active > 0 ? "emerald" as const : "slate" as const },
                  ]}
                  details={(s: any) => [
                    { label: "Credits", value: String(s.count) },
                  ]}
                  emptyState={<div className="p-8 text-center text-sm text-slate-500">No customer credits.</div>}
                  desktopTable={
                    <div className="overflow-x-auto"><Table>
                      <TableHeader><TableRow>
                        <TableHead>Customer</TableHead>
                        <TableHead className="text-right">Total Credited</TableHead>
                        <TableHead className="text-right">Active Balance</TableHead>
                        <TableHead className="text-right">Credits</TableHead>
                      </TableRow></TableHeader>
                      <TableBody>
                        {customerSummary.length === 0 ? <TableRow><TableCell colSpan={4} className="text-center text-slate-500 py-6">No customer credits.</TableCell></TableRow>
                        : summaryPg.pageItems.map((s: any) => (
                          <TableRow key={s.name}>
                            <TableCell className="font-medium">{s.name}</TableCell>
                            <TableCell className="text-right tabular-nums">{gh(s.total)}</TableCell>
                            <TableCell className="text-right tabular-nums font-semibold text-blue-700">{gh(s.active)}</TableCell>
                            <TableCell className="text-right">{s.count}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table></div>
                  }
                />
              </CardContent></Card>
            </TabsContent>
          </Tabs>
        </main>
      </div>

      {/* Create dialog — matching poultry manual credit dialog */}
      <Dialog open={createOpen} onOpenChange={setCreateOpen}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <PiggyBank className="w-5 h-5 text-blue-600" /> Record customer credit
            </DialogTitle>
            <DialogDescription>Add a credit for a customer — overpayment, advance, credit note or refund.</DialogDescription>
          </DialogHeader>
          <FormSection title="Credit details" color="indigo">
            <FormField label="Customer *">
              <Select value={form.genericCustomerId ? String(form.genericCustomerId) : ""} onValueChange={(v) => setForm({ ...form, genericCustomerId: Number(v) })}>
                <SelectTrigger><SelectValue placeholder="Select customer" /></SelectTrigger>
                <SelectContent>{customers.filter((c) => c.isActive !== false).map((c) => <SelectItem key={c.genericCustomerId} value={String(c.genericCustomerId)}>{c.customerName}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Credit type">
              <Select value={form.creditType} onValueChange={(v) => setForm({ ...form, creditType: v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>{CREDIT_TYPES.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent>
              </Select>
            </FormField>
            <FormField label="Amount *"><NumberInput min={0} step="0.01" value={form.amount} onChange={(e) => setForm({ ...form, amount: Number(e.target.value) || 0 })} /></FormField>
            <FormField label="Date"><Input type="date" value={form.creditDate} onChange={(e) => setForm({ ...form, creditDate: e.target.value })} /></FormField>
            <FormField label="Notes"><Input value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></FormField>
          </FormSection>
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => setCreateOpen(false)}>Cancel</Button>
            <Button onClick={doCreate} disabled={saving}>{saving ? <Loader2 className="h-4 w-4 animate-spin" /> : "Record Credit"}</Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}
