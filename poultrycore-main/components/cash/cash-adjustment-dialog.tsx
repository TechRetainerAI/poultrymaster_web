"use client"

/**
 * Add Adjustment — the /cash dialog, with an OPTIONAL cash account.
 *
 * Deliberately not the same thing as Record Cash Adjustment, which lives on the
 * cash accounts page and REQUIRES an account. The two exist because they answer
 * different questions:
 *
 *   Record Cash Adjustment   "this account's balance is wrong"     account required
 *   Add Adjustment (here)    "money moved and I want it recorded"  account optional
 *
 * The optional account is the whole point. Owner injections and opening balances
 * often arrive before anyone has decided which box the money sits in, and forcing
 * a choice there is how people either pick the wrong account or give up and
 * record nothing. Where it goes follows from that choice:
 *
 *   account chosen  ->  sppoultrycashaccount_adjust, straight into the ledger.
 *                       It moves that balance and Cash Flow counts it as normal.
 *   no account      ->  the legacy CashAdjustment table via POST /Cash/Adjustment.
 *                       Cash Flow still counts it, flagged "no account" — it is
 *                       in Money In/Out, Net and Cash at Hand. What it is NOT in
 *                       is any account balance, so reconciliation cannot see it.
 *
 * Both destinations already exist and both are already read by the Cash Flow
 * page, so nothing new has to be taught to display them.
 *
 * "Loan received" is the exception, and it leaves this dialog entirely. Picking
 * it is already a statement that the money is borrowed, so the page records a
 * REAL loan rather than a bare cash row — a lender, a balance, something to
 * repay against. That is why this type, and only this type, asks for a lender.
 * A negative one is a correction to an over-stated borrowing, not a borrowing,
 * so it stays an adjustment.
 *
 * "Owner injection" and "Withdrawal" leave the same way, for the same reason.
 * Picking either is already a statement that this is the owner's money moving
 * in or out, so the page records a REAL owner-money record rather than a bare
 * cash row. A bare row meant the Owner Money page had to read across into
 * cashadjustment to find it — and on Water it never appeared at all. Being the
 * record from the moment it is saved is what fixes that.
 *
 * Which is why, for those two and only those two, the cash account stops being
 * optional. The optional account above is a convenience for entries whose home
 * is genuinely undecided; owner money is not one of those. It came out of, or
 * went into, a real box, the owner-money record is anchored to that box, and
 * there is no version of the record without one.
 */

import { useEffect, useMemo, useState } from "react"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Loader2, Plus } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { entryTimestamp } from "@/lib/utils/date-key"

/** Same vocabulary the /cash page uses. Stored as text, so keep these stable. */
export const ADJUSTMENT_TYPES = [
  { value: "OpeningBalance", label: "Opening Balance" },
  { value: "OwnerInjection", label: "Owner injection" },
  { value: "LoanReceived",   label: "Loan received" },
  { value: "Withdrawal",     label: "Withdrawal" },
  { value: "Correction",     label: "Correction" },
] as const

export type AdjustmentTypeValue = (typeof ADJUSTMENT_TYPES)[number]["value"]

/**
 * Recover the stored value from the label the API hands back.
 *
 * GET /Cash returns the DISPLAY name ("Owner injection"), not the stored enum
 * ("OwnerInjection"), so an edit has to map back. Without this the type field
 * opens blank and quietly rewrites itself to whatever gets picked next.
 */
export function adjustmentTypeFromLabel(label: string | null | undefined): AdjustmentTypeValue | "" {
  const l = (label ?? "").trim().toLowerCase()
  return ADJUSTMENT_TYPES.find((t) => t.label.toLowerCase() === l)?.value ?? ""
}

/** Seed for editing an existing adjustment. `amount` is SIGNED, as stored. */
export type CashAdjustmentSeed = {
  adjustmentId: number
  adjustmentType: AdjustmentTypeValue | ""
  adjustmentDate: string
  amount: number
  description: string
}

/** Which way the money goes. Withdrawal is the only one that is always out. */
const ALWAYS_OUT = new Set<AdjustmentTypeValue>(["Withdrawal"])

export type AdjustableAccountOption = {
  accountId: number
  accountName: string
  isActive: boolean
}

