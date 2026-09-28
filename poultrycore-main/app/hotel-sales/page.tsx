"use client"

// Hotel Sales (Sales, Expenses & Money → Sales).
//
// Poultry's Sales list (app/sales) for what a hotel sells: each stay (room
// nights plus everything charged to the folio -- restaurant, room service,
// extras, overstay nights) and each walk-in restaurant order paid at the till.
// Same columns where they apply (Sale ID, Date, Customer, Quantity -> Nights,
// Total, Paid, Balance, Method, Status), the same row actions (Record payment,
// Payment history) and one hotel action: bill a checked-out stay to a corporate
// account. Folio work (adding charges, invoices) stays on Billing. Migration 332.

import { Suspense, useEffect, useMemo, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Building2, DollarSign, History, Loader2, Moon, Receipt, Search, ShoppingCart, TrendingUp, Wallet } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import { fmtDateTime } from "@/lib/utils/company-datetime"
import { billStayToAccount, listHotelSales, type HotelSaleRow } from "@/lib/api/hotel-sales"
import { listHotelCustomers, type HotelCustomer } from "@/lib/api/hotel-customers"
import type { OpenDocumentRow, PartyBalanceRow } from "@/lib/api/balances"
import { RecordPaymentDialog, type CashAccountOption } from "@/components/balances/record-payment-dialog"
import { PaymentHistoryDialog } from "@/components/balances/payment-history-dialog"
import { HOTEL_CUSTOMER_PERMISSIONS, loadHotelCashAccounts } from "@/lib/hotel/balances"

const STATUS_CLS: Record<string, string> = {
  Paid: "bg-emerald-100 text-emerald-700",
  Partial: "bg-amber-100 text-amber-700",
  Pending: "bg-slate-100 text-slate-700",
}

function PaymentStatusBadge({ status }: { status: string }) {
  return (
    <span className={cn("inline-flex w-fit rounded-full px-2 py-0.5 text-xs font-medium", STATUS_CLS[status] ?? STATUS_CLS.Pending)}>
      {status}
    </span>
  )
}

/** The sale as the shared payment dialog needs it: its party and one open line. */
function asParty(s: HotelSaleRow): PartyBalanceRow {
  return {
    partyId: s.partyId ?? 0, partyName: s.partyName ?? "", paymentTermsDays: 0, totalBalance: s.balance,
    openDocumentCount: 1, overdueAmount: 0, totalInvoiced: s.totalAmount, totalPaid: s.amountPaid,
  }
}
function asDocument(s: HotelSaleRow): OpenDocumentRow {
  return {
    documentType: s.documentType, documentId: s.documentId, reference: s.reference, documentDate: s.docDate,
    label: s.label, totalAmount: s.totalAmount, amountPaid: s.amountPaid, balance: s.balance,
    dueDate: s.dueDate, ageDays: 0, status: s.amountPaid > 0 ? "Partially Paid" : "Unpaid", isOverdue: s.isOverdue,
  }
}

