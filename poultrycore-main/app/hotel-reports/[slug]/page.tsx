"use client"

/**
 * /hotel-reports/<slug> — two jobs in one file.
 *
 * 1. THE TEN SERVER-SIDE REPORTS added in migration 299. If the slug is in
 *    HOTEL_REPORT_REGISTRY, this renders it through the shared report shell:
 *    date range, PDF, CSV and print, all for free.
 *
 * 2. THE ORIGINAL CATCH-ALL behaviour, unchanged. The 17 pre-existing hotel
 *    reports each own a directory under app/hotel-reports/, and Next resolves a
 *    real directory BEFORE this dynamic segment — so none of them reach this
 *    file and none of them changed. What still lands here is an unknown slug, or
 *    a catalog entry marked "stub", and both are handled exactly as before.
 */

import Link from "next/link"
import { useCallback, useEffect, useMemo, useState } from "react"
import { useParams, useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { ArrowLeft, BarChart3 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import { HOTEL_REPORT_GROUPS } from "@/lib/reports/hotel-reports-config"
import type { HotelReport, HotelReportGroup } from "@/lib/reports/hotel-reports-config"
import {
  ReportShell, defaultReportRange, type ReportExport, type ReportRange,
} from "@/components/reports/module-report-shell"
import {
  ReportTable, StatGrid, buildExport, makeFmt, type LoadResult,
} from "@/components/reports/report-table"
import { HOTEL_REPORT_REGISTRY, deriveHotelMetricRows } from "@/components/hotel/reports/registry"
import { getHotelProfile } from "@/lib/api/hotel"

/** Look up a report by slug across all groups. */
function findReport(slug: string): { report: HotelReport; group: HotelReportGroup } | null {
  for (const g of HOTEL_REPORT_GROUPS) {
    const r = g.reports.find((r) => r.slug === slug)
    if (r) return { report: r, group: g }
  }
  return null
}

export default function HotelReportRoutePage() {
  const params = useParams<{ slug: string }>()
  const slug = params?.slug ?? ""
  const router = useRouter()
  const logout = useLogout()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmName = useAuthStore((s) => s.activeFarmName)
  const permissions = usePermissions()

  const match = findReport(slug)
  const def = HOTEL_REPORT_REGISTRY[slug]

  const [range, setRange] = useState<ReportRange>(defaultReportRange)
  const [result, setResult] = useState<LoadResult<any, any> | null>(null)
  const [loading, setLoading] = useState(true)
  const [exportData, setExportData] = useState<ReportExport | null>(null)
  const [profile, setProfile] = useState<{
    name: string; address?: string; phone?: string; currency: string
  }>({ name: activeFarmName || "Hotel", currency: "" })

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Hotel") router.replace("/dashboard")
  }, [activeFarmType, router])

  // Branding and currency for the exports. A failure is not fatal — the report
  // still renders, it just falls back to the company name with no currency.
  useEffect(() => {
    if (!def || activeFarmType !== "Hotel") return
    let cancelled = false
    getHotelProfile()
      .then((p) => {
        if (cancelled) return
        setProfile({
          name: p.hotelName || activeFarmName || "Hotel",
          address: [p.address, p.city, p.country].filter(Boolean).join(", ") || undefined,
          phone: p.phone ?? undefined,
          currency: p.defaultCurrency || "",
        })
      })
      .catch(() => {})
    return () => { cancelled = true }
  }, [def, activeFarmType, activeFarmName])

  const fmt = useMemo(() => makeFmt(profile.currency), [profile.currency])

  const load = useCallback(async () => {
    if (!def) return
    setLoading(true)
    try {
      setResult(await def.load(range))
    } catch (e: any) {
      setResult({ rows: [] })
      toast({ title: "Could not load report", description: e?.message, variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }, [def, range, toast])

  useEffect(() => {
    if (activeFarmType !== "Hotel" || !def) return
    load()
  }, [activeFarmType, def, load])

  const shaped: LoadResult<any, any> | null = useMemo(() => {
    if (!result) return null
    const derived = deriveHotelMetricRows(slug, result.meta, fmt)
    return derived.length > 0 ? { ...result, rows: derived } : result
  }, [result, slug, fmt])

  useEffect(() => {
    if (!def || !shaped) { setExportData(null); return }
    setExportData(buildExport(def, shaped, fmt))
  }, [def, shaped, fmt])

  const frame = (body: React.ReactNode) => (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 min-w-0">{body}</main>
      </div>
    </div>
  )

  const backLink = (
    <Button asChild variant="outline" size="sm">
      <Link href="/hotel-reports"><ArrowLeft className="h-4 w-4 mr-1" /> Reports</Link>
    </Button>
  )

  // ---- The ten server-side reports ----------------------------------------
  if (match && def) {
    // These expose revenue, margins, profit and per-attendant performance, so
    // they follow the same reporting flag the rest of the app uses.
    if (!permissions.isAdmin && !permissions.featureAccess.canViewReports) {
      return frame(
        <Card className="max-w-lg">
          <CardContent className="p-6 space-y-2">
            <h1 className="text-lg font-semibold text-slate-900">Reports are restricted</h1>
            <p className="text-sm text-slate-600">
              Your account does not have permission to view hotel reports. An administrator can grant
              this under Users &amp; Permissions.
            </p>
          </CardContent>
        </Card>
      )
    }

    const summaryCards = shaped && def.summary ? def.summary(shaped, fmt) : []
    // `dateMode` is optional on the catalog type, because the 17 original
    // reports own their own filters and never reach the shell. Anything that
    // does reach it without one is a range report.
    const shellReport = { ...match.report, dateMode: match.report.dateMode ?? "range" as const }

    return frame(
      <ReportShell
        report={shellReport}
        group={match.group}
        range={range}
        onRangeChange={setRange}
        loading={loading}
        exportData={exportData}
        propertyName={profile.name}
        propertyAddress={profile.address}
        propertyPhone={profile.phone}
        currency={profile.currency}
        accent="violet"
        indexHref="/hotel-reports"
        enableEmail
      >
        <div className="space-y-4">
          {summaryCards.length > 0 && <StatGrid cards={summaryCards} />}
          {shaped && def.panel?.(shaped, fmt)}
          {shaped && <ReportTable def={def} result={shaped} fmt={fmt} />}
        </div>
      </ReportShell>
    )
  }

  // ---- Original catch-all behaviour, unchanged -----------------------------

  if (!match) {
    return frame(
      <>
        <div className="mb-4">{backLink}</div>
        <Card>
          <CardContent className="p-6 space-y-3">
            <div className="flex items-center gap-3">
              <div className="rounded-lg bg-violet-100 p-2">
                <BarChart3 className="h-6 w-6 text-violet-700" />
              </div>
              <h1 className="text-xl font-semibold text-slate-900">Report not found</h1>
            </div>
            <p className="text-sm text-slate-600 max-w-prose">
              No report matches the slug <span className="font-mono">{slug}</span>. Please check the
              URL or return to the{" "}
              <Link href="/hotel-reports" className="text-violet-600 hover:underline">reports catalog</Link>.
            </p>
          </CardContent>
        </Card>
      </>
    )
  }

  const { report, group } = match

  // A "ready" report should have its own directory, which Next would have
  // resolved before this file. Reaching here means the page is missing.
  if (report.status === "ready") {
    return frame(
      <>
        <div className="mb-4">{backLink}</div>
        <Card>
          <CardContent className="p-6 space-y-3">
            <div className="flex items-center gap-3">
              <div className="rounded-lg bg-violet-100 p-2">
                <BarChart3 className="h-6 w-6 text-violet-700" />
              </div>
              <h1 className="text-xl font-semibold text-slate-900">Report not found</h1>
            </div>
            <p className="text-sm text-slate-600 max-w-prose">
              The <span className="font-medium">{report.title}</span> report page has not been created
              yet. Return to the{" "}
              <Link href="/hotel-reports" className="text-violet-600 hover:underline">reports catalog</Link>.
            </p>
          </CardContent>
        </Card>
      </>
    )
  }

  // Stub — "coming soon".
  return frame(
    <>
      <div className="mb-4">{backLink}</div>
      <Card>
        <CardContent className="p-6 space-y-3">
          <div className="flex items-center gap-3">
            <div className={`rounded-lg p-2 ${group.color}`}>
              <report.icon className="h-6 w-6 text-white" />
            </div>
            <div>
              <h1 className="text-xl font-semibold text-slate-900">{report.title}</h1>
              <Badge variant="outline" className="text-[10px] uppercase mt-1">Coming soon</Badge>
            </div>
          </div>
          <p className="text-sm text-slate-600 max-w-prose">
            {report.description}. This report is in the catalog but hasn&apos;t been built out yet.
          </p>
          <p className="text-sm text-slate-600 max-w-prose">
            In the meantime, check out other reports from the{" "}
            <Link href="/hotel-reports" className="text-violet-600 hover:underline">reports catalog</Link>.
          </p>
        </CardContent>
      </Card>
    </>
  )
}
