// Cost recognition: when an inventory cost reaches Profit & Loss.
//
// Migrations 261-263. The server is the authority -- fnpoultrycostrecognition_
// effective resolves every item and stamps the answer on each purchase -- and
// this file is the frontend's matching vocabulary: the same values, the same
// category grouping, and the wording the pages use to explain them.
//
// WHY THE RESOLVER IS MIRRORED HERE AT ALL
// ----------------------------------------
// It is NOT used to decide anything. Every stored decision comes from the API.
// It exists so the two forms can PREVIEW an answer the user has not saved yet:
// "you are about to override the farm default", "this category follows the feed
// setting". Asking the server after every radio click would be slower and no
// more correct, and the tests pin this copy against the same cases the SQL
// check file pins the real one against.

/** The two methods, spelled exactly as the database stores and checks them. */
export const EXPENSE_WHEN_PURCHASED = "EXPENSE_WHEN_PURCHASED"
export const EXPENSE_WHEN_CONSUMED = "EXPENSE_WHEN_CONSUMED"

export type CostRecognitionMethod =
  | typeof EXPENSE_WHEN_PURCHASED
  | typeof EXPENSE_WHEN_CONSUMED

/** What an item's own setting can say. `null` means "follow the farm default". */
export type CostRecognitionOverride = CostRecognitionMethod | null

/** Where an effective method came from. */
export type CostRecognitionSource = "FarmDefault" | "ItemOverride"

/** Which farm setting a category listens to, if any. */
export type CostRecognitionGroup = "Feed" | "Medication" | "Unconfigured"

/**
 * Category to setting group. Mirrors fnpoultrycostrecognition_categorygroup.
 *
 * Grain is Feed and Supplement is neither -- both deliberate, both explained in
 * migration 261's header. If this list and the SQL one ever disagree, the SQL
 * one is right and this is a bug: it is what actually governs a purchase.
 */
export function costRecognitionGroup(category: string | null | undefined): CostRecognitionGroup {
  switch ((category ?? "").trim().toUpperCase()) {
    case "FEEDINGREDIENT":
    case "FINISHEDFEED":
    case "GRAIN":
      return "Feed"
    case "MEDICATION":
      return "Medication"
    default:
      return "Unconfigured"
  }
}

export interface FarmCostRecognitionDefaults {
  feed: CostRecognitionMethod
  medication: CostRecognitionMethod
}

/**
 * The farm default a category would follow. An unconfigured category follows
 * neither setting and always expenses on purchase -- which is why a farm can
 * turn both settings on without quietly deferring its packaging.
 */
export function farmDefaultFor(
  category: string | null | undefined,
  defaults: FarmCostRecognitionDefaults,
): CostRecognitionMethod {
  switch (costRecognitionGroup(category)) {
    case "Feed":
      return defaults.feed
    case "Medication":
      return defaults.medication
    default:
      return EXPENSE_WHEN_PURCHASED
  }
}

/**
 * The effective method for an item, and where it came from. Mirrors
 * fnpoultrycostrecognition_effective: override, else farm default, else the
 * baseline.
 */
export function effectiveCostRecognition(
  override: CostRecognitionOverride | undefined,
  category: string | null | undefined,
  defaults: FarmCostRecognitionDefaults,
): { method: CostRecognitionMethod; source: CostRecognitionSource; farmDefault: CostRecognitionMethod } {
  const farmDefault = farmDefaultFor(category, defaults)
  return override
    ? { method: override, source: "ItemOverride", farmDefault }
    : { method: farmDefault, source: "FarmDefault", farmDefault }
}

// ---------------------------------------------------------------- wording ---

/** Short enough for a table cell or a badge. */
export function methodShortLabel(m: string | null | undefined): string {
  return m === EXPENSE_WHEN_CONSUMED ? "On use" : "On purchase"
}

/** For a radio label or a sentence. */
export function methodLabel(m: string | null | undefined): string {
  return m === EXPENSE_WHEN_CONSUMED ? "Expense when consumed" : "Expense when purchased"
}

/**
 * What each method actually does, in the terms the farmer thinks in. Both
 * sentences lead with what happens to inventory, because the commonest
 * misreading of this feature is that deferring the cost stops the stock being
 * tracked.
 */
export const METHOD_HELP: Record<CostRecognitionMethod, string> = {
  [EXPENSE_WHEN_PURCHASED]:
    "The purchase cost is recognised in Profit & Loss straight away. Inventory quantity is still tracked, and using the item later does not create another expense.",
  [EXPENSE_WHEN_CONSUMED]:
    "The purchase is held as inventory value first. The cost reaches Profit & Loss later, as the item is used.",
}

