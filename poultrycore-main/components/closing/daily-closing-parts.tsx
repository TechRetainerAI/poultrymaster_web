"use client"

// Display pieces of the Daily Closing page (migration 333). Every figure here
// is read from the workspace document the Farm API built; nothing is summed or
// re-classified in the browser.

import Link from "next/link"
import { AlertTriangle, Ban, CheckCircle2, History, Lock } from "lucide-react"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { cn } from "@/lib/utils"
import type {
  ClosingCheck,
  ClosingEvent,
  ClosingRecord,
  ClosingWorkspace,
} from "@/lib/api/poultry-daily-closing"
import {
  SECTION_LABELS,
  checkIcon,
  closingActionHref,
  formatLongDate,
  productionSummaryLine,
  type FigureChange,
} from "@/lib/closing/daily-closing"

type Money = (n: number) => string
const qty = (n: number | null | undefined, digits = 0) =>
  Number(n ?? 0).toLocaleString(undefined, { maximumFractionDigits: digits })

function Stat({ label, value, tone }: { label: string; value: string; tone?: "good" | "bad" | "muted" }) {
  return (
    <div className="rounded-lg border border-slate-200 bg-white px-3 py-2">
      <div className="text-[11px] uppercase tracking-wide text-slate-500">{label}</div>
      <div
        className={cn(
          "font-semibold tabular-nums",
          tone === "good" && "text-emerald-700",
          tone === "bad" && "text-rose-700",
          tone === "muted" && "text-slate-400",
          !tone && "text-slate-900",
        )}
      >
        {value}
      </div>
    </div>
  )
}

function Section({ title, children, note }: { title: string; children: React.ReactNode; note?: string }) {
  return (
    <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
      <CardContent className="space-y-3 p-4">
        <h2 className="text-xs font-semibold uppercase tracking-wider text-slate-500">{title}</h2>
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">{children}</div>
        {note && <p className="text-xs text-slate-500">{note}</p>}
      </CardContent>
    </Card>
  )
}

