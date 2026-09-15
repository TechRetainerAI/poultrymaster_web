"use client"

// Generic Supplier Balances (Purchases & Suppliers → Supplier Balances).
//
// Thin, like the poultry and water twins: everything lives in <BalancesPage>.
// All this file decides is which module it is, where a supplier and a bill
// live, and which permission keys apply.
//
// This page is what migration 248 unlocked. Before it, genericexpenses had no
// amountpaid, duedate or paymentstatus at all, so a Generic company could
// record what it spent but never what it still owed — and an approved supplier
// payment moved the supplier's balance and the cash account while every
// purchase it was meant to settle kept its original balance.

import { BalancesPage } from "@/components/balances/balances-page"
import { getCashAccounts } from "@/lib/api/generic"

export default function GenericSupplierBalancesPage() {
  return (
    <BalancesPage
      module="generic"
      side="supplier"
      companyType="Generic"
      // A Generic supplier payment posts exactly one CashOut against the
      // account chosen here.
      loadCashAccounts={async () => {
        const accounts = await getCashAccounts()
        return accounts
          .filter((a) => a.isActive)
          .map((a) => ({
            id: a.genericCashAccountId,
            name: a.accountName,
            currentBalance: a.currentBalance,
            allowNegativeBalance: a.allowNegativeBalance,
          }))
      }}
      partyHref={() => "/generic-suppliers"}
      // Generic payables span TWO tables, so the link depends on which kind of
      // bill the row is. Expenses and purchases have separate pages.
      documentHref={(doc) =>
        doc.documentType === "Expense"
          ? `/generic-expenses?expenseId=${doc.documentId}`
          : `/generic-purchases?purchaseId=${doc.documentId}`
      }
      permissions={{
        view: "generic.supplier-balances.view",
        pay: "generic.supplier-payments.create",
        reverse: "generic.supplier-payments.reverse",
        statement: "generic.supplier-statements.view",
      }}
    />
  )
}
