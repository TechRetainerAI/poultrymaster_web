"use client"

// The "Project / Contract" filter for Generic reports and lists. Hidden when
// the module is off, so a company that never used projects sees its pages
// exactly as before. "All projects / entire company" never changes a result.

import { useMemo, useState } from "react"
import { Check, ChevronsUpDown, Briefcase } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { Command, CommandGroup, CommandInput, CommandItem, CommandList, CommandEmpty, CommandSeparator } from "@/components/ui/command"
import { cn } from "@/lib/utils"
import { useProjectOptions, useProjectsEnabled } from "@/hooks/use-generic-projects"
import { ALL_PROJECTS, type ProjectFilterValue } from "@/lib/generic/project-math"

export function ProjectFilter({
  value, onChange, className, multiple = true, showWhenDisabled = false,
}: {
  value: ProjectFilterValue
  onChange: (v: ProjectFilterValue) => void
  className?: string
  multiple?: boolean
  /** Show even when the module is off (a company that switched it off can still read history). */
  showWhenDisabled?: boolean
}) {
  const { enabled } = useProjectsEnabled()
  const { options } = useProjectOptions(true)
  const [open, setOpen] = useState(false)

  const label = useMemo(() => {
    if (value.kind === "all") return "All projects (entire company)"
    if (value.kind === "general") return "General company activity"
    if (value.ids.length === 1) {
      const o = options.find((x) => x.projectId === value.ids[0])
      return o ? `${o.projectNumber} — ${o.name}` : "1 project"
    }
    return `${value.ids.length} projects`
  }, [value, options])

  if (!enabled && !showWhenDisabled && value.kind === "all") return null

  const toggleId = (id: number) => {
    if (!multiple) { onChange({ kind: "projects", ids: [id] }); setOpen(false); return }
    const current = value.kind === "projects" ? value.ids : []
    const next = current.includes(id) ? current.filter((x) => x !== id) : [...current, id]
    onChange(next.length ? { kind: "projects", ids: next } : ALL_PROJECTS)
  }

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button type="button" variant="outline" role="combobox" aria-expanded={open} aria-label="Project / contract filter"
          className={cn("min-w-56 justify-between bg-white font-normal", value.kind !== "all" && "border-indigo-300 bg-indigo-50/50", className)}>
          <span className="flex min-w-0 items-center gap-2 truncate">
            <Briefcase className="h-4 w-4 shrink-0 text-slate-400" /><span className="truncate">{label}</span>
          </span>
          <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-96 p-0" align="start">
        <Command filter={(v, s) => (v.toLowerCase().includes(s.trim().toLowerCase()) ? 1 : 0)}>
          <CommandInput placeholder="Search projects…" />
          <CommandList className="max-h-80">
            <CommandEmpty>No project matches.</CommandEmpty>
            <CommandGroup>
              <CommandItem value="all projects entire company" onSelect={() => { onChange(ALL_PROJECTS); setOpen(false) }}>
                <Check className={cn("mr-2 h-4 w-4", value.kind === "all" ? "opacity-100" : "opacity-0")} />All projects (entire company)
              </CommandItem>
              <CommandItem value="general company activity unassigned" onSelect={() => { onChange({ kind: "general" }); setOpen(false) }}>
                <Check className={cn("mr-2 h-4 w-4", value.kind === "general" ? "opacity-100" : "opacity-0")} />General company activity
              </CommandItem>
            </CommandGroup>
            <CommandSeparator />
            <CommandGroup heading={multiple ? "Projects (pick one or more)" : "Projects"}>
              {options.map((o) => (
                <CommandItem key={o.projectId} value={`${o.projectNumber} ${o.name} #${o.projectId}`} onSelect={() => toggleId(o.projectId)}>
                  <Check className={cn("mr-2 h-4 w-4 shrink-0",
                    value.kind === "projects" && value.ids.includes(o.projectId) ? "opacity-100" : "opacity-0")} />
                  <span className="truncate"><span className="font-medium">{o.projectNumber}</span> — {o.name}</span>
                </CommandItem>
              ))}
            </CommandGroup>
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  )
}
