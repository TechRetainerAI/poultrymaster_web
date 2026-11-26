"use client"

import Link from "next/link"
import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { HelpCircle, Images, PlayCircle } from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Select, SelectContent, SelectGroup, SelectItem, SelectLabel, SelectTrigger, SelectValue } from "@/components/ui/select"
import { SetupGuideCard } from "@/components/help/setup-guide-card"
import { useSearchPages } from "@/hooks/use-global-search"
import { shotsFor } from "@/lib/help/help-shots"
import type { HelpEntry } from "@/lib/help/help-types"
import { HELP_ENTRIES, toneFor } from "@/lib/help/poultry-help-content"

/**
 * Setup Guide: every picture walkthrough, on a page of its own -- setting up
 * the farm first, then the daily work.
 *
 * The walkthroughs are the shots in help-shots.json (made by
 * `npm run screenshots`), titled and grouped by their Help Center entry in
 * lib/help/poultry-help-content.ts, in the Help Center's order -- so a new
 * walkthrough appears here by itself. They are drawn by SetupGuideCard, not
 * by HelpEntryCard, so the Help Center can stop showing pictures without
 * taking them off this page. The chips and colours are the Help Center's.
 *
 * Poultry-only through the "/poultry-" prefix in CompanyTypeGuard.
 */
const GUIDES: HelpEntry[] = HELP_ENTRIES.filter((e) => shotsFor(e.id).length > 0)

