// "Also add to payroll" on Add Employee: create the person's staff (payroll)
// record in the active company and link it to the new login (migration 362),
// in one go. Role "Other", Monthly, pay 0 -- the admin sets the real role and
// pay on the Staff page afterwards; payroll runs only pay what is set there.

import { farmApiUrl, getAuthHeaders, getUserContext, readApiError } from "./config"
import { createPoultryStaff } from "./poultry-finance"
import { createWaterStaff } from "./water"
import { createStaff as createGenericStaff } from "./generic"
import { createHotelStaff } from "./hotel"
import { setStaffUserLink } from "./staff-user-link"

export interface LinkedStaffPerson {
  firstName: string
  lastName: string
  phoneNumber?: string | null
  email?: string | null
}

/** Company types whose Staff record can be created from Add Employee. */
export function canCreateLinkedStaff(farmType: string | null | undefined): boolean {
  return farmType === "Poultry" || farmType === "Water" || farmType === "Generic"
    || farmType === "Hotel" || farmType === "Restaurant"
}

async function createRestaurantStaff(p: LinkedStaffPerson): Promise<number> {
  const { farmId } = getUserContext()
  const res = await fetch(farmApiUrl("/Restaurant/staff"), {
    method: "POST",
    headers: getAuthHeaders(),
    body: JSON.stringify({
      farmId, firstName: p.firstName, lastName: p.lastName, phone: p.phoneNumber ?? "", email: p.email ?? null,
      role: "Other", salaryType: "Monthly", basePay: 0,
    }),
  })
  if (!res.ok) throw new Error(await readApiError(res, "Could not add to Staff"))
  return (await res.json()).staffId
}

/** Creates the staff record and links it to `userId`. Returns the new staff id. */
export async function createLinkedStaff(farmType: string, userId: string, p: LinkedStaffPerson): Promise<number> {
  const base = {
    firstName: p.firstName.trim(), lastName: p.lastName.trim(),
    phoneNumber: p.phoneNumber || null, email: p.email || null,
    role: "Other", salaryType: "Monthly", basePay: 0, isActive: true,
  }
  let staffId: number | undefined
  switch (farmType) {
    case "Poultry": staffId = (await createPoultryStaff(base))?.poultryStaffId; break
    case "Water": staffId = (await createWaterStaff(base))?.waterStaffId; break
    case "Generic": staffId = (await createGenericStaff(base))?.genericStaffId; break
    case "Hotel":
      // skipLogin: this person already has one -- the login just created.
      staffId = (await createHotelStaff({
        firstName: base.firstName, lastName: base.lastName, email: base.email ?? undefined, phone: base.phoneNumber ?? undefined,
        role: "Other", department: "Front Desk", salaryAmount: 0, hireDate: new Date().toISOString().slice(0, 10), skipLogin: true,
      }))?.hotelStaffId
      break
    case "Restaurant": staffId = await createRestaurantStaff(p); break
    default: throw new Error("This company type has no Staff page to add to.")
  }
  if (!staffId) throw new Error("Staff record was not created.")
  await setStaffUserLink(staffId, userId)
  return staffId
}
