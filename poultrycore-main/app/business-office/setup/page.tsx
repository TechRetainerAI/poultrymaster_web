"use client"

// Doc 3 §3: Business Setup — the org-level setup hub (Employees, Companies, Org Profile).
import Link from "next/link"
import { BusinessOfficeShell } from "@/components/dashboard/business-office-shell"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs"
import { useViewMode } from "@/hooks/use-view-mode"
import { ViewModeToggle } from "@/components/ui/view-mode-toggle"
import { Users, Building2, UserCog, Clock, ArrowRight } from "lucide-react"

const CARDS = [
  { icon: Users, title: "Employees & Users", desc: "Manage all employees across your organization and assign access to companies.", href: "/business-office/users", cta: "Manage Employees", color: "bg-indigo-600" },
  { icon: Building2, title: "Companies", desc: "Create, edit, and manage companies under this Business Office.", href: "/business-office/companies", cta: "Manage Companies", color: "bg-emerald-600" },
  { icon: UserCog, title: "Organization Profile", desc: "Edit your organization/owner details — name, contact, currency and country.", href: "/business-office/organization-profile", cta: "Edit Organization", color: "bg-orange-600" },
  { icon: Clock, title: "Egg Pick Times", desc: "Set the time each egg pick (1st–4th) represents for this farm, and enable the 4th pick.", href: "/business-office/egg-pick-settings", cta: "Configure Pick Times", color: "bg-teal-600" },
]

export default function BusinessSetupPage() {
  const vm = useViewMode()

  const Cards = () => (
    <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
      {CARDS.map((c) => {
        const Icon = c.icon
        return (
          <Card key={c.title} className="overflow-hidden">
            <div className={`${c.color} h-1.5`} />
            <CardContent className="p-5 space-y-3">
              <span className={`inline-flex h-10 w-10 items-center justify-center rounded-lg ${c.color} text-white`}><Icon className="h-5 w-5" /></span>
              <h2 className="text-lg font-semibold text-slate-900">{c.title}</h2>
              <p className="text-sm text-slate-600 min-h-[40px]">{c.desc}</p>
              <Link href={c.href}><Button variant="outline" className="w-full justify-between">{c.cta} <ArrowRight className="h-4 w-4" /></Button></Link>
            </CardContent>
          </Card>
        )
      })}
    </div>
  )

  return (
    <BusinessOfficeShell active="settings">
      <main className="flex-1 overflow-y-auto p-4 sm:p-6 space-y-4">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">Business Setup</h1>
          <p className="text-slate-600">Set up your organization — employees, companies and your organization profile.</p>
        </div>

        <ViewModeToggle vm={vm} />

        {vm.mode === "table" ? (
          <Card><CardContent className="p-4">
            <div className="overflow-x-auto">
              <Table>
                <TableHeader><TableRow><TableHead>Area</TableHead><TableHead>What you can do</TableHead><TableHead className="text-right">Action</TableHead></TableRow></TableHeader>
                <TableBody>
                  {CARDS.map((c) => {
                    const Icon = c.icon
                    return (
                      <TableRow key={c.title}>
                        <TableCell><span className="inline-flex items-center gap-2 font-medium text-slate-900"><span className={`inline-flex h-7 w-7 items-center justify-center rounded-md ${c.color} text-white`}><Icon className="h-4 w-4" /></span>{c.title}</span></TableCell>
                        <TableCell className="text-sm text-slate-600 max-w-md">{c.desc}</TableCell>
                        <TableCell className="text-right"><Link href={c.href}><Button variant="outline" size="sm">{c.cta} <ArrowRight className="h-4 w-4 ml-1" /></Button></Link></TableCell>
                      </TableRow>
                    )
                  })}
                </TableBody>
              </Table>
            </div>
          </CardContent></Card>
        ) : vm.asTabs ? (
          <Tabs defaultValue={CARDS[0].title}>
            <TabsList>{CARDS.map((c) => <TabsTrigger key={c.title} value={c.title}>{c.title}</TabsTrigger>)}</TabsList>
            {CARDS.map((c) => {
              const Icon = c.icon
              return (
                <TabsContent key={c.title} value={c.title}>
                  <Card className="overflow-hidden">
                    <div className={`${c.color} h-1.5`} />
                    <CardContent className="p-6 space-y-3 max-w-xl">
                      <span className={`inline-flex h-10 w-10 items-center justify-center rounded-lg ${c.color} text-white`}><Icon className="h-5 w-5" /></span>
                      <h2 className="text-lg font-semibold text-slate-900">{c.title}</h2>
                      <p className="text-sm text-slate-600">{c.desc}</p>
                      <Link href={c.href}><Button variant="outline" className="justify-between">{c.cta} <ArrowRight className="h-4 w-4 ml-1" /></Button></Link>
                    </CardContent>
                  </Card>
                </TabsContent>
              )
            })}
          </Tabs>
        ) : (
          <Cards />
        )}
      </main>
    </BusinessOfficeShell>
  )
}
