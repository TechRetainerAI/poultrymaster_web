"use client"

/**
 * The header search.
 *
 * Type anything -- a page ("cash flow", "p&l", "who owes"), an intent ("new
 * sale", "record expense"), a name ("Kofi"), or part of a phone number
 * ("0244") -- and it offers the matching pages and records for the ACTIVE
 * company, already filtered to what this user may open. Typo-tolerant
 * ("expences"), acronym-aware ("cf"), and it remembers what you opened.
 *
 * On a list page that listens for `globalSearch`, the first result is "Filter
 * this page", so the old behaviour (type, the table filters as you go, Enter
 * keeps you here) still works.
 *
 * Ctrl+K / Cmd+K or "/" focuses it from anywhere.
 */

import { useEffect, useMemo, useRef, useState } from "react"
import { usePathname, useRouter } from "next/navigation"
import { Command as CommandPrimitive } from "cmdk"
import {
  ArrowRight, Bird, Building2, Clock, Filter, Loader2, Package, PlusCircle, Search, Truck, User, Users, X,
  type LucideIcon,
} from "lucide-react"
import { cn } from "@/lib/utils"
import { useAuthStore } from "@/lib/store/auth-store"
import { parseQuery, rankPages } from "@/lib/search/page-index"
import { rankRecords, RECORD_KIND_LABEL, type RecordKind } from "@/lib/search/records"
import { useSearchPages, useSearchRecents, useSearchRecords, type RecentEntry } from "@/hooks/use-global-search"

/**
 * List pages that filter themselves on the `globalSearch` event / the
 * `globalSearchQuery` hand-off. Adding a page here without wiring it up just
 * offers a "Filter this page" row that does nothing.
 */
export const GLOBAL_SEARCH_FILTER_PAGES = [
  "/employees", "/customers", "/suppliers", "/flocks", "/sales", "/inventory", "/expenses", "/supplies",
  "/health", "/audit-logs", "/water-customers", "/generic-products",
]

const KIND_ICON: Record<RecordKind, LucideIcon> = {
  customer: Users, supplier: Truck, flock: Bird, house: Building2, product: Package, driver: User,
}

function isFilterPage(pathname: string) {
  return GLOBAL_SEARCH_FILTER_PAGES.includes(pathname)
}

function dispatchFilter(query: string) {
  window.dispatchEvent(new CustomEvent("globalSearch", { detail: { query } }))
}

export function GlobalSearch({ placeholder }: { placeholder: string }) {
  const pathname = usePathname() ?? ""
  const inputRef = useRef<HTMLInputElement>(null)
  const [query, setQuery] = useState("")
  const [open, setOpen] = useState(false)
  // Where the panel sits. It is position:fixed, measured off the input,
  // because the header's wrapper is overflow-x-hidden -- which makes it clip on
  // the y axis too -- and an absolute panel would be cut off below the nav.
  const [rect, setRect] = useState<{ top: number; left: number; width: number } | null>(null)
  // The index (and its permission + record requests) is mounted the first
  // time the search is used, not on every page load. Once mounted it stays,
  // so reopening does not refetch.
  const [armed, setArmed] = useState(false)

  // Ctrl/Cmd+K anywhere, or "/" when not already typing somewhere.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const t = e.target as HTMLElement | null
      const typing = !!t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.isContentEditable)
      if ((e.key === "k" || e.key === "K") && (e.ctrlKey || e.metaKey)) {
        e.preventDefault()
        inputRef.current?.focus()
        inputRef.current?.select()
      } else if (e.key === "/" && !typing) {
        e.preventDefault()
        inputRef.current?.focus()
      }
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [])

  useEffect(() => {
    if (!open) return
    const measure = () => {
      const r = inputRef.current?.getBoundingClientRect()
      if (r) setRect({ top: r.bottom + 8, left: r.left, width: Math.max(r.width, 352) })
    }
    measure()
    window.addEventListener("resize", measure)
    window.addEventListener("scroll", measure, true)
    return () => {
      window.removeEventListener("resize", measure)
      window.removeEventListener("scroll", measure, true)
    }
  }, [open])

  // Leaving a page drops whatever was typed for it.
  useEffect(() => {
    setQuery("")
  }, [pathname])

  const onChange = (value: string) => {
    setQuery(value)
    setOpen(true)
    setArmed(true)
    // Live filtering on list pages, as before.
    if (isFilterPage(pathname)) dispatchFilter(value.trim())
  }

  const close = () => {
    setOpen(false)
    inputRef.current?.blur()
  }

  const clearQuery = () => {
    setQuery("")
    if (isFilterPage(pathname)) dispatchFilter("")
    sessionStorage.removeItem("globalSearchQuery")
    inputRef.current?.focus()
  }

  return (
    <CommandPrimitive
      shouldFilter={false}
      loop
      label="Search"
      className="relative w-full"
      onKeyDown={(e) => {
        if (e.key === "Escape") {
          e.preventDefault()
          if (query) clearQuery()
          else close()
        }
      }}
    >
      <div className="relative">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400 pointer-events-none" />
        <CommandPrimitive.Input
          ref={inputRef}
          value={query}
          onValueChange={onChange}
          onFocus={() => { setOpen(true); setArmed(true) }}
          onBlur={() => setOpen(false)}
          placeholder={placeholder}
          aria-label="Search pages and records"
          className="w-full h-9 rounded-md border border-slate-700 bg-slate-800 pl-10 pr-16 text-sm text-white placeholder:text-slate-400 outline-none focus:bg-slate-700 focus:border-slate-600"
        />
        {query ? (
          <button
            type="button"
            onMouseDown={(e) => e.preventDefault()}
            onClick={clearQuery}
            aria-label="Clear search"
            className="absolute right-2 top-1/2 -translate-y-1/2 rounded p-1 text-slate-400 hover:text-white"
          >
            <X className="h-4 w-4" />
          </button>
        ) : (
          <kbd className="pointer-events-none absolute right-2 top-1/2 -translate-y-1/2 rounded border border-slate-600 px-1.5 py-0.5 text-[10px] font-medium text-slate-400">
            Ctrl K
          </kbd>
        )}
      </div>

      {armed && (
        <SearchPanel
          query={query}
          pathname={pathname}
          open={open}
          rect={rect}
          onClose={close}
          onDone={() => { setQuery(""); close() }}
        />
      )}
    </CommandPrimitive>
  )
}

