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
import { Plus, Trash2, Loader2, ShoppingCart, X, Wallet, Ban, CheckCircle2 } from "lucide-react"
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
  // Issue 6 (test-report): walk-in cash sales should be marked paid in one
  // step instead of forcing the operator into the Details → Record payment
  // sub-flow. "Paid now" defaults Cash but the method is editable below.
  const [draftPaidNow, setDraftPaidNow] = useState<boolean>(false)
  const [draftPaidMethod, setDraftPaidMethod] = useState<string>("Cash")

  const [detailSale, setDetailSale] = useState<WaterSale | null>(null)
  const [payOpen, setPayOpen] = useState(false)
  const [payAmount, setPayAmount] = useState<number>(0)
  const [payMethod, setPayMethod] = useState<string>("Cash")
  // When opening the payment modal we now route through this so we can also
  // launch it directly from a pending row (issue 6, sub-fix 2).
  const [payForSale, setPayForSale] = useState<WaterSale | null>(null)

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
      const created = await createWaterSale({
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
      // Issue 6 (test-report): "Pay now" toggle in the modal records the full
      // payment immediately so walk-in cash sales never enter the Pending
      // state. The backend total is derived from items; we re-compute here.
      const total = draftItems.reduce((a, i) => a + (i.quantity || 0) * (i.unitPrice || 0), 0)
      if (draftPaidNow && created?.waterSaleId && total > 0) {
        try {
          await recordWaterPayment({
            waterSaleId: created.waterSaleId,
            amount: total,
            paymentMethod: draftPaidMethod || "Cash",
          })
          toast({ title: `Sale #${created.waterSaleId} recorded · Paid in full` })
        } catch (payErr: any) {
          // Sale already saved; surface the payment error but don't roll back.
          toast({
            title: `Sale #${created.waterSaleId} recorded, but payment failed`,
            description: payErr?.message ?? "You can record payment from the row.",
            variant: "destructive",
          })
        }
      } else {
        // Sub-fix 4 — give the operator a clear next-step when the sale lands
        // as Pending instead of leaving them to discover the Details button.
        toast({
          title: `Sale #${created?.waterSaleId ?? ""} recorded`,
          description: total > 0 ? "Tap 'Mark as Paid' on the row when payment is collected." : undefined,
        })
      }
      setNewOpen(false); setDraftItems([]); setDraftCustomerId(null); setDraftNotes("")
      setDraftPaidNow(false); setDraftPaidMethod("Cash")
      await loadAll()
    } catch (e: any) { toast({ title: "Sale failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  async function openDetail(sale: WaterSale) {
    try { setDetailSale(await getWaterSale(sale.waterSaleId)) }
    catch (e: any) { toast({ title: "Could not load sale", description: e?.message, variant: "destructive" }) }
  }

  // Issue 6 (sub-fix 2): opens the payment modal directly from a pending row
  // — no detour through the Details dialog. Works for both list-row triggers
  // (sets payForSale) and the in-detail "Record payment" button (already sets
  // detailSale, so we just mirror it into payForSale).
  function openPay(sale: WaterSale) {
    setPayForSale(sale)
    setPayAmount(sale.balance)
    setPayMethod("Cash")
    setPayOpen(true)
  }

  async function recordPayment() {
    const target = payForSale ?? detailSale
    if (!target) return
    if (!payAmount || payAmount <= 0) return toast({ title: "Enter an amount", variant: "destructive" })
    if (payAmount > target.balance + 0.001) return toast({ title: "Amount exceeds balance", variant: "destructive" })
    setSaving(true)
    try {
      await recordWaterPayment({ waterSaleId: target.waterSaleId, amount: payAmount, paymentMethod: payMethod })
      toast({ title: "Payment recorded" })
      setPayOpen(false); setPayAmount(0); setPayForSale(null)
      if (detailSale && detailSale.waterSaleId === target.waterSaleId) {
        const refreshed = await getWaterSale(detailSale.waterSaleId)
        setDetailSale(refreshed)
      }
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
            <Button onClick={() => { setDraftItems([]); setDraftCustomerId(null); setDraftNotes(""); setDraftPaidNow(false); setDraftPaidMethod("Cash"); setNewOpen(true) }} className="w-full sm:w-auto h-11 sm:h-10">
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
                      {/* Issue 6 (sub-fix 2): surface a primary "Mark as Paid"
                          button on every pending/partial row so staff don't
                          have to discover the Details → Record payment path. */}
                      {s.status !== "Cancelled" && s.balance > 0 && (
                        <Button
                          size="sm"
                          className="flex-1 h-10 bg-emerald-600 hover:bg-emerald-700 text-white"
                          onClick={() => openPay(s)}
                        >
                          <CheckCircle2 className="h-4 w-4 mr-1" /> Mark as Paid
                        </Button>
                      )}
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
                            <TableCell>
                              <StatusBadge status={s.status} />
                              {/* Issue 6 (sub-fix 3): clickable "Awaiting
                                  payment →" prompt next to the badge so pending
                                  rows have visible urgency without the staff
                                  needing to know what "Details" means. */}
                              {s.status !== "Cancelled" && s.balance > 0 && (
                                <button
                                  type="button"
                                  onClick={() => openPay(s)}
                                  className="ml-2 inline-flex items-center text-xs font-medium text-rose-600 hover:text-rose-700 hover:underline"
                                >
                                  Awaiting payment →
                                </button>
                              )}
                            </TableCell>
                            <TableCell className="text-right">
                              {/* Issue 6 (sub-fix 2): inline Mark as Paid on
                                  the row beats hiding it behind Details. */}
                              {s.status !== "Cancelled" && s.balance > 0 && (
                                <Button
                                  size="sm"
                                  className="mr-1 h-8 bg-emerald-600 hover:bg-emerald-700 text-white"
                                  onClick={() => openPay(s)}
                                >
                                  <CheckCircle2 className="h-4 w-4 mr-1" /> Mark as Paid
                                </Button>
                              )}
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
                  {/* Issue 5 (test-report): the items grid was using
                      col-span-1 for Quantity and Line Total so the input
                      boxes were too narrow and visibly clipped digits. We
                      now use a 24-column grid for finer balance, give Qty
                      two cols (~2/24 ≈ 8% → small but with bigger numeric
                      padding from tabular-nums), keep Product the widest,
                      and stack the stock count as a muted subline inside
                      the SelectItem so long names don't fight the same row
                      for space. The X column drops to a fixed 32px so it
                      doesn't steal width from data columns. */}
                  <div className="hidden md:grid grid-cols-[minmax(0,11fr)_minmax(0,4fr)_minmax(0,3fr)_minmax(0,3fr)_minmax(0,3fr)_32px] gap-2 text-xs text-slate-500 px-1">
                    <div>Product</div>
                    <div>Selling Unit</div>
                    <div className="text-right">Quantity</div>
                    <div className="text-right">Unit Price</div>
                    <div className="text-right">Line Total</div>
                    <div />
                  </div>
                  {draftItems.map((row, idx) => {
                    const p = products.find((x) => x.waterProductId === row.waterProductId)
                    const units = unitOptionsFor(p)
                    const lineTotal = (row.quantity || 0) * (row.unitPrice || 0)
                    return (
                      <div
                        key={idx}
                        className="grid grid-cols-12 md:grid-cols-[minmax(0,11fr)_minmax(0,4fr)_minmax(0,3fr)_minmax(0,3fr)_minmax(0,3fr)_32px] gap-2 items-end"
                      >
                        <div className="col-span-12 md:col-auto min-w-0" title={p?.name}>
                          <Label className="md:hidden text-xs text-slate-500">Product</Label>
                          <Select value={String(row.waterProductId)} onValueChange={(v) => setLine(idx, { waterProductId: parseInt(v, 10) })}>
                            <SelectTrigger className="min-w-0">
                              <SelectValue />
                            </SelectTrigger>
                            <SelectContent>
                              {products.filter((p) => p.isActive).map((p) => (
                                <SelectItem key={p.waterProductId} value={String(p.waterProductId)}>
                                  {/* Stack name + stock so the product cell
                                      doesn't have to fit "Sachet water (sachet) · stock 300"
                                      on one line. */}
                                  <span className="flex flex-col leading-tight">
                                    <span className="truncate">{p.name} {p.unit ? `(${p.unit})` : ""}</span>
                                    <span className="text-[11px] text-slate-400">stock {p.stockOnHand}</span>
                                  </span>
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                        <div className="col-span-6 md:col-auto min-w-0">
                          <Label className="md:hidden text-xs text-slate-500">Selling Unit</Label>
                          <Select value={row.sellingUnit ?? units[0]} onValueChange={(v) => setLine(idx, { sellingUnit: v })}>
                            <SelectTrigger className="min-w-0"><SelectValue /></SelectTrigger>
                            <SelectContent>
                              {units.map((u) => <SelectItem key={u} value={u}>{u}</SelectItem>)}
                            </SelectContent>
                          </Select>
                        </div>
                        <div className="col-span-3 md:col-auto min-w-0">
                          <Label className="md:hidden text-xs text-slate-500">Qty</Label>
                          <NumberInput
                            className="text-right tabular-nums"
                            min={1}
                            value={row.quantity}
                            onChange={(e) => setLine(idx, { quantity: parseInt(e.target.value || "0", 10) })}
                          />
                        </div>
                        <div className="col-span-3 md:col-auto min-w-0">
                          <Label className="md:hidden text-xs text-slate-500">Unit Price</Label>
                          <NumberInput
                            className="text-right tabular-nums"
                            min={0}
                            step="0.01"
                            value={row.unitPrice}
                            onChange={(e) => setLine(idx, { unitPrice: parseFloat(e.target.value || "0") })}
                          />
                        </div>
                        <div className="col-span-10 md:col-auto text-right tabular-nums font-medium text-slate-700 self-center">
                          <Label className="md:hidden text-xs text-slate-500">Line Total</Label>
                          {lineTotal.toFixed(2)}
                        </div>
                        <div className="col-span-2 md:col-auto text-right">
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

            {/* Issue 6 (sub-fix 1): point-of-sale payment status. The common
                case (walk-in cash) was forcing operators through the Details →
                Record payment sub-flow. With this toggle the sale lands as
                Paid in one click. */}
            <div className="rounded-md border border-slate-200 bg-slate-50 p-3">
              <Label className="mb-2 block text-sm">Payment status</Label>
              <div className="flex flex-wrap items-center gap-3">
                <label className="inline-flex items-center gap-2 text-sm">
                  <input
                    type="radio"
                    name="paid-now"
                    checked={!draftPaidNow}
                    onChange={() => setDraftPaidNow(false)}
                  />
                  Pay later (pending)
                </label>
                <label className="inline-flex items-center gap-2 text-sm">
                  <input
                    type="radio"
                    name="paid-now"
                    checked={draftPaidNow}
                    onChange={() => setDraftPaidNow(true)}
                  />
                  Paid now
                </label>
                {draftPaidNow && (
                  <div className="ml-2 min-w-[12rem]">
                    <Select value={draftPaidMethod} onValueChange={setDraftPaidMethod}>
                      <SelectTrigger className="h-9"><SelectValue /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="Cash">Cash</SelectItem>
                        <SelectItem value="Mobile Money">Mobile Money</SelectItem>
                        <SelectItem value="Bank">Bank transfer</SelectItem>
                        <SelectItem value="Cheque">Cheque</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                )}
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
                    <Button onClick={() => openPay(detailSale)}>
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
      <Dialog
        open={payOpen}
        onOpenChange={(o) => { setPayOpen(o); if (!o) setPayForSale(null) }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              Record payment
              {payForSale ? ` · Sale #${payForSale.waterSaleId}` : detailSale ? ` · Sale #${detailSale.waterSaleId}` : ""}
            </DialogTitle>
          </DialogHeader>
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
