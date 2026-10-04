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
// Layout (search, Filters, PDF, Email, scorecards, phone cards, table,
// pagination, Invoice) is the shared ModuleSalesView, same as Restaurant Sales.

import { Suspense, useCallback, useEffect, useMemo, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Building2, History, Pencil, Trash2, Wallet } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { useFmt } from "@/lib/currency"
import { billStayToAccount, deleteHotelStaySale, listHotelSales, type HotelSaleRow } from "@/lib/api/hotel-sales"
import { listHotelCustomers, type HotelCustomer } from "@/lib/api/hotel-customers"
import type { OpenDocumentRow, PartyBalanceRow } from "@/lib/api/balances"
import { RecordPaymentDialog, type CashAccountOption } from "@/components/balances/record-payment-dialog"
import { PaymentHistoryDialog } from "@/components/balances/payment-history-dialog"
import { HOTEL_CUSTOMER_PERMISSIONS, loadHotelCashAccounts } from "@/lib/hotel/balances"
import {
  ModuleSalesView, saleStatusOf, type ModuleSaleRow, type SaleStatus, type SalesExtraFilter,
} from "@/components/sales/module-sales-view"

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

const toRow = (s: HotelSaleRow): ModuleSaleRow => ({
  key: `${s.documentType}-${s.documentId}`,
  reference: s.reference ?? `#${s.documentId}`,
  date: s.docDate,
  customer: s.partyName ?? "",
  product: s.label ?? (s.documentType === "Stay" ? "Stay" : "Restaurant order"),
  quantity: s.nights ?? null,
  total: Number(s.totalAmount),
  paid: Number(s.amountPaid),
  balance: Number(s.balance),
  method: s.paymentMethod ?? null,
  status: (["Paid", "Partial", "Pending"].includes(s.paymentStatus) ? s.paymentStatus : saleStatusOf(s.totalAmount, s.amountPaid)) as SaleStatus,
  details: [
    { label: "Type", value: s.documentType === "Stay" ? "Stay" : "Restaurant" },
    ...(s.roomNumber ? [{ label: "Room", value: s.roomNumber }] : []),
    ...(s.bookingStatus ? [{ label: "Booking", value: s.bookingStatus }] : []),
    ...(s.billedToAccount ? [{ label: "Billed to", value: "Account" }] : []),
  ],
})

