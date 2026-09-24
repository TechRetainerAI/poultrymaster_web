"use client"

// =============================================================================
// The expanded row on a Capital Investments / Assets register (migrations 313,
// 314).
//
// THE PRINCIPLE THIS COMPONENT EXISTS TO SERVE
// --------------------------------------------
// The parent row is the SUMMARY. Expanding it EXPLAINS how the summary numbers
// were produced. Nobody should read
//
//     Capitalised cost   GHC 130,000
//     Depreciation       GHC 312.50
//     Book value         GHC 129,687.50
//
// and have to go to another page -- or three -- to find out where any of those
// came from.
//
// WHY IT IS SHARED, AND NOT COPIED INTO EACH PAGE
// -----------------------------------------------
// The poultry and water registers are deliberate mirrors: two migrations, two
// services, two pages, one design. The bug this whole change fixes was ONE
// number carrying two meanings on different screens, so the last thing to do
// about it is write the explanation twice and let the two drift. Each page owns
// its own API types and adapts them to `AssetDetailsView`; everything below is
// module-agnostic and knows nothing about poultry or water.
//
// WHAT IT DOES NOT DO
// -------------------
// It computes NOTHING. Every figure here is the server's -- the same
// fn*capitalasset_financials that the register, the depreciation engine and the
// P&L read. The one arithmetic on this page is the book-value IDENTITY printed
// under the Overview tab, and it is printed precisely so that a reader can check
// the server's numbers rather than be handed a fourth opinion about them.
//
// It also does not post depreciation. Due depreciation belongs to the
// Depreciation button at the top of the register, which already owns "what needs
// to be posted?". This tab answers "what HAS been posted?" -- see §39 of the
// brief: those are different questions and mixing them is how a history tab
// quietly becomes a second action centre.
// =============================================================================

import { useMemo, useState, type ReactNode } from "react"
import Link from "next/link"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import {
  AlertTriangle, Coins, Eye, Info, Loader2, Pencil, Receipt, SlidersHorizontal, Undo2,
} from "lucide-react"
import { cn } from "@/lib/utils"
import { DateTimeCell } from "@/components/ui/date-time-cell"
import { fmtDateTime, fmtInstant, fmtMonthYear } from "@/lib/utils/company-datetime"

// ----- the shape each register adapts its own types into -----------------

export interface AssetCostRow {
  id: number
  costDate: string
  description?: string | null
  costCategory?: string | null
  /** SIGNED: negative only on a correction that reduced what was recorded. */
  amount: number
  /** Acquisition | AdditionalCost | OriginalCostCorrection. */
  sourceType?: string | null
  supplierName?: string | null
  paymentStatus?: string | null
  amountPaid?: number | null
  balance?: number | null
  paymentMethod?: string | null
  dueDate?: string | null
  cashAccountName?: string | null
  expenseId?: number | null
  /** What the linked expense is NOW for -- a correction shares the acquisition's. */
  expenseAmount?: number | null
  expenseCategory?: string | null
  status: string
  createdBy?: string | null
  createdAt?: string | null
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
}

export interface AssetDepreciationRow {
  id: number
  periodStart: string
  periodEnd?: string | null
  depreciationDate?: string | null
  /** SIGNED: a reversal is a negative row beside the original, never an edit. */
  amount: number
  depreciationMethod?: string | null
  /** Scheduled | CatchUp | ManualAdjustment | Reversal. */
  sourceType?: string | null
  status?: string | null
  expenseId?: number | null
  accumulatedAfter?: number | null
  bookValueAfter?: number | null
  createdBy?: string | null
  createdAt?: string | null
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
}

export interface AssetDetailsView {
  id: number
  assetNumber?: string | null
  assetName: string
  categoryName?: string | null
  description?: string | null
  location?: string | null
  serialNumber?: string | null
  notes?: string | null
  supplierName?: string | null
  status: string
  statusLabel: string
  acquisitionDate: string
  inServiceDate?: string | null

