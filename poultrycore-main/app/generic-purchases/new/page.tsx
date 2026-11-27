"use client"

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ArrowLeft, CheckCircle2, Loader2, Package, Plus, X } from "lucide-react"
import { RelatedProjectField, LineProjectButton, loadDocumentProjects } from "@/components/generic/projects/form-project-field"
import { useProjectsEnabled } from "@/hooks/use-generic-projects"
import { buildAssignment, projectIdFromQuery } from "@/lib/generic/project-math"
import type { ProjectSplit } from "@/lib/api/generic-projects"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  approvePurchase, createPurchase, getCashAccounts, getProducts, getPurchase, getSuppliers, getUnitsOfMeasure, getUomConversions, updatePurchase,
  type GenericCashAccount, type GenericProduct, type GenericSupplier, type GenericUomConversion,
} from "@/lib/api/generic"
import { DEFAULT_UNITS } from "@/lib/generic/default-units"

const PAY_METHODS = ["Cash", "MoMo", "Bank", "Card", "Credit", "Mixed"]

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}

type Row = {
  genericProductId?: number
  description: string
  quantity: number
  unitCost: number
  discountAmount: number
  /** Unit this line is bought in ("" = the product's base unit). */
  purchaseUnit: string
  /** Base units in one purchaseUnit; stock rises by quantity x unitFactor. */
  unitFactor: number
  /** 483: this line's own project split; null = follows "Related project". */
  projects?: ProjectSplit[] | null
}

const blankRow = (): Row => ({ genericProductId: undefined, description: "", quantity: 1, unitCost: 0, discountAmount: 0, purchaseUnit: "", unitFactor: 1 })

const round2 = (n: number) => Math.round(n * 100) / 100
const fmtQty = (n: number) => new Intl.NumberFormat(undefined, { maximumFractionDigits: 3 }).format(n)
const same = (a?: string | null, b?: string | null) => (a ?? "").trim().toLowerCase() === (b ?? "").trim().toLowerCase()

/** The product's base stock unit, or "unit" when setup left it blank. */
function baseUnitOf(p?: GenericProduct | null) {
  return (p?.unitOfMeasure ?? "").trim() || "unit"
}

/**
 * Units a product can be bought in, from its setup: the base unit, its purchase and
 * sales units, and every conversion to or from the base unit (product-specific first,
 * then farm-wide). factor = base units in one of that unit; null = not known yet.
 * After those come every other unit (the company's saved units, then the general
 * list) so the buyer can switch unit at the point of purchase.
 */
function unitOptionsFor(p: GenericProduct | undefined, conversions: GenericUomConversion[], allUnits: string[] = []) {
  const base = baseUnitOf(p)
  const out: { unit: string; factor: number | null }[] = [{ unit: base, factor: 1 }]
  const add = (unit: string | null | undefined, factor: number | null) => {
    const u = (unit ?? "").trim()
    if (!u) return
    const hit = out.find((o) => same(o.unit, u))
    if (!hit) out.push({ unit: u, factor })
    else if (hit.factor == null && factor != null) hit.factor = factor
  }
  const convs = [
    ...conversions.filter((c) => c.isActive !== false && p && c.genericProductId === p.genericProductId),
    ...conversions.filter((c) => c.isActive !== false && c.genericProductId == null),
  ]
  for (const c of convs) {
    if (same(c.toUnit, base) && c.conversionFactor > 0) add(c.fromUnit, Number(c.conversionFactor))
    else if (same(c.fromUnit, base) && c.conversionFactor > 0) add(c.toUnit, 1 / Number(c.conversionFactor))
  }
  add(p?.purchaseUnit, null)
  add(p?.salesUnit, null)
  for (const u of allUnits) add(u, null)
  for (const u of DEFAULT_UNITS) add(u, null)
  return out
}

