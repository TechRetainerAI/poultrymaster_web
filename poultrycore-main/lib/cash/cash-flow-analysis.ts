// =============================================================================
// Cash Flow Detail — analysis.
//
// Turns the report's summary into a handful of plain-English readings. Pure and
// dependency-free (no React, no API, no currency store) so it can be unit
// tested, which matters here more than usual: these sentences make claims about
// somebody's money, and a wrong one is worse than no sentence at all.
//
// House pattern: lib/cash/cash-flow.ts, lib/balances/allocate.ts.
//
// Two rules the whole module follows:
//
//   1. NEVER INVENT A TREND FROM NOTHING. A comparison against a previous period
//      with no activity is not "up 100%", it is not a comparison. Those cases
//      return no insight rather than a confident-sounding fiction.
//
//   2. MONEY WITHOUT A CASH ACCOUNT IS NOT A FAULT. Paying a vet out of pocket
//      is ordinary business. It gets a neutral reading, never a warning tone.
// =============================================================================

export type AnalysisTone = "good" | "watch" | "neutral"

export interface AnalysisItem {
  id: string
  tone: AnalysisTone
  title: string
  detail: string
}

export interface CashFlowBucket {
  label: string
  amount: number
  sharePercent?: number | null
  movements?: number
}

export interface CashFlowAnalysisInput {
  moneyIn: number
  moneyOut: number
  /**
   * The four flow groups. Optional so callers that only have totals still work;
   * when present they unlock the reading that matters most in a cash flow —
   * whether the business funded itself or was funded.
   */
  operatingIn?: number
  operatingOut?: number
  financingIn?: number
  financingOut?: number
  netCashFlow: number
  cashAtHand: number
  offLedgerIn: number
  offLedgerOut: number
  transferVolume: number
  movementCount: number
  daysInPeriod: number
  previousMoneyIn: number
  previousMoneyOut: number
  previousNetCashFlow: number
  moneyInByCategory: CashFlowBucket[]
  moneyOutByCategory: CashFlowBucket[]
}

/** Percentage change, or null when the baseline is zero and a ratio is meaningless. */
export function pctChange(now: number, before: number): number | null {
  if (!Number.isFinite(now) || !Number.isFinite(before)) return null
  if (before === 0) return null
  return ((now - before) / Math.abs(before)) * 100
}

/** "up 12.4%" / "down 3.0%" / "unchanged" — direction in words, not a signed number. */
export function describeChange(pct: number | null): string | null {
  if (pct == null) return null
  const r = Math.round(Math.abs(pct) * 10) / 10
  if (r < 0.1) return "unchanged"
  return `${pct > 0 ? "up" : "down"} ${r.toFixed(1)}%`
}

/**
 * How many days the current cash would last at this period's net burn rate.
 * Null unless money is genuinely going out faster than it comes in — a runway
 * figure for a cash-positive period is nonsense.
 */
export function runwayDays(cashAtHand: number, netCashFlow: number, daysInPeriod: number): number | null {
  if (netCashFlow >= 0 || daysInPeriod <= 0 || cashAtHand <= 0) return null
  const perDay = Math.abs(netCashFlow) / daysInPeriod
  if (perDay <= 0) return null
  return Math.floor(cashAtHand / perDay)
}

const round2 = (n: number) => Math.round(n * 100) / 100

/**
 * The readings, most decision-relevant first.
 *
 * `fmt` is injected rather than imported so the sentences can be tested without
 * the currency store — the same trick buildCashFlowInsights uses.
 */
