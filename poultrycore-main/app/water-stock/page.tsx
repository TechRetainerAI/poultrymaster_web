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
import { Select, SelectContent, SelectGroup, SelectItem, SelectLabel, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { MobileCardList } from "@/components/ui/mobile-card-list"
import { usePagination } from "@/hooks/use-pagination"
import { Badge } from "@/components/ui/badge"
import { ListFilters, filterByDateAndSearch } from "@/components/ui/list-filters"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Plus, Boxes, Loader2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  listWaterStockTransactions, addWaterStockTransaction, listWaterProducts, listWaterRawMaterialItems,
  adjustWaterRawMaterialItem, setWaterProductStock, reconcileWaterProductStock,
  type WaterStockTransaction, type WaterProduct, type WaterRawMaterialItem,
} from "@/lib/api/water"
import { WaterRecalculateStockButton } from "@/components/water/recalculate-stock-button"
import { SetProductStockButton } from "@/components/inventory/set-product-stock-button"
import { ReconcileProductStockButton } from "@/components/inventory/reconcile-product-stock-button"

// #23: stock entries typed in by hand use these txn types; everything else
// (Production, ProductionConsume, Sale, DeliveryOut, …) is system-generated.
const MANUAL_TXN_TYPES = ["Restock", "Adjust", "Return", "Manual", "Opening"]
const isManualTxn = (txnType?: string | null) => MANUAL_TXN_TYPES.includes((txnType ?? "").trim())

