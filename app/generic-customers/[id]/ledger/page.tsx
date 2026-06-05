"use client"

import { useEffect, useState } from "react"
import Link from "next/link"
import { useParams, useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ArrowLeft, BookOpen, Loader2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { getCustomer, getCustomerLedger, type GenericCustomer, type GenericCustomerLedgerEntry } from "@/lib/api/generic"

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}

const TYPE_COLORS: Record<string, string> = {
  OpeningBalance:   "bg-slate-100 text-slate-800",
  SaleDebit:        "bg-rose-100 text-rose-800",
  PaymentCredit:    "bg-emerald-100 text-emerald-800",
  RefundDebit:      "bg-amber-100 text-amber-800",
  AdjustmentDebit:  "bg-amber-100 text-amber-800",
  AdjustmentCredit: "bg-sky-100 text-sky-800",
  BadDebtWriteOff:  "bg-slate-200 text-slate-700",
}

export default function CustomerLedgerPage() {
  const router = useRouter()
  const params = useParams<{ id: string }>()
  const id = Number(params.id)
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const [customer, setCustomer] = useState<GenericCustomer | null>(null)
  const [entries, setEntries] = useState<GenericCustomerLedgerEntry[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    let cancelled = false
    ;(async () => {
      try {
        const [c, l] = await Promise.all([getCustomer(id), getCustomerLedger(id)])
        if (cancelled) return
        setCustomer(c); setEntries(l)
      } catch (e: any) {
        if (!cancelled) toast({ title: "Could not load ledger", description: e?.message ?? String(e), variant: "destructive" })
      } finally { if (!cancelled) setLoading(false) }
    })()
    return () => { cancelled = true }
  }, [activeFarmType, id, router, toast])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <Link href="/generic-customers" className="inline-flex items-center text-sm text-slate-500 hover:text-slate-700 mb-2">
            <ArrowLeft className="h-3 w-3 mr-1" /> Back to customers
          </Link>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : !customer ? (
            <Card><CardContent className="py-8 text-center text-slate-500">Customer not found.</CardContent></Card>
          ) : (
            <>
              <div className="mb-4 flex items-start justify-between flex-wrap gap-2">
                <div>
                  <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                    <BookOpen className="h-6 w-6 text-emerald-600" /> {customer.customerName}
                  </h1>
                  <p className="text-sm text-slate-500">{customer.customerType} · {customer.phoneNumber ?? "no phone"} · {customer.location ?? "no location"}</p>
                </div>
                <Card className="min-w-[220px]">
                  <CardContent className="py-3 px-4">
                    <div className="text-xs text-slate-500 uppercase">Current balance</div>
                    <div className={`text-2xl font-semibold ${customer.currentBalance > 0 ? "text-rose-700" : "text-emerald-700"}`}>{fmt(customer.currentBalance)}</div>
                    <div className="text-xs text-slate-500">Credit limit: {customer.creditLimit > 0 ? fmt(customer.creditLimit) : "—"}</div>
                  </CardContent>
                </Card>
              </div>

              <Card>
                <CardHeader className="pb-2"><CardTitle className="text-base">Transactions</CardTitle></CardHeader>
                <CardContent className="p-0">
                  {entries.length === 0 ? (
                    <p className="text-slate-500 text-sm p-4">No transactions yet.</p>
                  ) : (
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Date</TableHead>
                          <TableHead>Type</TableHead>
                          <TableHead>Description</TableHead>
                          <TableHead>Ref</TableHead>
                          <TableHead className="text-right">Debit</TableHead>
                          <TableHead className="text-right">Credit</TableHead>
                          <TableHead className="text-right">Balance</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {entries.map((e) => (
                          <TableRow key={e.genericCustomerLedgerId}>
                            <TableCell>{new Date(e.transactionDate).toLocaleDateString()}</TableCell>
                            <TableCell><Badge className={`${TYPE_COLORS[e.transactionType] ?? "bg-slate-100 text-slate-800"} hover:opacity-90`}>{e.transactionType}</Badge></TableCell>
                            <TableCell className="max-w-md truncate" title={e.description ?? ""}>{e.description ?? "—"}</TableCell>
                            <TableCell className="text-xs text-slate-500">{e.saleId ? `Sale #${e.saleId}` : e.paymentId ? `Pay #${e.paymentId}` : "—"}</TableCell>
                            <TableCell className="text-right">{e.debitAmount > 0 ? fmt(e.debitAmount) : ""}</TableCell>
                            <TableCell className="text-right">{e.creditAmount > 0 ? fmt(e.creditAmount) : ""}</TableCell>
                            <TableCell className="text-right font-semibold">{fmt(e.balanceAfterTransaction)}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  )}
                </CardContent>
              </Card>
            </>
          )}
        </main>
      </div>
    </div>
  )
}
