"use client"

// Doc 3 §8: Organization Profile — standalone page. The content lives in
// OrganizationProfilePanel so Business Setup can render the same thing in a tab.
import { BusinessOfficeShell } from "@/components/dashboard/business-office-shell"
import { OrganizationProfilePanel } from "@/components/business-office/organization-profile-panel"

export default function OrganizationProfilePage() {
  return (
    <BusinessOfficeShell active="org">
      <main className="flex-1 overflow-y-auto p-4 sm:p-6">
        <OrganizationProfilePanel />
      </main>
    </BusinessOfficeShell>
  )
}