/** PRODUCTION · SALES · CASH · EXPENSES · INVENTORY · OUTSTANDING */
export function ClosingSections({ ws, fmt }: { ws: ClosingWorkspace; fmt: Money }) {
  const p = ws.production
  const s = ws.sales
  const c = ws.cash
  const e = ws.expenses
  const inv = ws.inventory
  const o = ws.outstanding
  const inventoryIssues = inv.lowFeed.length + inv.lowStock.length + inv.negativeStock.length

  return (
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
      <Section title="Production">
        <Stat
          label="Production records"
          value={p.expectedFlocks === 0 ? "None expected" : `${p.reportedFlocks} / ${p.expectedFlocks} expected`}
          tone={p.missingFlocks > 0 ? "bad" : undefined}
        />
        <Stat label="Eggs produced" value={qty(p.eggsProduced)} />
        <Stat label="Damaged eggs" value={qty(p.eggsDamaged)} />
        <Stat label="Mortality" value={qty(p.mortality)} />
        <Stat label="Feed used" value={`${qty(p.feedKg, 2)} kg`} />
        <Stat label="Missing production" value={qty(p.missingFlocks)} tone={p.missingFlocks > 0 ? "bad" : "good"} />
      </Section>

      <Section
        title="Sales"
        note="Sales are revenue. Payments received settle earlier credit and are not added to revenue."
      >
        <Stat label="Sales recorded" value={qty(s.count)} />
        <Stat label="Amount" value={fmt(s.revenue)} />
        <Stat label="Cash sales" value={fmt(s.cashSales)} />
        <Stat label="Credit sales" value={fmt(s.creditSales)} tone={s.creditSales > 0 ? "bad" : undefined} />
        <Stat label="Payments received" value={`${fmt(s.paymentsReceived)}${s.paymentsCount ? ` (${s.paymentsCount})` : ""}`} />
        <Stat
          label="Customer balances"
          value={`${s.receivablesChange > 0 ? "+" : ""}${fmt(s.receivablesChange)}`}
          tone={s.receivablesChange > 0 ? "bad" : s.receivablesChange < 0 ? "good" : undefined}
        />
      </Section>

      <Section
        title="Cash"
        note={c.reconciliations > 0
          ? `From ${c.reconciliations} posted cash count${c.reconciliations === 1 ? "" : "s"} for this day.`
          : "Expected vs actual appears once a cash count is posted for this day."}
      >
        <Stat label="Money in today" value={fmt(c.moneyIn)} tone="good" />
        <Stat label="Money out today" value={fmt(c.moneyOut)} tone="bad" />
        <Stat label="Net cash flow" value={fmt(c.netCashFlow)} tone={c.netCashFlow < 0 ? "bad" : undefined} />
        {c.reconciliations > 0 && (
          <>
            <Stat label="Expected cash" value={fmt(c.expectedCash ?? 0)} />
            <Stat label="Actual (counted)" value={fmt(c.actualCash ?? 0)} />
            <Stat
              label="Difference"
              value={fmt(c.difference ?? 0)}
              tone={(c.difference ?? 0) === 0 ? "good" : "bad"}
            />
          </>
        )}
      </Section>

      <Section title="Expenses" note="Non-cash covers depreciation, internal usage and consumption recognition.">
        <Stat label="Expenses recorded" value={`${qty(e.count)} · ${fmt(e.total)}`} />
        <Stat label="Cash (paid)" value={fmt(e.cash)} />
        <Stat label="Credit (unpaid)" value={fmt(e.credit)} tone={e.credit > 0 ? "bad" : undefined} />
        <Stat label="Non-cash" value={fmt(e.nonCash)} tone="muted" />
      </Section>

      <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
        <CardContent className="space-y-2 p-4">
          <h2 className="text-xs font-semibold uppercase tracking-wider text-slate-500">Inventory</h2>
          {inventoryIssues === 0 ? (
            <p className="flex items-center gap-1.5 text-sm text-emerald-700">
              <CheckCircle2 className="h-4 w-4" /> No stock exceptions.
            </p>
          ) : (
            <ul className="space-y-1 text-sm">
              {inv.negativeStock.map((i) => (
                <li key={`n${i.itemId}`} className="text-rose-700">
                  {i.item}: negative stock ({qty(i.quantity, 2)} {i.unit ?? ""})
                </li>
              ))}
              {inv.lowFeed.map((i) => (
                <li key={`f${i.itemId}`} className="text-amber-800">
                  {i.item}: about {i.daysRemaining} days remaining ({qty(i.quantity, 2)} {i.unit ?? ""} at{" "}
                  {qty(i.dailyUse, 2)}/day)
                </li>
              ))}
              {inv.lowStock.map((i) => (
                <li key={`l${i.itemId}`} className="text-amber-800">
                  {i.item}: {qty(i.quantity, 2)} {i.unit ?? ""} (reorder at {qty(i.minimum, 2)})
                </li>
              ))}
            </ul>
          )}
          <p className="text-xs text-slate-500">Stock levels are current, not as of this date.</p>
        </CardContent>
      </Card>

      <Section title="Outstanding items">
        <Stat label="Unposted batch production" value={qty(o.unpostedBatches)} tone={o.unpostedBatches > 0 ? "bad" : undefined} />
        <Stat label="Draft driver returns" value={qty(o.draftDriverReturns)} tone={o.draftDriverReturns > 0 ? "bad" : undefined} />
        <Stat
          label="Loadings with no return"
          value={qty(o.loadingsWithoutReturn)}
          tone={o.loadingsWithoutReturn > 0 ? "bad" : undefined}
        />
        <Stat label="Previous day" value={o.previousDayClosed ? "Closed" : "Not closed"} tone={o.previousDayClosed ? "good" : undefined} />
      </Section>
    </div>
  )
}

