"use client"

/**
 * Record Cash Adjustment.
 *
 * The account is REQUIRED, and that is the whole difference from the dialog this
 * replaces. The old /cash adjustment posted to no account at all, which is why
 * its rows never reached the cash ledger and vanished from every per-account
 * balance. Money has to move out of, or into, somewhere.
 *
 * Cash shortage and cash overage deliberately steer to Reconcile instead. An
 * adjustment silences the difference; reconciling records it, keeps the evidence
 * and can be reversed. Recording a shortage as a casual adjustment is how a real
 * loss gets buried.
 */

import { useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { FormSection, FormField } from "@/components/ui/form-section"
import { Loader2, Scale, ArrowRight } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { cn } from "@/lib/utils"

/** Reasons that mean "reality disagreed with the books", which Reconcile handles
 *  properly — with the figure that was checked, the evidence, and a reversal. */
const RECONCILE_REASONS = new Set(["Cash shortage", "Cash overage"])

/** Rail-agnostic: Poultry and Water both map their own id field onto this. */
export type AdjustableAccount = {
  accountId: number
  accountName: string
  accountType?: string | null
  isActive: boolean
}

export function RecordCashAdjustmentDialog({
  open,
  onOpenChange,
  accounts,
  reasons,
  fmtMoney,
  reconcileHref,
  onSubmit,
  onDone,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  accounts: AdjustableAccount[]
  reasons: readonly { value: string; label: string }[]
  fmtMoney: (n: number) => string
  reconcileHref: string
  /** amount is SIGNED: positive adds cash, negative removes it. */
  onSubmit: (input: { accountId: number; amount: number; reason: string }) => Promise<unknown>
  onDone?: () => void
}) {
  const { toast } = useToast()
  const [accountId, setAccountId] = useState<number | null>(null)
  const [direction, setDirection] = useState<"in" | "out">("in")
  const [amount, setAmount] = useState<number | undefined>(undefined)
  const [reason, setReason] = useState("")
  const [reasonNote, setReasonNote] = useState("")
  const [saving, setSaving] = useState(false)

  const active = useMemo(() => accounts.filter((a) => a.isActive), [accounts])

  // Never carry one run's entry into the next.
  useEffect(() => {
    if (!open) return
    setDirection("in")
    setAmount(undefined)
    setReason("")
    setReasonNote("")
    // One account is not a choice — pick it so the form opens ready to type.
    setAccountId(active.length === 1 ? active[0].accountId : null)
  }, [open, active])

  const needsNote = reason === "Other"
  const steerToReconcile = RECONCILE_REASONS.has(reason)
  const entered = amount !== undefined && !Number.isNaN(amount) && amount > 0
  const canSubmit =
    accountId != null && entered && !!reason && !steerToReconcile &&
    (!needsNote || !!reasonNote.trim()) && !saving

  const signed = entered ? (direction === "out" ? -Math.abs(amount!) : Math.abs(amount!)) : 0

  async function submit() {
    if (!canSubmit || accountId == null) return
    setSaving(true)
    try {
      await onSubmit({
        accountId,
        amount: signed,
        reason: needsNote ? reasonNote.trim() : reason,
      })
      toast({
        title: "Adjustment recorded",
        description: `${fmtMoney(Math.abs(signed))} ${direction === "out" ? "removed from" : "added to"} the account.`,
      })
      onOpenChange(false)
      onDone?.()
    } catch (e: any) {
      toast({ title: "Couldn't record the adjustment", description: e?.message, variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={(o) => { if (!saving) onOpenChange(o) }}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Scale className="h-5 w-5 text-sky-600" />
            Record Cash Adjustment
          </DialogTitle>
          <DialogDescription>
            Posts a cash transaction against one account. Balances are never edited directly.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <FormSection title="Adjustment" color="sky" columns={2}>
            <FormField label="Cash account *">
              <Select
                value={accountId != null ? String(accountId) : ""}
                onValueChange={(v) => setAccountId(Number(v))}
              >
                <SelectTrigger><SelectValue placeholder="Which account?" /></SelectTrigger>
                <SelectContent>
                  {active.map((a) => (
                    <SelectItem key={a.accountId} value={String(a.accountId)}>
                      {a.accountName}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {active.length === 0 && (
                <p className="mt-1 text-[11px] leading-snug text-rose-700">
                  This company has no active cash account. Create one before recording an adjustment.
                </p>
              )}
            </FormField>

            <FormField label="Direction *">
              <Select value={direction} onValueChange={(v) => setDirection(v as "in" | "out")}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="in">Add money (cash in)</SelectItem>
                  <SelectItem value="out">Remove money (cash out)</SelectItem>
                </SelectContent>
              </Select>
            </FormField>

            <FormField label="Amount *">
              <NumberInput
                min={0}
                step="0.01"
                value={amount ?? ""}
                onChange={(e) => setAmount(e.target.value === "" ? undefined : parseFloat(e.target.value))}
              />
            </FormField>

            <FormField label="Reason *">
              <Select value={reason} onValueChange={(v) => { setReason(v); setReasonNote("") }}>
                <SelectTrigger><SelectValue placeholder="Why is the balance changing?" /></SelectTrigger>
                <SelectContent>
                  {reasons.map((r) => (
                    <SelectItem key={r.value} value={r.value}>{r.label}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {needsNote && (
                <Input
                  autoFocus
                  className="mt-2"
                  value={reasonNote}
                  onChange={(e) => setReasonNote(e.target.value)}
                  placeholder="Say what happened"
                />
              )}
            </FormField>
          </FormSection>

          {/* A reconciliation difference is not an adjustment. Say so and hand over. */}
          {steerToReconcile && (
            <div className="rounded-md border border-amber-200 bg-amber-50 p-3">
              <p className="text-xs leading-snug text-amber-900">
                A {reason.toLowerCase()} means reality disagreed with the books, and reconciling the
                account records that properly — with the balance you actually checked, the evidence,
                and the ability to reverse it. An adjustment here would move the balance and lose all
                of that.
              </p>
              <Button asChild size="sm" variant="outline" className="mt-2 h-7 px-2 text-xs">
                <Link href={reconcileHref} onClick={() => onOpenChange(false)}>
                  Reconcile this account <ArrowRight className="ml-1 h-3 w-3" />
                </Link>
              </Button>
            </div>
          )}

          {entered && !steerToReconcile && (
            <p className={cn("rounded-md border border-slate-200 bg-slate-50 p-2",
                             "text-[11px] leading-snug text-slate-600")}>
              A {direction === "out" ? "money-out" : "money-in"} transaction of{" "}
              {fmtMoney(Math.abs(signed))} will be posted to this account. It appears in the ledger
              and can be reversed.
            </p>
          )}

          <div className="flex gap-3 justify-end pt-2">
            <Button type="button" variant="ghost" onClick={() => onOpenChange(false)} disabled={saving}>
              Cancel
            </Button>
            <Button onClick={submit} disabled={!canSubmit}>
              {saving ? (<><Loader2 className="mr-2 h-4 w-4 animate-spin" />Saving…</>) : "Record adjustment"}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}
