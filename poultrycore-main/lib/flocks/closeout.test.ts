import { describe, expect, it } from "vitest"
import {
  dispositionTotals,
  groupLifetimeSummaries,
  reconciliationLines,
  saleTotal,
  unresolvedBirds,
  validateCloseoutDraft,
  type CloseoutDraft,
} from "./closeout"
import type { FlockBirdPosition, FlockCloseoutContext, FlockLifetimeSummary } from "@/lib/api/flock-closeout"
import {
  getFlockLifecycleStatus,
  isFlockClosed,
  isFlockOpenForEntry,
  shouldAutoActivateFlock,
} from "@/lib/utils/flock-eligibility"
import type { Flock } from "@/lib/api/flock"

// The same flock the database checks use (poultry-flock-closeout.test.sql,
// flock A): 500 placed, 15 deaths, 35 sold earlier, 450 standing.
const position = (over: Partial<FlockBirdPosition> = {}): FlockBirdPosition => ({
  flockId: 1,
  hasOpeningPosition: false,
  historyKnown: true,
  originallyPlaced: 500,
  openingMortality: 0,
  openingSold: 0,
  openingCulled: 0,
  openingTransferred: 0,
  openingOther: 0,
  openingLiveBirds: 500,
  recordedMortality: 15,
  productionRecordCount: 2,
  lastCountedBirds: 485,
  lastCountDate: "2026-09-19",
  correction: 0,
  birdsSold: 35,
  birdsCulled: 0,
  birdsTransferred: 0,
  currentLiveBirds: 450,
  ...over,
})

const context = (over: Partial<FlockCloseoutContext> = {}): FlockCloseoutContext => ({
  flock: { flockId: 1, name: "A", hasArrived: true, active: true } as Flock,
  position: position(),
  isClosed: false,
  ineligibleReason: null,
  houseName: "House 1",
  businessDate: "2026-09-29",
  earliestCloseDate: "2026-09-19",
  birdProductName: "Birds",
  ...over,
})

const draft = (over: Partial<CloseoutDraft> = {}): CloseoutDraft => ({
  closedDate: "2026-09-29",
  reason: "End of lay",
  sales: [],
  culls: [],
  transfers: [],
  ...over,
})

const paidSale = (quantity: number) => ({
  quantity,
  unitPrice: 12.5,
  paymentTerms: "Paid" as const,
  paymentMethod: "Cash",
  poultryCashAccountId: 7,
})

describe("closeout reconciliation", () => {
  it("walks from placed to live in the order the birds moved", () => {
    const lines = reconciliationLines(position())
    expect(lines.map((l) => l.key)).toEqual(["placed", "openingLive", "mortality", "lastCount", "sold", "live"])
    expect(lines.find((l) => l.key === "live")?.value).toBe(450)
  })

  it("shows a correction only when the count disagrees with mortality", () => {
    expect(reconciliationLines(position({ correction: -20 })).some((l) => l.key === "correction")).toBe(true)
    expect(reconciliationLines(position()).some((l) => l.key === "correction")).toBe(false)
  })

  it("keeps opening history apart from mortality recorded since", () => {
    const lines = reconciliationLines(position({
      hasOpeningPosition: true, originallyPlaced: 1000, openingLiveBirds: 800,
      openingMortality: 150, openingSold: 50, recordedMortality: 0, lastCountedBirds: 800,
    }))
    const keys = lines.map((l) => l.key)
    expect(keys).toContain("openingMortality")
    expect(keys.indexOf("openingMortality")).toBeLessThan(keys.indexOf("openingLive"))
    expect(lines.find((l) => l.key === "openingLive")?.label).toBe("Opening current position")
    expect(lines.find((l) => l.key === "mortality")?.value).toBe(0)
  })

  it("never calls an unknown opening reduction mortality", () => {
    const lines = reconciliationLines(position({
      hasOpeningPosition: true, historyKnown: false, originallyPlaced: 1000, openingLiveBirds: 900, openingOther: 100,
    }))
    expect(lines.some((l) => l.key === "openingMortality")).toBe(false)
    expect(lines.find((l) => l.key === "openingOther")?.value).toBe(100)
  })
})

