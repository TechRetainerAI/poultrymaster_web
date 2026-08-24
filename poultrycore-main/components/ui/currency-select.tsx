"use client"

// Searchable picker over every world currency.
//
// A plain <Select> is unusable at ~300 options, so this is the Popover +
// Command combobox pattern: type to filter by code, name or symbol, arrow keys
// to move, Enter to pick.

import { useMemo, useState } from "react"
import { Check, ChevronsUpDown } from "lucide-react"
import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import {
  Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList,
} from "@/components/ui/command"
import { getAllCurrencies, findCurrency, type CurrencyOption } from "@/lib/constants/currencies"

interface CurrencySelectProps {
  /** ISO code, e.g. "GHS". */
  value: string
  /** Fires with the picked currency so callers can also take its symbol. */
  onChange: (option: CurrencyOption) => void
  disabled?: boolean
  className?: string
  placeholder?: string
  id?: string
}

export function CurrencySelect({
  value, onChange, disabled, className, placeholder = "Pick a currency", id,
}: CurrencySelectProps) {
  const [open, setOpen] = useState(false)
  const currencies = useMemo(() => getAllCurrencies(), [])
  const selected = findCurrency(value)

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button
          id={id}
          type="button"
          variant="outline"
          role="combobox"
          aria-expanded={open}
          disabled={disabled}
          className={cn("w-full justify-between font-normal", !selected && "text-slate-500", className)}
        >
          <span className="truncate">
            {selected ? (
              <>
                <span className="font-medium">{selected.code}</span>
                <span className="text-slate-500"> — {selected.name}</span>
                {selected.symbol !== selected.code && <span className="text-slate-500"> ({selected.symbol})</span>}
              </>
            ) : (
              // A code the runtime doesn't recognise is still shown rather than
              // silently blanked — an existing row must never look empty.
              value || placeholder
            )}
          </span>
          <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-[--radix-popover-trigger-width] p-0" align="start">
        <Command
          filter={(itemValue, search) => {
            // itemValue is "CODE name symbol" (see CommandItem value below), so
            // typing "cedi", "GHS" or "₵" all find the same row.
            const q = search.trim().toLowerCase()
            if (!q) return 1
            return itemValue.toLowerCase().includes(q) ? 1 : 0
          }}
        >
          <CommandInput placeholder="Search code, name or symbol…" />
          <CommandList>
            <CommandEmpty>No currency found.</CommandEmpty>
            <CommandGroup>
              {currencies.map((o) => (
                <CommandItem
                  key={o.code}
                  value={`${o.code} ${o.name} ${o.symbol}`}
                  onSelect={() => { onChange(o); setOpen(false) }}
                >
                  <Check className={cn("mr-2 h-4 w-4", selected?.code === o.code ? "opacity-100" : "opacity-0")} />
                  <span className="font-medium w-12 shrink-0">{o.code}</span>
                  <span className="truncate">{o.name}</span>
                  {o.symbol !== o.code && <span className="ml-auto pl-2 text-slate-500">{o.symbol}</span>}
                </CommandItem>
              ))}
            </CommandGroup>
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  )
}
