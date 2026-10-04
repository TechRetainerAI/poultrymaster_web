// Flock anomaly alerts (migration 338) — types and pure display helpers.
//
// Nothing here decides whether an anomaly happened: the server evaluates every
// signal deterministically and sends the explanation lines it proved. These
// helpers only word, colour, sort and count what came back.

export type Severity = "Information" | "Warning" | "Critical"
export type AlertStatus = "Open" | "Acknowledged" | "Resolved" | "Cleared"
export type EvaluationStatus =
  | "Fired" | "Normal" | "InsufficientBaseline" | "BelowMinimum" | "NoData" | "DuplicateRecords" | "OnboardingDay"
export type BaselineMethod = "ratio" | "pctchange" | "zscore"

/** Structured evidence (schema poultry.flock-anomaly.v1) — the only thing an assistant may explain from. */
export interface SignalEvidence {
  schema: string
  flockId: number
  businessDate: string
  signalKey: string
  signalLabel: string
  status: EvaluationStatus
  severity: Severity | null
  metric: { key: string; label: string; unit: string; direction: "up" | "down" }
  current: { value: number | null; birds: number | null; deaths: number; eggs: number; feedKg: number; recordCount: number }
  baseline: {
    method: BaselineMethod; days: number; minDays: number; points: number; from: string; to: string
    mean: number | null; stdDev: number | null; floor: number
    avgDeaths: number | null; avgEggs: number | null; avgFeedKg: number | null; avgBirds: number | null
  }
  observed: number | null
  changePct: number | null
  thresholds: { information: number | null; warning: number; critical: number }
  guard: { field: string; minimum: number } | null
  exclusions: { openingHistoryRead: boolean; openingEffectiveDate: string | null; duplicateDaysSkipped: number; onboardingDaysSkipped: number }
}

export interface AlertSignal {
  signalKey: string
  label: string
  isActive: boolean
  severity: Severity
  observed: number | null
  explanation: string[]
  evidence: SignalEvidence
  firstDetectedAtUtc: string
  clearedAtUtc: string | null
}

export interface FlockAlert {
  alertId: number
  flockId: number
  flockName: string
  houseName: string | null
  businessDate: string
  status: AlertStatus
  severity: Severity
  severityRank: number
  peakSeverity: Severity
  activeSignalCount: number
  consecutiveDays: number
  firstDetectedAtUtc: string
  lastEvaluatedAtUtc: string
  acknowledgedBy: string | null
  acknowledgedAtUtc: string | null
  resolvedBy: string | null
  resolvedAtUtc: string | null
  resolutionNote: string | null
  noteCount: number
  signals: AlertSignal[]
}

export interface FlockAlertEvent {
  eventId: number
  alertId: number
  eventType: string
  signalKey: string | null
  note: string | null
  actor: string | null
  details: Record<string, unknown> | null
  atUtc: string
}

export interface FlockSignalEvaluation {
  flockId: number
  flockName: string
  houseName: string | null
  businessDate: string
  signalKey: string
  signalLabel: string
  metricKey: string
  metricLabel: string
  metricUnit: string
  direction: "up" | "down"
  status: EvaluationStatus
  severity: Severity | null
  severityRank: number
  currentValue: number | null
  baselineMean: number | null
  baselineStdDev: number | null
  baselinePoints: number
  baselineFrom: string
  baselineTo: string
  method: BaselineMethod
  observed: number | null
  changePct: number | null
  informationThreshold: number | null
  warningThreshold: number
  criticalThreshold: number
  evidence: SignalEvidence
  explanation: string[]
}

export interface FlockAnomalySignalSetting {
  signalKey: string
  label: string
  metricLabel: string
  metricUnit: string
  direction: "up" | "down"
  guardField: string | null
  guardLabel: string | null
  enabled: boolean
  method: BaselineMethod
  baselineDays: number
  minBaselineDays: number
  informationThreshold: number | null
  warningThreshold: number
  criticalThreshold: number
  guardMinimum: number | null
  baselineFloor: number
  isCustomised?: boolean
  updatedBy?: string | null
  updatedAtUtc?: string | null
}

