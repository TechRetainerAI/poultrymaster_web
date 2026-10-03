import { describe, expect, it } from "vitest"
import {
  alertHeadline,
  evaluationStatusText,
  eventText,
  flockLabel,
  isActiveStatus,
  guardText,
  methodUnit,
  severityRank,
  severityStyle,
  sortAlerts,
  summarizeAlerts,
  thresholdExample,
  thresholdHelp,
  toAssistantEvidence,
  validateSetting,
  type AlertSignal,
  type FlockAlert,
  type FlockAnomalySignalSetting,
} from "./flock-anomalies"

const signal = (p: Partial<AlertSignal> = {}): AlertSignal => ({
  signalKey: "MortalitySpike", label: "Mortality spike", isActive: true, severity: "Critical", observed: 4.67,
  explanation: ["Deaths today: 14 (7 per 1,000 of 2,000 birds)", "Compared with normal: today is 4.67 times normal"],
  evidence: { signalKey: "MortalitySpike" } as AlertSignal["evidence"],
  firstDetectedAtUtc: "2026-09-30T08:00:00Z", clearedAtUtc: null,
  ...p,
})

const alert = (p: Partial<FlockAlert> = {}): FlockAlert => ({
  alertId: 1, flockId: 10, flockName: "B2-P4", houseName: "House 2", businessDate: "2026-09-30T00:00:00",
  status: "Open", severity: "Critical", severityRank: 3, peakSeverity: "Critical", activeSignalCount: 1,
  consecutiveDays: 1, firstDetectedAtUtc: "", lastEvaluatedAtUtc: "", acknowledgedBy: null, acknowledgedAtUtc: null,
  resolvedBy: null, resolvedAtUtc: null, resolutionNote: null, noteCount: 0, signals: [signal()],
  ...p,
})

const setting = (p: Partial<FlockAnomalySignalSetting> = {}): FlockAnomalySignalSetting => ({
  signalKey: "MortalitySpike", label: "Mortality spike", metricLabel: "Mortality rate", metricUnit: "deaths per 1,000 birds",
  direction: "up", guardField: "currentDeaths", guardLabel: "Minimum deaths in the day", enabled: true, method: "ratio",
  baselineDays: 14, minBaselineDays: 7, informationThreshold: 1.5, warningThreshold: 2.5, criticalThreshold: 4,
  guardMinimum: 3, baselineFloor: 0.3,
  ...p,
})

describe("severity", () => {
  it("ranks Critical > Warning > Information > nothing", () => {
    expect(severityRank("Critical")).toBe(3)
    expect(severityRank("Warning")).toBe(2)
    expect(severityRank("Information")).toBe(1)
    expect(severityRank(null)).toBe(0)
    expect(severityRank("Nonsense")).toBe(0)
  })

  it("styles each band, and tolerates a missing one", () => {
    expect(severityStyle("Critical").tone).toBe("bad")
    expect(severityStyle("Warning").tone).toBe("warn")
    expect(severityStyle("Information").tone).toBe("info")
    expect(severityStyle(undefined).label).toBe("—")
  })
})

describe("sortAlerts / summarizeAlerts", () => {
  const list = [
    alert({ alertId: 1, status: "Resolved", severity: "Critical" }),
    alert({ alertId: 2, status: "Open", severity: "Warning" }),
    alert({ alertId: 3, status: "Acknowledged", severity: "Critical" }),
    alert({ alertId: 4, status: "Open", severity: "Critical", businessDate: "2026-09-29" }),
    alert({ alertId: 5, status: "Open", severity: "Critical", businessDate: "2026-09-30" }),
    alert({ alertId: 6, status: "Cleared", severity: "Information" }),
  ]

  it("puts open, worst, newest first; resolved last", () => {
    expect(sortAlerts(list).map((a) => a.alertId)).toEqual([5, 4, 2, 3, 6, 1])
  })

  it("counts only Open + Acknowledged as active", () => {
    const s = summarizeAlerts(list)
    expect(s).toMatchObject({ active: 4, open: 3, acknowledged: 1, critical: 3, warning: 1, information: 0, worst: "Critical" })
    expect(isActiveStatus("Cleared")).toBe(false)
    expect(isActiveStatus("Resolved")).toBe(false)
  })

  it("has no worst severity when nothing is active", () => {
    expect(summarizeAlerts([alert({ status: "Resolved" })]).worst).toBeNull()
  })
})

describe("alertHeadline — one flock alert, several signals", () => {
  it("names the active signals worst first", () => {
    const a = alert({
      signals: [
        signal({ signalKey: "FeedConsumptionSpike", label: "Feed consumption spike", severity: "Warning" }),
        signal({ signalKey: "MortalitySpike", label: "Mortality spike", severity: "Critical" }),
        signal({ signalKey: "EggProductionDecline", label: "Egg production decline", severity: "Critical" }),
        signal({ signalKey: "FeedConsumptionDrop", label: "Feed consumption drop", severity: "Information", isActive: false }),
      ],
    })
    expect(alertHeadline(a)).toBe("Mortality spike + Egg production decline + Feed consumption spike")
  })

  it("falls back to the cleared signals when none is active", () => {
    expect(alertHeadline(alert({ status: "Cleared", signals: [signal({ isActive: false })] }))).toBe("Mortality spike")
  })
})

