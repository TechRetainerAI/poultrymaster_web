/**
 * Validation for the delivery setup forms: Vehicles, Drivers and Routes.
 *
 * Tester reports (2026-11-03) found these forms only checked that a name was
 * entered: three vehicles shared registration 12345, a motorbike was saved as
 * Diesel with room for 1,000 crates, and drivers went in with numeric names,
 * bad phone numbers, two-character licences and no vehicle.
 *
 * Every check returns the sentence to show, or null when the value is fine.
 * Pure functions so they are tested in fleet-validation.test.ts and shared by
 * every form that edits these records.
 */

// ---------------------------------------------------------------------------
// Vehicle type rules
// ---------------------------------------------------------------------------

export const VEHICLE_TYPES = ["Truck", "Van", "Pickup", "Tricycle", "Motorbike", "Other"] as const

const ALL_FUELS = ["Petrol", "Diesel", "Electric", "Hybrid", "LPG / Gas"]

/** Fuels a vehicle of each type can realistically run on. */
export const FUELS_BY_TYPE: Record<string, string[]> = {
  Truck: ["Diesel", "Petrol", "Electric", "Hybrid"],
  Van: ["Petrol", "Diesel", "Electric", "Hybrid", "LPG / Gas"],
  Pickup: ["Petrol", "Diesel", "Electric", "Hybrid"],
  Tricycle: ["Petrol", "Electric"],
  Motorbike: ["Petrol", "Electric"],
  Other: ALL_FUELS,
}

/**
 * Most crates of eggs a vehicle of each type can carry. Generous on purpose:
 * this exists to stop typos (a motorbike with 1,000 crates), not to second-
 * guess a farm that loads heavily.
 */
export const MAX_CRATES_BY_TYPE: Record<string, number> = {
  Motorbike: 40,
  Tricycle: 200,
  Pickup: 400,
  Van: 600,
  Truck: 5000,
  Other: 5000,
}

export function fuelsFor(type: string | null | undefined): string[] {
  return FUELS_BY_TYPE[type || "Other"] ?? ALL_FUELS
}

export function maxCratesFor(type: string | null | undefined): number {
  return MAX_CRATES_BY_TYPE[type || "Other"] ?? MAX_CRATES_BY_TYPE.Other
}

function article(word: string): string {
  return /^[aeiou]/i.test(word) ? "an" : "a"
}

// ---------------------------------------------------------------------------
// Field checks
// ---------------------------------------------------------------------------

const hasLetter = (s: string) => /\p{L}/u.test(s)

/** "GR 1234-20", "gr1234 20" and "GR-1234-20" are the same plate. */
export function normalizeRegistration(s: string | null | undefined): string {
  return (s || "").toUpperCase().replace(/[^A-Z0-9]/g, "")
}

export function checkRegistration(value: string | null | undefined): string | null {
  const v = (value || "").trim()
  if (!v) return "Enter the vehicle's registration number."
  if (!/^[A-Za-z0-9][A-Za-z0-9 \-\/]*$/.test(v)) {
    return "Registration number can only use letters, numbers, spaces, - and /."
  }
  const compact = normalizeRegistration(v)
  if (compact.length < 4 || compact.length > 15) return "Registration number should be 4 to 15 letters and numbers, e.g. GR 1234-20."
  if (!/\d/.test(compact)) return "Registration number should include numbers, e.g. GR 1234-20."
  return null
}

