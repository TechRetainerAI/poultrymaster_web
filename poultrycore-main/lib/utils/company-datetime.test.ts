import { describe, it, expect } from "vitest"
import {
  parseServerTimestamp,
  businessDatePart,
  formatCompanyDateTime,
  formatInstant,
  formatTimeInZone,
  businessSortValue,
  fmtDateTimeParts,
  fmtMonthYear,
} from "./company-datetime"

const ACCRA = "Africa/Accra"      // UTC+0, no DST
const LAGOS = "Africa/Lagos"      // UTC+1, no DST
const NEW_YORK = "America/New_York" // UTC-5 / -4, DST

describe("parseServerTimestamp", () => {
  it("treats a bare API timestamp as UTC, not as browser-local time", () => {
    // The Farm API has no JSON date converter and the columns are
    // `timestamp without time zone`, so .NET emits no offset. JavaScript would
    // read this as local time; the stored value is actually UTC. Getting this
    // wrong is invisible in Ghana and an hour or five out everywhere else.
    expect(parseServerTimestamp("2026-09-17T11:56:00.295985")?.toISOString())
      .toBe("2026-09-17T11:56:00.295Z")
  })

  it("accepts a space separator as well as a T", () => {
    expect(parseServerTimestamp("2026-09-17 11:56:00")?.toISOString())
      .toBe("2026-09-17T11:56:00.000Z")
  })

  it("leaves an already-zoned value alone", () => {
    expect(parseServerTimestamp("2026-09-17T11:56:00Z")?.toISOString())
      .toBe("2026-09-17T11:56:00.000Z")
    expect(parseServerTimestamp("2026-09-17T11:56:00+01:00")?.toISOString())
      .toBe("2026-09-17T10:56:00.000Z")
  })

  it("returns null rather than an Invalid Date", () => {
    expect(parseServerTimestamp(null)).toBeNull()
    expect(parseServerTimestamp("")).toBeNull()
    expect(parseServerTimestamp("not a date")).toBeNull()
  })
})

describe("businessDatePart", () => {
  it("reads the day off the string without any timezone conversion", () => {
    // The business date is a LABEL for a day, not an instant. Converting
    // midnight UTC into any zone west of UTC rolls it back a day -- the
    // off-by-one this codebase has hit repeatedly.
    expect(businessDatePart("2026-09-17T00:00:00")).toBe("2026-09-17")
    expect(businessDatePart("2026-09-17 00:00:00")).toBe("2026-09-17")
    expect(businessDatePart("2026-09-17")).toBe("2026-09-17")
  })

  it("returns empty for junk so a cell renders blank, not 'Invalid Date'", () => {
    expect(businessDatePart(null)).toBe("")
    expect(businessDatePart("nonsense")).toBe("")
  })
})

describe("formatCompanyDateTime", () => {
  it("shows the business date with the time the record was entered", () => {
    // The real shape of an Expenses row: business date midnight, creation
    // timestamp carrying the actual clock reading.
    expect(formatCompanyDateTime("2026-09-17T00:00:00", "2026-09-17T11:56:00.295985", ACCRA))
      .toBe("17 Sep 2026, 11:56")
  })

  it("renders the time in the COMPANY's zone, not the viewer's", () => {
    // Same instant, two companies. This is the whole reason the zone is a
    // parameter rather than being left to the browser.
    const created = "2026-09-17T11:56:00"
    expect(formatCompanyDateTime("2026-09-17T00:00:00", created, ACCRA)).toBe("17 Sep 2026, 11:56")
    expect(formatCompanyDateTime("2026-09-17T00:00:00", created, LAGOS)).toBe("17 Sep 2026, 12:56")
    expect(formatCompanyDateTime("2026-09-17T00:00:00", created, NEW_YORK)).toBe("17 Sep 2026, 07:56")
  })

  it("never moves the business date, even when the zone shifts the clock past midnight", () => {
    // 00:30 UTC is still the previous evening in New York. The TIME must shift;
    // the business DATE must not. This is the case that proves the two halves
    // are treated differently on purpose.
    expect(formatCompanyDateTime("2026-09-17T00:00:00", "2026-09-17T00:30:00", NEW_YORK))
      .toBe("17 Sep 2026, 20:30")
  })

  it("shows the date alone when there is no real time to show", () => {
    // A back-dated expense with no creation timestamp. Printing "12:00 AM" here
    // would be inventing a fact -- 184 of 185 live expense rows look like this.
    expect(formatCompanyDateTime("2026-09-15T00:00:00", null, ACCRA)).toBe("15 Sep 2026")
  })

  it("falls back to the business date's OWN time when it has a real one", () => {
    // Water Sales stores a genuine clock time on every row, so those tables show
    // a time even before the endpoint exposes a creation timestamp.
    expect(formatCompanyDateTime("2026-09-17T14:22:00", null, ACCRA))
      .toBe("17 Sep 2026, 14:22")
  })

  it("prefers the creation timestamp when both carry a time", () => {
    expect(formatCompanyDateTime("2026-09-17T14:22:00", "2026-09-17T09:05:00", ACCRA))
      .toBe("17 Sep 2026, 09:05")
  })

  it("keeps the back-dated date and the entry time, as agreed", () => {
    // Documented trade-off, not a bug: a purchase dated the 9th, keyed in on the
    // 17th, reads as the 9th at the time it was typed.
    expect(formatCompanyDateTime("2026-09-09T00:00:00", "2026-09-17T11:56:00", ACCRA))
      .toBe("9 Sep 2026, 11:56")
  })

  it("returns empty for a missing business date", () => {
    expect(formatCompanyDateTime(null, "2026-09-17T11:56:00", ACCRA)).toBe("")
  })

  it("falls back to UTC for an unknown zone instead of dropping the time", () => {
    expect(formatCompanyDateTime("2026-09-17T00:00:00", "2026-09-17T11:56:00", "Mars/Olympus"))
      .toBe("17 Sep 2026, 11:56")
  })
})

