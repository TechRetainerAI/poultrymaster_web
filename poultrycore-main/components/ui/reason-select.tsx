"use client"

// A reason picked from a list, with "Other" revealing a text box for the
// user's own words. The parent holds ONE string, exactly as it did with a
// plain text field: the picked option's value, or what was typed under
// "Other" (empty until something is typed, so existing `reason.trim()`
// required-checks keep working unchanged).
//
// MUST stay a top-level component -- declared inside a page it would remount
// on every render and the text box would lose focus after one character.

import * as React from "react"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import type { ReasonOption } from "@/lib/reversal-reasons"

export type ReasonSelectProps = {
  options: readonly ReasonOption[]
  value: string
  onChange: (value: string) => void
  id?: string
  placeholder?: string
  /** Placeholder for the box "Other" opens. */
  otherPlaceholder?: string
  /** Which option opens the text box. Defaults to "Other". */
  otherValue?: string
  /** A multi-line box for "Other" instead of a single line. */
  multiline?: boolean
  disabled?: boolean
  className?: string
}

export function ReasonSelect({
  options,
  value,
  onChange,
  id,
  placeholder = "Select a reason",
  otherPlaceholder = "Type the reason",
  otherValue = "Other",
  multiline = false,
  disabled,
  className,
}: ReasonSelectProps) {
  const inList = (v: string) => options.some((o) => o.value === v && o.value !== otherValue)
  const [choice, setChoice] = React.useState<string>(() => (inList(value) ? value : value ? otherValue : ""))
  const textRef = React.useRef<HTMLInputElement & HTMLTextAreaElement>(null)

  // Follow the parent when it sets or clears the value itself (e.g. a reset on
  // open). An empty value while "Other" is open just means nothing typed yet.
  React.useEffect(() => {
    if (inList(value)) setChoice(value)
    else if (!value && choice !== otherValue) setChoice("")
    else if (value && choice !== otherValue) setChoice(otherValue)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value])

  function pick(v: string) {
    setChoice(v)
    if (v === otherValue) {
      onChange("")
      // After the Radix select has closed, or it takes the focus back.
      setTimeout(() => textRef.current?.focus(), 60)
    } else {
      onChange(v)
    }
  }

  const isOther = choice === otherValue
  return (
    <div className={className}>
      <Select value={choice} onValueChange={pick} disabled={disabled}>
        <SelectTrigger id={id}><SelectValue placeholder={placeholder} /></SelectTrigger>
        <SelectContent>
          {options.map((o) => <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>)}
        </SelectContent>
      </Select>
      {isOther && (multiline ? (
        <Textarea ref={textRef} rows={2} className="mt-1.5" value={value} placeholder={otherPlaceholder}
          onChange={(e) => onChange(e.target.value)} disabled={disabled} />
      ) : (
        <Input ref={textRef} className="mt-1.5" value={value} placeholder={otherPlaceholder}
          onChange={(e) => onChange(e.target.value)}
          // Enter must not reach an enclosing form and submit it half-filled.
          onKeyDown={(e) => { if (e.key === "Enter") e.preventDefault() }}
          disabled={disabled} />
      ))}
    </div>
  )
}