export default function WaterStockPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  const [txns, setTxns] = useState<WaterStockTransaction[]>([])
  const [products, setProducts] = useState<WaterProduct[]>([])
  const [rawItems, setRawItems] = useState<WaterRawMaterialItem[]>([])
  const [search, setSearch] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [loading, setLoading] = useState(true)
  const [filterProductId, setFilterProductId] = useState<number | null>(null)
  // #23: distinguish stock typed in by hand from stock the system moved
  // (production output/consumption, sales, deliveries). Filter defaults to all.
  const [sourceFilter, setSourceFilter] = useState<"all" | "manual" | "system">("all")

  const visibleTxns = useMemo(
    () => filterByDateAndSearch(txns, {
      search, dateFrom, dateTo,
      searchKeys: ["productName", "txnType", "note"],
      dateKey: "createdDate",
    }).filter((t) =>
      sourceFilter === "all" ? true :
      sourceFilter === "manual" ? isManualTxn(t.txnType) : !isManualTxn(t.txnType),
    ),
    [txns, search, dateFrom, dateTo, sourceFilter],
  )

  const [sort, setSort] = useState<{ key: string | null; direction: SortDirection }>({ key: null, direction: null })
  const sortedTxns = useMemo(() => sortData(visibleTxns, sort.key, sort.direction, (t: WaterStockTransaction, k: string) => {
    if (k === "createdDate") return new Date(t.createdDate)
    if (k === "quantity") return t.quantity
    if (k === "unitCost") return t.unitCost ?? 0
    return (t as any)[k]
  }), [visibleTxns, sort])

  // Client-side paging: the whole list is already in memory, so this is a
  // slice. Feed the SAME slice to the cards and the desktop table.
  const pg = usePagination(sortedTxns)

  const onSort = (k: string) => setSort((s) => toggleSort(k, s.key, s.direction))

  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  // `target` encodes the picked item: "p:<id>" = finished product, "r:<id>" = raw material / supply.
  const [form, setForm] = useState<{ target: string; txnType: "Restock" | "Adjust" | "Return"; quantity: number; unitCost?: number; note: string }>({
    target: "", txnType: "Restock", quantity: 0, unitCost: undefined, note: "",
  })

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const [t, p, ri] = await Promise.all([listWaterStockTransactions(filterProductId ?? undefined), listWaterProducts(), listWaterRawMaterialItems().catch(() => [])])
      setTxns(t); setProducts(p); setRawItems(ri)
    } catch (e: any) { toast({ title: "Could not load stock", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  useEffect(() => { if (!loading) void load() /* refilter */ }, [filterProductId]) // eslint-disable-line

  async function save() {
    if (!form.target) return toast({ title: "Pick an item", variant: "destructive" })
    if (!form.quantity || form.quantity === 0) return toast({ title: "Quantity must be non-zero", variant: "destructive" })

    // For Adjust we accept signed quantity. For Restock/Return we treat input as positive units IN.
    let signedQty = form.quantity
    if (form.txnType === "Restock") signedQty = Math.abs(form.quantity)
    if (form.txnType === "Return")  signedQty = Math.abs(form.quantity)   // returning unsold goods back to stock

    const [kind, idStr] = form.target.split(":")
    const id = Number(idStr)
    setSaving(true)
    try {
      if (kind === "r") {
        // Raw material / supply — adjust its stock directly (no sale/production side effects).
        await adjustWaterRawMaterialItem(id, { quantity: signedQty, unitCost: form.unitCost ?? null, movementType: form.txnType, note: form.note || "Manual stock adjustment" })
      } else {
        await addWaterStockTransaction({
          waterProductId: id,
          txnType: form.txnType,
          quantity: signedQty,
          unitCost: form.unitCost ?? null,
          note: form.note || null,
        })
      }
      toast({ title: "Stock updated" })
      setOpen(false); setForm({ target: "", txnType: "Restock", quantity: 0, unitCost: undefined, note: "" })
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
              <Boxes className="h-6 w-6 text-sky-600" /> Stock movement
            </h1>
            <div className="flex flex-wrap items-center gap-2">
              <Select
                value={filterProductId ? String(filterProductId) : "0"}
                onValueChange={(v) => setFilterProductId(v === "0" ? null : parseInt(v, 10))}
              >
                <SelectTrigger className="w-[200px]"><SelectValue placeholder="All products" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="0">All products</SelectItem>
                  {products.map((p) => <SelectItem key={p.waterProductId} value={String(p.waterProductId)}>{p.name}</SelectItem>)}
                </SelectContent>
              </Select>
              {/* #23: entry-source filter (default All). */}
              <Select value={sourceFilter} onValueChange={(v) => setSourceFilter(v as any)}>
                <SelectTrigger className="w-[160px]"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All entries</SelectItem>
                  <SelectItem value="manual">Manual only</SelectItem>
                  <SelectItem value="system">System only</SelectItem>
                </SelectContent>
              </Select>
              <WaterRecalculateStockButton items={rawItems} onDone={load} />
              <ReconcileProductStockButton products={products.map((p) => ({ id: p.waterProductId, name: p.name }))} reconcile={reconcileWaterProductStock} onDone={load} />
              <SetProductStockButton products={products.map((p) => ({ id: p.waterProductId, name: p.name, currentStock: p.stockOnHand }))} setStock={setWaterProductStock} onDone={load} />
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
                <div className="p-8 text-center text-slate-500">No stock movement recorded yet.</div>
              ) : (
                <MobileCardList
                  striped
                  defaultOpen
                  items={pg.pageItems}
                  pagination={pg.paginationProps}
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
                  highlights={(t) => [
                    { label: "Qty", value: t.quantity > 0 ? `+${t.quantity}` : t.quantity, accent: t.quantity < 0 ? "rose" : "emerald" },
                    { label: "Unit cost", value: t.unitCost?.toFixed(2) ?? "—", accent: "blue" },
                  ]}
                  details={(t) => [
                    { label: "Date", value: new Date(t.createdDate).toLocaleString() },
                    { label: "Type", value: t.txnType },
                    { label: "Source", value: isManualTxn(t.txnType)
                        ? <Badge className="bg-blue-100 text-blue-700">Manual</Badge>
                        : <Badge variant="outline">System</Badge> },
                    { label: "Note", value: t.note ?? "—" },
                  ]}
                  desktopTable={
                    <div className="overflow-x-auto">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          {(() => { const cs = sort.key, cd = sort.direction; return (<>
                          <SortableHeader label="Date" sortKey="createdDate" currentSort={cs} currentDirection={cd} onSort={onSort} />
                          <SortableHeader label="Product" sortKey="productName" currentSort={cs} currentDirection={cd} onSort={onSort} />
                          <SortableHeader label="Type" sortKey="txnType" currentSort={cs} currentDirection={cd} onSort={onSort} />
                          <SortableHeader label="Source" sortKey="txnType" currentSort={cs} currentDirection={cd} onSort={onSort} />
                          <SortableHeader label="Qty" sortKey="quantity" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                          <SortableHeader label="Unit cost" sortKey="unitCost" currentSort={cs} currentDirection={cd} onSort={onSort} className="text-right" />
                          <SortableHeader label="Note" sortKey="note" currentSort={cs} currentDirection={cd} onSort={onSort} />
                          </>) })()}
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {pg.pageItems.map((t) => (
                          <TableRow key={t.stockTxnId}>
                            <TableCell>{new Date(t.createdDate).toLocaleString()}</TableCell>
                            <TableCell>{t.productName}</TableCell>
                            <TableCell>{t.txnType}</TableCell>
                            <TableCell>{isManualTxn(t.txnType) ? <Badge className="bg-blue-100 text-blue-700">Manual</Badge> : <Badge variant="outline">System</Badge>}</TableCell>
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

      {/* #24: styled popup matching the other dialogs (FormSection layout). */}
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="w-[95vw] max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2"><Boxes className="w-5 h-5 text-sky-600" /> New stock entry</DialogTitle>
            <DialogDescription>Manually record a restock, adjustment, or return. Shows as a “Manual” entry on the list.</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <FormSection title="Stock entry" color="sky">
              <FormField label="Item *" full>
                <Select value={form.target} onValueChange={(v) => setForm({ ...form, target: v })}>
                  <SelectTrigger><SelectValue placeholder="Pick a finished product, raw material or supply…" /></SelectTrigger>
                  <SelectContent>
                    {products.length > 0 && (
                      <SelectGroup>
                        <SelectLabel>Finished products</SelectLabel>
                        {products.map((p) => <SelectItem key={`p${p.waterProductId}`} value={`p:${p.waterProductId}`}>{p.name}</SelectItem>)}
                      </SelectGroup>
                    )}
                    {rawItems.filter((i) => i.isActive).length > 0 && (
                      <SelectGroup>
                        <SelectLabel>Raw materials &amp; supplies</SelectLabel>
                        {rawItems.filter((i) => i.isActive).map((i) => (
                          <SelectItem key={`r${i.waterRawMaterialItemId}`} value={`r:${i.waterRawMaterialItemId}`}>
                            {i.itemName}{i.category ? ` — ${i.category}` : ""}
                          </SelectItem>
                        ))}
                      </SelectGroup>
                    )}
                  </SelectContent>
                </Select>
              </FormField>
              <FormField label="Type">
                <Select value={form.txnType} onValueChange={(v) => setForm({ ...form, txnType: v as any })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="Restock">Restock (add stock)</SelectItem>
                    <SelectItem value="Adjust">Adjust (signed)</SelectItem>
                    <SelectItem value="Return">Return (add back)</SelectItem>
                  </SelectContent>
                </Select>
              </FormField>
              <FormField label={`Quantity ${form.txnType === "Adjust" ? "(signed)" : ""}`}>
                <NumberInput value={form.quantity || ""} onChange={(e) => setForm({ ...form, quantity: parseInt(e.target.value || "0", 10) })} />
              </FormField>
              <FormField label="Unit cost (optional, for restocks)">
                <NumberInput step="0.01" min={0} value={form.unitCost ?? ""} onChange={(e) => setForm({ ...form, unitCost: e.target.value === "" ? undefined : parseFloat(e.target.value) })} />
              </FormField>
              <FormField label="Note" full>
                <Input value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} />
              </FormField>
            </FormSection>
            <div className="flex justify-end gap-3 pt-2">
              <Button type="button" variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
              <Button onClick={save} disabled={saving}>{saving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>) : "Save entry"}</Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}
