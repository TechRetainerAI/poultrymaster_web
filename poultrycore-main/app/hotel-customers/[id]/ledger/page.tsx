"use client"
import { useEffect, useState } from "react"
import { useRouter, useParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Loader2, ArrowLeft } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import {
  getHotelCustomer, getHotelCustomerLedger,
  type HotelCustomer, type HotelCustomerLedgerEntry,
} from "@/lib/api/hotel-customers"

const TYPE_COLORS: Record<string, string> = {
  OpeningBalance: "bg-slate-100 text-slate-700",
  InvoiceCredit: "bg-blue-100 text-blue-700",
  PaymentDebit: "bg-emerald-100 text-emerald-700",
  AdjustmentCredit: "bg-amber-100 text-amber-700",
  AdjustmentDebit: "bg-purple-100 text-purple-700",
}

export default function CustomerLedgerPage() {
  const router = useRouter(); const params = useParams(); const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const customerId = Number(params.id)

  const [customer, setCustomer] = useState<HotelCustomer | null>(null)
  const [ledger, setLedger] = useState<HotelCustomerLedgerEntry[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (!activeFarmType) return
    if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    load()
  }, [activeFarmType, customerId])

  async function load() {
    setLoading(true)
    try {
      const [c, l] = await Promise.all([getHotelCustomer(customerId), getHotelCustomerLedger(customerId)])
      setCustomer(c); setLedger(l)
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  const fmt = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  const fmtDate = (s: string) => new Date(s).toLocaleDateString()

  if (loading) return (
    <div className="flex h-screen"><DashboardSidebar /><div className="flex-1 flex flex-col"><DashboardHeader />
      <div className="flex-1 flex items-center justify-center"><Loader2 className="h-8 w-8 animate-spin text-muted-foreground" /></div>
    </div></div>
  )

  if (!customer) return (
    <div className="flex h-screen"><DashboardSidebar /><div className="flex-1 flex flex-col"><DashboardHeader />
      <div className="flex-1 flex items-center justify-center text-muted-foreground">Customer not found</div>
    </div></div>
  )

  return (
    <div className="flex h-screen">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 md:p-6 space-y-6">
          <div className="flex items-center gap-4">
            <Button variant="ghost" size="sm" onClick={() => router.push("/hotel-customers")}><ArrowLeft className="h-4 w-4 mr-2" />Back</Button>
            <h1 className="text-2xl font-bold">{customer.customerName} — Statement</h1>
          </div>

          {/* Customer Info */}
          <div className="grid grid-cols-1 sm:grid-cols-4 gap-4">
            <Card><CardContent className="pt-6">
              <p className="text-sm text-muted-foreground">Type</p>
              <p className="font-medium">{customer.customerType}</p>
            </CardContent></Card>
            <Card><CardContent className="pt-6">
              <p className="text-sm text-muted-foreground">Phone</p>
              <p className="font-medium">{customer.phone || "—"}</p>
            </CardContent></Card>
            <Card><CardContent className="pt-6">
              <p className="text-sm text-muted-foreground">Payment Terms</p>
              <p className="font-medium">{customer.paymentTermDays} days</p>
            </CardContent></Card>
            <Card><CardContent className="pt-6">
              <p className="text-sm text-muted-foreground">Balance Owed</p>
              <p className={`text-2xl font-bold ${customer.currentBalance > 0 ? "text-red-600" : "text-emerald-600"}`}>
                {fmt(customer.currentBalance)}
              </p>
            </CardContent></Card>
          </div>

          {/* Ledger Table */}
          <Card>
            <CardContent className="p-0">
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead><tr className="border-b bg-muted/50">
                    <th className="text-left p-3">Date</th>
                    <th className="text-left p-3">Type</th>
                    <th className="text-left p-3">Description</th>
                    <th className="text-left p-3">Ref</th>
                    <th className="text-right p-3">Debit</th>
                    <th className="text-right p-3">Credit</th>
                    <th className="text-right p-3">Balance</th>
                  </tr></thead>
                  <tbody>
                    {ledger.length === 0 && (
                      <tr><td colSpan={7} className="text-center p-8 text-muted-foreground">No transactions yet</td></tr>
                    )}
                    {ledger.map(e => (
                      <tr key={e.hotelCustomerLedgerId} className="border-b hover:bg-muted/30">
                        <td className="p-3">{fmtDate(e.transactionDate)}</td>
                        <td className="p-3"><Badge className={TYPE_COLORS[e.transactionType] || "bg-slate-100 text-slate-700"}>{e.transactionType}</Badge></td>
                        <td className="p-3">{e.description || "—"}</td>
                        <td className="p-3 text-muted-foreground">
                          {e.invoiceId ? `Inv #${e.invoiceId}` : e.paymentId ? `Pay #${e.paymentId}` : "—"}
                        </td>
                        <td className="p-3 text-right font-mono">{e.debitAmount > 0 ? fmt(e.debitAmount) : ""}</td>
                        <td className="p-3 text-right font-mono">{e.creditAmount > 0 ? fmt(e.creditAmount) : ""}</td>
                        <td className="p-3 text-right font-mono font-semibold">{fmt(e.balanceAfterTransaction)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </CardContent>
          </Card>
        </main>
      </div>
    </div>
  )
}
