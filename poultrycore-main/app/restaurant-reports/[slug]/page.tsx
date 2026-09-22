"use client"

/**
 * One Restaurant report, at /restaurant-reports/<slug>.
 *
 * WHY A ROUTE PER REPORT
 * The old page was a single tab bar whose links carried `?tab=<slug>` — a query
 * string it never read, so every report in the mega-menu opened on Overview and
 * no report could be linked, bookmarked or sent to anyone. A real route fixes
 * that by construction, and it matches the shape hotel-reports already uses.
 *
 * WHAT THIS FILE ACTUALLY DOES
 * Very little, deliberately. It resolves the slug, owns the date range, runs the
 * definition's loader, and hands the result to the shell. Everything specific to
 * a given report lives in the registry; everything shared lives in the shell.
 */

import Link from "next/link"
import { useCallback, useEffect, useMemo, useState } from "react"
import { useParams, useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { BarChart3, ArrowLeft } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { usePermissions } from "@/hooks/use-permissions"
import {
  findRestaurantReport, LEGACY_SLUG_REDIRECTS,
} from "@/lib/reports/restaurant-reports-config"
import {
  ReportShell, defaultReportRange, type ReportExport, type ReportRange,
} from "@/components/reports/module-report-shell"
import {
  ReportTable, StatGrid, buildExport, makeFmt, type LoadResult,
} from "@/components/reports/report-table"
import { REPORT_REGISTRY, deriveMetricRows } from "@/components/restaurant/reports/registry"
import { getRestaurantProfile } from "@/lib/api/restaurant"

export default function RestaurantReportPage() {
  const params = useParams<{ slug: string }>()
  const slug = params?.slug ?? ""
  const router = useRouter()
  const logout = useLogout()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmName = useAuthStore((s) => s.activeFarmName)
  const permissions = usePermissions()

  const match = findRestaurantReport(slug)
  const def = REPORT_REGISTRY[slug]

  const [range, setRange] = useState<ReportRange>(defaultReportRange)
  const [result, setResult] = useState<LoadResult<any, any> | null>(null)
  const [loading, setLoading] = useState(true)
  const [exportData, setExportData] = useState<ReportExport | null>(null)

  const [profile, setProfile] = useState<{
    name: string; address?: string; phone?: string; currency: string
  }>({ name: activeFarmName || "Restaurant", currency: "" })

  // A slug from the old catalog lands on whatever replaced it rather than a
  // 404. Bookmarks and any stale links keep working.
  useEffect(() => {
    if (!match && LEGACY_SLUG_REDIRECTS[slug]) {
      router.replace(`/restaurant-reports/${LEGACY_SLUG_REDIRECTS[slug]}`)
    }
  }, [match, slug, router])

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") router.replace("/dashboard")
  }, [activeFarmType, router])

  // Branding and currency for the exports. A failure here is not fatal: the
  // report still renders, it just falls back to the company name with no
  // currency prefix rather than blocking on a settings call.
  useEffect(() => {
    if (activeFarmType !== "Restaurant") return
    let cancelled = false
    getRestaurantProfile()
      .then((p) => {
        if (cancelled) return
        setProfile({
          name: p.restaurantName || activeFarmName || "Restaurant",
          address: [p.address, p.city, p.country].filter(Boolean).join(", ") || undefined,
          phone: p.phone ?? undefined,
          currency: p.defaultCurrency || "",
        })
      })
      .catch(() => {})
    return () => { cancelled = true }
  }, [activeFarmType, activeFarmName])

  const fmt = useMemo(() => makeFmt(profile.currency), [profile.currency])

  const load = useCallback(async () => {
    if (!def) return
    setLoading(true)
    try {
      const r = await def.load(range)
      setResult(r)
    } catch (e: any) {
      setResult({ rows: [] })
      toast({ title: "Could not load report", description: e?.message, variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }, [def, range, toast])

  useEffect(() => {
    if (activeFarmType !== "Restaurant" || !def) return
    load()
  }, [activeFarmType, def, load])

  // The three single-object reports present the same object as a table. Rows are
  // derived here rather than in the loader because formatting needs the currency,
  // which arrives from the profile call on its own schedule.
  const shaped: LoadResult<any, any> | null = useMemo(() => {
    if (!result) return null
    const derived = deriveMetricRows(slug, result.meta, fmt)
    return derived.length > 0 ? { ...result, rows: derived } : result
  }, [result, slug, fmt])

  // Keep the shell's export buttons pointed at exactly what is on screen.
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

  // Reports expose revenue, margins and per-waiter performance. The old page had
  // no gate at all beyond the farm-type check, so any signed-in waiter or driver
  // could read the takings.
  if (!permissions.isAdmin && !permissions.featureAccess.canViewReports) {
    return frame(
      <Card className="max-w-lg">
        <CardContent className="p-6 space-y-2">
          <h1 className="text-lg font-semibold text-slate-900">Reports are restricted</h1>
          <p className="text-sm text-slate-600">
            Your account does not have permission to view restaurant reports. An administrator can
            grant this under Users &amp; Permissions.
          </p>
        </CardContent>
      </Card>
    )
  }

  if (!match || !def) {
    // A legacy slug is mid-redirect; anything else is genuinely unknown.
    if (LEGACY_SLUG_REDIRECTS[slug]) return frame(null)
    return frame(
      <div className="max-w-lg space-y-4">
        <Button asChild variant="outline" size="sm">
          <Link href="/restaurant-reports"><ArrowLeft className="h-4 w-4 mr-1" /> All reports</Link>
        </Button>
        <Card>
          <CardContent className="p-6 space-y-3">
            <div className="flex items-center gap-3">
              <div className="rounded-lg bg-rose-100 p-2"><BarChart3 className="h-6 w-6 text-rose-700" /></div>
              <h1 className="text-xl font-semibold text-slate-900">Report not found</h1>
            </div>
            <p className="text-sm text-slate-600">
              No report matches <span className="font-mono">{slug}</span>. Pick one from the{" "}
              <Link href="/restaurant-reports" className="text-rose-600 hover:underline">reports catalog</Link>.
            </p>
          </CardContent>
        </Card>
      </div>
    )
  }

  const summaryCards = shaped && def.summary ? def.summary(shaped, fmt) : []

  return frame(
    <ReportShell
      report={match.report}
      group={match.group}
      range={range}
      onRangeChange={setRange}
      loading={loading}
      exportData={exportData}
      propertyName={profile.name}
      propertyAddress={profile.address}
      propertyPhone={profile.phone}
      currency={profile.currency}
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
