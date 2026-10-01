// Where a Restaurant payable document lives (migration 329). Shared by Supplier
// Balances and Supplier Payments so both link to the same place.
//
//   Purchase   Inventory's Purchases tab, narrowed to the one purchase
//   Expense    the Expenses page, narrowed to the one expense
//   AssetCost  a capital investment cost row -> the Capital Investments list
//              (the cost row id is not the asset id, so the list is the honest target)

export function restaurantPayableHref(documentType: string, documentId: number): string | null {
  switch (documentType) {
    case "Purchase":
      return `/restaurant-inventory?tab=purchases&purchaseId=${documentId}`
    case "Expense":
      return `/restaurant-expenses?expenseId=${documentId}`
    case "AssetCost":
      return "/restaurant-assets"
    default:
      return null
  }
}