const EXTRA_FILTERS: SalesExtraFilter<HotelSaleRow>[] = [
  { key: "type", label: "Sale type", allLabel: "All sales", options: [{ value: "Stay", label: "Stays" }, { value: "Order", label: "Restaurant orders" }], test: (s, v) => s.documentType === v },
  { key: "status", label: "Status", allLabel: "All statuses", options: [{ value: "Paid", label: "Paid" }, { value: "Partial", label: "Partial" }, { value: "Pending", label: "Pending" }], test: (s, v) => s.paymentStatus === v },
]

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
  const [range, setRange] = useState<{ from: string; to: string } | null>(null)
  const focusBooking = Number(params.get("bookingId") ?? 0) || null

  const [paySale, setPaySale] = useState<HotelSaleRow | null>(null)
  const [historySale, setHistorySale] = useState<HotelSaleRow | null>(null)
  const [billSale, setBillSale] = useState<HotelSaleRow | null>(null)
  const [billCustomer, setBillCustomer] = useState("")
  const [billing, setBilling] = useState(false)

  const canPay = can(HOTEL_CUSTOMER_PERMISSIONS.pay)
  const canReverse = can(HOTEL_CUSTOMER_PERMISSIONS.reverse)

  const load = async () => {
    if (!range) return
    setLoading(true)
    try {
      setRows(await listHotelSales({ from: range.from || null, to: range.to || null }))
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
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, range])

  useEffect(() => {
    if (activeFarmType !== "Hotel") return
    loadHotelCashAccounts().then(setCashAccounts).catch(() => setCashAccounts([]))
    listHotelCustomers().then((c) => setCustomers(c.filter((x) => x.isActive !== false))).catch(() => setCustomers([]))
  }, [activeFarmType])

  const onRangeChange = useCallback((from: string, to: string) => setRange({ from, to }), [])
  const visible = useMemo(
    () => (focusBooking ? rows.filter((r) => r.documentType === "Stay" && r.documentId === focusBooking) : rows),
    [rows, focusBooking],
  )

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

  const [deleteSale, setDeleteSale] = useState<HotelSaleRow | null>(null)
  const [deleting, setDeleting] = useState(false)
  const confirmDelete = async () => {
    if (!deleteSale) return
    setDeleting(true)
    try {
      await deleteHotelStaySale(deleteSale.documentId)
      toast({ title: "Sale deleted", description: `${deleteSale.reference} was cancelled.` })
      setDeleteSale(null)
      await load()
    } catch (e: any) {
      toast({ title: "Could not delete", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setDeleting(false)
    }
  }

  const canBill = (s: HotelSaleRow) => s.documentType === "Stay" && s.bookingStatus === "CheckedOut" && !s.billedToAccount && s.balance > 0 && canPay

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <ModuleSalesView
            subtitle="Stays and restaurant sales, what was paid and what is still owed"
            accent={{ iconBg: "bg-violet-100", iconText: "text-violet-600", button: "bg-violet-600 hover:bg-violet-700", spinner: "text-violet-600" }}
            addAction={{ label: "New Booking", href: "/hotel-bookings?new=1" }}
            items={visible}
            loading={loading}
            toRow={toRow}
            quantityLabel="Room Nights"
            quantityHint="nights sold"
            searchPlaceholder="Search customer, reference or room"
            extraFilters={EXTRA_FILTERS}
            onRangeChange={onRangeChange}
            pdf={{ title: "Hotel Sales", filename: "hotel-sales", headFillColor: [124, 58, 237] }}
            emptyTitle="No sales found"
            emptyText="Bookings and restaurant orders appear here."
            banner={focusBooking ? (
              <div className="flex flex-wrap items-center justify-between gap-2 rounded-md border border-violet-200 bg-violet-50 px-3 py-2 text-sm text-violet-900">
                <span>Showing one stay.</span>
                <Link href="/hotel-sales" className="font-medium text-violet-700 hover:underline">Show all sales</Link>
              </div>
            ) : null}
            // Poultry's order (app/sales): Pay, Edit, Invoice, Payments, Delete. Edit and
            // Delete are for stays; a walk-in restaurant order is settled at the till.
            renderCardActions={(s) => (
              <>
                {s.documentType === "Stay" && s.balance > 0 && canPay && (
                  <Button variant="outline" size="sm" className="h-10 w-full text-emerald-700 border-emerald-200 hover:bg-emerald-50" onClick={() => setPaySale(s)}>
                    <Wallet className="h-4 w-4 mr-2" /> Pay
                  </Button>
                )}
                {s.documentType === "Stay" && (
                  <Button variant="outline" size="sm" className="h-10 w-full" onClick={() => router.push(`/hotel-bookings?edit=${s.documentId}`)}>
                    <Pencil className="h-4 w-4 mr-2" /> Edit
                  </Button>
                )}
              </>
            )}
            renderCardActionsEnd={(s) => (
              <>
                {s.documentType === "Stay" && (
                  <Button variant="outline" size="sm" className="h-10 w-full" onClick={() => setHistorySale(s)}>
                    <History className="h-4 w-4 mr-2" /> Payments
                  </Button>
                )}
                {canBill(s) && (
                  <Button variant="outline" size="sm" className="h-10 w-full text-violet-700 border-violet-200 hover:bg-violet-50" onClick={() => setBillSale(s)}>
                    <Building2 className="h-4 w-4 mr-2" /> Bill to account
                  </Button>
                )}
                {s.documentType === "Stay" && (
                  <Button variant="outline" size="sm" className="h-10 w-full text-red-600 border-red-200 hover:bg-red-50" onClick={() => setDeleteSale(s)}>
                    <Trash2 className="h-4 w-4 mr-2" /> Delete
                  </Button>
                )}
              </>
            )}
            renderTableActions={(s) => (
              <>
                {s.documentType === "Stay" && s.balance > 0 && canPay && (
                  <Button variant="ghost" size="sm" className="text-emerald-700 hover:bg-emerald-50"
                    onClick={() => setPaySale(s)} aria-label="Record payment" title={`Record payment · ${fmt(s.balance)} owed`}>
                    <Wallet className="h-4 w-4" />
                  </Button>
                )}
                {s.documentType === "Stay" && (
                  <Button variant="ghost" size="sm" onClick={() => router.push(`/hotel-bookings?edit=${s.documentId}`)} aria-label="Edit" title="Edit">
                    <Pencil className="h-4 w-4" />
                  </Button>
                )}
              </>
            )}
            renderTableActionsEnd={(s) => (
              <>
                {s.documentType === "Stay" && (
                  <Button variant="ghost" size="sm" onClick={() => setHistorySale(s)} aria-label="Payment history" title="Payment history">
                    <History className="h-4 w-4" />
                  </Button>
                )}
                {canBill(s) && (
                  <Button variant="ghost" size="sm" className="text-violet-700 hover:bg-violet-50"
                    onClick={() => setBillSale(s)} aria-label="Bill to account" title="Bill to account">
                    <Building2 className="h-4 w-4" />
                  </Button>
                )}
                {s.documentType === "Stay" && (
                  <Button variant="ghost" size="sm" className="text-red-600 hover:bg-red-50" onClick={() => setDeleteSale(s)} aria-label="Delete" title="Delete">
                    <Trash2 className="h-4 w-4" />
                  </Button>
                )}
              </>
            )}
          />
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

      <Dialog open={!!deleteSale} onOpenChange={(o) => { if (!o) setDeleteSale(null) }}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Delete sale?</DialogTitle>
            <DialogDescription>
              {deleteSale ? `${deleteSale.reference} · ${deleteSale.partyName ?? ""}` : ""}. The booking is cancelled and its room freed.
              A sale with money paid on it can't be deleted: reverse the payments first (Payments button).
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDeleteSale(null)} disabled={deleting}>Cancel</Button>
            <Button variant="destructive" onClick={confirmDelete} disabled={deleting}>{deleting ? "Deleting…" : "Delete"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

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