describe("closeout validation", () => {
  it("closes when every bird is sold", () => {
    expect(validateCloseoutDraft(draft({ sales: [paidSale(450)] }), context())).toEqual([])
  })

  it("closes with a transfer and a cull", () => {
    const d = draft({ transfers: [{ quantity: 300, destination: "Sister farm" }], culls: [{ quantity: 150 }] })
    expect(validateCloseoutDraft(d, context())).toEqual([])
    expect(dispositionTotals(d)).toEqual({ sold: 0, culled: 150, transferred: 300, total: 450 })
  })

  it("refuses an unresolved bird balance, both ways", () => {
    expect(validateCloseoutDraft(draft({ sales: [paidSale(400)] }), context()).join(" "))
      .toMatch(/50 bird\(s\) are still unaccounted/)
    expect(validateCloseoutDraft(draft({ culls: [{ quantity: 460 }] }), context()).join(" "))
      .toMatch(/10 more bird\(s\)/)
    expect(unresolvedBirds(position(), draft({ sales: [paidSale(400)] }))).toBe(50)
  })

  it("closes a flock with nothing left without any disposition", () => {
    expect(validateCloseoutDraft(draft(), context({ position: position({ currentLiveBirds: 0 }) }))).toEqual([])
  })

  it("points at a double-counted sale when the records go negative", () => {
    expect(validateCloseoutDraft(draft(), context({ position: position({ currentLiveBirds: -5 }) })).join(" "))
      .toMatch(/also deducted on a production record/)
  })

  it("needs a reason and a date inside the flock's life", () => {
    const errs = validateCloseoutDraft(draft({ reason: " ", closedDate: "2026-09-30", sales: [paidSale(450)] }), context())
    expect(errs.join(" ")).toMatch(/reason is required/)
    expect(errs.join(" ")).toMatch(/future/)
    expect(validateCloseoutDraft(draft({ closedDate: "2026-09-18", sales: [paidSale(450)] }), context()).join(" "))
      .toMatch(/cannot be before 2026-09-19/)
  })

  it("applies the sales page's payment rules", () => {
    const noAccount = { ...paidSale(450), poultryCashAccountId: null }
    expect(validateCloseoutDraft(draft({ sales: [noAccount] }), context()).join(" ")).toMatch(/cash account/)

    const creditNoCustomer = { quantity: 450, unitPrice: 10, paymentTerms: "Credit" as const }
    expect(validateCloseoutDraft(draft({ sales: [creditNoCustomer] }), context()).join(" ")).toMatch(/needs a customer/)

    const credit = { ...creditNoCustomer, customerName: "Market buyer" }
    expect(validateCloseoutDraft(draft({ sales: [credit] }), context())).toEqual([])

    const partTooMuch = { ...paidSale(450), paymentTerms: "PartPaid" as const, customerName: "B", amountPaid: 5625 }
    expect(validateCloseoutDraft(draft({ sales: [partTooMuch] }), context()).join(" ")).toMatch(/part payment/)
    const part = { ...partTooMuch, amountPaid: 2000 }
    expect(validateCloseoutDraft(draft({ sales: [part] }), context())).toEqual([])
  })

  it("requires a destination for birds that leave", () => {
    expect(validateCloseoutDraft(draft({ transfers: [{ quantity: 450, destination: "" }] }), context()).join(" "))
      .toMatch(/say where the birds went/)
  })

  it("refuses a closed or unarrived flock outright", () => {
    expect(validateCloseoutDraft(draft(), context({ isClosed: true }))).toEqual(["This flock is already closed."])
    expect(validateCloseoutDraft(draft(), context({ ineligibleReason: "Not arrived." }))).toEqual(["Not arrived."])
  })

  it("defaults the sale total to quantity x price", () => {
    expect(saleTotal({ quantity: 450, unitPrice: 12.5 })).toBe(5625)
    expect(saleTotal({ quantity: 450, unitPrice: 12.5, totalAmount: 5000 })).toBe(5000)
  })
})

