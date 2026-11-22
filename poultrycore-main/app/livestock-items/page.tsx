"use client"

// Feed & Stock -- feed, medication, vaccines and supplies, with what is in
// stock and its value at average cost. The poultry raw-materials / feed
// inventory page for livestock.

import { Suspense, useCallback, useEffect, useMemo, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { AlertTriangle, Boxes, Plus, ShoppingCart } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { listItems, listPurchases, type ItemCategory, type LivestockItem, type Purchase } from "@/lib/api/livestock"
import { PurchaseTotals, PurchasesTable } from "@/components/livestock/purchases-table"
import { ItemFormDialog, StockChangeDialog, CATEGORY_LABEL } from "@/components/livestock/stock-dialogs"
import { ItemPurchaseDialog } from "@/components/livestock/item-purchase-dialog"
import {
  AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, StatCard, fmtMoney, fmtNum, todayIso,
} from "@/components/livestock/livestock-page"

type Tab = "all" | "Feed" | "Ingredient" | "Health" | "Supply" | "Produce"
type View = "stock" | "purchases"

const daysAgo = (n: number) => { const d = new Date(); d.setDate(d.getDate() - n); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}` }

// useSearchParams (the ?tab= view) needs a Suspense boundary for the build.
export default function LivestockItemsPage() {
  return <Suspense fallback={null}><LivestockItemsView /></Suspense>
}

function LivestockItemsView() {
  const router = useRouter()
  // ?tab=purchases opens the Purchases view (like poultry's Supply Purchases tabs).
  const searchParams = useSearchParams()
  const view: View = searchParams.get("tab") === "purchases" ? "purchases" : "stock"
  const setView = (v: View) => router.replace(v === "stock" ? "/livestock-items" : "/livestock-items?tab=purchases", { scroll: false })
  const [purchases, setPurchases] = useState<Purchase[] | null>(null)
  const [purchaseError, setPurchaseError] = useState<string | null>(null)
  const [from, setFrom] = useState(daysAgo(60))
  const [to, setTo] = useState(todayIso())
  const [items, setItems] = useState<LivestockItem[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [tab, setTab] = useState<Tab>("all")
  const [creating, setCreating] = useState(false)
  const [changing, setChanging] = useState<LivestockItem | null>(null)
  // Record purchase: open, and the item to start with ("Buy" on a row).
  const [buying, setBuying] = useState<{ itemId: number | null } | null>(null)

  const load = useCallback(async () => {
    setError(null)
    try { setItems(await listItems(undefined, true)) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [])
  useEffect(() => { load() }, [load])

  // ?purchase=1[&itemId=N] (Operations > Purchase > Record purchase) opens the
  // purchase dialog straight away, then drops the flag so a refresh does not
  // open it again.
  useEffect(() => {
    if (searchParams.get("purchase") !== "1") return
    setBuying({ itemId: Number(searchParams.get("itemId")) || null })
    router.replace(view === "purchases" ? "/livestock-items?tab=purchases" : "/livestock-items", { scroll: false })
  }, [searchParams]) // eslint-disable-line react-hooks/exhaustive-deps

  // Purchases with stock on them: Feed & stock only shows what came into stock.
  const loadPurchases = useCallback(async () => {
    setPurchaseError(null)
    try {
      const rows = await listPurchases({ from, to })
      setPurchases(rows.filter((p) => p.lines.some((l) => l.lineType === "Item")))
    } catch (e: any) { setPurchaseError(e?.message ?? String(e)) }
  }, [from, to])
  useEffect(() => { if (view === "purchases") loadPurchases() }, [view, loadPurchases])

  const shown = useMemo(() => (items ?? []).filter((i) =>
    tab === "all" ? true
      : tab === "Health" ? i.category === "Medication" || i.category === "Vaccine"
      : tab === "Supply" ? i.category === "Supply" || i.category === "Other"
      : i.category === tab), [items, tab])
  const value = shown.reduce((s, i) => s + i.value, 0)
  const low = shown.filter((i) => i.isActive && i.isLow)

  return (
    <LivestockPage
      title="Feed & stock"
      description="Feed, medicine, vaccines and supplies on hand, valued at average cost."
      icon={Boxes}
      actions={
        <div className="flex gap-2">
          <Button variant="outline" onClick={() => setCreating(true)}><Plus className="h-4 w-4 mr-1" /> Add item</Button>
          <Button className={AMBER_BUTTON} onClick={() => setBuying({ itemId: null })}><ShoppingCart className="h-4 w-4 mr-1" /> Record purchase</Button>
        </div>
      }
    >
      <Tabs value={view} onValueChange={(v) => setView(v as View)}>
        <TabsList>
          <TabsTrigger value="stock">Stock</TabsTrigger>
          <TabsTrigger value="purchases">Purchases</TabsTrigger>
        </TabsList>
      </Tabs>

      {view === "purchases" ? (
        <>
          <div className="flex items-center gap-3 flex-wrap">
            <Input type="date" className="w-40" value={from} max={to} onChange={(e) => setFrom(e.target.value)} aria-label="From" />
            <span className="text-sm text-stone-500">to</span>
            <Input type="date" className="w-40" value={to} min={from} max={todayIso()} onChange={(e) => setTo(e.target.value)} aria-label="To" />
          </div>
          <PurchaseTotals rows={purchases ?? []} boughtLabel="Bought in these dates" />
          {purchaseError ? <LoadError message={purchaseError} onRetry={loadPurchases} /> : !purchases ? <Loading /> : purchases.length === 0 ? (
            <EmptyState title="No stock bought in these dates">Use Record purchase to buy feed, medicine or supplies.</EmptyState>
          ) : (
            <PurchasesTable rows={purchases} itemsOnly />
          )}
        </>
      ) : (
        <>
          <div className="grid grid-cols-2 lg:grid-cols-3 gap-3">
            <StatCard label="Stock value" value={fmtMoney(value)} tone="amber" />
            <StatCard label="Items" value={fmtNum(shown.filter((i) => i.isActive).length)} />
            <StatCard label="Running low" value={fmtNum(low.length)} tone={low.length ? "rose" : "stone"}
              hint={low.length ? low.slice(0, 3).map((i) => i.name).join(", ") : undefined} />
          </div>

          <Tabs value={tab} onValueChange={(v) => setTab(v as Tab)}>
            <TabsList>
              <TabsTrigger value="all">All</TabsTrigger>
              <TabsTrigger value="Feed">Feed</TabsTrigger>
              <TabsTrigger value="Ingredient">Ingredients</TabsTrigger>
              <TabsTrigger value="Health">Medicine & vaccines</TabsTrigger>
              <TabsTrigger value="Supply">Supplies</TabsTrigger>
              <TabsTrigger value="Produce">Produce</TabsTrigger>
            </TabsList>
          </Tabs>

          {error ? <LoadError message={error} onRetry={load} /> : !items ? <Loading /> : shown.length === 0 ? (
            <EmptyState title="No stock items yet">Add your feeds, medicines and supplies so daily records can take them out of stock.</EmptyState>
          ) : (
            <div className="rounded-md border bg-white overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Item</TableHead>
                    <TableHead>Kind</TableHead>
                    <TableHead>For</TableHead>
                    <TableHead className="text-right">In stock</TableHead>
                    <TableHead className="text-right">Average cost</TableHead>
                    <TableHead className="text-right">Value</TableHead>
                    <TableHead />
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {shown.map((i) => (
                    <TableRow key={i.itemId} className={`cursor-pointer hover:bg-amber-50/60 ${i.isActive ? "" : "opacity-60"}`}
                      onClick={() => router.push(`/livestock-items/${i.itemId}`)}>
                      <TableCell className="font-medium">
                        {i.name}
                        {!i.isActive && <Badge variant="outline" className="ml-2">Unused</Badge>}
                      </TableCell>
                      <TableCell>{CATEGORY_LABEL[i.category as ItemCategory]}</TableCell>
                      <TableCell>{i.speciesName ?? "Any"}</TableCell>
                      <TableCell className={`text-right ${i.isLow ? "text-rose-700 font-medium" : ""}`}>
                        {i.isLow && <AlertTriangle className="inline h-3.5 w-3.5 mr-1" />}
                        {fmtNum(i.stock)} {i.unit}
                      </TableCell>
                      <TableCell className="text-right">{i.avgCost == null ? "—" : fmtMoney(i.avgCost)}</TableCell>
                      <TableCell className="text-right">{fmtMoney(i.value)}</TableCell>
                      <TableCell className="text-right">
                        {i.isActive && (
                          <div className="flex justify-end gap-2">
                            <Button variant="outline" size="sm" onClick={(e) => { e.stopPropagation(); setBuying({ itemId: i.itemId }) }}>
                              <ShoppingCart className="h-3.5 w-3.5 mr-1" /> Buy
                            </Button>
                            <Button variant="outline" size="sm" onClick={(e) => { e.stopPropagation(); setChanging(i) }}>Correct count</Button>
                          </div>
                        )}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </>
      )}

      <ItemFormDialog open={creating} onOpenChange={setCreating}
        defaultCategory={tab === "Health" ? "Medication" : tab === "Supply" ? "Supply" : tab === "Ingredient" ? "Ingredient" : "Feed"} onSaved={load} />
      <ItemPurchaseDialog open={!!buying} onOpenChange={(o) => !o && setBuying(null)} presetItemId={buying?.itemId ?? null}
        items={(items ?? []).filter((i) => i.isActive)} onSaved={() => { load(); if (view === "purchases") loadPurchases() }} />
      {changing && <StockChangeDialog item={changing} onClose={() => setChanging(null)} onDone={() => { setChanging(null); load() }} />}
    </LivestockPage>
  )
}
