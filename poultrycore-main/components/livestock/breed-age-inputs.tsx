"use client"

// Breed dropdown and age-with-unit inputs for the livestock forms.

import { useEffect, useState } from "react"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { type AgeUnit, ageText, ageToDays, breedsFor, daysToAge, parseAgeText } from "@/lib/livestock/breeds"

const OTHER = "__other"
const NONE = "__none"

/**
 * Pick a breed for the chosen kind of animal, or "Other" to type one. A saved
 * breed that is not in the list (typed before, or by hand) opens as "Other"
 * with its text kept.
 */
export function BreedSelect({ id, speciesCode, value, onChange, placeholder = "Choose a breed", className }: {
  id?: string; speciesCode: string | null | undefined; value: string | null; onChange: (v: string | null) => void
  placeholder?: string; className?: string
}) {
  const options = breedsFor(speciesCode)
  const known = !value || options.includes(value)
  const [typing, setTyping] = useState(!known)
  useEffect(() => { if (value && !options.includes(value)) setTyping(true) }, [value, speciesCode]) // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <div className={`space-y-1.5 ${className ?? ""}`}>
      <Select value={typing ? OTHER : value ?? NONE}
        onValueChange={(v) => {
          if (v === OTHER) { setTyping(true); onChange(known ? null : value) }
          else { setTyping(false); onChange(v === NONE ? null : v) }
        }}>
        <SelectTrigger id={id}><SelectValue placeholder={placeholder} /></SelectTrigger>
        <SelectContent className="max-h-72">
          <SelectItem value={NONE}>Not given</SelectItem>
          {options.map((b) => <SelectItem key={b} value={b}>{b}</SelectItem>)}
          <SelectItem value={OTHER}>Other (type it)</SelectItem>
        </SelectContent>
      </Select>
      {typing && <Input aria-label="Breed" placeholder="Type the breed" value={value ?? ""} autoFocus={!value} onChange={(e) => onChange(e.target.value || null)} />}
    </div>
  )
}

function AgeFields({ id, n, unit, onChange }: { id?: string; n: string; unit: AgeUnit; onChange: (n: string, unit: AgeUnit) => void }) {
  return (
    <div className="flex gap-2">
      <Input id={id} type="number" min={0} step="any" inputMode="decimal" className="min-w-0 flex-1" placeholder="e.g. 8" value={n}
        onChange={(e) => onChange(e.target.value, unit)} />
      <Select value={unit} onValueChange={(u) => onChange(n, u as AgeUnit)}>
        <SelectTrigger className="w-28 shrink-0" aria-label="Unit"><SelectValue /></SelectTrigger>
        <SelectContent>
          <SelectItem value="days">Days</SelectItem>
          <SelectItem value="weeks">Weeks</SelectItem>
          <SelectItem value="months">Months</SelectItem>
          <SelectItem value="years">Years</SelectItem>
        </SelectContent>
      </Select>
    </div>
  )
}

/** Age kept as a number of days (groups). Shows e.g. 56 days as "8 weeks". */
export function AgeDaysInput({ id, value, onChange }: { id?: string; value: number | null; onChange: (days: number | null) => void }) {
  const start = value != null ? daysToAge(value) : null
  const [n, setN] = useState(start ? String(start.n) : "")
  const [unit, setUnit] = useState<AgeUnit>(start?.unit ?? "weeks")
  return (
    <AgeFields id={id} n={n} unit={unit} onChange={(nn, uu) => {
      setN(nn); setUnit(uu)
      onChange(nn === "" || Number(nn) < 0 ? null : ageToDays(Number(nn), uu))
    }} />
  )
}

/** Age kept as words (intake batches, purchases): "8 weeks". Older free text it cannot read is shown under the fields. */
export function AgeTextInput({ id, value, onChange }: { id?: string; value: string | null; onChange: (text: string | null) => void }) {
  const parsed = parseAgeText(value)
  const [n, setN] = useState(parsed ? String(parsed.n) : "")
  const [unit, setUnit] = useState<AgeUnit>(parsed?.unit ?? "weeks")
  const legacy = value && !parsed ? value : null
  return (
    <div className="space-y-1">
      <AgeFields id={id} n={n} unit={unit} onChange={(nn, uu) => {
        setN(nn); setUnit(uu)
        onChange(nn === "" || Number(nn) < 0 ? null : ageText(Number(nn), uu))
      }} />
      {legacy && <p className="text-xs text-stone-500">Saved as "{legacy}". Enter a number to replace it.</p>}
    </div>
  )
}
