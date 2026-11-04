"use client"

import Link from "next/link"
import { ShoppingCart } from "lucide-react"

/** Feed is bought through Record Purchase (it goes into stock), not as a plain expense. */
export const FEED_CATEGORY = "Feed"
export const FEED_PURCHASE_HREF = "/poultry-supply-purchases?purchase=1"
export const FEED_EXPENSE_BLOCKED_MESSAGE =
  "Feed can't be bought here. Use Record Purchase so the feed goes into stock."

export function isFeedCategory(category?: string | null) {
  return (category || "").trim().toLowerCase() === FEED_CATEGORY.toLowerCase()
}

export function FeedPurchaseNotice({ className = "" }: { className?: string }) {
  return (
    <div className={`rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900 ${className}`} role="alert">
      <p className="font-medium">You can&apos;t buy feed here.</p>
      <p className="mt-1">
        Feed purchases are recorded on Record Purchase, so the feed goes into stock and its cost
        is counted when the birds eat it.
      </p>
      <Link
        href={FEED_PURCHASE_HREF}
        className="mt-2 inline-flex items-center gap-1.5 rounded-md bg-amber-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-amber-700"
      >
        <ShoppingCart className="h-3.5 w-3.5" /> Go to Record Purchase
      </Link>
    </div>
  )
}