  acquisitionCost: number
  additionalCost: number
  totalCapitalizedCost: number
  residualValue: number
  depreciableAmount: number
  usefulLifeMonths?: number | null
  monthlyDepreciation?: number | null
  accumulatedDepreciation: number
  currentBookValue: number
  remainingDepreciable: number
  isFullyDepreciated: boolean
  depreciationEntries: number

  createdBy?: string | null
  createdAt?: string | null

  costs: AssetCostRow[]
  depreciation: AssetDepreciationRow[]
}

/**
 * The wording each module supplies. They are not defaults here on purpose: the
 * poultry register says "capital investment" and the water one says "asset", and
 * the two modules each keep their own copy in
 * lib/{poultry,water}/financial-classification.ts, where every other note on
 * these pages already lives.
 */
export interface AssetDetailsNotes {
  acquisitionCostTooltip: string
  additionalCostTooltip: string
  totalCapitalizedCostTooltip: string
  bookValueTooltip: string
  depreciationNonCashNote: string
  depreciationConventionNote: string
  costLockedByDepreciationNote: string
}

export interface AssetDetailsPanelProps {
  view: AssetDetailsView | null
  loading?: boolean
  error?: string | null
  /** The noun this module uses for the thing. */
  term: "investment" | "asset"
  notes: AssetDetailsNotes
  fmt: (n: number) => string
  /** Where the full-page detail view lives, if the register has one. */
  detailHref?: string
  /** Where a linked expense can be read. */
  expensesHref: string
  onEdit?: () => void
  onAddCost?: () => void
  onCorrectOriginalCost?: () => void
  onViewCost?: (row: AssetCostRow) => void
  onReverseCost?: (row: AssetCostRow) => void
  onReverseDepreciation?: (row: AssetDepreciationRow) => void
  onRetry?: () => void
}

const money = (fmt: (n: number) => string, n: number) => (n < 0 ? `-${fmt(Math.abs(n))}` : fmt(n))

export function AssetDetailsPanel(props: AssetDetailsPanelProps) {
  const { view, loading, error, onRetry } = props
  const [tab, setTab] = useState("overview")

  if (loading && !view) {
    return (
      <div className="flex items-center justify-center gap-2 px-4 py-8 text-sm text-slate-500">
        <Loader2 className="h-4 w-4 animate-spin" /> Loading the full history…
      </div>
    )
  }
  if (error) {
    return (
      <div className="flex flex-wrap items-center gap-3 px-4 py-6 text-sm text-red-700">
        <AlertTriangle className="h-4 w-4 shrink-0" />
        <span>{error}</span>
        {onRetry && <Button size="sm" variant="outline" onClick={onRetry}>Try again</Button>}
      </div>
    )
  }
  if (!view) return null

  const postedCosts = view.costs.filter((c) => c.status === "Posted")
  const reversedCosts = view.costs.filter((c) => c.status !== "Posted")
  const postedDepreciation = view.depreciation.length

  return (
    <div className="space-y-3 px-3 py-3 sm:px-4">
      <Tabs value={tab} onValueChange={setTab}>
        {/* Scrolls rather than squashes: three labels do not fit a 360px phone
            and truncating "Depreciation history" to "Deprecia…" helps nobody. */}
        <div className="overflow-x-auto">
          <TabsList className="w-max">
            <TabsTrigger value="overview">Overview</TabsTrigger>
            <TabsTrigger value="costs">
              Cost history
              <span className="ml-1.5 text-[11px] text-slate-500">{postedCosts.length}</span>
            </TabsTrigger>
            <TabsTrigger value="depreciation">
              Depreciation history
              <span className="ml-1.5 text-[11px] text-slate-500">{postedDepreciation}</span>
            </TabsTrigger>
          </TabsList>
        </div>

        <TabsContent value="overview" className="mt-3">
          <OverviewTab {...props} view={view} />
        </TabsContent>

        <TabsContent value="costs" className="mt-3">
          <CostHistoryTab {...props} view={view} posted={postedCosts} reversed={reversedCosts} />
        </TabsContent>

        <TabsContent value="depreciation" className="mt-3">
          <DepreciationHistoryTab {...props} view={view} />
        </TabsContent>
      </Tabs>
    </div>
  )
}

