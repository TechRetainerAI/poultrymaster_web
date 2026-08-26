"use client"

// Poultry Internal Use (migration 216).
//
// Stock the company intentionally consumes rather than sells. Deliberately not
// a sale and not a loss: posting reduces stock, writes an append-only ledger row
// and books a NON-CASH expense — no sale, no customer balance, no cash movement.
//
// Lifecycle mirrors the water page: Draft → Posted → Reversed, with a single
// ConfirmState-driven AlertDialog and a PromptDialog for reverse-with-reason.
// Kept a close clone of app/water-internal-use so the two stay in step.
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
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from "@/components/ui/alert-dialog"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Badge } from "@/components/ui/badge"
import { Plus, Loader2, PackageMinus, Pencil, Trash2, Undo2, CheckCircle2, Eye, Info } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { cn } from "@/lib/utils"
import { fmtMoney } from "@/lib/currency"
import { listPoultryProducts, type PoultryProduct } from "@/lib/api/poultry-inventory"
import {
  listPoultryInternalUsage, createPoultryInternalUsage, updatePoultryInternalUsage,
  deletePoultryInternalUsage, postPoultryInternalUsage, reversePoultryInternalUsage,
  getPoultryInternalUseSuggestedCost,
  POULTRY_INTERNAL_USE_CATEGORY_LABELS, POULTRY_INTERNAL_USE_CATEGORIES, STAFF_BASED_CATEGORIES,
  type PoultryInternalUsage, type InternalUseCategory, type InternalUseStatus,
} from "@/lib/api/internal-use"

const gh = (n: number) => fmtMoney(n)

const STATUS_BADGE: Record<string, string> = {
  Draft: "bg-slate-100 text-slate-700",
  Posted: "bg-green-100 text-green-700",
  Reversed: "bg-amber-100 text-amber-700",
}

const CATEGORIES = POULTRY_INTERNAL_USE_CATEGORIES

type ConfirmState = {
  type: "post" | "delete"
  id: number
  title: string
  description: string
  actionLabel: string
  destructive?: boolean
}

const emptyForm = () => ({
  poultryInternalUsageId: 0,
  usageDate: new Date().toISOString().split("T")[0],
  category: "StaffWelfare" as InternalUseCategory,
  recipientName: "",
  reason: "",
  notes: "",
  // quantity
  poultryProductId: 0,
  entryUnit: "Crate",
  entryQuantity: 0,
  unitCost: 0,
  // staff helper
  useStaffHelper: true,
  staffCount: 0,
  quantityPerStaff: 0,
})

