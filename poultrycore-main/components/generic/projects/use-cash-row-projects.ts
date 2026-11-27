"use client"

// The Project / contract column on Generic Cash Flow: which project(s) each
// cash-flow row belongs to, found through the document it was posted for --
// the same document -> project shares the Financial Activity and project cash
// flow use (493). Rows that are company-wide (transfers, adjustments) are General.

import { useCallback, useEffect, useState } from "react"
import { useProjectLabels } from "@/hooks/use-project-labels"
import { getAllLoanPayments } from "@/lib/api/generic"

type Row = { id: number; rowSource: string; sourceId: number | null }

export function useCashRowProjects(reloadKey?: unknown) {
  const sale = useProjectLabels("Sale", reloadKey)
  const receipt = useProjectLabels("CustomerPayment", reloadKey)
  const expense = useProjectLabels("Expense", reloadKey)
  const purchase = useProjectLabels("Purchase", reloadKey)
  const supplierPay = useProjectLabels("SupplierPayment", reloadKey)
  const owner = useProjectLabels("OwnerEntry", reloadKey)
  const payroll = useProjectLabels("PayrollRun", reloadKey)
  const loan = useProjectLabels("Loan", reloadKey)
  const enabled = sale.enabled

  // A loan repayment row carries the payment id; its project is the loan's.
  const [loanOfPayment, setLoanOfPayment] = useState<Map<number, number>>(new Map())
  useEffect(() => {
    if (!enabled) return
    let cancelled = false
    getAllLoanPayments()
      .then((ps) => { if (!cancelled) setLoanOfPayment(new Map(ps.map((p) => [p.genericLoanPaymentId, p.genericLoanId]))) })
      .catch(() => {})
    return () => { cancelled = true }
  }, [enabled, reloadKey])

  const labelsOf = useCallback((r: Row): string[] => {
    switch (r.rowSource) {
      case "Receipt": case "ReceiptReversal": return receipt.labelsOf(r.id)
      case "SaleResidual": return sale.labelsOf(r.id)
      case "SaleRefund": return sale.labelsOf(r.sourceId)
      case "Expense": return expense.labelsOf(r.id)
      // A reversed expense's refund (504_Enock): sourceId is the expense.
      case "ExpenseRefund": return expense.labelsOf(r.sourceId)
      case "PurchasePayment": return purchase.labelsOf(r.id)
      case "PurchaseRefund": return purchase.labelsOf(r.sourceId)
      case "SupplierPayment": return supplierPay.labelsOf(r.id)
      case "OwnerContribution": case "OwnerDraw": return owner.labelsOf(r.id)
      case "Payroll": return payroll.labelsOf(r.sourceId)
      case "LoanReceived": return loan.labelsOf(r.id)
      case "LoanRepayment": return loan.labelsOf(loanOfPayment.get(r.id))
      default: return []
    }
  }, [sale, receipt, expense, purchase, supplierPay, owner, payroll, loan, loanOfPayment])

  return { enabled, labelsOf }
}
