// Old address of Inventory & supply purchases (was "Raw materials & supplies").
// Kept so bookmarks and shared links keep working; the query string (?tab=,
// ?purchaseId=) is carried over so deep links still land on the right tab or
// purchase.

import { redirect } from "next/navigation"

export default async function WaterRawMaterialsRedirect({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>
}) {
  const params = new URLSearchParams()
  for (const [k, v] of Object.entries(await searchParams)) {
    for (const one of Array.isArray(v) ? v : v == null ? [] : [v]) params.append(k, one)
  }
  const qs = params.toString()
  redirect(qs ? `/water-supply-purchases?${qs}` : "/water-supply-purchases")
}
