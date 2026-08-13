"use client"

// Doc 3 §3: Business Setup — the org-level setup hub. Tabs only; each section
// renders its real page content inline — no links out.
//
// There used to be a Tabs / Scorecards view toggle here. Scorecards stacked all
// three panels on one scroll, which duplicated what the tabs already do, so it
// (and the one-option toggle it left behind) was removed.
//
// The sidebar's Organization Profile / Users & Permissions entries link here
// with ?tab=org|users, so the tab is deep-linkable and the sidebar highlights
// the section you're actually looking at.
import { Suspense } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { BusinessOfficeShell } from "@/components/dashboard/business-office-shell"
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs"
import { OrganizationProfilePanel } from "@/components/business-office/organization-profile-panel"
import { UsersPermissionsPanel } from "@/components/business-office/users-permissions-panel"
import { CompaniesPanel } from "@/components/business-office/companies-panel"
import { UserCog, Users, Building2 } from "lucide-react"

const SECTIONS = [
  { key: "org", icon: UserCog, title: "Organization Profile", Panel: OrganizationProfilePanel },
  { key: "users", icon: Users, title: "Employees & Users", Panel: UsersPermissionsPanel },
  { key: "companies", icon: Building2, title: "Companies", Panel: CompaniesPanel },
] as const

function BusinessSetupContent() {
  const router = useRouter()
  const searchParams = useSearchParams()

  const param = searchParams.get("tab")
  const tab = SECTIONS.some((s) => s.key === param) ? (param as string) : SECTIONS[0].key

  // Keep the URL (and therefore the sidebar highlight) in step with the tab,
  // without pushing a history entry for every click.
  const selectTab = (v: string) => router.replace(`/business-office/setup?tab=${v}`, { scroll: false })

  return (
    <BusinessOfficeShell active="settings">
      <main className="flex-1 overflow-y-auto p-4 sm:p-6 space-y-4">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">Administration</h1>
          <p className="text-slate-600">Set up your organization — your organization profile, employees and companies.</p>
        </div>

        <Tabs value={tab} onValueChange={selectTab}>
          <TabsList>
            {SECTIONS.map((s) => {
              const Icon = s.icon
              return <TabsTrigger key={s.key} value={s.key}><Icon className="h-4 w-4 mr-1.5" /> {s.title}</TabsTrigger>
            })}
          </TabsList>
          {SECTIONS.map(({ key, Panel }) => (
            <TabsContent key={key} value={key} className="pt-4">
              <Panel showHeading={false} />
            </TabsContent>
          ))}
        </Tabs>
      </main>
    </BusinessOfficeShell>
  )
}

export default function BusinessSetupPage() {
  // useSearchParams needs a Suspense boundary during prerender.
  return (
    <Suspense fallback={null}>
      <BusinessSetupContent />
    </Suspense>
  )
}
