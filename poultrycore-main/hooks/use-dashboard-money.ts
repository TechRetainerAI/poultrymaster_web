"use client"

import { usePermissions } from "@/hooks/use-permissions"
import { useAuthStore } from "@/lib/store/auth-store"
import { moduleForCompanyType } from "@/lib/iam/page-catalog"

/**
 * May this person see the money figures on the dashboard (sales, expenses,
 * profit, cash)? `<module>.dashboard-financials.view` — "Dashboard money
 * figures" in Staff Page Access. Operational cards (eggs, rooms, stock) do not
 * ask; only revenue/profit/cash cards and charts do (test 20). The Farm API
 * blanks the same figures server-side once enforcement is on.
 *
 * Before per-company page access is live this is always true: dashboards
 * behave exactly as they did.
 */
export function useDashboardMoney(): boolean {
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  if (!permissions.pageAccess) return true
  const module = moduleForCompanyType(activeFarmType) ?? "poultry"
  return permissions.can(`${module}.dashboard-financials.view`)
}
