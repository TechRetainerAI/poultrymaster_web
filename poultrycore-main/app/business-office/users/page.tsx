"use client"

// Doc 3 §6-7: Business Office → Users & Permissions — standalone page. The
// content lives in UsersPermissionsPanel so Business Setup can render the same
// thing in a tab.
import { BusinessOfficeShell } from "@/components/dashboard/business-office-shell"
import { UsersPermissionsPanel } from "@/components/business-office/users-permissions-panel"

export default function BusinessOfficeUsersPage() {
  return (
    <BusinessOfficeShell active="users">
      <main className="flex-1 overflow-y-auto p-4 sm:p-6">
        <UsersPermissionsPanel />
      </main>
    </BusinessOfficeShell>
  )
}
