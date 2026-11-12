import { describe, expect, it } from "vitest"
import { flockLifetime, sumLifetime } from "./bird-position"

const base = {
  historyKnown: true, originallyPlaced: 0, openingLiveBirds: 0, openingMortality: 0, openingSold: 0,
  openingCulled: 0, openingTransferred: 0, openingOther: 0, recordedMortality: 0, birdsSold: 0,
  birdsCulled: 0, birdsTransferred: 0, currentLiveBirds: 0,
}

describe("flockLifetime", () => {
  it("counts the opening historical reduction (B3: 10,000 placed, 7,500 live)", () => {
    const f = flockLifetime({ ...base, originallyPlaced: 10000, openingLiveBirds: 7600, openingMortality: 2000,
      openingSold: 300, openingCulled: 100, recordedMortality: 100, currentLiveBirds: 7500 })
    expect(f).toEqual({ started: 10000, deaths: 2100, sold: 300, culled: 100, transferred: 0, other: 0, correction: 0, live: 7500 })
  })

  it("starts from the opening live count when the history is not known", () => {
    const f = flockLifetime({ ...base, historyKnown: false, originallyPlaced: 1000, openingLiveBirds: 900,
      openingOther: 100, recordedMortality: 10, currentLiveBirds: 890 })
    expect(f.started).toBe(900)
    expect(f.deaths).toBe(10)
    expect(f.other).toBe(0)
    expect(f.correction).toBe(0)
  })

  it("leaves an unexplained count as a signed correction", () => {
    const f = flockLifetime({ ...base, originallyPlaced: 1000, openingLiveBirds: 1000, recordedMortality: 5, currentLiveBirds: 990 })
    expect(f.correction).toBe(5)
  })

  it("sums flocks", () => {
    const t = sumLifetime([
      { ...base, originallyPlaced: 967, openingLiveBirds: 941, openingMortality: 26, birdsSold: 20, currentLiveBirds: 921 },
      { ...base, originallyPlaced: 967, openingLiveBirds: 940, openingMortality: 27, currentLiveBirds: 940 },
    ])
    expect(t.started).toBe(1934)
    expect(t.deaths).toBe(53)
    expect(t.sold).toBe(20)
    expect(t.live).toBe(1861)
    expect(t.correction).toBe(0)
  })
})