describe("formatTimeInZone", () => {
  it("honours daylight saving, which is why zones are ids and not offsets", () => {
    // New York is -05:00 in January and -04:00 in July. A stored "-05:00" offset
    // would be an hour wrong all summer.
    const jan = parseServerTimestamp("2026-01-15T17:00:00")
    const jul = parseServerTimestamp("2026-07-15T17:00:00")
    expect(formatTimeInZone(jan, NEW_YORK)).toBe("12:00")
    expect(formatTimeInZone(jul, NEW_YORK)).toBe("13:00")
  })
})

describe("formatInstant", () => {
  it("formats a pure event timestamp in the company zone", () => {
    expect(formatInstant("2026-09-17T11:56:00", ACCRA)).toBe("17 Sep 2026, 11:56")
  })

  it("rolls the DATE too when the zone pushes it across midnight", () => {
    // Unlike a business date, an instant genuinely belongs to whatever day it
    // falls on in the viewing zone.
    expect(formatInstant("2026-09-17T00:30:00", NEW_YORK)).toBe("16 Sep 2026, 20:30")
  })
})

describe("createdTimestampOf", () => {
  it("finds the timestamp whatever the endpoint calls it", () => {
    expect(formatCompanyDateTime("2026-09-17T00:00:00", { createdDate: "2026-09-17T11:56:00" }, ACCRA))
      .toBe("17 Sep 2026, 11:56")
    expect(formatCompanyDateTime("2026-09-17T00:00:00", { createdAt: "2026-09-17T11:56:00" }, ACCRA))
      .toBe("17 Sep 2026, 11:56")
    expect(formatCompanyDateTime("2026-09-17T00:00:00", { dateCreated: "2026-09-17T11:56:00" }, ACCRA))
      .toBe("17 Sep 2026, 11:56")
  })

  it("finds a PascalCase key too", () => {
    // A silently-missed key would drop the row back to date-only, which is the
    // kind of bug nobody notices until someone asks why one table differs.
    expect(formatCompanyDateTime("2026-09-17T00:00:00", { CreatedAt: "2026-09-17T11:56:00" }, ACCRA))
      .toBe("17 Sep 2026, 11:56")
  })

  it("ignores a row with no usable timestamp", () => {
    expect(formatCompanyDateTime("2026-09-17T00:00:00", { createdAt: "" }, ACCRA)).toBe("17 Sep 2026")
    expect(formatCompanyDateTime("2026-09-17T00:00:00", { somethingElse: 1 }, ACCRA)).toBe("17 Sep 2026")
  })
})

