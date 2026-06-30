"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Badge } from "@/components/ui/badge"
import { Loader2, Boxes, Box, AlertTriangle } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { listPoultryProducts, listPoultryRawMaterialItems, type PoultryProduct, type PoultryRawMaterialItem } from "@/lib/api/poultry-inventory"

export default function PoultryInventoryPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const gh = useFmt()
  const [products, setProducts] = useState<PoultryProduct[]>([])
  const [items, setItems] = useState<PoultryRawMaterialItem[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") { router.replace("/dashboard"); return }
    ;(async () => {
      try { const [ps, is] = await Promise.all([listPoultryProducts(), listPoultryRawMaterialItems()]); setProducts(ps); setItems(is) }
      catch (e: any) { toast({ title: "Could not load inventory", description: e?.message, variant: "destructive" }) }
      finally { setLoading(false) }
    })()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  const lowRaw = useMemo(() => items.filter((i) => i.isActive && i.isLowStock).length, [items])
  const stat = (label: string, value: string | number, cls = "") => (
    <Card><CardContent className="p-4"><div className="text-sm text-slate-500">{label}</div><div className={`text-2xl font-bold ${cls}`}>{value}</div></CardContent></Card>
  )

  return (
    <div className="flex min-h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 p-4 sm:p-6 space-y-4">
          <div><h1 className="text-2xl font-bold">Inventory</h1><p className="text-sm text-slate-500">Finished products and raw materials at a glance.</p></div>
          {loading ? <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="w-4 h-4 animate-spin" /> Loading…</div> : (
            <>
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                {stat("Finished products", products.length)}
                {stat("Raw material items", items.length)}
                {stat("Low-stock raw items", lowRaw, lowRaw > 0 ? "text-amber-600" : "")}
                {stat("Total finished stock", products.reduce((s, p) => s + (p.stockOnHand || 0), 0).toLocaleString())}
              </div>
              <Tabs defaultValue="finished">
                <TabsList>
                  <TabsTrigger value="finished"><Boxes className="w-4 h-4 mr-1" /> Finished products</TabsTrigger>
                  <TabsTrigger value="raw"><Box className="w-4 h-4 mr-1" /> Raw materials</TabsTrigger>
                </TabsList>
                <TabsContent value="finished">
                  <Card><CardContent className="p-4">
                    <Table>
                      <TableHeader><TableRow><TableHead>Product</TableHead><TableHead>Type</TableHead><TableHead className="text-right">Stock on hand</TableHead><TableHead className="text-right">Price</TableHead></TableRow></TableHeader>
                      <TableBody>
                        {products.length === 0 ? <TableRow><TableCell colSpan={4} className="text-center text-slate-500 py-6">No products.</TableCell></TableRow>
                          : products.map((p) => (
                            <TableRow key={p.poultryProductId}><TableCell className="font-medium">{p.name}</TableCell><TableCell>{p.productType}</TableCell><TableCell className="text-right">{p.stockOnHand.toLocaleString()} {p.unit ?? ""}</TableCell><TableCell className="text-right">{gh(p.unitPrice)}</TableCell></TableRow>
                          ))}
                      </TableBody>
                    </Table>
                  </CardContent></Card>
                </TabsContent>
                <TabsContent value="raw">
                  <Card><CardContent className="p-4">
                    <Table>
                      <TableHeader><TableRow><TableHead>Item</TableHead><TableHead>Category</TableHead><TableHead className="text-right">In stock</TableHead><TableHead>Status</TableHead></TableRow></TableHeader>
                      <TableBody>
                        {items.length === 0 ? <TableRow><TableCell colSpan={4} className="text-center text-slate-500 py-6">No raw materials.</TableCell></TableRow>
                          : items.map((i) => (
                            <TableRow key={i.poultryRawMaterialItemId}>
                              <TableCell className="font-medium">{i.itemName}</TableCell><TableCell>{i.category}</TableCell>
                              <TableCell className="text-right">{i.currentQuantity.toLocaleString()} {i.unitOfMeasure ?? ""}</TableCell>
                              <TableCell>{i.isLowStock ? <Badge className="bg-amber-100 text-amber-700"><AlertTriangle className="w-3 h-3 mr-1" />Low</Badge> : <Badge className="bg-green-100 text-green-700">OK</Badge>}</TableCell>
                            </TableRow>
                          ))}
                      </TableBody>
                    </Table>
                  </CardContent></Card>
                </TabsContent>
              </Tabs>
            </>
          )}
        </main>
      </div>
    </div>
  )
}
