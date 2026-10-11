// Old address of the Inventory Restock Forecast (was "Days of Supply").
// Kept so bookmarks and links already shared keep working.

import { redirect } from "next/navigation"

export default function DaysOfSupplyRedirect() {
  redirect("/poultry-restock-forecast")
}
