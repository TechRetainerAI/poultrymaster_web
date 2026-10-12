"use client"

// Close Flock — the end-of-flock / spent-layer closeout wizard (migration 338).
//
// Three steps, in the order the decision is actually made:
//   1. Reconcile  what the records say is standing, derived server-side
//   2. Dispose    account for every live bird: sold, culled or transferred
//   3. Close      date, reason, review -- then one call does it all
//
// Sales are created by the server through the ordinary SaleService, so a
// spent-layer sale lands on the Sales page, the customer's balance and the cash
// account exactly like any other sale. Nothing here writes a sale itself.

import { useEffect, useMemo, useState, type ReactNode } from "react"
import { AlertCircle, ArrowLeft, ArrowRight, CheckCircle2, Home, Loader2, Plus, Trash2, Flag } from "lucide-react"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { SuggestInput } from "@/components/ui/suggest-input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { cn } from "@/lib/utils"
import { formatCurrency } from "@/lib/utils/currency"
import { getUserContext } from "@/lib/utils/user-context"
import { getCustomers } from "@/lib/api"
import { listPoultryCashAccounts, type PoultryCashAccount } from "@/lib/api/poultry-finance"
import {
  closeFlock,
  getFlockCloseoutContext,
  type FlockCloseoutContext,
  type FlockCloseoutResult,
  type FlockCloseoutSaleLine,
} from "@/lib/api/flock-closeout"
import {
  PAYMENT_TERMS,
  dispositionTotals,
  reconciliationLines,
  saleTotal,
  unresolvedBirds,
  validateCloseoutDraft,
  type CloseoutDraft,
} from "@/lib/flocks/closeout"

const PAYMENT_METHODS = ["Cash", "Mobile Money", "Bank Transfer", "Check", "Credit Card"]
const REASONS = [
  "End of lay (spent layers)",
  "Depopulated",
  "Disease outbreak",
  "All birds sold",
  "Other",
]
const STEPS = ["Reconcile", "Dispose", "Close"] as const

interface Props {
  flockId: number | null
  open: boolean
  onOpenChange: (open: boolean) => void
  onClosed?: (result: FlockCloseoutResult) => void
}

const n = (v: number) => v.toLocaleString()

function SectionLabel({ children }: { children: ReactNode }) {
  return <h3 className="mb-1.5 text-[11px] font-semibold uppercase tracking-wide text-slate-500">{children}</h3>
}

function Figure({ label, value, tone }: { label: string; value: string; tone?: string }) {
  return (
    <div className="rounded-md border border-slate-200 bg-white p-2.5">
      <div className="text-[11px] leading-tight text-slate-500">{label}</div>
      <div className={cn("text-base font-semibold tabular-nums leading-snug", tone)}>{value}</div>
    </div>
  )
}

