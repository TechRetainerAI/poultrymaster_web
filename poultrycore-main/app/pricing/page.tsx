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
import { getPublicPricing, getPricingContexts, type PricingContext } from "@/lib/api/platform-billing"

const inter = Inter({ subsets: ["latin"], display: "swap" })

const FALLBACK_CONTEXTS: PricingContext[] = [
  { billingProfileCode: "POULTRY_BIRDS", businessTemplateCode: null, displayName: "Poultry Farm", sortOrder: 10 },
  { billingProfileCode: "WATER_PRODUCTION_LINES", businessTemplateCode: null, displayName: "Water Production", sortOrder: 20 },
]

export default function PricingPage() {
  const [contexts, setContexts] = useState<PricingContext[]>(FALLBACK_CONTEXTS)
  const [ctx, setCtx] = useState<PricingContext>(FALLBACK_CONTEXTS[0])
  const [cycle, setCycle] = useState<"monthly" | "annual">("monthly")
  const [plans, setPlans] = useState<PublicPlan[]>(PUBLIC_PLANS)
  const [subtitle, setSubtitle] = useState<string | null>(null)

  useEffect(() => {
    getPricingContexts().then((list) => { if (list.length > 0) setContexts(list) }).catch(() => {})
  }, [])

  useEffect(() => {
    let cancelled = false
    getPublicPricing("GH", ctx.billingProfileCode, ctx.businessTemplateCode ?? undefined)
      .then((api) => {
        if (cancelled) return
        const mapped = plansFromApi(api)
        if (mapped.length > 0) setPlans(mapped)
        setSubtitle(api.shortDescription ?? null)
      })
      .catch(() => {
        // Offline/preview fallback: the baked-in poultry ladder.
        if (!cancelled && ctx.billingProfileCode === "POULTRY_BIRDS") setPlans(PUBLIC_PLANS)
      })
    return () => { cancelled = true }
  }, [ctx])

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

        {/* Pricing-context selector + monthly/annual explorer: every business
            type has its own presentation; the toggle is display-only. */}
        <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
          <label className="flex items-center gap-2 text-sm text-slate-600">
            View pricing for
            <select
              className="h-9 rounded-lg border border-slate-200 bg-white px-3 text-sm font-medium text-slate-900 shadow-sm"
              value={`${ctx.billingProfileCode}|${ctx.businessTemplateCode ?? ""}`}
              onChange={(e) => {
                const [pc, tc] = e.target.value.split("|")
                const next = contexts.find((x) => x.billingProfileCode === pc && (x.businessTemplateCode ?? "") === tc)
                if (next) setCtx(next)
              }}
            >
              {contexts.map((x) => (
                <option key={`${x.billingProfileCode}|${x.businessTemplateCode ?? ""}`} value={`${x.billingProfileCode}|${x.businessTemplateCode ?? ""}`}>
                  {x.displayName}
                </option>
              ))}
            </select>
          </label>
          <div className="inline-flex rounded-full bg-white p-1 shadow-sm ring-1 ring-slate-200">
            {(["monthly", "annual"] as const).map((cy) => (
              <button
                key={cy}
                onClick={() => setCycle(cy)}
                className={`rounded-full px-5 py-1.5 text-sm font-medium capitalize transition-colors ${
                  cycle === cy ? "bg-indigo-600 text-white" : "text-slate-600 hover:text-slate-900"
                }`}
              >
                {cy}
              </button>
            ))}
          </div>
        </div>

        <div className="mt-12 grid gap-6 sm:grid-cols-2 xl:grid-cols-4 xl:gap-5">
          {plans.map((p) => (
            <PlanCard
              key={`${ctx.billingProfileCode}-${ctx.businessTemplateCode ?? ""}-${p.code}`}
              plan={p}
              cycle={cycle}
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
