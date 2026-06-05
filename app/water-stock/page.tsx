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
import { Plus, Boxes, Loader2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterStockTransactions, addWaterStockTransaction, listWaterProducts,
  type WaterStockTransaction, type WaterProduct,
} from "@/lib/api/water"

export default function WaterStockPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [txns, setTxns] = useState<WaterStockTransaction[]>([])
  const [products, setProducts] = useState<WaterProduct[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [loading, setLoading] = useState(true)
  const [filterProductId, setFilterProductId] = useState<number | null>(null)

  const visibleTxns = useMemo(
    () => filterByDateAndSearch(txns, {
      search, dateFrom, dateTo,
      searchKeys: ["productName", "txnType", "note"],
      dateKey: "createdDate",
    }),
    [txns, search, dateFrom, dateTo],
  )

  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState<{ productId: number | null; txnType: "Restock" | "Adjust" | "Return"; quantity: number; unitCost?: number; note: string }>({
    productId: null, txnType: "Restock", quantity: 0, unitCost: undefined, note: "",
  })

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const [t, p] = await Promise.all([listWaterStockTransactions(filterProductId ?? undefined), listWaterProducts()])
      setTxns(t); setProducts(p)
    } catch (e: any) { toast({ title: "Could not load stock", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  useEffect(() => { if (!loading) void load() /* refilter */ }, [filterProductId]) // eslint-disable-line

  async function save() {
    if (!form.productId) return toast({ title: "Pick a product", variant: "destructive" })
    if (!form.quantity || form.quantity === 0) return toast({ title: "Quantity must be non-zero", variant: "destructive" })

    // For Adjust we accept signed quantity. For Restock/Return we treat input as positive units IN.
    let signedQty = form.quantity
    if (form.txnType === "Restock") signedQty = Math.abs(form.quantity)
    if (form.txnType === "Return")  signedQty = Math.abs(form.quantity)   // returning unsold goods back to stock

    setSaving(true)
    try {
      await addWaterStockTransaction({
        waterProductId: form.productId,
        txnType: form.txnType,
        quantity: signedQty,
        unitCost: form.unitCost ?? null,
        note: form.note || null,
      })
      toast({ title: "Stock updated" })
      setOpen(false); setForm({ productId: null, txnType: "Restock", quantity: 0, unitCost: undefined, note: "" })
      await load()
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <Boxes className="h-6 w-6 text-sky-600" /> Stock transactions
            </h1>
            <div className="flex flex-wrap items-center gap-2">
              <Select
                value={filterProductId ? String(filterProductId) : "0"}
                onValueChange={(v) => setFilterProductId(v === "0" ? null : parseInt(v, 10))}
              >
                <SelectTrigger className="w-[220px]"><SelectValue placeholder="All products" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="0">All products</SelectItem>
                  {products.map((p) => <SelectItem key={p.waterProductId} value={String(p.waterProductId)}>{p.name}</SelectItem>)}
                </SelectContent>
              </Select>
              <Button onClick={() => setOpen(true)}><Plus className="h-4 w-4 mr-1" /> New entry</Button>
            </div>
          </div>

          <ListFilters
            search={search} setSearch={setSearch}
            dateFrom={dateFrom} setDateFrom={setDateFrom}
            dateTo={dateTo} setDateTo={setDateTo}
            searchPlaceholder="Search product, type or note"
          />

          <Card>
            <CardContent className="p-0">
              {loading ? (
                <div className="p-6 text-slate-500 flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
              ) : txns.length === 0 ? (
                <div className="p-8 text-center text-slate-500">No stock transactions yet.</div>
              ) : (
                <MobileCardList
                  items={visibleTxns}
                  getKey={(t) => t.stockTxnId}
                  primary={(t) => t.productName}
                  secondary={(t) => (
                    <>
                      <span>{new Date(t.createdDate).toLocaleString()}</span>
                      <span>·</span>
                      <span>{t.txnType}</span>
                      <span>·</span>
                      <span className={`font-medium tabular-nums ${t.quantity < 0 ? "text-rose-600" : "text-emerald-600"}`}>
                        {t.quantity > 0 ? `+${t.quantity}` : t.quantity} qty
                      </span>
                    </>
                  )}
                  details={(t) => [
                    { label: "Date", value: new Date(t.createdDate).toLocaleString() },
                    { label: "Type", value: t.txnType },
                    {
                      label: "Qty",
                      value: (
                        <span className={t.quantity < 0 ? "text-rose-600" : "text-emerald-600"}>
                          {t.quantity > 0 ? `+${t.quantity}` : t.quantity}
                        </span>
                      ),
                    },
                    { label: "Unit cost", value: t.unitCost?.toFixed(2) ?? "—" },
                    { label: "Note", value: t.note ?? "—" },
                  ]}
                  desktopTable={
                    <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Date</TableHead>
                          <TableHead>Product</TableHead>
                          <TableHead>Type</TableHead>
                          <TableHead className="text-right">Qty</TableHead>
                          <TableHead className="text-right">Unit cost</TableHead>
                          <TableHead>Note</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {visibleTxns.map((t) => (
                          <TableRow key={t.stockTxnId}>
                            <TableCell>{new Date(t.createdDate).toLocaleString()}</TableCell>
                            <TableCell>{t.productName}</TableCell>
                            <TableCell>{t.txnType}</TableCell>
                            <TableCell className={`text-right tabular-nums ${t.quantity < 0 ? "text-rose-600" : "text-emerald-600"}`}>
                              {t.quantity > 0 ? `+${t.quantity}` : t.quantity}
                            </TableCell>
                            <TableCell className="text-right tabular-nums">{t.unitCost?.toFixed(2) ?? "—"}</TableCell>
                            <TableCell className="text-slate-500">{t.note ?? "—"}</TableCell>
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

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle>New stock entry</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <div><Label>Product *</Label>
              <Select value={form.productId ? String(form.productId) : ""} onValueChange={(v) => setForm({ ...form, productId: parseInt(v, 10) })}>
                <SelectTrigger><SelectValue placeholder="Pick a product…" /></SelectTrigger>
                <SelectContent>
                  {products.map((p) => <SelectItem key={p.waterProductId} value={String(p.waterProductId)}>{p.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div><Label>Type</Label>
              <Select value={form.txnType} onValueChange={(v) => setForm({ ...form, txnType: v as any })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="Restock">Restock (add stock)</SelectItem>
                  <SelectItem value="Adjust">Adjust (signed)</SelectItem>
                  <SelectItem value="Return">Return (add back)</SelectItem>
                </SelectContent>
              </Select></div>
            <div><Label>Quantity {form.txnType === "Adjust" ? "(signed)" : ""}</Label>
              <NumberInput value={form.quantity || ""} onChange={(e) => setForm({ ...form, quantity: parseInt(e.target.value || "0", 10) })} /></div>
            <div><Label>Unit cost (optional, for restocks)</Label>
              <NumberInput step="0.01" min={0} value={form.unitCost ?? ""} onChange={(e) => setForm({ ...form, unitCost: e.target.value === "" ? undefined : parseFloat(e.target.value) })} /></div>
            <div><Label>Note</Label>
              <Input value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} /></div>
            <div className="flex justify-end gap-2">
              <Button variant="ghost" onClick={() => setOpen(false)}>Cancel</Button>
              <Button onClick={save} disabled={saving}>{saving ? "Saving…" : "Save"}</Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}
