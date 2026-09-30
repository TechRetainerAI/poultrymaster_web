import { describe, expect, it } from "vitest"
import type { ActivityCheckItem, ActivityCheckResult, ActivityCompletenessReport, MissingProductionEntry } from "@/lib/api/activity-checks"
import {
  MAX_PREFILL_FLOCKS,
  PRODUCTION_CHECK_KEY,
  completeMissingProductionHref,
  completenessHeadline,
  findCheck,
  flocksNeedingEntry,
  formatDaysOutstanding,
  formatShortDate,
  itemActionHref,
  itemActionLabel,
  missingDateHref,
  flocksWithEarlierGaps,
  earlierGapActionHref,
  safeReturnPath,
  farmCompletenessHref,
  batchEntryHref,
  flockStepThroughHref,
  groupMissingByDate,
  formatWeekdayDate,
  daysAgoLabel,
  parseMissingProductionPrefill,
  severityStyle,
  shiftBusinessDate,
  toBusinessDate,
} from "./completeness"

function item(p: Partial<ActivityCheckItem> = {}): ActivityCheckItem {
  return {
    subjectType: "flock",
    subjectId: 1,
    label: "B2 - Pen 7",
    groupLabel: "B2",
    locationLabel: "Pen 7",
    state: "Missing",
    severity: "Warning",
    lastCompletedDate: "2026-09-19T00:00:00",
    daysOutstanding: 1,
    relatedRecordType: null,
    relatedRecordId: null,
    relatedRecordStatus: null,
    ...p,
  }
}

function check(items: ActivityCheckItem[], p: Partial<ActivityCheckResult> = {}): ActivityCheckResult {
  return {
    key: PRODUCTION_CHECK_KEY,
    module: "poultry",
    title: "Daily production",
    requiredPermission: "poultry.production-records.view",
    status: items.length ? "Incomplete" : "Complete",
    severity: items.length ? "Warning" : null,
    severityReason: null,
    expectedCount: 20,
    completedCount: 20 - items.length,
    outstandingCount: items.length,
    counters: {},
    items,
    ...p,
  }
}

function params(query: string) {
  return new URLSearchParams(query)
}

describe("toBusinessDate / formatShortDate", () => {
  it("trims a server date-time to the business date", () => {
    expect(toBusinessDate("2026-09-19T00:00:00")).toBe("2026-09-19")
    expect(toBusinessDate("2026-09-19")).toBe("2026-09-19")
  })

  it("rejects anything that is not a date", () => {
    expect(toBusinessDate("")).toBeNull()
    expect(toBusinessDate(null)).toBeNull()
    expect(toBusinessDate("19/09/2026")).toBeNull()
    expect(toBusinessDate("2026-13-01")).toBeNull()
  })

  it("formats without going through the browser's timezone", () => {
    // Jan 1 is the classic victim: new Date("2026-01-01") in a UTC-5 browser
    // renders as Dec 31.
    expect(formatShortDate("2026-01-01")).toBe("Jan 1")
    expect(formatShortDate("2026-09-19T00:00:00")).toBe("Sep 19")
    expect(formatShortDate(null)).toBe("—")
  })
})

describe("formatDaysOutstanding / completenessHeadline", () => {
  it("pluralises", () => {
    expect(formatDaysOutstanding(1)).toBe("1 day")
    expect(formatDaysOutstanding(3)).toBe("3 days")
    expect(formatDaysOutstanding(0)).toBe("0 days")
  })

  it("reads as the spec's headline", () => {
    expect(completenessHeadline({ completedCount: 17, expectedCount: 20 })).toBe("17 / 20 recorded")
    expect(completenessHeadline({ completedCount: 20, expectedCount: 20 })).toBe("20 / 20 recorded")
  })
})

describe("findCheck", () => {
  it("finds by key and tolerates a missing report", () => {
    const report = { checks: [check([])] } as unknown as ActivityCompletenessReport
    expect(findCheck(report, PRODUCTION_CHECK_KEY)?.title).toBe("Daily production")
    expect(findCheck(report, "water.something")).toBeNull()
    expect(findCheck(null, PRODUCTION_CHECK_KEY)).toBeNull()
  })
})

describe("completeMissingProductionHref", () => {
  it("links Batch Production Entry to exactly the missing flocks on the business date", () => {
    const c = check([item({ subjectId: 7 }), item({ subjectId: 8 }), item({ subjectId: 12 })])
    const href = completeMissingProductionHref("2026-09-20", c)!
    expect(href.startsWith("/batch-production-records/new?")).toBe(true)
    const q = new URLSearchParams(href.split("?")[1])
    expect(q.get("date")).toBe("2026-09-20")
    expect(q.get("flockIds")).toBe("7,8,12")
    expect(q.get("source")).toBe("missing-production")
  })

  it("leaves out flocks already sitting in an unposted batch", () => {
    const c = check([
      item({ subjectId: 7 }),
      item({ subjectId: 8, state: "AwaitingPosting", relatedRecordId: 44, relatedRecordStatus: "PendingAllocation" }),
    ])
    expect(flocksNeedingEntry(c).map((i) => i.subjectId)).toEqual([7])
    const q = new URLSearchParams(completeMissingProductionHref("2026-09-20", c)!.split("?")[1])
    expect(q.get("flockIds")).toBe("7")
  })

  it("returns null when there is nothing to enter", () => {
    expect(completeMissingProductionHref("2026-09-20", check([]))).toBeNull()
    expect(completeMissingProductionHref("2026-09-20", null)).toBeNull()
    const onlyPending = check([item({ state: "AwaitingPosting", relatedRecordId: 4 })])
    expect(completeMissingProductionHref("2026-09-20", onlyPending)).toBeNull()
  })

  it("refuses to build a link without a valid business date", () => {
    expect(completeMissingProductionHref("", check([item()]))).toBeNull()
  })
})

