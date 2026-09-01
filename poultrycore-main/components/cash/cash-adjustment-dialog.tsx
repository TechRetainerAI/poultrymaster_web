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
  /** accountId is null when none was chosen. amount is SIGNED. */
  onSubmit: (input: {
    accountId: number | null
    adjustmentType: AdjustmentTypeValue
    adjustmentDate: string
    amount: number
    description: string
  }) => Promise<unknown>
  onDone?: () => void
}) {
  const { toast } = useToast()
  const [accountId, setAccountId] = useState<string>("none")
  const [type, setType] = useState<AdjustmentTypeValue | "">("")
  const [when, setWhen] = useState(() => new Date().toISOString().split("T")[0])
  const [amount, setAmount] = useState<number | undefined>(undefined)
  const [description, setDescription] = useState("")
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
      return
    }
    // Defaults to "none" on purpose — not to the only account. Guessing which
    // box the money went into is the mistake this dialog exists to avoid.
    setAccountId("none")
    setType("")
    setWhen(new Date().toISOString().split("T")[0])
    setAmount(undefined)
    setDescription("")
  }, [open, editing])

  const entered = amount !== undefined && !Number.isNaN(amount) && amount > 0
  const canSubmit = !!type && entered && !saving
  const signed = entered && type
    ? (ALWAYS_OUT.has(type) ? -Math.abs(amount!) : Math.abs(amount!))
    : 0
  const linked = accountId !== "none"

  async function submit() {
    if (!canSubmit || !type) return
    setSaving(true)
    try {
      await onSubmit({
        accountId: linked ? Number(accountId) : null,
        adjustmentType: type,
        adjustmentDate: when,
        amount: signed,
        description: description.trim(),
      })
      const account = active.find((a) => String(a.accountId) === accountId)?.accountName ?? "the account"
      toast({
        title: editing && linked ? "Adjustment linked"
             : editing ? "Adjustment updated"
             : "Adjustment recorded",
        description: editing && linked
          ? `${fmtMoney(Math.abs(signed))} now sits in ${account}.`
          : linked
          ? `${fmtMoney(Math.abs(signed))} ${signed < 0 ? "removed from" : "added to"} ${account}.`
          : `${fmtMoney(Math.abs(signed))} recorded. It counts toward Cash Flow's totals and Cash at Hand, but sits in no account balance until you link it.`,
      })
      onOpenChange(false)
      onDone?.()
    } catch (e: any) {
      toast({
        title: editing && linked ? "Couldn't link the adjustment"
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

            <FormField label="Cash account">
              <Select value={accountId} onValueChange={setAccountId}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">Not linked to an account</SelectItem>
                  {active.map((a) => (
                    <SelectItem key={a.accountId} value={String(a.accountId)}>
                      {a.accountName}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
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
              {linked && editing ? (
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
                      : editing && linked ? "Link to account"
                      : editing ? "Update adjustment" : "Save adjustment"}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}