const STATUS_STYLE = {
  check: { icon: CheckCircle2, cls: "text-emerald-600" },
  warning: { icon: AlertTriangle, cls: "text-amber-600" },
  block: { icon: Ban, cls: "text-rose-600" },
} as const

/** CLOSING CHECKLIST — blocking first, then warnings, then complete (server order). */
export function ClosingChecklist({ checks, businessDate }: { checks: ClosingCheck[]; businessDate: string }) {
  return (
    <ul className="divide-y divide-slate-100">
      {checks.map((c) => {
        const s = STATUS_STYLE[checkIcon(c.status)]
        const href = c.status === "Complete" ? null : closingActionHref(c.action, businessDate)
        return (
          <li key={c.key} className="flex items-start justify-between gap-3 py-2">
            <div className="flex min-w-0 items-start gap-2">
              <s.icon className={cn("mt-0.5 h-4 w-4 shrink-0", s.cls)} aria-label={c.status} />
              <div className="min-w-0">
                <p className={cn("text-sm", c.status === "Complete" ? "text-slate-600" : "font-medium text-slate-900")}>
                  {c.title}
                  <span className="ml-2 text-[11px] font-normal uppercase tracking-wide text-slate-400">
                    {SECTION_LABELS[c.section] ?? c.section}
                  </span>
                </p>
                {c.description && <p className="text-xs text-slate-500">{c.description}</p>}
              </div>
            </div>
            {href && (
              <Link href={href} className="shrink-0 text-sm font-medium text-sky-700 hover:underline">
                {c.status === "Blocking" ? "Resolve" : "Review"}
              </Link>
            )}
          </li>
        )
      })}
    </ul>
  )
}

/** "September 20, 2026 — CLOSED" and the headline figures as closed. */
export function ClosedSummary({
  record, atClose, fmt, fmtInstant,
}: {
  record: ClosingRecord
  atClose: ClosingWorkspace
  fmt: Money
  fmtInstant: (v: string | null | undefined) => string
}) {
  return (
    <Card className="rounded-xl border border-l-4 border-slate-200 border-l-emerald-500 bg-white shadow-sm">
      <CardContent className="space-y-3 p-4">
        <div className="flex flex-wrap items-center gap-2">
          <Lock className="h-4 w-4 text-emerald-600" />
          <h2 className="text-lg font-bold text-slate-900">
            {formatLongDate(atClose.businessDate)} — <span className="text-emerald-700">CLOSED</span>
          </h2>
          {record.closeVersion > 1 && (
            <span className="rounded-full bg-slate-100 px-2 py-0.5 text-xs text-slate-600">
              closed {record.closeVersion} times
            </span>
          )}
        </div>
        <dl className="grid grid-cols-2 gap-x-6 gap-y-1 text-sm sm:grid-cols-3">
          <div><dt className="inline text-slate-500">Production: </dt><dd className="inline font-medium">{productionSummaryLine(atClose)}</dd></div>
          <div><dt className="inline text-slate-500">Sales: </dt><dd className="inline font-medium tabular-nums">{fmt(atClose.sales.revenue)}</dd></div>
          <div><dt className="inline text-slate-500">Money in: </dt><dd className="inline font-medium tabular-nums">{fmt(atClose.cash.moneyIn)}</dd></div>
          <div><dt className="inline text-slate-500">Money out: </dt><dd className="inline font-medium tabular-nums">{fmt(atClose.cash.moneyOut)}</dd></div>
          <div><dt className="inline text-slate-500">Net cash flow: </dt><dd className="inline font-medium tabular-nums">{fmt(atClose.cash.netCashFlow)}</dd></div>
          <div><dt className="inline text-slate-500">Warnings at closing: </dt><dd className="inline font-medium">{record.warningsAtClose ?? atClose.counts.warning}</dd></div>
        </dl>
        <p className="text-xs text-slate-500">
          Closed by {record.closedBy ?? "unknown"} · {fmtInstant(record.closedAtUtc)}
          {record.managerNotes ? ` · “${record.managerNotes}”` : ""}
        </p>
      </CardContent>
    </Card>
  )
}

