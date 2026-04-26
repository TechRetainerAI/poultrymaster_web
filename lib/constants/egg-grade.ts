/** Egg size grades for daily production records. */
export const EGG_GRADE_SELECT_VALUE_NONE = "__none__"

export const EGG_GRADE_OPTIONS: { value: string; label: string }[] = [
  { value: EGG_GRADE_SELECT_VALUE_NONE, label: "Not specified" },
  { value: "Small", label: "Small" },
  { value: "Medium", label: "Medium" },
  { value: "Large", label: "Large" },
  { value: "XLarge", label: "XLarge" },
  { value: "Jumbo", label: "Jumbo" },
]

export function eggGradeFromApi(value: string | null | undefined): string {
  const v = (value ?? "").trim()
  return v || EGG_GRADE_SELECT_VALUE_NONE
}

export function eggGradeToApi(selectValue: string): string | null {
  if (!selectValue || selectValue === EGG_GRADE_SELECT_VALUE_NONE) return null
  return selectValue.trim() || null
}

export function formatEggGradeLabel(value: string | null | undefined): string {
  const v = (value ?? "").trim()
  if (!v) return "—"
  const opt = EGG_GRADE_OPTIONS.find((o) => o.value === v)
  return opt?.label ?? v
}
