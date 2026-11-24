"use client"

import Link from "next/link"
import { useMemo, useState } from "react"
import { ArrowRight, Check, ChevronDown, ChevronUp, Images, ListChecks, Loader2, RotateCw } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Checkbox } from "@/components/ui/checkbox"
import { cn } from "@/lib/utils"
import { useSetupProgress } from "@/hooks/use-setup-progress"
import { SETUP_STEPS, setupProgress, stepStates } from "@/lib/help/setup-path"

/**
 * "Set up a new farm": the Setup Guide's numbered path, top of the page.
 * Steps tick themselves from the company's data where there is something to
 * count; settings steps are ticked by the person. Each step links to the page
 * that does it and to its picture walkthrough below.
 */
export function SetupPathCard({ hasGuide, onOpenGuide }: {
  /** Whether the page has a picture walkthrough with this id. */
  hasGuide: (id: string) => boolean
  /** Scroll to that walkthrough and open it. */
  onOpenGuide: (id: string) => void
}) {
  const { counts, ticked, toggleTick, loading, reload } = useSetupProgress(true)
  const states = useMemo(() => stepStates(SETUP_STEPS, counts, ticked), [counts, ticked])
  const progress = setupProgress(SETUP_STEPS, states)
  // Folded once the farm is set up; open while there is work left.
  const [openOverride, setOpenOverride] = useState<boolean | null>(null)
  const open = openOverride ?? (loading || !progress.complete)
  const pct = Math.round((progress.done / progress.total) * 100)

  return (
    <Card className="border-l-4 border-l-emerald-400 shadow-sm">
      <CardContent className="p-0">
        <button
          type="button"
          className="w-full rounded-xl px-4 py-4 text-left transition-colors hover:bg-slate-50 sm:px-5"
          onClick={() => setOpenOverride(!open)}
          aria-expanded={open}
        >
          <div className="flex items-start justify-between gap-3">
            <div className="flex min-w-0 flex-1 items-start gap-3">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-emerald-100">
                <ListChecks className="h-5 w-5 text-emerald-700" />
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-center gap-2">
                  <h2 className="font-semibold text-slate-900">Set up a new farm</h2>
                  {!loading && progress.complete && (
                    <Badge className="bg-emerald-600 hover:bg-emerald-600">All done</Badge>
                  )}
                </div>
                <p className="text-sm text-slate-600">
                  Follow these steps in order. Each one ticks itself once it is done.
                </p>
                <div className="mt-2 flex items-center gap-3">
                  <div className="h-2 max-w-xs flex-1 overflow-hidden rounded-full bg-slate-100">
                    <div className="h-full rounded-full bg-emerald-500 transition-all" style={{ width: `${loading ? 0 : pct}%` }} />
                  </div>
                  <span className="shrink-0 text-xs font-medium text-slate-600">
                    {loading ? "Checking…" : `${progress.done} of ${progress.total} done`}
                  </span>
                </div>
              </div>
            </div>
            {open ? <ChevronUp className="mt-0.5 h-5 w-5 shrink-0 text-slate-400" /> : <ChevronDown className="mt-0.5 h-5 w-5 shrink-0 text-slate-400" />}
          </div>
        </button>

        {open && (
          <div className="px-4 pb-4 sm:px-5">
            <ol className="space-y-2">
              {SETUP_STEPS.map((step, i) => {
                const state = states[step.id]
                const done = state === "done"
                const isNext = !loading && progress.next === step.id
                return (
                  <li
                    key={step.id}
                    className={cn(
                      "flex gap-3 rounded-lg border p-3",
                      isNext ? "border-emerald-300 bg-emerald-50/60" : "border-slate-200 bg-white",
                    )}
                  >
                    <div
                      className={cn(
                        "flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-xs font-semibold",
                        done ? "bg-emerald-600 text-white" : isNext ? "bg-emerald-100 text-emerald-800 ring-2 ring-emerald-400" : "bg-slate-100 text-slate-600",
                      )}
                      aria-label={done ? `Step ${i + 1}, done` : `Step ${i + 1}`}
                    >
                      {done ? <Check className="h-4 w-4" /> : i + 1}
                    </div>
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <span className={cn("font-medium", done ? "text-slate-500" : "text-slate-900")}>{step.title}</span>
                        {isNext && <Badge variant="outline" className="border-emerald-300 bg-white text-[10px] text-emerald-700">Next</Badge>}
                        {step.optional && <Badge variant="outline" className="text-[10px] text-slate-500">Optional</Badge>}
                        {step.count && !loading && state === "done" && (counts[step.count] ?? 0) > 0 && (
                          <span className="text-xs text-slate-500">{counts[step.count]} recorded</span>
                        )}
                        {state === "unknown" && !loading && <span className="text-xs text-slate-400">Couldn&apos;t check</span>}
                      </div>
                      <p className="mt-0.5 text-sm text-slate-600">{step.detail}</p>
                      <div className="mt-2 flex flex-wrap items-center gap-2">
                        <Button asChild size="sm" variant={isNext ? "default" : "outline"} className={cn("h-8", isNext && "bg-emerald-600 hover:bg-emerald-700")}>
                          <Link href={step.href}>{step.action} <ArrowRight className="ml-1 h-3.5 w-3.5" /></Link>
                        </Button>
                        {step.guide && hasGuide(step.guide) && (
                          <Button type="button" size="sm" variant="ghost" className="h-8 text-indigo-700" onClick={() => onOpenGuide(step.guide!)}>
                            <Images className="mr-1 h-3.5 w-3.5" /> See how, with pictures
                          </Button>
                        )}
                        {step.manual && (
                          <label className="ml-auto inline-flex cursor-pointer items-center gap-2 text-xs text-slate-600">
                            <Checkbox checked={done} onCheckedChange={() => toggleTick(step.id)} aria-label={`Mark "${step.title}" as done`} />
                            Mark as done
                          </label>
                        )}
                      </div>
                      {step.alt && (
                        <Link href={step.alt.href} className="mt-1.5 inline-block text-xs font-medium text-indigo-600 hover:underline">
                          {step.alt.label}
                        </Link>
                      )}
                    </div>
                  </li>
                )
              })}
            </ol>
            <div className="mt-3 flex justify-end">
              <Button type="button" size="sm" variant="ghost" className="h-8 text-slate-500" onClick={() => void reload()} disabled={loading}>
                {loading ? <Loader2 className="mr-1 h-3.5 w-3.5 animate-spin" /> : <RotateCw className="mr-1 h-3.5 w-3.5" />}
                Check again
              </Button>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