const SEVERITY_RANK: Record<string, number> = { Critical: 3, Warning: 2, Information: 1 }

export function severityRank(s: string | null | undefined): number {
  return (s && SEVERITY_RANK[s]) || 0
}

export function severityStyle(s: Severity | string | null | undefined) {
  switch (s) {
    case "Critical":
      return { label: "Critical", badge: "border-rose-200 bg-rose-50 text-rose-700", border: "border-l-rose-500", tone: "bad" as const }
    case "Warning":
      return { label: "Warning", badge: "border-amber-200 bg-amber-50 text-amber-800", border: "border-l-amber-500", tone: "warn" as const }
    case "Information":
      return { label: "Information", badge: "border-sky-200 bg-sky-50 text-sky-700", border: "border-l-sky-500", tone: "info" as const }
    default:
      return { label: "—", badge: "border-slate-200 bg-slate-50 text-slate-600", border: "border-l-slate-300", tone: "none" as const }
  }
}

export function statusStyle(s: AlertStatus | string) {
  switch (s) {
    case "Open": return { label: "Open", badge: "border-rose-200 bg-white text-rose-700" }
    case "Acknowledged": return { label: "Acknowledged", badge: "border-amber-200 bg-white text-amber-800" }
    case "Resolved": return { label: "Resolved", badge: "border-emerald-200 bg-white text-emerald-700" }
    case "Cleared": return { label: "Cleared by data", badge: "border-slate-200 bg-white text-slate-600" }
    default: return { label: s, badge: "border-slate-200 bg-white text-slate-600" }
  }
}

/** Short wording for the non-alert outcomes in the evaluation view. */
export function evaluationStatusText(s: EvaluationStatus | string): string {
  switch (s) {
    case "Fired": return "Alert"
    case "Normal": return "Normal"
    case "InsufficientBaseline": return "Not enough history"
    case "BelowMinimum": return "Below minimum"
    case "NoData": return "Not recorded"
    case "DuplicateRecords": return "Duplicate records"
    case "OnboardingDay": return "First recorded day"
    default: return s
  }
}

export function isActiveStatus(s: AlertStatus | string): boolean {
  return s === "Open" || s === "Acknowledged"
}

/** Open before Acknowledged before Cleared before Resolved; then worst first; then newest. */
export function sortAlerts(alerts: FlockAlert[]): FlockAlert[] {
  const order: Record<string, number> = { Open: 0, Acknowledged: 1, Cleared: 2, Resolved: 3 }
  return [...alerts].sort((a, b) =>
    (order[a.status] ?? 9) - (order[b.status] ?? 9)
    || severityRank(b.severity) - severityRank(a.severity)
    || (b.businessDate ?? "").localeCompare(a.businessDate ?? "")
    || a.flockName.localeCompare(b.flockName))
}

export function summarizeAlerts(alerts: FlockAlert[]) {
  const active = alerts.filter((a) => isActiveStatus(a.status))
  return {
    active: active.length,
    open: alerts.filter((a) => a.status === "Open").length,
    acknowledged: alerts.filter((a) => a.status === "Acknowledged").length,
    critical: active.filter((a) => a.severity === "Critical").length,
    warning: active.filter((a) => a.severity === "Warning").length,
    information: active.filter((a) => a.severity === "Information").length,
    worst: active.reduce<Severity | null>((w, a) => (severityRank(a.severity) > severityRank(w) ? a.severity : w), null),
  }
}

/** "Mortality spike + Egg production decline" — the signals still firing, worst first. */
export function alertHeadline(alert: FlockAlert): string {
  const active = alert.signals.filter((s) => s.isActive)
  const shown = (active.length ? active : alert.signals)
    .slice()
    .sort((a, b) => severityRank(b.severity) - severityRank(a.severity))
    .map((s) => s.label)
  return shown.join(" + ") || "Anomaly"
}