describe("parseMissingProductionPrefill", () => {
  it("round-trips what the dashboard link wrote", () => {
    const c = check([item({ subjectId: 7 }), item({ subjectId: 8 })])
    const href = completeMissingProductionHref("2026-09-20", c)!
    expect(parseMissingProductionPrefill(params(href.split("?")[1]))).toEqual({
      date: "2026-09-20",
      flockIds: [7, 8],
    })
  })

  it("drops junk, zero, negatives and duplicates", () => {
    expect(parseMissingProductionPrefill(params("date=2026-09-20&flockIds=7,,abc,0,-3,7,8.5,9"))).toEqual({
      date: "2026-09-20",
      flockIds: [7, 9],
    })
  })

  it("is null without a valid date, so the form never guesses the day", () => {
    expect(parseMissingProductionPrefill(params("flockIds=1,2"))).toBeNull()
    expect(parseMissingProductionPrefill(params("date=yesterday&flockIds=1"))).toBeNull()
    expect(parseMissingProductionPrefill(params(""))).toBeNull()
    expect(parseMissingProductionPrefill(null)).toBeNull()
  })

  it("caps the number of flocks", () => {
    const many = Array.from({ length: MAX_PREFILL_FLOCKS + 50 }, (_, i) => i + 1).join(",")
    expect(parseMissingProductionPrefill(params(`date=2026-09-20&flockIds=${many}`))!.flockIds).toHaveLength(
      MAX_PREFILL_FLOCKS,
    )
  })
})

describe("itemActionHref / itemActionLabel", () => {
  it("records a missing flock individually on the business date", () => {
    const i = item({ subjectId: 7 })
    expect(itemActionHref(i, "2026-09-20")).toBe("/production-records/new?flockId=7&date=2026-09-20")
    expect(itemActionLabel(i)).toBe("Record")
  })

  it("sends a flock in an unposted batch to that batch rather than a second entry", () => {
    const pending = item({ state: "AwaitingPosting", relatedRecordId: 44, relatedRecordStatus: "PendingAllocation" })
    expect(itemActionHref(pending, "2026-09-20")).toBe("/batch-production-records/44/allocate")
    expect(itemActionLabel(pending)).toBe("Post batch")

    const draft = item({ state: "AwaitingPosting", relatedRecordId: 45, relatedRecordStatus: "Draft" })
    expect(itemActionHref(draft, "2026-09-20")).toBe("/batch-production-records/45/edit")
    expect(itemActionLabel(draft)).toBe("Finish batch")
  })
})

describe("severityStyle", () => {
  it("has a style for every level, and treats null as complete", () => {
    expect(severityStyle("Critical").label).toBe("Critical")
    expect(severityStyle("Warning").label).toBe("Warning")
    expect(severityStyle("Information").label).toBe("Info")
    expect(severityStyle(null).label).toBe("Complete")
  })
})

describe("shiftBusinessDate", () => {
  it("steps across month, year and leap-day boundaries", () => {
    expect(shiftBusinessDate("2026-03-01", -1)).toBe("2026-02-28")
    expect(shiftBusinessDate("2028-03-01", -1)).toBe("2028-02-29")
    expect(shiftBusinessDate("2026-12-31", 1)).toBe("2027-01-01")
    expect(shiftBusinessDate("2026-09-28", 0)).toBe("2026-09-28")
  })

  it("is null for a non-date", () => {
    expect(shiftBusinessDate("", 1)).toBeNull()
  })
})

describe("missingDateHref (row dropdown)", () => {
  it("records a missing day individually on THAT date", () => {
    expect(missingDateHref(7, "2026-09-12T00:00:00")).toBe("/production-records/new?flockId=7&date=2026-09-12")
  })

  it("sends a day already in an unposted batch to that batch", () => {
    expect(missingDateHref(7, "2026-09-12", 44, "PendingAllocation")).toBe("/batch-production-records/44/allocate")
    expect(missingDateHref(7, "2026-09-12", 45, "Draft")).toBe("/batch-production-records/45/edit")
  })
})

