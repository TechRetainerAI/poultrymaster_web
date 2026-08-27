/**
 * The words a reconciliation uses, chosen by what kind of account it is.
 *
 * "Count the drawer" is nonsense for a bank account and "statement balance" is
 * nonsense for a cash box, but the mechanism behind both is identical: compare
 * what the account really holds against what the ledger says, and post the
 * difference. So the vocabulary is data, not a branch in the flow — nothing
 * here changes what is written, only what is read.
 *
 * Account types come from the SP layer as plain strings (see 047/128 and
 * *_CASH_ACCOUNT_TYPES). They are matched case-insensitively and an unknown one
 * falls through to the neutral wording, so a type added in the database later
 * degrades to "Reconcile Account" rather than to a blank label.
 */

export type CashAccountCategory = "cash" | "bank" | "momo" | "other"

export type CashAccountVocabulary = {
  category: CashAccountCategory
  /** Button in the page header, and the modal title. */
  action: string
  /** Label above the amount input. */
  amountLabel: string
  /** What that amount IS, for prose: "Physical Cash Balance" etc. */
  balanceTerm: string
  /** Where to go and get the figure. */
  helper: string
  /** Placeholder-length version of `helper`, for a card subtitle. */
  shortHelper: string
  /** What one of these records is called: "cash count", "bank reconciliation". */
  recordNoun: string
  /** Sentence for an account that has never been reconciled. */
  emptyHistory: string
}

/**
 * Physical-cash types across all three modules. Water (047) has FactoryCashBox
 * and DriverCash; Poultry (128) has FarmCashBox instead of FactoryCashBox. Both
 * lists are here on purpose: this module is shared, and a Poultry account must
 * not fall through to the neutral wording just because Water named its cash box
 * differently.
 */
const CASH_TYPES = [
  "factorycashbox",
  "farmcashbox",
  "ownercash",
  "pettycash",
  "drivercash",
  "cash",
]

const VOCAB: Record<CashAccountCategory, CashAccountVocabulary> = {
  cash: {
    category: "cash",
    action: "Reconcile Cash Balance",
    amountLabel: "Amount Counted",
    balanceTerm: "Physical Cash Balance",
    helper: "Count what is physically in the drawer, box or safe, and enter the total.",
    shortHelper: "What you physically counted.",
    recordNoun: "cash count",
    emptyHistory: "This account has never been counted.",
  },
  bank: {
    category: "bank",
    action: "Reconcile Bank Account",
    amountLabel: "Statement Balance",
    balanceTerm: "Bank Balance",
    helper: "Check the bank statement or banking app, and enter the balance it shows.",
    shortHelper: "The balance on the statement or in the banking app.",
    recordNoun: "bank reconciliation",
    emptyHistory: "This account has never been reconciled against a statement.",
  },
  momo: {
    category: "momo",
    action: "Reconcile MoMo Account",
    amountLabel: "MoMo Balance",
    balanceTerm: "MoMo Balance",
    helper: "Check the current MoMo balance on the phone or app, and enter it.",
    shortHelper: "The balance currently showing on MoMo.",
    recordNoun: "MoMo reconciliation",
    emptyHistory: "This account has never been reconciled against MoMo.",
  },
  other: {
    category: "other",
    action: "Reconcile Account",
    amountLabel: "Actual Balance",
    balanceTerm: "Actual Balance",
    helper: "Enter the balance this account actually holds.",
    shortHelper: "What this account actually holds.",
    recordNoun: "reconciliation",
    emptyHistory: "This account has never been reconciled.",
  },
}

export function cashAccountCategory(accountType?: string | null): CashAccountCategory {
  const t = (accountType ?? "").trim().toLowerCase()
  if (!t) return "other"
  if (t === "bankaccount" || t === "bank") return "bank"
  if (t === "momowallet" || t === "momo") return "momo"
  if (CASH_TYPES.includes(t)) return "cash"
  return "other"
}

export function cashAccountVocabulary(accountType?: string | null): CashAccountVocabulary {
  return VOCAB[cashAccountCategory(accountType)]
}