export default function NewGenericPurchasePage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [suppliers, setSuppliers] = useState<GenericSupplier[]>([])
  const [products, setProducts] = useState<GenericProduct[]>([])
  const [cashAccounts, setCashAccounts] = useState<GenericCashAccount[]>([])
  const [conversions, setConversions] = useState<GenericUomConversion[]>([])
  /** The company's saved units of measure (names). */
  const [companyUnits, setCompanyUnits] = useState<string[]>([])
  /** Set when the page edits an existing Draft (?edit=<id>). */
  const [editId, setEditId] = useState<number | null>(null)
  /** Once the user types their own "Amount paid now", it stops following the total. */
  const [paidTouched, setPaidTouched] = useState(false)

  const [header, setHeader] = useState(() => {
    const now = new Date()
    const date = now.toISOString().slice(0, 10)
    const pad = String(now.getHours()).padStart(2, "0") + String(now.getMinutes()).padStart(2, "0")
    const rand = String(Math.floor(Math.random() * 10000)).padStart(4, "0")
    const invoiceNumber = `PUR-${date.replace(/-/g, "")}-${pad}${rand}`
    return {
      purchaseDate: date,
      genericSupplierId: "",
      supplierName: "",
      invoiceNumber,
      headerDiscountAmount: "0",
      taxAmount: "0",
      amountPaid: "0",
      paymentMethod: "Cash",
      genericCashAccountId: "",
      notes: "",
    }
  })

  const [rows, setRows] = useState<Row[]>([blankRow()])
  // 483: Projects & Contracts. Opened from a project ("Record purchase") = preselected.
  const { enabled: projectsEnabled } = useProjectsEnabled()
  const [projectId, setProjectId] = useState<number | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    let cancelled = false
    ;(async () => {
      try {
        const editParam = Number(new URLSearchParams(window.location.search).get("edit")) || null
        setProjectId(projectIdFromQuery(window.location.search))
        const [ss, ps, as, cs, existing] = await Promise.all([
          getSuppliers(), getProducts(), getCashAccounts(),
          getUomConversions().catch(() => [] as GenericUomConversion[]),
          editParam ? getPurchase(editParam) : Promise.resolve(null),
        ])
        if (cancelled) return
        getUnitsOfMeasure()
          .then((us) => { if (!cancelled) setCompanyUnits(us.filter((u) => u.isActive !== false).map((u) => u.unitName)) })
          .catch(() => {})
        setSuppliers(ss); setProducts(ps); setCashAccounts(as); setConversions(cs ?? [])
        if (editParam) {
          if (!existing) throw new Error(`Purchase #${editParam} was not found.`)
          if (existing.status !== "Draft") {
            toast({ title: `Purchase #${editParam} is ${existing.status}`, description: "Only a Draft purchase can be edited.", variant: "destructive" })
            router.replace("/generic-inventory?tab=purchases")
            return
          }
          setEditId(editParam)
          setHeader({
            purchaseDate: String(existing.purchaseDate ?? "").slice(0, 10),
            genericSupplierId: existing.genericSupplierId ? String(existing.genericSupplierId) : "",
            supplierName: "",
            invoiceNumber: existing.invoiceNumber ?? "",
            headerDiscountAmount: String(existing.discountAmount ?? 0),
            taxAmount: String(existing.taxAmount ?? 0),
            amountPaid: String(existing.amountPaid ?? 0),
            paymentMethod: existing.paymentMethod || "Cash",
            genericCashAccountId: existing.genericCashAccountId ? String(existing.genericCashAccountId) : "",
            notes: existing.notes ?? "",
          })
          // A saved part-payment is the user's own figure; a full payment keeps following the total.
          setPaidTouched(round2(existing.amountPaid ?? 0) !== round2(existing.totalAmount ?? 0))
          setRows((existing.items ?? []).map((i) => ({
            genericProductId: i.genericProductId,
            description: i.description ?? "",
            quantity: Number(i.quantity) || 0,
            unitCost: Number(i.unitCost) || 0,
            discountAmount: Number(i.discountAmount) || 0,
            purchaseUnit: i.purchaseUnit ?? "",
            unitFactor: Number(i.unitFactor) || 1,
          })))
          // The saved project split, line by line.
          const lineIds = (existing.items ?? []).map((i) => i.genericPurchaseItemId).filter((x): x is number => !!x)
          if (lineIds.length === (existing.items ?? []).length) {
            const pr = await loadDocumentProjects("Purchase", editParam, lineIds)
            if (!cancelled) {
              setProjectId(pr.projectId)
              setRows((rs) => rs.map((r, k) => ({ ...r, projects: pr.lines[k] ?? null })))
            }
          }
        } else {
          const firstCash = as.find((a) => a.isActive)
          if (firstCash) setHeader((h) => ({ ...h, genericCashAccountId: String(firstCash.genericCashAccountId) }))
        }
      } catch (e: any) {
        if (!cancelled) toast({ title: "Could not load options", description: e?.message ?? String(e), variant: "destructive" })
      } finally { if (!cancelled) setLoading(false) }
    })()
    return () => { cancelled = true }
  }, [activeFarmType, router, toast])

  const selectedSupplier = useMemo(
    () => header.genericSupplierId ? suppliers.find((s) => String(s.genericSupplierId) === header.genericSupplierId) ?? null : null,
    [header.genericSupplierId, suppliers],
  )

  const totals = useMemo(() => {
    const subtotal = rows.reduce((s, r) => s + (r.quantity * r.unitCost - r.discountAmount), 0)
    const headerDisc = Number(header.headerDiscountAmount) || 0
    const tax = Number(header.taxAmount) || 0
    const total = subtotal - headerDisc + tax
    const paid = Number(header.amountPaid) || 0
    return { subtotal, headerDisc, tax, total, paid, balance: total - paid }
  }, [rows, header.headerDiscountAmount, header.taxAmount, header.amountPaid])

  // "Amount paid now" follows the total until the user types their own figure.
  // On credit (no cash account, or the Credit method) it stays 0.
  const paysNow = !!header.genericCashAccountId && header.paymentMethod !== "Credit"
  useEffect(() => {
    if (loading || paidTouched) return
    const next = String(paysNow ? Math.max(0, round2(totals.total)) : 0)
    setHeader((h) => (h.amountPaid === next ? h : { ...h, amountPaid: next }))
  }, [loading, paidTouched, paysNow, totals.total])

  const updateRow = (idx: number, patch: Partial<Row>) =>
    setRows((rs) => rs.map((r, i) => (i === idx ? { ...r, ...patch } : r)))

  const productOf = (r: Row) => products.find((x) => x.genericProductId === r.genericProductId)

  const onPickProduct = (idx: number, productId: string) => {
    const p = products.find((x) => x.genericProductId === Number(productId))
    if (!p) { updateRow(idx, { genericProductId: undefined, description: "", purchaseUnit: "", unitFactor: 1 }); return }
    // Start on the unit chosen in product setup: the purchase unit, else the base unit.
    // The buyer can switch to any other unit on the line.
    const opts = unitOptionsFor(p, conversions, companyUnits)
    const pick = opts.find((o) => p.purchaseUnit && same(o.unit, p.purchaseUnit)) ?? opts[0]
    const factor = pick.factor ?? 1
    updateRow(idx, {
      genericProductId: p.genericProductId,
      description: p.productName,
      purchaseUnit: pick.unit === opts[0].unit ? "" : pick.unit,
      unitFactor: factor,
      unitCost: p.costPrice > 0 ? round2(p.costPrice * factor) : rows[idx].unitCost,
    })
  }

  /** Switch a line's unit; the cost follows the product's base cost when it has one. */
  const onPickUnit = (idx: number, unit: string) => {
    const r = rows[idx]
    const p = productOf(r)
    const opts = unitOptionsFor(p, conversions, companyUnits)
    const o = opts.find((x) => x.unit === unit) ?? opts[0]
    const isBase = o.unit === opts[0].unit
    const factor = o.factor ?? 1
    updateRow(idx, {
      purchaseUnit: isBase ? "" : o.unit,
      unitFactor: factor,
      unitCost: p && p.costPrice > 0 ? round2(p.costPrice * factor) : r.unitCost,
    })
  }

  const unitCell = (r: Row, idx: number, h: string) => {
    const p = productOf(r)
    const opts = unitOptionsFor(p, conversions, companyUnits)
    const base = opts[0].unit
    const current = r.purchaseUnit || base
    const isBase = !r.purchaseUnit || same(r.purchaseUnit, base)
    // A saved unit no longer in setup still shows, so the line keeps its meaning.
    const shown = opts.some((o) => o.unit === current) ? opts : [...opts, { unit: current, factor: r.unitFactor }]
    return (
      <div className="space-y-1">
        <Select value={current} onValueChange={(v) => onPickUnit(idx, v)} disabled={!p}>
          <SelectTrigger className={h}><SelectValue placeholder="unit" /></SelectTrigger>
          <SelectContent>
            {shown.map((o) => (
              <SelectItem key={o.unit} value={o.unit}>
                {o.unit}{o.unit !== base && o.factor != null ? ` (= ${fmtQty(o.factor)} ${base})` : ""}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        {p && !isBase && (
          <div className={`flex items-center gap-1 text-[11px] whitespace-nowrap ${opts.find((o) => o.unit === current)?.factor == null ? "text-amber-700" : "text-slate-500"}`}
            title={opts.find((o) => o.unit === current)?.factor == null ? `Setup does not say how many ${base} are in one ${current}. Enter it so stock goes up by the right amount.` : undefined}>
            1 {current} =
            <NumberInput className="h-6 w-16 px-1 text-right text-[11px]" step="0.001" min="0" value={r.unitFactor}
              onChange={(e) => updateRow(idx, { unitFactor: Number(e.target.value) || 0 })} />
            {base}
          </div>
        )}
      </div>
    )
  }

  /** "10 bag x GHS 100 per bag -> 500 kg into stock" under a line. */
  const lineHint = (r: Row) => {
    const p = productOf(r)
    if (!p) return null
    const base = baseUnitOf(p)
    const unit = r.purchaseUnit || base
    const stockQty = r.quantity * (r.unitFactor || 0)
    return (
      <div className="text-[11px] text-slate-500 mt-1">
        {fmtQty(r.quantity)} {unit} × {fmt(r.unitCost)} per {unit}
        {p.trackInventory !== false && <> → <strong className="text-slate-700">{fmtQty(stockQty)} {base}</strong> into stock</>}
      </div>
    )
  }

  // Opened from a project's "Record purchase": go back to that project.
  const afterSave = () => {
    const from = typeof window !== "undefined" ? projectIdFromQuery(window.location.search) : null
    return from ? `/generic-projects/${from}?tab=inventory` : "/generic-inventory?tab=purchases"
  }

  const onSave = async (approve: boolean) => {
    const keptRows = rows.filter((r) => r.quantity > 0 && r.genericProductId)
    const items = keptRows
      .map((r) => ({
        genericProductId: r.genericProductId!,
        description: r.description || null,
        quantity: r.quantity,
        unitCost: r.unitCost,
        discountAmount: r.discountAmount,
        purchaseUnit: r.purchaseUnit || null,
        unitFactor: r.unitFactor > 0 ? r.unitFactor : 1,
      }))
    if (items.length === 0) {
      toast({ title: "Add at least one product line", variant: "destructive" })
      return
    }
    const badUnit = rows.find((r) => r.genericProductId && r.quantity > 0 && !(r.unitFactor > 0))
    if (badUnit) {
      toast({ title: "Say how many base units one purchase unit holds", description: `${badUnit.description}: fill in "1 ${badUnit.purchaseUnit} = ..." under the unit.`, variant: "destructive" })
      return
    }
    if (totals.balance > 0 && !header.genericSupplierId) {
      toast({ title: "Credit purchase requires a supplier", variant: "destructive" })
      return
    }
    setSaving(true)
    let savedId: number | null = editId
    try {
      const input = {
        purchaseDate: header.purchaseDate,
        genericSupplierId: header.genericSupplierId ? Number(header.genericSupplierId) : null,
        headerDiscountAmount: Number(header.headerDiscountAmount) || 0,
        taxAmount: Number(header.taxAmount) || 0,
        amountPaid: Number(header.amountPaid) || 0,
        paymentMethod: header.paymentMethod,
        genericCashAccountId: header.genericCashAccountId ? Number(header.genericCashAccountId) : null,
        invoiceNumber: header.invoiceNumber || null,
        notes: !header.genericSupplierId && header.supplierName.trim()
          ? (header.notes ? `Supplier: ${header.supplierName.trim()} | ${header.notes}` : `Supplier: ${header.supplierName.trim()}`)
          : (header.notes || null),
        items,
        // 483: saved in the same statement as the purchase (nothing sent when the module is off).
        projects: projectsEnabled ? buildAssignment(projectId, keptRows.map((r) => r.projects)) : undefined,
      }
      if (editId) {
        await updatePurchase(editId, input)
      } else {
        const created = await createPurchase(input)
        savedId = created?.genericPurchaseId ?? null
      }
    } catch (e: any) {
      toast({ title: editId ? "Could not save purchase" : "Could not create purchase", description: e?.message ?? String(e), variant: "destructive" })
      setSaving(false)
      return
    }
    if (!approve || !savedId) {
      toast({ title: `Purchase #${savedId ?? ""} saved as Draft`, description: "Review and approve to bump inventory and cash." })
      router.push(afterSave())
      return
    }
    try {
      await approvePurchase(savedId)
      toast({ title: `Purchase #${savedId} saved and approved`, description: "Stock and cash are updated." })
      router.push(afterSave())
    } catch (e: any) {
      // The purchase is saved; only the approval failed (e.g. not enough in the cash account).
      toast({ title: `Saved as Draft #${savedId}, but not approved`, description: e?.message ?? String(e), variant: "destructive" })
      if (!editId) {
        setEditId(savedId)
        window.history.replaceState(null, "", `/generic-purchases/new?edit=${savedId}`)
      }
      setSaving(false)
    }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <Link href="/generic-purchases" className="inline-flex items-center text-sm text-slate-500 hover:text-slate-700 mb-2">
            <ArrowLeft className="h-3 w-3 mr-1" /> Back to purchases
          </Link>
          <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2 mb-4">
            <Package className="h-6 w-6 text-orange-600" /> {editId ? `Edit purchase #${editId}` : "New purchase"}
            {editId && <span className="text-xs font-medium rounded bg-slate-100 text-slate-600 px-2 py-0.5">Draft</span>}
          </h1>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : (
            <div className="space-y-4">
              <Card>
                <CardContent className="grid grid-cols-1 md:grid-cols-4 gap-3 pt-6">
                  <div>
                    <Label>Purchase date</Label>
                    <Input type="date" value={header.purchaseDate} onChange={(e) => setHeader((h) => ({ ...h, purchaseDate: e.target.value }))} />
                  </div>
                  <div>
                    <Label>Supplier</Label>
                    <Select value={header.genericSupplierId || "__none__"} onValueChange={(v) => setHeader((h) => ({ ...h, genericSupplierId: v === "__none__" ? "" : v, supplierName: v !== "__none__" ? "" : h.supplierName }))}>
                      <SelectTrigger><SelectValue placeholder="— none —" /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="__none__">— none —</SelectItem>
                        {suppliers.map((s) => (
                          <SelectItem key={s.genericSupplierId} value={String(s.genericSupplierId)}>
                            <span className="flex items-center justify-between gap-2 w-full">
                              <span>{s.supplierName}</span>
                              {s.currentBalance > 0 && (
                                <span className="text-[10px] font-medium text-red-600 bg-red-50 px-1.5 py-0.5 rounded">owes {fmt(s.currentBalance)}</span>
                              )}
                            </span>
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    {!header.genericSupplierId && (
                      <Input
                        className="mt-1.5"
                        placeholder="Type supplier name (optional)"
                        value={header.supplierName}
                        onChange={(e) => setHeader((h) => ({ ...h, supplierName: e.target.value }))}
                      />
                    )}
                    {selectedSupplier && selectedSupplier.currentBalance > 0 && (
                      <div className="mt-1.5 flex items-center gap-2 rounded-md border border-red-200 bg-red-50 px-3 py-2">
                        <span className="text-xs text-red-800">
                          <strong>{selectedSupplier.supplierName}</strong> has an outstanding balance of <strong className="text-red-700">{fmt(selectedSupplier.currentBalance)}</strong>
                        </span>
                      </div>
                    )}
                    {selectedSupplier && selectedSupplier.currentBalance === 0 && (
                      <div className="mt-1.5 flex items-center gap-2 rounded-md border border-emerald-200 bg-emerald-50 px-3 py-2">
                        <span className="text-xs text-emerald-800">
                          <strong>{selectedSupplier.supplierName}</strong> — no outstanding balance
                        </span>
                      </div>
                    )}
                  </div>
                  <div>
                    <Label>Invoice number</Label>
                    <Input value={header.invoiceNumber} onChange={(e) => setHeader((h) => ({ ...h, invoiceNumber: e.target.value }))} maxLength={60} />
                  </div>
                  <RelatedProjectField value={projectId} onChange={setProjectId}
                    hint="Stock still goes into company inventory; it becomes this project's cost when sold or used." />
                </CardContent>
              </Card>

              <Card>
                <CardHeader className="flex flex-row items-center justify-between pb-2">
                  <CardTitle className="text-base">Items</CardTitle>
                  <Button size="sm" variant="outline" onClick={() => setRows((rs) => [...rs, blankRow()])}>
                    <Plus className="h-4 w-4 mr-1" /> Add row
                  </Button>
                </CardHeader>
                <CardContent className="p-0">
                  {/* Same responsive split as generic-sales/new: dense table
                      on lg+, two-column card-per-row on phones/tablets. */}
                  <div className="hidden lg:block">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Product</TableHead>
                          <TableHead className="w-[110px] text-right">Qty</TableHead>
                          <TableHead className="w-[170px]">Unit</TableHead>
                          <TableHead className="w-[130px] text-right">Cost per unit</TableHead>
                          <TableHead className="w-[130px] text-right">Discount</TableHead>
                          <TableHead className="w-[130px] text-right">Line total</TableHead>
                          <TableHead className="w-[40px]"></TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {rows.map((r, idx) => {
                          const line = r.quantity * r.unitCost - r.discountAmount
                          return (
                            <TableRow key={idx}>
                              <TableCell className="align-top">
                                <Select value={r.genericProductId ? String(r.genericProductId) : ""} onValueChange={(v) => onPickProduct(idx, v)}>
                                  <SelectTrigger className="h-8"><SelectValue placeholder="— select —" /></SelectTrigger>
                                  <SelectContent>
                                    {products.map((p) => (
                                      <SelectItem key={p.genericProductId} value={String(p.genericProductId)}>
                                        {p.productName}{p.sku ? ` (${p.sku})` : ""}
                                      </SelectItem>
                                    ))}
                                  </SelectContent>
                                </Select>
                                {lineHint(r)}
                                <LineProjectButton splits={r.projects} onChange={(p) => updateRow(idx, { projects: p })}
                                  headerProjectId={projectId} description={r.description || productOf(r)?.productName || ""}
                                  wholeQuantity={r.quantity} wholeAmount={r.quantity * r.unitCost - r.discountAmount}
                                  unit={r.purchaseUnit || baseUnitOf(productOf(r))} />
                              </TableCell>
                              <TableCell className="align-top"><NumberInput className="h-8 text-right"  step="0.001" min="0" value={r.quantity} onChange={(e) => updateRow(idx, { quantity: Number(e.target.value) || 0 })} /></TableCell>
                              <TableCell className="align-top">{unitCell(r, idx, "h-8")}</TableCell>
                              <TableCell className="align-top"><NumberInput className="h-8 text-right"  step="0.01" min="0" value={r.unitCost} onChange={(e) => updateRow(idx, { unitCost: Number(e.target.value) || 0 })} /></TableCell>
                              <TableCell className="align-top"><NumberInput className="h-8 text-right"  step="0.01" min="0" value={r.discountAmount} onChange={(e) => updateRow(idx, { discountAmount: Number(e.target.value) || 0 })} /></TableCell>
                              <TableCell className="align-top text-right font-semibold leading-8">{fmt(line)}</TableCell>
                              <TableCell className="align-top"><Button size="icon" variant="ghost" className="h-8 w-8" onClick={() => setRows((rs) => rs.filter((_, i) => i !== idx))}><X className="h-4 w-4 text-rose-600" /></Button></TableCell>
                            </TableRow>
                          )
                        })}
                      </TableBody>
                    </Table>
                  </div>

                  <div className="lg:hidden p-3 space-y-3">
                    {rows.map((r, idx) => {
                      const line = r.quantity * r.unitCost - r.discountAmount
                      return (
                        <div key={idx} className="rounded-lg border border-slate-200 bg-white p-3 space-y-3">
                          <div className="flex items-center gap-2">
                            <div className="flex-1 min-w-0">
                              <Select value={r.genericProductId ? String(r.genericProductId) : ""} onValueChange={(v) => onPickProduct(idx, v)}>
                                <SelectTrigger className="h-9"><SelectValue placeholder="— select product —" /></SelectTrigger>
                                <SelectContent>
                                  {products.map((p) => (
                                    <SelectItem key={p.genericProductId} value={String(p.genericProductId)}>
                                      {p.productName}{p.sku ? ` (${p.sku})` : ""}
                                    </SelectItem>
                                  ))}
                                </SelectContent>
                              </Select>
                              {lineHint(r)}
                              <LineProjectButton splits={r.projects} onChange={(p) => updateRow(idx, { projects: p })}
                                headerProjectId={projectId} description={r.description || productOf(r)?.productName || ""}
                                wholeQuantity={r.quantity} wholeAmount={r.quantity * r.unitCost - r.discountAmount}
                                unit={r.purchaseUnit || baseUnitOf(productOf(r))} />
                            </div>
                            <Button size="icon" variant="ghost" className="shrink-0" onClick={() => setRows((rs) => rs.filter((_, i) => i !== idx))}>
                              <X className="h-4 w-4 text-rose-600" />
                            </Button>
                          </div>
                          <div className="grid grid-cols-2 gap-2">
                            <div>
                              <label className="text-xs text-slate-500">Qty</label>
                              <NumberInput className="h-9 text-right tabular-nums" step="0.001" min="0" value={r.quantity} onChange={(e) => updateRow(idx, { quantity: Number(e.target.value) || 0 })} />
                            </div>
                            <div>
                              <label className="text-xs text-slate-500">Unit</label>
                              {unitCell(r, idx, "h-9")}
                            </div>
                            <div>
                              <label className="text-xs text-slate-500">Cost per {r.purchaseUnit || baseUnitOf(productOf(r))}</label>
                              <NumberInput className="h-9 text-right tabular-nums" step="0.01" min="0" value={r.unitCost} onChange={(e) => updateRow(idx, { unitCost: Number(e.target.value) || 0 })} />
                            </div>
                            <div>
                              <label className="text-xs text-slate-500">Discount</label>
                              <NumberInput className="h-9 text-right tabular-nums" step="0.01" min="0" value={r.discountAmount} onChange={(e) => updateRow(idx, { discountAmount: Number(e.target.value) || 0 })} />
                            </div>
                            <div>
                              <label className="text-xs text-slate-500">Line total</label>
                              <div className="h-9 flex items-center justify-end font-semibold tabular-nums pr-2">{fmt(line)}</div>
                            </div>
                          </div>
                        </div>
                      )
                    })}
                  </div>
                </CardContent>
              </Card>

              <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                <Card>
                  <CardHeader className="pb-2"><CardTitle className="text-base">Payment</CardTitle></CardHeader>
                  <CardContent className="grid grid-cols-2 gap-3">
                    <div><Label>Discount (header)</Label><NumberInput step="0.01" min="0" value={header.headerDiscountAmount} onChange={(e) => setHeader((h) => ({ ...h, headerDiscountAmount: e.target.value }))} /></div>
                    <div><Label>Tax</Label><NumberInput step="0.01" min="0" value={header.taxAmount} onChange={(e) => setHeader((h) => ({ ...h, taxAmount: e.target.value }))} /></div>
                    <div>
                      <Label>Amount paid now</Label>
                      <NumberInput step="0.01" min="0" value={header.amountPaid} onChange={(e) => { setPaidTouched(true); setHeader((h) => ({ ...h, amountPaid: e.target.value })) }} />
                      <p className="text-[11px] text-slate-500 mt-1">
                        {paidTouched
                          ? <>Your own figure. <button type="button" className="underline" onClick={() => setPaidTouched(false)}>Pay the full total</button></>
                          : paysNow ? "Fills in the full total; change it for a part payment." : "On credit: nothing paid now."}
                      </p>
                    </div>
                    <div>
                      <Label>Method</Label>
                      <Select value={header.paymentMethod} onValueChange={(v) => setHeader((h) => ({ ...h, paymentMethod: v }))}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>{PAY_METHODS.map((p) => <SelectItem key={p} value={p}>{p}</SelectItem>)}</SelectContent>
                      </Select>
                    </div>
                    <div className="col-span-2">
                      <Label>Cash account (paid from)</Label>
                      <Select value={header.genericCashAccountId || "__none__"} onValueChange={(v) => setHeader((h) => ({ ...h, genericCashAccountId: v === "__none__" ? "" : v }))}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="__none__">— none / credit —</SelectItem>
                          {cashAccounts.filter((a) => a.isActive).map((a) => (
                            <SelectItem key={a.genericCashAccountId} value={String(a.genericCashAccountId)}>{a.accountName} ({a.accountType})</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                    <div className="col-span-2">
                      <Label>Notes</Label>
                      <Textarea rows={2} value={header.notes} onChange={(e) => setHeader((h) => ({ ...h, notes: e.target.value }))} />
                    </div>
                  </CardContent>
                </Card>

                <Card>
                  <CardHeader className="pb-2"><CardTitle className="text-base">Totals</CardTitle></CardHeader>
                  <CardContent>
                    <dl className="space-y-1 text-sm">
                      <Row label="Subtotal" value={fmt(totals.subtotal)} />
                      <Row label="Header discount" value={fmt(totals.headerDisc)} />
                      <Row label="Tax" value={fmt(totals.tax)} />
                      <Row label="Total" value={fmt(totals.total)} bold />
                      <Row label="Paid now" value={fmt(totals.paid)} valueClass="text-emerald-700" />
                      <Row label="Balance owed to supplier" value={fmt(totals.balance)} valueClass={totals.balance > 0 ? "text-rose-700 font-bold" : ""} />
                    </dl>
                    <div className="flex justify-end gap-2 mt-4">
                      <Button variant="outline" onClick={() => router.push("/generic-purchases")}>Cancel</Button>
                      <Button variant="outline" onClick={() => onSave(false)} disabled={saving}>{saving && <Loader2 className="h-4 w-4 animate-spin mr-2" />}{editId ? "Save Draft" : "Save as Draft"}</Button>
                      <Button onClick={() => onSave(true)} disabled={saving} className="bg-emerald-600 hover:bg-emerald-700 text-white">
                        {saving ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <CheckCircle2 className="h-4 w-4 mr-2" />}Save &amp; Approve
                      </Button>
                    </div>
                  </CardContent>
                </Card>
              </div>
            </div>
          )}
        </main>
      </div>
    </div>
  )
}

function Row({ label, value, bold = false, valueClass = "" }: { label: string; value: string; bold?: boolean; valueClass?: string }) {
  return (
    <div className="flex justify-between">
      <dt className={bold ? "font-semibold" : "text-slate-600"}>{label}</dt>
      <dd className={`${bold ? "font-semibold" : ""} ${valueClass}`}>{value}</dd>
    </div>
  )
}
