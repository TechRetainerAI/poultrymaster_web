"use client"

// The plan card — one visual for every surface that shows the ladder
// (/pricing and the Business Office billing page), so the two never drift.
// The caller supplies the CTA area: the public page links to /register,
// the in-app page shows how many of the org's companies sit on the plan.

import type { ReactNode } from "react"
import { Check } from "lucide-react"
import type { PublicPlan } from "@/lib/billing/public-pricing"

export function PlanCard({ plan, cta, cycle = "monthly" }: { plan: PublicPlan; cta: ReactNode; cycle?: "monthly" | "annual" }) {
  const hl = plan.highlight
  // Annual is pure display here (customer-app spec 5/7): configured AnnualPrice
  // only, savings derived for DISPLAY from monthly x 12, never claimed when
  // there are none, and never guessed when no annual price exists.
  const annual = cycle === "annual"
  const annualSavings =
    plan.annualGhs != null && plan.monthlyGhs != null ? plan.monthlyGhs * 12 - plan.annualGhs : null
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
          {plan.monthlyGhs === null ? (
            <p className={`text-2xl font-semibold tracking-[-0.01em] ${hl ? "text-white" : "text-slate-900"}`}>
              Pricing on request
            </p>
          ) : annual && plan.annualGhs == null ? (
            <p className={`text-xl font-semibold tracking-[-0.01em] ${hl ? "text-indigo-100" : "text-slate-500"}`}>
              Annual pricing not available
            </p>
          ) : annual ? (
            <>
              <p className="flex items-baseline gap-1">
                <span className={`text-4xl font-semibold tabular-nums tracking-[-0.02em] ${hl ? "text-white" : "text-slate-900"}`}>
                  GHS {plan.annualGhs!.toLocaleString()}
                </span>
                <span className={`text-sm ${hl ? "text-indigo-200" : "text-slate-400"}`}>/year per company</span>
              </p>
              <p className={`mt-1 text-xs ${hl ? "text-indigo-200" : "text-slate-500"}`}>
                Equivalent to GHS {(plan.annualGhs! / 12).toLocaleString(undefined, { maximumFractionDigits: 2 })}/month
              </p>
              {annualSavings != null && annualSavings > 0 && (
                <p className={`mt-0.5 text-xs font-medium ${hl ? "text-emerald-200" : "text-emerald-700"}`}>
                  Save GHS {annualSavings.toLocaleString()}/year
                </p>
              )}
            </>
          ) : (
            <p className="flex items-baseline gap-1">
              <span className={`text-4xl font-semibold tabular-nums tracking-[-0.02em] ${hl ? "text-white" : "text-slate-900"}`}>
                GHS {plan.monthlyGhs.toLocaleString()}
              </span>
              <span className={`text-sm ${hl ? "text-indigo-200" : "text-slate-400"}`}>/mo per company</span>
            </p>
          )}
          <p className={`mt-1 text-xs font-medium uppercase tracking-wide ${hl ? "text-indigo-200" : "text-slate-500"}`}>
            {plan.scaleLine}
          </p>
        </div>

        <div className="mt-6">{cta}</div>

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
