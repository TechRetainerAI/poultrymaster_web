"use client"

// Feed & Stock -- feed, medication, vaccines and supplies, with what is in
// stock and its value at average cost. The poultry raw-materials / feed
// inventory page for livestock.

import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { AlertTriangle, Boxes, Plus } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { listItems, type ItemCategory, type LivestockItem } from "@/lib/api/livestock"
import { ItemFormDialog, StockChangeDialog, CATEGORY_LABEL } from "@/components/livestock/stock-dialogs"
import {
  AMBER_BUTTON, EmptyState, LivestockPage, LoadError, Loading, StatCard, fmtMoney, fmtNum,
} from "@/components/livestock/livestock-page"

type Tab = "all" | "Feed" | "Ingredient" | "Health" | "Supply" | "Produce"

export default function LivestockItemsPage() {
  const router = useRouter()
  const [items, setItems] = useState<LivestockItem[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [tab, setTab] = useState<Tab>("all")
  const [creating, setCreating] = useState(false)
  const [changing, setChanging] = useState<LivestockItem | null>(null)

  const load = useCallback(async () => {
    setError(null)
    try { setItems(await listItems(undefined, true)) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [])
  useEffect(() => { load() }, [load])

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
      actions={<Button className={AMBER_BUTTON} onClick={() => setCreating(true)}><Plus className="h-4 w-4 mr-1" /> Add item</Button>}
    >
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
                      <Button variant="outline" size="sm" onClick={(e) => { e.stopPropagation(); setChanging(i) }}>Add / correct</Button>
                    )}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}

      <ItemFormDialog open={creating} onOpenChange={setCreating}
        defaultCategory={tab === "Health" ? "Medication" : tab === "Supply" ? "Supply" : tab === "Ingredient" ? "Ingredient" : "Feed"} onSaved={load} />
      {changing && <StockChangeDialog item={changing} onClose={() => setChanging(null)} onDone={() => { setChanging(null); load() }} />}
    </LivestockPage>
  )
}
