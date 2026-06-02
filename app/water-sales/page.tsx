"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Plus, Trash2, Loader2, ShoppingCart, X, Wallet, Ban } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterSales, getWaterSale, createWaterSale, cancelWaterSale,
  listWaterProducts, listWaterCustomers, recordWaterPayment,
  type WaterSale, type WaterSaleItem, type WaterProduct, type WaterCustomer,
} from "@/lib/api/water"

// Migration 084: per-line selling unit so the operator can sell the same
// product by bag OR by sachet. Stock is deducted in BaseQuantity (sachets) on
// the backend.
interface DraftItem { waterProductId: number; quantity: number; unitPrice: number; productName?: string; sellingUnit?: string }

// Build the selling-unit options for a product. Sachet products expose both
// 'Bag' and 'Sachet'; non-sachet products fall back to their own Unit (or 'Unit').
function unitOptionsFor(p?: WaterProduct | null): string[] {
  if (!p) return ["Unit"]
  if (p.isSachetProduct) return ["Bag", "Sachet"]
  return [p.unit ?? "Unit"]
}

// Pick a default price for a (product, sellingUnit) pair using the new
// BagPrice / SachetPrice columns from migration 084, falling back to UnitPrice.
function priceFor(p: WaterProduct, sellingUnit: string): number {
  if (p.isSachetProduct) {
    if (sellingUnit === "Bag")    return p.bagPrice    ?? p.unitPrice
    if (sellingUnit === "Sachet") return p.sachetPrice ?? p.unitPrice
  }
  return p.unitPrice
}