export function CashAdjustmentDialog({
  open,
  onOpenChange,
  accounts,
  fmtMoney,
  editing,
  onSubmit,
  onDone,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  accounts: AdjustableAccountOption[]
  fmtMoney: (n: number) => string
  /** Present = editing that adjustment; absent = recording a new one. */
  editing?: CashAdjustmentSeed | null
  /**
   * accountId is null when none was chosen. amount is SIGNED.
   *
   * `lenderName` is set only for a new, positive "Loan received" — the one type
   * that is recorded as a real loan rather than a bare adjustment. It is null
   * for every other type, for an edit, and for a negative Loan received (which
   * is a correction to an over-stated borrowing, not a borrowing).
   *
   * `ownerName` is set only for a new "Owner injection" or "Withdrawal", the
   * two types recorded as real owner money. It stays OPTIONAL even there — a
   * farm with one owner has no need to name them on every entry — so null
   * means "not said", not "invalid". Null for every other type and every edit.
   */
  onSubmit: (input: {
    accountId: number | null
    adjustmentType: AdjustmentTypeValue
    adjustmentDate: string
    amount: number
    description: string
    lenderName: string | null
    ownerName: string | null
  }) => Promise<unknown>
  onDone?: () => void
}) {
  const { toast } = useToast()
  const [accountId, setAccountId] = useState<string>("none")
  const [type, setType] = useState<AdjustmentTypeValue | "">("")
  const [when, setWhen] = useState(() => new Date().toISOString().split("T")[0])
  const [amount, setAmount] = useState<number | undefined>(undefined)
  const [description, setDescription] = useState("")
  const [lender, setLender] = useState("")
  const [owner, setOwner] = useState("")
  const [saving, setSaving] = useState(false)

  const active = useMemo(() => accounts.filter((a) => a.isActive), [accounts])

  useEffect(() => {
    if (!open) return
    if (editing) {
      // Only unlinked adjustments are editable here, so the account stays "none".
      setAccountId("none")
      setType(editing.adjustmentType)
      setWhen((editing.adjustmentDate || new Date().toISOString()).split("T")[0])
      // Shown unsigned; the sign is re-derived from the type on save exactly as
      // it is for a new one, so an edited Withdrawal cannot come back positive.
      setAmount(Math.abs(editing.amount))
      setDescription(editing.description ?? "")
      // An edit stays an adjustment edit, so neither a lender nor an owner is
      // collected here — it updates a row that already exists and creates
      // nothing.
      setLender("")
      setOwner("")
      return
    }
    // Defaults to "none" on purpose — not to the only account. Guessing which
    // box the money went into is the mistake this dialog exists to avoid.
    setAccountId("none")
    setType("")
    setWhen(new Date().toISOString().split("T")[0])
    setAmount(undefined)
    setDescription("")
    setLender("")
    setOwner("")
  }, [open, editing])

  const entered = amount !== undefined && !Number.isNaN(amount) && amount > 0
  const signed = entered && type
    ? (ALWAYS_OUT.has(type) ? -Math.abs(amount!) : Math.abs(amount!))
    : 0
  const linked = accountId !== "none"

  /**
   * "Loan received" is not an adjustment — it is a loan, and the page records
   * it as one so it can be repaid. That needs a lender, which is why the field
   * appears only here and is required.
   *
   * Not on an edit: that path updates an existing adjustment row and creates
   * nothing. And not on a negative amount, which is a correction to an
   * over-stated borrowing — a loan cannot have a negative principal.
   */
  const asLoan = !editing && type === "LoanReceived"
  const lenderMissing = asLoan && signed > 0 && !lender.trim()

  /**
   * Owner injection and Withdrawal are not adjustments either — they are the
   * owner's own money moving, and the page records each as a real owner-money
   * record so the Owner Money page owns it instead of hunting for it.
   *
   * Not on an edit, same as the loan: that path updates an existing adjustment
   * row and creates nothing.
   */
  const asOwnerMoney = !editing && (type === "OwnerInjection" || type === "Withdrawal")
  /**
   * The one place this dialog's optional account stops being optional. An
   * owner-money record is anchored to the account the money actually moved
   * through, so "not linked" is not a state it can be saved in.
   */
  const accountMissing = asOwnerMoney && !linked

  const canSubmit = !!type && entered && !lenderMissing && !accountMissing && !saving

  async function submit() {
    if (!canSubmit || !type) return
    setSaving(true)
    try {
      await onSubmit({
        accountId: linked ? Number(accountId) : null,
        adjustmentType: type,
        // Recorded now, so it carries the real clock time and sorts above
        // everything already entered today. A back-dated one stays at
        // midnight. Same rule the payment dialogs use.
        adjustmentDate: entryTimestamp(when) ?? when,
        amount: signed,
        description: description.trim(),
        lenderName: asLoan && signed > 0 ? lender.trim() : null,
        // Optional by design: blank means "not said", so send null rather than
        // an empty string the record would have to store as a name.
        ownerName: asOwnerMoney ? (owner.trim() || null) : null,
      })
      const account = active.find((a) => String(a.accountId) === accountId)?.accountName ?? "the account"
      toast({
        title: asLoan && signed > 0 ? "Loan recorded"
             : asOwnerMoney ? (signed < 0 ? "Withdrawal recorded" : "Owner injection recorded")
             : editing && linked ? "Adjustment linked"
             : editing ? "Adjustment updated"
             : "Adjustment recorded",
        description: asLoan && signed > 0
          ? `${fmtMoney(signed)} borrowed from ${lender.trim()}. It is on your Loans page, where you can record repayments against it.`
          : asOwnerMoney
          ? `${fmtMoney(Math.abs(signed))} ${signed < 0 ? "taken out of" : "put into"} ${account} by ${owner.trim() || "the owner"}. It is on your Owner Money page.`
          : editing && linked
          ? `${fmtMoney(Math.abs(signed))} now sits in ${account}.`
          : linked
          ? `${fmtMoney(Math.abs(signed))} ${signed < 0 ? "removed from" : "added to"} ${account}.`
          : `${fmtMoney(Math.abs(signed))} recorded. It counts toward Cash Flow's totals and Cash at Hand, but sits in no account balance until you link it.`,
      })
      onOpenChange(false)
      onDone?.()
    } catch (e: any) {
      toast({
        title: asLoan && signed > 0 ? "Couldn't record the loan"
             : asOwnerMoney ? "Couldn't record the owner money"
             : editing && linked ? "Couldn't link the adjustment"
             : editing ? "Couldn't update the adjustment"
             : "Couldn't record the adjustment",
        description: e?.message, variant: "destructive",
      })
    } finally {
      setSaving(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={(o) => { if (!saving) onOpenChange(o) }}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Plus className="h-5 w-5 text-emerald-600" />
            {editing ? "Edit Adjustment" : "Add Adjustment"}
          </DialogTitle>
          <DialogDescription>
            Opening balance, owner injection, loan received, withdrawal or correction.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <FormSection title="Adjustment" color="emerald" columns={2}>
            <FormField label="Type *">
              <Select value={type} onValueChange={(v) => setType(v as AdjustmentTypeValue)}>
                <SelectTrigger><SelectValue placeholder="What kind of adjustment?" /></SelectTrigger>
                <SelectContent>
                  {ADJUSTMENT_TYPES.map((t) => (
                    <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </FormField>

            <FormField label="Date *">
              <Input type="date" value={when} onChange={(e) => setWhen(e.target.value)} />
            </FormField>

            <FormField label="Amount *">
              <NumberInput
                min={0}
                step="0.01"
                value={amount ?? ""}
                onChange={(e) => setAmount(e.target.value === "" ? undefined : parseFloat(e.target.value))}
              />
            </FormField>

            {/* Required for owner money only — see `accountMissing`. Every
                other type keeps the optional account this dialog exists for. */}
            <FormField label={asOwnerMoney ? "Cash account *" : "Cash account"}>
              <Select value={accountId} onValueChange={setAccountId}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {/* Kept even when required, so the trigger never renders
                      blank on a type switch. The hint below says why it will
                      not do, the same way the lender field does. */}
                  <SelectItem value="none">Not linked to an account</SelectItem>
                  {active.map((a) => (
                    <SelectItem key={a.accountId} value={String(a.accountId)}>
                      {a.accountName}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {accountMissing && (
                <p className="mt-1 text-[11px] leading-snug text-rose-600">
                  {type === "Withdrawal"
                    ? "Say which account the money came out of — owner money is recorded against a real account."
                    : "Say which account the money went into — owner money is recorded against a real account."}
                </p>
              )}
              {/* Choosing an account while editing MOVES the adjustment into the
                  ledger — a different table, not a field update. Say so, because
                  it is a one-way step: it can be reversed on the account
                  afterwards, but not un-edited back to unlinked. */}
              {editing && linked && (
                <p className="mt-1 text-[11px] leading-snug text-amber-700">
                  This moves the adjustment into the account ledger. It cannot be
                  changed back to unlinked afterwards.
                </p>
              )}
            </FormField>
            {/* Only for a loan, because only a loan has a lender. Asking for it
                here is what makes the borrowing repayable later — without a
                lender there is no debt record, only a cash event. */}
            {asLoan && (
              <FormField label="Lender *">
                <Input
                  value={lender}
                  onChange={(e) => setLender(e.target.value)}
                  placeholder="Who lent the money?"
                />
                {lenderMissing && (
                  <p className="mt-1 text-[11px] leading-snug text-rose-600">
                    A loan needs a lender before it can be recorded.
                  </p>
                )}
              </FormField>
            )}
            {/* Optional on purpose, unlike the lender. A loan without a lender
                is not a loan; owner money without a name is still owner money,
                and most farms have one owner nobody needs to re-type. */}
            {asOwnerMoney && (
              <FormField label="Owner name (optional)">
                <Input
                  value={owner}
                  onChange={(e) => setOwner(e.target.value)}
                  placeholder={type === "Withdrawal" ? "Who took it?" : "Who put it in?"}
                />
              </FormField>
            )}
          </FormSection>

          <FormSection title="Description" color="slate" columns={1}>
            <FormField label="Description (optional)">
              <Input
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                placeholder="e.g. Start of cycle"
              />
            </FormField>
          </FormSection>

          {/* Say where it lands before they commit, because the two destinations
              behave differently and the difference is not guessable. */}
          {entered && type && (
            <p className="rounded-md border border-slate-200 bg-slate-50 p-2 text-[11px] leading-snug text-slate-600">
              {asLoan && signed > 0 ? (
                <>
                  {fmtMoney(signed)} will be recorded as a <b>loan you can repay</b>, not just a cash
                  entry — it appears on your Loans page with {lender.trim() || "the lender"} against
                  it.{" "}
                  {linked ? (
                    <>
                      The money lands in{" "}
                      <b>{active.find((a) => String(a.accountId) === accountId)?.accountName}</b>,
                      moving its balance.
                    </>
                  ) : (
                    <>Cash Flow counts the money in; no account balance changes until you link it.</>
                  )}
                </>
              ) : asOwnerMoney ? (
                <>
                  {fmtMoney(Math.abs(signed))} will be recorded as <b>owner money</b>, not just a cash
                  entry — {signed < 0 ? "a draw" : "a contribution"} on your Owner Money page
                  {owner.trim() ? <> from <b>{owner.trim()}</b></> : null}.{" "}
                  {linked ? (
                    <>
                      The money moves {signed < 0 ? "out of" : "into"}{" "}
                      <b>{active.find((a) => String(a.accountId) === accountId)?.accountName}</b>,
                      changing its balance, and Cash Flow counts it once.
                    </>
                  ) : (
                    <>Pick the cash account it moved through first — owner money is recorded against one.</>
                  )}
                </>
              ) : linked && editing ? (
                <>
                  {fmtMoney(Math.abs(signed))} will be moved{" "}
                  {signed < 0 ? "out of" : "into"}{" "}
                  <b>{active.find((a) => String(a.accountId) === accountId)?.accountName}</b> and the
                  unlinked copy removed, so it is counted once. The account balance moves.
                </>
              ) : linked ? (
                <>
                  {fmtMoney(Math.abs(signed))} will be posted {signed < 0 ? "out of" : "into"}{" "}
                  <b>{active.find((a) => String(a.accountId) === accountId)?.accountName}</b>, moving
                  its balance. It appears in the ledger and can be reversed.
                </>
              ) : (
                <>
                  {fmtMoney(Math.abs(signed))} will be recorded without a cash account. Cash Flow
                  counts it in Money In/Out and Cash at Hand, but no account balance changes until
                  you link it.
                </>
              )}
            </p>
          )}

          <div className="flex gap-3 justify-end pt-2">
            <Button type="button" variant="ghost" onClick={() => onOpenChange(false)} disabled={saving}>
              Cancel
            </Button>
            <Button onClick={submit} disabled={!canSubmit}>
              {saving ? (<><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</>)
                      : asLoan && signed > 0 ? "Record loan"
                      : asOwnerMoney ? (signed < 0 ? "Record withdrawal" : "Record injection")
                      : editing && linked ? "Link to account"
                      : editing ? "Update adjustment" : "Save adjustment"}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}
