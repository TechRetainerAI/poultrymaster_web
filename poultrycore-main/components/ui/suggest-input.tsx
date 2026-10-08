"use client"

// Free-text field with a pick list: type anything, or open the list and pick.
//
// Replaces <Input list="..."> + <datalist>. A datalist only offers options that
// match what is already typed, so once a value is picked the other options
// vanish and it looks as if the choice can't be changed. Here the chevron
// always opens the FULL list.

import { useState } from "react"
import { Check, ChevronsUpDown } from "lucide-react"
import { cn } from "@/lib/utils"
import { Input } from "@/components/ui/input"
import { Popover, PopoverAnchor, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import {
  Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList,
} from "@/components/ui/command"

interface SuggestInputProps {
  value: string
  onChange: (value: string) => void
  suggestions: string[]
  placeholder?: string
  disabled?: boolean
  className?: string
  id?: string
}

export function SuggestInput({
  value, onChange, suggestions, placeholder, disabled, className, id,
}: SuggestInputProps) {
  const [open, setOpen] = useState(false)
  const options = Array.from(new Set(suggestions.map((s) => s.trim()).filter(Boolean)))
  const current = value.trim().toLowerCase()

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverAnchor asChild>
        <div className={cn("relative", className)}>
          <Input
            id={id}
            value={value}
            disabled={disabled}
            placeholder={placeholder}
            autoComplete="off"
            className="pr-9"
            onChange={(e) => onChange(e.target.value)}
            onKeyDown={(e) => { if (e.key === "ArrowDown" && options.length) { e.preventDefault(); setOpen(true) } }}
          />
          {options.length > 0 && (
            <PopoverTrigger asChild>
              <button
                type="button"
                disabled={disabled}
                aria-label="Show options"
                className="absolute inset-y-0 right-0 flex w-9 items-center justify-center text-slate-400 hover:text-slate-600 disabled:opacity-50"
              >
                <ChevronsUpDown className="h-4 w-4" />
              </button>
            </PopoverTrigger>
          )}
        </div>
      </PopoverAnchor>
      <PopoverContent className="w-[--radix-popover-trigger-width] min-w-[12rem] p-0" align="start"
        onOpenAutoFocus={(e) => { if (options.length < 8) e.preventDefault() }}>
        <Command>
          {options.length >= 8 && <CommandInput placeholder="Search…" />}
          <CommandList>
            <CommandEmpty>No match. Type it in the box instead.</CommandEmpty>
            <CommandGroup>
              {options.map((o) => (
                <CommandItem key={o} value={o} onSelect={() => { onChange(o); setOpen(false) }}>
                  <Check className={cn("mr-2 h-4 w-4", o.toLowerCase() === current ? "opacity-100" : "opacity-0")} />
                  {o}
                </CommandItem>
              ))}
            </CommandGroup>
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  )
}