// ------------------------------------------------------------------ overview --

function OverviewTab({
  view, notes, fmt, term, detailHref, onEdit, onAddCost, onCorrectOriginalCost,
}: AssetDetailsPanelProps & { view: AssetDetailsView }) {
  const locked = view.depreciationEntries > 0
  const disposedOrReversed = view.status === "Disposed" || view.status === "Reversed"

  return (
    <div className="space-y-4">
      <section>
        <SectionLabel>What it cost</SectionLabel>
        {/* The three amounts, in the order that makes the arithmetic readable:
            what it was bought for, what was added, what that comes to. */}
        <div className="grid grid-cols-2 gap-2 lg:grid-cols-3">
          <Figure label="Original acquisition cost" value={fmt(view.acquisitionCost)}
                  hint={notes.acquisitionCostTooltip} />
          <Figure label="Additional capitalised costs" value={fmt(view.additionalCost)}
                  hint={notes.additionalCostTooltip} />
          <Figure label="Total capitalised cost" value={fmt(view.totalCapitalizedCost)}
                  strong hint={notes.totalCapitalizedCostTooltip} />
        </div>
      </section>

      <section>
        <SectionLabel>What it is worth now</SectionLabel>
        <div className="grid grid-cols-2 gap-2 lg:grid-cols-3">
          <Figure label="Accumulated depreciation" value={fmt(view.accumulatedDepreciation)}
                  tone="amber" hint={notes.depreciationNonCashNote} />
          <Figure label="Current book value" value={fmt(view.currentBookValue)}
                  tone="emerald" strong hint={notes.bookValueTooltip} />
          <Figure label="Residual value" value={fmt(view.residualValue)}
                  hint={`What the ${term} is expected to still be worth at the end of its life. Book value never falls below it.`} />
        </div>
        {/* §9. The identity, spelled out, so the book value is checkable rather
            than merely asserted. The numbers are the server's; only the
            subtraction sign is this component's. */}
        <p className="mt-2 flex flex-wrap items-center gap-1 text-[11px] tabular-nums text-slate-500">
          <Info className="h-3.5 w-3.5 shrink-0" />
          <span>
            {fmt(view.totalCapitalizedCost)} total capitalised cost
            {" − "}{fmt(view.accumulatedDepreciation)} depreciation charged
            {" = "}<strong className="text-slate-700">{fmt(view.currentBookValue)}</strong> book value
            {view.currentBookValue <= view.residualValue && view.residualValue > 0 &&
              " — held at the residual value, which book value never falls below"}
          </span>
        </p>
      </section>

      <section>
        <SectionLabel>How it depreciates</SectionLabel>
        <div className="grid gap-x-6 gap-y-1 sm:grid-cols-2 lg:grid-cols-3">
          <Line label="Method" value={view.usefulLifeMonths ? "Straight line" : "—"} />
          <Line label="Useful life"
                value={view.usefulLifeMonths ? `${view.usefulLifeMonths} months` : "Not set"} />
          <Line label="Monthly charge"
                value={view.monthlyDepreciation ? fmt(view.monthlyDepreciation) : "—"} />
          <Line label="Depreciable amount" value={fmt(view.depreciableAmount)} />
          <Line label="Still to be charged" value={fmt(view.remainingDepreciable)} />
          <Line label="In service"
                value={view.inServiceDate ? fmtDateTime(view.inServiceDate) : "Not in service"} />
        </div>
      </section>

      <section>
        <SectionLabel>What it is</SectionLabel>
        <div className="grid gap-x-6 gap-y-1 sm:grid-cols-2 lg:grid-cols-3">
          <Line label="Category" value={view.categoryName ?? "—"} />
          <Line label="Acquired" value={fmtDateTime(view.acquisitionDate, view) || "—"} />
          <Line label="Status" value={view.statusLabel} />
          <Line label="Location" value={view.location ?? "—"} />
          <Line label="Serial number" value={view.serialNumber ?? "—"} />
          <Line label="Supplier" value={view.supplierName ?? "—"} />
          <Line label="Recorded by" value={view.createdBy ?? "—"} />
          <Line label="Recorded" value={view.createdAt ? fmtInstant(view.createdAt) : "—"} />
          {view.description && <Line label="Description" value={view.description} wide />}
          {view.notes && <Line label="Notes" value={view.notes} wide />}
        </div>
      </section>

      {/* §41. The actions that belong to the WHOLE record, kept here rather than
          added as more icons to an already wide row. */}
      {!disposedOrReversed && (
        <section className="flex flex-wrap gap-2 border-t border-slate-200 pt-3">
          {onEdit && (
            <Button size="sm" variant="outline" onClick={onEdit}>
              <Pencil className="mr-1 h-3.5 w-3.5" /> Edit {term}
            </Button>
          )}
          {onAddCost && (
            <Button size="sm" variant="outline" onClick={onAddCost} disabled={locked}
                    title={locked ? notes.costLockedByDepreciationNote : "Add capitalised cost"}>
              <Coins className="mr-1 h-3.5 w-3.5" /> Add cost
            </Button>
          )}
          {onCorrectOriginalCost && (
            <Button size="sm" variant="outline" onClick={onCorrectOriginalCost}
                    disabled={view.acquisitionCost <= 0}
                    title={view.acquisitionCost <= 0
                      ? `This ${term} has no original acquisition to correct — its cost was built up with Add cost.`
                      : "Fix a mistake in what the original acquisition was recorded as costing"}>
              <SlidersHorizontal className="mr-1 h-3.5 w-3.5" /> Correct original cost
            </Button>
          )}
          {detailHref && (
            <Button size="sm" variant="ghost" asChild>
              <Link href={detailHref}>Open full page</Link>
            </Button>
          )}
        </section>
      )}

      {locked && (
        <p className="flex items-start gap-1.5 rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-[11px] text-amber-900">
          <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" />
          {notes.costLockedByDepreciationNote}
        </p>
      )}
    </div>
  )
}

