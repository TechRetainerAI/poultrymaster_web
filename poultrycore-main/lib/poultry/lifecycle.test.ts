import { describe, expect, it } from "vitest"
import {
  ageAtStartDays, dueLabel, formatAgeDays, lifecycleActionHref, milestoneAgeLabel,
  repeatFromParts, repeatLabel, repeatToParts, sortTasks, taskAgeLabel, taskKey, taskSentence, validatePlan,
} from "./lifecycle"

describe("lifecycleActionHref — links only, never actions", () => {
  it("maps every action type to the ordinary page", () => {
    expect(lifecycleActionHref({ actionType: "FlockDetails", flockId: 7 })).toBe("/flocks/7")
    expect(lifecycleActionHref({ actionType: "FlockTransfer", flockId: 7 })).toBe("/flocks/7")
    expect(lifecycleActionHref({ actionType: "MedicationCampaign", flockId: 7 })).toBe("/health")
    expect(lifecycleActionHref({ actionType: "Production", flockId: 7 })).toBe("/production-records/new?flockId=7")
    expect(lifecycleActionHref({ actionType: "Closeout", flockId: 7 })).toBe("/flock-closeout/7")
  })
  it("has no link when the milestone has no action", () => {
    expect(lifecycleActionHref({ actionType: null, flockId: 7 })).toBeNull()
  })
})

describe("ages", () => {
  it("reads a milestone age", () => {
    expect(milestoneAgeLabel("Week", 16)).toBe("Week 16")
    expect(milestoneAgeLabel("Day", 3)).toBe("Day 3")
  })
  it("formats a flock's age in weeks and days", () => {
    expect(formatAgeDays(107)).toBe("15w 2d")
    expect(formatAgeDays(112)).toBe("16w")
    expect(formatAgeDays(5)).toBe("5d")
    expect(formatAgeDays(-1)).toBe("—")
  })
  it("stores age at start in days (16 weeks = 112)", () => {
    expect(ageAtStartDays(16, 0)).toBe(112)
    expect(ageAtStartDays(2, 3)).toBe(17)
    expect(ageAtStartDays(-1, 0)).toBe(0)
  })
})

describe("dueLabel / taskSentence", () => {
  it("says the prompt's own sentence for an upcoming milestone", () => {
    expect(taskSentence({ batchCode: "B3", flockName: "House A", ageUnit: "Week", ageValue: 16, status: "Upcoming", daysUntilDue: 5 }))
      .toBe("B3 (House A) reaches Week 16 in 5 days")
  })
  it("words each status", () => {
    expect(dueLabel({ status: "Upcoming", daysUntilDue: 5, ageUnit: "Week" })).toBe("in 5 days")
    expect(dueLabel({ status: "Upcoming", daysUntilDue: 1, ageUnit: "Day" })).toBe("in 1 day")
    expect(dueLabel({ status: "Due", daysUntilDue: 0, ageUnit: "Day" })).toBe("Due today")
    expect(dueLabel({ status: "Due", daysUntilDue: -3, ageUnit: "Week" })).toBe("Due this week")
    expect(dueLabel({ status: "Overdue", daysUntilDue: -1, ageUnit: "Day" })).toBe("1 day overdue")
    expect(dueLabel({ status: "Overdue", daysUntilDue: -10, ageUnit: "Week" })).toBe("10 days overdue")
    expect(dueLabel({ status: "Completed", daysUntilDue: 2, ageUnit: "Day" })).toBe("Completed")
  })
})

describe("sortTasks", () => {
  it("puts overdue first, then due, then upcoming, each by date", () => {
    const t = (status: any, dueDate: string, flockName = "F") => ({ status, dueDate, flockName })
    const sorted = sortTasks([t("Upcoming", "2026-10-05"), t("Overdue", "2026-09-30"), t("Due", "2026-10-02"), t("Overdue", "2026-09-20")])
    expect(sorted.map((x) => `${x.status}:${x.dueDate}`)).toEqual([
      "Overdue:2026-09-20", "Overdue:2026-09-30", "Due:2026-10-02", "Upcoming:2026-10-05",
    ])
  })
})

describe("validatePlan", () => {
  const ok = { title: "Review", ageUnit: "Week", ageValue: 6, leadTimeDays: 3 }
  it("accepts a sound plan", () => {
    expect(validatePlan("Layer plan", [ok])).toEqual([])
  })
  it("refuses what the database refuses", () => {
    expect(validatePlan(" ", [ok])).toContain("Give the lifecycle plan a name.")
    expect(validatePlan("P", [])).toContain("Add at least one milestone.")
    expect(validatePlan("P", [{ ...ok, title: "" }])).toContain("Milestone 1: give it a title.")
    expect(validatePlan("P", [{ ...ok, ageValue: -1 }])).toContain("Milestone 1: enter an age between 0 and 5000.")
    expect(validatePlan("P", [{ ...ok, leadTimeDays: 400 }])).toContain("Milestone 1: lead time must be between 0 and 365 days.")
    expect(validatePlan("P", [{ ...ok, repeatEveryDays: 0 }])).toContain("Milestone 1 (Review): repeat every 1 to 3650 days, or not at all.")
    expect(validatePlan("P", [{ ...ok, repeatEveryDays: 91 }])).toEqual([])
  })
})

describe("repeats (387)", () => {
  it("reads a repeat's own age", () => {
    expect(taskAgeLabel({ ageUnit: "Day", ageValue: 203, ageDays: 203, occurrence: 0 })).toBe("Day 203")
    expect(taskAgeLabel({ ageUnit: "Day", ageValue: 203, ageDays: 385, occurrence: 2 })).toBe("Day 385")
    expect(taskAgeLabel({ ageUnit: "Week", ageValue: 42, ageDays: 385, occurrence: 1 })).toBe("Week 55")
    expect(taskAgeLabel({ ageUnit: "Week", ageValue: 16 })).toBe("Week 16")
  })
  it("says the repeat in the task sentence", () => {
    expect(taskSentence({ batchCode: null, flockName: "Layers", ageUnit: "Day", ageValue: 203, ageDays: 294, occurrence: 1, status: "Due", daysUntilDue: 0 }))
      .toBe("Layers is at Day 294 now")
  })
  it("keys a task by flock, milestone and repeat", () => {
    expect(taskKey({ flockId: 3, milestoneId: 9 })).toBe("3-9-0")
    expect(taskKey({ flockId: 3, milestoneId: 9, occurrence: 2 })).toBe("3-9-2")
  })
  it("words and splits a repeat interval", () => {
    expect(repeatLabel(91)).toBe("every 13 weeks")
    expect(repeatLabel(7)).toBe("every week")
    expect(repeatLabel(10)).toBe("every 10 days")
    expect(repeatLabel(null)).toBeNull()
    expect(repeatToParts(91)).toEqual({ value: 13, unit: "Week" })
    expect(repeatToParts(10)).toEqual({ value: 10, unit: "Day" })
    expect(repeatToParts(null)).toBeNull()
    expect(repeatFromParts(13, "Week")).toBe(91)
    expect(repeatFromParts(10, "Day")).toBe(10)
  })
})
