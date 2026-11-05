import { describe, it, expect } from "vitest"
import { buildAutoLossEntries, fromAutoDamageApi, fromProductionRecords, fromProductionLosses, fromEggLossTransactions } from "./auto-loss-entries"

const rec = (o: any) => ({ id: 1, date: "2026-11-05T00:00:00", brokenEggs: 0, flockName: "A", ...o })

describe("auto loss entries", () => {
  it("makes one Damage row per production record with broken eggs", () => {
    const rows = fromProductionRecords([rec({ id: 1, brokenEggs: 12 }), rec({ id: 2, brokenEggs: 0 })] as any)
    expect(rows).toHaveLength(1)
    expect(rows[0]).toMatchObject({ key: "pr-1", lossType: "Damage", productName: "Broken eggs", quantity: 12 })
    expect(rows[0].href).toContain("/production-records/1")
  })

  it("describes a partial disposal", () => {
    const [r] = fromProductionRecords([rec({ brokenEggs: 10, brokenEggsDisposed: 4 })] as any)
    expect(r.reason).toBe("Flock A · 4 disposed, 6 kept")
  })

  it("maps driver-return losses and keeps their value", () => {
    const [r] = fromProductionLosses([{ poultryProductionLossId: 7, farmId: "f", sourceType: "PoultryDriverReturn", lossDate: "2026-11-04", quantityLost: 60, estimatedValue: 90, productName: "Fresh Eggs" }] as any)
    expect(r).toMatchObject({ source: "DriverReturn", quantity: 60, estimatedValue: 90, href: "/poultry-driver-returns" })
  })

  it("takes only Egg Loss ledger rows, as positive quantities", () => {
    const rows = fromEggLossTransactions([
      { poultryStockTransactionId: 1, txnType: "Egg Loss", quantity: -30, productName: "Large", note: "Breakage: dropped tray", createdDate: "2026-11-05" },
      { poultryStockTransactionId: 2, txnType: "Adjustment", quantity: 8, createdDate: "2026-11-05" },
      { poultryStockTransactionId: 3, txnType: "Sale", quantity: -100, createdDate: "2026-11-05" },
    ] as any)
    expect(rows).toHaveLength(1)
    expect(rows[0]).toMatchObject({ quantity: 30, productName: "Large eggs", reason: "Breakage: dropped tray" })
  })

  it("maps the server's rows to the same shape", () => {
    const rows = fromAutoDamageApi([
      { sourceType: "ProductionRecord", sourceId: 9, lossDate: "2026-11-05", lossType: "Damage", productName: "Broken eggs", quantity: 10, flockName: "A", brokenEggs: 10, disposed: 4 },
      { sourceType: "DriverReturn", sourceId: 3, lossDate: "2026-11-04", lossType: "Damage", productName: "Fresh Eggs", quantity: 60, estimatedValue: 90 },
      { sourceType: "EggSorting", sourceId: 5, lossDate: "2026-11-03", lossType: "Damage", productName: "Large eggs", quantity: 30, details: "Breakage: dropped tray" },
    ])
    expect(rows[0]).toMatchObject({ key: "pr-9", reason: "Flock A · 4 disposed, 6 kept", href: expect.stringContaining("/production-records/9") })
    expect(rows[1]).toMatchObject({ source: "DriverReturn", estimatedValue: 90, href: "/poultry-driver-returns" })
    expect(rows[2]).toMatchObject({ source: "EggSorting", reason: "Breakage: dropped tray" })
  })

  it("filters by date range and sorts newest first", () => {
    const rows = buildAutoLossEntries({
      records: [rec({ id: 1, date: "2026-11-01", brokenEggs: 1 }), rec({ id: 2, date: "2026-11-05", brokenEggs: 2 }), rec({ id: 3, date: "2026-10-01", brokenEggs: 3 })] as any,
      fromDate: "2026-11-01",
    })
    expect(rows.map((r) => r.key)).toEqual(["pr-2", "pr-1"])
  })
})
