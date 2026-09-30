"use client"

// Farm Completeness (Tools) — the Missing Activity Detector on its own page.
//
// The dashboard shows today only. This page reuses the SAME card, opened up,
// with a date picker so a past day can be checked too ("did everyone record
// on Saturday?"). Nothing here computes anything: the Farm API derives the
// report for whatever business date is asked for (migration 332).
//
// The date picker defaults to, and is capped at, the COMPANY's today from
// useBusinessDate — never the browser's clock. The API refuses a future date
// anyway; the cap just stops the picker offering one.

import { Suspense, useState } from "react"
import { useSearchParams } from "next/navigation"
import { ChevronLeft, ChevronRight, ClipboardCheck } from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { FarmCompletenessCard } from "@/components/dashboard/farm-completeness-card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { useLogout } from "@/hooks/use-logout"
import { useBusinessDate } from "@/hooks/use-business-date"
import { shiftBusinessDate, toBusinessDate } from "@/lib/activity/completeness"

function FarmCompletenessInner() {
  const logout = useLogout()
  const searchParams = useSearchParams()
  const { businessDate: today } = useBusinessDate()
  // null = follow the company's today (and keep following it past midnight).
  // ?date= comes from Daily Closing's "Resolve" on missing production.
  const [picked, setPicked] = useState<string | null>(() => toBusinessDate(searchParams.get("date")))

  const shown = picked && picked < today ? picked : today
  const isToday = shown === today
  // Undefined lets the SERVER decide today, so this page and the dashboard can
  // never disagree about which day "today" is.
  const requested = isToday ? undefined : shown

  const choose = (value: string | null) => {
    const d = toBusinessDate(value)
    if (!d || d >= today) setPicked(null)
    else setPicked(d)
  }

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex min-w-0 flex-1 flex-col">
        <DashboardHeader />
        <main className="min-w-0 overflow-x-hidden p-4 pb-16 sm:p-6 lg:pb-4">
          <div className="space-y-6">
            <div className="flex flex-wrap items-end justify-between gap-4">
              <div className="flex items-start gap-3">
                <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-amber-100">
                  <ClipboardCheck className="h-5 w-5 text-amber-600" />
                </div>
                <div className="min-w-0">
                  <h1 className="text-2xl font-bold text-slate-900">Farm Completeness</h1>
                  <p className="text-sm text-slate-600">
                    Expected farm activities that have not been recorded yet.
                  </p>
                </div>
              </div>

              <div className="flex items-end gap-2">
                <Button
                  variant="outline"
                  size="icon"
                  aria-label="Previous day"
                  onClick={() => choose(shiftBusinessDate(shown, -1))}
                >
                  <ChevronLeft className="h-4 w-4" />
                </Button>
                <div className="space-y-1">
                  <Label htmlFor="completeness-date" className="text-xs text-slate-500">Business date</Label>
                  <Input
                    id="completeness-date"
                    type="date"
                    className="w-40"
                    value={shown}
                    max={today}
                    onChange={(e) => choose(e.target.value)}
                  />
                </div>
                <Button
                  variant="outline"
                  size="icon"
                  aria-label="Next day"
                  disabled={isToday}
                  onClick={() => choose(shiftBusinessDate(shown, 1))}
                >
                  <ChevronRight className="h-4 w-4" />
                </Button>
                {!isToday && (
                  <Button variant="ghost" size="sm" onClick={() => setPicked(null)}>
                    Today
                  </Button>
                )}
              </div>
            </div>

            <FarmCompletenessCard businessDate={requested} defaultExpanded />
          </div>
        </main>
      </div>
    </div>
  )
}

export default function FarmCompletenessPage() {
  // useSearchParams needs a Suspense boundary during prerender.
  return (
    <Suspense fallback={null}>
      <FarmCompletenessInner />
    </Suspense>
  )
}
