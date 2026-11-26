"use client"

// Coupons — discount codes that can be applied to subscriptions at creation.
// Migration 499.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { Dialog, DialogContent, DialogDescription, DialogHeader } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { FormSection, FormField } from "@/components/ui/form-section"
import { FORM_DIALOG_CONTENT, FORM_DIALOG_PRIMARY, FormDialogFooter, FormDialogTitle } from "@/components/ui/form-dialog"
import { ListFilters } from "@/components/ui/list-filters"
import {
  Loader2, Plus, Tag, Percent, DollarSign, Ban, Check,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import {
  getCoupons, createCoupon, deactivateCoupon, getServicePlans,
  type CouponRow, type GenericServicePlan,
} from "@/lib/api/generic-subscriptions"
import { fmtDateTime } from "@/lib/utils/company-datetime"

const today = () => new Date().toISOString().slice(0, 10)

export default function GenericCouponsPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  const [rows, setRows] = useState<CouponRow[]>([])
  const [plans, setPlans] = useState<GenericServicePlan[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [open, setOpen] = useState(false)
  const [search, setSearch] = useState("")
  const [showInactive, setShowInactive] = useState(false)

  // Create form
  const [form, setForm] = useState({
    code: "", description: "", discountType: "Flat" as "Flat" | "Percentage",
    discountValue: "", maxUses: "", maxUsesPerCustomer: "",
    validFrom: "", validUntil: "", applicableServiceId: "",
  })

  const load = async () => {
    setLoading(true)
    try {
      const [coupons, planRows] = await Promise.all([
        getCoupons(),
        getServicePlans(true).catch(() => []),
      ])
      setRows(coupons)
      setPlans(planRows)
    } catch (e: any) {
      toast({ title: "Could not load coupons", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  const visible = useMemo(() => {
    const q = search.trim().toLowerCase()
    return rows.filter((r) => {
      if (!showInactive && !r.isActive) return false
      if (q) {
        const hay = [r.code, r.description, r.serviceName].filter(Boolean).join(" ").toLowerCase()
        if (!hay.includes(q)) return false
      }
      return true
    })
  }, [rows, search, showInactive])

  const pg = usePagination(visible)

  const stats = useMemo(() => ({
    active: rows.filter((r) => r.isActive).length,
    totalUsed: rows.reduce((s, r) => s + r.usedCount, 0),
    expired: rows.filter((r) => r.validUntil && new Date(r.validUntil) < new Date()).length,
  }), [rows])

  const resetForm = () => setForm({
    code: "", description: "", discountType: "Flat", discountValue: "",
    maxUses: "", maxUsesPerCustomer: "", validFrom: "", validUntil: "", applicableServiceId: "",
  })

  const generateCode = () => {
    const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    let code = ""
    for (let i = 0; i < 8; i++) code += chars[Math.floor(Math.random() * chars.length)]
    setForm((f) => ({ ...f, code }))
  }

  const onSave = async () => {
    if (!form.code.trim()) { toast({ title: "Enter a coupon code", variant: "destructive" }); return }
    if (!Number(form.discountValue)) { toast({ title: "Enter a discount value", variant: "destructive" }); return }
    setSaving(true)
    try {
      await createCoupon({
        code: form.code.trim().toUpperCase(),
        description: form.description.trim() || null,
        discountType: form.discountType,
        discountValue: Number(form.discountValue),
        maxUses: form.maxUses ? Number(form.maxUses) : null,
        maxUsesPerCustomer: form.maxUsesPerCustomer ? Number(form.maxUsesPerCustomer) : null,
        validFrom: form.validFrom || null,
        validUntil: form.validUntil || null,
        applicableServiceId: form.applicableServiceId ? Number(form.applicableServiceId) : null,
      })
      toast({ title: "Coupon created", description: `Code ${form.code.toUpperCase()} is now active.` })
      setOpen(false)
      resetForm()
      await load()
    } catch (e: any) {
      toast({ title: "Could not create coupon", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  const onDeactivate = async (c: CouponRow) => {
    try {
      await deactivateCoupon(c.genericCouponId)
      toast({ title: `${c.code} deactivated` })
      await load()
    } catch (e: any) {
      toast({ title: "Could not deactivate", description: e?.message ?? String(e), variant: "destructive" })
    }
  }

  const isExpired = (c: CouponRow) => c.validUntil && new Date(c.validUntil) < new Date()
  const isExhausted = (c: CouponRow) => c.maxUses != null && c.usedCount >= c.maxUses

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-1 flex flex-wrap items-start justify-between gap-2">
            <h1 className="flex items-center gap-2 text-2xl font-semibold text-slate-900">
              <Tag className="h-6 w-6 text-orange-600" /> Coupons & Promo Codes
            </h1>
            <Button onClick={() => { resetForm(); setOpen(true) }} className="h-10">
              <Plus className="h-4 w-4 mr-1" /> New coupon
            </Button>
          </div>
          <p className="mb-4 text-sm text-slate-500">
            {stats.active} active · {stats.totalUsed} total uses
            {stats.expired > 0 && <> · {stats.expired} expired</>}
          </p>

          {/* KPI cards */}
          <div className="mb-4 grid grid-cols-3 gap-3">
            <div className="rounded-lg border bg-white p-3">
              <div className="text-xs text-slate-500">Active coupons</div>
              <div className="mt-1 text-xl font-bold tabular-nums">{stats.active}</div>
            </div>
            <div className="rounded-lg border bg-white p-3">
              <div className="text-xs text-slate-500">Total redemptions</div>
              <div className="mt-1 text-xl font-bold tabular-nums text-emerald-700">{stats.totalUsed}</div>
            </div>
            <div className="rounded-lg border bg-white p-3">
              <div className="text-xs text-slate-500">Expired</div>
              <div className="mt-1 text-xl font-bold tabular-nums">{stats.expired}</div>
            </div>
          </div>

          <div className="flex flex-wrap items-end gap-2 mb-3">
            <div className="flex-1 min-w-[220px]">
              <ListFilters search={search} setSearch={setSearch} searchOnly searchPlaceholder="Search code, description…" />
            </div>
            <label className="flex items-center gap-1.5 text-sm cursor-pointer pb-1">
              <input type="checkbox" checked={showInactive} onChange={(e) => setShowInactive(e.target.checked)} className="rounded" />
              Show inactive
            </label>
          </div>

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="flex items-center gap-2 p-6 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : visible.length === 0 ? (
                <div className="p-8 text-center text-slate-500">
                  <Tag className="mx-auto mb-3 h-10 w-10 text-slate-300" />
                  <p className="font-medium text-slate-700">No coupons yet</p>
                  <p className="mt-1">Create a promo code to offer discounts on subscriptions.</p>
                </div>
              ) : (
                <>
                  {/* Mobile */}
                  <div className="space-y-2 p-3 lg:hidden">
                    {pg.pageItems.map((c, idx) => (
                      <div key={c.genericCouponId} className={cn("rounded-xl border p-3 shadow-sm", idx % 2 === 0 ? "border-orange-200 bg-orange-50/60" : "border-slate-200 bg-white")}>
                        <div className="flex items-start justify-between gap-2">
                          <div>
                            <span className="font-mono text-sm font-bold text-orange-700">{c.code}</span>
                            {c.description && <div className="mt-0.5 text-sm text-slate-600">{c.description}</div>}
                          </div>
                          <div className="text-right">
                            <span className="font-semibold">
                              {c.discountType === "Percentage" ? `${c.discountValue}%` : fmt(c.discountValue)} off
                            </span>
                          </div>
                        </div>
                        <div className="mt-2 flex flex-wrap gap-1">
                          {c.isActive ? <Badge variant="outline" className="border-emerald-300 bg-emerald-50 text-emerald-700">Active</Badge>
                            : <Badge variant="outline" className="border-slate-300 bg-slate-100 text-slate-500">Inactive</Badge>}
                          {isExpired(c) && <Badge variant="outline" className="border-rose-300 bg-rose-50 text-rose-700">Expired</Badge>}
                          {isExhausted(c) && <Badge variant="outline" className="border-amber-300 bg-amber-50 text-amber-700">Limit reached</Badge>}
                        </div>
                        <div className="mt-2 grid grid-cols-2 gap-x-3 gap-y-1 text-xs text-slate-500">
                          <span>Used: {c.usedCount}{c.maxUses != null ? ` / ${c.maxUses}` : ""}</span>
                          {c.serviceName && <span className="truncate">Plan: {c.serviceName}</span>}
                          {c.validFrom && <span>From: {c.validFrom}</span>}
                          {c.validUntil && <span>Until: {c.validUntil}</span>}
                        </div>
                        {c.isActive && (
                          <Button size="sm" variant="outline" className="mt-2 h-9 w-full text-rose-600 border-rose-200"
                            onClick={() => onDeactivate(c)}>
                            <Ban className="mr-1 h-3.5 w-3.5" /> Deactivate
                          </Button>
                        )}
                      </div>
                    ))}
                    <div className="px-3 py-3"><DataPagination {...pg.paginationProps} /></div>
                  </div>

                  {/* Desktop */}
                  <div className="hidden lg:block">
                    <Table className="w-full [&_td]:whitespace-normal [&_th]:whitespace-normal">
                      <TableHeader>
                        <TableRow>
                          <TableHead>Code</TableHead>
                          <TableHead>Description</TableHead>
                          <TableHead>Discount</TableHead>
                          <TableHead>Plan</TableHead>
                          <TableHead className="text-center">Used</TableHead>
                          <TableHead>Valid from</TableHead>
                          <TableHead>Valid until</TableHead>
                          <TableHead>Status</TableHead>
                          <TableHead className="w-20"><span className="sr-only">Actions</span></TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {pg.pageItems.map((c) => (
                          <TableRow key={c.genericCouponId} className={!c.isActive ? "text-slate-400" : undefined}>
                            <TableCell className="font-mono font-bold text-orange-700 whitespace-nowrap!">{c.code}</TableCell>
                            <TableCell className="text-slate-600">{c.description || "—"}</TableCell>
                            <TableCell className="whitespace-nowrap! font-semibold">
                              {c.discountType === "Percentage" ? (
                                <span className="flex items-center gap-1"><Percent className="h-3.5 w-3.5 text-blue-600" /> {c.discountValue}%</span>
                              ) : (
                                <span className="flex items-center gap-1"><DollarSign className="h-3.5 w-3.5 text-emerald-600" /> {fmt(c.discountValue)}</span>
                              )}
                            </TableCell>
                            <TableCell>{c.serviceName ?? "All plans"}</TableCell>
                            <TableCell className="text-center tabular-nums">
                              {c.usedCount}{c.maxUses != null ? ` / ${c.maxUses}` : ""}
                            </TableCell>
                            <TableCell className="whitespace-nowrap!">{c.validFrom ?? "—"}</TableCell>
                            <TableCell className="whitespace-nowrap!">{c.validUntil ?? "—"}</TableCell>
                            <TableCell>
                              <div className="flex items-center gap-1 flex-wrap">
                                {c.isActive
                                  ? <Badge variant="outline" className="border-emerald-300 bg-emerald-50 text-emerald-700">Active</Badge>
                                  : <Badge variant="outline" className="border-slate-300 bg-slate-100 text-slate-500">Inactive</Badge>}
                                {isExpired(c) && <Badge variant="outline" className="border-rose-300 bg-rose-50 text-rose-700">Expired</Badge>}
                                {isExhausted(c) && <Badge variant="outline" className="border-amber-300 bg-amber-50 text-amber-700">Full</Badge>}
                              </div>
                            </TableCell>
                            <TableCell className="text-right">
                              {c.isActive && (
                                <Button size="sm" variant="ghost" className="h-8 text-rose-600" onClick={() => onDeactivate(c)} title="Deactivate coupon">
                                  <Ban className="h-3.5 w-3.5" />
                                </Button>
                              )}
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                    <div className="px-4 pb-4 pt-2"><DataPagination {...pg.paginationProps} /></div>
                  </div>
                </>
              )}
            </CardContent>
          </Card>
        </main>
      </div>

      {/* Create coupon dialog */}
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className={cn(FORM_DIALOG_CONTENT, "sm:max-w-lg")}>
          <DialogHeader>
            <FormDialogTitle icon={Tag} color="orange">New coupon</FormDialogTitle>
            <DialogDescription>Create a promo code customers can use when subscribing.</DialogDescription>
          </DialogHeader>

          <div className="min-w-0 space-y-4">
            <FormSection title="Code" color="orange">
              <FormField label="Coupon code *">
                <div className="flex gap-2">
                  <Input className="bg-white flex-1 font-mono uppercase" placeholder="e.g. WELCOME20"
                    value={form.code} onChange={(e) => setForm((f) => ({ ...f, code: e.target.value.toUpperCase() }))} />
                  <Button type="button" variant="outline" onClick={generateCode} title="Generate random code">
                    Auto
                  </Button>
                </div>
              </FormField>
              <FormField label="Description">
                <Input className="bg-white" placeholder="e.g. Welcome offer — 20% off first month"
                  value={form.description} onChange={(e) => setForm((f) => ({ ...f, description: e.target.value }))} />
              </FormField>
            </FormSection>

            <FormSection title="Discount" color="emerald">
              <FormField label="Type">
                <Select value={form.discountType} onValueChange={(v) => setForm((f) => ({ ...f, discountType: v as "Flat" | "Percentage" }))}>
                  <SelectTrigger className="bg-white"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="Flat">Flat amount</SelectItem>
                    <SelectItem value="Percentage">Percentage</SelectItem>
                  </SelectContent>
                </Select>
              </FormField>
              <FormField label={form.discountType === "Percentage" ? "Percentage *" : "Amount *"}>
                <NumberInput step="0.01" value={form.discountValue}
                  onChange={(e) => setForm((f) => ({ ...f, discountValue: e.target.value }))} />
              </FormField>
            </FormSection>

            <FormSection title="Limits" color="slate">
              <FormField label="Max total uses" hint="Leave empty for unlimited">
                <NumberInput value={form.maxUses} min={0}
                  onChange={(e) => setForm((f) => ({ ...f, maxUses: e.target.value }))} />
              </FormField>
              <FormField label="Max per customer" hint="Leave empty for unlimited">
                <NumberInput value={form.maxUsesPerCustomer} min={0}
                  onChange={(e) => setForm((f) => ({ ...f, maxUsesPerCustomer: e.target.value }))} />
              </FormField>
            </FormSection>

            <FormSection title="Validity" color="blue">
              <FormField label="Valid from">
                <Input type="date" className="bg-white" value={form.validFrom}
                  onChange={(e) => setForm((f) => ({ ...f, validFrom: e.target.value }))} />
              </FormField>
              <FormField label="Valid until">
                <Input type="date" className="bg-white" value={form.validUntil}
                  onChange={(e) => setForm((f) => ({ ...f, validUntil: e.target.value }))} />
              </FormField>
              <FormField label="Applicable plan" hint="Leave empty to apply to all plans" full>
                <Select value={form.applicableServiceId} onValueChange={(v) => setForm((f) => ({ ...f, applicableServiceId: v }))}>
                  <SelectTrigger className="bg-white"><SelectValue placeholder="All plans" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="">All plans</SelectItem>
                    {plans.map((p) => <SelectItem key={p.genericServiceId} value={String(p.genericServiceId)}>{p.serviceName}</SelectItem>)}
                  </SelectContent>
                </Select>
              </FormField>
            </FormSection>
          </div>

          <FormDialogFooter onCancel={() => setOpen(false)}>
            <Button onClick={onSave} disabled={saving} className={cn("px-6", FORM_DIALOG_PRIMARY.orange)}>
              {saving ? <><Loader2 className="mr-2 h-4 w-4 animate-spin" /> Creating…</> : "Create coupon"}
            </Button>
          </FormDialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
