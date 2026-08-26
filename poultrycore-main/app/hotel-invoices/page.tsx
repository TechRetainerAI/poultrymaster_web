"use client"
import { useEffect, useState, useRef } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Loader2, FileText, Printer } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listInvoices, type HotelInvoice } from "@/lib/api/hotel"

const STATUS_COLOR: Record<string, string> = { Draft: "bg-slate-100 text-slate-700", Issued: "bg-blue-100 text-blue-700", Paid: "bg-emerald-100 text-emerald-700", PartiallyPaid: "bg-amber-100 text-amber-700", Void: "bg-red-100 text-red-700" }

export default function HotelInvoicesPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmName = useAuthStore((s) => s.activeFarmName)
  const [items, setItems] = useState<HotelInvoice[]>([]); const [loading, setLoading] = useState(true)
  const [printInvoice, setPrintInvoice] = useState<any>(null)
  const printRef = useRef<HTMLDivElement>(null)

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])
  async function load() { setLoading(true); try { setItems(await listInvoices()) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setLoading(false) } }

  function handlePrint() {
    if (!printRef.current) return
    const win = window.open("", "_blank")
    if (!win) return
    win.document.write(`<html><head><title>Invoice ${printInvoice?.invoiceNumber ?? printInvoice?.invoicenumber}</title><style>body{font-family:Arial,sans-serif;padding:40px;color:#333}table{width:100%;border-collapse:collapse;margin:20px 0}th,td{padding:8px 12px;text-align:left;border-bottom:1px solid #eee}th{background:#f8f8f8;font-weight:600}.right{text-align:right}.bold{font-weight:bold}.header{border-bottom:2px solid #7c3aed;padding-bottom:15px;margin-bottom:20px}.total{font-size:1.2em;border-top:2px solid #333;padding-top:10px}.badge{display:inline-block;padding:2px 8px;border-radius:4px;font-size:12px}@media print{body{padding:20px}}</style></head><body>`)
    win.document.write(printRef.current.innerHTML)
    win.document.write("</body></html>")
    win.document.close()
    win.print()
  }

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center gap-3 mb-6"><FileText className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Invoices</h1><span className="text-sm text-slate-500">({items.length})</span></div>
        <p className="text-sm text-slate-500 mb-4">Invoices are generated from the Billing page. Click an invoice to preview and print.</p>
        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
          <Card><CardContent className="p-0"><table className="w-full text-sm"><thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">Invoice #</th><th className="text-left p-3">Date</th><th className="text-right p-3">Subtotal</th><th className="text-right p-3">Tax</th><th className="text-right p-3">Total</th><th className="text-right p-3">Paid</th><th className="text-right p-3">Balance</th><th className="text-left p-3">Status</th><th className="text-right p-3">Actions</th></tr></thead>
            <tbody>{items.map((i: any, idx: number) => (
              <tr key={i.hotelInvoiceId ?? i.hotelinvoiceid ?? `inv-${idx}`} className="border-b hover:bg-slate-50">
                <td className="p-3 font-mono font-semibold">{i.invoiceNumber ?? i.invoicenumber}</td>
                <td className="p-3">{(i.issuedDate ?? i.issueddate)?.slice?.(0,10)}</td>
                <td className="p-3 text-right">{Number(i.subTotal ?? i.subtotal ?? 0).toFixed(2)}</td>
                <td className="p-3 text-right">{Number(i.taxAmount ?? i.taxamount ?? 0).toFixed(2)}</td>
                <td className="p-3 text-right font-semibold">{Number(i.totalAmount ?? i.totalamount ?? 0).toFixed(2)}</td>
                <td className="p-3 text-right text-emerald-700">{Number(i.amountPaid ?? i.amountpaid ?? 0).toFixed(2)}</td>
                <td className={`p-3 text-right font-bold ${Number(i.balance ?? 0) > 0 ? "text-red-700" : "text-emerald-700"}`}>{Number(i.balance ?? 0).toFixed(2)}</td>
                <td className="p-3"><Badge variant="outline" className={STATUS_COLOR[i.status] ?? ""}>{i.status}</Badge></td>
                <td className="p-3 text-right"><Button variant="ghost" size="sm" onClick={() => setPrintInvoice(i)}><Printer className="h-4 w-4 mr-1" />Print</Button></td>
              </tr>
            ))}
              {items.length === 0 && <tr><td colSpan={9} className="p-8 text-center text-slate-400">No invoices yet. Generate one from the Billing page.</td></tr>}
            </tbody></table></CardContent></Card>
        )}

        {/* Print Preview Dialog */}
        <Dialog open={!!printInvoice} onOpenChange={() => setPrintInvoice(null)}>
          <DialogContent className="max-w-2xl">
            <DialogHeader><DialogTitle>Invoice Preview</DialogTitle></DialogHeader>
            <div ref={printRef} className="p-6 bg-white">
              <div className="header border-b-2 border-violet-600 pb-4 mb-6">
                <div className="flex justify-between items-start">
                  <div>
                    <h1 className="text-2xl font-bold text-violet-700">{activeFarmName}</h1>
                    <p className="text-sm text-slate-500">Hotel Management System</p>
                  </div>
                  <div className="text-right">
                    <h2 className="text-xl font-bold">INVOICE</h2>
                    <p className="font-mono text-lg">{printInvoice?.invoiceNumber ?? printInvoice?.invoicenumber}</p>
                    <p className="text-sm text-slate-500">Date: {(printInvoice?.issuedDate ?? printInvoice?.issueddate)?.slice?.(0,10)}</p>
                  </div>
                </div>
              </div>
              <table className="w-full mb-6" style={{borderCollapse:"collapse"}}>
                <tbody>
                  <tr style={{borderBottom:"1px solid #eee"}}><td className="py-2 text-slate-500" style={{padding:"8px"}}>Subtotal</td><td className="py-2 text-right font-semibold" style={{padding:"8px",textAlign:"right"}}>{Number(printInvoice?.subTotal ?? printInvoice?.subtotal ?? 0).toFixed(2)}</td></tr>
                  <tr style={{borderBottom:"1px solid #eee"}}><td className="py-2 text-slate-500" style={{padding:"8px"}}>Tax ({Number(printInvoice?.taxRate ?? printInvoice?.taxrate ?? 0)}%)</td><td className="py-2 text-right" style={{padding:"8px",textAlign:"right"}}>{Number(printInvoice?.taxAmount ?? printInvoice?.taxamount ?? 0).toFixed(2)}</td></tr>
                  <tr style={{borderBottom:"1px solid #eee"}}><td className="py-2 text-slate-500" style={{padding:"8px"}}>Discount</td><td className="py-2 text-right" style={{padding:"8px",textAlign:"right"}}>-{Number(printInvoice?.discountAmount ?? printInvoice?.discountamount ?? 0).toFixed(2)}</td></tr>
                  <tr style={{borderTop:"2px solid #333"}}><td className="py-2 font-bold text-lg" style={{padding:"8px"}}>Total Due</td><td className="py-2 text-right font-bold text-lg" style={{padding:"8px",textAlign:"right"}}>{Number(printInvoice?.totalAmount ?? printInvoice?.totalamount ?? 0).toFixed(2)}</td></tr>
                  <tr><td className="py-2 text-emerald-700" style={{padding:"8px"}}>Amount Paid</td><td className="py-2 text-right text-emerald-700" style={{padding:"8px",textAlign:"right"}}>-{Number(printInvoice?.amountPaid ?? printInvoice?.amountpaid ?? 0).toFixed(2)}</td></tr>
                  <tr style={{borderTop:"1px solid #eee"}}><td className="py-2 font-bold" style={{padding:"8px"}}>Balance</td><td className="py-2 text-right font-bold" style={{padding:"8px",textAlign:"right",color:Number(printInvoice?.balance ?? 0) > 0 ? "#dc2626" : "#16a34a"}}>{Number(printInvoice?.balance ?? 0).toFixed(2)}</td></tr>
                </tbody>
              </table>
              <div className="text-center text-sm text-slate-400 border-t pt-4">
                <p>Thank you for staying with us!</p>
                <p>{activeFarmName} — Generated on {new Date().toLocaleDateString()}</p>
              </div>
            </div>
            <div className="flex justify-end gap-2 mt-2">
              <Button variant="outline" onClick={() => setPrintInvoice(null)}>Close</Button>
              <Button onClick={handlePrint} className="bg-violet-600 hover:bg-violet-700"><Printer className="h-4 w-4 mr-1" />Print Invoice</Button>
            </div>
          </DialogContent>
        </Dialog>
      </main></div></div>
  )
}
