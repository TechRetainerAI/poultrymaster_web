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
import { IamPanel } from "@/components/business-office/iam-panel"
import { UserCog, Users, Building2, KeyRound } from "lucide-react"

// Access sits after Employees & Users deliberately: you hire someone there, then
// look at what they can do here. It is additive — Employees & Users keeps its own
// permission controls, and IAM can only widen access until phase 3.
// `short` is the phone label. The full titles are far too wide for a 2-up grid
// on a 375px screen — they'd wrap to four stacked rows and push the tab strip
// past the viewport.
const SECTIONS = [
  { key: "org", icon: UserCog, title: "Organization Profile", short: "Organization", Panel: OrganizationProfilePanel },
  { key: "users", icon: Users, title: "Employees & Users", short: "Employees", Panel: UsersPermissionsPanel },
  { key: "iam", icon: KeyRound, title: "Access Management", short: "Access", Panel: IamPanel },
  { key: "companies", icon: Building2, title: "Companies", short: "Companies", Panel: CompaniesPanel },
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
          <h1 className="text-xl font-bold text-slate-900 sm:text-2xl">Administration</h1>
          <p className="text-sm text-slate-600 sm:text-base">Set up your organization — your organization profile, employees and companies.</p>
        </div>

        <Tabs value={tab} onValueChange={selectTab}>
          {/* 2×2 grid on phones, single inline row from sm up. The default list
              is w-fit + nowrap, which on a phone runs straight off the side of
              the screen and takes the whole page into horizontal scroll. */}
          <TabsList className="grid h-auto w-full grid-cols-2 gap-1 sm:inline-flex sm:h-9 sm:w-fit sm:gap-0">
            {SECTIONS.map((s) => {
              const Icon = s.icon
              return (
                <TabsTrigger key={s.key} value={s.key} className="h-9 w-full sm:h-[calc(100%-1px)] sm:w-auto">
                  <Icon className="h-4 w-4 mr-1.5" />
                  <span className="sm:hidden">{s.short}</span>
                  <span className="hidden sm:inline">{s.title}</span>
                </TabsTrigger>
              )
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
