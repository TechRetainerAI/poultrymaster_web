"use client"

// Migration 441. The cash guard, as a WARNING ONLY: part of the cash on hand
// is money the farm is keeping for staff (Employee Credit). Nothing is
// blocked -- the owner just sees it before spending it. Renders nothing when
// the farm holds nothing for anyone, or when the total cannot be read.

import { useEffect, useState } from "react"
import Link from "next/link"
import { PiggyBank } from "lucide-react"
import { cn } from "@/lib/utils"
import { getPoultryEmployeeCreditTotal } from "@/lib/api/poultry-finance"

export function EmployeeCreditHeldNote({
  totalCash, fmt, className,
}: {
  totalCash: number
  fmt: (n: number) => string
  className?: string
}) {
  const [held, setHeld] = useState<{ totalHeld: number; staffCount: number } | null>(null)

  useEffect(() => {
    let live = true
    getPoultryEmployeeCreditTotal()
      .then((t) => { if (live) setHeld(t) })
      .catch(() => { if (live) setHeld(null) })
    return () => { live = false }
  }, [])

  if (!held || held.totalHeld <= 0) return null
  const short = totalCash < held.totalHeld
  return (
    <div className={cn(
      "flex items-start gap-2 rounded-md border p-3 text-sm",
      short ? "border-amber-300 bg-amber-50 text-amber-900" : "border-sky-200 bg-sky-50 text-sky-900",
      className)}>
      <PiggyBank className="h-4 w-4 mt-0.5 shrink-0" />
      <p>
        <strong>{fmt(held.totalHeld)}</strong> of this cash belongs to {held.staffCount}{" "}
        {held.staffCount === 1 ? "member" : "members"} of staff (
        <Link href="/poultry-employee-credit" className="underline underline-offset-2">Employee Credit</Link>).{" "}
        {short
          ? "You do not have enough cash to pay all of it out today."
          : `The farm's own cash is ${fmt(totalCash - held.totalHeld)}.`}
      </p>
    </div>
  )
}
