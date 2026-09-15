"use client"

// Generic Customer Balances (Sales & Money → Customer Balances).
//
// Thin, like the poultry and water twins: everything lives in <BalancesPage>.
// All this file decides is which module it is, where a customer and an invoice
// live, and which permission keys apply.
//
// This page is what migration 244 unlocked. Before it, an approved Generic
// customer payment moved the customer's balance and the cash account but left
// every sale showing its original unpaid balance, because
// GenericCustomerPayments.LinkedSaleId was written by _Insert and read by
// nothing.

import { BalancesPage } from "@/components/balances/balances-page"
import { getCashAccounts } from "@/lib/api/generic"
import { useGenericModules } from "@/hooks/use-generic-modules"

export default function GenericCustomerBalancesPage() {
  // The shared page speaks "customer" and "sale" by default. A gym's owner
  // reads "member" and "membership bill" instead -- same table, same API, same
  // permissions, different words.
  const { labels } = useGenericModules()

  return (
    <BalancesPage
      module="generic"
      side="customer"
      companyType="Generic"
      // Unlike water, a Generic payment DOES post cash: the recording function
      // writes exactly one CashIn against the account chosen here.
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
      partyHref={() => "/generic-customers"}
      // Invoices and counter sales are the same table, so both deep-link into
      // the Sales page with the row highlighted.
      documentHref={(doc) => `/generic-sales?saleId=${doc.documentId}`}
      permissions={{
        view: "generic.customer-balances.view",
        pay: "generic.customer-payments.create",
        reverse: "generic.customer-payments.reverse",
        statement: "generic.customer-statements.view",
      }}
      wording={{
        party: labels.customer.toLowerCase(),
        partyPlural: labels.customerPlural.toLowerCase(),
        title: labels.customerBalance,
        document: labels.invoice.toLowerCase(),
      }}
    />
  )
}