function HotelSalesContent() {
  const fmt = useFmt()
  const router = useRouter()
  const params = useSearchParams()
  const { toast } = useToast()
  const logout = useLogout()
  const { can } = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [rows, setRows] = useState<HotelSaleRow[]>([])
  const [loading, setLoading] = useState(true)
  const [cashAccounts, setCashAccounts] = useState<CashAccountOption[]>([])
  const [customers, setCustomers] = useState<HotelCustomer[]>([])

  const [search, setSearch] = useState("")
  const [status, setStatus] = useState("all")
  const [type, setType] = useState("all")
  const [from, setFrom] = useState("")
  const [to, setTo] = useState("")
  const focusBooking = Number(params.get("bookingId") ?? 0) || null

  const [paySale, setPaySale] = useState<HotelSaleRow | null>(null)
  const [historySale, setHistorySale] = useState<HotelSaleRow | null>(null)
  const [billSale, setBillSale] = useState<HotelSaleRow | null>(null)
  const [billCustomer, setBillCustomer] = useState("")
  const [billing, setBilling] = useState(false)

  const canPay = can(HOTEL_CUSTOMER_PERMISSIONS.pay)
  const canReverse = can(HOTEL_CUSTOMER_PERMISSIONS.reverse)

  const load = async () => {
    setLoading(true)
    try {
      setRows(await listHotelSales({ from: from || null, to: to || null }))
    } catch (e: any) {
      toast({ title: "Error", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (!activeFarmType) return
    if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    load()
    loadHotelCashAccounts().then(setCashAccounts).catch(() => setCashAccounts([]))
    listHotelCustomers().then((c) => setCustomers(c.filter((x) => x.isActive !== false))).catch(() => setCustomers([]))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, from, to])

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase()
    return rows.filter((r) =>
      (!focusBooking || (r.documentType === "Stay" && r.documentId === focusBooking)) &&
      (type === "all" || r.documentType === type) &&
      (status === "all" || r.paymentStatus === status) &&
      (!q || [r.partyName, r.reference, r.label, r.roomNumber].some((v) => (v ?? "").toLowerCase().includes(q))))
  }, [rows, search, status, type, focusBooking])

  const totalSales = filtered.reduce((s, r) => s + Number(r.totalAmount), 0)
  const totalNights = filtered.reduce((s, r) => s + Number(r.nights ?? 0), 0)
  const totalOwed = filtered.reduce((s, r) => s + Number(r.balance), 0)

  const billToAccount = async () => {
    if (!billSale || !billCustomer) return
    setBilling(true)
    try {
      await billStayToAccount(billSale.documentId, Number(billCustomer))
      toast({ title: "Billed to account", description: `${billSale.reference} moved to the account's balance.` })
      setBillSale(null); setBillCustomer("")
      await load()
    } catch (e: any) {
      toast({ title: "Error", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setBilling(false)
    }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6">
            <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
              <div className="flex items-start gap-3 min-w-0">
                <div className="w-10 h-10 shrink-0 bg-violet-100 rounded-lg flex items-center justify-center">
                  <ShoppingCart className="w-5 h-5 text-violet-600" />
                </div>
                <div className="min-w-0">
                  <h1 className="text-xl sm:text-2xl font-bold text-slate-900 truncate">Sales</h1>
                  <p className="text-sm text-slate-600">Stays and restaurant sales, what was paid and what is still owed</p>
                </div>
              </div>
              <Button asChild className="gap-2 w-full sm:w-auto h-11 sm:h-10 bg-violet-600 hover:bg-violet-700 shrink-0">
                <Link href="/hotel-billing"><Receipt className="w-4 h-4" /> Billing</Link>
              </Button>
            </div>

            <div className="grid gap-4 grid-cols-2 md:grid-cols-4">
              <Card className="bg-white">
                <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                  <CardTitle className="text-sm font-medium">Total Sales</CardTitle>
                  <DollarSign className="h-4 w-4 text-muted-foreground" />
                </CardHeader>
                <CardContent>
                  <div className="text-xl sm:text-2xl font-bold leading-tight break-words">{fmt(totalSales)}</div>
                  <p className="text-xs text-muted-foreground">{filtered.length} transactions</p>
                </CardContent>
              </Card>
              <Card className="bg-white">
                <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                  <CardTitle className="text-sm font-medium">Room Nights</CardTitle>
                  <Moon className="h-4 w-4 text-muted-foreground" />
                </CardHeader>
                <CardContent>
                  <div className="text-xl sm:text-2xl font-bold leading-tight">{totalNights.toLocaleString()}</div>
                  <p className="text-xs text-muted-foreground">nights sold</p>
                </CardContent>
              </Card>
              <Card className="bg-white">
                <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                  <CardTitle className="text-sm font-medium">Average Sale</CardTitle>
                  <TrendingUp className="h-4 w-4 text-muted-foreground" />
                </CardHeader>
                <CardContent>
                  <div className="text-xl sm:text-2xl font-bold leading-tight break-words">{fmt(filtered.length ? totalSales / filtered.length : 0)}</div>
                  <p className="text-xs text-muted-foreground">per transaction</p>
                </CardContent>
              </Card>
              <Card className="bg-white">
                <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                  <CardTitle className="text-sm font-medium">Balance</CardTitle>
                  <Wallet className="h-4 w-4 text-muted-foreground" />
                </CardHeader>
                <CardContent>
                  <div className={cn("text-xl sm:text-2xl font-bold leading-tight break-words", totalOwed > 0 ? "text-amber-700" : "")}>{fmt(totalOwed)}</div>
                  <p className="text-xs text-muted-foreground">still owed</p>
                </CardContent>
              </Card>
            </div>

            <Card className="bg-white">
              <CardContent className="p-4 grid gap-3 grid-cols-1 sm:grid-cols-2 lg:grid-cols-5">
                <div className="relative lg:col-span-2">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                  <Input placeholder="Search customer, reference or room" value={search} onChange={(e) => setSearch(e.target.value)} className="pl-10" />
                </div>
                <Select value={type} onValueChange={setType}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">All sales</SelectItem>
                    <SelectItem value="Stay">Stays</SelectItem>
                    <SelectItem value="Order">Restaurant orders</SelectItem>
                  </SelectContent>
                </Select>
                <Select value={status} onValueChange={setStatus}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">All statuses</SelectItem>
                    <SelectItem value="Paid">Paid</SelectItem>
                    <SelectItem value="Partial">Partial</SelectItem>
                    <SelectItem value="Pending">Pending</SelectItem>
                  </SelectContent>
                </Select>
                <div className="grid grid-cols-2 gap-2">
                  <Input type="date" aria-label="From" value={from} onChange={(e) => setFrom(e.target.value)} />
                  <Input type="date" aria-label="To" value={to} onChange={(e) => setTo(e.target.value)} />
                </div>
                {focusBooking && (
                  <div className="sm:col-span-2 lg:col-span-5 text-sm text-slate-600">
                    Showing one stay. <Link href="/hotel-sales" className="text-violet-700 hover:underline">Show all sales</Link>
                  </div>
                )}
              </CardContent>
            </Card>

            {loading ? (
              <Card className="bg-white"><CardContent className="py-12 text-center"><Loader2 className="h-6 w-6 animate-spin text-violet-600 mx-auto" /></CardContent></Card>
            ) : rows.length === 0 ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center">
                  <h3 className="text-lg font-semibold text-slate-900 mb-2">No sales found</h3>
                  <p className="text-slate-600">Bookings and restaurant orders appear here.</p>
                </CardContent>
              </Card>
            ) : filtered.length === 0 ? (
              <Card className="bg-white"><CardContent className="py-12 text-center"><p className="text-slate-600">No sales match the current filters.</p></CardContent></Card>
            ) : (
              <Card className="bg-white overflow-hidden">
                <CardHeader>
                  <CardTitle>Recent Sales</CardTitle>
                  <CardDescription>View and manage your sales transactions</CardDescription>
                </CardHeader>
                <CardContent className="p-0 overflow-x-auto">
                  <Table className="w-full min-w-[1100px]">
                    <TableHeader>
                      <TableRow>
                        <TableHead>Sale ID</TableHead>
                        <TableHead>Date</TableHead>
                        <TableHead>Sale</TableHead>
                        <TableHead>Customer</TableHead>
                        <TableHead>Nights</TableHead>
                        <TableHead>Total</TableHead>
                        <TableHead>Paid</TableHead>
                        <TableHead>Balance</TableHead>
                        <TableHead>Method</TableHead>
                        <TableHead>Status</TableHead>
                        <TableHead className="min-w-[140px]">Actions</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {filtered.map((s) => (
                        <TableRow key={`${s.documentType}-${s.documentId}`}>
                          <TableCell className="whitespace-nowrap tabular-nums text-slate-500">{s.reference}</TableCell>
                          <TableCell className="whitespace-nowrap">{fmtDateTime(s.docDate)}</TableCell>
                          <TableCell>
                            <div>{s.label}</div>
                            {s.documentType === "Stay" && s.bookingStatus && <div className="text-xs text-slate-500">{s.bookingStatus}</div>}
                          </TableCell>
                          <TableCell>
                            {s.partyName}
                            {s.billedToAccount && <Badge variant="outline" className="ml-2 text-violet-700 border-violet-300">Account</Badge>}
                          </TableCell>
                          <TableCell className="tabular-nums">{s.nights ?? "—"}</TableCell>
                          <TableCell className="font-medium tabular-nums">{fmt(s.totalAmount)}</TableCell>
                          <TableCell className="tabular-nums text-emerald-700">{fmt(s.amountPaid)}</TableCell>
                          <TableCell className={cn("tabular-nums", s.balance > 0 ? "font-semibold text-amber-700" : "text-slate-400")}>{fmt(s.balance)}</TableCell>
                          <TableCell>{s.paymentMethod ? <Badge variant="outline" className="w-fit">{s.paymentMethod}</Badge> : "—"}</TableCell>
                          <TableCell><PaymentStatusBadge status={s.paymentStatus} /></TableCell>
                          <TableCell className="whitespace-nowrap">
                            <div className="flex items-center gap-1">
                              {s.documentType === "Stay" && s.balance > 0 && canPay && (
                                <Button variant="ghost" size="sm" className="text-emerald-700 hover:bg-emerald-50"
                                  onClick={() => setPaySale(s)} aria-label="Record payment" title={`Record payment · ${fmt(s.balance)} owed`}>
                                  <Wallet className="h-4 w-4" />
                                </Button>
                              )}
                              {s.documentType === "Stay" && (
                                <Button variant="ghost" size="sm" onClick={() => setHistorySale(s)} aria-label="Payment history" title="Payment history">
                                  <History className="h-4 w-4" />
                                </Button>
                              )}
                              {s.documentType === "Stay" && s.bookingStatus === "CheckedOut" && !s.billedToAccount && s.balance > 0 && canPay && (
                                <Button variant="ghost" size="sm" className="text-violet-700 hover:bg-violet-50"
                                  onClick={() => setBillSale(s)} aria-label="Bill to account" title="Bill to account">
                                  <Building2 className="h-4 w-4" />
                                </Button>
                              )}
                            </div>
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </CardContent>
              </Card>
            )}
          </div>
        </main>
      </div>

      <RecordPaymentDialog
        open={!!paySale}
        onOpenChange={(o) => { if (!o) setPaySale(null) }}
        module="hotel"
        side="customer"
        party={paySale ? asParty(paySale) : null}
        singleDocument={paySale ? asDocument(paySale) : null}
        cashAccounts={cashAccounts}
        sourceType="SaleEntry"
        onPosted={() => { setPaySale(null); load() }}
      />

      <PaymentHistoryDialog
        open={!!historySale}
        onOpenChange={(o) => { if (!o) setHistorySale(null) }}
        module="hotel"
        side="customer"
        partyName={historySale?.partyName ?? null}
        documentType="Sale"
        documentId={historySale?.documentId ?? null}
        canReverse={canReverse}
        onReversed={() => { load() }}
      />

      <Dialog open={!!billSale} onOpenChange={(o) => { if (!o) { setBillSale(null); setBillCustomer("") } }}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Bill to account</DialogTitle>
            <DialogDescription>
              The stay's balance moves from the guest to a corporate account and appears on Customer Balances.
            </DialogDescription>
          </DialogHeader>
          {billSale && (
            <div className="space-y-4">
              <div className="rounded-lg bg-slate-50 border border-slate-200 p-3 text-sm space-y-1">
                <div className="flex justify-between"><span className="text-slate-500">Sale</span><span className="font-medium">{billSale.reference} · {billSale.partyName}</span></div>
                <div className="flex justify-between"><span className="text-slate-500">Owed</span><span className="tabular-nums font-semibold text-amber-700">{fmt(billSale.balance)}</span></div>
              </div>
              <div className="space-y-2">
                <Label>Customer *</Label>
                <Select value={billCustomer} onValueChange={setBillCustomer}>
                  <SelectTrigger><SelectValue placeholder="Select a customer" /></SelectTrigger>
                  <SelectContent>
                    {customers.map((c) => <SelectItem key={c.hotelCustomerId} value={String(c.hotelCustomerId)}>{c.customerName}</SelectItem>)}
                  </SelectContent>
                </Select>
                {customers.length === 0 && (
                  <p className="text-xs text-slate-500">No customers yet. Add one under <Link href="/hotel-customers" className="text-violet-700 hover:underline">Customers</Link>.</p>
                )}
              </div>
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => setBillSale(null)} disabled={billing}>Cancel</Button>
            <Button onClick={billToAccount} disabled={billing || !billCustomer} className="bg-violet-600 hover:bg-violet-700">
              {billing ? "Saving…" : "Bill to account"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

export default function HotelSalesPage() {
  return (
    <Suspense fallback={null}>
      <HotelSalesContent />
    </Suspense>
  )
}
