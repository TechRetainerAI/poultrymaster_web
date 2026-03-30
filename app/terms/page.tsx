"use client"

import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"

const sections = [
  {
    title: "Use of the Platform",
    body: "Poultry Master is provided to help you manage poultry farm operations, records, and reporting. You agree to use the platform only for lawful farm management activities.",
  },
  {
    title: "Data Responsibility",
    body: "You are responsible for ensuring that data entered into your account is accurate and up to date. This includes flock data, inventory, financial data, and employee records.",
  },
  {
    title: "Privacy and Access",
    body: "Only authorized users within your farm team should have access to your account. Keep login credentials secure and update passwords when staff roles change.",
  },
  {
    title: "Service Availability",
    body: "We strive to keep the service available and reliable. Planned maintenance or unexpected outages may occur, and we continuously work to reduce interruptions.",
  },
  {
    title: "Limitation of Liability",
    body: "The platform is provided as a farm management tool. Final business decisions remain your responsibility, including production, medication, and financial actions.",
  },
  {
    title: "Updates to Terms",
    body: "These terms may be updated from time to time. Continued use of the platform after updates means you accept the revised terms and conditions.",
  },
]

export default function TermsPage() {
  const router = useRouter()

  const handleLogout = () => {
    localStorage.removeItem("auth_token")
    localStorage.removeItem("refresh_token")
    localStorage.removeItem("username")
    localStorage.removeItem("userId")
    localStorage.removeItem("farmId")
    localStorage.removeItem("farmName")
    localStorage.removeItem("isStaff")
    localStorage.removeItem("isSubscriber")
    router.push("/login")
  }

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 md:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6">
            <div className="flex items-start justify-between gap-4">
              <div>
                <h1 className="text-2xl font-bold text-slate-900">Terms & Conditions</h1>
                <p className="text-slate-600 mt-1">Please read these terms before using Poultry Master.</p>
              </div>
              <Badge variant="outline" className="text-orange-700 border-orange-300 bg-orange-50">
                Effective immediately
              </Badge>
            </div>

            <Card>
              <CardHeader>
                <CardTitle>Agreement Overview</CardTitle>
                <CardDescription>
                  This summary highlights the key terms that govern use of the platform.
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-5">
                {sections.map((section) => (
                  <section key={section.title} className="space-y-2">
                    <h2 className="text-base font-semibold text-slate-900">{section.title}</h2>
                    <p className="text-sm text-slate-700 leading-relaxed">{section.body}</p>
                  </section>
                ))}
              </CardContent>
            </Card>
          </div>
        </main>
      </div>
    </div>
  )
}
