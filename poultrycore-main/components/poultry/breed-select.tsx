"use client"

// The breed picker.
//
// A dropdown, because free text made "Isa Brown", "ISA brown" and "Isa-Brown"
// three different breeds to every report that groups by one. But breed data
// already exists and new breeds keep appearing, so the list can never be the
// only way in: there is always an "Other" that takes typing, and a value the
// list has never heard of still shows and stays selected.
//
// What goes in the list lives in lib/poultry/breeds.ts.

import { useState } from "react"
import { Input } from "@/components/ui/input"
import { Button } from "@/components/ui/button"
import { List, Pencil } from "lucide-react"
import {
  Select, SelectContent, SelectGroup, SelectItem, SelectLabel,
  SelectTrigger, SelectValue,
} from "@/components/ui/select"
import { breedKey, groupedBreedOptions } from "@/lib/poultry/breeds"

/** Not a breed anyone can type, so it cannot collide with a real value. */
const OTHER = "__other__"

export interface BreedSelectProps {
  value: string
  onChange: (breed: string) => void
  /** Breeds already used on this farm — offered first. */
  known?: readonly string[]
  disabled?: boolean
  required?: boolean
  placeholder?: string
}

export function BreedSelect({
  value, onChange, known = [], disabled, required, placeholder = "Select a breed",
}: BreedSelectProps) {
  const groups = groupedBreedOptions(known, value)

  // Typing mode is sticky once entered, so a half-typed breed is not thrown away
  // the moment it stops matching anything.
  const [typing, setTyping] = useState(false)

  if (typing) {
    return (
      <div className="flex gap-2">
        <Input
          autoFocus
          placeholder="e.g., Rhode Island Red"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          disabled={disabled}
          required={required}
        />
        <Button type="button" variant="outline" size="icon" className="shrink-0"
          onClick={() => setTyping(false)} disabled={disabled}
          title="Choose from the list instead" aria-label="Choose from the list instead">
          <List className="h-4 w-4" />
        </Button>
      </div>
    )
  }

  return (
    <div className="flex gap-2">
      <Select
        value={breedKey(value) ? value : ""}
        onValueChange={(v) => {
          if (v === OTHER) {
            // Start from empty so the farm types the new breed rather than
            // editing the one that happened to be selected.
            onChange("")
            setTyping(true)
            return
          }
          onChange(v)
        }}
        disabled={disabled}
      >
        <SelectTrigger className="min-w-0">
          <SelectValue placeholder={placeholder} />
        </SelectTrigger>
        <SelectContent>
          {groups.map(({ group, options }) => (
            <SelectGroup key={group}>
              <SelectLabel>{group}</SelectLabel>
              {options.map((o) => (
                <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>
              ))}
            </SelectGroup>
          ))}
          <SelectGroup>
            <SelectItem value={OTHER}>Other — type a breed…</SelectItem>
          </SelectGroup>
        </SelectContent>
      </Select>
      <Button type="button" variant="outline" size="icon" className="shrink-0"
        onClick={() => setTyping(true)} disabled={disabled}
        title="Type a breed instead" aria-label="Type a breed instead">
        <Pencil className="h-4 w-4" />
      </Button>
    </div>
  )
}