describe("wording", () => {
  it("labels the flock with its house when known", () => {
    expect(flockLabel(alert())).toBe("B2-P4 · House 2")
    expect(flockLabel(alert({ houseName: null }))).toBe("B2-P4")
  })

  it("words every non-alert evaluation outcome", () => {
    expect(evaluationStatusText("InsufficientBaseline")).toBe("Not enough history")
    expect(evaluationStatusText("OnboardingDay")).toBe("First recorded day")
    expect(evaluationStatusText("DuplicateRecords")).toBe("Duplicate records")
    expect(evaluationStatusText("NoData")).toBe("Not recorded")
  })

  it("describes history events", () => {
    const labels = { MortalitySpike: "Mortality spike" }
    expect(eventText({ eventId: 1, alertId: 1, eventType: "SeverityChanged", signalKey: "MortalitySpike", note: null, actor: "system",
      details: { fromSeverity: "Warning", toSeverity: "Critical" }, atUtc: "" }, labels)).toBe("Mortality spike: Warning → Critical")
    expect(eventText({ eventId: 2, alertId: 1, eventType: "Escalated", signalKey: null, note: null, actor: "system",
      details: { acknowledgedSeverity: "Warning", severity: "Critical" }, atUtc: "" }))
      .toBe("Reopened — severity rose above what was acknowledged (Warning → Critical)")
    expect(eventText({ eventId: 3, alertId: 1, eventType: "SignalCleared", signalKey: "MortalitySpike", note: null, actor: "system",
      details: null, atUtc: "" }, labels)).toBe("Signal no longer firing: Mortality spike")
  })

  it("gives each method its unit", () => {
    expect(methodUnit("ratio")).toBe("×")
    expect(methodUnit("pctchange")).toBe("%")
    expect(methodUnit("zscore")).toBe("σ")
  })
})

describe("validateSetting — mirrors the server's rules", () => {
  it("accepts the defaults", () => {
    expect(validateSetting(setting())).toBeNull()
    expect(validateSetting(setting({ informationThreshold: null, guardMinimum: null }))).toBeNull()
  })

  it("rejects bands out of order", () => {
    expect(validateSetting(setting({ criticalThreshold: 2.5 }))).toMatch(/Critical must be higher/)
    expect(validateSetting(setting({ informationThreshold: 3 }))).toMatch(/Information must be/)
  })

  it("rejects impossible baselines", () => {
    expect(validateSetting(setting({ baselineDays: 2 }))).toMatch(/3 to 90/)
    expect(validateSetting(setting({ minBaselineDays: 20 }))).toMatch(/no more than the days used to work out normal/)
    expect(validateSetting(setting({ method: "zscore", minBaselineDays: 2 }))).toMatch(/at least 3 days/)
    expect(validateSetting(setting({ baselineFloor: 0 }))).toMatch(/Treat normal as at least/)
    expect(validateSetting(setting({ warningThreshold: Number.NaN }))).toMatch(/Critical must be higher/)
  })
})

describe("threshold wording — plain words, no 'baseline' or 'standard deviation'", () => {
  it("explains the numbers in the card's own method and direction", () => {
    expect(thresholdHelp({ method: "ratio", direction: "up" })).toMatch(/2\.5 times the flock's normal/)
    expect(thresholdHelp({ method: "pctchange", direction: "down" })).toMatch(/10% lower than normal/)
    expect(thresholdHelp({ method: "zscore", direction: "up" })).toMatch(/clearly unusual/)
  })

  it("works an example from the thresholds as typed", () => {
    expect(thresholdExample(setting()))
      .toBe("For example, a flock that normally loses 2 birds a day: Warning at 5 birds a day, Critical at 8 birds a day.")
    expect(thresholdExample(setting({
      signalKey: "EggProductionDecline", metricLabel: "Laying rate", direction: "down", method: "pctchange",
      warningThreshold: 10, criticalThreshold: 20,
    }))).toBe("For example, a flock normally at 80% laying: Warning at or below 72% laying, Critical at or below 64% laying.")
    expect(thresholdExample(setting({ method: "zscore" }))).toBeNull()
    expect(thresholdExample(setting({ warningThreshold: Number.NaN }))).toBeNull()
  })

  it("names the minimums plainly", () => {
    expect(guardText({ guardField: "currentDeaths", guardLabel: "x" }).label).toMatch(/at least this many birds died/)
    expect(guardText({ guardField: "baselineMean", guardLabel: "x" }).label).toMatch(/normally laying at least/)
    expect(guardText({ guardField: "other", guardLabel: "Server label" }).label).toBe("Server label")
  })

  it("never shows 'baseline' or 'standard deviation' in a validation message", () => {
    const bad = [
      setting({ baselineDays: 2 }), setting({ minBaselineDays: 20 }),
      setting({ method: "zscore", minBaselineDays: 2 }), setting({ baselineFloor: 0 }),
    ].map(validateSetting)
    for (const m of bad) expect(m).not.toMatch(/baseline|standard deviation/i)
  })
})

describe("toAssistantEvidence — future AI explains, never decides", () => {
  it("passes only the stored evidence and explanation, with the instruction not to re-grade", () => {
    const p = toAssistantEvidence(alert())
    expect(p.instruction).toMatch(/Do not add, remove or re-grade/)
    expect(p.alert).toMatchObject({ alertId: 1, flock: "B2-P4 · House 2", severity: "Critical" })
    expect(p.signals[0].explanation[1]).toBe("Compared with normal: today is 4.67 times normal")
    expect(p.signals[0].evidence.signalKey).toBe("MortalitySpike")
  })
})
