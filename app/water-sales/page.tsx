"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Plus, Trash2, Loader2, ShoppingCart, AlertCircle, X, Wallet, Ban } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterSales, getWaterSale, createWaterSale, cancelWaterSale,
  listWaterProducts, listWaterCustomers, recordWaterPayment,
  type WaterSale, type WaterSaleItem, type WaterProduct, type WaterCustomer,
} from "@/lib/api/water"

interface DraftItem { waterProductId: number; quantity: number; unitPrice: number; productName?: string }

export default function WaterSalesPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [sales, setSales] = useState<WaterSale[]>([])
  const [products, setProducts] = useState<WaterProduct[]>([])
  const [customers, setCustomers] = useState<WaterCustomer[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

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
    setLoading(true); setError(null)
    try {
      const [s, p, c] = await Promise.all([listWaterSales(), listWaterProducts(), listWaterCustomers()])
      setSales(s); setProducts(p); setCustomers(c)
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setLoading(false) }
  }

  const draftTotal = useMemo(
    () => draftItems.reduce((a, i) => a + (i.quantity || 0) * (i.unitPrice || 0), 0),
    [draftItems],
  )

  function addLine() {
    if (products.length === 0) return toast({ title: "Add a product first" })
    const first = products[0]
    setDraftItems((d) => [...d, { waterProductId: first.waterProductId, quantity: 1, unitPrice: first.unitPrice, productName: first.name }])
  }

  function removeLine(idx: number) { setDraftItems((d) => d.filter((_, i) => i !== idx)) }

  function setLine(idx: number, patch: Partial<DraftItem>) {
    setDraftItems((d) => d.map((row, i) => {
      if (i !== idx) return row
      if (patch.waterProductId !== undefined) {
        const p = products.find((x) => x.waterProductId === patch.waterProductId)
        if (p) return { ...row, ...patch, unitPrice: p.unitPrice, productName: p.name }
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
        items: draftItems.map((i) => ({ waterProductId: i.waterProductId, quantity: i.quantity, unitPrice: i.unitPrice })),
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
          <div className="mb-4 flex items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <ShoppingCart className="h-6 w-6 text-sky-600" /> Water sales
            </h1>
            <Button onClick={() => { setDraftItems([]); setDraftCustomerId(null); setDraftNotes(""); setNewOpen(true) }}>
              <Plus className="h-4 w-4 mr-1" /> New sale
            </Button>
          </div>

          {error && (
            <Card className="border-red-200 bg-red-50 mb-4">
              <CardContent className="flex items-center gap-2 p-3 text-red-700">
                <AlertCircle className="h-4 w-4" /> {error}
              </CardContent>
            </Card>
          )}

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : sales.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No sales yet.</div>
              ) : (
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
                    {sales.map((s) => (
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
              )}
            </CardContent>
          </Card>
        </main>
      </div>

      {/* New sale dialog */}
      <Dialog open={newOpen} onOpenChange={setNewOpen}>
        <DialogContent className="max-w-2xl">
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
                <div className="space-y-2">
                  {draftItems.map((row, idx) => (
                    <div key={idx} className="grid grid-cols-12 gap-2 items-center">
                      <Select value={String(row.waterProductId)} onValueChange={(v) => setLine(idx, { waterProductId: parseInt(v, 10) })}>
                        <SelectTrigger className="col-span-6"><SelectValue /></SelectTrigger>
                        <SelectContent>
                          {products.filter((p) => p.isActive).map((p) => (
                            <SelectItem key={p.waterProductId} value={String(p.waterProductId)}>
                              {p.name} {p.unit ? `(${p.unit})` : ""} · stock {p.stockOnHand}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      <Input className="col-span-2" type="number" min={1} value={row.quantity} onChange={(e) => setLine(idx, { quantity: parseInt(e.target.value || "0", 10) })} />
                      <Input className="col-span-3" type="number" min={0} step="0.01" value={row.unitPrice} onChange={(e) => setLine(idx, { unitPrice: parseFloat(e.target.value || "0") })} />
                      <Button size="icon" variant="ghost" className="col-span-1" onClick={() => removeLine(idx)}>
                        <X className="h-4 w-4 text-red-500" />
                      </Button>
                    </div>
                  ))}
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
        <DialogContent className="max-w-2xl">
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
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Product</TableHead>
                      <TableHead className="text-right">Qty</TableHead>
                      <TableHead className="text-right">Unit price</TableHead>
                      <TableHead className="text-right">Line total</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {detailSale.items.map((it: WaterSaleItem) => (
                      <TableRow key={it.waterSaleItemId}>
                        <TableCell>{it.productName}</TableCell>
                        <TableCell className="text-right tabular-nums">{it.quantity}</TableCell>
                        <TableCell className="text-right tabular-nums">{it.unitPrice.toFixed(2)}</TableCell>
                        <TableCell className="text-right tabular-nums">{(it.lineTotal ?? it.quantity * it.unitPrice).toFixed(2)}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
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
              <Input type="number" min={0} step="0.01" value={payAmount || ""} onChange={(e) => setPayAmount(parseFloat(e.target.value || "0"))} /></div>
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