export function flockLabel(a: { flockName: string; houseName: string | null }): string {
  return a.houseName ? `${a.flockName} · ${a.houseName}` : a.flockName
}

// Farmer-facing wording: "normal" stands in for "baseline" everywhere a user reads it.
export const METHOD_OPTIONS: { value: BaselineMethod; label: string; unit: string; hint: string }[] = [
  { value: "ratio", label: "Times normal (×)", unit: "×",
    hint: "Compares today with the flock's normal as “so many times”. 2.5 means today is 2.5 times normal." },
  { value: "pctchange", label: "Percent above or below normal (%)", unit: "%",
    hint: "Compares today with the flock's normal in percent. 10 means today is 10% higher or lower than normal." },
  { value: "zscore", label: "How unusual for this flock (score)", unit: "σ",
    hint: "Allows for flocks whose figures naturally jump around a lot. 2 = clearly unusual, 3 = very unusual. Most farms don't need this." },
]

export function methodUnit(m: BaselineMethod | string): string {
  return METHOD_OPTIONS.find((o) => o.value === m)?.unit ?? ""
}

/** Help line under the Information / Warning / Critical boxes, in the card's own method and direction. */
export function thresholdHelp(s: Pick<FlockAnomalySignalSetting, "method" | "direction">): string {
  if (s.method === "ratio")
    return s.direction === "up"
      ? "Times normal. 2.5 = today is 2.5 times the flock's normal."
      : "Times normal. 2 = today is half of the flock's normal."
  if (s.method === "pctchange")
    return `Percent ${s.direction === "up" ? "above" : "below"} normal. 10 = today is 10% ${s.direction === "up" ? "higher" : "lower"} than normal.`
  return "How unusual today is for this flock. 2 = clearly unusual, 3 = very unusual."
}

/** A realistic "normal" for each metric, used only to build the example sentence. */
const EXAMPLE_NORMAL: Record<string, { value: number; intro: string; say: (v: number) => string }> = {
  "Mortality rate": { value: 2, intro: "a flock that normally loses", say: (v) => `${fmtExample(v)} bird${v === 1 ? "" : "s"} a day` },
  "Laying rate": { value: 80, intro: "a flock normally at", say: (v) => `${fmtExample(v)}% laying` },
  "Feed per bird": { value: 115, intro: "a flock normally eating", say: (v) => `${fmtExample(v)} g per bird a day` },
}

function fmtExample(v: number): string {
  return Number(v.toFixed(1)).toLocaleString()
}

/**
 * "For example: a flock that normally loses 2 birds a day → Warning at 5, Critical at 8."
 * Worked from the thresholds as typed, so the farmer sees what a number means before saving.
 */
export function thresholdExample(s: FlockAnomalySignalSetting): string | null {
  const ex = EXAMPLE_NORMAL[s.metricLabel]
  const w = s.warningThreshold, c = s.criticalThreshold
  if (!ex || !Number.isFinite(w) || !Number.isFinite(c) || w <= 0 || c <= 0) return null
  if (s.method === "zscore") return null
  const at = (t: number) => {
    if (s.method === "ratio") return s.direction === "up" ? ex.value * t : ex.value / t
    return s.direction === "up" ? ex.value * (1 + t / 100) : ex.value * (1 - t / 100)
  }
  const word = s.direction === "up" ? "at" : "at or below"
  return `For example, ${ex.intro} ${ex.say(ex.value)}: Warning ${word} ${ex.say(at(w))}, Critical ${word} ${ex.say(at(c))}.`
}

/** Plain label + help for the per-signal minimum (the "guard"); falls back to the server's label. */
export function guardText(s: Pick<FlockAnomalySignalSetting, "guardField" | "guardLabel">): { label: string; help: string } {
  switch (s.guardField) {
    case "currentDeaths":
      return { label: "Only alert if at least this many birds died",
        help: "Stops tiny changes looking like a spike, e.g. 0 deaths one day and 1 the next." }
    case "baselineMean":
      return { label: "Only check flocks normally laying at least (%)",
        help: "Skips flocks not really in lay, such as young pullets or spent hens." }
    default:
      return { label: s.guardLabel ?? "Minimum", help: "" }
  }
}

