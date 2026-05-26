"use client"

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ArrowLeft, Loader2, Plus, ShoppingCart, X } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  createSale,
  getCashAccounts,
  getCustomers,
  getProducts,
  type GenericCashAccount,
  type GenericCustomer,
  type GenericProduct,
  type GenericSaleItem,
} from "@/lib/api/generic"

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
}

const blankRow = (): Row => ({
  itemType: "Product",
  genericProductId: undefined,
  description: "",
  quantity: 1,
  unitPrice: 0,
  discountAmount: 0,
})

export default function NewGenericSalePage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [customers, setCustomers] = useState<GenericCustomer[]>([])
  const [products, setProducts] = useState<GenericProduct[]>([])
  const [cashAccounts, setCashAccounts] = useState<GenericCashAccount[]>([])

  const [header, setHeader] = useState({
    saleDate: new Date().toISOString().slice(0, 10),
    genericCustomerId: "",
    salesType: "WalkInSale",
    receiptNumber: "",
    headerDiscountAmount: "0",
    taxAmount: "0",
    amountPaid: "0",
    paymentMethod: "Cash",
    genericCashAccountId: "",
    notes: "",
  })

  const [rows, setRows] = useState<Row[]>([blankRow()])

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    let cancelled = false
    ;(async () => {
      try {
        const [cs, ps, as] = await Promise.all([getCustomers(), getProducts(), getCashAccounts()])
        if (cancelled) return
        setCustomers(cs)
        setProducts(ps)
        setCashAccounts(as)
        // Default to first active cash account
        const firstCash = as.find((a) => a.isActive)
        if (firstCash) setHeader((h) => ({ ...h, genericCashAccountId: String(firstCash.genericCashAccountId) }))
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
    const paid = Number(header.amountPaid) || 0
    return { subtotal, headerDisc, tax, total, paid, balance: total - paid }
  }, [rows, header.headerDiscountAmount, header.taxAmount, header.amountPaid])

  const updateRow = (idx: number, patch: Partial<Row>) =>
    setRows((rs) => rs.map((r, i) => (i === idx ? { ...r, ...patch } : r)))

  const onPickProduct = (idx: number, productId: string) => {
    const p = products.find((x) => x.genericProductId === Number(productId))
    if (!p) {
      updateRow(idx, { genericProductId: undefined, description: "" })
      return
    }
    updateRow(idx, {
      genericProductId: p.genericProductId,
      description: p.productName,
      unitPrice: p.sellingPrice > 0 ? p.sellingPrice : rows[idx].unitPrice,
    })
  }

  const onSave = async () => {
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
      }))

    if (items.length === 0) {
      toast({ title: "Add at least one item", variant: "destructive" })
      return
    }

    setSaving(true)
    try {
      const created = await createSale({
        saleDate: header.saleDate,
        genericCustomerId: header.genericCustomerId ? Number(header.genericCustomerId) : null,
        salesType: header.salesType,
        salesChannel: null,
        headerDiscountAmount: Number(header.headerDiscountAmount) || 0,
        taxAmount: Number(header.taxAmount) || 0,
        amountPaid: Number(header.amountPaid) || 0,
        paymentMethod: header.paymentMethod,
        genericCashAccountId: header.genericCashAccountId ? Number(header.genericCashAccountId) : null,
        receiptNumber: header.receiptNumber || null,
        notes: header.notes || null,
        items,
      })
      if (created) {
        toast({ title: `Sale #${created.genericSaleId} created as Draft`, description: "Review and approve to commit it." })
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
            <ShoppingCart className="h-6 w-6 text-emerald-600" /> New sale
          </h1>

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
                    <Select value={header.genericCustomerId || "__walk_in__"} onValueChange={(v) => setHeader((h) => ({ ...h, genericCustomerId: v === "__walk_in__" ? "" : v }))}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="__walk_in__">— Walk-in —</SelectItem>
                        {customers.map((c) => (
                          <SelectItem key={c.genericCustomerId} value={String(c.genericCustomerId)}>{c.customerName}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
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
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead className="w-[110px]">Type</TableHead>
                        <TableHead>Product</TableHead>
                        <TableHead className="w-[110px] text-right">Qty</TableHead>
                        <TableHead className="w-[130px] text-right">Unit price</TableHead>
                        <TableHead className="w-[130px] text-right">Discount</TableHead>
                        <TableHead className="w-[130px] text-right">Line total</TableHead>
                        <TableHead className="w-[40px]"></TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {rows.map((r, idx) => {
                        const line = r.quantity * r.unitPrice - r.discountAmount
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
                            <TableCell><Input className="h-8 text-right" type="number" step="0.001" min="0" value={r.quantity} onChange={(e) => updateRow(idx, { quantity: Number(e.target.value) || 0 })} /></TableCell>
                            <TableCell><Input className="h-8 text-right" type="number" step="0.01" min="0" value={r.unitPrice} onChange={(e) => updateRow(idx, { unitPrice: Number(e.target.value) || 0 })} /></TableCell>
                            <TableCell><Input className="h-8 text-right" type="number" step="0.01" min="0" value={r.discountAmount} onChange={(e) => updateRow(idx, { discountAmount: Number(e.target.value) || 0 })} /></TableCell>
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
                </CardContent>
              </Card>

              {/* Payment + totals */}
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                <Card>
                  <CardHeader className="pb-2"><CardTitle className="text-base">Payment</CardTitle></CardHeader>
                  <CardContent className="grid grid-cols-2 gap-3">
                    <div>
                      <Label>Discount (header)</Label>
                      <Input type="number" step="0.01" min="0" value={header.headerDiscountAmount} onChange={(e) => setHeader((h) => ({ ...h, headerDiscountAmount: e.target.value }))} />
                    </div>
                    <div>
                      <Label>Tax</Label>
                      <Input type="number" step="0.01" min="0" value={header.taxAmount} onChange={(e) => setHeader((h) => ({ ...h, taxAmount: e.target.value }))} />
                    </div>
                    <div>
                      <Label>Amount paid</Label>
                      <Input type="number" step="0.01" min="0" value={header.amountPaid} onChange={(e) => setHeader((h) => ({ ...h, amountPaid: e.target.value }))} />
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
                      <Row label="Subtotal" value={fmt(totals.subtotal)} />
                      <Row label="Header discount" value={fmt(totals.headerDisc)} />
                      <Row label="Tax" value={fmt(totals.tax)} />
                      <Row label="Total" value={fmt(totals.total)} bold />
                      <Row label="Paid" value={fmt(totals.paid)} valueClass="text-emerald-700" />
                      <Row label="Balance" value={fmt(totals.balance)} valueClass={totals.balance > 0 ? "text-rose-700 font-bold" : ""} />
                    </dl>
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

function Row({ label, value, bold = false, valueClass = "" }: { label: string; value: string; bold?: boolean; valueClass?: string }) {
  return (
    <div className="flex justify-between">
      <dt className={bold ? "font-semibold" : "text-slate-600"}>{label}</dt>
      <dd className={`${bold ? "font-semibold" : ""} ${valueClass}`}>{value}</dd>
    </div>
  )
}