/** A person's name: letters, spaces and . ' - only, at least two letters. */
export function checkPersonName(value: string | null | undefined, what = "Driver name"): string | null {
  const v = (value || "").trim()
  if (!v) return `${what} is required.`
  if (/\d/.test(v)) return `${what} cannot contain numbers.`
  if (!/^[\p{L}][\p{L} .'\-]*$/u.test(v)) return `${what} can only use letters, spaces, apostrophes and hyphens.`
  if ((v.match(/\p{L}/gu) || []).length < 2) return `${what} is too short.`
  return null
}

/**
 * A phone number. Ghana numbers in either form (0241234567 or +233241234567),
 * or any international number written with a leading +. Spaces and dashes are
 * fine; letters are not.
 */
export function checkPhone(value: string | null | undefined, required = true): string | null {
  const v = (value || "").trim()
  if (!v) return required ? "Enter the driver's phone number." : null
  if (!/^\+?[\d\s\-()]+$/.test(v)) return "Phone number can only contain digits, spaces, dashes and a leading +."
  const digits = v.replace(/\D/g, "")
  const ok =
    /^0\d{9}$/.test(digits) && !v.startsWith("+") ||           // 024 123 4567
    /^233\d{9}$/.test(digits) ||                                // +233 24 123 4567
    v.startsWith("+") && digits.length >= 8 && digits.length <= 15 && !digits.startsWith("233")
  return ok ? null : "Enter a valid phone number, e.g. 024 123 4567 or +233 24 123 4567."
}

export function normalizePhone(s: string | null | undefined): string {
  const d = (s || "").replace(/\D/g, "")
  if (/^0\d{9}$/.test(d)) return "233" + d.slice(1)
  return d
}

/** A driver's licence number: 6 to 20 letters/numbers, must include a number. */
export function checkLicense(value: string | null | undefined): string | null {
  const v = (value || "").trim()
  if (!v) return "Enter the driver's licence number."
  if (!/^[A-Za-z0-9][A-Za-z0-9 \-\/]*$/.test(v)) return "Licence number can only use letters, numbers, spaces, - and /."
  const compact = v.replace(/[^A-Za-z0-9]/g, "")
  if (compact.length < 6) return "Licence number looks incomplete. Enter the full number from the licence card."
  if (compact.length > 20) return "Licence number is too long. Check it against the licence card."
  if (!/\d/.test(compact)) return "Licence number should include numbers. Check it against the licence card."
  return null
}

function checkWholeNumber(value: number | null | undefined, label: string): string | null {
  if (value === null || value === undefined) return null
  if (!Number.isFinite(value) || value < 0) return `${label} cannot be negative.`
  if (!Number.isInteger(value)) return `${label} must be a whole number.`
  return null
}

// ---------------------------------------------------------------------------
// Whole-form checks (first problem wins, in the order the form shows fields)
// ---------------------------------------------------------------------------

export interface VehicleLike {
  id?: number | null
  vehicleName: string
  vehicleType?: string | null
  registrationNumber?: string | null
  capacityCrates?: number | null
  fuelType?: string | null
}

export function validateVehicle(form: VehicleLike, others: VehicleLike[]): string | null {
  const name = form.vehicleName.trim()
  if (!name) return "Vehicle name is required."
  if (!hasLetter(name)) return "Vehicle name should include letters, e.g. Truck 1."

  const regError = checkRegistration(form.registrationNumber)
  if (regError) return regError
  const reg = normalizeRegistration(form.registrationNumber)
  const clash = others.find((o) => o.id !== form.id && normalizeRegistration(o.registrationNumber) === reg)
  if (clash) return `Registration number ${form.registrationNumber!.trim()} is already used by ${clash.vehicleName}.`

  const type = form.vehicleType || "Other"
  if (form.fuelType && !fuelsFor(type).includes(form.fuelType)) {
    return `${article(type)[0].toUpperCase()}${article(type).slice(1)} ${type.toLowerCase()} cannot run on ${form.fuelType}. Choose ${fuelsFor(type).join(" or ")}.`
  }

  const cap = form.capacityCrates
  if (cap === null || cap === undefined) return "Enter how many crates this vehicle can carry."
  const capError = checkWholeNumber(cap, "Capacity")
  if (capError) return capError
  if (cap === 0) return "Capacity must be at least 1 crate."
  const max = maxCratesFor(type)
  if (cap > max) {
    return `${article(type)[0].toUpperCase()}${article(type).slice(1)} ${type.toLowerCase()} cannot carry ${cap.toLocaleString("en-US")} crates. The most allowed is ${max.toLocaleString("en-US")}.`
  }
  return null
}

export interface DriverLike {
  id?: number | null
  driverName: string
  phoneNumber?: string | null
  licenseNumber?: string | null
  defaultVehicleId?: number | null
}

export function validateDriver(
  form: DriverLike,
  ctx: { others: DriverLike[]; vehicleCount: number },
): string | null {
  const nameError = checkPersonName(form.driverName)
  if (nameError) return nameError

  const phoneError = checkPhone(form.phoneNumber)
  if (phoneError) return phoneError
  const phone = normalizePhone(form.phoneNumber)
  const phoneClash = ctx.others.find((o) => o.id !== form.id && o.phoneNumber && normalizePhone(o.phoneNumber) === phone)
  if (phoneClash) return `Phone number ${form.phoneNumber!.trim()} already belongs to driver ${phoneClash.driverName}.`

  const licError = checkLicense(form.licenseNumber)
  if (licError) return licError
  const lic = normalizeRegistration(form.licenseNumber)
  const licClash = ctx.others.find((o) => o.id !== form.id && o.licenseNumber && normalizeRegistration(o.licenseNumber) === lic)
  if (licClash) return `Licence number ${form.licenseNumber!.trim()} already belongs to driver ${licClash.driverName}.`

  if (!form.defaultVehicleId) {
    return ctx.vehicleCount === 0
      ? "Add a vehicle on the Vehicles page first, then choose it as this driver's default vehicle."
      : "Choose the driver's default vehicle."
  }
  return null
}

export interface RouteLike {
  id?: number | null
  routeName: string
  areaCovered?: string | null
  defaultVehicleId?: number | null
  expectedCustomers?: number | null
  expectedCratesSold?: number | null
}

export function validateRoute(
  form: RouteLike,
  ctx: { others: RouteLike[]; vehicles: { id: number; vehicleName: string; capacityCrates?: number | null }[] },
): string | null {
  const name = form.routeName.trim()
  if (!name) return "Route name is required."
  if (!hasLetter(name)) return "Route name should include letters, e.g. Kumasi East."
  const clash = ctx.others.find((o) => o.id !== form.id && o.routeName.trim().toLowerCase() === name.toLowerCase())
  if (clash) return `There is already a route called ${clash.routeName}.`

  const area = (form.areaCovered || "").trim()
  if (!area) return "Enter the area this route covers, e.g. Asafo, Adum, Bantama."
  if (!hasLetter(area)) return "Area covered should name places, not just numbers."

  if (!form.defaultVehicleId) {
    return ctx.vehicles.length === 0
      ? "Add a vehicle on the Vehicles page first, then choose it as this route's default vehicle."
      : "Choose the vehicle that usually runs this route."
  }

  const custError = checkWholeNumber(form.expectedCustomers, "Expected customers")
  if (custError) return custError
  const crateError = checkWholeNumber(form.expectedCratesSold, "Expected crates/day")
  if (crateError) return crateError

  const v = ctx.vehicles.find((x) => x.id === form.defaultVehicleId)
  if (v?.capacityCrates && form.expectedCratesSold && form.expectedCratesSold > v.capacityCrates) {
    return `${v.vehicleName} carries at most ${v.capacityCrates.toLocaleString("en-US")} crates, but this route expects ${form.expectedCratesSold.toLocaleString("en-US")} a day. Lower the number or choose a bigger vehicle.`
  }
  return null
}
