"use client"

/**
 * The New sale dialog's shell (app/sales/page.tsx), shared so every form
 * dialog looks like it:
 *
 *   <DialogContent className={cn(FORM_DIALOG_CONTENT, "sm:max-w-2xl")}>
 *     <DialogHeader>
 *       <FormDialogTitle icon={PiggyBank} color="blue">Add customer credit</FormDialogTitle>
 *       <DialogDescription>...</DialogDescription>
 *     </DialogHeader>
 *     <div className="min-w-0 space-y-4">
 *       <FormSection title="Customer & Date" color="blue" tinted>...</FormSection>
 *     </div>
 *     <FormDialogFooter onCancel={close}>
 *       <Button className={FORM_DIALOG_PRIMARY.blue}>Add credit · GH₵ 50.00</Button>
 *     </FormDialogFooter>
 *   </DialogContent>
 *
 * The dialog itself is the only scroll area and the footer is pinned to its
 * bottom, so the buttons stay in reach on a long form. That is why the content
 * has no bottom padding: the footer supplies it.
 */

import type { ComponentType, ReactNode } from "react"
import { Button } from "@/components/ui/button"
import { DialogTitle } from "@/components/ui/dialog"
import { cn } from "@/lib/utils"

/** Width is the caller's, and MUST carry the sm: prefix (see ui/dialog.tsx). */
export const FORM_DIALOG_CONTENT = "w-[95vw] max-h-[92vh] gap-4 overflow-y-auto p-4 pb-0 sm:p-6 sm:pb-0"

const TILE = {
  blue:    "bg-blue-600",
  green:   "bg-green-600",
  emerald: "bg-emerald-600",
  amber:   "bg-amber-500",
  rose:    "bg-rose-600",
  red:     "bg-red-600",
  purple:  "bg-purple-600",
  slate:   "bg-slate-700",
} as const

export type FormDialogColor = keyof typeof TILE

/** Primary button colours, matching the tile. */
export const FORM_DIALOG_PRIMARY: Record<FormDialogColor, string> = {
  blue:    "bg-blue-600 text-white hover:bg-blue-700",
  green:   "bg-green-600 text-white hover:bg-green-700",
  emerald: "bg-emerald-600 text-white hover:bg-emerald-700",
  amber:   "bg-amber-500 text-white hover:bg-amber-600",
  rose:    "bg-rose-600 text-white hover:bg-rose-700",
  red:     "bg-red-600 text-white hover:bg-red-700",
  purple:  "bg-purple-600 text-white hover:bg-purple-700",
  slate:   "bg-slate-700 text-white hover:bg-slate-800",
}

/** DialogTitle with the solid icon tile. */
export function FormDialogTitle({
  icon: Icon, color = "blue", children, className,
}: {
  icon: ComponentType<{ className?: string }>
  color?: FormDialogColor
  children: ReactNode
  className?: string
}) {
  return (
    <DialogTitle className={cn("flex items-center gap-2.5 text-left", className)}>
      <span className={cn("flex h-9 w-9 shrink-0 items-center justify-center rounded-lg text-white", TILE[color])}>
        <Icon className="h-5 w-5" />
      </span>
      <span className="min-w-0">{children}</span>
    </DialogTitle>
  )
}

/**
 * Sticky footer: the red-outline Cancel, then the caller's primary action(s).
 * Pass `cancelLabel="Close"` on a read-only dialog with no primary action.
 */
export function FormDialogFooter({
  onCancel, cancelLabel = "Cancel", cancelDisabled, children,
}: {
  onCancel: () => void
  cancelLabel?: string
  cancelDisabled?: boolean
  children?: ReactNode
}) {
  return (
    <div className="sticky bottom-0 z-10 -mx-4 flex flex-col-reverse gap-2 border-t bg-white px-4 py-3 sm:-mx-6 sm:flex-row sm:justify-end sm:px-6 [&>button]:w-full sm:[&>button]:w-auto">
      <Button variant="outline" onClick={onCancel} disabled={cancelDisabled}
              className="border-red-200 text-red-600 hover:bg-red-50 hover:text-red-700">
        {cancelLabel}
      </Button>
      {children}
    </div>
  )
}
