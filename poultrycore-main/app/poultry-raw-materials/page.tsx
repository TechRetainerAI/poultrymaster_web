// Old address of Inventory & Supply Purchases (was "Raw Materials & Supplies").
// Kept so bookmarks and shared links keep working; the query string (?tab=,
// ?purchaseId=, ?purchase=1&itemId=) is carried over so deep links still land
// on the right tab, row or dialog.

import { redirect } from "next/navigation"

export default async function RawMaterialsRedirect({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>
}) {
  const params = new URLSearchParams()
  for (const [k, v] of Object.entries(await searchParams)) {
    for (const one of Array.isArray(v) ? v : v == null ? [] : [v]) params.append(k, one)
  }
  const qs = params.toString()
  redirect(qs ? `/poultry-supply-purchases?${qs}` : "/poultry-supply-purchases")
}