export default function WaterSalesPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [sales, setSales] = useState<WaterSale[]>([])
  const [products, setProducts] = useState<WaterProduct[]>([])
  const [customers, setCustomers] = useState<WaterCustomer[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [loading, setLoading] = useState(true)

  const visibleSales = useMemo(
    () => filterByDateAndSearch(sales, {
      search, dateFrom, dateTo,
      searchKeys: ["customerName", "status", "notes"],
      dateKey: "saleDate",
    }),
    [sales, search, dateFrom, dateTo],
  )

  const [newOpen, setNewOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [draftCustomerId, setDraftCustomerId] = useState<number | null>(null)
  const [draftNotes, setDraftNotes] = useState("")
  const [draftItems, setDraftItems] = useState<DraftItem[]>([])

  const [detailSale, setDetailSale] = useState<WaterSale | null>(null)
  const [payOpen, setPayOpen] = useState(false)
  const [payAmount, setPayAmount] = useState<number>(0)
  const [payMethod, setPayMethod] = useState<string>("Cash")

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void loadAll()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function loadAll() {
    setLoading(true)
    try {
      const [s, p, c] = await Promise.all([listWaterSales(), listWaterProducts(), listWaterCustomers()])
      setSales(s); setProducts(p); setCustomers(c)
    } catch (e: any) { toast({ title: "Could not load sales", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  const draftTotal = useMemo(
    () => draftItems.reduce((a, i) => a + (i.quantity || 0) * (i.unitPrice || 0), 0),
    [draftItems],
  )

  function addLine() {
    if (products.length === 0) return toast({ title: "Add a product first" })
    const first = products[0]
    const unit = unitOptionsFor(first)[0]
    setDraftItems((d) => [...d, {
      waterProductId: first.waterProductId,
      quantity: 1,
      unitPrice: priceFor(first, unit),
      productName: first.name,
      sellingUnit: unit,
    }])
  }

  function removeLine(idx: number) { setDraftItems((d) => d.filter((_, i) => i !== idx)) }

  function setLine(idx: number, patch: Partial<DraftItem>) {
    setDraftItems((d) => d.map((row, i) => {
      if (i !== idx) return row
      // Switching product → reset selling unit + auto-fill price.
      if (patch.waterProductId !== undefined) {
        const p = products.find((x) => x.waterProductId === patch.waterProductId)
        if (p) {
          const unit = unitOptionsFor(p)[0]
          return { ...row, ...patch, unitPrice: priceFor(p, unit), productName: p.name, sellingUnit: unit }
        }
      }
      // Switching selling unit → auto-fill the matching price.
      if (patch.sellingUnit !== undefined) {
        const p = products.find((x) => x.waterProductId === row.waterProductId)
        if (p) return { ...row, ...patch, unitPrice: priceFor(p, patch.sellingUnit) }
      }
      return { ...row, ...patch }
    }))
  }

  async function saveSale() {
    if (draftItems.length === 0) return toast({ title: "Add at least one product", variant: "destructive" })
    if (draftItems.some((i) => !i.quantity || i.quantity < 1)) return toast({ title: "Quantity must be ≥ 1", variant: "destructive" })
    setSaving(true)
    try {
      await createWaterSale({
        waterCustomerId: draftCustomerId ?? null,
        notes: draftNotes || null,
        items: draftItems.map((i) => ({
          waterProductId: i.waterProductId,
          quantity: i.quantity,
          unitPrice: i.unitPrice,
          // Migration 084 — pass the selling unit so the backend deducts stock
          // in the correct base quantity (sachets for sachet products).
          sellingUnit: i.sellingUnit ?? null,
        })),
      })
      toast({ title: "Sale recorded" })
      setNewOpen(false); setDraftItems([]); setDraftCustomerId(null); setDraftNotes("")
      await loadAll()
    } catch (e: any) { toast({ title: "Sale failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function openDetail(sale: WaterSale) {
    try { setDetailSale(await getWaterSale(sale.waterSaleId)) }
    catch (e: any) { toast({ title: "Could not load sale", description: e?.message, variant: "destructive" }) }
  }

  async function recordPayment() {
    if (!detailSale) return
    if (!payAmount || payAmount <= 0) return toast({ title: "Enter an amount", variant: "destructive" })
    if (payAmount > detailSale.balance + 0.001) return toast({ title: "Amount exceeds balance", variant: "destructive" })
    setSaving(true)
    try {
      await recordWaterPayment({ waterSaleId: detailSale.waterSaleId, amount: payAmount, paymentMethod: payMethod })
      toast({ title: "Payment recorded" })
      setPayOpen(false); setPayAmount(0)
      const refreshed = await getWaterSale(detailSale.waterSaleId)
      setDetailSale(refreshed)
      await loadAll()
    } catch (e: any) { toast({ title: "Payment failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function cancel(sale: WaterSale) {
    if (!confirm(`Cancel sale #${sale.waterSaleId}? Stock will be restored.`)) return
    try {
      await cancelWaterSale(sale.waterSaleId)
      toast({ title: "Sale cancelled" })
      if (detailSale?.waterSaleId === sale.waterSaleId) setDetailSale(null)
      await loadAll()
    } catch (e: any) { toast({ title: "Cancel failed", description: e?.message, variant: "destructive" }) }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <ShoppingCart className="h-6 w-6 text-sky-600" /> Water sales
            </h1>
            <Button onClick={() => { setDraftItems([]); setDraftCustomerId(null); setDraftNotes(""); setNewOpen(true) }} className="w-full sm:w-auto h-11 sm:h-10">
              <Plus className="h-4 w-4 mr-1" /> New sale
            </Button>
          </div>

          <ListFilters
            search={search} setSearch={setSearch}
            dateFrom={dateFrom} setDateFrom={setDateFrom}
            dateTo={dateTo} setDateTo={setDateTo}
            searchPlaceholder="Search customer, status or notes"
          />

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : sales.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No sales yet.</div>
              ) : (
                <MobileCardList
                  items={visibleSales}
                  getKey={(s) => s.waterSaleId}
                  primary={(s) => `#${s.waterSaleId} · ${s.customerName ?? "Walk-in"}`}
                  secondary={(s) => (
                    <>
                      <span>{new Date(s.saleDate).toLocaleString()}</span>
                      <span>·</span>
                      <StatusBadge status={s.status} />
                      <span>·</span>
                      <span className="tabular-nums">
                        Paid <strong>{s.amountPaid.toFixed(2)}</strong> / {s.totalAmount.toFixed(2)}
                      </span>
                    </>
                  )}
                  details={(s) => [
                    { label: "Date", value: new Date(s.saleDate).toLocaleString() },
                    { label: "Customer", value: s.customerName ?? "Walk-in" },
                    { label: "Total", value: s.totalAmount.toFixed(2) },
                    { label: "Paid", value: s.amountPaid.toFixed(2) },
                    {
                      label: "Balance",
                      value: (
                        <span className={s.balance > 0 ? "text-rose-600" : "text-slate-500"}>
                          {s.balance.toFixed(2)}
                        </span>
                      ),
                    },
                    { label: "Status", value: <StatusBadge status={s.status} /> },
                  ]}
                  actions={(s) => (
                    <>
                      <Button size="sm" variant="outline" className="flex-1 h-10" onClick={() => openDetail(s)}>Details</Button>
                      {s.status !== "Cancelled" && (
                        <Button size="sm" variant="outline" className="flex-1 h-10 text-red-600 border-red-200" onClick={() => cancel(s)}>
                          <Ban className="h-4 w-4 mr-1" /> Cancel
                        </Button>
                      )}
                    </>
                  )}
                  desktopTable={
                    <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>#</TableHead>
                          <TableHead>Date</TableHead>
                          <TableHead>Customer</TableHead>
                          <TableHead className="text-right">Total</TableHead>
                          <TableHead className="text-right">Paid</TableHead>
                          <TableHead className="text-right">Balance</TableHead>
                          <TableHead>Status</TableHead>
                          <TableHead className="text-right">Actions</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {visibleSales.map((s) => (
                          <TableRow key={s.waterSaleId}>
                            <TableCell>#{s.waterSaleId}</TableCell>
                            <TableCell>{new Date(s.saleDate).toLocaleString()}</TableCell>
                            <TableCell>{s.customerName ?? <span className="text-slate-400">Walk-in</span>}</TableCell>
                            <TableCell className="text-right tabular-nums">{s.totalAmount.toFixed(2)}</TableCell>
                            <TableCell className="text-right tabular-nums">{s.amountPaid.toFixed(2)}</TableCell>
                            <TableCell className={`text-right tabular-nums ${s.balance > 0 ? "text-rose-600" : "text-slate-500"}`}>{s.balance.toFixed(2)}</TableCell>
                            <TableCell><StatusBadge status={s.status} /></TableCell>
                            <TableCell className="text-right">
                              <Button size="sm" variant="ghost" onClick={() => openDetail(s)}>Details</Button>
                              {s.status !== "Cancelled" && (
                                <Button size="sm" variant="ghost" onClick={() => cancel(s)} title="Cancel">
                                  <Ban className="h-4 w-4 text-red-500" />
                                </Button>
                              )}
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                    </div>
                  }
                />
              )}
            </CardContent>
          </Card>
        </main>
      </div>

      {/* New sale dialog */}
      <Dialog open={newOpen} onOpenChange={setNewOpen}>
        <DialogContent className="w-[95vw] max-w-[1600px] max-h-[90vh] overflow-y-auto">
          <DialogHeader><DialogTitle>New water sale</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <div>
              <Label>Customer</Label>
              <Select value={draftCustomerId ? String(draftCustomerId) : "0"} onValueChange={(v) => setDraftCustomerId(v === "0" ? null : parseInt(v, 10))}>
                <SelectTrigger><SelectValue placeholder="Walk-in / cash" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="0">Walk-in / cash</SelectItem>
                  {customers.map((c) => <SelectItem key={c.waterCustomerId} value={String(c.waterCustomerId)}>{c.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>

            <div>
              <div className="flex items-center justify-between mb-2">
                <Label>Items</Label>
                <Button size="sm" variant="outline" onClick={addLine}><Plus className="h-3 w-3 mr-1" /> Add line</Button>
              </div>
              {draftItems.length === 0 ? (
                <div className="rounded-md border border-dashed border-slate-300 p-4 text-center text-sm text-slate-400">
                  No items. Click <span className="font-medium">Add line</span>.
                </div>
              ) : (
                <div className="space-y-3">
                  {/* Migration 084: explicit field labels — operators were guessing
                      which numeric column was Quantity vs Unit Price. Selling
                      Unit lets sachet products be sold by bag OR by sachet. */}
                  <div className="hidden md:grid grid-cols-12 gap-2 text-xs text-slate-500 px-1">
                    <div className="col-span-5">Product</div>
                    <div className="col-span-2">Selling Unit</div>
                    <div className="col-span-1 text-right">Quantity</div>
                    <div className="col-span-2 text-right">Unit Price</div>
                    <div className="col-span-1 text-right">Line Total</div>
                    <div className="col-span-1" />
                  </div>
                  {draftItems.map((row, idx) => {
                    const p = products.find((x) => x.waterProductId === row.waterProductId)
                    const units = unitOptionsFor(p)
                    const lineTotal = (row.quantity || 0) * (row.unitPrice || 0)
                    return (
                      <div key={idx} className="grid grid-cols-12 gap-2 items-end">
                        <div className="col-span-12 md:col-span-5">
                          <Label className="md:hidden text-xs text-slate-500">Product</Label>
                          <Select value={String(row.waterProductId)} onValueChange={(v) => setLine(idx, { waterProductId: parseInt(v, 10) })}>
                            <SelectTrigger><SelectValue /></SelectTrigger>
                            <SelectContent>
                              {products.filter((p) => p.isActive).map((p) => (
                                <SelectItem key={p.waterProductId} value={String(p.waterProductId)}>
                                  {p.name} {p.unit ? `(${p.unit})` : ""} · stock {p.stockOnHand}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                        <div className="col-span-6 md:col-span-2">
                          <Label className="md:hidden text-xs text-slate-500">Selling Unit</Label>
                          <Select value={row.sellingUnit ?? units[0]} onValueChange={(v) => setLine(idx, { sellingUnit: v })}>
                            <SelectTrigger><SelectValue /></SelectTrigger>
                            <SelectContent>
                              {units.map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}
                            </SelectContent>
                          </Select>
                        </div>
                        <div className="col-span-3 md:col-span-1">
                          <Label className="md:hidden text-xs text-slate-500">Qty</Label>
                          <NumberInput min={1} value={row.quantity} onChange={(e) => setLine(idx, { quantity: parseInt(e.target.value || "0", 10) })} />
                        </div>
                        <div className="col-span-3 md:col-span-2">
                          <Label className="md:hidden text-xs text-slate-500">Unit Price</Label>
                          <NumberInput min={0} step="0.01" value={row.unitPrice} onChange={(e) => setLine(idx, { unitPrice: parseFloat(e.target.value || "0") })} />
                        </div>
                        <div className="col-span-10 md:col-span-1 text-right tabular-nums font-medium text-slate-700 self-center">
                          <Label className="md:hidden text-xs text-slate-500">Line Total</Label>
                          {lineTotal.toFixed(2)}
                        </div>
                        <div className="col-span-2 md:col-span-1 text-right">
                          <Button size="icon" variant="ghost" onClick={() => removeLine(idx)} title="Remove line">
                            <X className="h-4 w-4 text-red-500" />
                          </Button>
                        </div>
                      </div>
                    )
                  })}
                </div>
              )}
              <div className="mt-3 text-right text-sm">
                Total: <span className="font-semibold tabular-nums">{draftTotal.toFixed(2)}</span>
              </div>
            </div>

            <div><Label>Notes</Label>
              <Input value={draftNotes} onChange={(e) => setDraftNotes(e.target.value)} /></div>

            <div className="flex justify-end gap-2">
              <Button variant="ghost" onClick={() => setNewOpen(false)}>Cancel</Button>
              <Button onClick={saveSale} disabled={saving || draftItems.length === 0}>{saving ? "Saving…" : "Record sale"}</Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Detail dialog */}
      <Dialog open={!!detailSale} onOpenChange={(o) => { if (!o) setDetailSale(null) }}>
        <DialogContent className="w-[95vw] max-w-[1600px] max-h-[90vh] overflow-y-auto">
          {detailSale && (
            <>
              <DialogHeader>
                <DialogTitle>Sale #{detailSale.waterSaleId} · <StatusBadge status={detailSale.status} /></DialogTitle>
              </DialogHeader>
              <div className="space-y-3">
                <div className="grid grid-cols-2 gap-3 text-sm">
                  <div><span className="text-slate-500">Customer:</span> {detailSale.customerName ?? "Walk-in"}</div>
                  <div><span className="text-slate-500">Date:</span> {new Date(detailSale.saleDate).toLocaleString()}</div>
                  <div><span className="text-slate-500">Total:</span> <span className="tabular-nums">{detailSale.totalAmount.toFixed(2)}</span></div>
                  <div><span className="text-slate-500">Paid:</span> <span className="tabular-nums">{detailSale.amountPaid.toFixed(2)}</span></div>
                  <div className="col-span-2"><span className="text-slate-500">Balance:</span> <span className={`tabular-nums font-semibold ${detailSale.balance > 0 ? "text-rose-600" : "text-emerald-600"}`}>{detailSale.balance.toFixed(2)}</span></div>
                </div>
                <div className="overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Product</TableHead>
                      <TableHead>Selling Unit</TableHead>
                      <TableHead className="text-right">Quantity</TableHead>
                      <TableHead className="text-right">Unit Price</TableHead>
                      <TableHead className="text-right">Line Total</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {detailSale.items.map((it: WaterSaleItem) => (
                      <TableRow key={it.waterSaleItemId}>
                        <TableCell>{it.productName}</TableCell>
                        <TableCell className="text-slate-600">
                          {it.sellingUnit ?? "—"}
                          {it.baseUnit && it.baseQuantity != null && it.sellingUnit && it.sellingUnit !== it.baseUnit
                            ? <span className="text-xs text-slate-400 ml-1">({Number(it.baseQuantity).toLocaleString()} {it.baseUnit})</span>
                            : null}
                        </TableCell>
                        <TableCell className="text-right tabular-nums">{it.quantity}</TableCell>
                        <TableCell className="text-right tabular-nums">{it.unitPrice.toFixed(2)}</TableCell>
                        <TableCell className="text-right tabular-nums">{(it.lineTotal ?? it.quantity * it.unitPrice).toFixed(2)}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
                </div>
                <div className="flex justify-end gap-2 pt-2">
                  {detailSale.status !== "Cancelled" && detailSale.balance > 0 && (
                    <Button onClick={() => { setPayAmount(detailSale.balance); setPayMethod("Cash"); setPayOpen(true) }}>
                      <Wallet className="h-4 w-4 mr-1" /> Record payment
                    </Button>
                  )}
                  <Button variant="ghost" onClick={() => setDetailSale(null)}>Close</Button>
                </div>
              </div>
            </>
          )}
        </DialogContent>
      </Dialog>

      {/* Payment dialog */}
      <Dialog open={payOpen} onOpenChange={setPayOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle>Record payment</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <div><Label>Amount</Label>
              <NumberInput min={0} step="0.01" value={payAmount || ""} onChange={(e) => setPayAmount(parseFloat(e.target.value || "0"))} /></div>
            <div><Label>Method</Label>
              <Select value={payMethod} onValueChange={setPayMethod}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="Cash">Cash</SelectItem>
                  <SelectItem value="Mobile Money">Mobile Money</SelectItem>
                  <SelectItem value="Bank">Bank transfer</SelectItem>
                  <SelectItem value="Cheque">Cheque</SelectItem>
                </SelectContent>
              </Select></div>
            <div className="flex justify-end gap-2">
              <Button variant="ghost" onClick={() => setPayOpen(false)}>Cancel</Button>
              <Button onClick={recordPayment} disabled={saving}>{saving ? "Saving…" : "Record"}</Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}

function StatusBadge({ status }: { status: string }) {
  const map: Record<string, string> = {
    Paid:          "bg-emerald-100 text-emerald-700",
    PartiallyPaid: "bg-amber-100 text-amber-700",
    Pending:       "bg-slate-100 text-slate-700",
    Cancelled:     "bg-rose-100 text-rose-700",
  }
  return <span className={`inline-block rounded px-2 py-0.5 text-xs font-medium ${map[status] ?? "bg-slate-100 text-slate-700"}`}>{status}</span>
}