describe("closed flocks leave the active workflows", () => {
  const open = { flockId: 1, name: "Open", active: true, hasArrived: true } as Flock
  const closed = { flockId: 2, name: "Done", active: false, hasArrived: true, closedDate: "2026-09-29", inactivationReason: "closed" } as Flock

  it("has its own lifecycle status, distinct from inactive", () => {
    expect(isFlockClosed(closed)).toBe(true)
    expect(getFlockLifecycleStatus(closed)).toBe("closed")
    expect(getFlockLifecycleStatus({ ...open, active: false })).toBe("inactive")
  })

  it("is not offered for data entry, except to the record that already has it", () => {
    expect(isFlockOpenForEntry(open)).toBe(true)
    expect(isFlockOpenForEntry(closed)).toBe(false)
    expect(isFlockOpenForEntry(closed, 2)).toBe(true)
  })

  it("is never auto-activated, even with an empty reason", () => {
    expect(shouldAutoActivateFlock({ ...closed, inactivationReason: "" })).toBe(false)
    expect(shouldAutoActivateFlock({ ...open, active: false, inactivationReason: "" })).toBe(true)
  })
})

describe("lifetime comparison", () => {
  const row = (over: Partial<FlockLifetimeSummary>): FlockLifetimeSummary => ({
    flockId: 1, flockName: "A", breed: "Isa Brown", status: "Closed", batchId: 1, batchCode: "B1",
    startDate: "2026-01-01", daysInProduction: 200, hasOpeningPosition: false, historyKnown: true,
    originallyPlaced: 1000, openingLiveBirds: 1000, openingMortality: 0, recordedMortality: 50,
    birdsSold: 950, birdsCulled: 0, birdsTransferred: 0, finalBirds: 0, totalEggs: 120000, productionDays: 180,
    eggRevenue: 0, birdSaleRevenue: 0, otherRevenue: 0, totalRevenue: 10000, feedConsumedKg: 12000,
    feedCost: 0, medicationCost: 0, birdCost: 0, birdCostRecorded: true, laborCost: 0, otherDirectCost: 0,
    totalCost: 6000, profit: 4000, houseId: 1, houseName: "H1",
    ...over,
  })

  it("groups by breed and re-derives ratios from the sums", () => {
    const groups = groupLifetimeSummaries([
      row({ flockId: 1, originallyPlaced: 1000, openingLiveBirds: 1000, recordedMortality: 50, profit: 4000 }),
      row({ flockId: 2, originallyPlaced: 100, openingLiveBirds: 100, recordedMortality: 50, profit: 100 }),
      row({ flockId: 3, breed: "Lohmann" }),
    ], "breed")
    const isa = groups.find((g) => g.label === "Isa Brown")!
    expect(isa.flocks).toBe(2)
    // 100 deaths over 1,100 birds -- not the mean of 5% and 50%.
    expect(isa.trackedMortalityRate).toBeCloseTo(100 / 1100, 6)
    expect(isa.profitPerOriginalBird).toBe(3.73)
    expect(groups).toHaveLength(2)
  })

  it("groups by batch, house and supplier with an explicit 'none' bucket", () => {
    const rows = [row({ flockId: 1 }), row({ flockId: 2, batchId: null, batchCode: null, houseId: null, houseName: null })]
    expect(groupLifetimeSummaries(rows, "batch").map((g) => g.label).sort()).toEqual(["B1", "No batch"])
    expect(groupLifetimeSummaries(rows, "house").map((g) => g.label).sort()).toEqual(["H1", "No house"])
    expect(groupLifetimeSummaries(rows, "supplier").map((g) => g.label)).toEqual(["No supplier recorded"])
    expect(groupLifetimeSummaries(rows, "flock")).toHaveLength(2)
  })

  it("leaves feed per dozen empty when no eggs were laid", () => {
    expect(groupLifetimeSummaries([row({ totalEggs: 0 })], "flock")[0].feedKgPerDozenEggs).toBeNull()
  })
})