describe("formatWeekdayDate / daysAgoLabel", () => {
  it("names the weekday from the calendar date", () => {
    expect(formatWeekdayDate("2026-09-12")).toBe("Sat, Sep 12")
    expect(formatWeekdayDate("2026-01-01T00:00:00")).toBe("Thu, Jan 1")
    expect(formatWeekdayDate("")).toBe("—")
  })

  it("counts days between business dates, across months", () => {
    expect(daysAgoLabel("2026-09-28", "2026-09-28")).toBe("today")
    expect(daysAgoLabel("2026-09-27", "2026-09-28")).toBe("yesterday")
    expect(daysAgoLabel("2026-08-30", "2026-09-02")).toBe("3 days ago")
  })
})

describe("step-through for a flock behind by several days", () => {
  it("opens the normal form in catch-up mode", () => {
    const i = item({ subjectId: 7, daysOutstanding: 5 })
    expect(itemActionHref(i, "2026-09-20")).toBe("/production-records/new?flockId=7&catchUp=1&asOf=2026-09-20")
    expect(itemActionLabel(i)).toBe("Record 5 days")
    expect(flockStepThroughHref(7, "2026-09-20")).toBe("/production-records/new?flockId=7&catchUp=1&asOf=2026-09-20")
  })

  it("keeps the single form for one missing day", () => {
    const i = item({ subjectId: 7, daysOutstanding: 1 })
    expect(itemActionHref(i, "2026-09-20")).toBe("/production-records/new?flockId=7&date=2026-09-20")
    expect(itemActionLabel(i)).toBe("Record")
  })
})

describe("batchEntryHref", () => {
  it("opens Batch Production Entry for any date with those flocks", () => {
    const q = new URLSearchParams(batchEntryHref("2026-09-12", [3, 4, 3])!.split("?")[1])
    expect(q.get("date")).toBe("2026-09-12")
    expect(q.get("flockIds")).toBe("3,4")
  })

  it("is null with no flocks or no date", () => {
    expect(batchEntryHref("2026-09-12", [])).toBeNull()
    expect(batchEntryHref("", [3])).toBeNull()
  })
})

describe("groupMissingByDate", () => {
  const e = (date: string, flockId: number, pending: number | null = null): MissingProductionEntry => ({
    date: `${date}T00:00:00`, flockId, flockName: `F${flockId}`, batchName: null, houseName: null,
    pendingBatchRecordId: pending, pendingBatchStatus: pending ? "PendingAllocation" : null,
  })

  it("groups by date newest first and separates flocks already in a batch", () => {
    const groups = groupMissingByDate([
      e("2026-09-12", 1), e("2026-09-12", 2), e("2026-09-12", 3, 44), e("2026-09-12", 4, 44),
      e("2026-09-11", 1),
    ])
    expect(groups.map((g) => g.date)).toEqual(["2026-09-12", "2026-09-11"])
    expect(groups[0].missing.map((x) => x.flockId)).toEqual([1, 2])
    expect(groups[0].pendingBatches).toEqual([
      expect.objectContaining({ id: 44, flocks: [expect.objectContaining({ flockId: 3 }), expect.objectContaining({ flockId: 4 })] }),
    ])
    expect(groups[1].missing).toHaveLength(1)
  })
})

describe("safeReturnPath", () => {
  it("accepts a same-site path", () => {
    expect(safeReturnPath("/poultry-farm-completeness?date=2026-09-29")).toBe("/poultry-farm-completeness?date=2026-09-29")
  })

  it("refuses anything that could leave the site", () => {
    for (const bad of ["//evil.com", "https://evil.com", "/\\evil.com", "evil", "", null, "/ok\\..\\x", "/a\nb"]) {
      expect(safeReturnPath(bad as string | null)).toBeNull()
    }
  })

  it("builds the Farm Completeness link for a date", () => {
    expect(farmCompletenessHref("2026-09-29")).toBe("/poultry-farm-completeness?date=2026-09-29")
    expect(farmCompletenessHref(null)).toBe("/poultry-farm-completeness")
  })
})

describe("flocksWithEarlierGaps (By flock when today is complete)", () => {
  const e = (date: string, flockId: number, name = `F${flockId}`): MissingProductionEntry => ({
    date: `${date}T00:00:00`, flockId, flockName: name, batchName: "B", houseName: "Pen",
    pendingBatchRecordId: null, pendingBatchStatus: null,
  })

  it("lists flocks with earlier gaps, most days first, skipping ones already shown", () => {
    const list = flocksWithEarlierGaps(
      [e("2026-09-27", 1), e("2026-09-26", 1), e("2026-09-25", 1), e("2026-09-27", 2), e("2026-09-28", 3)],
      [3],
    )
    expect(list.map((f) => [f.flockId, f.missingDays, f.latestMissing])).toEqual([
      [1, 3, "2026-09-27"],
      [2, 1, "2026-09-27"],
    ])
  })

  it("steps through several days, or records the single one", () => {
    const [many, one] = flocksWithEarlierGaps([e("2026-09-27", 1), e("2026-09-26", 1), e("2026-09-20", 2)], [])
    expect(earlierGapActionHref(many, "2026-09-29")).toBe("/production-records/new?flockId=1&catchUp=1&asOf=2026-09-29")
    expect(earlierGapActionHref(one, "2026-09-29")).toBe("/production-records/new?flockId=2&date=2026-09-20")
  })
})
