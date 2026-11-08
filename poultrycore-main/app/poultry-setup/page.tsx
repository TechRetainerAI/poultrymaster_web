"use client"

// Farm Setup — the one place a poultry farm sets itself up.
//
//   Farm Setup                                 (title)
//   ( ) Production Setup  ( ) Business Setup   (native radios = section)
//   [tab] [tab] [tab] …                        (tabs of that section)
//   One-line description ........ [actions]   (the view's own primary buttons)
//   the full setup view                        (same component as its standalone page)
//
// The URL is the single source of truth: ?section=production|business&tab=<key>.
// Radios and tabs push a new URL (so Back / Forward walk the selections); the
// rendered view is derived from the URL alone. Old ?step= links are mapped to
// the matching tab.
//
// Each tab renders the standalone page's own view from components/setup-views/
// inside a SetupEmbedProvider: the view drops its page shell and title, and its
// primary actions are portalled into the action slot beside the description.
// Lists, dialogs, filters, validation and API calls are the same code as the
// standalone route, so the two stay identical.

import { Suspense, useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react"
import { usePathname, useRouter, useSearchParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Loader2 } from "lucide-react"
import { useLogout } from "@/hooks/use-logout"
import { usePermissions } from "@/hooks/use-permissions"
import { useAuthStore } from "@/lib/store/auth-store"
import { isFinancialNavItemVisible } from "@/lib/utils/financial-nav-access"
import { cn } from "@/lib/utils"
import { SetupEmbedProvider } from "@/components/setup/setup-embed"
import {
  resolveSetupLocation, setupHref, SETUP_SECTIONS,
  type SetupSection, type SetupTabKey,
} from "@/lib/nav/poultry-setup-tabs"

import { CompanySettingsForm } from "@/components/setup-views/poultry-company-settings"
import { HousesPage } from "@/components/setup-views/houses"
import { FlocksPage } from "@/components/setup-views/flocks"
import { FlockBatchesPage } from "@/components/setup-views/flock-batch"
import { PoultryProductsPage } from "@/components/setup-views/poultry-products"
import { PoultryFeedFormulasPage } from "@/components/setup-views/poultry-feed-formulas"
import { EggPickSettingsPage } from "@/components/setup-views/egg-pick-settings"
import { PoultryRawMaterialsPage } from "@/components/setup-views/poultry-supply-purchases"
import { CustomersPage } from "@/components/setup-views/customers"
import { SuppliersPage } from "@/components/setup-views/suppliers"
import { PoultryFinancialSettingsPage } from "@/components/setup-views/poultry-financial-settings"
import { PoultryCashAccountsPage } from "@/components/setup-views/poultry-cash-accounts"
import { PoultryDriversPage } from "@/components/setup-views/poultry-drivers"
import { PoultryVehiclesPage } from "@/components/setup-views/poultry-vehicles"
import { PoultryRoutesPage } from "@/components/setup-views/poultry-routes"
import { PoultryStaffPage } from "@/components/setup-views/poultry-staff"

/** What each tab renders. Keys, labels and descriptions live in lib/nav/poultry-setup-tabs. */
const VIEWS: Record<SetupTabKey, () => ReactNode> = {
  "company-settings": () => <CompanySettingsForm />,
  "houses": () => <HousesPage />,
  "flock-purchases": () => <FlockBatchesPage />,
  "flock-groups": () => <FlocksPage />,
  "products": () => <PoultryProductsPage />,
  "feed-formulas": () => <PoultryFeedFormulasPage />,
  "egg-settings": () => <EggPickSettingsPage />,
  "inventory": () => <PoultryRawMaterialsPage />,
  "customers": () => <CustomersPage />,
  "suppliers": () => <SuppliersPage />,
  "financial-settings": () => <PoultryFinancialSettingsPage />,
  "cash-accounts": () => <PoultryCashAccountsPage />,
  "drivers": () => <PoultryDriversPage />,
  "vehicles": () => <PoultryVehiclesPage />,
  "routes": () => <PoultryRoutesPage />,
  "staff": () => <PoultryStaffPage />,
}

const LEAVE_PROMPT = "You have unsaved changes on this tab. Leave without saving them?"

function FarmSetupInner() {
  const router = useRouter()
  const pathname = usePathname()
  const searchParams = useSearchParams()
  const logout = useLogout()
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") router.replace("/dashboard")
  }, [activeFarmType, router])

  // Which tabs this user may open: the same flags the Setup menu uses.
  const { featureAccess, isAdmin } = permissions
  const allowed = useCallback((key: SetupTabKey): boolean => {
    const money = (href: string) => isFinancialNavItemVisible(href, featureAccess, isAdmin, { tempShowPayments: true })
    switch (key) {
      case "company-settings": return featureAccess.canViewSettings
      case "feed-formulas": return featureAccess.canViewFeedProduction
      case "egg-settings": return isAdmin
      case "customers": return money("/customers")
      case "suppliers": return money("/suppliers")
      case "financial-settings": return featureAccess.canViewFinancial
      case "cash-accounts": return money("/poultry-cash-accounts")
      case "staff": return isAdmin || featureAccess.canSeeEmployees
      default: return true
    }
  }, [featureAccess, isAdmin])

  // Resolve the URL (incl. legacy ?step=) to a section + tab the user can see.
  const sectionParam = searchParams.get("section")
  const tabParam = searchParams.get("tab")
  const stepParam = searchParams.get("step")
  const loc = useMemo(
    () => resolveSetupLocation({ section: sectionParam, tab: tabParam, step: stepParam }, allowed),
    [sectionParam, tabParam, stepParam, allowed],
  )

  // Put the normalized URL in the address bar (no new history entry) when the
  // one we were given was partial, legacy or not allowed.
  useEffect(() => {
    if (permissions.isLoading) return
    if (loc.kind === "redirect") { router.replace(loc.href); return }
    if (loc.kind !== "ok") return
    const want = setupHref(loc.section, loc.tab)
    const have = `${pathname}?${searchParams.toString()}`
    if (have !== want) router.replace(want, { scroll: false })
  }, [loc, pathname, searchParams, router, permissions.isLoading])

  // ---- unsaved changes ---------------------------------------------------
  const dirtyKeys = useRef(new Set<string>())
  const [anyDirty, setAnyDirty] = useState(false)
  const setDirty = useCallback((key: string, dirty: boolean) => {
    if (dirty) dirtyKeys.current.add(key); else dirtyKeys.current.delete(key)
    setAnyDirty(dirtyKeys.current.size > 0)
  }, [])
  useEffect(() => {
    if (!anyDirty) return
    const onBeforeUnload = (e: BeforeUnloadEvent) => { e.preventDefault(); e.returnValue = "" }
    window.addEventListener("beforeunload", onBeforeUnload)
    return () => window.removeEventListener("beforeunload", onBeforeUnload)
  }, [anyDirty])

  // Radios and tabs: ask first when the open view holds unsaved edits. A
  // cancelled confirm changes nothing — the URL, and so the view, stay put.
  const go = (section: SetupSection, tab?: SetupTabKey) => {
    if (dirtyKeys.current.size > 0 && !window.confirm(LEAVE_PROMPT)) return
    const target = tab ?? SETUP_SECTIONS[section].tabs.find((t) => allowed(t.key))?.key
    if (!target) return
    router.push(setupHref(section, target), { scroll: false })
  }

  // On a phone the tab row scrolls sideways: keep the open tab in view.
  const tabRowRef = useRef<HTMLDivElement>(null)
  const openTab = loc.kind === "ok" ? loc.tab : null
  useEffect(() => {
    tabRowRef.current?.querySelector<HTMLElement>('[data-state="active"]')
      ?.scrollIntoView({ block: "nearest", inline: "nearest" })
  }, [openTab])

  // The view portals its primary buttons into this slot.
  const [actionsEl, setActionsEl] = useState<HTMLElement | null>(null)
  const embedValue = useMemo(() => ({ actionsEl, setDirty }), [actionsEl, setDirty])

  const sectionsVisible = (Object.keys(SETUP_SECTIONS) as SetupSection[])
    .filter((s) => SETUP_SECTIONS[s].tabs.some((t) => allowed(t.key)))

  let body: ReactNode
  if (permissions.isLoading || loc.kind === "redirect") {
    body = <div className="flex items-center gap-2 p-6 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
  } else if (loc.kind === "none") {
    body = (
      <Card><CardContent className="p-8 text-center text-slate-500">
        You do not have access to any part of Farm Setup. Ask the account owner or an admin.
      </CardContent></Card>
    )
  } else {
    const section = SETUP_SECTIONS[loc.section]
    const visibleTabs = section.tabs.filter((t) => allowed(t.key))
    // Grouped tabs (Delivery) show once in the row, under the group's label.
    const topTabs = visibleTabs.filter((t, i) => !t.group || visibleTabs.findIndex((x) => x.group === t.group) === i)
    const current = section.tabs.find((t) => t.key === loc.tab)!
    const groupKids = current.group ? visibleTabs.filter((t) => t.group === current.group) : []
    const topValue = current.group ? topTabs.find((t) => t.group === current.group)!.key : current.key

    body = (
      <>
        {/* Section radios: native inputs, styled to the app. */}
        <fieldset className="mb-4 flex flex-wrap items-center gap-x-6 gap-y-2">
          <legend className="sr-only">Setup section</legend>
          {sectionsVisible.map((s) => {
            const on = s === loc.section
            return (
              <label key={s} className={cn("flex cursor-pointer items-center gap-2 text-sm font-semibold", on ? "text-amber-700" : "text-slate-800")}>
                <input type="radio" name="setup-section" value={s} checked={on}
                  onChange={() => go(s)} className="h-4 w-4 accent-amber-600" />
                {SETUP_SECTIONS[s].label}
              </label>
            )
          })}
        </fieldset>

        <div className="min-w-0 rounded-xl border border-slate-200 bg-white px-4 py-3 shadow-sm md:px-6 md:py-4">
          {/* Underlined text tabs; they scroll sideways on a phone rather than
              widening the page. */}
          {/* manual: Radix otherwise also activates on focus, which asked the
              unsaved-changes question twice for one click. */}
          <Tabs value={topValue} onValueChange={(v) => go(loc.section, v as SetupTabKey)} activationMode="manual" className="gap-0">
            <div ref={tabRowRef} className="-mx-1 overflow-x-auto">
              <TabsList className="h-auto w-max min-w-full justify-start gap-1 rounded-none border-b border-slate-200 bg-transparent p-0 px-1">
                {topTabs.map((t) => (
                  <TabsTrigger key={t.key} value={t.key}
                    className="-mb-px h-auto flex-none cursor-pointer rounded-none border-0 border-b-2 border-transparent bg-transparent px-3 py-2.5 text-sm font-normal text-slate-600 shadow-none transition-colors
                      hover:text-slate-900 data-[state=active]:border-amber-600 data-[state=active]:bg-transparent data-[state=active]:font-medium data-[state=active]:text-amber-700 data-[state=active]:shadow-none">
                    {t.group ? t.groupLabel : t.label}
                  </TabsTrigger>
                ))}
              </TabsList>
            </div>
          </Tabs>

          {/* Delivery: Drivers / Vehicles / Routes share one tab. */}
          {groupKids.length > 1 && (
            <div role="tablist" aria-label={current.groupLabel} className="mt-3 inline-flex max-w-full overflow-x-auto rounded-lg bg-slate-100 p-0.5">
              {groupKids.map((k) => (
                <button key={k.key} type="button" role="tab" aria-selected={k.key === loc.tab}
                  onClick={() => { if (k.key !== loc.tab) go(loc.section, k.key) }}
                  className={cn("whitespace-nowrap rounded-md px-3 py-1.5 text-sm transition-colors",
                    k.key === loc.tab ? "bg-white font-medium text-slate-900 shadow-sm" : "text-slate-600 hover:text-slate-900")}>
                  {k.label}
                </button>
              ))}
            </div>
          )}

          {/* One line on what this tab is for; the view's buttons sit beside it. */}
          <div className="mt-3 flex flex-col gap-3 border-b border-slate-100 pb-3 sm:flex-row sm:items-center sm:justify-between">
            <p className="text-sm text-slate-600">{current.description}</p>
            <div ref={setActionsEl} className="flex min-w-0 flex-wrap items-center gap-2 empty:hidden sm:justify-end" />
          </div>

          {/* key: a new tab or a new company remounts the view, so it loads fresh
              data (a house added a moment ago shows up in Flock groups) and no
              late reply from the previous company can land in it. */}
          <div className="mt-4 min-w-0">
            <SetupEmbedProvider value={embedValue}>
              <div key={`${activeFarmId ?? ""}:${loc.tab}`}>{VIEWS[loc.tab]()}</div>
            </SetupEmbedProvider>
          </div>
        </div>
      </>
    )
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex min-w-0 flex-1 flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto overflow-x-hidden p-4 pb-16 sm:p-6 lg:pb-6">
          <h1 className="mb-3 text-2xl font-semibold text-slate-900">Farm Setup</h1>
          {body}
        </main>
      </div>
    </div>
  )
}

export default function PoultrySetupPage() {
  // useSearchParams needs a Suspense boundary during prerender.
  return (
    <Suspense fallback={null}>
      <FarmSetupInner />
    </Suspense>
  )
}
