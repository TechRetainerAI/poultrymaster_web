"use client"

// Public pricing page — visibilitycore.com/pricing. No auth, no app shell;
// anyone can see the plan ladder before registering. Plans scale with flock
// size (the GH-2026 price book); poultry is priced today, other business
// types show "pricing being finalized". Monthly only — annual prices are
// not configured yet, so there is deliberately no monthly/annual toggle.

import Link from "next/link"
import { Inter } from "next/font/google"
import { Check } from "lucide-react"
import { PUBLIC_PLANS, TRIAL_DAYS, type PublicPlan } from "@/lib/billing/public-pricing"

const inter = Inter({ subsets: ["latin"], display: "swap" })

function PlanCard({ plan }: { plan: PublicPlan }) {
  const hl = plan.highlight
  return (
    <div className="relative flex">
      {hl && (
        <span className="absolute -top-3.5 left-1/2 z-10 -translate-x-1/2 whitespace-nowrap rounded-full bg-slate-900 px-3.5 py-1 text-xs font-medium text-white shadow-sm">
          Most popular
        </span>
      )}
      <div
        className={`flex w-full flex-col rounded-2xl p-6 sm:p-7 ${
          hl
            ? "bg-indigo-600 text-white shadow-xl shadow-indigo-600/20 ring-1 ring-indigo-600"
            : "bg-white text-slate-900 shadow-sm ring-1 ring-slate-200"
        }`}
      >
        <h3 className={`text-lg font-semibold tracking-[-0.01em] ${hl ? "text-white" : "text-slate-900"}`}>{plan.name}</h3>
        <p className={`mt-1 min-h-10 text-sm leading-5 ${hl ? "text-indigo-100" : "text-slate-500"}`}>{plan.blurb}</p>

        <div className="mt-5">
          {plan.monthlyGhs !== null ? (
            <p className="flex items-baseline gap-1">
              <span className={`text-4xl font-semibold tabular-nums tracking-[-0.02em] ${hl ? "text-white" : "text-slate-900"}`}>
                GHS {plan.monthlyGhs.toLocaleString()}
              </span>
              <span className={`text-sm ${hl ? "text-indigo-200" : "text-slate-400"}`}>/mo per company</span>
            </p>
          ) : (
            <p className={`text-2xl font-semibold tracking-[-0.01em] ${hl ? "text-white" : "text-slate-900"}`}>
              Pricing on request
            </p>
          )}
          <p className={`mt-1 text-xs font-medium uppercase tracking-wide ${hl ? "text-indigo-200" : "text-slate-500"}`}>
            {plan.scaleLine}
          </p>
        </div>

        {plan.monthlyGhs !== null ? (
          <Link
            href="/register"
            className={`mt-6 inline-flex h-11 items-center justify-center rounded-lg text-sm font-medium transition-colors ${
              hl
                ? "bg-white text-indigo-700 hover:bg-indigo-50"
                : "bg-slate-900 text-white hover:bg-slate-800"
            }`}
          >
            Start free — {TRIAL_DAYS} days
          </Link>
        ) : (
          <a
            href="https://techretainer.com/contact/"
            className={`mt-6 inline-flex h-11 items-center justify-center rounded-lg text-sm font-medium transition-colors ${
              hl ? "bg-white text-indigo-700 hover:bg-indigo-50" : "bg-slate-900 text-white hover:bg-slate-800"
            }`}
          >
            Request a price
          </a>
        )}

        <ul className={`mt-6 space-y-2.5 text-sm leading-5 ${hl ? "text-indigo-50" : "text-slate-600"}`}>
          {plan.features.map((f) => (
            <li key={f} className="flex gap-2.5">
              <Check className={`mt-0.5 h-4 w-4 shrink-0 ${hl ? "text-indigo-200" : "text-indigo-600"}`} strokeWidth={2.5} />
              <span>{f}</span>
            </li>
          ))}
        </ul>
      </div>
    </div>
  )
}

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
            <PlanCard key={p.code} plan={p} />
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
