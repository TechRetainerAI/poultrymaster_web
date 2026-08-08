"use client"

// Business Office → Companies (Prompt 4) — standalone page. The content lives in
// CompaniesPanel so Business Setup can render the same thing in a tab.
import { BusinessOfficeShell } from "@/components/dashboard/business-office-shell"
import { CompaniesPanel } from "@/components/business-office/companies-panel"

export default function BusinessOfficeCompaniesPage() {
  return (
    <BusinessOfficeShell active="companies">
      <main className="flex-1 overflow-auto p-4 sm:p-6">
        <CompaniesPanel />
      </main>
    </BusinessOfficeShell>
  )
}
