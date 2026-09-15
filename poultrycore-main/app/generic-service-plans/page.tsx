"use client"

// Service Plans — the recurring things a Generic company sells.
//
// A plan IS a service. The two plan columns (plan type and billing frequency)
// were added to genericservices rather than to a new table, so a plan sells
// through the existing sale-item path with no special casing, and a company
// that already had a service catalogue simply sees its services here with no
// frequency set.
//
// What this page is NOT: a place to rename or delete a service. That stays on
// the service catalogue, which owns the row.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Textarea } from "@/components/ui/textarea"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogTrigger,
} from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { FormSection, FormField } from "@/components/ui/form-section"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Loader2, Plus, Repeat, Pencil } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import {
  getServicePlans, setServicePlan, createServicePlan, getServiceCategories,
  getModuleSettings, getBusinessTemplate,
  type GenericServicePlan, type GenericServiceCategory,
} from "@/lib/api/generic-subscriptions"
import { templateLabels } from "@/lib/generic/template-labels"
import { BILLING_FREQUENCIES, FREQUENCY_LABELS, type BillingFrequency } from "@/lib/generic/billing-schedule"

const PLAN_TYPES = [
  { value: "Recurring", label: "Recurring — bills every period" },
  { value: "OneOff", label: "One-off — a service you sell once" },
]

