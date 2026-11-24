"use client"

import { useEffect, useMemo, useState, useCallback } from "react"
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
import { ArrowLeft, Loader2, Plus, ShoppingCart, X, AlertTriangle, CreditCard, RotateCcw } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useGenericModules } from "@/hooks/use-generic-modules"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  createCustomer,
  createSale,
  getCashAccounts,
  getCustomers,
  getProducts,
  getSale,
  type GenericCashAccount,
  type GenericCustomer,
  type GenericProduct,
  type GenericSale,
  type GenericSaleItem,
} from "@/lib/api/generic"

/** Find or create a walk-in customer record so walk-in sales are tracked. */
async function resolveWalkInCustomer(
  name: string,
  existing: GenericCustomer[],
): Promise<{ id: number; customer: GenericCustomer | null }> {
  const trimmed = name.trim()
  const match = existing.find(
    (c) => c.customerName.toLowerCase() === trimmed.toLowerCase() && c.customerType === "Walk-in",
  )
  if (match) return { id: match.genericCustomerId, customer: match }
  const created = await createCustomer({
    customerName: trimmed,
    customerType: "Walk-in",
    creditLimit: 0,
    paymentTermsDays: 0,
    openingBalance: 0,
    isActive: true,
    notes: "Auto-created from walk-in sale",
  })
  return { id: created?.genericCustomerId ?? 0, customer: created }
}

const SALES_TYPES = [
  "WalkInSale", "CustomerSale", "ProductSale", "ServiceSale", "MixedSale",
  "CreditSale", "OnlineSale", "DeliverySale", "WholesaleSale", "RetailSale",
]
const PAY_METHODS = ["Cash", "MoMo", "Bank", "Card", "Mixed", "Credit"]

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}

type Row = {
  itemType: "Product" | "Service"
  genericProductId?: number
  description: string
  quantity: number
  unitPrice: number
  discountAmount: number
  saleUnit: string
  unitFactor: number
}

const blankRow = (): Row => ({
  itemType: "Product",
  genericProductId: undefined,
  description: "",
  quantity: 1,
  unitPrice: 0,
  discountAmount: 0,
  saleUnit: "",
  unitFactor: 1,
})

