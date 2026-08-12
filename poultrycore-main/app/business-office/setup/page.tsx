"use client"

// Doc 3 §3: Business Setup — the org-level setup hub. Two views only: TABS
// (default) and SCORECARDS. Each section renders its real page content inline —
// no links out.
//
// The sidebar's Organization Profile / Users & Permissions entries link here
// with ?tab=org|users, so the tab is deep-linkable and the sidebar highlights
// the section you're actually looking at.
import { Suspense, useEffect, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { BusinessOfficeShell } from "@/components/dashboard/business-office-shell"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs"
import { OrganizationProfilePanel } from "@/components/business-office/organization-profile-panel"
import { UsersPermissionsPanel } from "@/components/business-office/users-permissions-panel"
import { CompaniesPanel } from "@/components/business-office/companies-panel"
import { UserCog, Users, Building2, LayoutGrid, Rows3 } from "lucide-react"

const SECTIONS = [
  { key: "org", icon: UserCog, title: "Organization Profile", color: "bg-orange-600", Panel: OrganizationProfilePanel },
  { key: "users", icon: Users, title: "Employees & Users", color: "bg-indigo-600", Panel: UsersPermissionsPanel },
  { key: "companies", icon: Building2, title: "Companies", color: "bg-emerald-600", Panel: CompaniesPanel },
] as const

// Page-local preference so it doesn't disturb the global vc.view.* prefs other pages share.
const VIEW_KEY = "vc.businessSetup.view"
type SetupView = "tabs" | "scorecards"

function BusinessSetupContent() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const [view, setView] = useState<SetupView>("tabs")

  const param = searchParams.get("tab")
  const tab = SECTIONS.some((s) => s.key === param) ? (param as string) : SECTIONS[0].key

  useEffect(() => {
    try {
      const saved = window.localStorage.getItem(VIEW_KEY)
      if (saved === "scorecards" || saved === "tabs") setView(saved)
    } catch { /* ignore */ }
  }, [])

  const choose = (v: SetupView) => {
    setView(v)
    try { window.localStorage.setItem(VIEW_KEY, v) } catch { /* ignore */ }
  }

  // Keep the URL (and therefore the sidebar highlight) in step with the tab,
  // without pushing a history entry for every click.
  const selectTab = (v: string) => router.replace(`/business-office/setup?tab=${v}`, { scroll: false })

  return (
    <BusinessOfficeShell active="settings">
      <main className="flex-1 overflow-y-auto p-4 sm:p-6 space-y-4">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">Main Setup</h1>
          <p className="text-slate-600">Set up your organization — your organization profile, employees and companies.</p>
        </div>

        <div className="inline-flex items-center gap-1 rounded-lg border border-slate-200 bg-white p-1">
          <Button size="sm" variant={view === "tabs" ? "default" : "ghost"} onClick={() => choose("tabs")}>
            <Rows3 className="h-4 w-4 mr-1.5" /> Tabs
          </Button>
          <Button size="sm" variant={view === "scorecards" ? "default" : "ghost"} onClick={() => choose("scorecards")}>
            <LayoutGrid className="h-4 w-4 mr-1.5" /> Scorecards
          </Button>
        </div>

        {view === "tabs" ? (
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
        ) : (
          <div className="space-y-4">
            {SECTIONS.map(({ key, icon: Icon, title, color, Panel }) => (
              <Card key={key} className="overflow-hidden">
                <div className={`${color} h-1.5`} />
                <CardContent className="p-5 space-y-4">
                  <h2 className="flex items-center gap-2 text-lg font-semibold text-slate-900">
                    <span className={`inline-flex h-8 w-8 items-center justify-center rounded-lg ${color} text-white`}><Icon className="h-4 w-4" /></span>
                    {title}
                  </h2>
                  <Panel showHeading={false} />
                </CardContent>
              </Card>
            ))}
          </div>
        )}
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
