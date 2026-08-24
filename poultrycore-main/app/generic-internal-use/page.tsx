"use client"

// Generic Internal Use (migration 217).
//
// Stock the company intentionally consumes rather than sells. Deliberately not
// a sale and not a loss: posting reduces stock, writes an append-only ledger row
// and books a NON-CASH expense — no sale, no customer balance, no cash movement.
//
// Lifecycle mirrors the water and poultry pages: Draft → Posted → Reversed.
// Generic has NO unit conversion — one freetext unitOfMeasure, so what you type
// is what leaves stock — which is why there is no sachet/crate picker here.
//
// Phase 1 records ONE product per entry. The API and schema are header+items, so
// adding more lines later is additive and needs no migration.

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from "@/components/ui/alert-dialog"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Badge } from "@/components/ui/badge"
import { Plus, Loader2, PackageMinus, Pencil, Trash2, Undo2, CheckCircle2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { cn } from "@/lib/utils"
import { fmtMoney } from "@/lib/currency"
import { getProducts as listGenericProducts, type GenericProduct } from "@/lib/api/generic"
import {
  listGenericInternalUsage, createGenericInternalUsage, updateGenericInternalUsage,
  deleteGenericInternalUsage, postGenericInternalUsage, reverseGenericInternalUsage,
  getGenericInternalUseSuggestedCost,
  INTERNAL_USE_CATEGORY_LABELS, GENERIC_INTERNAL_USE_CATEGORIES, STAFF_BASED_CATEGORIES,
  type GenericInternalUsage, type InternalUseCategory, type InternalUseStatus,
} from "@/lib/api/internal-use"

const gh = (n: number) => fmtMoney(n)

const STATUS_BADGE: Record<string, string> = {
  Draft: "bg-slate-100 text-slate-700",
  Posted: "bg-green-100 text-green-700",
  Reversed: "bg-amber-100 text-amber-700",
}

const CATEGORIES = GENERIC_INTERNAL_USE_CATEGORIES

type ConfirmState = {
  type: "post" | "delete"
  id: number
  title: string
  description: string
  actionLabel: string
  destructive?: boolean
}

const emptyForm = () => ({
  genericInternalUsageId: 0,
  usageDate: new Date().toISOString().split("T")[0],
  category: "StaffWelfare" as InternalUseCategory,
  recipientName: "",
  reason: "",
  notes: "",
  // quantity
  genericProductId: 0,
  entryUnit: "Unit",
  entryQuantity: 0,
  unitCost: 0,
  // staff helper
  useStaffHelper: true,
  staffCount: 0,
  quantityPerStaff: 0,
})

export default function GenericInternalUsePage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [items, setItems] = useState<GenericInternalUsage[]>([])
  const [products, setProducts] = useState<GenericProduct[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [statusFilter, setStatusFilter] = useState<string>("ALL")
  const [categoryFilter, setCategoryFilter] = useState<string>("ALL")

  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState(emptyForm())
  const set = <K extends keyof ReturnType<typeof emptyForm>>(k: K, v: ReturnType<typeof emptyForm>[K]) =>
    setForm((p) => ({ ...p, [k]: v }))

  /** The product's cost price, as seeded by the server. */
  const [suggestedPerBase, setSuggestedPerBase] = useState(0)
  const [confirm, setConfirm] = useState<ConfirmState | null>(null)
  const [busy, setBusy] = useState(false)
  const [reverseTarget, setReverseTarget] = useState<GenericInternalUsage | null>(null)

  // Wrong company type: this page only means anything for a Generic company.
  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") {
      router.replace("/dashboard")
    }
  }, [activeFarmType, router])

  // allSettled, not all: these are independent reads, and a failure in one must
  // not blank the other. Promise.all here meant that while the Internal Use
  // tables were missing the product list never arrived either, so the form
  // looked broken ("can't pick a product") rather than reporting the real cause.
  async function load() {
    setLoading(true)
    const [rowsRes, prodsRes] = await Promise.allSettled([
      listGenericInternalUsage(),
      listGenericProducts(),
    ])

    if (rowsRes.status === "fulfilled") setItems(rowsRes.value)
    else toast({
      title: "Couldn't load internal use records",
      description: rowsRes.reason?.message,
      variant: "destructive",
    })

    if (prodsRes.status === "fulfilled") setProducts(prodsRes.value)
    else toast({
      title: "Couldn't load products",
      description: prodsRes.reason?.message,
      variant: "destructive",
    })

    setLoading(false)
  }
  useEffect(() => { void load() }, [])

  // ---------------------------------------------------------------- quantity
  const selectedProduct = useMemo(
    () => products.find((p) => p.genericProductId === form.genericProductId),
    [products, form.genericProductId],
  )

  // Generic has no unit conversion: genericProducts carries one freetext
  // unitOfMeasure with no factor and no second unit, so what you type is what
  // leaves stock. The entry unit simply follows the product.
  useEffect(() => {
    const u = selectedProduct?.unitOfMeasure || ""
    if (selectedProduct && u && form.entryUnit !== u) {
      setForm((p) => ({ ...p, entryUnit: u }))
    }
  }, [selectedProduct, form.entryUnit])

  /** Plural noun for whatever the product is measured in: "Packs", "Bottles". */
  const entryLabel = useMemo(
    () => plural(form.entryUnit || "Unit"),
    [form.entryUnit],
  )

  /** Always 1 — generic has no conversion. Kept so the shared markup reads the same. */
  const factor = 1

  /** The staff helper is a calculator: it writes into entryQuantity, which stays editable. */
  const effectiveQuantity = useMemo(() => {
    if (form.useStaffHelper && isStaffCategory(form.category)) {
      return round3((form.staffCount || 0) * (form.quantityPerStaff || 0))
    }
    return form.entryQuantity || 0
  }, [form.useStaffHelper, form.category, form.staffCount, form.quantityPerStaff, form.entryQuantity])

  const baseQuantity = useMemo(() => round3(effectiveQuantity * factor), [effectiveQuantity, factor])
  // Multiplication in the entry unit, matching the SP — no divide-by-30 drift.
  const totalCost = useMemo(
    () => round2(effectiveQuantity * (form.unitCost || 0)),
    [effectiveQuantity, form.unitCost],
  )
  const baseUnitLabel = selectedProduct?.unitOfMeasure || "unit"

  // Generic keeps a denormalised currentStock alongside the movement ledger; the
  // posting SP maintains both, so either is a valid read here.
  const onHandBase = selectedProduct?.currentStock ?? 0
  const notEnough = form.genericProductId > 0 && baseQuantity > onHandBase

  // Seed the cost from the weighted average whenever the product changes. The
  // endpoint answers per egg, so scale it into whichever unit is being
  // entered. The user can override it, and 0 is a legitimate answer for a
  // product with no costed inflow — so this never blocks.
  useEffect(() => {
    if (!form.genericProductId) return
    let cancelled = false
    getGenericInternalUseSuggestedCost(form.genericProductId)
      .then((r) => {
        if (cancelled) return
        setSuggestedPerBase(r.unitCost || 0)
        setForm((p) => ({
          ...p,
          unitCost: round4(r.unitCost || 0),
        }))
      })
      .catch(() => { /* suggestion only — leave whatever is in the field */ })
    return () => { cancelled = true }
  }, [form.genericProductId])

  // ----------------------------------------------------------------- filters
  const visible = useMemo(() => {
    let rows = filterByDateAndSearch(items, {
      search, dateFrom, dateTo,
      dateKey: "usageDate",
      searchKeys: ["referenceNo", "category", "reason", "recipientName", "notes"],
    } as any)
    if (statusFilter !== "ALL") rows = rows.filter((r) => r.status === statusFilter)
    if (categoryFilter !== "ALL") rows = rows.filter((r) => r.category === categoryFilter)
    return rows
  }, [items, search, dateFrom, dateTo, statusFilter, categoryFilter])

  const pg = usePagination(visible)

  const stats = useMemo(() => {
    const posted = visible.filter((r) => r.status === "Posted")
    return {
      records: visible.length,
      drafts: visible.filter((r) => r.status === "Draft").length,
      postedCost: posted.reduce((s, r) => s + (r.totalCostValue || 0), 0),
      reversed: visible.filter((r) => r.status === "Reversed").length,
    }
  }, [visible])

  // ------------------------------------------------------------------ writes
  function openCreate() {
    // The product cannot be optional — the whole record is "this much of THIS
    // came out of stock, at this cost". But most farms carry one or two
    // things, so preselect when the choice is obvious and save a click.
    const only = products.length === 1
      ? products[0]
      : undefined

    setForm({
      ...emptyForm(),
      genericProductId: only?.genericProductId ?? 0,
      entryUnit: only?.unitOfMeasure || "Unit",
    })
    setOpen(true)
  }

  function openEdit(r: GenericInternalUsage) {
    const line = r.items?.[0]
    setForm({
      ...emptyForm(),
      genericInternalUsageId: r.genericInternalUsageId,
      usageDate: (r.usageDate || "").split("T")[0],
      category: r.category,
      recipientName: r.recipientName ?? "",
      reason: r.reason ?? "",
      notes: r.notes ?? "",
      genericProductId: line?.genericProductId ?? 0,
      entryUnit: line?.entryUnit || "Unit",
      entryQuantity: line?.entryQuantity ?? 0,
      // The entry-unit figure is what was typed; unitCost is the derived
      // per-egg one and would read 30× too small in this field.
      unitCost: line?.entryUnitCost ?? 0,
      // An existing record already carries its quantity; don't let the helper
      // silently recompute it on open.
      useStaffHelper: false,
      staffCount: r.staffCount ?? 0,
      quantityPerStaff: line?.quantityPerStaff ?? 0,
    })
    setOpen(true)
  }

  function validate(): string | null {
    if (!form.usageDate) return "Pick the date."
    if (form.usageDate > new Date().toISOString().split("T")[0]) return "The date cannot be in the future."
    if (!form.category) return "Pick what the stock was used for."
    if (!form.genericProductId) return "Pick the product."
    if (effectiveQuantity <= 0) return "Enter a quantity greater than zero."
    if (form.useStaffHelper && isStaffCategory(form.category)) {
      if ((form.staffCount || 0) <= 0) return "Enter how many staff received it."
      if ((form.quantityPerStaff || 0) <= 0) return "Enter how much each staff member received."
    }
    if (notEnough) return `Not enough stock: ${onHandBase} ${baseUnitLabel} available, ${baseQuantity} needed.`
    return null
  }

  async function save() {
    const bad = validate()
    if (bad) { toast({ title: bad, variant: "destructive" }); return }

    setSaving(true)
    try {
      const payload = {
        usageDate: form.usageDate,
        category: form.category,
        reason: form.reason || null,
        recipientName: form.recipientName || null,
        staffCount: form.useStaffHelper && isStaffCategory(form.category) ? form.staffCount : null,
        notes: form.notes || null,
        items: [{
          genericProductId: form.genericProductId,
          entryQuantity: effectiveQuantity,
          entryUnit: form.entryUnit,
          quantityPerStaff: form.useStaffHelper && isStaffCategory(form.category) ? form.quantityPerStaff : null,
          // In the unit shown on the label. The SP derives the per-egg figure
          // and the line total from this.
          entryUnitCost: form.unitCost || 0,
        }],
      }
      if (form.genericInternalUsageId) {
        await updateGenericInternalUsage(form.genericInternalUsageId, payload)
        toast({ title: "Draft updated" })
      } else {
        await createGenericInternalUsage(payload)
        toast({ title: "Draft saved", description: "Post it when you're ready to move the stock." })
      }
      setOpen(false)
      await load()
    } catch (e: any) {
      toast({ title: "Couldn't save", description: e?.message, variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  async function runConfirm() {
    if (!confirm) return
    setBusy(true)
    try {
      if (confirm.type === "post") {
        await postGenericInternalUsage(confirm.id)
        toast({ title: "Posted", description: "Stock reduced and the cost booked as a non-cash expense." })
      } else {
        await deleteGenericInternalUsage(confirm.id)
        toast({ title: "Draft deleted" })
      }
      setConfirm(null)
      await load()
    } catch (e: any) {
      toast({ title: "That didn't work", description: e?.message, variant: "destructive" })
    } finally {
      setBusy(false)
    }
  }

  // -------------------------------------------------------------------- view
  const showStaffHelper = isStaffCategory(form.category)

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="flex items-start justify-between gap-4 mb-6">
            <div>
              <h1 className="text-2xl font-bold text-slate-900 flex items-center gap-2">
                <PackageMinus className="w-6 h-6 text-sky-600" /> Internal Use
              </h1>
              <p className="text-sm text-slate-500 mt-1">
                Eggs, birds, feed or supplies used by the farm — given to staff, taken by the owner,
                donated, sampled or tested. Recorded at cost, never as a sale.
              </p>
            </div>
            <Button onClick={openCreate} className="shrink-0">
              <Plus className="w-4 h-4 mr-2" /> Record internal use
            </Button>
          </div>

          {/* Tell them up front, not after they open the form and find an empty list. */}
          {!loading && products.length === 0 && (
            <div className="mb-5 rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm">
              <span className="font-medium text-amber-900">No products in this company yet. </span>
              <span className="text-amber-800">
                Internal Use takes stock off a product, so add one before recording anything.{" "}
              </span>
              <Link href="/generic-products" className="font-medium text-amber-900 underline underline-offset-2">
                Go to Products
              </Link>
            </div>
          )}

          <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-5">
            <StatCard label="Records" value={String(stats.records)} />
            <StatCard label="Drafts" value={String(stats.drafts)} />
            <StatCard label="Posted cost" value={gh(stats.postedCost)} />
            <StatCard label="Reversed" value={String(stats.reversed)} />
          </div>

          <ListFilters
            search={search} setSearch={setSearch}
            dateFrom={dateFrom} setDateFrom={setDateFrom}
            dateTo={dateTo} setDateTo={setDateTo}
            searchPlaceholder="Search reason, recipient or notes"
            extras={(
              <>
                <Select value={statusFilter} onValueChange={setStatusFilter}>
                  <SelectTrigger className="w-36"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="ALL">All statuses</SelectItem>
                    <SelectItem value="Draft">Draft</SelectItem>
                    <SelectItem value="Posted">Posted</SelectItem>
                    <SelectItem value="Reversed">Reversed</SelectItem>
                  </SelectContent>
                </Select>
                <Select value={categoryFilter} onValueChange={setCategoryFilter}>
                  <SelectTrigger className="w-52"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="ALL">All reasons</SelectItem>
                    {CATEGORIES.map((c) => (
                      <SelectItem key={c} value={c}>{INTERNAL_USE_CATEGORY_LABELS[c]}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </>
            )}
          />

          <Card className="mt-4">
            <CardContent className="p-0 md:p-2">
              {loading ? (
                <div className="flex items-center gap-2 p-8 text-slate-500">
                  <Loader2 className="w-4 h-4 animate-spin" /> Loading…
                </div>
              ) : visible.length === 0 ? (
                <div className="p-8 text-center text-slate-500">
                  No internal use recorded yet.
                </div>
              ) : (
                <MobileCardList
                  items={pg.pageItems}
                  pagination={pg.paginationProps}
                  getKey={(r) => r.genericInternalUsageId}
                  primary={(r) => `${INTERNAL_USE_CATEGORY_LABELS[r.category] ?? r.category} · ${gh(r.totalCostValue ?? 0)}`}
                  secondary={(r) => (
                    <>
                      <span>{(r.usageDate || "").split("T")[0]}</span>
                      <Badge variant="outline" className={cn("border-0", STATUS_BADGE[r.status])}>{r.status}</Badge>
                    </>
                  )}
                  details={(r) => [
                    { label: "Date", value: (r.usageDate || "").split("T")[0] },
                    { label: "Reason", value: INTERNAL_USE_CATEGORY_LABELS[r.category] ?? r.category },
                    { label: "Product", value: r.items?.[0]?.productName ?? "—" },
                    { label: "Quantity", value: describeQty(r) },
                    { label: "Cost", value: gh(r.totalCostValue ?? 0) },
                    { label: "Recipient", value: r.recipientName ?? "—" },
                  ]}
                  actions={(r) => rowActions(r)}
                  desktopTable={(
                    <div className="overflow-x-auto">
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Date</TableHead>
                            <TableHead>Reason</TableHead>
                            <TableHead>Product</TableHead>
                            <TableHead>Quantity</TableHead>
                            <TableHead className="text-right">Cost</TableHead>
                            <TableHead>Status</TableHead>
                            <TableHead className="text-right">Actions</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {pg.pageItems.map((r) => (
                            <TableRow key={r.genericInternalUsageId}>
                              <TableCell className="font-medium">{(r.usageDate || "").split("T")[0]}</TableCell>
                              <TableCell>{INTERNAL_USE_CATEGORY_LABELS[r.category] ?? r.category}</TableCell>
                              <TableCell>{r.items?.[0]?.productName ?? "—"}</TableCell>
                              <TableCell>{describeQty(r)}</TableCell>
                              <TableCell className="text-right">{gh(r.totalCostValue ?? 0)}</TableCell>
                              <TableCell>
                                <Badge variant="outline" className={cn("border-0", STATUS_BADGE[r.status])}>{r.status}</Badge>
                              </TableCell>
                              <TableCell className="text-right">
                                <div className="flex justify-end gap-1">{rowActions(r)}</div>
                              </TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    </div>
                  )}
                />
              )}
            </CardContent>
          </Card>
        </main>
      </div>

      {/* ------------------------------------------------------------- form */}
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="w-[95vw] max-w-[900px] max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{form.genericInternalUsageId ? "Edit draft" : "Record internal use"}</DialogTitle>
            <DialogDescription>
              This reduces stock and records the cost. It does not create a sale, a customer balance or a
              cash transaction.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4">
            <FormSection title="What was used, and why" color="sky" columns={2}>
              <FormField label="Date">
                <Input type="date" value={form.usageDate} max={today()}
                       onChange={(e) => set("usageDate", e.target.value)} />
              </FormField>
              <FormField label="Reason">
                <Select value={form.category} onValueChange={(v) => set("category", v as InternalUseCategory)}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {CATEGORIES.map((c) => (
                      <SelectItem key={c} value={c}>{INTERNAL_USE_CATEGORY_LABELS[c]}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </FormField>
              <FormField label="Who received it" hint="Optional">
                <Input value={form.recipientName} onChange={(e) => set("recipientName", e.target.value)}
                       placeholder="e.g. Production team" />
              </FormField>
              <FormField label="Detail" hint="Optional">
                <Input value={form.reason} onChange={(e) => set("reason", e.target.value)}
                       placeholder="e.g. Friday staff allowance" />
              </FormField>
            </FormSection>

            <FormSection title="How much" color="blue" columns={2}>
              {/* A company with no products has nothing to give out. Say so and
                  point at the fix — an empty dropdown just looks broken. */}
              {products.length === 0 ? (
                <FormField label="Product" full>
                  <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm">
                    <p className="font-medium text-amber-900">This company has no products yet.</p>
                    <p className="mt-1 text-amber-800">
                      Internal Use takes stock off a product, so add one first — then come back and record
                      what was given out.
                    </p>
                    <Link href="/generic-products"
                          className="mt-2 inline-block font-medium text-amber-900 underline underline-offset-2">
                      Go to Products
                    </Link>
                  </div>
                </FormField>
              ) : (
                <FormField label="Product" full
                           hint={selectedProduct
                             ? `${onHandBase.toLocaleString()} ${baseUnitLabel.toLowerCase()} in stock`
                             : undefined}>
                  <Select value={String(form.genericProductId || "")}
                          onValueChange={(v) => set("genericProductId", Number(v))}>
                    <SelectTrigger><SelectValue placeholder="Pick a product" /></SelectTrigger>
                    <SelectContent>
                      {products.map((p) => (
                        <SelectItem key={p.genericProductId} value={String(p.genericProductId)}>{p.productName}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </FormField>
              )}

              {showStaffHelper && (
                <FormField label="How do you want to enter it?" full>
                  <div className="grid grid-cols-2 gap-2">
                    <UnitChoice
                      active={!form.useStaffHelper}
                      title="Total quantity"
                      sub="Type one number"
                      onClick={() => set("useStaffHelper", false)}
                    />
                    <UnitChoice
                      active={form.useStaffHelper}
                      title="Per staff member"
                      sub="Staff × amount each"
                      onClick={() => set("useStaffHelper", true)}
                    />
                  </div>
                </FormField>
              )}

              {showStaffHelper && form.useStaffHelper ? (
                <>
                  <FormField label="Number of staff">
                    <NumberInput min={0} value={form.staffCount}
                                 onChange={(e) => set("staffCount", Number(e.target.value) || 0)} />
                  </FormField>
                  <FormField label={`${entryLabel} each`}>
                    <NumberInput min={0} step={1} value={form.quantityPerStaff}
                                 onChange={(e) => set("quantityPerStaff", Number(e.target.value) || 0)} />
                  </FormField>
                </>
              ) : (
                <FormField label={`Total ${entryLabel.toLowerCase()}`}>
                  <NumberInput min={0} step={1} value={form.entryQuantity}
                               onChange={(e) => set("entryQuantity", Number(e.target.value) || 0)} />
                </FormField>
              )}

              {/* Cost per unit of measure. Generic has no conversion, so this is
                  simply the product's cost — seeded from genericProducts.costPrice. */}
              <FormField
                label={`Cost per ${singular(form.entryUnit).toLowerCase()}`}
                hint={suggestedPerBase > 0
                  ? "Suggested from the product's cost price — change it if you need to"
                  : "No cost price set — enter what it costs you"}>
                <NumberInput min={0} step={0.01} value={form.unitCost}
                             onChange={(e) => set("unitCost", Number(e.target.value) || 0)} />
              </FormField>
            </FormSection>

            <FormSection title="Check before you save" color="slate" columns={1}>
              <div className="col-span-full -mt-1">
                <dl className="divide-y divide-slate-100 text-sm">
                  <SummaryRow
                    label="Coming out of stock"
                    value={effectiveQuantity > 0
                      ? `${effectiveQuantity.toLocaleString()} ${entryLabel.toLowerCase()}`
                      : "—"}
                    note={factor > 1 && effectiveQuantity > 0
                      ? `${baseQuantity.toLocaleString()} eggs`
                      : undefined}
                  />
                  <SummaryRow label="Cost recorded" value={gh(totalCost)} />
                </dl>

                {/* Save is disabled when there isn't enough stock, so the reason
                    has to be visible — otherwise it's a dead button. */}
                {notEnough && (
                  <p className="mt-3 text-xs font-medium text-red-600">
                    Not enough stock: only {onHandBase.toLocaleString()} {baseUnitLabel.toLowerCase()} available,
                    {" "}{baseQuantity.toLocaleString()} needed.
                  </p>
                )}
                <p className="mt-3 text-[11px] leading-relaxed text-slate-500">
                  Posting reduces stock and records the cost as a non-cash expense. It does not create a
                  sale, a customer balance or any cash movement.
                </p>
              </div>

              <FormField label="Notes" hint="Optional">
                <Textarea rows={2} value={form.notes} onChange={(e) => set("notes", e.target.value)} />
              </FormField>
            </FormSection>
          </div>

          <div className="flex justify-end gap-2 pt-4">
            <Button variant="outline" onClick={() => setOpen(false)} disabled={saving}>Cancel</Button>
            <Button onClick={() => void save()} disabled={saving || notEnough}>
              {saving ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</> : "Save draft"}
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* ---------------------------------------------------------- confirms */}
      <AlertDialog open={!!confirm} onOpenChange={(o) => { if (!o) setConfirm(null) }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{confirm?.title}</AlertDialogTitle>
            <AlertDialogDescription>{confirm?.description}</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={busy}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={(e) => { e.preventDefault(); void runConfirm() }}
              disabled={busy}
              className={cn(confirm?.destructive && "bg-red-600 hover:bg-red-700 focus:ring-red-600")}
            >
              {busy ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Working…</> : confirm?.actionLabel}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <PromptDialog
        open={!!reverseTarget}
        onOpenChange={(o) => { if (!o) setReverseTarget(null) }}
        title="Reverse this internal use?"
        description="The stock comes back with an opposite ledger entry — the original is kept — and the linked expense is cancelled."
        label="Reason for reversal"
        confirmLabel="Reverse"
        confirmVariant="destructive"
        onSubmit={async (reason: string) => {
          if (!reverseTarget) return
          try {
            await reverseGenericInternalUsage(reverseTarget.genericInternalUsageId, reason)
            toast({ title: "Reversed", description: "Stock restored and the expense cancelled." })
            setReverseTarget(null)
            await load()
          } catch (e: any) {
            toast({ title: "Couldn't reverse", description: e?.message, variant: "destructive" })
          }
        }}
      />
    </div>
  )

  // Actions available depend on where the record is in its life.
  function rowActions(r: GenericInternalUsage) {
    if (r.status === "Draft") {
      return (
        <>
          <Button size="sm" variant="ghost" title="Edit" onClick={() => openEdit(r)}>
            <Pencil className="w-4 h-4" />
          </Button>
          <Button size="sm" variant="ghost" title="Post" onClick={() => setConfirm({
            type: "post", id: r.genericInternalUsageId,
            title: "Post this internal use?",
            description: `${describeQty(r)} comes out of stock and ${gh(r.totalCostValue || 0)} is booked as a non-cash expense. No sale and no cash movement is created.`,
            actionLabel: "Post",
          })}>
            <CheckCircle2 className="w-4 h-4 text-green-600" />
          </Button>
          <Button size="sm" variant="ghost" title="Delete" onClick={() => setConfirm({
            type: "delete", id: r.genericInternalUsageId,
            title: "Delete this draft?",
            description: "It has not touched stock, so it can be removed outright.",
            actionLabel: "Delete", destructive: true,
          })}>
            <Trash2 className="w-4 h-4 text-red-600" />
          </Button>
        </>
      )
    }
    if (r.status === "Posted") {
      return (
        <Button size="sm" variant="ghost" title="Reverse" onClick={() => setReverseTarget(r)}>
          <Undo2 className="w-4 h-4 text-amber-600" />
        </Button>
      )
    }
    return <span className="text-xs text-slate-400 px-2">Reversed</span>
  }
}

// ------------------------------------------------------------------ helpers

function isStaffCategory(c: InternalUseCategory) {
  return STAFF_BASED_CATEGORIES.includes(c)
}

/** "10 crates (300 eggs)" — the crate figure is what people said, the egg figure is what moved. */
function describeQty(r: GenericInternalUsage): string {
  const line = r.items?.[0]
  if (!line) return "—"
  const qty = line.entryQuantity ?? 0
  const entry = `${qty.toLocaleString()} ${unitWord(line.entryUnit || "Egg").toLowerCase()}`
  const f = line.unitsPerEntryUnit ?? 1
  return f > 1 ? `${entry} (${(line.stockQuantity ?? 0).toLocaleString()} eggs)` : entry
}

const round2 = (n: number) => Math.round(n * 100) / 100
const round3 = (n: number) => Math.round(n * 1000) / 1000
const round4 = (n: number) => Math.round(n * 10000) / 10000
const today = () => new Date().toISOString().split("T")[0]

/** "Crates" → "Crate". The cost label reads "Cost per crate", not "Cost per crates". */
function singular(unit: string) {
  const u = (unit || "Egg").trim()
  return u.toLowerCase().endsWith("s") ? u.slice(0, -1) : u
}

/** "Egg" → "Sachets", "Bottles" → "Bottles". Good enough for unit nouns. */
function plural(unit: string) {
  const u = (unit || "").trim()
  if (!u) return "Sachets"
  return u.toLowerCase().endsWith("s") ? u : `${u}s`
}

/** "Eggs" / "Crates" — the plural noun for a stored unit value. */
function unitWord(unit: string) {
  return unit.toLowerCase() === "crate" ? "Crates" : plural(unit)
}

function StatCard({ label, value }: { label: string; value: string }) {
  return (
    <Card>
      <CardContent className="p-4">
        <p className="text-xs text-slate-500">{label}</p>
        <p className="text-lg font-semibold text-slate-900 mt-0.5">{value}</p>
      </CardContent>
    </Card>
  )
}

/**
 * A big two-option picker. Used for egg-vs-crate and total-vs-per-staff: both
 * are binary choices that change every number on the form, so they deserve to be
 * visible at a glance rather than collapsed into a dropdown.
 */
function UnitChoice({
  active, title, sub, onClick,
}: { active: boolean; title: string; sub: string; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className={cn(
        "rounded-lg border-2 px-3 py-2 text-left transition-all",
        active
          ? "border-sky-500 bg-sky-50 ring-2 ring-sky-500/30"
          : "border-slate-200 bg-white hover:border-slate-300",
      )}
    >
      <div className="text-sm font-semibold text-slate-900">{title}</div>
      <div className="text-[11px] text-slate-500">{sub}</div>
    </button>
  )
}

function SummaryRow({
  label, value, note, danger,
}: { label: string; value: string; note?: string; danger?: boolean }) {
  return (
    <div className="flex items-baseline justify-between gap-4 py-2">
      <dt className="text-slate-500">{label}</dt>
      <dd className="text-right">
        <span className={cn("font-semibold", danger ? "text-red-600" : "text-slate-900")}>{value}</span>
        {note && <span className={cn("block text-[11px]", danger ? "text-red-500" : "text-slate-500")}>{note}</span>}
      </dd>
    </div>
  )
}