export default function PoultryInternalUsePage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [items, setItems] = useState<PoultryInternalUsage[]>([])
  const [products, setProducts] = useState<PoultryProduct[]>([])
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

  /** Server's weighted average, per stock unit — so the hint can show both. */
  const [suggestedPerBase, setSuggestedPerBase] = useState(0)
  const [confirm, setConfirm] = useState<ConfirmState | null>(null)
  const [busy, setBusy] = useState(false)
  const [reverseTarget, setReverseTarget] = useState<PoultryInternalUsage | null>(null)
  /** Read-only detail, for every status. The row cannot show the free-text
      detail, the notes, or who did what and when; this is where those live. */
  const [viewTarget, setViewTarget] = useState<PoultryInternalUsage | null>(null)

  // Wrong company type: this page only means anything for a Poultry company.
  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") {
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
      listPoultryInternalUsage(),
      listPoultryProducts(),
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
    () => products.find((p) => p.poultryProductId === form.poultryProductId),
    [products, form.poultryProductId],
  )

  /**
   * Eggs per crate. Unlike water's sachetsPerBag there is no column for this —
   * migration 206 decided egg stock is a plain piece count — so 30 is the
   * convention fnpoultrycrateunits also defaults to, and it travels with the
   * line so a record always explains its own arithmetic.
   */
  const EGGS_PER_CRATE = 30
  const eggsPerCrate = EGGS_PER_CRATE

  // Crates only mean something for eggs. Birds, feed and supplies are counted in
  // their own unit, so the crate/egg choice is hidden and the entry stays 1:1 —
  // exactly what fnpoultrycrateunits enforces server-side.
  const isRawEggProduct = selectedProduct?.isRawEggProduct ?? false

  useEffect(() => {
    if (selectedProduct && !isRawEggProduct && form.entryUnit === "Crate") {
      // Fall back to the product's own unit (Bottle, Pack…), not a literal
      // "Egg" — the stored entryUnit is what the list and reports show.
      setForm((p) => ({ ...p, entryUnit: selectedProduct.unit || "Unit" }))
    }
  }, [selectedProduct, isRawEggProduct, form.entryUnit])

  /** Plural noun for whatever the user is entering: "Crates", "Eggs", "Birds". */
  const entryLabel = useMemo(
    () => (form.entryUnit === "Crate" ? "Crates" : plural(form.entryUnit || "Egg")),
    [form.entryUnit],
  )

  /** Only a crate entry converts; an egg (stock-unit) entry is 1:1. Mirrors the SP. */
  const factor = useMemo(
    () => (form.entryUnit.toLowerCase() === "crate" ? eggsPerCrate : 1),
    [form.entryUnit, eggsPerCrate],
  )

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
  const baseUnitLabel = selectedProduct?.unit || "unit"

  const onHandBase = selectedProduct?.stockOnHand ?? 0
  const notEnough = form.poultryProductId > 0 && baseQuantity > onHandBase

  // Seed the cost from Product setup for the unit being entered (migration 218).
  // The server answers "what does ONE of these cost", so there is no scaling to
  // do here — and re-asking when the unit changes keeps bulk pricing honest.
  // The field stays editable; 0 just means nothing is priced yet.
  useEffect(() => {
    if (!form.poultryProductId) return
    let cancelled = false
    getPoultryInternalUseSuggestedCost(form.poultryProductId, form.entryUnit)
      .then((r) => {
        if (cancelled) return
        setSuggestedPerBase(r.unitCost || 0)
        setForm((p) => ({ ...p, unitCost: round4(r.unitCost || 0) }))
      })
      .catch(() => { /* suggestion only — leave whatever is in the field */ })
    return () => { cancelled = true }
  }, [form.poultryProductId, form.entryUnit])

  /**
   * Changing the unit re-asks the server for that unit's price (see the effect
   * above), so there is nothing to rescale here — the suggestion arrives already
   * correct for bags or singles, bulk pricing included.
   */
  function changeEntryUnit(next: string) {
    setForm((p) => (p.entryUnit === next ? p : { ...p, entryUnit: next }))
  }

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
      : products.filter((p) => p.isRawEggProduct).length === 1
        ? products.find((p) => p.isRawEggProduct)
        : undefined

    setForm({
      ...emptyForm(),
      poultryProductId: only?.poultryProductId ?? 0,
      entryUnit: only && !only.isRawEggProduct ? (only.unit || "Unit") : "Crate",
    })
    setOpen(true)
  }

  function openEdit(r: PoultryInternalUsage) {
    const line = r.items?.[0]
    setForm({
      ...emptyForm(),
      poultryInternalUsageId: r.poultryInternalUsageId,
      usageDate: (r.usageDate || "").split("T")[0],
      category: r.category,
      recipientName: r.recipientName ?? "",
      reason: r.reason ?? "",
      notes: r.notes ?? "",
      poultryProductId: line?.poultryProductId ?? 0,
      entryUnit: line?.entryUnit || "Crate",
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
    if (!form.poultryProductId) return "Pick the product."
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
          poultryProductId: form.poultryProductId,
          entryQuantity: effectiveQuantity,
          entryUnit: form.entryUnit,
          quantityPerStaff: form.useStaffHelper && isStaffCategory(form.category) ? form.quantityPerStaff : null,
          // In the unit shown on the label. The SP derives the per-egg figure
          // and the line total from this.
          entryUnitCost: form.unitCost || 0,
          // Travels with the line so the record explains its own arithmetic;
          // fnpoultrycrateunits ignores it for anything but a raw-egg product.
          eggsPerCrate: EGGS_PER_CRATE,
        }],
      }
      if (form.poultryInternalUsageId) {
        await updatePoultryInternalUsage(form.poultryInternalUsageId, payload)
        toast({ title: "Draft updated" })
      } else {
        await createPoultryInternalUsage(payload)
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
        await postPoultryInternalUsage(confirm.id)
        toast({ title: "Posted", description: "Stock reduced and the cost booked as a non-cash expense." })
      } else {
        await deletePoultryInternalUsage(confirm.id)
        toast({ title: "Deleted" })
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
              <Link href="/poultry-products" className="font-medium text-amber-900 underline underline-offset-2">
                Go to Products
              </Link>
            </div>
          )}

          <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-5">
            <StatCard label="Records" value={String(stats.records)} />
            <StatCard label="Drafts" value={String(stats.drafts)} />
            <StatCard
              label="Posted cost"
              value={gh(stats.postedCost)}
              hint="Posting writes a stock movement, updates inventory and books a non-cash expense."
            />
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
                      <SelectItem key={c} value={c}>{POULTRY_INTERNAL_USE_CATEGORY_LABELS[c]}</SelectItem>
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
                  getKey={(r) => r.poultryInternalUsageId}
                  primary={(r) => `${POULTRY_INTERNAL_USE_CATEGORY_LABELS[r.category] ?? r.category} · ${gh(r.totalCostValue ?? 0)}`}
                  secondary={(r) => (
                    <>
                      <span>{(r.usageDate || "").split("T")[0]}</span>
                      <Badge variant="outline" className={cn("border-0", STATUS_BADGE[r.status])}>{r.status}</Badge>
                    </>
                  )}
                  details={(r) => [
                    { label: "Date", value: (r.usageDate || "").split("T")[0] },
                    { label: "Reason", value: POULTRY_INTERNAL_USE_CATEGORY_LABELS[r.category] ?? r.category },
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
                            <TableRow key={r.poultryInternalUsageId}>
                              <TableCell className="font-medium">{(r.usageDate || "").split("T")[0]}</TableCell>
                              <TableCell>{POULTRY_INTERNAL_USE_CATEGORY_LABELS[r.category] ?? r.category}</TableCell>
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
            <DialogTitle>{form.poultryInternalUsageId ? "Edit draft" : "Record internal use"}</DialogTitle>
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
                      <SelectItem key={c} value={c}>{POULTRY_INTERNAL_USE_CATEGORY_LABELS[c]}</SelectItem>
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
                    <Link href="/poultry-products"
                          className="mt-2 inline-block font-medium text-amber-900 underline underline-offset-2">
                      Go to Products
                    </Link>
                  </div>
                </FormField>
              ) : (
                <FormField label="Product" full
                           hint={selectedProduct
                             ? `${onHandBase.toLocaleString()} ${baseUnitLabel.toLowerCase()} in stock`
                                   + (isRawEggProduct ? ` · 1 crate = ${eggsPerCrate} eggs` : "")
                             : undefined}>
                  <Select value={String(form.poultryProductId || "")}
                          onValueChange={(v) => set("poultryProductId", Number(v))}>
                    <SelectTrigger><SelectValue placeholder="Pick a product" /></SelectTrigger>
                    <SelectContent>
                      {products.map((p) => (
                        <SelectItem key={p.poultryProductId} value={String(p.poultryProductId)}>{p.name}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </FormField>
              )}

              {/* Egg or crate, with the conversion stated on the control itself
                  rather than hidden in a dropdown — it is the thing people get
                  wrong, and it drives every number below. */}
              {isRawEggProduct && (
                <FormField label="Given out as" full>
                  <div className="grid grid-cols-2 gap-2">
                    <UnitChoice
                      active={form.entryUnit !== "Crate"}
                      title="Eggs"
                      sub="Single eggs"
                      onClick={() => changeEntryUnit("Egg")}
                    />
                    <UnitChoice
                      active={form.entryUnit === "Crate"}
                      title="Crates"
                      sub={`1 crate = ${eggsPerCrate} eggs`}
                      onClick={() => changeEntryUnit("Crate")}
                    />
                  </div>
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

              {/* The cost is asked for in whatever unit is being given out —
                  a crate costs GHC 15.00, and nobody should have to divide by 30
                  at data-entry time. changeEntryUnit rescales this on switch. */}
              <FormField
                label={`Cost per ${singular(form.entryUnit).toLowerCase()}`}
                hint={form.entryUnit === "Crate" && form.unitCost > 0
                  ? `= ${gh(round4(form.unitCost / Math.max(eggsPerCrate, 1)))} per egg`
                  : suggestedPerBase > 0
                    ? "Suggested from your stock history — change it if you need to"
                    : "No purchase history yet — enter what it costs you"}>
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

      {/* ------------------------------------------------------------ details */}
      <Dialog open={!!viewTarget} onOpenChange={(o) => { if (!o) setViewTarget(null) }}>
        <DialogContent className="w-[95vw] max-w-[560px]">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              {viewTarget?.referenceNo || "Internal use"}
              {viewTarget && (
                <Badge variant="outline" className={cn("border-0", STATUS_BADGE[viewTarget.status])}>
                  {viewTarget.status}
                </Badge>
              )}
            </DialogTitle>
            <DialogDescription>
              {(viewTarget?.usageDate || "").split("T")[0]}
            </DialogDescription>
          </DialogHeader>

          {viewTarget && (
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <Field label="Reason" value={POULTRY_INTERNAL_USE_CATEGORY_LABELS[viewTarget.category] ?? viewTarget.category} />
                <Field label="Recipient" value={viewTarget.recipientName || "-"} />
                <Field label="Product" value={viewTarget.items?.[0]?.productName || "-"} />
                <Field label="Quantity" value={describeQty(viewTarget)} />
                <Field label="Unit cost" value={gh(viewTarget.items?.[0]?.entryUnitCost ?? 0)} />
                <Field label="Total cost" value={gh(viewTarget.totalCostValue ?? 0)} />
                {viewTarget.staffCount ? <Field label="Staff" value={String(viewTarget.staffCount)} /> : null}
                {viewTarget.reason ? <Field label="Detail" value={viewTarget.reason} /> : null}
                {viewTarget.notes ? <Field label="Notes" value={viewTarget.notes} /> : null}
              </div>

              {/* Who did what, and the reversal reason -- the only things here
                  that the row itself can never show. */}
              <div className="border-t pt-3 space-y-1 text-sm text-slate-600">
                <HistoryLine label="Created" who={viewTarget.createdBy} when={viewTarget.createdAt} />
                <HistoryLine label="Posted" who={viewTarget.postedBy} when={viewTarget.postedAt} />
                <HistoryLine label="Reversed" who={viewTarget.reversedBy} when={viewTarget.reversedAt}
                             note={viewTarget.reversalReason} />
              </div>
            </div>
          )}

          <DialogFooter>
            <Button variant="outline" onClick={() => setViewTarget(null)}>Close</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

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
            await reversePoultryInternalUsage(reverseTarget.poultryInternalUsageId, reason)
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
  function rowActions(r: PoultryInternalUsage) {
    const view = (
      <Button size="sm" variant="ghost" title="View details" onClick={() => setViewTarget(r)}>
        <Eye className="w-4 h-4 text-slate-600" />
      </Button>
    )
    if (r.status === "Draft") {
      return (
        <>
          {view}
          <Button size="sm" variant="ghost" title="Edit" onClick={() => openEdit(r)}>
            <Pencil className="w-4 h-4" />
          </Button>
          <Button size="sm" variant="ghost" title="Post" onClick={() => setConfirm({
            type: "post", id: r.poultryInternalUsageId,
            title: "Post this internal use?",
            description: `${describeQty(r)} comes out of stock and ${gh(r.totalCostValue || 0)} is booked as a non-cash expense. No sale and no cash movement is created.`,
            actionLabel: "Post",
          })}>
            <CheckCircle2 className="w-4 h-4 text-green-600" />
          </Button>
          <Button size="sm" variant="ghost" title="Delete" onClick={() => setConfirm({
            type: "delete", id: r.poultryInternalUsageId,
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
        <>
          {view}
          <Button size="sm" variant="ghost" title="Reverse" onClick={() => setReverseTarget(r)}>
            <Undo2 className="w-4 h-4 text-amber-600" />
          </Button>
        </>
      )
    }
    // Reversed. Arithmetically this is a draft again: its ledger rows cancel to
    // zero and its expense is cancelled, so it edits and deletes like one
    // (migration 220). Re-posting is the only step that moves stock, which is
    // why fixing the figures and posting them are two separate presses.
    return (
      <>
        {view}
        <Button size="sm" variant="ghost" title="Edit" onClick={() => openEdit(r)}>
          <Pencil className="w-4 h-4" />
        </Button>
        <Button size="sm" variant="ghost" title="Post again" onClick={() => setConfirm({
          type: "post", id: r.poultryInternalUsageId,
          title: "Post this reversed record again?",
          description: `${describeQty(r)} comes back out of stock and ${gh(r.totalCostValue || 0)} is booked as a non-cash expense again. The reversal stays in the stock history.`,
          actionLabel: "Post again",
        })}>
          <CheckCircle2 className="w-4 h-4 text-green-600" />
        </Button>
        <Button size="sm" variant="ghost" title="Delete" onClick={() => setConfirm({
          type: "delete", id: r.poultryInternalUsageId,
          title: "Delete this reversed record?",
          description: "The stock came back when this was reversed, so nothing moves now. The out-and-back entries stay in stock history.",
          actionLabel: "Delete", destructive: true,
        })}>
          <Trash2 className="w-4 h-4 text-red-600" />
        </Button>
      </>
    )
  }
}

// ------------------------------------------------------------------ helpers

function isStaffCategory(c: InternalUseCategory) {
  return STAFF_BASED_CATEGORIES.includes(c)
}

/** "10 crates (300 eggs)" — the crate figure is what people said, the egg figure is what moved. */
function describeQty(r: PoultryInternalUsage): string {
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

/** The label-over-value pair the batch production detail page uses. */
function Field({ label, value }: { label: string; value: string }) {
  return (
    <div className="min-w-0">
      <div className="text-xs text-muted-foreground">{label}</div>
      <div className="font-medium break-words">{value}</div>
    </div>
  )
}

/** One "Posted: 2026-08-24 - admin" line; renders nothing when that step never happened. */
function HistoryLine({ label, who, when, note }: {
  label: string; who?: string | null; when?: string | null; note?: string | null
}) {
  if (!who && !when) return null
  return (
    <p>
      <span className="text-slate-500">{label}: </span>
      {(when || "").split("T")[0]}{who ? ` - ${who}` : ""}
      {note ? <span className="text-slate-500"> ({note})</span> : null}
    </p>
  )
}

/**
 * `hint` turns the card into a callout: tinted, outlined, and carrying a
 * sentence about what the number means. Muted small print got lost next to
 * three plain cards, and the consequence it states -- that posting is what
 * actually moves stock and money -- is the thing a user needs to see before
 * pressing Post, not after.
 */
function StatCard({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <Card className={cn(hint && "border-sky-300 bg-sky-50")}>
      <CardContent className="p-4">
        <p className={cn("text-xs font-medium", hint ? "text-sky-700" : "text-slate-500")}>{label}</p>
        <p className="text-lg font-semibold text-slate-900 mt-0.5">{value}</p>
        {hint && (
          <p className="mt-2 flex items-start gap-1.5 text-xs font-medium leading-snug text-sky-900">
            <Info className="w-4 h-4 shrink-0 mt-px" />
            <span>{hint}</span>
          </p>
        )}
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
