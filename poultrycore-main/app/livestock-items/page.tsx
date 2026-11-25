"use client"

// Feed & Stock -- feed, medication, vaccines and supplies, with what is in
// stock and its value at average cost. The poultry raw-materials / feed
// inventory page for livestock.

import { Suspense, useCallback, useEffect, useMemo, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { AlertTriangle, Boxes, Leaf, Plus, ShoppingCart } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import {
  listForageCollections, listItems, listPurchases, reverseForageCollection,
  type ForageCollection, type ItemCategory, type LivestockItem, type Purchase,
} from "@/lib/api/livestock"
import { PurchaseTotals, PurchasesTable } from "@/components/livestock/purchases-table"
import { ItemFormDialog, StockChangeDialog, CATEGORY_LABEL } from "@/components/livestock/stock-dialogs"
import { ItemPurchaseDialog } from "@/components/livestock/item-purchase-dialog"
import { ForageCollectDialog } from "@/components/livestock/forage-collect-dialog"
import { PromptDialog } from "@/components/ui/prompt-dialog"
import {
  AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, StatCard, fmtDate, fmtMoney, fmtNum, todayIso,
} from "@/components/livestock/livestock-page"

type Tab = "all" | "Feed" | "Ingredient" | "Health" | "Supply" | "Produce"
type View = "stock" | "purchases" | "collected"

const daysAgo = (n: number) => { const d = new Date(); d.setDate(d.getDate() - n); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}` }

// useSearchParams (the ?tab= view) needs a Suspense boundary for the build.
export default function LivestockItemsPage() {
  return <Suspense fallback={null}><LivestockItemsView /></Suspense>
}

function LivestockItemsView() {
  const router = useRouter()
  // ?tab=purchases opens the Purchases view (like poultry's Supply Purchases tabs).
  const searchParams = useSearchParams()
  const tabParam = searchParams.get("tab")
  const view: View = tabParam === "purchases" ? "purchases" : tabParam === "collected" ? "collected" : "stock"
  const setView = (v: View) => router.replace(v === "stock" ? "/livestock-items" : `/livestock-items?tab=${v}`, { scroll: false })
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
  // 494: Collect feed (forest / bush forage): open, and the item to start with.
  const [collecting, setCollecting] = useState<{ itemId: number | null } | null>(null)
  const [collections, setCollections] = useState<ForageCollection[] | null>(null)
  const [collectionError, setCollectionError] = useState<string | null>(null)
  const [reversing, setReversing] = useState<ForageCollection | null>(null)

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

  const loadCollections = useCallback(async () => {
    setCollectionError(null)
    try { setCollections(await listForageCollections({ from, to })) } catch (e: any) { setCollectionError(e?.message ?? String(e)) }
  }, [from, to])
  useEffect(() => { if (view === "collected") loadCollections() }, [view, loadCollections])
  const forageItems = useMemo(() => (items ?? []).filter((i) => i.isActive && i.isForage), [items])
  const liveCollections = (collections ?? []).filter((c) => !c.reversedAt)

  const shown = useMemo(() => (items ?? []).filter((i) =>
    tab === "all" ? true
      : tab === "Health" ? i.category === "Medication" || i.category === "Vaccine"
      : tab === "Supply" ? i.category === "Supply" || i.category === "Other"
      : i.category === tab), [items, tab])
  const pg = usePagination(shown, 10)
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
          <Button variant="outline" onClick={() => setCollecting({ itemId: null })}><Leaf className="h-4 w-4 mr-1" /> Collect feed</Button>
          <Button className={AMBER_BUTTON} onClick={() => setBuying({ itemId: null })}><ShoppingCart className="h-4 w-4 mr-1" /> Record purchase</Button>
        </div>
      }
    >
      <Tabs value={view} onValueChange={(v) => setView(v as View)}>
        <TabsList>
          <TabsTrigger value="stock">Stock</TabsTrigger>
          <TabsTrigger value="purchases">Purchases</TabsTrigger>
          <TabsTrigger value="collected">Collected</TabsTrigger>
        </TabsList>
      </Tabs>

      {view === "collected" ? (
        <>
          <div className="flex items-center gap-3 flex-wrap">
            <Input type="date" className="w-40" value={from} max={to} onChange={(e) => setFrom(e.target.value)} aria-label="From" />
            <span className="text-sm text-stone-500">to</span>
            <Input type="date" className="w-40" value={to} min={from} max={todayIso()} onChange={(e) => setTo(e.target.value)} aria-label="To" />
          </div>
          <div className="grid grid-cols-2 lg:grid-cols-3 gap-3">
            <StatCard label="Times collected" value={fmtNum(liveCollections.length)} tone="amber" />
            <StatCard label="Brought back" value={liveCollections.some((c) => c.kg != null) ? `${fmtNum(liveCollections.reduce((t, c) => t + (c.kg ?? 0), 0))} kg` : "—"}
              hint={liveCollections.some((c) => c.kg == null) ? "Items without kg per unit not counted" : undefined} />
            <StatCard label="Spent collecting" value={fmtMoney(liveCollections.reduce((t, c) => t + c.cost, 0))} />
          </div>
          {collectionError ? <LoadError message={collectionError} onRetry={loadCollections} /> : !collections ? <Loading /> : collections.length === 0 ? (
            <EmptyState title="No feed collected in these dates">Use Collect feed when grass or leaves are brought back from the forest or bush.</EmptyState>
          ) : (
            <div className="rounded-md border bg-white overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Date</TableHead>
                    <TableHead>Feed</TableHead>
                    <TableHead className="text-right">Quantity</TableHead>
                    <TableHead>Where from</TableHead>
                    <TableHead>Collected by</TableHead>
                    <TableHead className="text-right">Cost</TableHead>
                    <TableHead>Paid from</TableHead>
                    <TableHead />
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {collections.map((c) => (
                    <TableRow key={c.collectionId} className={c.reversedAt ? "opacity-50" : undefined}>
                      <TableCell className="whitespace-nowrap">{fmtDate(c.date)}</TableCell>
                      <TableCell className="font-medium">
                        {c.itemName}{c.reversedAt && <Badge variant="outline" className="ml-2">Reversed</Badge>}
                        {c.reverseReason && <div className="text-xs font-normal text-stone-500">Reversed: {c.reverseReason}</div>}
                      </TableCell>
                      <TableCell className="text-right">
                        {fmtNum(c.quantity)} {c.unit}
                        {c.kg != null && c.unit !== "kg" && <div className="text-xs text-stone-500">{fmtNum(c.kg)} kg</div>}
                      </TableCell>
                      <TableCell>{c.place ?? "—"}</TableCell>
                      <TableCell>{c.collectedBy ?? "—"}</TableCell>
                      <TableCell className="text-right">{c.cost > 0 ? fmtMoney(c.cost) : <span className="text-stone-500">Free</span>}</TableCell>
                      <TableCell>{c.accountName ?? "—"}</TableCell>
                      <TableCell className="text-right">
                        {!c.reversedAt && <Button variant="ghost" size="sm" onClick={() => setReversing(c)}>Reverse</Button>}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </>
      ) : view === "purchases" ? (
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
                  {pg.pageItems.map((i) => (
                    <TableRow key={i.itemId} className={`cursor-pointer hover:bg-amber-50/60 ${i.isActive ? "" : "opacity-60"}`}
                      onClick={() => router.push(`/livestock-items/${i.itemId}`)}>
                      <TableCell className="font-medium">
                        {i.name}
                        {!i.isActive && <Badge variant="outline" className="ml-2">Unused</Badge>}
                      </TableCell>
                      <TableCell>{CATEGORY_LABEL[i.category as ItemCategory]}{i.isForage && <span className="text-stone-500"> · collected</span>}</TableCell>
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
                            {i.isForage ? (
                              <Button variant="outline" size="sm" onClick={(e) => { e.stopPropagation(); setCollecting({ itemId: i.itemId }) }}>
                                <Leaf className="h-3.5 w-3.5 mr-1" /> Collect
                              </Button>
                            ) : (
                              <Button variant="outline" size="sm" onClick={(e) => { e.stopPropagation(); setBuying({ itemId: i.itemId }) }}>
                                <ShoppingCart className="h-3.5 w-3.5 mr-1" /> Buy
                              </Button>
                            )}
                            <Button variant="outline" size="sm" onClick={(e) => { e.stopPropagation(); setChanging(i) }}>Correct count</Button>
                          </div>
                        )}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
              <DataPagination {...pg.paginationProps} variant="records" />
            </div>
          )}
        </>
      )}

      <ItemFormDialog open={creating} onOpenChange={setCreating}
        defaultCategory={tab === "Health" ? "Medication" : tab === "Supply" ? "Supply" : tab === "Ingredient" ? "Ingredient" : "Feed"} onSaved={load} />
      <ItemPurchaseDialog open={!!buying} onOpenChange={(o) => !o && setBuying(null)} presetItemId={buying?.itemId ?? null}
        items={(items ?? []).filter((i) => i.isActive)} onSaved={() => { load(); if (view === "purchases") loadPurchases() }} />
      <ForageCollectDialog open={!!collecting} onOpenChange={(o) => !o && setCollecting(null)} presetItemId={collecting?.itemId ?? null}
        items={forageItems} onSaved={() => { load(); if (view === "collected") loadCollections() }} />
      <PromptDialog
        open={!!reversing}
        onOpenChange={(o) => !o && setReversing(null)}
        title="Reverse this collection?"
        description={reversing ? `${fmtNum(reversing.quantity)} ${reversing.unit} of ${reversing.itemName} on ${fmtDate(reversing.date)}`
          + (reversing.cost > 0 ? `. The ${fmtMoney(reversing.cost)} goes back to ${reversing.accountName ?? "the cash account"}.` : ".") : undefined}
        label="Why"
        confirmLabel="Reverse"
        confirmVariant="destructive"
        onSubmit={async (reason) => { await reverseForageCollection(reversing!.collectionId, reason); setReversing(null); load(); loadCollections() }}
      />
      {changing && <StockChangeDialog item={changing} onClose={() => setChanging(null)} onDone={() => { setChanging(null); load() }} />}
    </LivestockPage>
  )
}