/**
 * The results. Everything that costs a request lives here, so it only exists
 * once the search has been used.
 */
function SearchPanel({ query, pathname, open, rect, onClose, onDone }: {
  query: string
  pathname: string
  open: boolean
  rect: { top: number; left: number; width: number } | null
  onClose: () => void
  /** A result was opened: clear the box and close. */
  onDone: () => void
}) {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const pages = useSearchPages()
  const records = useSearchRecords(true, pages)
  const { recents, remember, clear } = useSearchRecents()

  const openable = useMemo(() => new Set(pages.map((p) => p.href.split("?")[0])), [pages])
  const pageTitle = useMemo(() => pages.find((p) => p.href === pathname)?.title, [pages, pathname])

  // A stored recent is only a preference. If the user has since lost the
  // page it points into (or switched to a company that has no such page), it
  // is not shown -- same rule as Quick Links.
  const visibleRecents = useMemo(
    () => recents.filter((r) => {
      const path = r.href.split("?")[0]
      return openable.has(path) || openable.has(`/${path.split("/")[1]}`)
    }),
    [recents, openable],
  )

  const parsed = useMemo(() => parseQuery(query), [query])
  const rankedPages = useMemo(() => rankPages(query, pages, visibleRecents.map((r) => r.href)), [query, pages, visibleRecents])
  const rankedRecords = useMemo(
    () => (parsed.text.length >= 2 ? rankRecords(parsed.text, records.data ?? []) : []),
    [parsed.text, records.data],
  )
  const canFilterHere = isFilterPage(pathname) && query.trim().length > 0

  const go = (entry: RecentEntry) => {
    remember(entry)
    const path = entry.href.split("?")[0]
    if (entry.prefill) {
      sessionStorage.setItem("globalSearchQuery", entry.prefill)
      // Already on that list: it will not remount, so tell it directly.
      if (path === pathname) dispatchFilter(entry.prefill)
    } else {
      sessionStorage.removeItem("globalSearchQuery")
      if (isFilterPage(pathname)) dispatchFilter("")
    }
    onDone()
    if (entry.href !== pathname) router.push(entry.href)
  }

  const filterHere = () => {
    dispatchFilter(query.trim())
    onClose()
  }

  const hasQuery = query.trim().length > 0
  const nothing = hasQuery && !canFilterHere && rankedPages.length === 0 && rankedRecords.length === 0 && !records.isFetching

  return (
    <>
      {open && rect && (
        <div
          // Keep focus in the input while clicking a result, so blur does not
          // close the panel before the click lands.
          onMouseDown={(e) => e.preventDefault()}
          style={{ top: rect.top, left: rect.left, width: rect.width }}
          className="fixed z-50 overflow-hidden rounded-lg border border-slate-200 bg-white text-slate-900 shadow-xl"
        >
          <CommandPrimitive.List className="max-h-[min(70vh,28rem)] overflow-y-auto p-1">
            {!hasQuery && visibleRecents.length > 0 && (
              <CommandPrimitive.Group
                heading={
                  <div className="flex items-center justify-between">
                    <span>Recent</span>
                    <button type="button" onClick={clear} className="text-[11px] font-normal text-slate-400 hover:text-slate-700">
                      Clear
                    </button>
                  </div>
                }
                className={GROUP_CLASS}
              >
                {visibleRecents.map((r) => (
                  <Row key={`recent:${r.href}:${r.prefill ?? ""}`} value={`recent:${r.href}:${r.prefill ?? ""}`}
                    icon={Clock} title={r.title} meta={r.meta} onSelect={() => go(r)} />
                ))}
              </CommandPrimitive.Group>
            )}

            {!hasQuery && (
              <div className="px-3 py-3 text-xs text-slate-500">
                Search pages and {activeFarmType === "Hotel" || activeFarmType === "Restaurant" ? "reports" : "records"}. Try{" "}
                <span className="font-medium text-slate-700">who owes</span>,{" "}
                <span className="font-medium text-slate-700">new sale</span>,{" "}
                <span className="font-medium text-slate-700">p&amp;l</span>
                {activeFarmType !== "Hotel" && activeFarmType !== "Restaurant" && <>, a customer name or a phone number</>}.
              </div>
            )}

            {canFilterHere && (
              <CommandPrimitive.Group heading="This page" className={GROUP_CLASS}>
                <Row value="filter-here" icon={Filter}
                  title={<>Filter {pageTitle ?? "this page"} for “<span className="font-semibold">{query.trim()}</span>”</>}
                  meta="Enter" onSelect={filterHere} />
              </CommandPrimitive.Group>
            )}

            {rankedPages.length > 0 && (
              <CommandPrimitive.Group heading={parsed.create ? "Record it on" : "Pages"} className={GROUP_CLASS}>
                {rankedPages.map((p) => (
                  <Row key={`page:${p.href}`} value={`page:${p.href}`}
                    icon={parsed.create ? PlusCircle : (p.icon ?? ArrowRight)}
                    title={p.title} meta={p.group}
                    onSelect={() => go({ href: p.href, title: p.title, meta: p.group })} />
                ))}
              </CommandPrimitive.Group>
            )}

            {rankedRecords.length > 0 && (
              <CommandPrimitive.Group heading="Records" className={GROUP_CLASS}>
                {rankedRecords.map((r) => (
                  <Row key={`rec:${r.kind}:${r.id}`} value={`rec:${r.kind}:${r.id}`}
                    icon={KIND_ICON[r.kind]}
                    title={<>{r.title}{r.inactive && <span className="ml-1.5 text-[11px] text-slate-400">(inactive)</span>}</>}
                    subtitle={r.subtitle}
                    meta={RECORD_KIND_LABEL[r.kind]}
                    onSelect={() => go({ href: r.href, title: r.title, meta: RECORD_KIND_LABEL[r.kind], prefill: r.prefill })} />
                ))}
              </CommandPrimitive.Group>
            )}

            {hasQuery && records.isFetching && rankedRecords.length === 0 && (
              <div className="flex items-center gap-2 px-3 py-2 text-xs text-slate-500">
                <Loader2 className="h-3.5 w-3.5 animate-spin" /> Looking through records…
              </div>
            )}

            {nothing && (
              <div className="px-3 py-6 text-center text-sm text-slate-500">
                Nothing matches “{query.trim()}”.
                <div className="mt-1 text-xs">Check the spelling, or try a shorter word.</div>
              </div>
            )}
          </CommandPrimitive.List>

          <div className="flex items-center gap-3 border-t border-slate-100 bg-slate-50 px-3 py-1.5 text-[11px] text-slate-500">
            <span><kbd className={KBD}>↑</kbd><kbd className={KBD}>↓</kbd> move</span>
            <span><kbd className={KBD}>Enter</kbd> open</span>
            <span><kbd className={KBD}>Esc</kbd> {query ? "clear" : "close"}</span>
          </div>
        </div>
      )}
    </>
  )
}

