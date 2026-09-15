"use client"

/**
 * Feed tracker — FINISHED FEED only: the feed flocks actually eat.
 *
 * This page used to pool finished feed and feed ingredients into one balance,
 * which answered neither question — an ingredient is bought and milled away,
 * finished feed is produced and eaten, and the sum of the two is not a quantity
 * of anything. Ingredients now have their own page at /feed-ingredient-tracker;
 * both render the same component, so the two can never drift apart.
 */

import { FeedStockTracker } from "@/components/poultry/feed-stock-tracker"

export default function FeedTrackerPage() {
  return <FeedStockTracker kind="FinishedFeed" />
}