// -------------------------------------------------------------- cost history --

function CostHistoryTab({
  view, posted, reversed, fmt, term, expensesHref, onViewCost, onReverseCost, notes,
}: AssetDetailsPanelProps & {
  view: AssetDetailsView; posted: AssetCostRow[]; reversed: AssetCostRow[]
}) {
  const total = useMemo(() => posted.reduce((s, c) => s + c.amount, 0), [posted])
  const locked = view.depreciationEntries > 0

  return (
    <div className="space-y-2">
      {/* §66. An empty cost history is NOT "no history" -- it is an asset that
          has not been paid for yet, and saying so is more useful than a dash. */}
      {posted.length === 0 ? (
        <p className="rounded-md border border-slate-200 bg-white px-3 py-4 text-sm text-slate-600">
          Nothing has been capitalised into this {term} yet, so its cost is {fmt(0)}. Use
          &ldquo;Add cost&rdquo; to build it up — that is how a {term} that is constructed rather than
          bought is recorded.
        </p>
      ) : (
        <>
          {/* Desktop: the columns, because this is a ledger and a ledger reads
              down a column. Mobile: the same rows stacked, because seven columns
              on a phone is a horizontal scrollbar nobody uses. */}
          <div className="hidden overflow-x-auto lg:block">
            <Table className="min-w-[860px]">
              <TableHeader><TableRow>
                <TableHead>Date</TableHead>
                <TableHead>Cost type</TableHead>
                <TableHead>Description</TableHead>
                <TableHead>Supplier / payee</TableHead>
                <TableHead className="text-right">Amount</TableHead>
                <TableHead>Payment</TableHead>
                <TableHead>Reference</TableHead>
                <TableHead className="text-right">Actions</TableHead>
              </TableRow></TableHeader>
              <TableBody>
                {posted.map((c) => (
                  <TableRow key={c.id}>
                    <TableCell className="align-top text-sm">
                      <DateTimeCell value={c.costDate} row={c} />
                    </TableCell>
                    <TableCell className="text-sm"><CostTypeBadge row={c} /></TableCell>
                    <TableCell className="text-sm">{c.description ?? "—"}</TableCell>
                    <TableCell className="text-sm">{c.supplierName ?? "—"}</TableCell>
                    <TableCell className={cn("text-right tabular-nums", c.amount < 0 && "text-red-600")}>
                      {money(fmt, c.amount)}
                    </TableCell>
                    <TableCell className="text-sm">
                      <PaymentCell row={c} fmt={fmt} />
                    </TableCell>
                    <TableCell className="text-sm">
                      <ExpenseLink row={c} expensesHref={expensesHref} />
                    </TableCell>
                    <TableCell className="whitespace-nowrap text-right">
                      <CostActions row={c} locked={locked} lockedNote={notes.costLockedByDepreciationNote}
                                   onView={onViewCost} onReverse={onReverseCost} />
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>

          <ul className="space-y-2 lg:hidden">
            {posted.map((c) => (
              <li key={c.id} className="rounded-md border border-slate-200 bg-white p-3">
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <CostTypeBadge row={c} />
                    <p className="mt-1 truncate text-sm text-slate-900">{c.description ?? "—"}</p>
                    <p className="text-[11px] text-slate-500">
                      {fmtDateTime(c.costDate, c)}
                      {c.supplierName ? ` · ${c.supplierName}` : ""}
                    </p>
                  </div>
                  <div className={cn("shrink-0 text-right text-sm font-semibold tabular-nums",
                                     c.amount < 0 && "text-red-600")}>
                    {money(fmt, c.amount)}
                  </div>
                </div>
                <div className="mt-2 flex flex-wrap items-center justify-between gap-2 text-[11px] text-slate-500">
                  <PaymentCell row={c} fmt={fmt} />
                  <CostActions row={c} locked={locked} lockedNote={notes.costLockedByDepreciationNote}
                               onView={onViewCost} onReverse={onReverseCost} />
                </div>
              </li>
            ))}
          </ul>

          {/* §12's footer. It is a SUM of the rows above it, which is the whole
              claim this tab is making. */}
          <div className="flex items-center justify-between rounded-md border border-slate-300 bg-slate-50 px-3 py-2 text-sm">
            <span className="text-slate-700">Total capitalised cost</span>
            <strong className="tabular-nums text-slate-900">{fmt(total)}</strong>
          </div>
        </>
      )}

      {reversed.length > 0 && (
        <div className="rounded-md border border-slate-200 bg-slate-50 p-3">
          <SectionLabel>Reversed — kept on the record, excluded from the total</SectionLabel>
          <ul className="space-y-1.5">
            {reversed.map((c) => (
              <li key={c.id} className="flex flex-wrap items-baseline justify-between gap-2 text-sm text-slate-500">
                <span className="line-through">
                  {fmtDateTime(c.costDate, c)} · {c.description ?? "—"}
                </span>
                <span className="tabular-nums line-through">{money(fmt, c.amount)}</span>
                {c.reversalReason && (
                  <span className="w-full text-[11px] not-italic">
                    Reversed{c.reversedBy ? ` by ${c.reversedBy}` : ""}
                    {c.reversedAt ? ` on ${fmtInstant(c.reversedAt)}` : ""}: {c.reversalReason}
                  </span>
                )}
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  )
}

function CostTypeBadge({ row }: { row: AssetCostRow }) {
  const isCorrection = row.sourceType === "OriginalCostCorrection"
  const isAcquisition = row.sourceType === "Acquisition"
  const label = isCorrection
    ? "Original cost correction"
    : isAcquisition
      ? "Original acquisition"
      : (row.costCategory ?? "").trim() || "Additional cost"
  return (
    <Badge
      variant="outline"
      className={cn(
        "whitespace-nowrap text-[10px] font-normal",
        isCorrection && "border-rose-300 bg-rose-50 text-rose-700",
        isAcquisition && "border-blue-300 bg-blue-50 text-blue-700",
        !isCorrection && !isAcquisition && "border-violet-300 bg-violet-50 text-violet-700",
      )}
    >
      {label}
    </Badge>
  )
}

/**
 * A correction has no payment of its own -- it AMENDED the acquisition's
 * document rather than creating one -- so printing "Paid GHC 0" beside it would
 * be a third wrong number on a screen that exists to remove wrong numbers.
 */
function PaymentCell({ row, fmt }: { row: AssetCostRow; fmt: (n: number) => string }) {
  if (row.sourceType === "OriginalCostCorrection") {
    return <span className="text-slate-500">Adjusts the acquisition</span>
  }
  return (
    <span>
      {row.paymentStatus ?? "—"}
      {row.paymentMethod ? ` · ${row.paymentMethod}` : ""}
      {(row.balance ?? 0) > 0 && (
        <span className="block text-[11px] text-amber-700">{fmt(row.balance ?? 0)} owed</span>
      )}
    </span>
  )
}

function ExpenseLink({ row, expensesHref }: { row: AssetCostRow; expensesHref: string }) {
  if (!row.expenseId) return <span className="text-slate-400">—</span>
  return (
    <Link href={expensesHref} className="text-slate-600 underline underline-offset-2 hover:text-slate-900">
      Expense #{row.expenseId}
    </Link>
  )
}

function CostActions({ row, locked, lockedNote, onView, onReverse }: {
  row: AssetCostRow
  locked: boolean
  lockedNote: string
  onView?: (r: AssetCostRow) => void
  onReverse?: (r: AssetCostRow) => void
}) {
  // Offered only where the server can accept it. The SP refuses the acquisition
  // (correct it instead), refuses a correction (correct it again instead) and
  // refuses everything once a month has been charged -- and a button that always
  // errors is worse than no button.
  const reversible = row.sourceType !== "Acquisition"
    && row.sourceType !== "OriginalCostCorrection"
    && row.status === "Posted"
  return (
    <span className="inline-flex items-center gap-1">
      {onView && (
        <Button variant="ghost" size="sm" title="View everything recorded about this cost"
                onClick={() => onView(row)}>
          <Eye className="h-4 w-4" />
        </Button>
      )}
      {onReverse && reversible && (
        <Button variant="ghost" size="sm" disabled={locked}
                title={locked ? lockedNote : "Reverse this cost"}
                onClick={() => onReverse(row)}>
          <Undo2 className={cn("h-4 w-4", !locked && "text-red-500")} />
        </Button>
      )}
    </span>
  )
}

// ------------------------------------------------------ depreciation history --

function DepreciationHistoryTab({
  view, fmt, term, notes, expensesHref, onReverseDepreciation,
}: AssetDetailsPanelProps & { view: AssetDetailsView }) {
  const rows = view.depreciation

  return (
    <div className="space-y-3">
      {/* §27. The basis first: every row below is this schedule doing its work,
          and without it the amounts are just numbers. */}
      <div className="grid grid-cols-2 gap-2 lg:grid-cols-4">
        <Figure label="Depreciable basis" value={fmt(view.depreciableAmount)}
                hint="Total capitalised cost less the residual value. This is what is charged to profit over the life." />
        <Figure label="Monthly charge"
                value={view.monthlyDepreciation ? fmt(view.monthlyDepreciation) : "—"}
                hint={view.usefulLifeMonths ? `Straight line over ${view.usefulLifeMonths} months.` : "No useful life set yet."} />
        <Figure label="Charged so far" value={fmt(view.accumulatedDepreciation)} tone="amber" />
        <Figure label="Still to charge" value={fmt(view.remainingDepreciable)} tone="emerald" />
      </div>

      {rows.length === 0 ? (
        <div className="space-y-1.5 rounded-md border border-slate-200 bg-white px-3 py-4">
          <p className="text-sm text-slate-600">
            No depreciation has been posted for this {term} yet.
          </p>
          {/* §66. Says where posting happens; deliberately does NOT post from
              here. Due depreciation is the action centre's job. */}
          {view.status === "Draft" ? (
            <p className="text-[11px] text-slate-500">
              It is not in service, so it does not depreciate. Set an in-service date and a useful
              life to start.
            </p>
          ) : view.remainingDepreciable > 0 ? (
            <p className="text-[11px] text-slate-500">
              Depreciation may be due. Use the Depreciation button above the list to review and post it.
            </p>
          ) : null}
        </div>
      ) : (
        <>
          <div className="hidden overflow-x-auto lg:block">
            <Table className="min-w-[820px]">
              <TableHeader><TableRow>
                <TableHead>Period</TableHead>
                <TableHead>Posted</TableHead>
                <TableHead>Type</TableHead>
                <TableHead className="text-right">Depreciation</TableHead>
                <TableHead className="text-right">Accumulated</TableHead>
                <TableHead className="text-right">Book value after</TableHead>
                <TableHead>Expense</TableHead>
                <TableHead className="text-right">Actions</TableHead>
              </TableRow></TableHeader>
              <TableBody>
                {rows.map((d) => (
                  <TableRow key={d.id} className={cn(d.status === "Reversed" && "opacity-60")}>
                    <TableCell className="whitespace-nowrap text-sm">
                      {fmtMonthYear(d.periodStart)}
                      {d.status === "Reversed" && (
                        <span className="ml-2 text-[11px] text-red-600">reversed</span>
                      )}
                    </TableCell>
                    <TableCell className="align-top text-sm">
                      {d.depreciationDate
                        ? <DateTimeCell value={d.depreciationDate} row={d} />
                        : <span className="text-slate-400">—</span>}
                    </TableCell>
                    <TableCell className="text-sm text-slate-500">
                      {d.sourceType}
                      {d.reversalReason && <div className="text-[11px]">{d.reversalReason}</div>}
                    </TableCell>
                    <TableCell className={cn("text-right tabular-nums text-sm", d.amount < 0 && "text-red-600")}>
                      {money(fmt, d.amount)}
                    </TableCell>
                    <TableCell className="text-right tabular-nums text-sm text-slate-500">
                      {d.accumulatedAfter != null ? fmt(d.accumulatedAfter) : "—"}
                    </TableCell>
                    <TableCell className="text-right tabular-nums text-sm">
                      {d.bookValueAfter != null ? fmt(d.bookValueAfter) : "—"}
                    </TableCell>
                    <TableCell className="text-sm">
                      {d.expenseId ? (
                        <Link href={expensesHref}
                              className="inline-flex items-center gap-1 text-slate-600 underline underline-offset-2 hover:text-slate-900">
                          <Receipt className="h-3.5 w-3.5" /> #{d.expenseId}
                        </Link>
                      ) : <span className="text-slate-400">—</span>}
                    </TableCell>
                    <TableCell className="text-right">
                      {onReverseDepreciation && d.status === "Posted" && d.amount > 0 && (
                        <Button variant="ghost" size="sm" title="Reverse this charge"
                                onClick={() => onReverseDepreciation(d)}>
                          <Undo2 className="h-4 w-4 text-red-500" />
                        </Button>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>

          <ul className="space-y-2 lg:hidden">
            {rows.map((d) => (
              <li key={d.id}
                  className={cn("rounded-md border border-slate-200 bg-white p-3",
                                d.status === "Reversed" && "opacity-60")}>
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <p className="text-sm font-medium text-slate-900">{fmtMonthYear(d.periodStart)}</p>
                    <p className="text-[11px] text-slate-500">
                      {d.sourceType}
                      {d.depreciationDate ? ` · posted ${fmtDateTime(d.depreciationDate, d)}` : ""}
                    </p>
                  </div>
                  <div className={cn("text-right text-sm font-semibold tabular-nums",
                                     d.amount < 0 && "text-red-600")}>
                    {money(fmt, d.amount)}
                  </div>
                </div>
                <div className="mt-2 grid grid-cols-2 gap-x-4 text-[11px] text-slate-500">
                  <span>Accumulated <strong className="tabular-nums text-slate-700">
                    {d.accumulatedAfter != null ? fmt(d.accumulatedAfter) : "—"}</strong></span>
                  <span>Book value after <strong className="tabular-nums text-slate-700">
                    {d.bookValueAfter != null ? fmt(d.bookValueAfter) : "—"}</strong></span>
                </div>
                <div className="mt-2 flex items-center justify-between gap-2">
                  {d.expenseId ? (
                    <Link href={expensesHref}
                          className="inline-flex items-center gap-1 text-[11px] text-slate-600 underline underline-offset-2">
                      <Receipt className="h-3.5 w-3.5" /> Expense #{d.expenseId}
                    </Link>
                  ) : <span />}
                  {onReverseDepreciation && d.status === "Posted" && d.amount > 0 && (
                    <Button variant="ghost" size="sm" onClick={() => onReverseDepreciation(d)}>
                      <Undo2 className="mr-1 h-3.5 w-3.5 text-red-500" /> Reverse
                    </Button>
                  )}
                </div>
              </li>
            ))}
          </ul>
        </>
      )}

      <p className="flex items-start gap-1.5 text-[11px] text-slate-500">
        <Info className="mt-0.5 h-3.5 w-3.5 shrink-0" />
        <span>{notes.depreciationNonCashNote} {notes.depreciationConventionNote}</span>
      </p>
    </div>
  )
}

// ---------------------------------------------------------------- house bits --

/** House section heading — matches cash-flow-insights-dialog. */
function SectionLabel({ children }: { children: ReactNode }) {
  return (
    <h4 className="mb-1.5 text-[11px] font-semibold uppercase tracking-wide text-slate-500">
      {children}
    </h4>
  )
}

/**
 * A figure tile.
 *
 * NEUTRAL BY DEFAULT, AND THAT IS THE POINT
 * -----------------------------------------
 * These started as filled HIGHLIGHT_TONES tiles -- blue, violet, slate, amber,
 * emerald across two rows -- which read as a rainbow rather than as meaning. The
 * three cost figures are the worst case: acquisition, additional and total are
 * three views of ONE number, and giving them three colours says they are three
 * different kinds of thing.
 *
 * So the tile is a white card with a slate border, matching the register's own
 * scorecards directly above it on the same page, and colour is spent on exactly
 * two ideas: AMBER for cost that has reached profit, EMERALD for what the
 * company still owns. `strong` rings the figure its row exists to produce.
 */
function Figure({ label, value, tone, hint, strong }: {
  label: string
  value: string
  /**
   * Left off for most figures on purpose. Only TWO ideas earn a colour here:
   * amber for cost that has reached profit, emerald for what the company still
   * owns. Everything else is a neutral tile.
   */
  tone?: "amber" | "emerald"
  hint?: string
  /** The figure its row exists to produce. */
  strong?: boolean
}) {
  return (
    <div
      className={cn(
        "rounded-lg border bg-white px-3 py-2 shadow-sm",
        tone === "amber" ? "border-amber-200"
          : tone === "emerald" ? "border-emerald-200"
          : "border-slate-200",
        strong && "ring-1 ring-slate-300",
      )}
      title={hint}
    >
      <p className="text-[11px] font-semibold uppercase tracking-wide text-slate-500">{label}</p>
      <p className={cn("text-base font-extrabold leading-tight tabular-nums break-words",
        tone === "amber" ? "text-amber-800"
          : tone === "emerald" ? "text-emerald-800"
          : "text-slate-900")}>
        {value}
      </p>
    </div>
  )
}

function Line({ label, value, wide }: { label: string; value: string; wide?: boolean }) {
  return (
    <div className={cn("flex justify-between gap-4 text-sm", wide && "sm:col-span-2 lg:col-span-3")}>
      <span className="shrink-0 text-slate-600">{label}</span>
      <span className="truncate text-right text-slate-900">{value}</span>
    </div>
  )
}
