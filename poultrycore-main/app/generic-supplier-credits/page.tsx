"use client"

// Generic Supplier Credits & Advances (Report 40, migration 449): the Poultry
// page, as Water's is (426). Its client, dialogs, permission keys and links
// follow the active company (lib/api/credit-module.ts: supplierCreditModule),
// so a Generic company reads and writes api/Generic/supplier-credits.
// The old Generic page (a list of typed credits that nothing could use) is
// replaced; its one row was moved into the new model by migration 449.
export { default } from "@/app/supplier-credits/page"
