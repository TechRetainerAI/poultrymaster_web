/**
 * Reason lists for reversing, cancelling or reopening. Every such action picks its reason
 * from a list; "Other" opens a text box so the user can type their own -- a
 * list never covers everything, and forcing the nearest wrong option is worse
 * than free text. The chosen value is what is stored, so the wording here IS
 * the stored vocabulary: reword with care.
 *
 * Used by ReasonSelect (inline fields) and PromptDialog `options`.
 */

export type ReasonOption = { value: string; label: string }

const opt = (value: string): ReasonOption => ({ value, label: value })

/** Money entries: payments, refunds, transfers, owner money, debts, loans. */
export const REVERSAL_REASONS: readonly ReasonOption[] = [
  opt("Duplicate entry"),
  opt("Wrong amount"),
  opt("Wrong date"),
  opt("Wrong account"),
  opt("Wrong customer or supplier"),
  opt("Posted by mistake"),
  opt("Test or training entry"),
  opt("Other"),
]

/** Stock movements, receipts and production postings. */
export const STOCK_REVERSAL_REASONS: readonly ReasonOption[] = [
  opt("Duplicate entry"),
  opt("Wrong quantity"),
  opt("Wrong product"),
  opt("Wrong date"),
  opt("Wrong flock or batch"),
  opt("Posted by mistake"),
  opt("Test or training entry"),
  opt("Other"),
]

/** Capital assets: capitalised costs, depreciation, in-service changes. */
export const ASSET_REVERSAL_REASONS: readonly ReasonOption[] = [
  opt("Duplicate entry"),
  opt("Wrong amount"),
  opt("Wrong asset"),
  opt("Wrong month"),
  opt("Posted by mistake"),
  opt("Test or training entry"),
  opt("Other"),
]

/** Cash counts and cash account adjustments. */
export const CASH_COUNT_REVERSAL_REASONS: readonly ReasonOption[] = [
  opt("Miscounted"),
  opt("Counted the wrong account"),
  opt("Wrong amount entered"),
  opt("Wrong date"),
  opt("Duplicate count"),
  opt("Cash located afterwards"),
  opt("Posted by mistake"),
  opt("Other"),
]

/** Cancelling a draft, a run, a schedule or a campaign. */
export const CANCEL_REASONS: readonly ReasonOption[] = [
  opt("Created by mistake"),
  opt("Duplicate entry"),
  opt("Wrong details"),
  opt("No longer needed"),
  opt("Plans changed"),
  opt("Test or training entry"),
  opt("Other"),
]

/** Cancelling a customer's subscription. */
export const SUBSCRIPTION_CANCEL_REASONS: readonly ReasonOption[] = [
  opt("Customer asked to cancel"),
  opt("Customer stopped paying"),
  opt("Customer moved away"),
  opt("Switched to another plan"),
  opt("Created by mistake"),
  opt("Duplicate entry"),
  opt("Other"),
]

/** Reopening a closed day, an approved payroll run or a record. */
export const REOPEN_REASONS: readonly ReasonOption[] = [
  opt("Correction needed"),
  opt("Missing entry to add"),
  opt("Wrong amount"),
  opt("Wrong date"),
  opt("Document arrived late"),
  opt("Closed too early"),
  opt("Other"),
]

/** Reopening a closed flock. */
export const FLOCK_REOPEN_REASONS: readonly ReasonOption[] = [
  opt("Closed by mistake"),
  opt("Birds still on the farm"),
  opt("Late sale or record to enter"),
  opt("Wrong close date"),
  opt("Wrong closing figures"),
  opt("Other"),
]

/** Reopening a lifecycle task. */
export const TASK_REOPEN_REASONS: readonly ReasonOption[] = [
  opt("Marked done by mistake"),
  opt("Task not actually done"),
  opt("Needs to be done again"),
  opt("Other"),
]

/** Loans and staff advances. */
export const LOAN_REVERSAL_REASONS: readonly ReasonOption[] = [
  opt("Duplicate entry"),
  opt("Wrong amount"),
  opt("Wrong date"),
  opt("Wrong employee or lender"),
  opt("Wrong account"),
  opt("Posted by mistake"),
  opt("Other"),
]

// ---------------------------------------------------------------------------
// Every other reason asked for in a modal (user request 2026-10-15: all
// reasons in modals are a dropdown, with "Other" to type one).
// ---------------------------------------------------------------------------

/** Rejecting a submitted daily closing or stock adjustment. */
export const REJECT_REASONS: readonly ReasonOption[] = [
  opt("Figures do not match"),
  opt("Cash difference not explained"),
  opt("Missing entries"),
  opt("Wrong date"),
  opt("Needs more detail"),
  opt("Other"),
]

/** Rejecting a guest's online order -- the guest sees this. */
export const ORDER_REJECT_REASONS: readonly ReasonOption[] = [
  opt("Item not available"),
  opt("Kitchen is closed"),
  opt("Kitchen is too busy right now"),
  opt("Outside our delivery area"),
  opt("Could not reach you"),
  opt("Duplicate order"),
  opt("Other"),
]

/** Refunding a restaurant order. */
export const ORDER_REFUND_REASONS: readonly ReasonOption[] = [
  opt("Wrong dish served"),
  opt("Item not available"),
  opt("Quality complaint"),
  opt("Long wait"),
  opt("Overcharged"),
  opt("Order cancelled"),
  opt("Other"),
]

