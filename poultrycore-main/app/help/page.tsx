"use client"

import Link from "next/link"
import { useEffect, useMemo, useRef, useState } from "react"
import { useRouter } from "next/navigation"
import {
  ArrowRight, BookA, BookOpen, HelpCircle, Keyboard, LifeBuoy, MessageCircle, Search, Wrench, X,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { HelpEntryCard } from "@/components/help/help-entry-card"
import { ContactSupport, type ContactSupportHandle } from "@/components/help/contact-support"
import { useSearchPages } from "@/hooks/use-global-search"
import { rankPages } from "@/lib/search/page-index"
import { prepareHelpIndex, searchHelp } from "@/lib/help/help-search"
import type { HelpEntry, HelpKind } from "@/lib/help/help-types"
import { FEATURE_GUIDES, HELP_ENTRIES, toneFor } from "@/lib/help/poultry-help-content"

const SHORTCUTS: { keys: string[]; what: string }[] = [
  { keys: ["Ctrl", "K"], what: "Search pages, customers and flocks from anywhere" },
  { keys: ["/"], what: "Same, when you are not typing in a box" },
  { keys: ["↑", "↓", "Enter"], what: "Move through search results and open one" },
  { keys: ["Esc"], what: "Clear the search, then close it" },
]

/** Questions people actually type, offered before they type anything. */
const SUGGESTIONS = ["who owes me", "cash doesn't match profit", "reverse a sale", "eggs per crate", "close the day", "can't see a page"]

const TAB_FOR_KIND: Record<HelpKind, string> = { faq: "questions", fix: "troubleshooting", term: "glossary" }

export default function HelpPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  // /help is poultry-specific (flocks, eggs, birds, vaccinations). Send
  // Water/Generic users to their dashboard until type-specific help pages
  // exist. Wait for Zustand to hydrate before deciding.
  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType === "Water")        router.replace("/water-dashboard")
    else if (activeFarmType === "Generic") router.replace("/generic-dashboard")
  }, [activeFarmType, router])

  const [searchQuery, setSearchQuery] = useState("")
  const [tab, setTab] = useState("questions")
  const [selectedCategory, setSelectedCategory] = useState<string>("All")
  // Questions are open by default, and several at once: someone on a help page
  // is reading, not navigating. `closed` holds the few they folded away.
  // Troubleshooting is the other way round -- a list of symptoms to scan, so
  // `opened` holds the ones they expanded.
  const [closed, setClosed] = useState<Set<string>>(new Set())
  const [opened, setOpened] = useState<Set<string>>(new Set())
  const [flashId, setFlashId] = useState<string | null>(null)
  const supportRef = useRef<ContactSupportHandle>(null)

  // The gated page list the header search uses: answer links and "Go to page"
  // results only offer pages this user may open.
  const pages = useSearchPages()
  const openable = useMemo(() => new Set(pages.map((p) => p.href.split("?")[0])), [pages])
  const canOpen = (href: string) => openable.has(href.split("?")[0])

  const index = useMemo(() => prepareHelpIndex(HELP_ENTRIES), [])
  const hits = useMemo(() => searchHelp(searchQuery, index), [searchQuery, index])
  const pageHits = useMemo(() => rankPages(searchQuery, pages, [], 5), [searchQuery, pages])
  const searching = searchQuery.trim().length > 0

  const isOpen = (e: HelpEntry) => (e.kind === "fix" ? opened.has(e.id) : !closed.has(e.id))
  const toggle = (e: HelpEntry) => {
    const flip = (prev: Set<string>) => {
      const next = new Set(prev)
      if (!next.delete(e.id)) next.add(e.id)
      return next
    }
    if (e.kind === "fix") setOpened(flip)
    else setClosed(flip)
  }

  // A shared link (/help#reverse-sale) opens on its answer: switch to its tab,
  // make sure it is expanded, scroll to it and ring it for a moment.
  useEffect(() => {
    const go = () => {
      const id = decodeURIComponent(window.location.hash.slice(1))
      const entry = HELP_ENTRIES.find((e) => e.id === id)
      if (!entry) {
        if (id === "contact") document.getElementById("contact")?.scrollIntoView({ behavior: "smooth" })
        return
      }
      setSearchQuery("")
      setSelectedCategory("All")
      setTab(TAB_FOR_KIND[entry.kind])
      if (entry.kind === "fix") setOpened((p) => new Set(p).add(entry.id))
      else setClosed((p) => { const n = new Set(p); n.delete(entry.id); return n })
      setFlashId(entry.id)
      setTimeout(() => document.getElementById(entry.id)?.scrollIntoView({ behavior: "smooth", block: "start" }), 60)
      setTimeout(() => setFlashId(null), 2200)
    }
    go()
    window.addEventListener("hashchange", go)
    return () => window.removeEventListener("hashchange", go)
  }, [])

  const faqs = HELP_ENTRIES.filter((e) => e.kind === "faq")
  const fixes = HELP_ENTRIES.filter((e) => e.kind === "fix")
  const terms = HELP_ENTRIES.filter((e) => e.kind === "term").sort((a, b) => a.title.localeCompare(b.title))
  const categories = ["All", ...Array.from(new Set(faqs.map((f) => f.category)))]
  const shownFaqs = selectedCategory === "All" ? faqs : faqs.filter((f) => f.category === selectedCategory)
  const allOpen = shownFaqs.every((f) => !closed.has(f.id))
  const termLetters = Array.from(new Set(terms.map((t) => t.title[0].toUpperCase())))

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
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="max-w-5xl mx-auto space-y-8">
            {/* Page Header */}
            <div className="text-center space-y-3">
              <div className="w-16 h-16 bg-indigo-100 rounded-2xl flex items-center justify-center mx-auto">
                <HelpCircle className="w-8 h-8 text-indigo-600" />
              </div>
              <h1 className="text-3xl font-bold text-slate-900">Help Center</h1>
              <p className="text-slate-600 max-w-xl mx-auto">
                Ask in your own words. Answers, fixes for common problems, what the terms mean, and a quick way to
                reach us.
              </p>
            </div>

            {/* Search */}
            <div className="max-w-xl mx-auto space-y-2">
              <div className="relative">
                <Search className="absolute left-4 top-1/2 -translate-y-1/2 h-5 w-5 text-slate-400" />
                <Input
                  placeholder="e.g. how do I reverse a sale?"
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  onKeyDown={(e) => { if (e.key === "Escape") setSearchQuery("") }}
                  aria-label="Search help"
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
              {!searching && (
                <div className="flex flex-wrap justify-center gap-1.5">
                  {SUGGESTIONS.map((s) => (
                    <button
                      key={s}
                      type="button"
                      onClick={() => setSearchQuery(s)}
                      className="rounded-full border border-slate-200 bg-white px-3 py-1 text-xs text-slate-600 hover:border-indigo-300 hover:text-indigo-700"
                    >
                      {s}
                    </button>
                  ))}
                </div>
              )}
            </div>

            {searching ? (
              /* ------------------------------------------------ results */
              <div className="space-y-4">
                {pageHits.length > 0 && (
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="text-xs font-medium uppercase tracking-wide text-slate-400">Go to page</span>
                    {pageHits.map((p) => (
                      <Link
                        key={p.href}
                        href={p.href}
                        className="inline-flex items-center gap-1.5 rounded-full border border-indigo-200 bg-white px-3 py-1 text-sm text-indigo-700 hover:bg-indigo-50"
                      >
                        {p.icon && <p.icon className="h-3.5 w-3.5" />}
                        {p.title}
                        <ArrowRight className="h-3 w-3" />
                      </Link>
                    ))}
                  </div>
                )}

                <h2 className="text-sm font-medium text-slate-500">
                  {hits.length} {hits.length === 1 ? "answer" : "answers"} for “{searchQuery.trim()}”
                </h2>

                {hits.length > 0 ? (
                  <div className="space-y-2">
                    {hits.map(({ entry, matched }) => (
                      <HelpEntryCard
                        key={entry.id}
                        entry={entry}
                        tone={toneFor(entry.category)}
                        open={isOpen(entry)}
                        onToggle={() => toggle(entry)}
                        matched={matched}
                        canOpen={canOpen}
                        showKind
                      />
                    ))}
                  </div>
                ) : (
                  <Card>
                    <CardContent className="space-y-3 py-8 text-center text-slate-500">
                      <p>No answer matches “{searchQuery.trim()}” yet.</p>
                      <button
                        type="button"
                        onClick={() => supportRef.current?.ask(searchQuery.trim())}
                        className="inline-flex items-center gap-1.5 rounded-md bg-indigo-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-indigo-700"
                      >
                        <MessageCircle className="h-4 w-4" /> Ask support this question
                      </button>
                    </CardContent>
                  </Card>
                )}

                {hits.length > 0 && (
                  <p className="text-center text-sm text-slate-500">
                    Not what you needed?{" "}
                    <button
                      type="button"
                      onClick={() => supportRef.current?.ask(searchQuery.trim())}
                      className="font-medium text-indigo-600 hover:underline"
                    >
                      Ask support
                    </button>
                  </p>
                )}
              </div>
            ) : (
              <>
                {/* Feature Guide */}
                <div>
                  <h2 className="text-lg font-semibold text-slate-900 mb-4 flex items-center gap-2">
                    <BookOpen className="w-5 h-5 text-indigo-600" />
                    Feature Guide
                  </h2>
                  <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-5 gap-3">
                    {FEATURE_GUIDES.filter((g) => canOpen(g.path)).map((guide) => (
                      <Link key={guide.path} href={guide.path} className="group">
                        <Card className="h-full transition-all group-hover:-translate-y-0.5 group-hover:shadow-md">
                          <CardContent className="p-4 text-center">
                            {/* The icon in its own tinted disc: ten grey glyphs
                                in a row are hard to tell apart at a glance, and
                                this grid is meant to be scanned, not read. */}
                            <div className={`mx-auto mb-2 flex h-11 w-11 items-center justify-center rounded-xl ${guide.tint}`}>
                              <guide.icon className="h-6 w-6" />
                            </div>
                            <div className="text-sm font-medium text-slate-900">{guide.title}</div>
                            <div className="mt-1 hidden text-xs text-slate-500 sm:block">{guide.description}</div>
                          </CardContent>
                        </Card>
                      </Link>
                    ))}
                  </div>
                </div>

                {/* Questions / Troubleshooting / Glossary */}
                <Tabs value={tab} onValueChange={setTab}>
                  <TabsList className="w-full justify-start overflow-x-auto sm:w-auto">
                    <TabsTrigger value="questions" className="gap-1.5">
                      <HelpCircle className="h-4 w-4" /> Questions <span className="text-xs text-slate-400">{faqs.length}</span>
                    </TabsTrigger>
                    <TabsTrigger value="troubleshooting" className="gap-1.5">
                      <Wrench className="h-4 w-4" /> Troubleshooting <span className="text-xs text-slate-400">{fixes.length}</span>
                    </TabsTrigger>
                    <TabsTrigger value="glossary" className="gap-1.5">
                      <BookA className="h-4 w-4" /> Glossary <span className="text-xs text-slate-400">{terms.length}</span>
                    </TabsTrigger>
                  </TabsList>

                  <TabsContent value="questions" className="mt-4">
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
                                {cat === "All" ? faqs.length : faqs.filter((f) => f.category === cat).length}
                              </span>
                            </Badge>
                          )
                        })}
                      </div>
                      <button
                        className="text-xs font-medium text-indigo-600 hover:underline"
                        onClick={() => setClosed(allOpen ? new Set(shownFaqs.map((f) => f.id)) : new Set())}
                      >
                        {allOpen ? "Collapse all" : "Expand all"}
                      </button>
                    </div>
                    <div className="space-y-2">
                      {shownFaqs.map((e) => (
                        <HelpEntryCard key={e.id} entry={e} tone={toneFor(e.category)} open={isOpen(e)}
                          onToggle={() => toggle(e)} canOpen={canOpen} flash={flashId === e.id} />
                      ))}
                    </div>
                  </TabsContent>

                  <TabsContent value="troubleshooting" className="mt-4">
                    <p className="mb-3 text-sm text-slate-500">
                      Something looks wrong? Find the symptom, open it, and work through the checks in order.
                    </p>
                    <div className="space-y-2">
                      {fixes.map((e) => (
                        <HelpEntryCard key={e.id} entry={e} tone={toneFor(e.category)} open={isOpen(e)}
                          onToggle={() => toggle(e)} canOpen={canOpen} flash={flashId === e.id} />
                      ))}
                    </div>
                  </TabsContent>

                  <TabsContent value="glossary" className="mt-4">
                    <div className="mb-3 flex flex-wrap gap-1">
                      {termLetters.map((l) => (
                        <a key={l} href={`#letter-${l}`}
                          className="flex h-7 w-7 items-center justify-center rounded-md border border-slate-200 bg-white text-xs font-medium text-slate-600 hover:border-indigo-300 hover:text-indigo-700">
                          {l}
                        </a>
                      ))}
                    </div>
                    <Card>
                      <CardContent className="divide-y divide-slate-100 p-0">
                        {terms.map((t, i) => {
                          const letter = t.title[0].toUpperCase()
                          const firstOfLetter = i === 0 || terms[i - 1].title[0].toUpperCase() !== letter
                          const links = (t.links ?? []).filter((l) => canOpen(l.href))
                          return (
                            <div
                              key={t.id}
                              id={t.id}
                              className={`scroll-mt-24 px-4 py-3 sm:px-5 transition-colors ${flashId === t.id ? "bg-indigo-50" : ""}`}
                            >
                              {firstOfLetter && <span id={`letter-${letter}`} className="block scroll-mt-24" />}
                              <div className="flex flex-wrap items-baseline justify-between gap-x-3">
                                <div className="font-semibold text-slate-900">{t.title}</div>
                                <span className="text-[11px] text-slate-400">{t.category}</span>
                              </div>
                              <div className="mt-1 text-sm leading-relaxed text-slate-600">
                                {t.body}
                              </div>
                              {links.length > 0 && (
                                <div className="mt-1.5 flex flex-wrap gap-3">
                                  {links.map((l) => (
                                    <Link key={l.href} href={l.href} className="text-xs font-medium text-indigo-600 hover:underline">
                                      {l.label} →
                                    </Link>
                                  ))}
                                </div>
                              )}
                            </div>
                          )
                        })}
                      </CardContent>
                    </Card>
                  </TabsContent>
                </Tabs>
              </>
            )}

            {/* Support + shortcuts */}
            <div className="grid gap-4 lg:grid-cols-3">
              <div className="lg:col-span-2">
                <ContactSupport ref={supportRef} />
              </div>
              <Card>
                <CardHeader>
                  <CardTitle className="flex items-center gap-2 text-base text-slate-900">
                    <Keyboard className="h-5 w-5 text-indigo-600" />
                    Shortcuts
                  </CardTitle>
                </CardHeader>
                <CardContent className="space-y-3">
                  {SHORTCUTS.map((s) => (
                    <div key={s.what} className="flex items-start justify-between gap-3 text-sm">
                      <span className="text-slate-600">{s.what}</span>
                      <span className="flex shrink-0 gap-1">
                        {s.keys.map((k) => (
                          <kbd key={k} className="rounded border border-slate-200 bg-slate-50 px-1.5 py-0.5 text-[11px] font-medium text-slate-600">
                            {k}
                          </kbd>
                        ))}
                      </span>
                    </div>
                  ))}
                  <div className="flex items-start gap-2 border-t border-slate-100 pt-3 text-xs text-slate-500">
                    <LifeBuoy className="mt-0.5 h-4 w-4 shrink-0 text-slate-400" />
                    Every answer has a <span className="font-medium text-slate-700">Copy link</span> button — send it to
                    a colleague and it opens on that answer.
                  </div>
                </CardContent>
              </Card>
            </div>
          </div>
        </main>
      </div>
    </div>
  )
}