describe("businessSortValue", () => {
  const key = (d: string, row?: any) => businessSortValue(d, row)

  it("puts the later ENTRY on top within the same business day", () => {
    // The reported bug: a sale entered a minute ago sat below older rows because
    // every business date on that day is midnight, so they all tied.
    const early = key("2026-09-17T00:00:00", { createdAt: "2026-09-17T09:05:00" })
    const late  = key("2026-09-17T00:00:00", { createdAt: "2026-09-17T18:20:19" })
    expect(late).toBeGreaterThan(early)
  })

  it("keeps the business date dominant over the entry time", () => {
    // A back-dated entry typed today must NOT jump above a row that genuinely
    // belongs to a later day.
    const backdated = key("2026-09-09T00:00:00", { createdAt: "2026-09-17T23:59:00" })
    const laterDay  = key("2026-09-17T00:00:00", { createdAt: "2026-09-17T00:01:00" })
    expect(laterDay).toBeGreaterThan(backdated)
  })

  it("falls back to the business date's own time when there is no entry time", () => {
    const early = key("2026-09-17T09:05:00")
    const late  = key("2026-09-17T14:22:00")
    expect(late).toBeGreaterThan(early)
  })

  it("is stable for junk instead of producing NaN", () => {
    expect(businessSortValue(null)).toBe(0)
    expect(businessSortValue("nonsense")).toBe(0)
  })
})

describe("fmtDateTimeParts", () => {
  it("splits the date from the time so a narrow column can stack them", () => {
    expect(fmtDateTimeParts("2026-09-17T00:00:00", { createdAt: "2026-09-17T11:56:00" }))
      .toEqual({ date: "17 Sep 2026", time: "11:56" })
  })

  it("returns an empty time when there is none, so nothing is rendered", () => {
    expect(fmtDateTimeParts("2026-09-15T00:00:00", null))
      .toEqual({ date: "15 Sep 2026", time: "" })
  })

  it("returns empty parts for a missing date", () => {
    expect(fmtDateTimeParts(null)).toEqual({ date: "", time: "" })
  })
})

describe("fmtMonthYear", () => {
  // The bug this guards: `new Date("2026-09-01")` is UTC midnight, so
  // toLocaleDateString in a browser WEST of Greenwich renders AUGUST -- a
  // depreciation period labelled "Aug 2026" for September's charge. Ghana and
  // Nigeria are UTC+0/+1 and would never have seen it; one customer in the
  // Americas would have seen every period label slip by a month.
  //
  // Note what the plain cases below do and do not prove. They pin the digits,
  // but on a UTC+ runner (this one is Atlantic/Reykjavik) they would ALSO pass
  // against the old Date-parsing implementation. The last test is the one that
  // bites on any runner, because it compares the two approaches directly.
  it("labels a period from its own digits, not the browser's clock", () => {
    expect(fmtMonthYear("2026-09-01")).toBe("Sep 2026")
    expect(fmtMonthYear("2026-01-01")).toBe("Jan 2026")
    expect(fmtMonthYear("2026-12-31")).toBe("Dec 2026")
  })

  it("reads a timestamp the same way, in either wire shape", () => {
    expect(fmtMonthYear("2026-09-30T00:00:00")).toBe("Sep 2026")
    expect(fmtMonthYear("2026-09-30 23:59:59")).toBe("Sep 2026")
  })

  it("does not roll a first-of-month back into the month before", () => {
    // The exact shape the old implementation got wrong.
    expect(fmtMonthYear("2026-03-01T00:00:00")).toBe("Mar 2026")
  })

  it("does not drift with the viewer's timezone, the way Date parsing does", () => {
    // Deterministic on every runner: an explicit timeZone stands in for a
    // browser in the Americas, without depending on the process TZ (which Node
    // on Windows ignores anyway).
    const viaInstant = (tz: string) =>
      new Date("2026-09-01").toLocaleDateString("en-GB", {
        month: "short", year: "numeric", timeZone: tz,
      })

    // This is the failure mode, reproduced: parsing the period as an instant
    // puts a September charge in August.
    expect(viaInstant("America/New_York")).toContain("Aug")

    // And this is the fix: the same input, labelled off its digits, is September
    // for every viewer on earth.
    expect(fmtMonthYear("2026-09-01")).toBe("Sep 2026")
    expect(fmtMonthYear("2026-09-01")).not.toBe(viaInstant("America/New_York"))
    expect(fmtMonthYear("2026-09-01")).not.toBe(viaInstant("America/Los_Angeles"))
  })

  it("is empty rather than 'Invalid Date' when there is nothing to label", () => {
    expect(fmtMonthYear(null)).toBe("")
    expect(fmtMonthYear(undefined)).toBe("")
    expect(fmtMonthYear("")).toBe("")
    expect(fmtMonthYear("nonsense")).toBe("")
  })
})
