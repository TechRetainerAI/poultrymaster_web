import { describe, it, expect, beforeAll, afterAll, beforeEach, afterEach } from "vitest"
import { formatActivityMoment } from "./poultry-financial-activity"
import { COMPANY_TZ_CACHE_PREFIX } from "@/lib/utils/company-datetime"

// formatActivityMoment is the Financial Activity page's own date formatter. It
// is NOT the house fmtDateTime: this page renders "09/17/2026 11:56 AM" and the
// format was explicitly kept when the missing times were added (315), so these
// tests exist as much to pin the FORMAT as the behaviour.
//
// The rule it implements:
//   1. the clock on the business timestamp, where it has one  (sliced, because
//      it is company-local wall clock in a `timestamp without time zone`)
//   2. otherwise the row's entry time                         (converted, because
//      that one is a real UTC instant)
//   3. otherwise the day alone -- never a midnight nobody recorded

const LAGOS = "Africa/Lagos"   // UTC+1, no DST
const ACCRA = "Africa/Accra"   // UTC+0, no DST

// The suite runs under vitest's `node` environment, and currentCompanyTimeZone
// short-circuits to UTC when there is no `window`. Without these two stubs the
// zone-conversion tests below would pass for the wrong reason -- everything
// would be UTC and the Lagos case would never exercise an offset at all.
//
// Stubbed rather than switching the file to jsdom: two properties is a smaller
// and more honest dependency than a DOM, and the config's own comment asks for
// widening to be deliberate.
const store = new Map<string, string>()
const fakeStorage = {
  getItem: (k: string) => (store.has(k) ? store.get(k)! : null),
  setItem: (k: string, v: string) => void store.set(k, v),
  removeItem: (k: string) => void store.delete(k),
  clear: () => store.clear(),
  key: (i: number) => [...store.keys()][i] ?? null,
  get length() { return store.size },
} as Storage

beforeAll(() => {
  ;(globalThis as any).window = globalThis
  ;(globalThis as any).localStorage = fakeStorage
})
afterAll(() => {
  delete (globalThis as any).window
  delete (globalThis as any).localStorage
})

/** currentCompanyTimeZone() reads the active farm id, then the cached zone. */
function useCompanyZone(zone: string) {
  localStorage.setItem("farmId", "test-farm")
  localStorage.setItem(COMPANY_TZ_CACHE_PREFIX + "test-farm", zone)
}

describe("formatActivityMoment", () => {
  beforeEach(() => store.clear())
  afterEach(() => store.clear())

  it("keeps the page's existing format when the business timestamp has a clock", () => {
    // Unchanged behaviour, and the reason these tests are here: the format was
    // deliberately NOT switched to the house "17 Sep 2026" style.
    expect(formatActivityMoment("2026-09-17T11:56:23")).toBe("09/17/2026 11:56 AM")
    expect(formatActivityMoment("2026-09-17T14:05:00")).toBe("09/17/2026 2:05 PM")
    expect(formatActivityMoment("2026-09-17T00:30:00")).toBe("09/17/2026 12:30 AM")
    expect(formatActivityMoment("2026-09-17T12:00:00")).toBe("09/17/2026 12:00 PM")
  })

  it("slices the business clock rather than parsing it", () => {
    // It is company-local wall clock, so parsing it through Date would apply the
    // BROWSER's offset and move an evening entry to the previous day.
    useCompanyZone(LAGOS)
    expect(formatActivityMoment("2026-09-17T23:45:00")).toBe("09/17/2026 11:45 PM")
  })

  // ---- 315: the gap this migration closed ---------------------------------

  it("falls back to the entry time when the business date is midnight", () => {
    useCompanyZone(ACCRA)
    // A sale entered as a plain day: saledate is midnight, so before 315 this
    // row showed "09/17/2026" and nothing else.
    expect(formatActivityMoment("2026-09-17T00:00:00", "2026-09-17T14:32:05"))
      .toBe("09/17/2026 2:32 PM")
  })

  it("converts the entry time into the company's zone, unlike the business clock", () => {
    // The entry time IS a real UTC instant, so 23:30 UTC is 00:30 in Lagos.
    useCompanyZone(LAGOS)
    expect(formatActivityMoment("2026-09-17T00:00:00", "2026-09-17T23:30:00"))
      .toBe("09/17/2026 12:30 AM")
    // Same instant, a zone with no offset.
    useCompanyZone(ACCRA)
    expect(formatActivityMoment("2026-09-17T00:00:00", "2026-09-17T23:30:00"))
      .toBe("09/17/2026 11:30 PM")
  })

  it("keeps the BUSINESS date even when the entry time lands on another day", () => {
    // The day is what the row is ABOUT. A sale back-dated to the 17th and typed
    // on the 20th is still the 17th's sale.
    useCompanyZone(ACCRA)
    expect(formatActivityMoment("2026-09-17T00:00:00", "2026-09-20T08:15:00"))
      .toBe("09/17/2026 8:15 AM")
  })

  it("prefers the business clock over the entry time when both exist", () => {
    useCompanyZone(ACCRA)
    expect(formatActivityMoment("2026-09-17T11:56:00", "2026-09-18T09:00:00"))
      .toBe("09/17/2026 11:56 AM")
  })

  // ---- nothing to show ----------------------------------------------------

  it("shows the day alone rather than a midnight nobody recorded", () => {
    expect(formatActivityMoment("2026-09-17T00:00:00")).toBe("09/17/2026")
    expect(formatActivityMoment("2026-09-17T00:00:00", null)).toBe("09/17/2026")
    expect(formatActivityMoment("2026-09-17")).toBe("09/17/2026")
  })

  it("does not invent a time from an unparseable entry timestamp", () => {
    expect(formatActivityMoment("2026-09-17T00:00:00", "nonsense")).toBe("09/17/2026")
  })

  it("handles an entry time that is itself exactly midnight", () => {
    // A genuine 00:00 entry is indistinguishable from "no time recorded", and
    // guessing would be worse than saying nothing.
    useCompanyZone(ACCRA)
    expect(formatActivityMoment("2026-09-17T00:00:00", "2026-09-17T00:00:00"))
      .toBe("09/17/2026")
  })

  it("is a dash when there is no moment at all", () => {
    expect(formatActivityMoment("")).toBe("—")
    expect(formatActivityMoment("", "2026-09-17T10:00:00")).toBe("—")
  })
})
