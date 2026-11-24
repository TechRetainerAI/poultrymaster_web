"use client"

// "Related Project / Contract" -- the one selector every Generic transaction
// form uses. Searchable (a company may run dozens of contracts), with
// "General company activity" first: most transactions belong to no project,
// and that is a real choice, not a missing one.

import { useMemo, useState } from "react"
import { Check, ChevronsUpDown, Briefcase } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from "@/components/ui/command"
import { cn } from "@/lib/utils"
import { useProjectOptions } from "@/hooks/use-generic-projects"
import { statusLabel } from "@/lib/api/generic-projects"

export const GENERAL_LABEL = "General company activity"

export function ProjectPicker({
  value, onChange, id, className, includeClosed = false, disabled, placeholder = GENERAL_LABEL, allowGeneral = true,
}: {
  /** null = General company activity */
  value: number | null
  onChange: (projectId: number | null) => void
  id?: string
  className?: string
  includeClosed?: boolean
  disabled?: boolean
  placeholder?: string
  allowGeneral?: boolean
}) {
  const [open, setOpen] = useState(false)
  const { options, loading } = useProjectOptions(includeClosed)
  const selected = options.find((o) => o.projectId === value) ?? null

  const groups = useMemo(() => ({
    contracts: options.filter((o) => o.kind === "Contract"),
    projects: options.filter((o) => o.kind === "Project"),
  }), [options])

  const pick = (v: number | null) => { onChange(v); setOpen(false) }

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button id={id} type="button" variant="outline" role="combobox" aria-expanded={open} disabled={disabled}
          className={cn("w-full min-w-48 justify-between bg-white font-normal", !selected && "text-slate-500", className)}>
          <span className="flex min-w-0 items-center gap-2 truncate">
            <Briefcase className="h-4 w-4 shrink-0 text-slate-400" />
            {selected
              ? <span className="truncate"><span className="font-medium text-slate-900">{selected.projectNumber}</span> — {selected.name}</span>
              : value != null && loading ? "Loading…" : placeholder}
          </span>
          <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-96 p-0" align="start">
        <Command filter={(v, s) => (v.toLowerCase().includes(s.trim().toLowerCase()) ? 1 : 0)}>
          <CommandInput placeholder="Search number, name or contract…" />
          <CommandList className="max-h-80">
            <CommandEmpty>{loading ? "Loading projects…" : "No project matches."}</CommandEmpty>
            {allowGeneral && (
              <CommandGroup>
                <CommandItem value="general company activity none unassigned" onSelect={() => pick(null)}>
                  <Check className={cn("mr-2 h-4 w-4", value == null ? "opacity-100" : "opacity-0")} />
                  {GENERAL_LABEL}
                </CommandItem>
              </CommandGroup>
            )}
            {(["contracts", "projects"] as const).map((g) => groups[g].length > 0 && (
              <CommandGroup key={g} heading={g === "contracts" ? "Contracts" : "Projects"}>
                {groups[g].map((o) => (
                  <CommandItem key={o.projectId} value={`${o.projectNumber} ${o.name} #${o.projectId}`} onSelect={() => pick(o.projectId)}>
                    <Check className={cn("mr-2 h-4 w-4 shrink-0", value === o.projectId ? "opacity-100" : "opacity-0")} />
                    <span className="truncate"><span className="font-medium">{o.projectNumber}</span> — {o.name}</span>
                    {o.status !== "Active" && (
                      <span className="ml-auto shrink-0 rounded-full bg-slate-100 px-1.5 py-0.5 text-[10px] text-slate-600">{statusLabel(o.status)}</span>
                    )}
                  </CommandItem>
                ))}
              </CommandGroup>
            ))}
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  )
}
