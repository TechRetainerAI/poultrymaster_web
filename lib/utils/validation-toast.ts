import type { ReactNode } from "react"

/**
 * Friendly form-validation feedback (missing dropdowns, empty required fields).
 * Prefer this over `variant: "destructive"` for user-fixable issues so it does not
 * read like a system error. Keep `destructive` for auth failures, server errors, deletes.
 */

export const FORM_GUIDE_TITLE = "Almost there"

export type FormGuideToast = (props: {
  title?: ReactNode
  description?: ReactNode
  variant?: "default" | "destructive" | "warning"
}) => void

export function toastFormGuide(
  toast: FormGuideToast,
  description: string,
  title: string = FORM_GUIDE_TITLE,
) {
  toast({ title, description, variant: "warning" })
}
