"use client"

// One purchase, read-only, with its Project / Contract box (483). Purchases had
// no detail page before; projects need one so a purchase's lines can be
// assigned or split after it was saved (e.g. 60 chairs to Contract A, 40 to B).

import { useEffect, useState } from "react"
import Link from "next/link"
import { useParams } from "next/navigation"
import { Loader2, Package, Pencil } from "lucide-react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ProjectPage } from "@/components/generic/projects/project-page"
import { ProjectAssignmentCard } from "@/components/generic/projects/project-assignment-card"
import { useFmt } from "@/lib/currency"
import { getPurchase, getProducts, type GenericPurchaseDetail, type GenericProduct } from "@/lib/api/generic"

export default function GenericPurchaseDetailPage() {
  const { id } = useParams<{ id: string }>()
  const fmt = useFmt()
  const [p, setP] = useState<GenericPurchaseDetail | null>(null)
  const [products, setProducts] = useState<GenericProduct[]>([])
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    getPurchase(Number(id)).then(setP).catch((e) => setError(e?.message ?? String(e)))
    getProducts().then(setProducts).catch(() => {})
  }, [id])

  const name = (pid: number) => products.find((x) => x.genericProductId === pid)?.productName ?? `Product #${pid}`

  return (
    <ProjectPage title={p ? (p.invoiceNumber || `Purchase #${p.genericPurchaseId}`) : "Purchase"} icon={<Package className="h-5 w-5 text-orange-600" />}
      back="/generic-purchases" projectsBanner={false} subtitle={p ? `${p.supplierName ?? "No supplier"} · ${p.purchaseDate?.slice(0, 10)}` : undefined}
      actions={p?.status === "Draft" ? <Button variant="outline" asChild><Link href={`/generic-purchases/new?edit=${p.genericPurchaseId}`}><Pencil className="mr-1 h-4 w-4" />Edit</Link></Button> : undefined}>
      {error ? <p className="text-sm text-rose-600">{error}</p> : !p ? <Loader2 className="h-5 w-5 animate-spin text-slate-400" /> : (
        <div className="grid gap-4 lg:grid-cols-3">
          <Card className="lg:col-span-2">
            <CardHeader className="flex flex-row items-center justify-between space-y-0">
              <CardTitle className="text-base">Lines</CardTitle><Badge variant="secondary">{p.status}</Badge>
            </CardHeader>
            <CardContent className="p-0">
              <Table>
                <TableHeader><TableRow><TableHead>Product</TableHead><TableHead className="text-right">Qty</TableHead><TableHead className="text-right">Unit cost</TableHead><TableHead className="text-right">Line total</TableHead></TableRow></TableHeader>
                <TableBody>{p.items.map((it, i) => (
                  <TableRow key={it.genericPurchaseItemId ?? i}>
                    <TableCell>{it.description || name(it.genericProductId)}</TableCell>
                    <TableCell className="text-right">{it.quantity} {it.purchaseUnit ?? ""}</TableCell>
                    <TableCell className="text-right">{fmt(it.unitCost)}</TableCell>
                    <TableCell className="text-right font-medium">{fmt(it.lineTotal ?? it.quantity * it.unitCost - (it.discountAmount ?? 0))}</TableCell>
                  </TableRow>
                ))}</TableBody>
              </Table>
              <div className="space-y-1 border-t p-4 text-sm">
                <div className="flex justify-between"><span className="text-slate-600">Total</span><b>{fmt(p.totalAmount)}</b></div>
                <div className="flex justify-between"><span className="text-slate-600">Paid</span><span className="text-emerald-700">{fmt(p.amountPaid)}</span></div>
                <div className="flex justify-between"><span className="text-slate-600">Still owed</span><span className={p.balance > 0 ? "font-semibold text-rose-700" : ""}>{fmt(p.balance)}</span></div>
              </div>
            </CardContent>
          </Card>
          <div className="space-y-4">
            <ProjectAssignmentCard documentType="Purchase" documentId={p.genericPurchaseId}
              note="Bought goods become a project cost only when they are sold or used. Supplier payments follow these lines."
              lines={p.items.filter((it) => it.genericPurchaseItemId).map((it) => ({
                lineId: it.genericPurchaseItemId!, description: it.description || name(it.genericProductId),
                quantity: it.quantity, amount: it.lineTotal ?? it.quantity * it.unitCost, unit: it.purchaseUnit,
              }))} />
            {p.notes && <Card><CardContent className="p-4 text-sm text-slate-700">{p.notes}</CardContent></Card>}
          </div>
        </div>
      )}
    </ProjectPage>
  )
}