const GROUP_CLASS =
  "p-1 [&_[cmdk-group-heading]]:px-2 [&_[cmdk-group-heading]]:py-1.5 [&_[cmdk-group-heading]]:text-[11px] [&_[cmdk-group-heading]]:font-semibold [&_[cmdk-group-heading]]:uppercase [&_[cmdk-group-heading]]:tracking-wide [&_[cmdk-group-heading]]:text-slate-400"

const KBD = "mx-0.5 rounded border border-slate-200 bg-white px-1 font-sans text-[10px]"

function Row({ value, icon: Icon, title, subtitle, meta, onSelect }: {
  value: string
  icon: LucideIcon
  title: React.ReactNode
  subtitle?: string
  meta?: string
  onSelect: () => void
}) {
  return (
    <CommandPrimitive.Item
      value={value}
      onSelect={onSelect}
      className={cn(
        "flex cursor-pointer items-center gap-3 rounded-md px-2 py-2 text-sm",
        "data-[selected=true]:bg-slate-100",
      )}
    >
      <Icon className="h-4 w-4 shrink-0 text-slate-400" />
      <div className="min-w-0 flex-1">
        <div className="truncate text-slate-900">{title}</div>
        {subtitle && <div className="truncate text-xs text-slate-500">{subtitle}</div>}
      </div>
      {meta && <span className="shrink-0 text-[11px] text-slate-400">{meta}</span>}
    </CommandPrimitive.Item>
  )
}
