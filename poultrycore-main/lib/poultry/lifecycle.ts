/**
 * Flock Lifecycle Assistant (migration 347) -- presentation rules.
 *
 * The SCHEDULE is worked out in the database (fnpoultrylifecycle_schedule);
 * nothing here recomputes a due date or a status. This file only says how a
 * task reads and where its action link goes, so the Tools page and Business
 * Office My Tasks word things the same way.
 *
 * VisibilityCore ships no milestones. Nothing in this file names a week, a
 * treatment or a breed rule.
 */

import type { LifecycleActionType, LifecycleAgeUnit, LifecycleStatus, LifecycleTask } from "@/lib/api/poultry-lifecycle"

export const AGE_UNITS: LifecycleAgeUnit[] = ["Week", "Day"]

/** Suggestions for the free-text category field -- a farm may type its own. */
export const CATEGORY_SUGGESTIONS = ["Housing", "Health", "Feeding", "Lighting", "Production", "Review", "Other"]

export const ACTION_TYPES: { value: LifecycleActionType; label: string; hint: string }[] = [
  { value: "FlockDetails", label: "Flock details", hint: "Opens the flock" },
  { value: "FlockTransfer", label: "Move house", hint: "Opens the flock, where its house is changed" },
  { value: "MedicationCampaign", label: "Treatment records", hint: "Opens Health records to record a treatment" },
  { value: "Production", label: "Production record", hint: "Opens a new production record for the flock" },
  { value: "Closeout", label: "Flock closeout", hint: "Opens the flock's lifetime page, where it is closed" },
]

/**
 * Where a task's action link goes. A LINK, never an action: following it opens
 * the ordinary page, where a person does the work or decides not to.
 */
export function lifecycleActionHref(task: Pick<LifecycleTask, "actionType" | "flockId">): string | null {
  switch (task.actionType) {
    case "FlockDetails":
    case "FlockTransfer":
      return `/flocks/${task.flockId}`
    case "MedicationCampaign":
      return "/health"
    case "Production":
      return `/production-records/new?flockId=${task.flockId}`
    case "Closeout":
      return `/flock-closeout/${task.flockId}`
    default:
      return null
  }
}

export function actionLabel(type: LifecycleActionType | null | undefined): string | null {
  return ACTION_TYPES.find((a) => a.value === type)?.label ?? null
}

/** "Week 16" / "Day 3" -- how a milestone's age reads. */
export function milestoneAgeLabel(unit: LifecycleAgeUnit | string, value: number): string {
  return `${unit === "Day" ? "Day" : "Week"} ${value}`
}

/** A flock's age in days as weeks + days: 107 -> "15w 2d", 112 -> "16w". */
export function formatAgeDays(days: number): string {
  if (!Number.isFinite(days) || days < 0) return "—"
  const w = Math.floor(days / 7)
  const d = days % 7
  if (w === 0) return `${d}d`
  return d === 0 ? `${w}w` : `${w}w ${d}d`
}

/** Plain-words timing: "in 5 days", "today", "3 days overdue". */
export function dueLabel(task: Pick<LifecycleTask, "status" | "daysUntilDue" | "ageUnit">): string {
  const n = task.daysUntilDue
  if (task.status === "Completed") return "Completed"
  if (task.status === "Skipped") return "Skipped"
  if (task.status === "Due") {
    if (n === 0) return "Due today"
    return task.ageUnit === "Week" ? "Due this week" : "Due today"
  }
  if (n > 0) return n === 1 ? "in 1 day" : `in ${n} days`
  const late = -n
  return late === 1 ? "1 day overdue" : `${late} days overdue`
}

/** "B3 reaches Week 16 in 5 days" -- the sentence the prompt asked for. */
export function taskSentence(task: Pick<LifecycleTask, "batchCode" | "flockName" | "ageUnit" | "ageValue" | "status" | "daysUntilDue">): string {
  const who = task.batchCode ? `${task.batchCode} (${task.flockName})` : task.flockName
  const age = milestoneAgeLabel(task.ageUnit, task.ageValue)
  if (task.status === "Upcoming") {
    return `${who} reaches ${age} ${task.daysUntilDue === 1 ? "tomorrow" : `in ${task.daysUntilDue} days`}`
  }
  if (task.status === "Due") return `${who} is at ${age} now`
  if (task.status === "Overdue") return `${who} passed ${age}`
  return `${who} — ${age}`
}

export const STATUS_TONE: Record<LifecycleStatus, string> = {
  Overdue: "bg-rose-100 text-rose-800 border-rose-300",
  Due: "bg-amber-100 text-amber-800 border-amber-300",
  Upcoming: "bg-blue-100 text-blue-800 border-blue-300",
  Scheduled: "bg-slate-100 text-slate-600 border-slate-300",
  Completed: "bg-emerald-100 text-emerald-800 border-emerald-300",
  Skipped: "bg-slate-100 text-slate-500 border-slate-300",
}

const STATUS_ORDER: Record<string, number> = { Overdue: 0, Due: 1, Upcoming: 2, Scheduled: 3, Completed: 4, Skipped: 5 }

/** Most urgent first, then by due date. */
export function sortTasks<T extends Pick<LifecycleTask, "status" | "dueDate" | "flockName">>(tasks: T[]): T[] {
  return [...tasks].sort((a, b) =>
    (STATUS_ORDER[a.status] ?? 9) - (STATUS_ORDER[b.status] ?? 9)
    || a.dueDate.localeCompare(b.dueDate)
    || a.flockName.localeCompare(b.flockName))
}

/** Age at start entered as weeks + days, stored as days. */
export function ageAtStartDays(weeks: number, days: number): number {
  return Math.max(0, Math.floor(weeks || 0)) * 7 + Math.max(0, Math.floor(days || 0))
}

export interface MilestoneDraftCheck { title: string; ageUnit: string; ageValue: number; leadTimeDays: number }

/** The database's refusals, in its words, so most mistakes are caught before saving. */
export function validatePlan(name: string, milestones: MilestoneDraftCheck[]): string[] {
  const errs: string[] = []
  if (!name.trim()) errs.push("Give the lifecycle plan a name.")
  if (milestones.length === 0) errs.push("Add at least one milestone.")
  milestones.forEach((m, i) => {
    const n = i + 1
    if (!m.title.trim()) errs.push(`Milestone ${n}: give it a title.`)
    if (m.ageUnit !== "Day" && m.ageUnit !== "Week") errs.push(`Milestone ${n}: age must be in days or weeks.`)
    if (!Number.isInteger(m.ageValue) || m.ageValue < 0 || m.ageValue > 5000) errs.push(`Milestone ${n}: enter an age between 0 and 5000.`)
    if (!Number.isInteger(m.leadTimeDays) || m.leadTimeDays < 0 || m.leadTimeDays > 365) errs.push(`Milestone ${n}: lead time must be between 0 and 365 days.`)
  })
  return errs
}