/** State At Closing vs Current Corrected State, for the figures that moved. */
export function ChangesSinceClosing({ changes, fmt }: { changes: FigureChange[]; fmt: Money }) {
  if (changes.length === 0) return null
  const show = (c: FigureChange, v: number) => (c.kind === "money" ? fmt(v) : qty(v, c.kind === "quantity" ? 2 : 0))
  return (
    <Card className="rounded-xl border border-amber-200 bg-amber-50/60 shadow-sm">
      <CardContent className="space-y-2 p-4">
        <h2 className="flex items-center gap-1.5 text-sm font-semibold text-amber-900">
          <AlertTriangle className="h-4 w-4" /> Changed since closing
        </h2>
        <p className="text-xs text-amber-900/80">
          Records for this day were added or corrected after it was closed. The closing keeps what it was closed
          with; reopen and close again to adopt the corrected figures.
        </p>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[28rem] text-sm">
            <thead className="text-left text-xs uppercase tracking-wider text-amber-900/70">
              <tr>
                <th className="py-1 pr-3 font-medium">Figure</th>
                <th className="py-1 pr-3 text-right font-medium">State at closing</th>
                <th className="py-1 pr-3 text-right font-medium">Current corrected state</th>
                <th className="py-1 text-right font-medium">Change</th>
              </tr>
            </thead>
            <tbody>
              {changes.map((c) => (
                <tr key={c.label} className="border-t border-amber-200/70">
                  <td className="py-1 pr-3">{c.label}</td>
                  <td className="py-1 pr-3 text-right tabular-nums">{show(c, c.atClose)}</td>
                  <td className="py-1 pr-3 text-right tabular-nums">{show(c, c.current)}</td>
                  <td className="py-1 text-right font-medium tabular-nums">
                    {c.delta > 0 ? "+" : ""}{show(c, c.delta)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </CardContent>
    </Card>
  )
}

const EVENT_LABEL: Record<ClosingEvent["eventType"], string> = {
  Created: "Started",
  Submitted: "Submitted for approval",
  Rejected: "Rejected",
  Closed: "Closed",
  Reopened: "Reopened",
  Recreated: "Recreated",
  Deleted: "Deleted",
}

/** Who did what to this day, and why. Append-only on the server. */
export function ClosingTimeline({
  events, fmtInstant, onViewSnapshot,
}: {
  events: ClosingEvent[]
  fmtInstant: (v: string | null | undefined) => string
  onViewSnapshot: (e: ClosingEvent) => void
}) {
  if (events.length === 0) return <p className="text-sm text-slate-500">Nothing has been recorded for this day yet.</p>
  return (
    <ol className="space-y-2">
      {[...events].reverse().map((e) => (
        <li key={e.eventId} className="flex items-start justify-between gap-3 text-sm">
          <div className="flex min-w-0 items-start gap-2">
            <History className="mt-0.5 h-4 w-4 shrink-0 text-slate-400" />
            <div className="min-w-0">
              <p className="text-slate-900">
                <span className="font-medium">{EVENT_LABEL[e.eventType] ?? e.eventType}</span>
                {e.eventType === "Closed" && e.closeVersion ? ` (v${e.closeVersion}${e.warningCount ? `, ${e.warningCount} warnings` : ""})` : ""}
                {" "}by {e.actor ?? "unknown"}
              </p>
              <p className="text-xs text-slate-500">{fmtInstant(e.occurredAtUtc)}</p>
              {e.reason && <p className="text-xs text-slate-700">Reason: {e.reason}</p>}
            </div>
          </div>
          {e.hasSnapshot && (
            <Button variant="ghost" size="sm" className="h-7 shrink-0 text-xs" onClick={() => onViewSnapshot(e)}>
              View as closed
            </Button>
          )}
        </li>
      ))}
    </ol>
  )
}
