/** Egg size grades for daily production (slot / sort). Legacy DB values P1–P4 map to these. */
export const EGG_GRADE_SELECT_VALUE_NONE = "__none__"

export const EGG_GRADE_OPTIONS: { value: string; label: string }[] = [
  { value: EGG_GRADE_SELECT_VALUE_NONE, label: "Not specified" },
  { value: "Small", label: "Small" },
  { value: "Medium", label: "Medium" },
  { value: "Large", label: "Large" },
  { value: "XLarge", label: "X-Large" },
  { value: "Jumbo", label: "Jumbo" },
  { value: "Seconds", label: "Seconds / B-grade" },
  { value: "Cracks", label: "Cracks" },
  { value: "Mixed", label: "Mixed grades" },
]

/** Maps old layer-farm codes saved in SQL to the new size select values. */
const LEGACY_API_TO_SELECT: Record<string, string> = {
  p1: "Small",
  p2: "Medium",
  p3: "Large",
  p4: "XLarge",
}

export function eggGradeFromApi(value: string | null | undefined): string {
  const v = (value ?? "").trim()
  if (!v) return EGG_GRADE_SELECT_VALUE_NONE
  const mapped = LEGACY_API_TO_SELECT[v.toLowerCase()]
  if (mapped) return mapped
  const hasOption = EGG_GRADE_OPTIONS.some((o) => o.value === v)
  return hasOption ? v : EGG_GRADE_SELECT_VALUE_NONE
}

export function eggGradeToApi(selectValue: string): string | null {
  if (!selectValue || selectValue === EGG_GRADE_SELECT_VALUE_NONE) return null
  return selectValue.trim() || null
}

export function formatEggGradeLabel(value: string | null | undefined): string {
  const v = (value ?? "").trim()
  if (!v) return "—"
  const legacyKey = v.toLowerCase()
  const canonical = LEGACY_API_TO_SELECT[legacyKey]
  const lookup = canonical ?? v
  const opt = EGG_GRADE_OPTIONS.find((o) => o.value === lookup)
  return opt?.label ?? lookup
}
