"use client"

// Who may create a company. Mirrors CompanyService.CreateAsync in the Login API.
// (Setup pages in general are gated by lib/nav/setup-admin-routes +
// SetupAccessGuard on permissions.isAdmin.)

import { usePermissions } from "@/hooks/use-permissions"
import { useAuthStore } from "@/lib/store/auth-store"

/** Owns at least one company. Some older OWNER accounts carry IsStaff, so the
 *  staff flag alone is not trusted to mean "employee". */
function useOwnsACompany(): boolean {
  const userId = useAuthStore((s) => s.user?.id)
  const companies = useAuthStore((s) => s.companies)
  const me = userId || (typeof window !== "undefined" ? localStorage.getItem("userId") : null)
  return !!me && companies.some((c) => c.ownerUserId === me)
}

/** Creating a company makes the caller its OWNER, so an employee doing it would
 *  end up with a company outside the real owner's account. Owners only. */
export function useCanCreateCompany(): boolean {
  const { isStaff, isLoading } = usePermissions()
  const owns = useOwnsACompany()
  if (isLoading) return false
  return !isStaff || owns
}
