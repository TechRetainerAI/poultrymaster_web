"use client"

// Customer Credit (migration 351), shown on Poultry Customer Balances.
//
// "Customer owes us" and "we are holding the customer's money" are different
// things, so they are shown side by side and never netted. Credit usually
// comes from a payment kept when its sale was reversed. From here it can be
// refunded (real Money Out); applying it to a sale is done from that sale's
// Pay dialog on the Sales page.

import { useCallback, useEffect, useState } from "react"
import { HandCoins, PiggyBank } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { formatCurrency, getSelectedCurrency } from "@/lib/utils/currency"
import { useCurrency } from "@/lib/currency"
import { listCustomerCredit, type CustomerCreditSummaryRow } from "@/lib/api/customer-credit"
import { RefundCreditDialog, type RefundTarget } from "@/components/sales/refund-credit-dialog"

export function CustomerCreditPanel() {
  const { toast } = useToast()
  const { can } = usePermissions()
  const { code } = useCurrency()
  const currencyCode = code || getSelectedCurrency()
  const [rows, setRows] = useState<CustomerCreditSummaryRow[]>([])
  const [loaded, setLoaded] = useState(false)
  const [refundFor, setRefundFor] = useState<RefundTarget | null>(null)
  const canRefund = can("poultry.customer-payments.create")

  const load = useCallback(() => {
    listCustomerCredit()
      .then((r) => setRows(r))
      .catch(() => setRows([]))
      .finally(() => setLoaded(true))
  }, [])

  useEffect(() => { load() }, [load])

  // Nothing held for anyone: say nothing, the page is about balances owed.
  if (!loaded || rows.length === 0) return null

  const total = rows.reduce((t, r) => t + (Number(r.availableCredit) || 0), 0)
  const money = (n: number) => formatCurrency(Number(n) || 0, currencyCode)

  return (
    <Card className="mb-4 border-blue-200">
      <CardContent className="space-y-3 p-4">
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <h2 className="flex items-center gap-2 text-sm font-semibold text-slate-900">
            <PiggyBank className="h-4 w-4 text-blue-600" /> Customer credit
            <span className="font-normal text-slate-500">— money customers paid that is not on any active sale</span>
          </h2>
          <span className="text-sm font-semibold tabular-nums text-blue-700">{money(total)} held</span>
        </div>
        <div className="grid gap-2 sm:grid-cols-2 xl:grid-cols-3">
          {rows.map((r) => (
            <div key={r.customerId} className="flex items-center justify-between gap-3 rounded-md border p-3">
              <div className="min-w-0">
                <p className="truncate text-sm font-medium text-slate-900">{r.customerName}</p>
                <p className="text-xs text-slate-500">
                  Credit <span className="font-semibold tabular-nums text-blue-700">{money(r.availableCredit)}</span>
                  {" · "}Owes <span className="tabular-nums">{money(r.outstanding)}</span>
                </p>
              </div>
              {canRefund && (
                <Button size="sm" variant="outline" className="shrink-0"
                        onClick={() => setRefundFor({ customerId: r.customerId, customerName: r.customerName, availableCredit: Number(r.availableCredit) || 0 })}>
                  <HandCoins className="mr-1.5 h-4 w-4" /> Refund
                </Button>
              )}
            </div>
          ))}
        </div>
        <p className="text-xs text-slate-500">
          To use credit on a sale, open the sale&apos;s Pay dialog on the Sales page and choose &quot;Use customer credit&quot;. No new money is recorded.
        </p>
      </CardContent>
      <RefundCreditDialog
        target={refundFor}
        currencyCode={currencyCode}
        onOpenChange={(o) => { if (!o) setRefundFor(null) }}
        onRefunded={() => {
          toast({ title: "Refund recorded", description: `Paid back to ${refundFor?.customerName}. It shows in Cash Flow as a customer refund.` })
          setRefundFor(null)
          load()
        }}
      />
    </Card>
  )
}