export default function SetupGuidePage() {
  const router = useRouter()
  const [selectedCategory, setSelectedCategory] = useState("All")
  // As on the Help Center: every guide is open, pictures showing, and
  // `closed` holds the few someone folded away.
  const [closed, setClosed] = useState<Set<string>>(new Set())
  const [flashId, setFlashId] = useState<string | null>(null)

  // Same gate the Help Center uses: a link only for a page this user may open.
  const pages = useSearchPages()
  const openable = useMemo(() => new Set(pages.map((p) => p.href.split("?")[0])), [pages])
  // The set-up answer links to this page; here that link would point at itself.
  const canOpen = (href: string) => href !== "/poultry-setup-guide" && openable.has(href.split("?")[0])

  const categories = ["All", ...Array.from(new Set(GUIDES.map((g) => g.category)))]
  const shown = selectedCategory === "All" ? GUIDES : GUIDES.filter((g) => g.category === selectedCategory)
  const allOpen = shown.every((g) => !closed.has(g.id))

  const flip = (id: string) => (prev: Set<string>) => {
    const next = new Set(prev)
    if (!next.delete(id)) next.add(id)
    return next
  }

  // /poultry-setup-guide#add-flock opens on that guide.
  useEffect(() => {
    const go = () => {
      const id = decodeURIComponent(window.location.hash.slice(1))
      if (!GUIDES.some((g) => g.id === id)) return
      setSelectedCategory("All")
      setClosed((p) => { const n = new Set(p); n.delete(id); return n })
      setFlashId(id)
      setTimeout(() => document.getElementById(id)?.scrollIntoView({ behavior: "smooth", block: "start" }), 60)
      setTimeout(() => setFlashId(null), 2200)
    }
    go()
    window.addEventListener("hashchange", go)
    return () => window.removeEventListener("hashchange", go)
  }, [])

  const handleLogout = () => {
    for (const k of ["auth_token", "refresh_token", "username", "userId", "farmId", "farmName", "isStaff", "isSubscriber"]) {
      localStorage.removeItem(k)
    }
    router.push("/login")
  }

  const pictureCount = GUIDES.reduce((n, g) => n + shotsFor(g.id).length, 0)

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="max-w-5xl mx-auto space-y-8">
            {/* Page header: title on top, description in one row under it */}
            <div className="space-y-1">
              <h1 className="text-2xl font-bold text-slate-900">Setup Guide</h1>
              <p className="flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-slate-600">
                <span>Step-by-step guides with a picture of every step: set up your farm first, then the daily work.</span>
                <span className="inline-flex items-center gap-1.5 text-xs text-slate-500">
                  <Images className="h-3.5 w-3.5" /> {GUIDES.length} guides · {pictureCount} pictures
                </span>
              </p>
            </div>

            {/* Pick a guide: opens it below */}
            <div className="max-w-xl">
              <Select
                value=""
                onValueChange={(id) => {
                  // Same path as a shared #id link: open, scroll, ring.
                  if (window.location.hash === `#${id}`) window.dispatchEvent(new HashChangeEvent("hashchange"))
                  else window.location.hash = id
                }}
              >
                <SelectTrigger aria-label="Pick a guide" className="h-12 w-full rounded-xl bg-white text-base">
                  <SelectValue placeholder="Pick a guide..." />
                </SelectTrigger>
                <SelectContent className="max-h-80">
                  {categories.filter((c) => c !== "All").map((cat) => (
                    <SelectGroup key={cat}>
                      <SelectLabel>{cat}</SelectLabel>
                      {GUIDES.filter((g) => g.category === cat).map((g) => (
                        <SelectItem key={g.id} value={g.id}>{g.title}</SelectItem>
                      ))}
                    </SelectGroup>
                  ))}
                </SelectContent>
              </Select>
            </div>

              <div>
                {/* Section tabs: large and boxed so they read as the way to browse */}
                <div className="mb-4 flex flex-wrap items-end justify-between gap-3">
                  <div
                    role="tablist"
                    aria-label="Guide sections"
                    className="flex flex-wrap gap-2 rounded-2xl border border-slate-200 bg-white p-2 shadow-sm"
                  >
                    {categories.map((cat) => {
                      const tone = toneFor(cat === "All" ? "" : cat)
                      const on = selectedCategory === cat
                      return (
                        <Badge
                          key={cat}
                          role="tab"
                          aria-selected={on}
                          tabIndex={0}
                          variant={on ? "default" : "outline"}
                          className={`cursor-pointer rounded-xl px-4 py-2 text-sm font-semibold transition-colors ${on ? `${tone.chipOn} shadow` : tone.chip}`}
                          onClick={() => setSelectedCategory(cat)}
                          onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); setSelectedCategory(cat) } }}
                        >
                          {cat}
                          <span className={`ml-2 rounded-full px-1.5 text-xs ${on ? "bg-white/25" : "bg-slate-100 text-slate-500"}`}>
                            {cat === "All" ? GUIDES.length : GUIDES.filter((g) => g.category === cat).length}
                          </span>
                        </Badge>
                      )
                    })}
                  </div>
                  <button
                    className="text-xs font-medium text-indigo-600 hover:underline"
                    onClick={() => setClosed(allOpen ? new Set(shown.map((g) => g.id)) : new Set())}
                  >
                    {allOpen ? "Collapse all" : "Expand all"}
                  </button>
                </div>
                <div className="space-y-2">
                  {shown.map((g) => (
                    <SetupGuideCard
                      key={g.id}
                      guide={g}
                      shots={shotsFor(g.id)}
                      tone={toneFor(g.category)}
                      open={!closed.has(g.id)}
                      onToggle={() => setClosed(flip(g.id))}
                      canOpen={canOpen}
                      flash={flashId === g.id}
                    />
                  ))}
                </div>
              </div>

            {/* More help */}
            <div className="flex flex-wrap justify-center gap-2 pb-4">
              <Button asChild variant="ghost" size="sm">
                <Link href="/help"><HelpCircle className="mr-1.5 h-4 w-4" /> Help Center</Link>
              </Button>
              <Button asChild variant="ghost" size="sm">
                <Link href="/poultry-videos"><PlayCircle className="mr-1.5 h-4 w-4" /> Support Videos</Link>
              </Button>
            </div>
          </div>
        </main>
      </div>
    </div>
  )
}
