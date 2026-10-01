"use client"

// Hotel Internal Use (Sales, Expenses & Money → Expenses → Internal Use).
// Migration 334.
//
// Poultry's Internal Use (app/poultry-internal-use), through the Restaurant's
// copy (app/restaurant-internal-use), in violet: supplies the hotel uses itself
// -- rooms restocked with amenities, housekeeping consumption, staff use,
// complimentary, donation, damaged or written off. Recorded at cost, never as a
// sale. Draft -> Posted -> Reversed. Posting takes the stock out through the
// purchase lots; the cost reaches Profit & Loss only for stock expensed when
// consumed (stock expensed when purchased was charged when it was bought).

import { useEffect, useMemo, useState, type ReactNode } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { PageHeader } from "@/components/hotel/page-header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectGroup, SelectItem, SelectLabel, SelectTrigger, SelectValue } from "@/components/ui/select"
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
import { Plus, Loader2, PackageMinus, Pencil, Trash2, Undo2, CheckCircle2, Eye, Info } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { cn } from "@/lib/utils"
import { useFmt } from "@/lib/currency"
import { INTERNAL_USE_REVERSAL_REASONS } from "@/lib/api/internal-use"
import {
  listHotelInternalUsage, listHotelInternalUseItems, createHotelInternalUsage,
  updateHotelInternalUsage, deleteHotelInternalUsage, postHotelInternalUsage,
  reverseHotelInternalUsage,
  HOTEL_INTERNAL_USE_CATEGORIES, HOTEL_INTERNAL_USE_CATEGORY_LABELS, HOTEL_STAFF_BASED_CATEGORIES,
  type HotelInternalUsage, type HotelInternalUseOption, type HotelInternalUseItemType,
  type HotelInternalUseCategory as InternalUseCategory,
} from "@/lib/api/hotel-supplies"
import { fmtDateTime, fmtInstant } from "@/lib/utils/company-datetime"

const STATUS_BADGE: Record<string, string> = {
  Draft: "bg-slate-100 text-slate-700",
  Posted: "bg-green-100 text-green-700",
  Reversed: "bg-amber-100 text-amber-700",
}

const CATEGORIES = HOTEL_INTERNAL_USE_CATEGORIES
const catLabel = (c: string) => HOTEL_INTERNAL_USE_CATEGORY_LABELS[c as InternalUseCategory] ?? c

type ConfirmState = {
  type: "post" | "delete"
  id: number
  title: string
  description: string
  actionLabel: string
  destructive?: boolean
}

/** "Ingredient:12" / "MenuItem:4" — one Select value for either kind of line. */
const optKey = (t: HotelInternalUseItemType, id: number) => `${t}:${id}`

const emptyForm = () => ({
  internalUsageId: 0,
  usageDate: today(),
  category: "StaffWelfare" as InternalUseCategory,
  recipientName: "",
  reason: "",
  notes: "",
  // quantity
  itemKey: "",
  entryQuantity: 0,
  unitCost: 0,
  // staff helper
  useStaffHelper: true,
  staffCount: 0,
  quantityPerStaff: 0,
})