export function FlockCloseoutWizard({ flockId, open, onOpenChange, onClosed }: Props) {
  const [step, setStep] = useState(0)
  const [loading, setLoading] = useState(false)
  const [loadError, setLoadError] = useState("")
  const [context, setContext] = useState<FlockCloseoutContext | null>(null)
  const [customers, setCustomers] = useState<{ customerId: number; name: string }[]>([])
  const [cashAccounts, setCashAccounts] = useState<PoultryCashAccount[]>([])
  const [reasonChoice, setReasonChoice] = useState(REASONS[0])
  const [draft, setDraft] = useState<CloseoutDraft>({ closedDate: "", reason: REASONS[0], sales: [], culls: [], transfers: [] })
  const [submitting, setSubmitting] = useState(false)
  const [serverErrors, setServerErrors] = useState<string[]>([])
  const [result, setResult] = useState<FlockCloseoutResult | null>(null)

  useEffect(() => {
    if (!open || flockId == null) return
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) return
    let cancelled = false
    setStep(0)
    setLoading(true)
    setLoadError("")
    setServerErrors([])
    setResult(null)
    setContext(null)
    ;(async () => {
      const [ctx, cust, accounts] = await Promise.all([
        getFlockCloseoutContext(flockId, userId, farmId),
        getCustomers(userId, farmId).catch(() => ({ success: false, data: [] })),
        listPoultryCashAccounts().catch(() => [] as PoultryCashAccount[]),
      ])
      if (cancelled) return
      if (!ctx.success || !ctx.data) {
        setLoadError(ctx.message || "Could not load this flock's bird position.")
      } else {
        setContext(ctx.data)
        setReasonChoice(REASONS[0])
        setDraft({
          closedDate: (ctx.data.businessDate || "").slice(0, 10),
          reason: REASONS[0],
          notes: "",
          sales: [],
          culls: [],
          transfers: [],
        })
      }
      setCustomers(((cust as any)?.data ?? []) as { customerId: number; name: string }[])
      setCashAccounts((accounts as PoultryCashAccount[]).filter((a) => a.isActive))
      setLoading(false)
    })()
    return () => { cancelled = true }
  }, [open, flockId])

  const defaultAccountId = useMemo(() => {
    const main = cashAccounts.find((a) => a.accountName.trim().toLowerCase() === "main cash account")
    return (main ?? cashAccounts[0])?.poultryCashAccountId ?? null
  }, [cashAccounts])

  const live = context?.position.currentLiveBirds ?? 0
  const totals = dispositionTotals(draft)
  const remaining = context ? unresolvedBirds(context.position, draft) : 0
  const errors = context ? validateCloseoutDraft(draft, context) : []
  const lines = context ? reconciliationLines(context.position) : []

  const patchSale = (i: number, patch: Partial<FlockCloseoutSaleLine>) =>
    setDraft((d) => ({ ...d, sales: d.sales.map((s, j) => (j === i ? { ...s, ...patch } : s)) }))

  const addSale = () =>
    setDraft((d) => ({
      ...d,
      sales: [...d.sales, {
        quantity: Math.max(0, unresolvedBirds(context!.position, d)),
        unitPrice: 0,
        paymentTerms: "Paid",
        paymentMethod: "Cash",
        poultryCashAccountId: defaultAccountId,
        customerName: "",
      }],
    }))

  const submit = async () => {
    if (!context || flockId == null) return
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) return
    setSubmitting(true)
    setServerErrors([])
    const res = await closeFlock(flockId, {
      userId,
      farmId,
      closedDate: draft.closedDate,
      reason: draft.reason.trim(),
      notes: draft.notes?.trim() || null,
      sales: draft.sales.map((s) => {
        const match = customers.find((c) => c.name.trim().toLowerCase() === (s.customerName ?? "").trim().toLowerCase())
        return {
          ...s,
          totalAmount: saleTotal(s),
          customerId: match?.customerId ?? null,
          customerName: (s.customerName ?? "").trim() || null,
          amountPaid: s.paymentTerms === "PartPaid" ? Number(s.amountPaid) || 0 : null,
          poultryCashAccountId: s.paymentTerms === "Credit" ? null : s.poultryCashAccountId,
          paymentMethod: s.paymentTerms === "Credit" ? null : s.paymentMethod,
        }
      }),
      culls: draft.culls,
      transfers: draft.transfers,
    })
    setSubmitting(false)
    if (res.success && res.data?.success) {
      setResult(res.data)
      onClosed?.(res.data)
    } else {
      const errs = res.data?.errors?.length ? res.data.errors : [res.data?.message || res.message || "The flock could not be closed."]
      setServerErrors(errs)
    }
  }

  const flockName = context?.flock?.name ?? "flock"

  return (
    <Dialog open={open} onOpenChange={(o) => !submitting && onOpenChange(o)}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Flag className="h-5 w-5 text-slate-600" /> Close {flockName}
          </DialogTitle>
          <DialogDescription>
            End this flock's life: account for every bird still standing, then close it and free its house.
            The flock and its history are kept — nothing is deleted.
          </DialogDescription>
        </DialogHeader>

        {loading && (
          <div className="flex items-center gap-2 py-10 justify-center text-slate-500">
            <Loader2 className="h-4 w-4 animate-spin" /> Reconciling the flock's birds…
          </div>
        )}

        {!loading && loadError && (
          <Alert variant="destructive"><AlertCircle className="h-4 w-4" /><AlertDescription>{loadError}</AlertDescription></Alert>
        )}

        {!loading && context && result && (
          <div className="space-y-4">
            <Alert className="border-emerald-200 bg-emerald-50">
              <CheckCircle2 className="h-4 w-4 text-emerald-600" />
              <AlertDescription className="text-emerald-900">{result.message}</AlertDescription>
            </Alert>
            {result.saleIds.length > 0 && (
              <p className="text-sm text-slate-600">
                {result.saleIds.length === 1 ? "The sale is" : `${result.saleIds.length} sales are`} on the Sales page
                ({result.saleIds.map((id) => `#${id}`).join(", ")}), with any balance owed on the customer's account.
              </p>
            )}
            {result.warnings.map((w) => (
              <Alert key={w} className="border-amber-200 bg-amber-50">
                <AlertCircle className="h-4 w-4 text-amber-600" />
                <AlertDescription className="text-amber-900">{w}</AlertDescription>
              </Alert>
            ))}
            <DialogFooter>
              <Button onClick={() => onOpenChange(false)}>Done</Button>
            </DialogFooter>
          </div>
        )}

        {!loading && context && !result && (
          <div className="space-y-4">
            {/* Step indicator */}
            <ol className="flex items-center gap-2 text-xs">
              {STEPS.map((label, i) => (
                <li key={label} className="flex items-center gap-2">
                  <span className={cn(
                    "flex h-6 w-6 items-center justify-center rounded-full border font-semibold",
                    i === step ? "border-slate-900 bg-slate-900 text-white"
                      : i < step ? "border-emerald-500 bg-emerald-50 text-emerald-700"
                      : "border-slate-300 text-slate-500",
                  )}>{i + 1}</span>
                  <span className={cn(i === step ? "font-semibold text-slate-900" : "text-slate-500")}>{label}</span>
                  {i < STEPS.length - 1 && <span className="mx-1 h-px w-6 bg-slate-300" />}
                </li>
              ))}
            </ol>

            {(context.isClosed || context.ineligibleReason) && (
              <Alert variant="destructive">
                <AlertCircle className="h-4 w-4" />
                <AlertDescription>{context.isClosed ? "This flock is already closed." : context.ineligibleReason}</AlertDescription>
              </Alert>
            )}

            {/* ---------------- Step 1: reconcile ---------------- */}
            {step === 0 && (
              <section className="space-y-3">
                <SectionLabel>Where the birds went</SectionLabel>
                <div className="rounded-md border border-slate-200 divide-y">
                  {lines.map((l) => (
                    <div
                      key={l.key}
                      className={cn(
                        "flex items-start justify-between gap-3 px-3 py-2 text-sm",
                        l.sign === "=" && "bg-slate-50 font-semibold",
                        l.key === "live" && "bg-blue-50 text-blue-900",
                        l.muted && "text-slate-500",
                      )}
                    >
                      <div>
                        <div>{l.label}</div>
                        {l.hint && <div className="text-xs font-normal text-slate-500">{l.hint}</div>}
                        {l.key === "lastCount" && context.position.lastCountDate && (
                          <div className="text-xs font-normal text-slate-500">
                            Latest production record, {context.position.lastCountDate.slice(0, 10)}
                          </div>
                        )}
                      </div>
                      <div className="tabular-nums whitespace-nowrap">
                        {l.sign === "=" ? "" : l.sign === "±" ? (l.value >= 0 ? "+ " : "− ") : `${l.sign === "-" ? "−" : "+"} `}
                        {n(l.sign === "±" ? Math.abs(l.value) : l.value)}
                      </div>
                    </div>
                  ))}
                </div>

                {live < 0 ? (
                  <Alert variant="destructive">
                    <AlertCircle className="h-4 w-4" />
                    <AlertDescription>
                      The records account for {n(-live)} more birds than this flock had. That usually means a bird sale
                      was also deducted by hand on a production record. Correct that record before closing.
                    </AlertDescription>
                  </Alert>
                ) : (
                  <p className="text-sm text-slate-600">
                    {live === 0
                      ? "No birds are left standing, so this flock can be closed without selling, culling or transferring any."
                      : `${n(live)} birds are still standing. The next step accounts for every one of them.`}
                    {" "}If a physical count differs, record the missing birds as mortality on a production record first —
                    closing a flock never invents deaths to make the numbers fit.
                  </p>
                )}
              </section>
            )}

            {/* ---------------- Step 2: dispose ---------------- */}
            {step === 1 && (
              <section className="space-y-4">
                <div className={cn(
                  "flex items-center justify-between rounded-md border px-3 py-2 text-sm",
                  remaining === 0 ? "border-emerald-200 bg-emerald-50 text-emerald-900"
                    : remaining > 0 ? "border-amber-200 bg-amber-50 text-amber-900"
                    : "border-rose-200 bg-rose-50 text-rose-900",
                )}>
                  <span>
                    {n(live)} standing · {n(totals.total)} accounted for
                  </span>
                  <span className="font-semibold tabular-nums">
                    {remaining === 0 ? "Balanced" : remaining > 0 ? `${n(remaining)} still to account for` : `${n(-remaining)} too many`}
                  </span>
                </div>

                {/* Sales */}
                <div className="space-y-2">
                  <div className="flex items-center justify-between">
                    <SectionLabel>Sold</SectionLabel>
                    <Button type="button" variant="outline" size="sm" onClick={addSale}><Plus className="h-4 w-4 mr-1" /> Sale</Button>
                  </div>
                  <p className="text-xs text-slate-500">
                    Spent-layer sales are recorded as ordinary {context.birdProductName} sales. There is no separate
                    save: each sale here is saved together with the closeout when you press{" "}
                    <span className="font-medium text-slate-700">Close flock &amp; record sales</span> on the last step,
                    so a sale can never be left behind on a flock that did not close.
                  </p>
                  {draft.sales.map((s, i) => (
                    <div key={i} className="rounded-md border p-3 space-y-3">
                      <div className="flex items-center justify-between">
                        <span className="text-sm font-medium">Sale {i + 1}</span>
                        <Button type="button" variant="ghost" size="icon" className="h-7 w-7 text-red-600"
                          onClick={() => setDraft((d) => ({ ...d, sales: d.sales.filter((_, j) => j !== i) }))}>
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </div>
                      <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
                        <div className="space-y-1">
                          <Label className="text-xs">Birds</Label>
                          <Input type="number" min={0} value={s.quantity || ""} onChange={(e) => patchSale(i, { quantity: Number(e.target.value) })} />
                        </div>
                        <div className="space-y-1">
                          <Label className="text-xs">Price per bird</Label>
                          <Input type="number" min={0} step="0.01" value={s.unitPrice || ""}
                            onChange={(e) => patchSale(i, { unitPrice: Number(e.target.value), totalAmount: null })} />
                        </div>
                        <div className="space-y-1 col-span-2 sm:col-span-1">
                          <Label className="text-xs">Total price</Label>
                          <Input type="number" min={0} step="0.01" value={saleTotal(s) || ""}
                            onChange={(e) => patchSale(i, { totalAmount: e.target.value === "" ? null : Number(e.target.value) })} />
                        </div>
                      </div>
                      <div className="space-y-1">
                        <Label className="text-xs">Customer{s.paymentTerms === "Paid" ? " (optional)" : ""}</Label>
                        <SuggestInput placeholder="Customer name" value={s.customerName ?? ""} suggestions={customers.map((c) => c.name)}
                          onChange={(v) => patchSale(i, { customerName: v })} />
                      </div>
                      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                        <div className="space-y-1">
                          <Label className="text-xs">Payment terms</Label>
                          <Select value={s.paymentTerms} onValueChange={(v) => patchSale(i, { paymentTerms: v as FlockCloseoutSaleLine["paymentTerms"] })}>
                            <SelectTrigger><SelectValue /></SelectTrigger>
                            <SelectContent>
                              {PAYMENT_TERMS.map((t) => <SelectItem key={t.value} value={t.value}>{t.label}</SelectItem>)}
                            </SelectContent>
                          </Select>
                        </div>
                        {s.paymentTerms === "PartPaid" && (
                          <div className="space-y-1">
                            <Label className="text-xs">Amount received now</Label>
                            <Input type="number" min={0} step="0.01" value={s.amountPaid ?? ""}
                              onChange={(e) => patchSale(i, { amountPaid: e.target.value === "" ? null : Number(e.target.value) })} />
                          </div>
                        )}
                      </div>
                      {s.paymentTerms !== "Credit" && (
                        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                          <div className="space-y-1">
                            <Label className="text-xs">Payment method</Label>
                            <Select value={s.paymentMethod ?? ""} onValueChange={(v) => patchSale(i, { paymentMethod: v })}>
                              <SelectTrigger><SelectValue placeholder="How was it paid?" /></SelectTrigger>
                              <SelectContent>
                                {PAYMENT_METHODS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}
                              </SelectContent>
                            </Select>
                          </div>
                          <div className="space-y-1">
                            <Label className="text-xs">Received into</Label>
                            <Select
                              value={s.poultryCashAccountId != null ? String(s.poultryCashAccountId) : ""}
                              onValueChange={(v) => patchSale(i, { poultryCashAccountId: Number(v) })}
                            >
                              <SelectTrigger><SelectValue placeholder="Cash account" /></SelectTrigger>
                              <SelectContent>
                                {cashAccounts.map((a) => (
                                  <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>{a.accountName}</SelectItem>
                                ))}
                              </SelectContent>
                            </Select>
                          </div>
                        </div>
                      )}
                    </div>
                  ))}
                </div>

                {/* Culls */}
                <div className="space-y-2">
                  <div className="flex items-center justify-between">
                    <SectionLabel>Culled</SectionLabel>
                    <Button type="button" variant="outline" size="sm"
                      onClick={() => setDraft((d) => ({ ...d, culls: [...d.culls, { quantity: Math.max(0, unresolvedBirds(context.position, d)), notes: "" }] }))}>
                      <Plus className="h-4 w-4 mr-1" /> Cull
                    </Button>
                  </div>
                  {draft.culls.map((c, i) => (
                    <div key={i} className="rounded-md border p-3 grid grid-cols-[6rem_1fr_auto] gap-2 items-end">
                      <div className="space-y-1">
                        <Label className="text-xs">Birds</Label>
                        <Input type="number" min={0} value={c.quantity || ""}
                          onChange={(e) => setDraft((d) => ({ ...d, culls: d.culls.map((x, j) => j === i ? { ...x, quantity: Number(e.target.value) } : x) }))} />
                      </div>
                      <div className="space-y-1">
                        <Label className="text-xs">Notes</Label>
                        <Input placeholder="e.g. culled and disposed on site" value={c.notes ?? ""}
                          onChange={(e) => setDraft((d) => ({ ...d, culls: d.culls.map((x, j) => j === i ? { ...x, notes: e.target.value } : x) }))} />
                      </div>
                      <Button type="button" variant="ghost" size="icon" className="h-9 w-9 text-red-600"
                        onClick={() => setDraft((d) => ({ ...d, culls: d.culls.filter((_, j) => j !== i) }))}>
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    </div>
                  ))}
                </div>

                {/* Transfers */}
                <div className="space-y-2">
                  <div className="flex items-center justify-between">
                    <SectionLabel>Transferred off the farm</SectionLabel>
                    <Button type="button" variant="outline" size="sm"
                      onClick={() => setDraft((d) => ({ ...d, transfers: [...d.transfers, { quantity: Math.max(0, unresolvedBirds(context.position, d)), destination: "" }] }))}>
                      <Plus className="h-4 w-4 mr-1" /> Transfer
                    </Button>
                  </div>
                  {draft.transfers.length === 0 && (
                    <p className="text-xs text-slate-500">
                      For birds leaving the company. Birds moving to another house stay the same flock — edit its house instead of closing it.
                    </p>
                  )}
                  {draft.transfers.map((t, i) => (
                    <div key={i} className="rounded-md border p-3 grid grid-cols-[6rem_1fr_auto] gap-2 items-end">
                      <div className="space-y-1">
                        <Label className="text-xs">Birds</Label>
                        <Input type="number" min={0} value={t.quantity || ""}
                          onChange={(e) => setDraft((d) => ({ ...d, transfers: d.transfers.map((x, j) => j === i ? { ...x, quantity: Number(e.target.value) } : x) }))} />
                      </div>
                      <div className="space-y-1">
                        <Label className="text-xs">Destination</Label>
                        <Input placeholder="Where did they go?" value={t.destination}
                          onChange={(e) => setDraft((d) => ({ ...d, transfers: d.transfers.map((x, j) => j === i ? { ...x, destination: e.target.value } : x) }))} />
                      </div>
                      <Button type="button" variant="ghost" size="icon" className="h-9 w-9 text-red-600"
                        onClick={() => setDraft((d) => ({ ...d, transfers: d.transfers.filter((_, j) => j !== i) }))}>
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    </div>
                  ))}
                </div>
              </section>
            )}

            {/* ---------------- Step 3: close ---------------- */}
            {step === 2 && (
              <section className="space-y-4">
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <div className="space-y-1">
                    <Label className="text-xs">Closing date</Label>
                    <Input type="date" value={draft.closedDate}
                      min={(context.earliestCloseDate || "").slice(0, 10)} max={(context.businessDate || "").slice(0, 10)}
                      onChange={(e) => setDraft((d) => ({ ...d, closedDate: e.target.value }))} />
                  </div>
                  <div className="space-y-1">
                    <Label className="text-xs">Reason</Label>
                    <Select value={reasonChoice} onValueChange={(v) => { setReasonChoice(v); setDraft((d) => ({ ...d, reason: v === "Other" ? "" : v })) }}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>{REASONS.map((r) => <SelectItem key={r} value={r}>{r}</SelectItem>)}</SelectContent>
                    </Select>
                  </div>
                </div>
                {reasonChoice === "Other" && (
                  <Input placeholder="Why is this flock closing?" value={draft.reason}
                    onChange={(e) => setDraft((d) => ({ ...d, reason: e.target.value }))} />
                )}
                <Textarea placeholder="Notes (optional)" rows={2} value={draft.notes ?? ""}
                  onChange={(e) => setDraft((d) => ({ ...d, notes: e.target.value }))} />

                <div>
                  <SectionLabel>What will happen</SectionLabel>
                  <div className="grid grid-cols-3 gap-2">
                    <Figure label="Sold" value={n(totals.sold)} tone="text-emerald-700" />
                    <Figure label="Culled" value={n(totals.culled)} tone="text-slate-700" />
                    <Figure label="Transferred" value={n(totals.transferred)} tone="text-violet-700" />
                  </div>
                  {draft.sales.length > 0 && (
                    <div className="mt-2 space-y-1">
                      <p className="text-sm text-slate-600">
                        {draft.sales.length === 1 ? "This sale" : `These ${draft.sales.length} sales`} will be created on the
                        Sales page when you close the flock:
                      </p>
                      {draft.sales.map((s, i) => (
                        <div key={i} className="rounded-md border p-2 text-sm flex flex-wrap justify-between gap-2">
                          <span>
                            {n(Number(s.quantity) || 0)} birds{s.customerName?.trim() ? ` to ${s.customerName.trim()}` : ""}
                            {" · "}{PAYMENT_TERMS.find((t) => t.value === s.paymentTerms)?.label}
                            {s.paymentTerms === "PartPaid" && s.amountPaid ? ` (${formatCurrency(Number(s.amountPaid))} now)` : ""}
                          </span>
                          <span className="font-semibold tabular-nums">{formatCurrency(saleTotal(s))}</span>
                        </div>
                      ))}
                    </div>
                  )}
                  <p className="mt-2 flex items-center gap-2 text-sm text-slate-600">
                    <Home className="h-4 w-4 text-slate-400" />
                    {context.houseName
                      ? <>{context.houseName} will be released for a new flock. The flock keeps its house in its history.</>
                      : <>This flock has no house assigned.</>}
                  </p>
                </div>
              </section>
            )}

            {(step === 2 ? [...errors, ...serverErrors] : serverErrors).length > 0 && (
              <Alert variant="destructive">
                <AlertCircle className="h-4 w-4" />
                <AlertDescription>
                  <ul className="list-disc pl-4 space-y-0.5">
                    {[...new Set(step === 2 ? [...errors, ...serverErrors] : serverErrors)].map((e) => <li key={e}>{e}</li>)}
                  </ul>
                </AlertDescription>
              </Alert>
            )}

            <DialogFooter className="gap-2 sm:gap-2">
              {step > 0 && (
                <Button variant="outline" onClick={() => setStep((s) => s - 1)} disabled={submitting}>
                  <ArrowLeft className="h-4 w-4 mr-1" /> Back
                </Button>
              )}
              {step < 2 && (
                <Button
                  onClick={() => setStep((s) => s + 1)}
                  disabled={Boolean(context.isClosed || context.ineligibleReason) || live < 0 || (step === 1 && remaining !== 0)}
                >
                  Next <ArrowRight className="h-4 w-4 ml-1" />
                </Button>
              )}
              {step === 2 && (
                <Button onClick={submit} disabled={submitting || errors.length > 0} className="bg-slate-900 hover:bg-slate-800">
                  {submitting ? <Loader2 className="h-4 w-4 mr-1 animate-spin" /> : <Flag className="h-4 w-4 mr-1" />}
                  {draft.sales.length > 0 ? "Close flock & record sales" : "Close flock"}
                </Button>
              )}
            </DialogFooter>
            {step === 1 && remaining !== 0 && (
              <p className="text-right text-xs text-slate-500">
                <Badge variant="outline" className="mr-1">{remaining > 0 ? n(remaining) : `−${n(-remaining)}`}</Badge>
                Every bird must be accounted for before you continue.
              </p>
            )}
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}
