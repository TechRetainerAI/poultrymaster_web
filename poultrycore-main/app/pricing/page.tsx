"use client"

// Public pricing page — visibilitycore.com/pricing. No auth, no app shell;
// anyone can see the plan ladder before registering. Plans scale with flock
// size (the GH-2026 price book); poultry is priced today, other business
// types show "pricing being finalized". Monthly only — annual prices are
// not configured yet, so there is deliberately no monthly/annual toggle.

import Link from "next/link"
import { Inter } from "next/font/google"
import { PlanCard } from "@/components/billing/plan-card"
import { PUBLIC_PLANS, TRIAL_DAYS } from "@/lib/billing/public-pricing"

const inter = Inter({ subsets: ["latin"], display: "swap" })

export default function PricingPage() {
  return (
    <div className={`min-h-screen bg-slate-50 ${inter.className}`}>
      <main className="mx-auto max-w-6xl px-4 py-14 sm:py-20">
        <div className="mx-auto max-w-2xl text-center">
          <p className="text-sm font-semibold uppercase tracking-wider text-indigo-600">VisibilityCore pricing</p>
          <h1 className="mt-2 text-3xl font-semibold tracking-[-0.02em] text-slate-900 sm:text-4xl">
            Choose the plan that fits your farm
          </h1>
          <p className="mt-3 text-base leading-7 text-slate-600">
            Every plan includes the complete platform — pricing simply scales with your flock.
            Start with a free {TRIAL_DAYS}-day trial; no card needed.
          </p>
        </div>

        <div className="mt-12 grid gap-6 sm:grid-cols-2 xl:grid-cols-4 xl:gap-5">
          {PUBLIC_PLANS.map((p) => (
            <PlanCard
              key={p.code}
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
            Prices shown are for poultry companies, billed per company per month in Ghana cedis. Pricing for water,
            hotel, restaurant and other business types is being finalized — those companies run free on your account
            until their pricing is enabled.
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