export function buildCashFlowAnalysis(
  s: CashFlowAnalysisInput,
  fmt: (n: number) => string,
): AnalysisItem[] {
  const out: AnalysisItem[] = []
  const hasActivity = s.moneyIn > 0 || s.moneyOut > 0
  if (!hasActivity) {
    return [{
      id: "no-activity",
      tone: "neutral",
      title: "No cash moved in this period",
      detail: "Nothing came in and nothing went out. Widen the date range, or check that sales and expenses are being recorded.",
    }]
  }

  // ---- 1. Did the business keep money? ------------------------------------
  if (s.netCashFlow >= 0) {
    const kept = s.moneyIn > 0 ? (s.netCashFlow / s.moneyIn) * 100 : 0
    out.push({
      id: "net-positive",
      tone: "good",
      title: `Cash positive — you kept ${fmt(s.netCashFlow)}`,
      detail: `${fmt(s.moneyIn)} came in and ${fmt(s.moneyOut)} went out, so you held on to ${kept.toFixed(1)} of every 100 that arrived.`,
    })
  } else {
    const gap = Math.abs(s.netCashFlow)
    out.push({
      id: "net-negative",
      tone: "watch",
      title: `Spent ${fmt(gap)} more than came in`,
      detail: `${fmt(s.moneyOut)} went out against ${fmt(s.moneyIn)} in. The gap was covered by cash already held, so the balance fell rather than the business stopping.`,
    })
  }

  // ---- 1b. Did the business fund itself? ----------------------------------
  // The single most useful thing a cash flow can say, and the reason operating
  // and financing are separated at all. A month that looks healthy on the net
  // figure alone can be a month the owner paid for.
  const opIn = s.operatingIn ?? 0
  const opOut = s.operatingOut ?? 0
  const finIn = s.financingIn ?? 0
  const finOut = s.financingOut ?? 0
  const hasGroups = opIn + opOut + finIn + finOut > 0

  if (hasGroups) {
    const operatingNet = opIn - opOut
    if (operatingNet >= 0) {
      out.push({
        id: "operating-self-funding",
        tone: "good",
        title: `Trading covered its own costs, with ${fmt(operatingNet)} left`,
        detail: finIn > 0
          ? `${fmt(opIn)} earned against ${fmt(opOut)} spent. ${fmt(finIn)} of capital also came in, but the business did not need it to cover trading.`
          : `${fmt(opIn)} earned against ${fmt(opOut)} spent, with no capital needed.`,
      })
    } else {
      const gap = Math.abs(operatingNet)
      const covered = finIn >= gap
      out.push({
        id: "operating-shortfall",
        tone: "watch",
        title: `Trading fell short by ${fmt(gap)}`,
        detail: finIn > 0
          ? `${fmt(opIn)} earned against ${fmt(opOut)} spent. ${fmt(finIn)} of capital came in, ${covered ? "which covered the gap" : "which did not cover it"} — so ${covered ? "this period was funded rather than earned" : "cash already held made up the rest"}.`
          : `${fmt(opIn)} earned against ${fmt(opOut)} spent, and no capital came in — the gap came out of cash already held.`,
      })
    }
  }

  // ---- 1c. Capital taken out ----------------------------------------------
  if (finOut > 0) {
    out.push({
      id: "capital-out",
      tone: "neutral",
      title: `${fmt(finOut)} taken out as capital`,
      detail: "Owner withdrawals and loan repayments. Counted in money out, but it is not a cost of running the business — trading performance is the operating figures above.",
    })
  }

  // ---- 2. Where the money actually went -----------------------------------
  const topOut = s.moneyOutByCategory[0]
  if (topOut && topOut.amount > 0 && s.moneyOut > 0) {
    const share = topOut.sharePercent ?? (topOut.amount / s.moneyOut) * 100
    // Concentration is only worth flagging when there was a real choice of
    // where to spend. With one or two categories it is arithmetic, not insight.
    const concentrated = share >= 50 && s.moneyOutByCategory.length >= 3
    out.push({
      id: "top-outflow",
      tone: concentrated ? "watch" : "neutral",
      title: `${topOut.label} took ${share.toFixed(1)}% of spending`,
      detail: concentrated
        ? `${fmt(topOut.amount)} of ${fmt(s.moneyOut)} went on ${topOut.label.toLowerCase()} — more than half of everything spent. A price change there moves the whole month.`
        : `${fmt(topOut.amount)} of ${fmt(s.moneyOut)}, the largest of ${s.moneyOutByCategory.length} spending categories.`,
    })
  }

  // ---- 3. Where it came from ----------------------------------------------
  const topIn = s.moneyInByCategory[0]
  if (topIn && topIn.amount > 0 && s.moneyIn > 0) {
    const share = topIn.sharePercent ?? (topIn.amount / s.moneyIn) * 100
    const single = s.moneyInByCategory.length === 1
    out.push({
      id: "top-inflow",
      tone: share >= 80 && !single ? "watch" : "neutral",
      title: `${topIn.label} brought in ${share.toFixed(1)}% of the money`,
      detail: single
        ? `All ${fmt(topIn.amount)} of it. Every cedi this period came from one place.`
        : `${fmt(topIn.amount)} of ${fmt(s.moneyIn)}${share >= 80 ? " — most income depends on this one source." : "."}`,
    })
  }

  // ---- 4. Against the period before ---------------------------------------
  // Only when the previous window actually had activity. Otherwise there is no
  // trend to report, and inventing one is how a report loses trust.
  const prevActive = s.previousMoneyIn > 0 || s.previousMoneyOut > 0
  if (prevActive) {
    const inWord = describeChange(pctChange(s.moneyIn, s.previousMoneyIn))
    const outWord = describeChange(pctChange(s.moneyOut, s.previousMoneyOut))
    if (inWord || outWord) {
      const improving = s.netCashFlow > s.previousNetCashFlow
      out.push({
        id: "vs-previous",
        tone: improving ? "good" : "watch",
        title: improving ? "Better than the period before" : "Worse than the period before",
        detail: [
          inWord ? `Money in ${inWord}` : null,
          outWord ? `money out ${outWord}` : null,
        ].filter(Boolean).join(", ") +
          `. Net moved from ${fmt(s.previousNetCashFlow)} to ${fmt(s.netCashFlow)} over the same number of days.`,
      })
    }
  }

  // ---- 5. Burn rate and runway --------------------------------------------
  const runway = runwayDays(s.cashAtHand, s.netCashFlow, s.daysInPeriod)
  if (runway != null) {
    const perDay = Math.abs(s.netCashFlow) / s.daysInPeriod
    out.push({
      id: "runway",
      tone: runway < 30 ? "watch" : "neutral",
      title: `About ${runway} days of cash at this rate`,
      detail: `Net spending ran at ${fmt(round2(perDay))} a day. Against ${fmt(s.cashAtHand)} on hand that is roughly ${runway} days — a projection from this period alone, not a forecast.`,
    })
  } else if (s.netCashFlow > 0 && s.daysInPeriod > 0) {
    const perDay = s.netCashFlow / s.daysInPeriod
    out.push({
      id: "accumulation",
      tone: "good",
      title: `Building cash at ${fmt(round2(perDay))} a day`,
      detail: `Averaged across ${s.daysInPeriod} days. Cash on hand is ${fmt(s.cashAtHand)}.`,
    })
  }

  // ---- 6. Off-ledger, stated plainly --------------------------------------
  // Deliberately neutral and deliberately last. This is normal business; it is
  // here because it explains a difference, not because anything is wrong.
  const off = s.offLedgerIn + s.offLedgerOut
  if (off > 0) {
    const share = s.moneyIn + s.moneyOut > 0 ? (off / (s.moneyIn + s.moneyOut)) * 100 : 0
    out.push({
      id: "off-ledger",
      tone: "neutral",
      title: `${fmt(off)} moved without a cash account`,
      detail: `${share.toFixed(1)}% of all movement — usually owner injections, or expenses paid without picking an account. Counted in the totals above, but in no account balance, so reconciliation will not see it.`,
    })
  }

  // ---- 7. Transfers, if any ------------------------------------------------
  if (s.transferVolume > 0) {
    out.push({
      id: "transfers",
      tone: "neutral",
      title: `${fmt(s.transferVolume)} moved between your own accounts`,
      detail: "Excluded from money in and money out — it is the same money in a different place, not income or spending.",
    })
  }

  return out
}
