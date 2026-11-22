"use client"

// The frame every /livestock-* page sits in: the company chrome (sidebar +
// header, via PageShell), then a title row in the Livestock colours -- stone
// text, amber accents -- and the page's own actions on the right.

import Link from "next/link"
import type { ComponentType, ReactNode } from "react"
import { ArrowLeft, Loader2 } from "lucide-react"
import { PageShell } from "@/components/dashboard/page-shell"
import { Card, CardContent } from "@/components/ui/card"
import { cn } from "@/lib/utils"

export function LivestockPage({
  title, description, icon: Icon, actions, back, children,
}: {
  title: ReactNode
  description?: ReactNode
  icon?: ComponentType<{ className?: string }>
  actions?: ReactNode
  /** Back link shown above the title (detail pages). */
  back?: { href: string; label: string }
  children: ReactNode
}) {
  return (
    <PageShell boActive="companies">
      <div className="p-4 sm:p-6 space-y-4">
        {back && (
          <Link href={back.href} className="inline-flex items-center gap-1 text-sm text-stone-500 hover:text-amber-800">
            <ArrowLeft className="h-4 w-4" /> {back.label}
          </Link>
        )}
        <div className="flex items-start justify-between gap-3 flex-wrap">
          <div className="min-w-0">
            <h1 className="text-2xl font-semibold text-stone-900 flex items-center gap-2">
              {Icon && <Icon className="h-6 w-6 text-amber-700 shrink-0" />}
              <span className="truncate">{title}</span>
            </h1>
            {description && <p className="text-sm text-stone-500 mt-0.5">{description}</p>}
          </div>
          {actions && <div className="flex gap-2 flex-wrap">{actions}</div>}
        </div>
        {children}
      </div>
    </PageShell>
  )
}

export function StatCard({ label, value, hint, tone = "stone" }: {
  label: string
  value: ReactNode
  hint?: ReactNode
  tone?: "stone" | "amber" | "rose" | "emerald"
}) {
  const border = { stone: "border-l-stone-400", amber: "border-l-amber-600", rose: "border-l-rose-500", emerald: "border-l-emerald-600" }[tone]
  return (
    <Card className={cn("border-l-4", border)}>
      <CardContent className="p-4">
        <div className="text-xs font-medium uppercase tracking-wide text-stone-500">{label}</div>
        <div className="text-2xl font-semibold text-stone-900 mt-1">{value}</div>
        {hint && <div className="text-xs text-stone-500 mt-1">{hint}</div>}
      </CardContent>
    </Card>
  )
}

export function Loading({ label = "Loading…" }: { label?: string }) {
  return <div className="flex items-center gap-2 text-sm text-stone-500 py-6"><Loader2 className="h-4 w-4 animate-spin" /> {label}</div>
}

export function LoadError({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div className="rounded-md border border-rose-200 bg-rose-50 p-4 text-sm text-rose-800">
      {message}
      {onRetry && <button onClick={onRetry} className="ml-2 underline">Try again</button>}
    </div>
  )
}

export function EmptyState({ title, children, action }: { title: string; children?: ReactNode; action?: ReactNode }) {
  return (
    <div className="rounded-lg border border-dashed border-amber-300 bg-amber-50/50 p-8 text-center">
      <div className="font-medium text-stone-800">{title}</div>
      {children && <div className="text-sm text-stone-500 mt-1 max-w-md mx-auto">{children}</div>}
      {action && <div className="mt-4">{action}</div>}
    </div>
  )
}

/** Primary button colours for Livestock. */
export const AMBER_BUTTON = "bg-amber-700 hover:bg-amber-800 text-white"

export const fmtNum = (n: number | null | undefined) => (n == null ? "—" : n.toLocaleString())
export const fmtMoney = (n: number | null | undefined) =>
  n == null ? "—" : n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
export function fmtDate(d: string | null | undefined) {
  if (!d) return "—"
  const dt = new Date(d.length === 10 ? `${d}T00:00:00` : d)
  return Number.isNaN(dt.getTime()) ? d : dt.toLocaleDateString(undefined, { day: "2-digit", month: "short", year: "numeric" })
}
export function fmtAge(days: number | null | undefined) {
  if (days == null) return "—"
  if (days < 0) return "—"
  if (days < 14) return `${days} day${days === 1 ? "" : "s"}`
  if (days < 120) return `${Math.floor(days / 7)} weeks`
  if (days < 730) return `${Math.floor(days / 30.4)} months`
  return `${(days / 365.25).toFixed(1)} years`
}
export const todayIso = () => {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
}