export default function NewGenericSalePage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const modules = useGenericModules()
  const logout = useLogout()
  const { toast } = useToast()

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [customers, setCustomers] = useState<GenericCustomer[]>([])
  const [products, setProducts] = useState<GenericProduct[]>([])
  const [cashAccounts, setCashAccounts] = useState<GenericCashAccount[]>([])

  const [header, setHeader] = useState(() => {
    const now = new Date()
    const date = now.toISOString().slice(0, 10)
    const pad = String(now.getHours()).padStart(2, "0") + String(now.getMinutes()).padStart(2, "0")
    const rand = String(Math.floor(Math.random() * 10000)).padStart(4, "0")
    return {
    saleDate: date,
    genericCustomerId: "",
    salesType: "WalkInSale",
    receiptNumber: `SAL-${date.replace(/-/g, "")}-${pad}${rand}`,
    headerDiscountAmount: "0",
    taxAmount: "0",
    amountPaid: "",
    paymentMethod: "Cash",
    genericCashAccountId: "",
    notes: "",
    applyCreditAmount: "0",
  }})

  // Track whether user has manually edited amountPaid
  const [amountPaidTouched, setAmountPaidTouched] = useState(false)

  const [walkInName, setWalkInName] = useState("")
  const [rows, setRows] = useState<Row[]>([blankRow()])
  // 485: Correct sale / Edit & repost -- /generic-sales/new?corrects=<reversed sale>
  // opens this form filled in from that sale; saving links the two.
  const [corrects, setCorrects] = useState<GenericSale | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    let cancelled = false
    ;(async () => {
      try {
        const [cs, ps, as_] = await Promise.all([getCustomers(), getProducts(), getCashAccounts()])
        if (cancelled) return
        setCustomers(cs)
        setProducts(ps.filter((p) => p.canSell === true || (p.canSell == null && p.itemType !== "SupplyItem")))
        setCashAccounts(as_)
        const defaultId = modules.businessSettings?.defaultCashAccountForPayments
        const defaultAccount = defaultId ? as_.find((a) => a.genericCashAccountId === defaultId && a.isActive) : null
        const firstCash = defaultAccount ?? as_.find((a) => a.isActive)
        if (firstCash) setHeader((h) => ({ ...h, genericCashAccountId: String(firstCash.genericCashAccountId) }))

        const correctsId = Number(new URLSearchParams(window.location.search).get("corrects"))
        if (Number.isFinite(correctsId) && correctsId > 0) {
          const old = await getSale(correctsId)
          if (cancelled) return
          if (old) {
            setCorrects(old)
            const lineDiscounts = (old.items ?? []).reduce((n, i) => n + (Number(i.discountAmount) || 0), 0)
            setHeader((h) => ({
              ...h,
              saleDate: (old.saleDate || h.saleDate).slice(0, 10),
              genericCustomerId: old.genericCustomerId ? String(old.genericCustomerId) : "",
              salesType: old.salesType || h.salesType,
              headerDiscountAmount: String(Math.max(0, (Number(old.discountAmount) || 0) - lineDiscounts)),
              taxAmount: String(Number(old.taxAmount) || 0),
              paymentMethod: old.paymentMethod || h.paymentMethod,
              notes: old.notes ?? "",
              // Nothing is taken as paid: money from the reversed sale was paid
              // back or kept as the customer's credit, which is applied below.
              amountPaid: "0",
            }))
            setAmountPaidTouched(true)
            if (old.items?.length) {
              setRows(old.items.map((i) => ({
                itemType: i.itemType === "Service" ? "Service" : "Product",
                genericProductId: i.genericProductId ?? undefined,
                description: i.description ?? "",
                quantity: Number(i.quantity) || 0,
                unitPrice: Number(i.unitPrice) || 0,
                discountAmount: Number(i.discountAmount) || 0,
                saleUnit: i.saleUnit ?? "",
                unitFactor: Number(i.unitFactor) || 1,
              })))
            }
          } else {
            toast({ title: `Sale #${correctsId} was not found`, description: "Enter the sale from scratch.", variant: "destructive" })
          }
        }
      } catch (e: any) {
        if (!cancelled) toast({ title: "Could not load options", description: e?.message ?? String(e), variant: "destructive" })
      } finally { if (!cancelled) setLoading(false) }
    })()
    return () => { cancelled = true }
  }, [activeFarmType, router, toast])

  const totals = useMemo(() => {
    const subtotal = rows.reduce((s, r) => s + (r.quantity * r.unitPrice - r.discountAmount), 0)
    const headerDisc = Number(header.headerDiscountAmount) || 0
    const tax = Number(header.taxAmount) || 0
    const total = subtotal - headerDisc + tax
    const creditApplied = Number(header.applyCreditAmount) || 0
    const paid = Number(header.amountPaid) || 0
    const balance = total - paid - creditApplied
    const overpayment = paid > total - creditApplied ? paid - (total - creditApplied) : 0
    return { subtotal, headerDisc, tax, total, paid, creditApplied, balance, overpayment }
  }, [rows, header.headerDiscountAmount, header.taxAmount, header.amountPaid, header.applyCreditAmount])

  // Auto-fill amountPaid with invoice total when untouched
  useEffect(() => {
    if (!amountPaidTouched) {
      const totalAfterCredit = Math.max(totals.total - totals.creditApplied, 0)
      setHeader((h) => ({ ...h, amountPaid: totalAfterCredit > 0 ? String(totalAfterCredit) : "0" }))
    }
  }, [totals.total, totals.creditApplied, amountPaidTouched])

  // Customer credit available
  const selectedCustomer = useMemo(() => {
    if (!header.genericCustomerId) return null
    return customers.find((c) => c.genericCustomerId === Number(header.genericCustomerId)) ?? null
  }, [header.genericCustomerId, customers])

  const customerCreditAvailable = useMemo(() => {
    if (!selectedCustomer) return 0
    return selectedCustomer.currentBalance < 0 ? Math.abs(selectedCustomer.currentBalance) : 0
  }, [selectedCustomer])

  const updateRow = (idx: number, patch: Partial<Row>) =>
    setRows((rs) => rs.map((r, i) => (i === idx ? { ...r, ...patch } : r)))

  const onPickProduct = (idx: number, productId: string) => {
    const p = products.find((x) => x.genericProductId === Number(productId))
    if (!p) {
      updateRow(idx, { genericProductId: undefined, description: "", saleUnit: "", unitFactor: 1 })
      return
    }
    updateRow(idx, {
      genericProductId: p.genericProductId,
      description: p.productName,
      unitPrice: p.sellingPrice > 0 ? p.sellingPrice : rows[idx].unitPrice,
      saleUnit: p.salesUnit || p.unitOfMeasure || "",
      unitFactor: 1,
    })
  }

  // Build unit options for a product: base unit + salesUnit if different
  const getUnitOptions = useCallback((row: Row) => {
    if (row.itemType !== "Product" || !row.genericProductId) return []
    const p = products.find((x) => x.genericProductId === row.genericProductId)
    if (!p) return []
    const opts: { label: string; unit: string; factor: number; price: number }[] = []
    const baseUnit = p.unitOfMeasure || "unit"
    opts.push({ label: baseUnit, unit: baseUnit, factor: 1, price: p.sellingPrice })
    if (p.salesUnit && p.salesUnit !== baseUnit) {
      // salesUnit is typically the customer-facing unit
      opts.push({ label: p.salesUnit, unit: p.salesUnit, factor: 1, price: p.sellingPrice })
    }
    if (p.purchaseUnit && p.purchaseUnit !== baseUnit && p.purchaseUnit !== p.salesUnit) {
      // purchaseUnit is a bulk unit — no default factor available, user must set
      opts.push({ label: p.purchaseUnit, unit: p.purchaseUnit, factor: 1, price: p.sellingPrice })
    }
    return opts
  }, [products])

  const onSave = async () => {
    // Overpayment requires a named customer
    if (totals.overpayment > 0 && !header.genericCustomerId && !walkInName.trim()) {
      toast({
        title: "Customer required for overpayment",
        description: `${fmt(totals.overpayment)} will be saved as customer credit. Please select or enter a customer.`,
        variant: "destructive",
      })
      return
    }

    // Credit application requires a customer
    if (totals.creditApplied > 0 && !header.genericCustomerId) {
      toast({ title: "Customer required for credit application", variant: "destructive" })
      return
    }

    const items: GenericSaleItem[] = rows
      .filter((r) => r.quantity > 0 && (r.itemType === "Service" || r.genericProductId))
      .map((r) => ({
        itemType: r.itemType,
        genericProductId: r.itemType === "Product" ? r.genericProductId : null,
        genericServiceId: null,
        description: r.description || null,
        quantity: r.quantity,
        unitPrice: r.unitPrice,
        discountAmount: r.discountAmount,
        saleUnit: r.saleUnit || null,
        unitFactor: r.unitFactor,
      }))

    if (items.length === 0) {
      toast({ title: "Add at least one item", variant: "destructive" })
      return
    }

    // Overpayment confirmation
    if (totals.overpayment > 0) {
      const customerName = selectedCustomer?.customerName || walkInName.trim()
      if (!confirm(`${fmt(totals.overpayment)} will be saved as customer credit for ${customerName}. Continue?`)) {
        return
      }
    }

    setSaving(true)
    try {
      let resolvedCustomerId = header.genericCustomerId ? Number(header.genericCustomerId) : null
      if (!header.genericCustomerId && walkInName.trim()) {
        const { id, customer } = await resolveWalkInCustomer(walkInName, customers)
        if (id) {
          resolvedCustomerId = id
          if (customer && !customers.some((c) => c.genericCustomerId === id)) {
            setCustomers((prev) => [...prev, customer])
          }
        }
      }

      const created = await createSale({
        saleDate: header.saleDate,
        genericCustomerId: resolvedCustomerId,
        salesType: header.salesType,
        salesChannel: null,
        headerDiscountAmount: Number(header.headerDiscountAmount) || 0,
        taxAmount: Number(header.taxAmount) || 0,
        amountPaid: Number(header.amountPaid) || 0,
        paymentMethod: header.paymentMethod,
        genericCashAccountId: header.genericCashAccountId ? Number(header.genericCashAccountId) : null,
        receiptNumber: header.receiptNumber || null,
        notes: header.notes || null,
        applyCreditAmount: Number(header.applyCreditAmount) || 0,
        items,
        correctsSaleId: corrects?.genericSaleId ?? null,
      })
      if (created) {
        toast({
          title: `Sale #${created.genericSaleId} created as Draft`,
          description: corrects
            ? `It replaces reversed sale #${corrects.genericSaleId}. Review and approve to commit it.`
            : "Review and approve to commit it.",
        })
        router.push(`/generic-sales/${created.genericSaleId}`)
      }
    } catch (e: any) {
      toast({ title: "Could not create sale", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <Link href="/generic-sales" className="inline-flex items-center text-sm text-slate-500 hover:text-slate-700 mb-2">
            <ArrowLeft className="h-3 w-3 mr-1" /> Back to sales
          </Link>
          <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2 mb-4">
            {corrects
              ? <><RotateCcw className="h-6 w-6 text-blue-600" /> Correct sale #{corrects.genericSaleId}</>
              : <><ShoppingCart className="h-6 w-6 text-emerald-600" /> New sale</>}
          </h1>
          {corrects && (
            <div className="mb-4 rounded-md border border-blue-200 bg-blue-50 px-3 py-2 text-sm text-blue-900">
              Sale #{corrects.genericSaleId} was reversed. It is filled in below: fix what was wrong and save.
              The new sale is linked to it.
              {(Number(corrects.amountPaid) || 0) > 0 && " Money the customer paid and kept as credit can be applied with \"Apply credit\"."}
            </div>
          )}

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : (
            <div className="space-y-4">
              {/* Header */}
              <Card>
                <CardContent className="grid grid-cols-1 md:grid-cols-4 gap-3 pt-6">
                  <div>
                    <Label>Sale date</Label>
                    <Input type="date" value={header.saleDate} onChange={(e) => setHeader((h) => ({ ...h, saleDate: e.target.value }))} />
                  </div>
                  <div>
                    <Label>Sales type</Label>
                    <Select value={header.salesType} onValueChange={(v) => setHeader((h) => ({ ...h, salesType: v }))}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>{SALES_TYPES.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent>
                    </Select>
                  </div>
                  <div>
                    <Label>Customer (optional)</Label>
                    <Select value={header.genericCustomerId || "__walk_in__"} onValueChange={(v) => {
                      setHeader((h) => ({ ...h, genericCustomerId: v === "__walk_in__" ? "" : v, applyCreditAmount: "0" }))
                      if (v !== "__walk_in__") setWalkInName("")
                    }}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="__walk_in__">— Walk-in —</SelectItem>
                        {customers.map((c) => (
                          <SelectItem key={c.genericCustomerId} value={String(c.genericCustomerId)}>
                            {c.customerName}
                            {c.currentBalance < 0 ? ` (${fmt(Math.abs(c.currentBalance))} credit)` : ""}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    {!header.genericCustomerId && (
                      <Input className="mt-1.5" placeholder="Walk-in customer name (optional)" value={walkInName} onChange={(e) => setWalkInName(e.target.value)} />
                    )}
                  </div>
                  <div>
                    <Label>Receipt no.</Label>
                    <Input value={header.receiptNumber} onChange={(e) => setHeader((h) => ({ ...h, receiptNumber: e.target.value }))} maxLength={60} />
                  </div>
                </CardContent>
              </Card>

              {/* Items */}
              <Card>
                <CardHeader className="flex flex-row items-center justify-between pb-2">
                  <CardTitle className="text-base">Items</CardTitle>
                  <Button size="sm" variant="outline" onClick={() => setRows((rs) => [...rs, blankRow()])}>
                    <Plus className="h-4 w-4 mr-1" /> Add row
                  </Button>
                </CardHeader>
                <CardContent className="p-0">
                  {/* Desktop table */}
                  <div className="hidden lg:block">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead className="w-[110px]">Type</TableHead>
                          <TableHead>Product</TableHead>
                          <TableHead className="w-[100px]">Unit</TableHead>
                          <TableHead className="w-[80px] text-right">Factor</TableHead>
                          <TableHead className="w-[90px] text-right">Qty</TableHead>
                          <TableHead className="w-[120px] text-right">Unit price</TableHead>
                          <TableHead className="w-[110px] text-right">Discount</TableHead>
                          <TableHead className="w-[120px] text-right">Line total</TableHead>
                          <TableHead className="w-[40px]"></TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {rows.map((r, idx) => {
                          const line = r.quantity * r.unitPrice - r.discountAmount
                          const unitOpts = getUnitOptions(r)
                          return (
                            <TableRow key={idx}>
                              <TableCell>
                                <Select value={r.itemType} onValueChange={(v) => updateRow(idx, { itemType: v as "Product" | "Service" })}>
                                  <SelectTrigger className="h-8"><SelectValue /></SelectTrigger>
                                  <SelectContent>
                                    <SelectItem value="Product">Product</SelectItem>
                                    <SelectItem value="Service">Service</SelectItem>
                                  </SelectContent>
                                </Select>
                              </TableCell>
                              <TableCell>
                                {r.itemType === "Product" ? (
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
                                ) : (
                                  <Input className="h-8" value={r.description} onChange={(e) => updateRow(idx, { description: e.target.value })} placeholder="Service description" />
                                )}
                              </TableCell>
                              <TableCell>
                                {r.itemType === "Product" && unitOpts.length > 0 ? (
                                  <Select value={r.saleUnit || unitOpts[0]?.unit || ""} onValueChange={(v) => {
                                    const opt = unitOpts.find((o) => o.unit === v)
                                    updateRow(idx, { saleUnit: v, unitFactor: opt?.factor ?? 1, unitPrice: opt?.price ?? r.unitPrice })
                                  }}>
                                    <SelectTrigger className="h-8"><SelectValue /></SelectTrigger>
                                    <SelectContent>
                                      {unitOpts.map((o) => <SelectItem key={o.unit} value={o.unit}>{o.label}</SelectItem>)}
                                    </SelectContent>
                                  </Select>
                                ) : <span className="text-xs text-slate-400">—</span>}
                              </TableCell>
                              <TableCell>
                                {r.itemType === "Product" ? (
                                  <NumberInput className="h-8 text-right" step="0.01" min="0.0001" value={r.unitFactor} onChange={(e) => updateRow(idx, { unitFactor: Number(e.target.value) || 1 })} />
                                ) : <span className="text-xs text-slate-400">—</span>}
                              </TableCell>
                              <TableCell><NumberInput className="h-8 text-right" step="0.001" min="0" value={r.quantity} onChange={(e) => updateRow(idx, { quantity: Number(e.target.value) || 0 })} /></TableCell>
                              <TableCell><NumberInput className="h-8 text-right" step="0.01" min="0" value={r.unitPrice} onChange={(e) => updateRow(idx, { unitPrice: Number(e.target.value) || 0 })} /></TableCell>
                              <TableCell><NumberInput className="h-8 text-right" step="0.01" min="0" value={r.discountAmount} onChange={(e) => updateRow(idx, { discountAmount: Number(e.target.value) || 0 })} /></TableCell>
                              <TableCell className="text-right font-semibold">{fmt(line)}</TableCell>
                              <TableCell>
                                <Button size="icon" variant="ghost" onClick={() => setRows((rs) => rs.filter((_, i) => i !== idx))}>
                                  <X className="h-4 w-4 text-rose-600" />
                                </Button>
                              </TableCell>
                            </TableRow>
                          )
                        })}
                      </TableBody>
                    </Table>
                  </div>

                  {/* Mobile card stack */}
                  <div className="lg:hidden p-3 space-y-3">
                    {rows.map((r, idx) => {
                      const line = r.quantity * r.unitPrice - r.discountAmount
                      const unitOpts = getUnitOptions(r)
                      return (
                        <div key={idx} className="rounded-lg border border-slate-200 bg-white p-3 space-y-3">
                          <div className="flex items-center gap-2">
                            <Select value={r.itemType} onValueChange={(v) => updateRow(idx, { itemType: v as "Product" | "Service" })}>
                              <SelectTrigger className="h-9 w-28 shrink-0"><SelectValue /></SelectTrigger>
                              <SelectContent>
                                <SelectItem value="Product">Product</SelectItem>
                                <SelectItem value="Service">Service</SelectItem>
                              </SelectContent>
                            </Select>
                            <div className="flex-1 min-w-0">
                              {r.itemType === "Product" ? (
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
                              ) : (
                                <Input className="h-9" value={r.description} onChange={(e) => updateRow(idx, { description: e.target.value })} placeholder="Service description" />
                              )}
                            </div>
                            <Button size="icon" variant="ghost" className="shrink-0" onClick={() => setRows((rs) => rs.filter((_, i) => i !== idx))}>
                              <X className="h-4 w-4 text-rose-600" />
                            </Button>
                          </div>
                          {r.itemType === "Product" && unitOpts.length > 0 && (
                            <div className="grid grid-cols-2 gap-2">
                              <div>
                                <label className="text-xs text-slate-500">Sale unit</label>
                                <Select value={r.saleUnit || unitOpts[0]?.unit || ""} onValueChange={(v) => {
                                  const opt = unitOpts.find((o) => o.unit === v)
                                  updateRow(idx, { saleUnit: v, unitFactor: opt?.factor ?? 1, unitPrice: opt?.price ?? r.unitPrice })
                                }}>
                                  <SelectTrigger className="h-9"><SelectValue /></SelectTrigger>
                                  <SelectContent>
                                    {unitOpts.map((o) => <SelectItem key={o.unit} value={o.unit}>{o.label}</SelectItem>)}
                                  </SelectContent>
                                </Select>
                              </div>
                              <div>
                                <label className="text-xs text-slate-500">Factor (units per sale unit)</label>
                                <NumberInput className="h-9 text-right tabular-nums" step="0.01" min="0.0001" value={r.unitFactor} onChange={(e) => updateRow(idx, { unitFactor: Number(e.target.value) || 1 })} />
                              </div>
                            </div>
                          )}
                          <div className="grid grid-cols-2 gap-2">
                            <div>
                              <label className="text-xs text-slate-500">Qty</label>
                              <NumberInput className="h-9 text-right tabular-nums" step="0.001" min="0" value={r.quantity} onChange={(e) => updateRow(idx, { quantity: Number(e.target.value) || 0 })} />
                            </div>
                            <div>
                              <label className="text-xs text-slate-500">Unit price</label>
                              <NumberInput className="h-9 text-right tabular-nums" step="0.01" min="0" value={r.unitPrice} onChange={(e) => updateRow(idx, { unitPrice: Number(e.target.value) || 0 })} />
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

              {/* Payment + totals */}
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                <Card>
                  <CardHeader className="pb-2"><CardTitle className="text-base">Payment</CardTitle></CardHeader>
                  <CardContent className="grid grid-cols-2 gap-3">
                    <div>
                      <Label>Discount (header)</Label>
                      <NumberInput step="0.01" min="0" value={header.headerDiscountAmount} onChange={(e) => setHeader((h) => ({ ...h, headerDiscountAmount: e.target.value }))} />
                    </div>
                    <div>
                      <Label>Tax</Label>
                      <NumberInput step="0.01" min="0" value={header.taxAmount} onChange={(e) => setHeader((h) => ({ ...h, taxAmount: e.target.value }))} />
                    </div>

                    {/* Customer credit section */}
                    {customerCreditAvailable > 0 && (
                      <div className="col-span-2 rounded-md border border-emerald-200 bg-emerald-50 p-3">
                        <div className="flex items-center gap-2 mb-2">
                          <CreditCard className="h-4 w-4 text-emerald-600" />
                          <span className="text-sm font-medium text-emerald-800">
                            {selectedCustomer?.customerName} has {fmt(customerCreditAvailable)} credit available
                          </span>
                        </div>
                        <div className="flex items-center gap-2">
                          <Label className="text-sm text-emerald-700 whitespace-nowrap">Apply credit</Label>
                          <NumberInput
                            className="h-8 w-32"
                            step="0.01" min="0"
                            max={Math.min(customerCreditAvailable, totals.total)}
                            value={header.applyCreditAmount}
                            onChange={(e) => {
                              const val = Math.min(Number(e.target.value) || 0, customerCreditAvailable, totals.total)
                              setHeader((h) => ({ ...h, applyCreditAmount: String(val) }))
                            }}
                          />
                          <Button size="sm" variant="outline" className="h-8 text-xs"
                            onClick={() => {
                              const max = Math.min(customerCreditAvailable, totals.total)
                              setHeader((h) => ({ ...h, applyCreditAmount: String(max) }))
                            }}>
                            Apply max
                          </Button>
                        </div>
                      </div>
                    )}

                    <div>
                      <Label>Amount paid</Label>
                      <NumberInput step="0.01" min="0"
                        value={header.amountPaid}
                        onChange={(e) => {
                          setAmountPaidTouched(true)
                          setHeader((h) => ({ ...h, amountPaid: e.target.value }))
                        }}
                      />
                    </div>
                    <div>
                      <Label>Method</Label>
                      <Select value={header.paymentMethod} onValueChange={(v) => setHeader((h) => ({ ...h, paymentMethod: v }))}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>{PAY_METHODS.map((p) => <SelectItem key={p} value={p}>{p}</SelectItem>)}</SelectContent>
                      </Select>
                    </div>
                    <div className="col-span-2">
                      <Label>Cash account (receives payment)</Label>
                      <Select value={header.genericCashAccountId || "__none__"} onValueChange={(v) => setHeader((h) => ({ ...h, genericCashAccountId: v === "__none__" ? "" : v }))}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="__none__">— none / credit sale —</SelectItem>
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
                      <SummaryRow label="Subtotal" value={fmt(totals.subtotal)} />
                      <SummaryRow label="Header discount" value={fmt(totals.headerDisc)} />
                      <SummaryRow label="Tax" value={fmt(totals.tax)} />
                      <SummaryRow label="Total" value={fmt(totals.total)} bold />
                      {totals.creditApplied > 0 && (
                        <SummaryRow label="Credit applied" value={`-${fmt(totals.creditApplied)}`} valueClass="text-emerald-700" />
                      )}
                      <SummaryRow label="Paid (cash)" value={fmt(totals.paid)} valueClass="text-emerald-700" />
                      <SummaryRow label="Balance" value={fmt(Math.max(totals.balance, 0))} valueClass={totals.balance > 0 ? "text-rose-700 font-bold" : ""} />
                    </dl>

                    {/* Overpayment warning */}
                    {totals.overpayment > 0 && (
                      <div className="mt-3 rounded-md border border-amber-300 bg-amber-50 p-3 flex items-start gap-2">
                        <AlertTriangle className="h-4 w-4 text-amber-600 mt-0.5 shrink-0" />
                        <p className="text-sm text-amber-800">
                          <strong>{fmt(totals.overpayment)}</strong> will be saved as customer credit
                          {selectedCustomer ? ` for ${selectedCustomer.customerName}` : ""}.
                          {!header.genericCustomerId && !walkInName.trim() && (
                            <span className="block mt-1 text-rose-600 font-medium">
                              Select or enter a customer to save overpayment as credit.
                            </span>
                          )}
                        </p>
                      </div>
                    )}

                    <div className="flex justify-end gap-2 mt-4">
                      <Button variant="outline" onClick={() => router.push("/generic-sales")}>Cancel</Button>
                      <Button onClick={onSave} disabled={saving}>
                        {saving && <Loader2 className="h-4 w-4 animate-spin mr-2" />}
                        Create as Draft
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

function SummaryRow({ label, value, bold = false, valueClass = "" }: { label: string; value: string; bold?: boolean; valueClass?: string }) {
  return (
    <div className="flex justify-between">
      <dt className={bold ? "font-semibold" : "text-slate-600"}>{label}</dt>
      <dd className={`${bold ? "font-semibold" : ""} ${valueClass}`}>{value}</dd>
    </div>
  )
}
