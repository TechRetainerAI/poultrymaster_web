// Cost recognition: when an inventory cost reaches Profit & Loss.
//
// Migrations 274 and 276. The server is the authority --
// fnwatercostrecognition_effective resolves every item and stamps the answer on
// each purchase -- and this file is the frontend's matching vocabulary: the same
// values, the same category grouping, and the wording the pages use.
//
// WHY THE RESOLVER IS MIRRORED HERE AT ALL
// ----------------------------------------
// It is NOT used to decide anything. Every stored decision comes from the API.
// It exists so the two forms can PREVIEW an answer the user has not saved yet:
// "you are about to override the company default", "this category follows the
// packaging setting". Asking the server after every radio click would be slower
// and no more correct, and the tests pin this copy against the same cases the
// SQL check file pins the real one against.
//
// DEFERRAL IS NOT SWITCHED ON FOR WATER YET
// -----------------------------------------
// The whole vocabulary of deferred costing is here, and none of it can be
// chosen yet. 274 ships an interlock -- fnwatercostrecognition_deferralready()
// -- that refuses EXPENSE_WHEN_CONSUMED until the phase-2 migrations land,
// because stamping purchases as deferred while they are still expensed at
// purchase would charge the same cost to Profit & Loss twice.
//
// The settings page reads `deferralAvailable` off the API and explains the
// disabled option. It does NOT hardcode that state here: the day phase 2 is
// applied, the page must start working without a frontend deploy.

/** The two methods, spelled exactly as the database stores and checks them. */
export const EXPENSE_WHEN_PURCHASED = "EXPENSE_WHEN_PURCHASED"
export const EXPENSE_WHEN_CONSUMED = "EXPENSE_WHEN_CONSUMED"

export type CostRecognitionMethod =
  | typeof EXPENSE_WHEN_PURCHASED
  | typeof EXPENSE_WHEN_CONSUMED

/** What an item's own setting can say. `null` means "follow the company default". */
export type CostRecognitionOverride = CostRecognitionMethod | null

/** Where an effective method came from. */
export type CostRecognitionSource = "FarmDefault" | "ItemOverride"

/** Which company setting a category listens to, if any. */
export type CostRecognitionGroup = "Packaging" | "Treatment" | "Unconfigured"

/**
 * Category to setting group. Mirrors fnwatercostrecognition_categorygroup.
 *
 * Filter and UVLamp are deliberately NOT Treatment -- explained in migration
 * 274's header. If this list and the SQL one ever disagree, the SQL one is right
 * and this is a bug: it is what actually governs a purchase.
 */
export function costRecognitionGroup(category: string | null | undefined): CostRecognitionGroup {
  switch ((category ?? "").trim().toUpperCase()) {
    case "PACKAGINGROLL":
    case "SACHETFILM":
    case "OUTERBAG":
      return "Packaging"
    case "CHEMICAL":
      return "Treatment"
    default:
      return "Unconfigured"
  }
}

export interface FarmCostRecognitionDefaults {
  packaging: CostRecognitionMethod
  treatment: CostRecognitionMethod
}

/**
 * The company default a category would follow. An unconfigured category follows
 * neither setting and always expenses on purchase -- which is why a company can
 * turn both settings on without quietly deferring its fuel.
 */
export function farmDefaultFor(
  category: string | null | undefined,
  defaults: FarmCostRecognitionDefaults,
): CostRecognitionMethod {
  switch (costRecognitionGroup(category)) {
    case "Packaging":
      return defaults.packaging
    case "Treatment":
      return defaults.treatment
    default:
      return EXPENSE_WHEN_PURCHASED
  }
}

/**
 * The effective method for an item, and where it came from. Mirrors
 * fnwatercostrecognition_effective: override, else company default, else the
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

/** The human name of a category group, for a heading or a sentence. */
export const GROUP_LABEL: Record<CostRecognitionGroup, string> = {
  Packaging: "Packaging materials",
  Treatment: "Treatment chemicals",
  Unconfigured: "Not covered by a company setting",
}

/**
 * Which categories each group actually covers. Shown beside the setting so a
 * company can see what it is about to change before it changes it -- the list
 * is the single commonest question this page gets.
 */
export const GROUP_CATEGORIES: Record<CostRecognitionGroup, string[]> = {
  Packaging: ["PackagingRoll", "SachetFilm", "OuterBag"],
  Treatment: ["Chemical"],
  Unconfigured: ["Filter", "UVLamp", "SparePart", "Fuel", "CleaningSupply", "Other"],
}

/**
 * What each method actually does, in the terms the operator thinks in. Both
 * sentences lead with what happens to inventory, because the commonest
 * misreading of this feature is that deferring the cost stops the stock being
 * tracked.
 */
export const METHOD_HELP: Record<CostRecognitionMethod, string> = {
  [EXPENSE_WHEN_PURCHASED]:
    "The purchase cost is recognised in Profit & Loss straight away. Inventory quantity is still tracked, and using the item later does not create another expense.",
  [EXPENSE_WHEN_CONSUMED]:
    "The purchase is held as inventory value first. The cost reaches Profit & Loss later, as the item is used in production.",
}

/** The one-line pitch on each radio in the settings page. */
export const PACKAGING_OPTION_HINT: Record<CostRecognitionMethod, string> = {
  [EXPENSE_WHEN_PURCHASED]:
    "Simpler. Suits companies that buy film and bags often and use them quickly.",
  [EXPENSE_WHEN_CONSUMED]:
    "More precise. Packaging costs affect Profit & Loss as production draws the stock.",
}

export const TREATMENT_OPTION_HINT: Record<CostRecognitionMethod, string> = {
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
 * Why the deferred option is disabled. Deliberately explains the CONSEQUENCE
 * rather than saying "coming soon": somebody reading this is deciding whether to
 * chase it, and "it would double-count" is the answer to that question.
 */
export const DEFERRAL_UNAVAILABLE_NOTE =
  "Expense-when-consumed is not available for Water yet. It needs the consumption-recognition work, which tracks a purchase's cost through production and charges it as the stock is used. Until that is in place, choosing it would leave the cost recognised at purchase AND again at consumption, so the setting is locked to expense-when-purchased."

/**
 * What deferral will do once it is available. Kept here so the page can describe
 * the option it is disabling, rather than disabling something unexplained.
 */
export const DEFERRAL_FUTURE_NOTE =
  "Once available, a deferred purchase will hold its cost as inventory value and reach Profit & Loss as you record production drawing the stock, so nothing is expensed twice."

// ------------------------------------------------------- reading it back ---
//
// The server decides everything below. These helpers only choose how to SHOW
// it. None of them re-derive a recognition.

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