/** The one-line pitch on each radio in the settings page. */
export const FEED_OPTION_HINT: Record<CostRecognitionMethod, string> = {
  [EXPENSE_WHEN_PURCHASED]:
    "Simpler. Suits farms that buy feed often and use it quickly.",
  [EXPENSE_WHEN_CONSUMED]:
    "More precise. Feed and raw-material costs affect Profit & Loss as stock is used.",
}

export const MEDICATION_OPTION_HINT: Record<CostRecognitionMethod, string> = {
  [EXPENSE_WHEN_PURCHASED]:
    "Simpler. Recognise the cost when you buy, while still tracking what is left.",
  [EXPENSE_WHEN_CONSUMED]:
    "More precise. Recognise the cost as recorded usage reduces stock.",
}

/**
 * Shown wherever a method is being changed. Says the one thing users get wrong
 * about this feature: it is not retrospective.
 */
export const CHANGE_WARNING =
  "This applies to new purchases from now on. Purchases already recorded keep the treatment they were created with, so past reports do not change."

/**
 * What deferral now actually does, end to end. Migrations 264-268 built the
 * release: the cost is opened on the purchase lot, carried through feed
 * production into the finished feed, and charged to Profit & Loss as the stock
 * is used -- once, and never twice.
 *
 * It says "as you record usage" rather than "as you use it" on purpose: stock
 * that leaves without a recorded consumption still holds its cost, and that is
 * the one thing a farm choosing this needs to know.
 */
export const DEFERRED_ACTIVE_NOTE =
  "A deferred purchase holds its cost as inventory value and reaches Profit & Loss as you record usage of the stock. Feed production carries the cost into the feed it makes, so nothing is expensed twice."

// ------------------------------------------------------- reading it back ---
//
// The server decides everything below -- each lot carries its own snapshot and
// each consumption carries what it actually recognised. These helpers only
// choose how to SHOW that. None of them re-derive a recognition.

/** How a cost figure should read: still owed, already taken, or not applicable. */
export type RecognitionTone = "deferred" | "expensed" | "muted"

/**
 * Tone from the number, not from the server's wording. Parsing prose would tie
 * the palette to a sentence the database is free to reword.
 */
export function recognitionTone(
  deferredAmount: number | null | undefined,
  opts?: { reversed?: boolean; notApplicable?: boolean },
): RecognitionTone {
  if (opts?.reversed || opts?.notApplicable) return "muted"
  return (deferredAmount ?? 0) > 0 ? "deferred" : "expensed"
}

/** Tailwind classes per tone, so every screen colours this the same way. */
export const RECOGNITION_TONE_CLASS: Record<RecognitionTone, string> = {
  deferred: "border-amber-300 bg-amber-50 text-amber-800",
  expensed: "border-emerald-300 bg-emerald-50 text-emerald-800",
  muted: "border-gray-300 bg-gray-50 text-gray-600",
}

/**
 * THE sentence this whole read layer exists for. A consumption that recognised
 * nothing is not a consumption that cost nothing, and a farm on
 * expense-at-purchase -- which is every farm until it chooses otherwise -- would
 * otherwise read its entire feed bill as zero.
 */
export function recognizedCostNote(recognized: number, operational: number): string {
  if (recognized > 0) return "Charged to Profit & Loss when this usage was recorded."
  if (operational > 0) return "Already charged to Profit & Loss when this stock was bought, so using it adds no new expense."
  return "No cost layers were drawn for this usage."
}

/** Feed Production, beside the unchanged production cost. */
export const PRODUCTION_COST_TOOLTIP =
  "What this batch cost to make: the ingredients at the cost they were drawn at, plus milling, labour and any other production costs. This is what cost per unit is based on."

export const CARRIED_FORWARD_TOOLTIP =
  "The part of that cost still waiting to reach Profit & Loss, carried into the feed this batch made. Ingredients already expensed when they were bought are not in this figure, and neither are milling and labour -- they are expenses of their own already."

/** Inventory item detail. */
export const DEFERRED_INVENTORY_TOOLTIP =
  "What this stock still owes Profit & Loss. It is charged as you record usage."

export const EXPENSED_AT_PURCHASE_TOOLTIP =
  "This stock was charged to Profit & Loss when it was bought. Using it reduces the quantity but adds no new expense."

export const OPERATIONAL_VALUE_TOOLTIP =
  "What the stock on hand cost. This is what the inventory is worth, whichever way its cost was recognised."