export default function HotelInternalUsePage() {
  const router = useRouter()
  const { toast } = useToast()
  const gh = useFmt()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [items, setItems] = useState<HotelInternalUsage[]>([])
  const [products, setProducts] = useState<HotelInternalUseOption[]>([])
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

  const [confirm, setConfirm] = useState<ConfirmState | null>(null)
  const [busy, setBusy] = useState(false)
  const [reverseTarget, setReverseTarget] = useState<HotelInternalUsage | null>(null)
  const [viewTarget, setViewTarget] = useState<HotelInternalUsage | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Hotel") router.replace("/dashboard")
  }, [activeFarmType, router])

  // allSettled, not all: independent reads (Poultry's reasoning).
  async function load() {
    setLoading(true)
    const [rowsRes, prodsRes] = await Promise.allSettled([listHotelInternalUsage(), listHotelInternalUseItems()])
    if (rowsRes.status === "fulfilled") setItems(rowsRes.value)
    else toast({ title: "Couldn't load internal use records", description: rowsRes.reason?.message, variant: "destructive" })
    if (prodsRes.status === "fulfilled") setProducts(prodsRes.value)
    else toast({ title: "Couldn't load products", description: prodsRes.reason?.message, variant: "destructive" })
    setLoading(false)
  }
  useEffect(() => { void load() }, [])

  const stockItems = useMemo(() => products.filter((p) => p.itemType === "Supply"), [products])
  const menuItems = useMemo(() => products.filter((p) => p.itemType === "MenuItem"), [products])

  // ---------------------------------------------------------------- quantity
  const selectedProduct = useMemo(
    () => products.find((p) => optKey(p.itemType, p.itemId) === form.itemKey),
    [products, form.itemKey],
  )
  const isMenu = selectedProduct?.itemType === "MenuItem"
  const unitLabel = isMenu ? "portion" : (selectedProduct?.unit || "unit")
  const entryLabel = plural(unitLabel)

  const effectiveQuantity = useMemo(() => {
    if (form.useStaffHelper && isStaffCategory(form.category)) {
      return round3((form.staffCount || 0) * (form.quantityPerStaff || 0))
    }
    return form.entryQuantity || 0
  }, [form.useStaffHelper, form.category, form.staffCount, form.quantityPerStaff, form.entryQuantity])

  const totalCost = useMemo(() => round2(effectiveQuantity * (form.unitCost || 0)), [effectiveQuantity, form.unitCost])
  const onHand = selectedProduct?.onHand ?? 0
  const notEnough = !!selectedProduct && effectiveQuantity > onHand
  const suggested = selectedProduct?.suggestedUnitCost ?? 0

  // Seed the cost from stock history when the item changes (Poultry 218). The
  // field stays editable; 0 just means nothing is costed yet.
  function pickItem(key: string) {
    const p = products.find((x) => optKey(x.itemType, x.itemId) === key)
    setForm((f) => ({ ...f, itemKey: key, unitCost: round4(p?.suggestedUnitCost ?? 0) }))
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
    const only = products.length === 1 ? products[0] : undefined
    setForm({
      ...emptyForm(),
      itemKey: only ? optKey(only.itemType, only.itemId) : "",
      unitCost: round4(only?.suggestedUnitCost ?? 0),
    })
    setOpen(true)
  }

  function openEdit(r: HotelInternalUsage) {
    const line = r.items?.[0]
    setForm({
      ...emptyForm(),
      internalUsageId: r.internalUsageId,
      usageDate: (r.usageDate || "").split("T")[0],
      category: r.category,
      recipientName: r.recipientName ?? "",
      reason: r.reason ?? "",
      notes: r.notes ?? "",
      itemKey: line ? optKey(line.itemType, (line.itemType === "MenuItem" ? line.menuItemId : line.ingredientId) ?? 0) : "",
      entryQuantity: line?.entryQuantity ?? 0,
      unitCost: line?.entryUnitCost ?? 0,
      useStaffHelper: false,
      staffCount: r.staffCount ?? 0,
      quantityPerStaff: line?.quantityPerStaff ?? 0,
    })
    setOpen(true)
  }

  function validate(): string | null {
    if (!form.usageDate) return "Pick the date."
    if (form.usageDate > today()) return "The date cannot be in the future."
    if (!form.category) return "Pick what the stock was used for."
    if (!selectedProduct) return "Pick the product."
    if (effectiveQuantity <= 0) return "Enter a quantity greater than zero."
    if (form.useStaffHelper && isStaffCategory(form.category)) {
      if ((form.staffCount || 0) <= 0) return "Enter how many staff received it."
      if ((form.quantityPerStaff || 0) <= 0) return "Enter how much each staff member received."
    }
    if (notEnough) return `Not enough stock: ${onHand} ${unitLabel} available, ${effectiveQuantity} needed.`
    return null
  }

  async function save() {
    const bad = validate()
    if (bad) { toast({ title: bad, variant: "destructive" }); return }
    if (!selectedProduct) return
    setSaving(true)
    try {
      const staff = form.useStaffHelper && isStaffCategory(form.category)
      const payload = {
        usageDate: form.usageDate,
        category: form.category,
        reason: form.reason || null,
        recipientName: form.recipientName || null,
        staffCount: staff ? form.staffCount : null,
        notes: form.notes || null,
        items: [{
          itemType: selectedProduct.itemType,
          ingredientId: selectedProduct.itemType === "Supply" ? selectedProduct.itemId : null,
          menuItemId: selectedProduct.itemType === "MenuItem" ? selectedProduct.itemId : null,
          entryQuantity: effectiveQuantity,
          entryUnit: unitLabel,
          quantityPerStaff: staff ? form.quantityPerStaff : null,
          entryUnitCost: form.unitCost || 0,
        }],
      }
      if (form.internalUsageId) {
        await updateHotelInternalUsage(form.internalUsageId, payload)
        toast({ title: "Draft updated" })
      } else {
        await createHotelInternalUsage(payload)
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
        await postHotelInternalUsage(confirm.id)
        toast({ title: "Posted", description: "Stock reduced and the cost booked as a non-cash expense." })
      } else {
        await deleteHotelInternalUsage(confirm.id)
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

  const showStaffHelper = isStaffCategory(form.category)

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 min-w-0 overflow-y-auto p-4 sm:p-6 space-y-4">
          <PageHeader icon={PackageMinus} title="Internal Use"
                      subtitle="Supplies used by the hotel itself — rooms restocked, housekeeping, staff use, complimentary, donated or written off. Recorded at cost, never as a sale.">
            <Button onClick={openCreate} className="bg-violet-600 hover:bg-violet-700">
              <Plus className="w-4 h-4 mr-2" /> Record internal use
            </Button>
          </PageHeader>
          <p className="inline-flex items-start gap-1.5 rounded-md border border-violet-200 bg-violet-50 px-2.5 py-1.5 text-xs font-medium text-violet-900">
            <Info className="w-4 h-4 shrink-0 mt-px" />
            <span>Posting writes a stock movement, updates inventory and books a non-cash expense.</span>
          </p>

          {!loading && products.length === 0 && (
            <div className="rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm">
              <span className="font-medium text-amber-900">No products in this company yet. </span>
              <span className="text-amber-800">
                Internal Use takes stock off a product, so add one before recording anything.{" "}
              </span>
              <Link href="/hotel-inventory" className="font-medium text-amber-900 underline underline-offset-2">
                Go to Inventory
              </Link>
            </div>
          )}

          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
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
                  <SelectTrigger className="w-full sm:w-36"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="ALL">All statuses</SelectItem>
                    <SelectItem value="Draft">Draft</SelectItem>
                    <SelectItem value="Posted">Posted</SelectItem>
                    <SelectItem value="Reversed">Reversed</SelectItem>
                  </SelectContent>
                </Select>
                <Select value={categoryFilter} onValueChange={setCategoryFilter}>
                  <SelectTrigger className="w-full sm:w-52"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="ALL">All reasons</SelectItem>
                    {CATEGORIES.map((c) => <SelectItem key={c} value={c}>{catLabel(c)}</SelectItem>)}
                  </SelectContent>
                </Select>
              </>
            )}
          />

          <Card>
            <CardContent className="p-0 md:p-2">
              {loading ? (
                <div className="flex items-center gap-2 p-8 text-slate-500">
                  <Loader2 className="w-4 h-4 animate-spin" /> Loading…
                </div>
              ) : visible.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No internal use recorded yet.</div>
              ) : (
                <MobileCardList
                  items={pg.pageItems}
                  pagination={pg.paginationProps}
                  defaultOpen
                  striped
                  getKey={(r) => r.internalUsageId}
                  primary={(r) => catLabel(r.category)}
                  secondary={(r) => (
                    <>
                      <span>{fmtDateTime(r.usageDate, r)}</span>
                      <Badge variant="outline" className={cn("border-0", STATUS_BADGE[r.status])}>{r.status}</Badge>
                    </>
                  )}
                  highlights={(r) => [
                    { label: "Quantity", value: describeQty(r), accent: "rose" },
                    { label: "Cost", value: gh(r.totalCostValue ?? 0), accent: "violet" },
                  ]}
                  details={(r) => [
                    { label: "Date", value: fmtDateTime(r.usageDate, r) },
                    { label: "Product", value: r.items?.[0]?.itemName ?? "—" },
                    { label: "Recipient", value: r.recipientName ?? "—" },
                    { label: "Staff", value: r.staffCount ? r.staffCount.toLocaleString() : "—" },
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
                            <TableRow key={r.internalUsageId}>
                              <TableCell className="font-medium">{fmtDateTime(r.usageDate, r)}</TableCell>
                              <TableCell>{catLabel(r.category)}</TableCell>
                              <TableCell>{r.items?.[0]?.itemName ?? "—"}</TableCell>
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
        <DialogContent className="w-[95vw] sm:max-w-[900px] max-h-[90vh] overflow-y-auto p-4 sm:p-6">
          <DialogHeader>
            <DialogTitle>{form.internalUsageId ? "Edit draft" : "Record internal use"}</DialogTitle>
            <DialogDescription>
              This reduces stock and records the cost. It does not create a sale, a customer balance or a
              cash transaction.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4">
            <FormSection title="What was used, and why" color="rose" columns={2} stackOnMobile>
              <FormField label="Date">
                <Input type="date" value={form.usageDate} max={today()} onChange={(e) => set("usageDate", e.target.value)} />
              </FormField>
              <FormField label="Reason">
                <Select value={form.category} onValueChange={(v) => set("category", v as InternalUseCategory)}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {CATEGORIES.map((c) => <SelectItem key={c} value={c}>{catLabel(c)}</SelectItem>)}
                  </SelectContent>
                </Select>
              </FormField>
              <FormField label="Who received it" hint="Optional">
                <Input value={form.recipientName} onChange={(e) => set("recipientName", e.target.value)}
                       placeholder="e.g. Housekeeping team" />
              </FormField>
              <FormField label="Detail" hint="Optional">
                <Input value={form.reason} onChange={(e) => set("reason", e.target.value)}
                       placeholder="e.g. Friday staff lunch" />
              </FormField>
            </FormSection>

            <FormSection title="How much" color="blue" columns={2} stackOnMobile>
              {products.length === 0 ? (
                <FormField label="Product" full>
                  <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm">
                    <p className="font-medium text-amber-900">This company has no products yet.</p>
                    <p className="mt-1 text-amber-800">
                      Internal Use takes stock off a product, so add one first — then come back and record
                      what was given out.
                    </p>
                    <Link href="/hotel-inventory"
                          className="mt-2 inline-block font-medium text-amber-900 underline underline-offset-2">
                      Go to Inventory
                    </Link>
                  </div>
                </FormField>
              ) : (
                <FormField label="Product" full
                           hint={selectedProduct
                             ? isMenu
                               ? `Takes its recipe out of stock · enough for ${onHand.toLocaleString()} ${plural("portion").toLowerCase()}`
                               : `${onHand.toLocaleString()} ${unitLabel.toLowerCase()} in stock`
                             : undefined}>
                  <Select value={form.itemKey} onValueChange={pickItem}>
                    <SelectTrigger><SelectValue placeholder="Pick a product" /></SelectTrigger>
                    <SelectContent>
                      {stockItems.length > 0 && (
                        <SelectGroup>
                          <SelectLabel>Stock items</SelectLabel>
                          {stockItems.map((p) => (
                            <SelectItem key={optKey(p.itemType, p.itemId)} value={optKey(p.itemType, p.itemId)}>{p.name}</SelectItem>
                          ))}
                        </SelectGroup>
                      )}
                      {menuItems.length > 0 && (
                        <SelectGroup>
                          <SelectLabel>Menu items (uses the recipe)</SelectLabel>
                          {menuItems.map((p) => (
                            <SelectItem key={optKey(p.itemType, p.itemId)} value={optKey(p.itemType, p.itemId)}>{p.name}</SelectItem>
                          ))}
                        </SelectGroup>
                      )}
                    </SelectContent>
                  </Select>
                </FormField>
              )}

              {showStaffHelper && (
                <FormField label="How do you want to enter it?" full>
                  <div className="grid grid-cols-2 gap-2">
                    <UnitChoice active={!form.useStaffHelper} title="Total quantity" sub="Type one number"
                                onClick={() => set("useStaffHelper", false)} />
                    <UnitChoice active={form.useStaffHelper} title="Per staff member" sub="Staff × amount each"
                                onClick={() => set("useStaffHelper", true)} />
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

              <FormField
                label={`Cost per ${singular(unitLabel).toLowerCase()}`}
                hint={suggested > 0
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
                    value={effectiveQuantity > 0 ? `${effectiveQuantity.toLocaleString()} ${entryLabel.toLowerCase()}` : "—"}
                    note={isMenu && effectiveQuantity > 0 ? "Its recipe ingredients come out of stock" : undefined}
                  />
                  <SummaryRow label="Cost recorded" value={gh(totalCost)} />
                </dl>
                {notEnough && (
                  <p className="mt-3 text-xs font-medium text-red-600">
                    Not enough stock: only {onHand.toLocaleString()} {unitLabel.toLowerCase()} available,
                    {" "}{effectiveQuantity.toLocaleString()} needed.
                  </p>
                )}
                <p className="mt-3 text-[11px] leading-relaxed text-slate-500">
                  Posting reduces stock and records the cost as a non-cash expense. It does not create a
                  sale, a customer balance or any cash movement. Stock expensed when purchased was already
                  charged to Profit &amp; Loss when it was bought, so it is not charged again.
                </p>
              </div>
              <FormField label="Notes" hint="Optional">
                <Textarea rows={2} value={form.notes} onChange={(e) => set("notes", e.target.value)} />
              </FormField>
            </FormSection>
          </div>

          <div className="flex flex-col gap-2 pt-4 sm:flex-row sm:justify-end">
            <Button variant="outline" className="w-full sm:w-auto" onClick={() => setOpen(false)} disabled={saving}>Cancel</Button>
            <Button className="w-full sm:w-auto bg-violet-600 hover:bg-violet-700" onClick={() => void save()} disabled={saving || notEnough}>
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
        <DialogContent className="w-[95vw] sm:max-w-[620px] max-h-[88vh] overflow-y-auto gap-0 bg-slate-50 p-0">
          <div className="px-6 pt-6 pb-4">
            <DialogHeader className="space-y-1.5 text-left">
              <div className="flex items-center justify-between gap-3">
                <DialogTitle className="text-lg font-semibold text-slate-900">
                  {viewTarget?.referenceNo || "Internal use"}
                </DialogTitle>
                {viewTarget && (
                  <Badge variant="outline" className={cn("border-0 shrink-0", STATUS_BADGE[viewTarget.status])}>
                    {viewTarget.status}
                  </Badge>
                )}
              </div>
              <DialogDescription className="text-sm text-slate-500">
                {fmtDateTime(viewTarget?.usageDate, viewTarget)}
                {viewTarget ? ` · ${catLabel(viewTarget.category)}` : ""}
              </DialogDescription>
            </DialogHeader>
          </div>

          {viewTarget && (
            <div className="space-y-3 px-6 pb-6">
              {viewTarget.status === "Reversed" && (
                <DetailCard tone="amber">
                  <div className="flex gap-3">
                    <Undo2 className="mt-0.5 h-4 w-4 shrink-0 text-amber-700" />
                    <div className="min-w-0">
                      <p className="text-sm font-semibold text-amber-900">
                        Reversed — {viewTarget.reversalReason || "no reason recorded"}
                      </p>
                      <p className="mt-1 text-xs text-amber-800">{fmtInstant(viewTarget.reversedAt)}</p>
                    </div>
                  </div>
                </DetailCard>
              )}

              <DetailCard title="What was used">
                <p className="text-sm font-medium text-slate-900">{viewTarget.items?.[0]?.itemName || "-"}</p>
                <div className="mt-2 flex items-end justify-between gap-4">
                  <span className="text-sm text-slate-500">
                    {describeQty(viewTarget)} @ {gh(viewTarget.items?.[0]?.entryUnitCost ?? 0)}
                  </span>
                  <span className="text-xl font-bold tabular-nums text-slate-900">{gh(viewTarget.totalCostValue ?? 0)}</span>
                </div>
                {viewTarget.status === "Posted" && (
                  <p className="mt-2 text-xs text-slate-500">
                    Charged to Profit &amp; Loss now: {gh(viewTarget.plCost ?? 0)}.
                    {" "}The rest was charged when the stock was bought (expense when purchased), or never came
                    through a purchase.
                  </p>
                )}
              </DetailCard>

              <DetailCard title="Who and why">
                <dl className="divide-y divide-slate-100 text-sm">
                  <DetailRow label="Reason" value={catLabel(viewTarget.category)} />
                  <DetailRow label="Recipient" value={viewTarget.recipientName} />
                  <DetailRow label="Staff" value={viewTarget.staffCount ? String(viewTarget.staffCount) : null} />
                  <DetailRow label="Detail" value={viewTarget.reason} />
                  <DetailRow label="Notes" value={viewTarget.notes} />
                </dl>
              </DetailCard>

              <DetailCard title="History">
                <ol className="space-y-3">
                  <TimelineStep label="Created"  who={viewTarget.createdBy}  when={viewTarget.createdAt} />
                  <TimelineStep label="Posted"   who={viewTarget.postedBy}   when={viewTarget.postedAt}  tone="green" />
                  <TimelineStep label="Reversed" who={viewTarget.reversedBy} when={viewTarget.reversedAt} tone="amber" />
                </ol>
              </DetailCard>

              <div className="flex justify-end pt-1">
                <Button variant="outline" onClick={() => setViewTarget(null)}>Close</Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>

      <PromptDialog
        open={!!reverseTarget}
        onOpenChange={(o) => { if (!o) setReverseTarget(null) }}
        title="Reverse this internal use?"
        description="The stock comes back with an opposite ledger entry — the original is kept — and the linked expense is cancelled."
        label="Reason for reversal"
        options={INTERNAL_USE_REVERSAL_REASONS}
        confirmLabel="Reverse"
        confirmVariant="destructive"
        onSubmit={async (reason: string) => {
          if (!reverseTarget) return
          try {
            await reverseHotelInternalUsage(reverseTarget.internalUsageId, reason)
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

  function rowActions(r: HotelInternalUsage) {
    const view = (
      <Button size="sm" variant="ghost" title="View details" onClick={() => setViewTarget(r)}>
        <Eye className="w-4 h-4 text-slate-600" />
      </Button>
    )
    if (r.status === "Draft") {
      return (
        <>
          {view}
          <Button size="sm" variant="ghost" title="Edit" onClick={() => openEdit(r)}><Pencil className="w-4 h-4" /></Button>
          <Button size="sm" variant="ghost" title="Post" onClick={() => setConfirm({
            type: "post", id: r.internalUsageId,
            title: "Post this internal use?",
            description: `${describeQty(r)} comes out of stock and ${gh(r.totalCostValue || 0)} is booked as a non-cash expense. No sale and no cash movement is created.`,
            actionLabel: "Post",
          })}>
            <CheckCircle2 className="w-4 h-4 text-green-600" />
          </Button>
          <Button size="sm" variant="ghost" title="Delete" onClick={() => setConfirm({
            type: "delete", id: r.internalUsageId,
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
    return (
      <>
        {view}
        <Button size="sm" variant="ghost" title="Edit" onClick={() => openEdit(r)}><Pencil className="w-4 h-4" /></Button>
        <Button size="sm" variant="ghost" title="Post again" onClick={() => setConfirm({
          type: "post", id: r.internalUsageId,
          title: "Post this reversed record again?",
          description: `${describeQty(r)} comes back out of stock and ${gh(r.totalCostValue || 0)} is booked as a non-cash expense again. The reversal stays in the stock history.`,
          actionLabel: "Post again",
        })}>
          <CheckCircle2 className="w-4 h-4 text-green-600" />
        </Button>
        <Button size="sm" variant="ghost" title="Delete" onClick={() => setConfirm({
          type: "delete", id: r.internalUsageId,
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
  return HOTEL_STAFF_BASED_CATEGORIES.includes(c)
}

/** "3 portions" / "2.5 kgs" — what was typed, in the item's unit. */
function describeQty(r: HotelInternalUsage): string {
  const line = r.items?.[0]
  if (!line) return "—"
  return `${(line.entryQuantity ?? 0).toLocaleString()} ${plural(line.entryUnit || "unit").toLowerCase()}`
}

const round2 = (n: number) => Math.round(n * 100) / 100
const round3 = (n: number) => Math.round(n * 1000) / 1000
const round4 = (n: number) => Math.round(n * 10000) / 10000
const today = () => new Date().toISOString().split("T")[0]

function singular(unit: string) {
  const u = (unit || "unit").trim()
  return u.toLowerCase().endsWith("s") ? u.slice(0, -1) : u
}

function plural(unit: string) {
  const u = (unit || "").trim()
  if (!u) return "Units"
  return u.toLowerCase().endsWith("s") ? u : `${u}s`
}

function DetailCard({ title, children, tone = "white" }: { title?: string; children: ReactNode; tone?: "white" | "amber" }) {
  return (
    <div className={cn("rounded-lg border p-4", tone === "amber" ? "border-amber-200 bg-amber-50" : "border-slate-200 bg-white")}>
      {title && <p className="mb-3 text-[11px] font-semibold uppercase tracking-wider text-slate-500">{title}</p>}
      {children}
    </div>
  )
}

function DetailRow({ label, value }: { label: string; value?: string | null }) {
  if (!value) return null
  return (
    <div className="flex items-start justify-between gap-6 py-2.5 first:pt-0 last:pb-0">
      <dt className="shrink-0 text-slate-500">{label}</dt>
      <dd className="break-words text-right font-medium text-slate-900">{value}</dd>
    </div>
  )
}

function TimelineStep({ label, who, when, tone = "slate" }: {
  label: string; who?: string | null; when?: string | null; tone?: "slate" | "green" | "amber"
}) {
  if (!who && !when) return null
  const dot = tone === "green" ? "bg-emerald-500" : tone === "amber" ? "bg-amber-500" : "bg-slate-300"
  return (
    <li className="flex items-center gap-3 text-sm">
      <span className={cn("h-2 w-2 shrink-0 rounded-full", dot)} />
      <span className="font-medium text-slate-900">{label}</span>
      <span className="ml-auto text-xs text-slate-500">{(when || "").split("T")[0]}</span>
    </li>
  )
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

function UnitChoice({ active, title, sub, onClick }: { active: boolean; title: string; sub: string; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className={cn(
        "rounded-lg border-2 px-3 py-2 text-left transition-all",
        active ? "border-violet-500 bg-violet-50 ring-2 ring-violet-500/30" : "border-slate-200 bg-white hover:border-slate-300",
      )}
    >
      <div className="text-sm font-semibold text-slate-900">{title}</div>
      <div className="text-[11px] text-slate-500">{sub}</div>
    </button>
  )
}

function SummaryRow({ label, value, note }: { label: string; value: string; note?: string }) {
  return (
    <div className="flex items-baseline justify-between gap-4 py-2">
      <dt className="text-slate-500">{label}</dt>
      <dd className="text-right">
        <span className="font-semibold text-slate-900">{value}</span>
        {note && <span className="block text-[11px] text-slate-500">{note}</span>}
      </dd>
    </div>
  )
}
