"use client"

import { Suspense } from "react"
import { usePathname, useRouter, useSearchParams } from "next/navigation"
import { Compass, HelpCircle, PlayCircle } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { cn } from "@/lib/utils"
import { SupportPageShell } from "@/components/support/support-page-shell"
import { SetupGuideView } from "@/components/support/setup-guide-view"
import { HelpCenterView } from "@/components/support/help-center-view"
import { SupportVideosView } from "@/components/support/support-videos-view"

/**
 * Support: the Setup Guide, the Help Center and the Support Videos on one page,
 * with a sidebar of its own that swaps which one is shown. The section is in
 * the URL (?section=help) so a link can open on it; a question or guide id in
 * the hash (/support?section=help#reverse-sale) still opens that entry.
 *
 * The Setup Guide and Help Center teach the poultry screens, so other company
 * types see only the videos -- the same rule as the main sidebar's rows.
 */
const SECTIONS = [
  { id: "setup-guide", label: "Setup Guide", icon: Compass, poultryOnly: true },
  { id: "help", label: "Help Center", icon: HelpCircle, poultryOnly: true },
  { id: "videos", label: "Support Videos", icon: PlayCircle, poultryOnly: false },
] as const

type SectionId = (typeof SECTIONS)[number]["id"]

function SupportContent() {
  const router = useRouter()
  const pathname = usePathname()
  const params = useSearchParams()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const isPoultry = !["Water", "Generic", "Hotel", "Restaurant", "Livestock"].includes(activeFarmType ?? "")

  const sections = SECTIONS.filter((s) => isPoultry || !s.poultryOnly)
  const requested = params.get("section")
  const active: SectionId = sections.find((s) => s.id === requested)?.id ?? sections[0].id

  const select = (id: SectionId) => router.replace(`${pathname}?section=${id}`, { scroll: false })

  return (
    <div className="mx-auto flex max-w-[1600px] flex-col gap-4 lg:flex-row lg:gap-6">
      {/* The page's own sidebar: a column on desktop, a row of tabs on a phone */}
      <aside className="lg:w-56 lg:shrink-0">
        <div className="lg:sticky lg:top-0 space-y-3">
          <h1 className="hidden text-lg font-bold text-slate-900 lg:block">Support</h1>
          <nav
            aria-label="Support sections"
            className="flex gap-1 overflow-x-auto rounded-xl border border-slate-200 bg-white p-1.5 shadow-sm lg:flex-col"
          >
            {sections.map((s) => {
              const on = s.id === active
              return (
                <button
                  key={s.id}
                  type="button"
                  onClick={() => select(s.id)}
                  aria-current={on ? "page" : undefined}
                  className={cn(
                    "flex shrink-0 items-center gap-2 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
                    on ? "bg-indigo-600 text-white shadow" : "text-slate-600 hover:bg-slate-100 hover:text-slate-900",
                  )}
                >
                  <s.icon className="h-4 w-4" />
                  {s.label}
                </button>
              )
            })}
          </nav>
        </div>
      </aside>

      {/* The chosen section, rendered in place */}
      <section className="min-w-0 flex-1">
        {active === "setup-guide" && <SetupGuideView />}
        {active === "help" && <HelpCenterView />}
        {active === "videos" && <SupportVideosView />}
      </section>
    </div>
  )
}

export default function SupportPage() {
  return (
    <SupportPageShell>
      <Suspense fallback={null}>
        <SupportContent />
      </Suspense>
    </SupportPageShell>
  )
}
