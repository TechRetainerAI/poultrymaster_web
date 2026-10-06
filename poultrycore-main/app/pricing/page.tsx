"use client"

// Public pricing page — visibilitycore.com/pricing. No auth, no app shell.
// PRESENTATION-DRIVEN (admin-app spec 11-16): copy and prices come from the
// backend (pricing presentation + live price book), so staff change them from
// the admin console without a deploy. The static PUBLIC_PLANS constants are
// only the offline fallback. Monthly prices shown; annual appears per card
// when the price book has one (never computed as 12x monthly).

import { useEffect, useState } from "react"
import Link from "next/link"
import { Inter } from "next/font/google"
import { PlanCard } from "@/components/billing/plan-card"
import { PUBLIC_PLANS, TRIAL_DAYS, plansFromApi, type PublicPlan } from "@/lib/billing/public-pricing"
import { getPublicPricing } from "@/lib/api/platform-billing"

const inter = Inter({ subsets: ["latin"], display: "swap" })

const VERTICALS = [
  { profile: "POULTRY_BIRDS", label: "Poultry" },
  { profile: "WATER_PRODUCTION_LINES", label: "Water" },
] as const

export default function PricingPage() {
  const [profile, setProfile] = useState<string>(VERTICALS[0].profile)
  const [plans, setPlans] = useState<PublicPlan[]>(PUBLIC_PLANS)
  const [subtitle, setSubtitle] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    getPublicPricing("GH", profile)
      .then((api) => {
        if (cancelled) return
        const mapped = plansFromApi(api)
        if (mapped.length > 0) setPlans(mapped)
        setSubtitle(api.shortDescription ?? null)
      })
      .catch(() => {
        // Offline/preview fallback: the baked-in poultry ladder.
        if (!cancelled && profile === "POULTRY_BIRDS") setPlans(PUBLIC_PLANS)
      })
    return () => { cancelled = true }
  }, [profile])

  return (
    <div className={`min-h-screen bg-slate-50 ${inter.className}`}>
      <main className="mx-auto max-w-6xl px-4 py-14 sm:py-20">
        <div className="mx-auto max-w-2xl text-center">
          <p className="text-sm font-semibold uppercase tracking-wider text-indigo-600">VisibilityCore pricing</p>
          <h1 className="mt-2 text-3xl font-semibold tracking-[-0.02em] text-slate-900 sm:text-4xl">
            Choose the plan that fits your business
          </h1>
          <p className="mt-3 text-base leading-7 text-slate-600">
            {subtitle || "Every plan includes the complete platform — pricing simply scales with your operation."}{" "}
            Start with a free {TRIAL_DAYS}-day trial; no card needed.
          </p>
        </div>

        {/* Vertical switch: each business type has its own presentation. */}
        <div className="mt-8 flex justify-center">
          <div className="inline-flex rounded-full bg-white p-1 shadow-sm ring-1 ring-slate-200">
            {VERTICALS.map((v) => (
              <button
                key={v.profile}
                onClick={() => setProfile(v.profile)}
                className={`rounded-full px-5 py-1.5 text-sm font-medium transition-colors ${
                  profile === v.profile ? "bg-indigo-600 text-white" : "text-slate-600 hover:text-slate-900"
                }`}
              >
                {v.label}
              </button>
            ))}
          </div>
        </div>

        <div className="mt-12 grid gap-6 sm:grid-cols-2 xl:grid-cols-4 xl:gap-5">
          {plans.map((p) => (
            <PlanCard
              key={`${profile}-${p.code}`}
              plan={p}
              cta={
                p.monthlyGhs !== null ? (
                  <Link
                    href="/register"
                    className={`inline-flex h-11 w-full items-center justify-center rounded-lg text-sm font-medium transition-colors ${
                      p.highlight
                        ? "bg-white text-indigo-700 hover:bg-indigo-50"
                        : "bg-slate-900 text-white hover:bg-slate-800"
                    }`}
                  >
                    Start free — {TRIAL_DAYS} days
                  </Link>
                ) : (
                  <a
                    href="https://techretainer.com/contact/"
                    className="inline-flex h-11 w-full items-center justify-center rounded-lg bg-slate-900 text-sm font-medium text-white transition-colors hover:bg-slate-800"
                  >
                    Request a price
                  </a>
                )
              }
            />
          ))}
        </div>

        <div className="mx-auto mt-10 max-w-3xl space-y-3 text-center text-sm leading-6 text-slate-500">
          <p>
            Prices are per company per month in Ghana cedis. Business types whose pricing is still being finalized
            run free on your account until their pricing is enabled.
          </p>
          <p>
            Run several companies? The Business Office gives your whole organization one consolidated bill.{" "}
            <Link href="/register" className="font-medium text-indigo-600 hover:text-indigo-700">
              Create your account
            </Link>{" "}
            or{" "}
            <Link href="/login" className="font-medium text-indigo-600 hover:text-indigo-700">
              sign in
            </Link>
            .
          </p>
        </div>
      </main>
    </div>
  )
}