/** Skipping a scheduled task or a recurring expense this time. */
export const SKIP_REASONS: readonly ReasonOption[] = [
  opt("Not needed this time"),
  opt("Already done another way"),
  opt("Postponed"),
  opt("Supplier or service not available"),
  opt("Other"),
]

/** Ending a recurring expense. */
export const END_REASONS: readonly ReasonOption[] = [
  opt("No longer needed"),
  opt("Contract ended"),
  opt("Replaced by another arrangement"),
  opt("Paying it differently now"),
  opt("Other"),
]

/** Taking back an approval (e.g. a water loss record). */
export const UNAPPROVE_REASONS: readonly ReasonOption[] = [
  opt("Wrong quantity"),
  opt("Wrong cause"),
  opt("Wrong date"),
  opt("Approved by mistake"),
  opt("Other"),
]

/** Adjusting stock by hand. */
export const STOCK_ADJUSTMENT_REASONS: readonly ReasonOption[] = [
  opt("Stocktake correction"),
  opt("Damaged"),
  opt("Expired"),
  opt("Spoiled"),
  opt("Theft or missing"),
  opt("Found extra stock"),
  opt("Opening stock"),
  opt("Data entry correction"),
  opt("Other"),
]

/** Recording a loss. */
export const LOSS_REASONS: readonly ReasonOption[] = [
  opt("Damaged"),
  opt("Spoiled"),
  opt("Expired"),
  opt("Breakage"),
  opt("Spillage or leak"),
  opt("Pest damage"),
  opt("Theft"),
  opt("Other"),
]

/** Why a treatment campaign is run. */
export const TREATMENT_REASONS: readonly ReasonOption[] = [
  opt("Routine vaccination"),
  opt("Vet diagnosis"),
  opt("Disease outbreak"),
  opt("Preventive treatment"),
  opt("Deworming"),
  opt("Vitamins or supplements"),
  opt("Other"),
]

/** Adjusting a sized-egg class by hand. */
export const EGG_ADJUSTMENT_REASONS: readonly ReasonOption[] = [
  opt("Tray dropped"),
  opt("Breakage found"),
  opt("Miscount"),
  opt("Spoiled"),
  opt("Found extra eggs"),
  opt("Other"),
]

/** Correcting an asset's original cost. */
export const COST_CORRECTION_REASONS: readonly ReasonOption[] = [
  opt("Wrong amount entered"),
  opt("Supplier invoice corrected"),
  opt("Missing cost added"),
  opt("Duplicate cost removed"),
  opt("Other"),
]

/** Recording a manual deferred cost on stock no purchase covers. */
export const DEFERRED_COST_REASONS: readonly ReasonOption[] = [
  opt("Stock on hand before using the system"),
  opt("Opening stock cost"),
  opt("Cost not captured on the purchase"),
  opt("Correction"),
  opt("Other"),
]

/** Refunding a customer's credit. */
export const CUSTOMER_REFUND_REASONS: readonly ReasonOption[] = [
  opt("Customer asked for their money"),
  opt("Overpayment returned"),
  opt("Order cancelled"),
  opt("Customer no longer buying"),
  opt("Other"),
]

/** A supplier refunding our credit. */
export const SUPPLIER_REFUND_REASONS: readonly ReasonOption[] = [
  opt("Unused advance returned"),
  opt("Overpayment returned"),
  opt("Order cancelled"),
  opt("Goods returned"),
  opt("Other"),
]

/** Customer credit added by hand, by kind. */
export const CUSTOMER_CREDIT_REASONS: Record<"OpeningCredit" | "Deposit" | "CreditNote", readonly ReasonOption[]> = {
  OpeningCredit: [opt("Balance carried from old books"), opt("Prepaid balance"), opt("Other")],
  Deposit: [opt("Advance for next order"), opt("Prepayment for a bulk order"), opt("Deposit to hold an order"), opt("Other")],
  CreditNote: [opt("Damaged goods"), opt("Short delivery"), opt("Returned goods"), opt("Price adjustment"), opt("Goodwill"), opt("Other")],
}

/** Supplier credit added by hand (credit note, opening or manual credit). */
export const SUPPLIER_CREDIT_REASONS: readonly ReasonOption[] = [
  opt("Short delivery"),
  opt("Damaged goods"),
  opt("Returned goods"),
  opt("Price adjustment"),
  opt("Balance carried from old books"),
  opt("Other"),
]

/** Explaining a cash difference at closing. */
export const CASH_DIFFERENCE_REASONS: readonly ReasonOption[] = [
  opt("Miscount"),
  opt("Wrong change given"),
  opt("Expense not recorded"),
  opt("Sale not recorded"),
  opt("Cash taken by the owner"),
  opt("Other"),
]

/** Overriding a person's permissions. */
export const PERMISSION_OVERRIDE_REASONS: readonly ReasonOption[] = [
  opt("Covering for a colleague"),
  opt("Role change pending"),
  opt("Extra responsibility"),
  opt("Temporary access"),
  opt("Other"),
]

/** Changing a company's billing market. */
export const MARKET_CHANGE_REASONS: readonly ReasonOption[] = [
  opt("Business relocated"),
  opt("Wrong country was set"),
  opt("Billing currency change"),
  opt("Other"),
]
