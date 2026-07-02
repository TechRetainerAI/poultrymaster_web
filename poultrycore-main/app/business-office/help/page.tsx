"use client"

// Business Office → Help Center (Prompt 4). Stays inside the Business Office shell.

import { Card, CardContent } from "@/components/ui/card"
import { Briefcase, Building2, Users, Megaphone, ArrowRight } from "lucide-react"
import Link from "next/link"
import { BusinessOfficeShell } from "@/components/dashboard/business-office-shell"

const TOPICS = [
  { icon: Briefcase, title: "What is the Business Office?", body: "Your organization headquarters. From here you see every company you own or can access, open any of them, and manage people — without being stuck inside one company." },
  { icon: Building2, title: "Opening & creating companies", body: "Click Open on a company card to work inside it (Company Mode). Admins can create new companies with “New company” — they're filed under your Business Office automatically." },
  { icon: Users, title: "Users & Permissions", body: "Admins add employees and grant or remove admin access from Users & Permissions. Staff only see the companies and tasks they're assigned to." },
  { icon: Megaphone, title: "Announcements", body: "Admins can post announcements to everyone, admins-only, or staff-only. Users can dismiss or acknowledge them right on the Business Office home." },
]

export default function BusinessOfficeHelpPage() {
  return (
    <BusinessOfficeShell active="help">
      <main className="flex-1 overflow-auto p-4 sm:p-6 space-y-5">
        <div>
          <h1 className="text-2xl font-semibold text-slate-900">Help Center</h1>
          <p className="text-sm text-slate-500">Quick answers about your Business Office.</p>
        </div>

        <div className="grid sm:grid-cols-2 gap-4">
          {TOPICS.map((t) => {
            const Icon = t.icon
            return (
              <Card key={t.title}><CardContent className="p-5">
                <div className="flex items-center gap-2.5 mb-2">
                  <span className="h-9 w-9 grid place-items-center rounded-lg bg-orange-100 text-orange-700"><Icon className="h-5 w-5" /></span>
                  <h3 className="font-semibold text-slate-900">{t.title}</h3>
                </div>
                <p className="text-sm text-slate-600">{t.body}</p>
              </CardContent></Card>
            )
          })}
        </div>

        <Card><CardContent className="p-5 flex items-center justify-between gap-3 flex-wrap">
          <div>
            <h3 className="font-semibold text-slate-900">Need more help?</h3>
            <p className="text-sm text-slate-600">Open a company to access its detailed help, or go back to your Business Office.</p>
          </div>
          <Link href="/business-office" className="inline-flex items-center gap-1.5 text-sm font-semibold text-orange-600 hover:text-orange-700">Back to Business Office <ArrowRight className="h-4 w-4" /></Link>
        </CardContent></Card>
      </main>
    </BusinessOfficeShell>
  )
}
