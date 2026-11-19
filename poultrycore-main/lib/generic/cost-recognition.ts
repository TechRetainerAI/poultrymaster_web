// Generic Deferred inventory cost wording (Report 40, Part 6). The Poultry/Water
// texts (lib/water/cost-recognition.ts) say "used in production"; a Generic
// business's stock reaches Profit & Loss when it is SOLD or USED, so the same
// sentences are kept with those words.
export { RECOGNITION_TONE_CLASS, deferredStatusTone } from "@/lib/water/cost-recognition"

export const REMAINING_DEFERRED_TOOLTIP =
  "The part of this purchase still held as stock value. It has not been charged to Profit & Loss yet, and will be as the stock is sold or used."

export const RECOGNIZED_COST_TOOLTIP =
  "How much of this purchase has already been charged to Profit & Loss as the stock was sold or used."

export const OPERATIONAL_COST_TOOLTIP =
  "The stock this sale or use took from this purchase, at what the purchase cost."

export const NEWLY_RECOGNIZED_TOOLTIP =
  "The part of this purchase's cost that this sale or use charged to Profit & Loss."

export const DEFERRED_EXCEPTION_TOOLTIP =
  "This purchase's own balance and its recorded usages do not agree on how much has been charged to Profit & Loss. Neither figure should be relied on until it is checked."

export const DEFERRED_PAGE_INTRO =
  "These purchases have already been recorded and may already have affected cash or supplier balances. What is shown here is stock value that has not yet become an expense -- it moves into Profit & Loss as the stock is sold or used, oldest stock first."

export const NO_SECOND_PAYMENT_TOOLTIP =
  "Charging this to Profit & Loss moves no money. The cash left the business when the stock was bought."
