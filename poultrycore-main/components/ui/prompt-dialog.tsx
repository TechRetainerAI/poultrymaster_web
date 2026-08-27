"use client"

// Drop-in replacement for window.prompt() — system prompts look like browser
// chrome and operators dismiss them by accident. Same shape as
// ConfirmDeleteDialog: caller controls open state, supplies an onSubmit handler
// that receives the trimmed string. Returns immediately if the user submits an
// empty value unless `allowEmpty` is set (e.g. optional cancel reasons).

import * as React from "react"
import { Loader2 } from "lucide-react"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Button, buttonVariants } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { cn } from "@/lib/utils"

export type PromptDialogProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  title: string
  description?: React.ReactNode
  label?: string
  placeholder?: string
  defaultValue?: string
  /** Submit button label. Defaults to "Confirm". */
  confirmLabel?: string
  /** Submit button visual variant. Defaults to "default" (primary). */
  confirmVariant?: "default" | "destructive"
  /** Use a single-line input instead of a multiline textarea. */
  singleLine?: boolean
  /** Allow submitting an empty value (e.g. optional cancel reasons). */
  allowEmpty?: boolean
  /**
   * When set, the value is PICKED from this list instead of typed. The chosen
   * option's `value` is what onSubmit receives, so the list doubles as the
   * stored vocabulary.
   *
   * Choosing `otherValue` reveals the free-text field underneath and submits
   * what was typed instead — a fixed list never covers everything, and forcing
   * someone into the nearest wrong option corrupts the data worse than free
   * text does. Omit `options` entirely and the dialog behaves exactly as it
   * always has, which is what its other callers rely on.
   */
  options?: readonly { value: string; label: string }[]
  /** Which option opens the free-text box. Defaults to "Other". */
  otherValue?: string
  onSubmit: (value: string) => Promise<unknown> | unknown
}

export function PromptDialog({
  open,
  onOpenChange,
  title,
  description,
  label,
  placeholder,
  defaultValue = "",
  confirmLabel = "Confirm",
  confirmVariant = "default",
  singleLine = false,
  allowEmpty = false,
  options,
  otherValue = "Other",
  onSubmit,
}: PromptDialogProps) {
  const [value, setValue] = React.useState(defaultValue)
  const [choice, setChoice] = React.useState("")
  const [submitting, setSubmitting] = React.useState(false)
  const [error, setError] = React.useState<string | null>(null)

  const isOther = !!options && choice === otherValue
  // With a list, the free-text box only appears for "Other".
  const showText = !options || isOther

  // Reset when the dialog opens so a previous run's text isn't shown stale.
  React.useEffect(() => {
    if (open) {
      setValue(defaultValue)
      setChoice("")
      setError(null)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open])

  const handleSubmit = async () => {
    const trimmed = value.trim()

    if (options) {
      if (!choice) {
        setError(`${label ?? "Value"} is required.`)
        return
      }
      // A picked option submits itself; "Other" submits what was typed.
      if (!isOther) {
        await runSubmit(choice)
        return
      }
    }

    if (!allowEmpty && !trimmed) {
      setError(`${label ?? "Value"} is required.`)
      return
    }
    await runSubmit(trimmed)
  }

  async function runSubmit(submitted: string) {
    try {
      setSubmitting(true)
      setError(null)
      await onSubmit(submitted)
      onOpenChange(false)
    } catch (e: any) {
      setError(e?.message ?? "Something went wrong.")
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={(v) => { if (!submitting) onOpenChange(v) }}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          {description && <DialogDescription>{description}</DialogDescription>}
        </DialogHeader>
        <div className="space-y-2">
          {label && <Label>{label}</Label>}
          {options && (
            <Select value={choice} onValueChange={(v) => { setChoice(v); setError(null) }}>
              <SelectTrigger>
                <SelectValue placeholder={placeholder ?? "Select a reason"} />
              </SelectTrigger>
              <SelectContent>
                {options.map((o) => (
                  <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          )}
          {showText && (singleLine ? (
            <Input
              autoFocus
              value={value}
              onChange={(e) => setValue(e.target.value)}
              placeholder={placeholder}
              onKeyDown={(e) => { if (e.key === "Enter") void handleSubmit() }}
            />
          ) : (
            <Textarea
              autoFocus
              rows={4}
              value={value}
              onChange={(e) => setValue(e.target.value)}
              placeholder={options ? "Say what happened" : placeholder}
            />
          ))}
          {error && <p className="text-sm text-rose-700">{error}</p>}
        </div>
        <DialogFooter className="gap-2">
          <Button variant="ghost" onClick={() => onOpenChange(false)} disabled={submitting}>
            Cancel
          </Button>
          <Button
            type="button"
            className={cn(confirmVariant === "destructive" ? buttonVariants({ variant: "destructive" }) : undefined)}
            onClick={handleSubmit}
            disabled={submitting}
          >
            {submitting && <Loader2 className="h-4 w-4 animate-spin mr-1" />}
            {confirmLabel}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
