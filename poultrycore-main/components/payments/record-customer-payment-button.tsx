"use client"

// Record a customer payment from Payments Received (367) or a supplier payment
// from Supplier Payments (370), poultry.
//
// Pick who, then the ordinary payment dialog opens on their open items. Spread
// it over them, or not: what is not applied is kept as their credit, and a
// payment applied to nothing is an advance. One payment, one cash movement,
// whatever the split.

import { useEffect, useState } from "react"
import { HandCoins } from "lucide-react"
import { Button } from "@/components/ui/button"
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { RecordPaymentDialog, type CashAccountOption } from "@/components/balances/record-payment-dialog"
import { getCustomers } from "@/lib/api"
import { getSuppliers } from "@/lib/api/supplier"
import { getUserContext } from "@/lib/api/config"
import { listPoultryCashAccounts } from "@/lib/api/poultry-finance"
import type { PartyBalanceRow } from "@/lib/api/balances"

export function RecordCustomerPaymentButton({ onPosted }: { onPosted: () => void }) {
  return <RecordPartyPaymentButton side="customer" onPosted={onPosted} />
}

export function RecordPartyPaymentButton({ side, onPosted }: { side: "customer" | "supplier"; onPosted: () => void }) {
  const isCustomer = side === "customer"
  const word = isCustomer ? "customer" : "supplier"
  const [pickOpen, setPickOpen] = useState(false)
  const [customers, setCustomers] = useState<{ id: number; name: string }[]>([])
  const [customerId, setCustomerId] = useState("")
  const [party, setParty] = useState<PartyBalanceRow | null>(null)
  const [cashAccounts, setCashAccounts] = useState<CashAccountOption[]>([])

  useEffect(() => {
    if (!pickOpen) return
    setCustomerId("")
    const { userId, farmId } = getUserContext()
    const people: Promise<{ id: number; name: string }[]> = isCustomer
      ? getCustomers(userId, farmId).then((r: any) => {
          const list = (r?.success ? r.data : r) ?? []
          return (Array.isArray(list) ? list : [])
            .map((c: any) => ({ id: Number(c.customerId ?? c.id), name: String(c.name ?? c.customerName ?? "") }))
        })
      : getSuppliers(userId, farmId).then((r) => (r?.data ?? []).map((x) => ({ id: Number(x.supplierId), name: String(x.name ?? "") })))
    people
      .then((list) => setCustomers(list
        .filter((c) => c.id > 0 && c.name)
        .sort((a, b) => a.name.localeCompare(b.name))))
      .catch(() => setCustomers([]))
    listPoultryCashAccounts()
      .then((accounts) => setCashAccounts(accounts
        .filter((a) => a.isActive)
        .map((a) => ({
          id: a.poultryCashAccountId,
          name: a.accountName,
          currentBalance: a.currentBalance,
          allowNegativeBalance: a.allowNegativeBalance,
        }))))
      .catch(() => setCashAccounts([]))
  }, [pickOpen, isCustomer])

  const next = () => {
    const c = customers.find((x) => String(x.id) === customerId)
    if (!c) return
    setPickOpen(false)
    // Only the id and name are read by the dialog; the totals are not shown.
    setParty({
      partyId: c.id, partyName: c.name, paymentTermsDays: 0, totalBalance: 0, openDocumentCount: 0,
      overdueAmount: 0, totalInvoiced: 0, totalPaid: 0,
    })
  }

  return (
    <>
      <Button onClick={() => setPickOpen(true)} className={isCustomer ? "h-10 bg-sky-600 hover:bg-sky-700" : "h-10 bg-amber-600 hover:bg-amber-700"}>
        <HandCoins className="mr-1 h-4 w-4" /> Record {word} payment
      </Button>

      <Dialog open={pickOpen} onOpenChange={setPickOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Record {word} payment</DialogTitle>
            <DialogDescription>
              {isCustomer
                ? "Choose who paid. You can then apply the money to their open sales; whatever is not applied is kept as their credit."
                : "Choose who you paid. You can then apply the money to what you owe them; whatever is not applied is kept as supplier credit."}
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-1.5">
            <Label>{isCustomer ? "Customer" : "Supplier"} *</Label>
            <Select value={customerId} onValueChange={setCustomerId}>
              <SelectTrigger><SelectValue placeholder={customers.length ? `Choose the ${word}` : "Loading…"} /></SelectTrigger>
              <SelectContent>
                {customers.map((c) => <SelectItem key={c.id} value={String(c.id)}>{c.name}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setPickOpen(false)}>Cancel</Button>
            <Button onClick={next} disabled={!customerId}>Next</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <RecordPaymentDialog
        open={!!party}
        onOpenChange={(o) => { if (!o) setParty(null) }}
        module="poultry"
        side={side}
        party={party}
        cashAccounts={cashAccounts}
        sourceType={isCustomer ? "PaymentsPage" : "SupplierPayments"}
        // 383: money not applied to anything paid an old debt -- on Profit & Loss.
        remainderAsOldDebt
        onPosted={() => { setParty(null); onPosted() }}
      />
    </>
  )
}
