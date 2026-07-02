"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Badge } from "@/components/ui/badge"
import { Loader2, AlertTriangle } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import Link from "next/link"
import { listPoultryProducts, listPoultryRawMaterialItems, ensurePoultryDefaults, type PoultryProduct, type PoultryRawMaterialItem } from "@/lib/api/poultry-inventory"

type Row = {
  key: string; seq: number; parentType: "Finished Product" | "Raw Material"
  id: number; name: string; type: string; size: string | null; unit: string | null
  unitPrice: number | null; stock: number; low: boolean; active: boolean
  isEgg?: boolean; isBird?: boolean
}

// Doc 2 §3-5: Details link routes to the right tracker, filtered by the item.
function detailLink(r: Row): { href: string; label: string } {
  if (r.parentType === "Finished Product") {
    if (r.isEgg) return { href: `/egg-tracker?inventoryItemId=${r.id}`, label: "View Egg Tracker" }
    if (r.isBird) return { href: `/birds-left-tracker?inventoryItemId=${r.id}`, label: "View Birds Tracker" }
    return { href: `/poultry-stock?productId=${r.id}`, label: "View Stock" }
  }
  if (r.type === "FeedIngredient") return { href: `/feed-tracker?inventoryItemId=${r.id}`, label: "View Feed Tracker" }
  if (r.type === "Medication" || r.type === "Vaccine") return { href: `/medication-tracker?inventoryItemId=${r.id}`, label: "View Medication Tracker" }
  return { href: `/poultry-stock?rawId=${r.id}`, label: "View Details" }
}

export default function PoultryInventoryPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const gh = useFmt()
  const [products, setProducts] = useState<PoultryProduct[]>([])
  const [items, setItems] = useState<PoultryRawMaterialItem[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState("")

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    ;(async () => {
      try {
        await ensurePoultryDefaults().catch(() => {})   // doc: Eggs + Birds defaults visible in inventory
        const [ps, is] = await Promise.all([listPoultryProducts(), listPoultryRawMaterialItems()]); setProducts(ps); setItems(is)
      }
      catch (e: any) { toast({ title: "Could not load inventory", description: e?.message, variant: "destructive" }) }
      finally { setLoading(false) }
    })()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  // doc 2/3/8: one table, Finished Products first (seq 1), then Raw Materials (seq 2).
  const rows: Row[] = useMemo(() => {
    const fin: Row[] = products.map((p) => ({ key: `p${p.poultryProductId}`, seq: 1, parentType: "Finished Product", id: p.poultryProductId, name: p.name, type: p.productType, size: p.size ?? null, unit: p.unit ?? null, unitPrice: p.unitPrice, stock: p.stockOnHand, low: false, active: p.isActive, isEgg: p.isRawEggProduct, isBird: p.isBirdProduct }))
    const raw: Row[] = items.map((i) => ({ key: `r${i.poultryRawMaterialItemId}`, seq: 2, parentType: "Raw Material", id: i.poultryRawMaterialItemId, name: i.itemName, type: i.category, size: null, unit: i.unitOfMeasure ?? null, unitPrice: null, stock: i.currentQuantity, low: !!i.isLowStock, active: i.isActive }))
    const all = [...fin, ...raw]
    const q = search.trim().toLowerCase()
    const filtered = q ? all.filter((r) => r.name.toLowerCase().includes(q) || r.type.toLowerCase().includes(q) || r.parentType.toLowerCase().includes(q)) : all
    return filtered.sort((a, b) => a.seq - b.seq || a.name.localeCompare(b.name))
  }, [products, items, search])

  const lowRaw = items.filter((i) => i.isActive && i.isLowStock).length
  const stat = (label: string, value: string | number, cls = "") => (
    <Card><CardContent className="p-4"><div className="text-sm text-slate-500">{label}</div><div className={`text-2xl font-bold ${cls}`}>{value}</div></CardContent></Card>
  )

  return (
    <div className="flex min-h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 p-4 sm:p-6 space-y-4">
          <div><h1 className="text-2xl font-bold">Inventory</h1><p className="text-sm text-slate-500">All finished products and raw materials in one view. Finished products first.</p></div>
          {loading ? <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div> : (
            <>
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                {stat("Finished products", products.length)}
                {stat("Raw material items", items.length)}
                {stat("Low-stock raw items", lowRaw, lowRaw > 0 ? "text-amber-600" : "")}
                {stat("Total finished stock", products.reduce((s, p) => s + (p.stockOnHand || 0), 0).toLocaleString())}
              </div>
              <Card><CardContent className="p-4 space-y-3">
                <Input placeholder="Search inventory…" value={search} onChange={(e) => setSearch(e.target.value)} className="max-w-xs" />
                <Table>
                  <TableHeader><TableRow>
                    <TableHead>Item</TableHead><TableHead>Parent Type</TableHead><TableHead>Type / Category</TableHead>
                    <TableHead>Size</TableHead><TableHead>Unit</TableHead><TableHead className="text-right">Unit Price</TableHead>
                    <TableHead className="text-right">In stock</TableHead><TableHead>Status</TableHead><TableHead>Details</TableHead>
                  </TableRow></TableHeader>
                  <TableBody>
                    {rows.length === 0 ? <TableRow><TableCell colSpan={9} className="text-center text-slate-500 py-6">No inventory yet.</TableCell></TableRow>
                      : rows.map((r) => (
                        <TableRow key={r.key}>
                          <TableCell className="font-medium">{r.name}</TableCell>
                          <TableCell><Badge className={r.parentType === "Finished Product" ? "bg-blue-100 text-blue-700" : "bg-slate-100 text-slate-700"}>{r.parentType}</Badge></TableCell>
                          <TableCell>{r.type}</TableCell>
                          <TableCell>{r.size ?? "—"}</TableCell>
                          <TableCell>{r.unit ?? "—"}</TableCell>
                          <TableCell className="text-right">{r.unitPrice != null ? gh(r.unitPrice) : "—"}</TableCell>
                          <TableCell className="text-right">{r.stock.toLocaleString()}</TableCell>
                          <TableCell>{!r.active ? <Badge variant="secondary">Inactive</Badge> : r.low ? <Badge className="bg-amber-100 text-amber-700"><AlertTriangle className="w-3 h-3 mr-1" />Low</Badge> : <Badge className="bg-green-100 text-green-700">OK</Badge>}</TableCell>
                          <TableCell>{(() => { const l = detailLink(r); return <Link href={l.href} className="text-blue-600 hover:underline text-sm whitespace-nowrap">{l.label}</Link> })()}</TableCell>
                        </TableRow>
                      ))}
                  </TableBody>
                </Table>
              </CardContent></Card>
            </>
          )}
        </main>
      </div>
    </div>
  )
}
