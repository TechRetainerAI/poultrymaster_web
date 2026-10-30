// Staff <-> Employee link (migration 362). An Employee is a login (Login API);
// a Staff member is a payroll record in the company type's staff table. A
// linked pair is one person, shown on both the Employees and the Staff page.
// Creating either side still uses that side's own API; these calls only read
// and set the link.

import { farmApiUrl, getAuthHeaders, getUserContext, readApiError } from "./config"

export interface StaffUserLink { staffId: number; userId: string }

/** ?fromEmployee=<userId> on a Staff page: open New staff prefilled from that employee. */
export const FROM_EMPLOYEE_PARAM = "fromEmployee"

/** The Staff page of each company type. */
export function staffPagePath(farmType: string | null | undefined): string | null {
  switch (farmType) {
    case "Poultry": return "/poultry-staff"
    case "Water": return "/water-staff"
    case "Generic": return "/generic-staff"
    case "Hotel": return "/hotel-staff"
    case "Restaurant": return "/restaurant-staff"
    default: return null
  }
}

function farmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}

export async function getStaffUserLinks(): Promise<StaffUserLink[]> {
  const res = await fetch(farmApiUrl(`/StaffUserLink?farmId=${encodeURIComponent(farmId())}`), { headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res, "Could not load staff links"))
  return res.json()
}

/** Link a staff row to an employee login; userId null unlinks. */
export async function setStaffUserLink(staffId: number, userId: string | null): Promise<void> {
  const res = await fetch(farmApiUrl("/StaffUserLink"), {
    method: "PUT",
    headers: getAuthHeaders(),
    body: JSON.stringify({ farmId: farmId(), staffId, userId }),
  })
  if (!res.ok) throw new Error(await readApiError(res, "Could not link staff and employee"))
}
