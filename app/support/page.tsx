"use client"

import Link from "next/link"
import { useRouter } from "next/navigation"
import { useEffect, useState } from "react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { appConfig } from "@/config/app.config"
import { MessageCircle, Mail, Shield, BookOpen, Stethoscope, Phone } from "lucide-react"

export default function SupportPage() {
  const router = useRouter()
  const [deployStamp, setDeployStamp] = useState<string | null>(null)
  const supportEmail = appConfig.support.email
  const mailSubject = encodeURIComponent("Poultry Master — support request")
  const mailBody = encodeURIComponent(
    "Hi Poultry Master team,\n\n(Farm name and a short description of your question)\n\n",
  )
  const mailtoHref = `mailto:${supportEmail}?subject=${mailSubject}&body=${mailBody}`

  useEffect(() => {
    let cancelled = false
    fetch(`/deploy-stamp.txt?cb=${Date.now()}`, { cache: "no-store" })
      .then((res) => (res.ok ? res.text() : Promise.reject()))
      .then((t) => {
        if (!cancelled) setDeployStamp(t.trim())
      })
      .catch(() => {
        if (!cancelled) setDeployStamp(null)
      })
    return () => {
      cancelled = true
    }
  }, [])

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
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-auto overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4">
          <div className="max-w-3xl mx-auto space-y-6">
            <div className="text-center space-y-2">
              <div className="w-16 h-16 bg-teal-100 rounded-2xl flex items-center justify-center mx-auto">
                <MessageCircle className="w-8 h-8 text-teal-700" />
              </div>
              <h1 className="text-2xl sm:text-3xl font-bold text-slate-900">Talk to Poultry Master</h1>
              <p className="text-slate-600 text-sm sm:text-base max-w-xl mx-auto">
                Message the product team about billing, bugs, ideas, or onboarding. This is separate from chatting with
                people on <strong>your farm</strong> (use the blue chat button for farm team messages).
              </p>
            </div>

            <Card className="border-teal-200 bg-teal-50/40">
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-teal-900 text-lg">
                  <Shield className="w-5 h-5 shrink-0" />
                  Privacy
                </CardTitle>
                <CardDescription className="text-teal-900/80 text-sm leading-relaxed">
                  Email goes only to our support mailbox. We do not show your message to other farms. In the app, your
                  flock and financial data stay scoped to your farm account; other customers do not browse your charts.
                  Broader benchmarks or trends, if we ever show them, would use aggregated or anonymized data only.
                  Aggregated product insights may be used to improve the app; your personal account details stay in
                  normal support handling unless you choose to share them in the email.
                </CardDescription>
              </CardHeader>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-lg">
                  <Mail className="w-5 h-5 text-slate-600" />
                  Contact
                </CardTitle>
                <CardDescription>
                  Opens your email app. Override the address with{" "}
                  <code className="text-xs bg-slate-100 px-1 rounded">NEXT_PUBLIC_SUPPORT_EMAIL</code> when you deploy.
                </CardDescription>
              </CardHeader>
              <CardContent className="flex flex-col sm:flex-row gap-3 sm:items-center">
                <p className="text-sm text-slate-700 flex-1">
                  <span className="font-medium text-slate-900">{supportEmail}</span>
                </p>
                <Button asChild className="bg-teal-600 hover:bg-teal-700 shrink-0">
                  <a href={mailtoHref}>
                    <Mail className="w-4 h-4 mr-2" />
                    Email the team
                  </a>
                </Button>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-lg">
                  <Phone className="w-5 h-5 text-slate-600" />
                  Phone
                </CardTitle>
                <CardDescription>Use if you need a quick call; email is best for account-specific details.</CardDescription>
              </CardHeader>
              <CardContent className="text-sm text-slate-700 space-y-1">
                <p>+1 (917) 420-2946</p>
                <p>0533431086</p>
              </CardContent>
            </Card>

            <div className="grid gap-3 sm:grid-cols-2">
              <Card className="hover:border-indigo-200 transition-colors">
                <CardHeader className="pb-2">
                  <CardTitle className="text-base flex items-center gap-2">
                    <BookOpen className="w-4 h-4 text-indigo-600" />
                    Help Center
                  </CardTitle>
                  <CardDescription className="text-xs">How-to, FAQs, and feature guides.</CardDescription>
                </CardHeader>
                <CardContent>
                  <Button variant="outline" size="sm" asChild className="w-full">
                    <Link href="/help">Open Help Center</Link>
                  </Button>
                </CardContent>
              </Card>
              <Card className="hover:border-amber-200 transition-colors">
                <CardHeader className="pb-2">
                  <CardTitle className="text-base flex items-center gap-2">
                    <Stethoscope className="w-4 h-4 text-amber-600" />
                    Health records
                  </CardTitle>
                  <CardDescription className="text-xs">Flock health, treatments, and vet notes.</CardDescription>
                </CardHeader>
                <CardContent>
                  <Button variant="outline" size="sm" asChild className="w-full">
                    <Link href="/health">Open Health</Link>
                  </Button>
                </CardContent>
              </Card>
            </div>

            {deployStamp ? (
              <p className="text-center text-xs text-slate-400">
                This server&apos;s build time (UTC):{" "}
                <span className="font-mono text-slate-600">{deployStamp}</span>. After you deploy, this should update;
                if it does not, traffic may still be on an old revision or you are not on this Cloud Run URL.
              </p>
            ) : null}

            <p className="text-center text-xs text-slate-500">
              In-app <strong>farm chat</strong> (floating icon) is only for users on your farm, not the Poultry Master
              company inbox.
            </p>
          </div>
        </main>
      </div>
    </div>
  )
}
