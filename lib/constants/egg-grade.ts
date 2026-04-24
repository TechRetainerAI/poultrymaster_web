/** Egg quality grades for daily production (common layer-farm labels). */
export const EGG_GRADE_SELECT_VALUE_NONE = "__none__"

export const EGG_GRADE_OPTIONS: { value: string; label: string }[] = [
  { value: EGG_GRADE_SELECT_VALUE_NONE, label: "Not specified" },
  { value: "P1", label: "P1" },
  { value: "P2", label: "P2" },
  { value: "P3", label: "P3" },
  { value: "P4", label: "P4" },
  { value: "Seconds", label: "Seconds / B-grade" },
  { value: "Cracks", label: "Cracks" },
  { value: "Mixed", label: "Mixed grades" },
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
