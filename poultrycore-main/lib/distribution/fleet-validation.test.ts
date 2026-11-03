import { describe, it, expect } from "vitest"
import {
  checkLicense, checkPersonName, checkPhone, validateDriver, validateRoute, validateVehicle,
} from "./fleet-validation"

// Each case below is one of the tester's reports (2026-11-03) or its mirror.

const truck = { id: 1, vehicleName: "Truck 1", vehicleType: "Truck", registrationNumber: "GR 1234-20", capacityCrates: 800, fuelType: "Diesel" }

describe("validateVehicle", () => {
  it("accepts a sensible vehicle", () => {
    expect(validateVehicle({ ...truck, id: null, registrationNumber: "AS 555-21" }, [truck])).toBeNull()
  })

  it("rejects a registration number already in use, however it is spaced", () => {
    const out = validateVehicle({ ...truck, id: null, vehicleName: "Van", registrationNumber: "gr1234 20" }, [truck])
    expect(out).toMatch(/already used by Truck 1/)
  })

  it("lets a vehicle keep its own registration number on edit", () => {
    expect(validateVehicle(truck, [truck])).toBeNull()
  })

  it("rejects a diesel motorbike", () => {
    const out = validateVehicle({ vehicleName: "Bike", vehicleType: "Motorbike", registrationNumber: "M 22-19", capacityCrates: 10, fuelType: "Diesel" }, [])
    expect(out).toMatch(/A motorbike cannot run on Diesel/)
  })

  it("rejects a motorbike carrying 1,000 crates", () => {
    const out = validateVehicle({ vehicleName: "Bike", vehicleType: "Motorbike", registrationNumber: "M 22-19", capacityCrates: 1000, fuelType: "Petrol" }, [])
    expect(out).toBe("A motorbike cannot carry 1,000 crates. The most allowed is 40.")
  })

  it("requires a registration number and capacity", () => {
    expect(validateVehicle({ ...truck, id: null, registrationNumber: "" }, [])).toMatch(/registration number/i)
    expect(validateVehicle({ ...truck, id: null, capacityCrates: null }, [])).toMatch(/how many crates/)
  })
})

describe("driver fields", () => {
  it("rejects numeric names", () => {
    expect(checkPersonName("12345")).toMatch(/cannot contain numbers/)
    expect(checkPersonName("Kofi Mensah")).toBeNull()
    expect(checkPersonName("Ama O'Neil-Boateng")).toBeNull()
  })

  it("accepts Ghana numbers in both forms and rejects junk", () => {
    expect(checkPhone("024 123 4567")).toBeNull()
    expect(checkPhone("+233 24 123 4567")).toBeNull()
    expect(checkPhone("+44 7700 900123")).toBeNull()
    expect(checkPhone("123")).toMatch(/valid phone/)
    expect(checkPhone("02412345678")).toMatch(/valid phone/)
    expect(checkPhone("abc")).toMatch(/digits/)
  })

  it("rejects an incomplete licence", () => {
    expect(checkLicense("12")).toMatch(/incomplete/)
    expect(checkLicense("ABCDEFG")).toMatch(/numbers/)
    expect(checkLicense("GHA-12345678")).toBeNull()
  })

  it("requires a default vehicle, and says how when there are none", () => {
    const d = { driverName: "Kofi Mensah", phoneNumber: "0241234567", licenseNumber: "GHA-12345678", defaultVehicleId: null }
    expect(validateDriver(d, { others: [], vehicleCount: 2 })).toBe("Choose the driver's default vehicle.")
    expect(validateDriver(d, { others: [], vehicleCount: 0 })).toMatch(/Add a vehicle on the Vehicles page first/)
    expect(validateDriver({ ...d, defaultVehicleId: 1 }, { others: [], vehicleCount: 1 })).toBeNull()
  })

  it("rejects a phone number another driver already has, in either form", () => {
    const other = { id: 9, driverName: "Yaw", phoneNumber: "+233 24 123 4567", licenseNumber: "X1234567" }
    const d = { driverName: "Kofi Mensah", phoneNumber: "0241234567", licenseNumber: "GHA-12345678", defaultVehicleId: 1 }
    expect(validateDriver(d, { others: [other], vehicleCount: 1 })).toMatch(/already belongs to driver Yaw/)
  })
})

describe("validateRoute", () => {
  const vehicles = [{ id: 1, vehicleName: "Bike", capacityCrates: 30 }]
  const r = { routeName: "Kumasi East", areaCovered: "Asafo, Adum", defaultVehicleId: 1, expectedCustomers: 12, expectedCratesSold: 20 }

  it("accepts a sensible route", () => {
    expect(validateRoute(r, { others: [], vehicles })).toBeNull()
  })

  it("rejects numeric names, a missing area and duplicate names", () => {
    expect(validateRoute({ ...r, routeName: "123" }, { others: [], vehicles })).toMatch(/include letters/)
    expect(validateRoute({ ...r, areaCovered: "" }, { others: [], vehicles })).toMatch(/area this route covers/)
    expect(validateRoute(r, { others: [{ id: 5, routeName: "kumasi east" }], vehicles })).toMatch(/already a route/)
  })

  it("rejects more crates a day than the vehicle can carry", () => {
    expect(validateRoute({ ...r, expectedCratesSold: 100 }, { others: [], vehicles })).toMatch(/carries at most 30 crates/)
  })
})