/** Mirrors sppoultryanomalysettings_set so the form can say what is wrong before saving. */
export function validateSetting(s: FlockAnomalySignalSetting): string | null {
  const n = (v: unknown) => typeof v === "number" && Number.isFinite(v)
  if (!n(s.baselineDays) || s.baselineDays < 3 || s.baselineDays > 90) return "“Work out normal from the last” must be 3 to 90 days."
  if (!n(s.minBaselineDays) || s.minBaselineDays < 1 || s.minBaselineDays > s.baselineDays)
    return "“Days of records needed first” must be at least 1 and no more than the days used to work out normal."
  if (s.method === "zscore" && s.minBaselineDays < 3) return "“How unusual for this flock” needs at least 3 days of records first."
  if (!n(s.warningThreshold) || !n(s.criticalThreshold) || s.warningThreshold <= 0 || s.criticalThreshold <= s.warningThreshold)
    return "Critical must be higher than Warning, and both above zero."
  if (s.informationThreshold != null && (!n(s.informationThreshold) || s.informationThreshold <= 0 || s.informationThreshold >= s.warningThreshold))
    return "Information must be above zero and lower than Warning (or left empty)."
  if (s.guardMinimum != null && (!n(s.guardMinimum) || s.guardMinimum < 0)) return "The minimum cannot be negative."
  if (!n(s.baselineFloor) || s.baselineFloor <= 0) return "“Treat normal as at least” must be above zero."
  return null
}

const EVENT_TEXT: Record<string, string> = {
  Detected: "Detected",
  SignalAdded: "Another signal fired",
  SignalReactivated: "Signal fired again",
  SeverityChanged: "Severity changed",
  EvidenceUpdated: "Figures updated",
  SignalCleared: "Signal no longer firing",
  AutoCleared: "Cleared — the recorded figures no longer show it",
  Reactivated: "Reopened — it fired again",
  Escalated: "Reopened — severity rose above what was acknowledged",
  Acknowledged: "Acknowledged",
  NoteAdded: "Note",
  Resolved: "Resolved",
}

export function eventText(e: FlockAlertEvent, signalLabels: Record<string, string> = {}): string {
  const base = EVENT_TEXT[e.eventType] ?? e.eventType
  const sig = e.signalKey ? signalLabels[e.signalKey] ?? e.signalKey : null
  const d = e.details ?? {}
  if (e.eventType === "SeverityChanged" && d.fromSeverity && d.toSeverity)
    return `${sig ?? "Signal"}: ${String(d.fromSeverity)} → ${String(d.toSeverity)}`
  if (e.eventType === "Escalated" && d.acknowledgedSeverity && d.severity)
    return `${base} (${String(d.acknowledgedSeverity)} → ${String(d.severity)})`
  if (e.eventType === "Detected" && d.severity) return `${base} — ${String(d.severity)}`
  return sig ? `${base}: ${sig}` : base
}

/**
 * The payload a future assistant receives to EXPLAIN an alert: the stored,
 * deterministic evidence only. It never decides whether an anomaly occurred.
 */
export function toAssistantEvidence(alert: FlockAlert) {
  return {
    schema: "poultry.flock-alert.v1",
    instruction: "Explain these deterministic signals to a farmer. Do not add, remove or re-grade any signal.",
    alert: {
      alertId: alert.alertId,
      flock: flockLabel(alert),
      businessDate: alert.businessDate,
      status: alert.status,
      severity: alert.severity,
      consecutiveDays: alert.consecutiveDays,
    },
    signals: alert.signals.map((s) => ({ isActive: s.isActive, explanation: s.explanation, evidence: s.evidence })),
  }
}

/** YYYY-MM-DD from an API date ("2026-09-30T00:00:00"). */
export function dayOf(value: string | null | undefined): string {
  return value ? value.slice(0, 10) : ""
}
