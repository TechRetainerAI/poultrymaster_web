"use client"

/**
 * Ingredients tracker — the maize, soya and wheat bran side of the feed store:
 * bought in, drawn out by feed production. The finished feed those batches make
 * is the other half, at /feed-tracker.
 *
 * Same component as the feed tracker, with the whole-farm kg correction tool
 * left out: that correction has no item behind it and belongs to finished feed.
 */

import { FeedStockTracker } from "@/components/poultry/feed-stock-tracker"

export default function FeedIngredientTrackerPage() {
  return <FeedStockTracker kind="Ingredient" />
}
