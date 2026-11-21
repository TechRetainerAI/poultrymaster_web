"use client"

import Link from "next/link"
import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { Compass, HelpCircle, Images, PlayCircle, Search, X } from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { SetupGuideCard } from "@/components/help/setup-guide-card"
import { useSearchPages } from "@/hooks/use-global-search"
import { prepareHelpIndex, searchHelp } from "@/lib/help/help-search"
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
  const [searchQuery, setSearchQuery] = useState("")
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

  // Search the walkthroughs themselves: the title, keywords and every
  // picture's caption (not the Help Center's written answer).
  const index = useMemo(
    () => prepareHelpIndex(GUIDES.map((g) => ({ ...g, body: shotsFor(g.id).map((s) => s.caption).join(" ") }))),
    [],
  )
  const hits = useMemo(() => searchHelp(searchQuery, index), [searchQuery, index])
  const searching = searchQuery.trim().length > 0

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
      setSearchQuery("")
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
            {/* Page header */}
            <div className="text-center space-y-3">
              <div className="w-16 h-16 bg-indigo-100 rounded-2xl flex items-center justify-center mx-auto">
                <Compass className="w-8 h-8 text-indigo-600" />
              </div>
              <h1 className="text-3xl font-bold text-slate-900">Setup Guide</h1>
              <p className="text-slate-600 max-w-xl mx-auto">
                Step-by-step guides with a picture of every step: set up your farm first, then the daily work.
              </p>
              <p className="inline-flex items-center gap-1.5 text-xs text-slate-500">
                <Images className="h-3.5 w-3.5" /> {GUIDES.length} guides · {pictureCount} pictures
              </p>
            </div>

            {/* Search, as on the Help Center */}
            <div className="max-w-xl mx-auto">
              <div className="relative">
                <Search className="absolute left-4 top-1/2 -translate-y-1/2 h-5 w-5 text-slate-400" />
                <Input
                  placeholder="e.g. how do I record a sale?"
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  onKeyDown={(e) => { if (e.key === "Escape") setSearchQuery("") }}
                  aria-label="Search the guides"
                  className="pl-12 pr-10 h-12 text-base rounded-xl bg-white"
                />
                {searching && (
                  <button
                    type="button"
                    onClick={() => setSearchQuery("")}
                    aria-label="Clear search"
                    className="absolute right-3 top-1/2 -translate-y-1/2 rounded p-1 text-slate-400 hover:text-slate-700"
                  >
                    <X className="h-4 w-4" />
                  </button>
                )}
              </div>
            </div>

            {searching ? (
              /* ------------------------------------------------ results */
              <div className="space-y-4">
                <h2 className="text-sm font-medium text-slate-500">
                  {hits.length} {hits.length === 1 ? "guide" : "guides"} for “{searchQuery.trim()}”
                </h2>
                {hits.length > 0 ? (
                  <div className="space-y-2">
                    {hits.map(({ entry, matched }) => (
                      <SetupGuideCard
                        key={entry.id}
                        guide={GUIDES.find((g) => g.id === entry.id) ?? entry}
                        shots={shotsFor(entry.id)}
                        tone={toneFor(entry.category)}
                        open={!closed.has(entry.id)}
                        onToggle={() => setClosed(flip(entry.id))}
                        matched={matched}
                        canOpen={canOpen}
                      />
                    ))}
                  </div>
                ) : (
                  <Card>
                    <CardContent className="space-y-2 py-8 text-center text-slate-500">
                      <p>No guide matches “{searchQuery.trim()}”.</p>
                      <Link href="/help" className="font-medium text-indigo-600 hover:underline">
                        Search the Help Center instead
                      </Link>
                    </CardContent>
                  </Card>
                )}
              </div>
            ) : (
              /* ------------------------------------------------ browse */
              <div>
                {/* Filter chips, exactly as on the Help Center's Questions tab */}
                <div className="mb-4 flex flex-wrap items-start justify-between gap-2">
                  <div className="flex flex-wrap gap-2">
                    {categories.map((cat) => {
                      const tone = toneFor(cat === "All" ? "" : cat)
                      const on = selectedCategory === cat
                      return (
                        <Badge
                          key={cat}
                          variant={on ? "default" : "outline"}
                          className={`cursor-pointer px-3 py-1 transition-colors ${on ? tone.chipOn : tone.chip}`}
                          onClick={() => setSelectedCategory(cat)}
                        >
                          {cat}
                          <span className={`ml-1.5 text-[10px] ${on ? "opacity-80" : "text-slate-400"}`}>
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
            )}

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
