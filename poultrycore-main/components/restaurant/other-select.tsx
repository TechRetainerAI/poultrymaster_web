"use client"

import { forwardRef, useEffect, useImperativeHandle, useMemo, useRef, useState } from "react"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { useToast } from "@/hooks/use-toast"
import {
  createCustomOption, listCustomOptions,
  type CustomOptionListKey,
} from "@/lib/api/restaurant"

/**
 * A dropdown whose "Other" choice actually works.
 *
 * Picking "Other" leaves the dropdown in place and reveals a text box beneath
 * it; what gets typed is applied to the record as it is typed. Remembering it
 * for next time happens when the surrounding form is submitted — the parent
 * calls `remember()` on this component's ref after its own save succeeded.
 *
 * This mirrors Add Menu Item (app/restaurant-menu/page.tsx, Item Name and
 * Category), which is the behaviour the operator asked every "Other" dropdown
 * to copy. There are deliberately NO Save/Cancel buttons inside the field: two
 * extra buttons inside a dialog that already has its own footer buttons read as
 * a second, competing form. To back out of "Other", pick something else from
 * the dropdown, which is still sitting right above the text box.
 *
 * See Migrations/291 for the storage, and lib/api/restaurant.ts
 * `listCustomOptions` for why a missing endpoint is not an error.
 *
 * Used by: restaurant-inventory (ingredient category, waste reason),
 * restaurant-reservations (occasion), restaurant-setup (cuisine type).
 *
 * MUST stay a top-level component. Declaring it inside a page component would
 * give it a new identity on every render, React would remount the subtree, and
 * the text box would lose focus after a single character — the exact bug fixed
 * on 2026-09-08 in restaurant-order-online (see plan/plan.md).
 */

const OTHER = "__other__"
const NONE = "__none__"

export interface OtherSelectHandle {
  /**
   * Persist whatever was typed under "Other" so it is a normal option next
   * time. Always resolves: failing to memorise a value must never look like
   * the record itself failed to save. A no-op unless "Other" is in use.
   */
  remember: () => Promise<void>
}

export interface OtherSelectProps {
  /** Which remembered list this dropdown draws from. */
  listKey: CustomOptionListKey
  /** The options that ship with the product. Not stored in the database. */
  baseOptions: readonly string[]
  value?: string
  onChange: (value: string | undefined) => void
  placeholder?: string
  /** Adds a "None" choice that clears the value. */
  includeNone?: boolean
  /** Label for the "Other" row, e.g. "Other (type it)". */
  otherLabel?: string
  /** Placeholder for the text box that "Other" reveals. */
  typePlaceholder?: string
  className?: string
  disabled?: boolean
}

export const OtherSelect = forwardRef<OtherSelectHandle, OtherSelectProps>(function OtherSelect({
  listKey,
  baseOptions,
  value,
  onChange,
  placeholder = "Select",
  includeNone = false,
  otherLabel = "Other (type your own)",
  typePlaceholder = "Type your own",
  className,
  disabled,
}, ref) {
  const { toast } = useToast()
  const [custom, setCustom] = useState<string[]>([])
  const [typing, setTyping] = useState(false)
  const inputRef = useRef<HTMLInputElement>(null)

  // Remembered values for this list. Failure is silent by design — the dropdown
  // still works with the built-in options.
  useEffect(() => {
    let alive = true
    listCustomOptions(listKey)
      .then(rows => { if (alive) setCustom(rows.map(r => r.value)) })
      .catch(() => { /* listCustomOptions already swallows; belt and braces */ })
    return () => { alive = false }
  }, [listKey])

  /**
   * Everything pickable, de-duplicated case-insensitively so a remembered value
   * that later becomes a built-in cannot appear twice.
   *
   * `value` is folded in even when it is in neither list: an existing record may
   * hold a value that was typed before this list existed, or one that has since
   * been removed. Without this the Select would render blank and silently drop
   * that value when the form was saved. While the operator is typing it is left
   * out — a half-typed word has no business appearing as an option.
   */
  const options = useMemo(() => {
    const seen = new Set<string>()
    const out: string[] = []
    for (const o of [...baseOptions, ...custom, ...(!typing && value ? [value] : [])]) {
      const v = (o ?? "").trim()
      if (!v || v.toLowerCase() === "other") continue
      const k = v.toLowerCase()
      if (seen.has(k)) continue
      seen.add(k)
      out.push(v)
    }
    return out
  }, [baseOptions, custom, value, typing])

  function handleSelect(v: string) {
    if (v === OTHER) {
      setTyping(true)
      onChange(undefined)
      // Focus after the Radix select has closed, or it steals focus straight back.
      setTimeout(() => inputRef.current?.focus(), 60)
      return
    }
    setTyping(false)
    onChange(v === NONE ? undefined : v)
  }

  useImperativeHandle(ref, () => ({
    async remember() {
      if (!typing) return
      const v = (value ?? "").trim()
      if (!v) return
      try {
        await createCustomOption(listKey, v)
        setCustom(prev =>
          prev.some(p => p.toLowerCase() === v.toLowerCase()) ? prev : [...prev, v])
        // Back to the dropdown, with the typed value now sitting in it as a
        // normal option. Matters on restaurant-setup, where the field is on a
        // page rather than in a dialog that unmounts on save.
        setTyping(false)
      } catch (e: any) {
        toast({
          title: "Saved, but the value was not remembered",
          description: e?.message ?? "It applies to this record; it just will not be in the list next time.",
        })
      }
    },
  }), [typing, value, listKey, toast])

  return (
    <div className={className}>
      <Select
        value={typing ? OTHER : (value || (includeNone ? NONE : ""))}
        onValueChange={handleSelect}
        disabled={disabled}
      >
        <SelectTrigger className="h-10 w-full"><SelectValue placeholder={placeholder} /></SelectTrigger>
        <SelectContent>
          {includeNone && <SelectItem value={NONE}>None</SelectItem>}
          {options.map(o => <SelectItem key={o} value={o}>{o}</SelectItem>)}
          <SelectItem value={OTHER} className="text-rose-600 font-medium">{otherLabel}</SelectItem>
        </SelectContent>
      </Select>
      {typing && (
        <Input
          ref={inputRef}
          className="h-10 mt-1.5"
          placeholder={typePlaceholder}
          value={value ?? ""}
          onChange={e => onChange(e.target.value || undefined)}
          // Enter must not reach an enclosing form and submit the dialog.
          onKeyDown={e => { if (e.key === "Enter") e.preventDefault() }}
          disabled={disabled}
        />
      )}
    </div>
  )
})
