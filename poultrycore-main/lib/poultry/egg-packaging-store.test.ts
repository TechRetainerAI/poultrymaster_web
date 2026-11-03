import { beforeEach, describe, expect, it } from "vitest"
import { useAuthStore } from "@/lib/store/auth-store"
import { applyEggPackaging, getEggPackagingNow } from "@/hooks/use-egg-packaging"
import { setEggsPerCrate } from "@/lib/production/production-record-calc"
import type { EggPackagingSettings } from "@/lib/api/egg-sorting"

const settings = (farmId: string, cratesPerBox: number | null, on = true): EggPackagingSettings => ({
  farmId,
  eggsPerCrate: 30,
  enableBoxes: on,
  cratesPerBox,
  eggsPerBox: on && cratesPerBox ? cratesPerBox * 30 : null,
  eggDisplay: on ? "BoxesCratesPieces" : "CratesPieces",
  saleEntryUnit: on ? "Boxes" : "Crates",
  packagingVersion: 1,
  storedCratesPerBox: cratesPerBox,
  storedDisplay: on ? "BoxesCratesPieces" : "CratesPieces",
  storedEntryUnit: on ? "Boxes" : "Crates",
})

const switchTo = (farmId: string) => useAuthStore.setState({ activeFarmId: farmId } as never)

describe("egg packaging per company (spec tests 35-37)", () => {
  beforeEach(() => setEggsPerCrate(30))

  it("35: each company converts with its own box size", () => {
    switchTo("farm-a")
    applyEggPackaging("farm-a", settings("farm-a", 14))
    expect(getEggPackagingNow().eggsPerBox).toBe(420)

    switchTo("farm-b")
    applyEggPackaging("farm-b", settings("farm-b", 10))
    expect(getEggPackagingNow().eggsPerBox).toBe(300)
  })

  it("36: switching company never shows the previous company's boxes", () => {
    switchTo("farm-a")
    applyEggPackaging("farm-a", settings("farm-a", 14))
    // Farm B's own settings have not arrived yet: boxes off, not farm A's 14.
    switchTo("farm-b")
    const p = getEggPackagingNow()
    expect(p.enableBoxes).toBe(false)
    expect(p.cratesPerBox).toBeNull()
    expect(p.display).toBe("CratesPieces")
  })

  it("37: a crate-only company stays on crates and pieces", () => {
    switchTo("farm-c")
    applyEggPackaging("farm-c", settings("farm-c", null, false))
    const p = getEggPackagingNow()
    expect(p.enableBoxes).toBe(false)
    expect(p.saleEntryUnit).toBe("Crates")
    expect(p.eggsPerBox).toBeNull()
  })

  it("eggs per crate always comes from the crate-size setting", () => {
    switchTo("farm-d")
    applyEggPackaging("farm-d", settings("farm-d", 10))
    setEggsPerCrate(24)
    expect(getEggPackagingNow().eggsPerBox).toBe(240)
  })
})
