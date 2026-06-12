"use client"

import { useEffect, useState } from "react"
import Link from "next/link"
import { useParams, useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger } from "@/components/ui/alert-dialog"
import { ArrowLeft, Check, Loader2, Trash2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { approveSale, cancelSale, getSale, refundSale, type GenericSale } from "@/lib/api/generic"

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}

function statusBadgeClass(s: string) {
  switch (s) {
    case "Approved":  return "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"
    case "Cancelled": return "bg-rose-100 text-rose-800 hover:bg-rose-100"
    case "Refunded":  return "bg-amber-100 text-amber-800 hover:bg-amber-100"
    default:          return "bg-slate-100 text-slate-800 hover:bg-slate-100"
  }
}

export default function GenericSaleDetailPage() {
  const router = useRouter()
  const params = useParams<{ id: string }>()
  const id = Number(params.id)
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const [sale, setSale] = useState<GenericSale | null>(null)
  const [loading, setLoading] = useState(true)
  const [acting, setActing] = useState(false)

  const load = async () => {
    setLoading(true)
    try {
      setSale(await getSale(id))
    } catch (e: any) {
      toast({ title: "Could not load sale", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, id, router])

  const onApprove = async () => {
    setActing(true)
    try {
      await approveSale(id)
      toast({ title: `Sale #${id} approved`, description: "Inventory, cash and customer ledger updated." })
      await load()
    } catch (e: any) {
      toast({ title: "Approve failed", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setActing(false) }
  }

  const onCancel = async () => {
    setActing(true)
    try {
      await cancelSale(id)
      toast({ title: `Sale #${id} cancelled.` })
      await load()
    } catch (e: any) {
      toast({ title: "Cancel failed", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setActing(false) }
  }

  const onRefund = async () => {
    setActing(true)
    try {
      await refundSale(id)
      toast({ title: `Sale #${id} refunded`, description: "Stock + cash + customer ledger reversed." })
      await load()
    } catch (e: any) {
      toast({ title: "Refund failed", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setActing(false) }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <Link href="/generic-sales" className="inline-flex items-center text-sm text-slate-500 hover:text-slate-700 mb-2">
            <ArrowLeft className="h-3 w-3 mr-1" /> Back to sales
          </Link>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : !sale ? (
            <Card><CardContent className="py-8 text-center text-slate-500">Sale not found.</CardContent></Card>
          ) : (
            <>
              <div className="mb-4 flex items-start justify-between flex-wrap gap-2">
                <div>
                  <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                    Sale #{sale.genericSaleId}
                    <Badge className={statusBadgeClass(sale.status)}>{sale.status}</Badge>
                  </h1>
                  <p className="text-sm text-slate-500">{new Date(sale.saleDate).toLocaleString()}</p>
                </div>
                <div className="flex gap-2">
                  {sale.status === "Draft" && (
                    <>
                      <Button onClick={onApprove} disabled={acting} className="bg-emerald-600 hover:bg-emerald-700">
                        {acting ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <Check className="h-4 w-4 mr-1" />}
                        Approve
                      </Button>
                      <AlertDialog>
                        <AlertDialogTrigger asChild>
                          <Button variant="outline" disabled={acting}><Trash2 className="h-4 w-4 mr-1" />Cancel</Button>
                        </AlertDialogTrigger>
                        <AlertDialogContent>
                          <AlertDialogHeader>
                            <AlertDialogTitle>Cancel this draft sale?</AlertDialogTitle>
                            <AlertDialogDescription>This marks the sale as Cancelled. It has no inventory or cash impact (the sale was never approved).</AlertDialogDescription>
                          </AlertDialogHeader>
                          <AlertDialogFooter>
                            <AlertDialogCancel>Keep it</AlertDialogCancel>
                            <AlertDialogAction onClick={onCancel}>Yes, cancel</AlertDialogAction>
                          </AlertDialogFooter>
                        </AlertDialogContent>
                      </AlertDialog>
                    </>
                  )}
                  {sale.status === "Approved" && (
                    <AlertDialog>
                      <AlertDialogTrigger asChild>
                        <Button variant="outline" disabled={acting}>Refund</Button>
                      </AlertDialogTrigger>
                      <AlertDialogContent>
                        <AlertDialogHeader>
                          <AlertDialogTitle>Refund this sale?</AlertDialogTitle>
                          <AlertDialogDescription>
                            This will return inventory to stock, refund the cash from the receiving account, and reverse any credit on the customer ledger. All three are atomic.
                          </AlertDialogDescription>
                        </AlertDialogHeader>
                        <AlertDialogFooter>
                          <AlertDialogCancel>Cancel</AlertDialogCancel>
                          <AlertDialogAction onClick={onRefund}>Yes, refund</AlertDialogAction>
                        </AlertDialogFooter>
                      </AlertDialogContent>
                    </AlertDialog>
                  )}
                </div>
              </div>

              <div className="grid grid-cols-1 lg:grid-cols-7 gap-4">
                <Card className="lg:col-span-4">
                  <CardHeader className="pb-1"><CardTitle className="text-xs uppercase tracking-wide text-slate-500">Items</CardTitle></CardHeader>
                  <CardContent className="p-0">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Type</TableHead>
                          <TableHead>Description</TableHead>
                          <TableHead className="text-right">Qty</TableHead>
                          <TableHead className="text-right">Unit price</TableHead>
                          <TableHead className="text-right">Discount</TableHead>
                          <TableHead className="text-right">Line total</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {sale.items.map((i) => (
                          <TableRow key={i.genericSaleItemId}>
                            <TableCell className="text-xs text-slate-500">{i.itemType}</TableCell>
                            <TableCell>{i.description ?? (i.genericProductId ? `Product #${i.genericProductId}` : `Service #${i.genericServiceId}`)}</TableCell>
                            <TableCell className="text-right">{i.quantity}</TableCell>
                            <TableCell className="text-right">{fmt(i.unitPrice)}</TableCell>
                            <TableCell className="text-right">{fmt(i.discountAmount)}</TableCell>
                            <TableCell className="text-right font-semibold">{fmt(i.lineTotal ?? 0)}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </CardContent>
                </Card>

                <div className="lg:col-span-3 space-y-4">
                  <Card>
                    <CardHeader className="pb-1"><CardTitle className="text-xs uppercase tracking-wide text-slate-500">Totals</CardTitle></CardHeader>
                    <CardContent>
                      <dl className="space-y-1 text-sm">
                        <Row label="Subtotal" value={fmt(sale.subtotalAmount)} />
                        <Row label="Discount" value={fmt(sale.discountAmount)} />
                        <Row label="Tax"      value={fmt(sale.taxAmount)} />
                        <Row label="Total"    value={fmt(sale.totalAmount)} bold />
                        <Row label={`Paid (${sale.paymentMethod ?? "—"})`} value={fmt(sale.amountPaid)} valueClass="text-emerald-700" />
                        <Row label="Balance"  value={fmt(sale.balance)} valueClass={sale.balance > 0 ? "text-rose-700 font-bold" : ""} />
                      </dl>
                    </CardContent>
                  </Card>

                  <Card>
                    <CardHeader className="pb-1"><CardTitle className="text-xs uppercase tracking-wide text-slate-500">Header</CardTitle></CardHeader>
                    <CardContent className="text-sm space-y-1">
                      <div>Customer: <strong>{sale.customerName ?? "Walk-in"}</strong></div>
                      <div>Type: {sale.salesType}{sale.salesChannel ? ` / ${sale.salesChannel}` : ""}</div>
                      <div>Receipt: {sale.receiptNumber ?? "—"}</div>
                      <div>Payment status: <strong>{sale.paymentStatus}</strong></div>
                      {sale.notes && <><hr className="my-2" /><div>{sale.notes}</div></>}
                    </CardContent>
                  </Card>
                </div>
              </div>
            </>
          )}
        </main>
      </div>
    </div>
  )
}

function Row({ label, value, bold = false, valueClass = "" }: { label: string; value: string; bold?: boolean; valueClass?: string }) {
  return (
    <div className="flex justify-between">
      <dt className={bold ? "font-semibold" : "text-slate-600"}>{label}</dt>
      <dd className={`${bold ? "font-semibold" : ""} ${valueClass}`}>{value}</dd>
    </div>
  )
}
