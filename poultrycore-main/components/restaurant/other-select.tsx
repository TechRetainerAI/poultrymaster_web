"use client"

import { useEffect, useMemo, useRef, useState } from "react"
import { Check, Loader2, X } from "lucide-react"
import { Button } from "@/components/ui/button"
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
 * Picking "Other" reveals a text box; what gets typed is applied to the record
 * immediately and — on Save — remembered against this farm so it appears as a
 * normal option from then on. See Migrations/291 for the storage, and
 * lib/api/restaurant.ts `listCustomOptions` for why a missing endpoint is not an
 * error.
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
  className?: string
  disabled?: boolean
}

export function OtherSelect({
  listKey,
  baseOptions,
  value,
  onChange,
  placeholder = "Select",
  includeNone = false,
  otherLabel = "Other (type your own)",
  className,
  disabled,
}: OtherSelectProps) {
  const { toast } = useToast()
  const [custom, setCustom] = useState<string[]>([])
  const [typing, setTyping] = useState(false)
  const [draft, setDraft] = useState("")
  const [saving, setSaving] = useState(false)
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
   * that value when the form was saved.
   */
  const options = useMemo(() => {
    const seen = new Set<string>()
    const out: string[] = []
    for (const o of [...baseOptions, ...custom, ...(value ? [value] : [])]) {
      const v = (o ?? "").trim()
      if (!v || v.toLowerCase() === "other") continue
      const k = v.toLowerCase()
      if (seen.has(k)) continue
      seen.add(k)
      out.push(v)
    }
    return out
  }, [baseOptions, custom, value])

  function handleSelect(v: string) {
    if (v === OTHER) {
      setDraft("")
      setTyping(true)
      // Focus after the Radix select has closed, or it steals focus straight back.
      setTimeout(() => inputRef.current?.focus(), 60)
      return
    }
    setTyping(false)
    onChange(v === NONE ? undefined : v)
  }

  async function save() {
    const v = draft.trim()
    if (!v) { setTyping(false); return }

    // Apply it to the record first. Whether we manage to REMEMBER it is a
    // separate concern from whether this form gets the value the operator typed.
    onChange(v)
    setSaving(true)
    try {
      await createCustomOption(listKey, v)
      setCustom(prev =>
        prev.some(p => p.toLowerCase() === v.toLowerCase()) ? prev : [...prev, v])
      setTyping(false)
      setDraft("")
      toast({ title: "Saved", description: `"${v}" will be in the list next time.` })
    } catch (e: any) {
      // Keep the box open so the value is visibly still there, and say plainly
      // that only the remembering failed.
      toast({
        title: "Applied, but not remembered",
        description: e?.message ?? "Could not save it for next time. It still applies to this record.",
        variant: "destructive",
      })
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className={className}>
      {!typing ? (
        <Select value={value || (includeNone ? NONE : "")} onValueChange={handleSelect} disabled={disabled}>
          <SelectTrigger className="h-10 w-full"><SelectValue placeholder={placeholder} /></SelectTrigger>
          <SelectContent>
            {includeNone && <SelectItem value={NONE}>None</SelectItem>}
            {options.map(o => <SelectItem key={o} value={o}>{o}</SelectItem>)}
            <SelectItem value={OTHER} className="text-rose-600 font-medium">{otherLabel}</SelectItem>
          </SelectContent>
        </Select>
      ) : (
        // Stacks on a phone so the text box gets the full width; the two buttons
        // sit beside it from sm up.
        <div className="flex flex-col sm:flex-row gap-2">
          <Input
            ref={inputRef}
            className="h-10 flex-1"
            placeholder="Type it, then Save"
            value={draft}
            onChange={e => { setDraft(e.target.value); onChange(e.target.value.trim() || undefined) }}
            onKeyDown={e => {
              // Enter must not reach an enclosing form and submit the dialog.
              if (e.key === "Enter") { e.preventDefault(); save() }
              if (e.key === "Escape") { e.preventDefault(); setTyping(false); setDraft(""); onChange(undefined) }
            }}
          />
          <div className="flex gap-2">
            <Button
              type="button" onClick={save} disabled={saving || !draft.trim()}
              className="h-10 flex-1 sm:flex-none bg-rose-600 hover:bg-rose-700"
            >
              {saving
                ? <><Loader2 className="h-4 w-4 mr-1 animate-spin" /> Saving</>
                : <><Check className="h-4 w-4 mr-1" /> Save</>}
            </Button>
            <Button
              type="button" variant="outline" className="h-10 flex-1 sm:flex-none"
              onClick={() => { setTyping(false); setDraft(""); onChange(undefined) }}
            >
              <X className="h-4 w-4 mr-1" /> Cancel
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}
