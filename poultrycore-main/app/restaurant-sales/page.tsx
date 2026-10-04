"use client"

// Restaurant Sales (Sales, Expenses & Money → Sales).
//
// Poultry's Sales page (app/sales) for what a restaurant sells: every order
// that was not cancelled, as money -- total, paid, balance, Paid / Partial /
// Pending -- on the shared ModuleSalesView (search, Filters, PDF, Email,
// scorecards, phone cards, table, pagination). The kitchen workflow stays on
// the Orders board; "Add Sale" opens the POS, where orders are taken.
// Pay records a payment against a pay-later order (migration 333); an order
// still open at the till is paid at the POS.

import { Suspense, useCallback, useEffect, useMemo, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { History, Pencil, Trash2, Wallet } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { useFmt } from "@/lib/currency"
import { listOrderItems, listOrders, updateOrderStatus, type Order } from "@/lib/api/restaurant"
import type { OpenDocumentRow, PartyBalanceRow } from "@/lib/api/balances"
import { RecordPaymentDialog, type CashAccountOption } from "@/components/balances/record-payment-dialog"
import { PaymentHistoryDialog } from "@/components/balances/payment-history-dialog"
import { RESTAURANT_CUSTOMER_PERMISSIONS, loadRestaurantCashAccounts } from "@/lib/restaurant/balances"
import {
  ModuleSalesView, saleStatusOf, type ModuleSaleRow, type SalesExtraFilter,
} from "@/components/sales/module-sales-view"

const paidOf = (o: Order) => Number(o.paidAmount ?? 0)
const owedOf = (o: Order) => Math.max(0, Number(o.totalAmount ?? 0) - paidOf(o))
const typeLabel = (o: Order) => (o.orderType ?? "Order").replace(/([a-z])([A-Z])/g, "$1 $2")

/** A completed order that is still owed can only be a pay-later order, which is what Pay settles. */
const isPayLater = (o: Order) => o.status === "Completed" && !!o.customerId && owedOf(o) > 0

const toRow = (o: Order): ModuleSaleRow => ({
  key: String(o.orderId),
  reference: o.orderNumber,
  date: o.createdAt,
  customer: o.customerName || (o.tableNumber ? `Table ${o.tableNumber}` : "Walk-in"),
  product: `${typeLabel(o)} · ${o.itemCount} item${o.itemCount === 1 ? "" : "s"}`,
  quantity: o.itemCount,
  total: Number(o.totalAmount ?? 0),
  paid: paidOf(o),
  balance: owedOf(o),
  method: o.guestPaymentIntent ?? null,
  status: saleStatusOf(Number(o.totalAmount ?? 0), paidOf(o)),
  details: [
    { label: "Type", value: typeLabel(o) },
    { label: "Order", value: o.status },
    ...(o.onlineSource ? [{ label: "Source", value: `Online · ${o.onlineSource}` }] : []),
    ...(o.tableNumber ? [{ label: "Table", value: o.tableNumber }] : []),
  ],
})

const EXTRA_FILTERS: SalesExtraFilter<Order>[] = [
  {
    key: "type", label: "Order type", allLabel: "All types",
    options: [{ value: "DineIn", label: "Dine in" }, { value: "Takeaway", label: "Takeaway" }, { value: "Delivery", label: "Delivery" }],
    test: (o, v) => (o.orderType ?? "").replace(/[\s-]/g, "").toLowerCase() === v.toLowerCase(),
  },
  {
    key: "status", label: "Status", allLabel: "All statuses",
    options: [{ value: "Paid", label: "Paid" }, { value: "Partial", label: "Partial" }, { value: "Pending", label: "Pending" }],
    test: (o, v) => saleStatusOf(Number(o.totalAmount ?? 0), paidOf(o)) === v,
  },
]

function asParty(o: Order): PartyBalanceRow {
  return {
    partyId: o.customerId ?? 0, partyName: o.customerName ?? "", paymentTermsDays: 0, totalBalance: owedOf(o),
    openDocumentCount: 1, overdueAmount: 0, totalInvoiced: Number(o.totalAmount ?? 0), totalPaid: paidOf(o),
  }
}
function asDocument(o: Order): OpenDocumentRow {
  return {
    documentType: "Order", documentId: o.orderId, reference: o.orderNumber, documentDate: o.createdAt,
    label: typeLabel(o), totalAmount: Number(o.totalAmount ?? 0), amountPaid: paidOf(o), balance: owedOf(o),
    dueDate: null, ageDays: 0, status: paidOf(o) > 0 ? "Partially Paid" : "Unpaid", isOverdue: false,
  }
}

function RestaurantSalesContent() {
  const fmt = useFmt()
  const router = useRouter()
  const params = useSearchParams()
  const { toast } = useToast()
  const logout = useLogout()
  const { can } = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [orders, setOrders] = useState<Order[]>([])
  const [loading, setLoading] = useState(true)
  const [cashAccounts, setCashAccounts] = useState<CashAccountOption[]>([])
  const [range, setRange] = useState<{ from: string; to: string } | null>(null)
  const focusOrder = Number(params.get("orderId") ?? 0) || null

  const [payOrder, setPayOrder] = useState<Order | null>(null)
  const [historyOrder, setHistoryOrder] = useState<Order | null>(null)

  // Poultry's Delete: the order is cancelled. The server refuses an order with
  // money paid on it ("Refund it instead of cancelling", migration 333).
  const [deleteOrder, setDeleteOrder] = useState<Order | null>(null)
  const [deleting, setDeleting] = useState(false)
  const confirmDelete = async () => {
    if (!deleteOrder) return
    setDeleting(true)
    try {
      await updateOrderStatus(deleteOrder.orderId, "Cancelled", "Deleted from Sales")
      toast({ title: "Sale deleted", description: `Order ${deleteOrder.orderNumber ?? deleteOrder.orderId} was cancelled.` })
      setDeleteOrder(null)
      await load()
    } catch (e: any) {
      toast({ title: "Could not delete", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setDeleting(false)
    }
  }
  const editOrder = (o: Order) => router.push(`/restaurant-orders?orderId=${o.orderId}`)

  const canPay = can(RESTAURANT_CUSTOMER_PERMISSIONS.pay)
  const canReverse = can(RESTAURANT_CUSTOMER_PERMISSIONS.reverse)

  const load = async () => {
    if (!range) return
    setLoading(true)
    try {
      // The server compares createdat <= toDate, and a bare date means midnight at the
      // START of that day -- so send the end of the day or its orders drop out.
      const all = await listOrders(undefined, undefined, range.from || undefined, range.to ? `${range.to}T23:59:59` : undefined)
      setOrders(all.filter((o) => o.status !== "Cancelled"))
    } catch (e: any) {
      toast({ title: "Error", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (!activeFarmType) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, range])

  useEffect(() => {
    if (activeFarmType !== "Restaurant") return
    loadRestaurantCashAccounts().then(setCashAccounts).catch(() => setCashAccounts([]))
  }, [activeFarmType])

  const onRangeChange = useCallback((from: string, to: string) => setRange({ from, to }), [])
  const visible = useMemo(() => (focusOrder ? orders.filter((o) => o.orderId === focusOrder) : orders), [orders, focusOrder])

  const loadInvoiceLines = useCallback(async (o: Order) => {
    const items = await listOrderItems(o.orderId)
    return items
      .filter((i) => i.status !== "Voided" && i.status !== "Cancelled")
      .map((i) => ({ description: i.itemName, quantity: i.quantity, unitPrice: Number(i.unitPrice) + Number(i.modifierTotal ?? 0), total: Number(i.lineTotal) }))
  }, [])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <ModuleSalesView
            subtitle="Every order as a sale: what was paid and what is still owed"
            accent={{ iconBg: "bg-rose-100", iconText: "text-rose-600", button: "bg-rose-600 hover:bg-rose-700", spinner: "text-rose-600" }}
            addAction={{ label: "Add Sale", href: "/restaurant-pos" }}
            items={visible}
            loading={loading}
            toRow={toRow}
            quantityLabel="Total Items"
            quantityHint="items sold"
            searchPlaceholder="Search customer, order or type"
            extraFilters={EXTRA_FILTERS}
            onRangeChange={onRangeChange}
            loadInvoiceLines={loadInvoiceLines}
            pdf={{ title: "Restaurant Sales", filename: "restaurant-sales", headFillColor: [225, 29, 72] }}
            emptyTitle="No sales found"
            emptyText="Orders taken at the POS or online appear here."
            banner={focusOrder ? (
              <div className="flex flex-wrap items-center justify-between gap-2 rounded-md border border-rose-200 bg-rose-50 px-3 py-2 text-sm text-rose-900">
                <span>Showing one order.</span>
                <Link href="/restaurant-sales" className="font-medium text-rose-700 hover:underline">Show all sales</Link>
              </div>
            ) : null}
            renderCardActions={(o) => (
              <>
                {isPayLater(o) && canPay && (
                  <Button variant="outline" size="sm" className="h-10 w-full text-emerald-700 border-emerald-200 hover:bg-emerald-50" onClick={() => setPayOrder(o)}>
                    <Wallet className="h-4 w-4 mr-2" /> Pay
                  </Button>
                )}
                {!isPayLater(o) && o.status !== "Completed" && owedOf(o) > 0 && (
                  <Button asChild variant="outline" size="sm" className="h-10 w-full text-emerald-700 border-emerald-200 hover:bg-emerald-50">
                    <Link href="/restaurant-orders"><Wallet className="h-4 w-4 mr-2" /> Pay at till</Link>
                  </Button>
                )}
                <Button variant="outline" size="sm" className="h-10 w-full" onClick={() => editOrder(o)}>
                  <Pencil className="h-4 w-4 mr-2" /> Edit
                </Button>
              </>
            )}
            renderCardActionsEnd={(o) => (
              <>
                <Button variant="outline" size="sm" className="h-10 w-full" onClick={() => setHistoryOrder(o)}>
                  <History className="h-4 w-4 mr-2" /> Payments
                </Button>
                <Button variant="outline" size="sm" className="h-10 w-full text-red-600 border-red-200 hover:bg-red-50" onClick={() => setDeleteOrder(o)}>
                  <Trash2 className="h-4 w-4 mr-2" /> Delete
                </Button>
              </>
            )}
            renderTableActions={(o) => (
              <>
                {isPayLater(o) && canPay && (
                  <Button variant="ghost" size="sm" className="text-emerald-700 hover:bg-emerald-50"
                    onClick={() => setPayOrder(o)} aria-label="Record payment" title={`Record payment · ${fmt(owedOf(o))} owed`}>
                    <Wallet className="h-4 w-4" />
                  </Button>
                )}
                <Button variant="ghost" size="sm" onClick={() => editOrder(o)} aria-label="Edit" title="Edit">
                  <Pencil className="h-4 w-4" />
                </Button>
              </>
            )}
            renderTableActionsEnd={(o) => (
              <>
                <Button variant="ghost" size="sm" onClick={() => setHistoryOrder(o)} aria-label="Payment history" title="Payment history">
                  <History className="h-4 w-4" />
                </Button>
                <Button variant="ghost" size="sm" className="text-red-600 hover:bg-red-50" onClick={() => setDeleteOrder(o)} aria-label="Delete" title="Delete">
                  <Trash2 className="h-4 w-4" />
                </Button>
              </>
            )}
          />
        </main>
      </div>

      <RecordPaymentDialog
        open={!!payOrder}
        onOpenChange={(o) => { if (!o) setPayOrder(null) }}
        module="restaurant"
        side="customer"
        party={payOrder ? asParty(payOrder) : null}
        singleDocument={payOrder ? asDocument(payOrder) : null}
        cashAccounts={cashAccounts}
        sourceType="SaleEntry"
        onPosted={() => { setPayOrder(null); load() }}
      />

      <PaymentHistoryDialog
        open={!!historyOrder}
        onOpenChange={(o) => { if (!o) setHistoryOrder(null) }}
        module="restaurant"
        side="customer"
        partyName={historyOrder?.customerName ?? null}
        documentType="Order"
        documentId={historyOrder?.orderId ?? null}
        canReverse={canReverse}
        onReversed={() => { load() }}
      />

      <Dialog open={!!deleteOrder} onOpenChange={(v) => { if (!v) setDeleteOrder(null) }}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Delete sale?</DialogTitle>
            <DialogDescription>
              Order {deleteOrder?.orderNumber ?? deleteOrder?.orderId} will be cancelled. An order with money paid on it can't be
              deleted: reverse the payments (Payments button) or refund it on Orders first.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDeleteOrder(null)} disabled={deleting}>Cancel</Button>
            <Button variant="destructive" onClick={confirmDelete} disabled={deleting}>{deleting ? "Deleting…" : "Delete"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

export default function RestaurantSalesPage() {
  return (
    <Suspense fallback={null}>
      <RestaurantSalesContent />
    </Suspense>
  )
}