export default function GenericServicePlansPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const fmt = useFmt()

  const [rows, setRows] = useState<GenericServicePlan[]>([])
  const [categories, setCategories] = useState<GenericServiceCategory[]>([])
  const [industry, setIndustry] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [search, setSearch] = useState("")
  const [open, setOpen] = useState(false)
  // Null id = creating. A number = editing that plan's two plan columns only.
  const [editingId, setEditingId] = useState<number | null>(null)

  const labels = templateLabels(industry)

  const EMPTY = {
    serviceName: "",
    defaultPrice: "0",
    genericServiceCategoryId: "",
    planType: "Recurring",
    billingFrequency: "Monthly" as BillingFrequency | string,
    notes: "",
  }
  const [form, setForm] = useState(EMPTY)

  const load = async () => {
    setLoading(true)
    try {
      const [plans, cats, template] = await Promise.all([
        getServicePlans(),
        getServiceCategories().catch(() => [] as GenericServiceCategory[]),
        getBusinessTemplate().catch(() => null),
      ])
      setRows(plans)
      setCategories(cats)
      setIndustry(template?.genericIndustryTemplate ?? null)
    } catch (e: any) {
      toast({
        title: "Could not load plans",
        description: e?.message ?? String(e),
        variant: "destructive",
      })
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") {
      router.replace("/dashboard")
      return
    }
    // A company that has turned subscriptions off has no business here.
    getModuleSettings()
      .then((s) => {
        if (!s.enableSubscriptions) router.replace("/generic-dashboard")
      })
      .catch(() => {
        /* settings unavailable — show the page rather than a blank screen */
      })
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router])

  const visible = useMemo(
    () =>
      filterByDateAndSearch(rows, {
        search,
        searchKeys: ["serviceName", "categoryName", "billingFrequency"],
      }),
    [rows, search],
  )
  const pg = usePagination(visible)

  const openNew = () => {
    setEditingId(null)
    setForm(EMPTY)
    setOpen(true)
  }

  const openEdit = (p: GenericServicePlan) => {
    setEditingId(p.genericServiceId)
    setForm({
      serviceName: p.serviceName,
      defaultPrice: String(p.defaultPrice),
      genericServiceCategoryId: p.genericServiceCategoryId
        ? String(p.genericServiceCategoryId)
        : "",
      planType: p.planType ?? "Recurring",
      billingFrequency: p.billingFrequency ?? "Monthly",
      notes: p.notes ?? "",
    })
    setOpen(true)
  }

  const onSave = async () => {
    if (editingId == null && !form.serviceName.trim()) {
      toast({ title: "A name is required", variant: "destructive" })
      return
    }
    setSaving(true)
    try {
      if (editingId != null) {
        // Editing sets ONLY the plan columns. Renaming or repricing the service
        // belongs to the service catalogue, which owns the row.
        await setServicePlan(editingId, {
          planType: form.planType || null,
          billingFrequency: form.billingFrequency || null,
        })
        toast({ title: `${labels.plan} updated.` })
      } else {
        await createServicePlan({
          serviceName: form.serviceName.trim(),
          defaultPrice: Number(form.defaultPrice) || 0,
          genericServiceCategoryId: form.genericServiceCategoryId
            ? Number(form.genericServiceCategoryId)
            : null,
          planType: form.planType || null,
          billingFrequency: form.billingFrequency || null,
          notes: form.notes || null,
        })
        toast({ title: `${labels.plan} "${form.serviceName.trim()}" created.` })
      }
      setOpen(false)
      setEditingId(null)
      setForm(EMPTY)
      await load()
    } catch (e: any) {
      toast({
        title: "Could not save",
        description: e?.message ?? String(e),
        variant: "destructive",
      })
    } finally {
      setSaving(false)
    }
  }

  const frequencyBadge = (p: GenericServicePlan) =>
    p.billingFrequency ? (
      <Badge className="bg-indigo-100 text-indigo-800 hover:bg-indigo-100">
        {FREQUENCY_LABELS[p.billingFrequency as BillingFrequency] ?? p.billingFrequency}
      </Badge>
    ) : (
      // A service with no frequency is a service, not a plan. Saying so is more
      // useful than an empty cell.
      <Badge variant="outline">Not a plan yet</Badge>
    )

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <Repeat className="h-6 w-6 text-indigo-600" /> {labels.planPlural}
              </h1>
              <p className="text-sm text-slate-500">
                {rows.length} {rows.length === 1 ? labels.plan.toLowerCase() : labels.planPlural.toLowerCase()}
              </p>
            </div>
            <Dialog
              open={open}
              onOpenChange={(o) => {
                setOpen(o)
                if (!o) setEditingId(null)
              }}
            >
              <DialogTrigger asChild>
                <Button onClick={openNew} className="w-full sm:w-auto h-11 sm:h-10">
                  <Plus className="h-4 w-4 mr-1" />
                  New {labels.plan.toLowerCase()}
                </Button>
              </DialogTrigger>
              <DialogContent className="w-[95vw] max-w-[900px] max-h-[90vh] overflow-y-auto">
                <DialogHeader>
                  <DialogTitle className="flex items-center gap-2">
                    {editingId != null ? (
                      <>
                        <Pencil className="w-5 h-5 text-blue-600" /> Edit {labels.plan.toLowerCase()}
                      </>
                    ) : (
                      <>
                        <Repeat className="w-5 h-5 text-blue-600" /> New {labels.plan.toLowerCase()}
                      </>
                    )}
                  </DialogTitle>
                  <DialogDescription>
                    {editingId != null
                      ? "Only the plan type and billing frequency change here — the name and price live on the service itself."
                      : `The price here is the default. A ${labels.subscription.toLowerCase()} can still be given its own amount.`}
                  </DialogDescription>
                </DialogHeader>

                <div className="space-y-4">
                  <FormSection title="The plan" color="indigo">
                    <FormField label={`${labels.plan} name *`} full>
                      <Input
                        value={form.serviceName}
                        disabled={editingId != null}
                        onChange={(e) => setForm((f) => ({ ...f, serviceName: e.target.value }))}
                        maxLength={200}
                        placeholder="e.g. Monthly Subscription"
                      />
                    </FormField>
                    <FormField label="Default price">
                      <NumberInput
                        step="0.01"
                        value={form.defaultPrice}
                        disabled={editingId != null}
                        onChange={(e) => setForm((f) => ({ ...f, defaultPrice: e.target.value }))}
                      />
                    </FormField>
                    <FormField label="Income category">
                      <Select
                        value={form.genericServiceCategoryId}
                        disabled={editingId != null}
                        onValueChange={(v) => setForm((f) => ({ ...f, genericServiceCategoryId: v }))}
                      >
                        <SelectTrigger>
                          <SelectValue placeholder="Pick one" />
                        </SelectTrigger>
                        <SelectContent>
                          {categories.map((c) => (
                            <SelectItem key={c.genericServiceCategoryId} value={String(c.genericServiceCategoryId)}>
                              {c.name}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </FormField>
                  </FormSection>

                  <FormSection title="How it bills" color="emerald">
                    <FormField label="Plan type">
                      <Select
                        value={form.planType}
                        onValueChange={(v) => setForm((f) => ({ ...f, planType: v }))}
                      >
                        <SelectTrigger>
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          {PLAN_TYPES.map((t) => (
                            <SelectItem key={t.value} value={t.value}>
                              {t.label}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </FormField>
                    <FormField label="Billing frequency">
                      <Select
                        value={String(form.billingFrequency)}
                        onValueChange={(v) => setForm((f) => ({ ...f, billingFrequency: v }))}
                      >
                        <SelectTrigger>
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          {BILLING_FREQUENCIES.map((f) => (
                            <SelectItem key={f} value={f}>
                              {FREQUENCY_LABELS[f]}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </FormField>
                  </FormSection>

                  {editingId == null && (
                    <FormSection title="Notes" color="slate" columns={1}>
                      <FormField label="Notes">
                        <Textarea
                          rows={2}
                          value={form.notes}
                          onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))}
                        />
                      </FormField>
                    </FormSection>
                  )}

                  <div className="flex gap-3 justify-end pt-2">
                    <Button
                      type="button"
                      onClick={() => setOpen(false)}
                      className="bg-red-600 hover:bg-red-700 text-white"
                    >
                      Cancel
                    </Button>
                    <Button onClick={onSave} disabled={saving}>
                      {saving ? (
                        <>
                          <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                          Saving…
                        </>
                      ) : editingId != null ? (
                        "Save changes"
                      ) : (
                        "Create"
                      )}
                    </Button>
                  </div>
                </div>
              </DialogContent>
            </Dialog>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500">
              <Loader2 className="h-4 w-4 animate-spin" /> Loading…
            </div>
          ) : rows.length === 0 ? (
            <Card>
              <CardContent className="py-8 text-center text-slate-500">
                No {labels.planPlural.toLowerCase()} yet. Create one to start billing.
              </CardContent>
            </Card>
          ) : (
            <>
              <ListFilters
                search={search}
                setSearch={setSearch}
                searchOnly
                searchPlaceholder={`Search ${labels.planPlural.toLowerCase()}`}
              />
              <Card>
                <CardContent className="p-0">
                  <MobileCardList
                    items={pg.pageItems}
                    getKey={(p) => p.genericServiceId}
                    primary={(p) => p.serviceName}
                    secondary={(p) => (
                      <>
                        {p.categoryName && <span>{p.categoryName} · </span>}
                        <span>{fmt(p.defaultPrice)}</span>
                      </>
                    )}
                    trailing={(p) => frequencyBadge(p)}
                    details={(p) => [
                      { label: "Price", value: fmt(p.defaultPrice) },
                      { label: "Type", value: p.planType ?? "—" },
                      { label: `Active ${labels.subscriptionPlural.toLowerCase()}`, value: p.activeSubscriptions },
                      { label: "Billed per period", value: fmt(p.monthlyValue) },
                    ]}
                    actions={(p) => (
                      <Button
                        size="sm"
                        variant="outline"
                        className="flex-1 h-10"
                        onClick={() => openEdit(p)}
                      >
                        <Pencil className="h-4 w-4 mr-1" /> Edit plan
                      </Button>
                    )}
                    pagination={pg.paginationProps}
                    desktopTable={
                      <div className="overflow-x-auto">
                        <Table>
                          <TableHeader>
                            <TableRow>
                              <TableHead>{labels.plan}</TableHead>
                              <TableHead>Category</TableHead>
                              <TableHead className="text-right">Price</TableHead>
                              <TableHead>Billing</TableHead>
                              <TableHead className="text-right">
                                Active {labels.subscriptionPlural.toLowerCase()}
                              </TableHead>
                              <TableHead className="text-right">Per period</TableHead>
                              <TableHead />
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {pg.pageItems.map((p) => (
                              <TableRow key={p.genericServiceId} className={p.isActive ? "" : "opacity-60"}>
                                <TableCell className="font-medium">{p.serviceName}</TableCell>
                                <TableCell>{p.categoryName ?? "—"}</TableCell>
                                <TableCell className="text-right">{fmt(p.defaultPrice)}</TableCell>
                                <TableCell>{frequencyBadge(p)}</TableCell>
                                <TableCell className="text-right">{p.activeSubscriptions}</TableCell>
                                <TableCell className="text-right">{fmt(p.monthlyValue)}</TableCell>
                                <TableCell className="text-right">
                                  <Button size="sm" variant="outline" onClick={() => openEdit(p)}>
                                    <Pencil className="h-4 w-4 mr-1" /> Edit
                                  </Button>
                                </TableCell>
                              </TableRow>
                            ))}
                          </TableBody>
                        </Table>
                        <DataPagination {...pg.paginationProps} />
                      </div>
                    }
                  />
                </CardContent>
              </Card>
            </>
          )}
        </main>
      </div>
    </div>
  )
}
