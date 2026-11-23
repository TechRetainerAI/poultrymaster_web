"use client"

// Searchable Mother / Father picker. Type a tag, name or group; each animal
// shows its group, age and whether it is still on the farm. Animals that
// cannot be the parent by sex are left out; ones that are too young for this
// birth date (or share it) are shown greyed with the reason, so the farmer
// sees them and knows which birth date to fix.
// See lib/livestock/parents.ts for the rules.
//
// In "Tag several animals" it also offers the animals being tagged in the same
// list ("Being tagged now"), picked by tag since they have no id yet (472).

import { useMemo, useState } from "react"
import { Check, ChevronsUpDown } from "lucide-react"
import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from "@/components/ui/command"
import type { AnimalSex, LivestockAnimal } from "@/lib/api/livestock"
import { fitsRole, parentProblem, parentRank, type ParentRole } from "@/lib/livestock/parents"
import { fmtAge } from "./livestock-page"

const STATUS_LABEL: Record<string, string> = { Active: "On the farm", Sold: "Sold", Dead: "Dead", Culled: "Culled" }
const STATUS_TONE: Record<string, string> = {
  Active: "bg-emerald-100 text-emerald-800", Sold: "bg-sky-100 text-sky-800", Dead: "bg-stone-200 text-stone-700", Culled: "bg-rose-100 text-rose-800",
}
const HEADINGS = ["In the same group", "Other groups", "No longer on the farm"]

/** An animal in the same list, not saved yet. */
export interface PendingParent { tag: string; sex: AnimalSex; birthDate: string | null }

export function ParentPicker({ role, animals, value, onChange, pending = [], pendingValue = null,
  childBirthDate, groupId, gestationDays, excludeId, className, id }: {
  role: ParentRole
  /** Every animal of the same kind, any status. */
  animals: LivestockAnimal[]
  value: number | null
  /** Picks an animal by id, or (second argument) one being tagged now by its tag. */
  onChange: (animalId: number | null, pendingTag?: string | null) => void
  pending?: PendingParent[]
  pendingValue?: string | null
  /** The young one's birth date, to rule out parents born too late. */
  childBirthDate?: string | null
  /** The young one's group: its animals are listed first. */
  groupId?: number | null
  gestationDays?: number | null
  /** The animal being edited, which cannot be its own parent. */
  excludeId?: number | null
  className?: string
  id?: string
}) {
  const [open, setOpen] = useState(false)
  const selected = value != null ? animals.find((a) => a.animalId === value) : undefined
  const selectedPending = pendingValue ? pending.find((p) => p.tag.toLowerCase() === pendingValue.toLowerCase()) : undefined
  const problem = selected
    ? parentProblem(selected, role, childBirthDate, gestationDays)
    : selectedPending ? parentProblem(selectedPending, role, childBirthDate, gestationDays)
    : pendingValue ? "is no longer in this list" : null
  const shownTag = selected?.tagNumber ?? selectedPending?.tag ?? pendingValue

  const grouped = useMemo(() => {
    const out: { a: LivestockAnimal; why: string | null }[][] = [[], [], []]
    for (const a of animals) {
      if (a.animalId === excludeId || !fitsRole(a, role)) continue
      const why = parentProblem(a, role, childBirthDate, gestationDays)
      out[parentRank(a, groupId)].push({ a, why })
    }
    for (const g of out) g.sort((x, y) => Number(!!x.why) - Number(!!y.why) || x.a.tagNumber.localeCompare(y.a.tagNumber, undefined, { numeric: true }))
    return out
  }, [animals, role, childBirthDate, gestationDays, groupId, excludeId])

  const pendingList = useMemo(() => pending
    .filter((p) => p.tag.trim() && fitsRole(p, role))
    .map((p) => ({ p, why: parentProblem(p, role, childBirthDate, gestationDays) })),
  [pending, role, childBirthDate, gestationDays])

  const pick = (v: number | null, tag: string | null = null) => { onChange(v, tag); setOpen(false) }

  return (
    <div className="space-y-1">
      <Popover open={open} onOpenChange={setOpen}>
        <PopoverTrigger asChild>
          <Button id={id} type="button" variant="outline" role="combobox" aria-expanded={open}
            className={cn("w-full min-w-36 justify-between bg-white font-normal", !shownTag && "text-stone-500", problem && "border-rose-400", className)}>
            <span className="truncate">
              {shownTag
                ? <><span className="font-medium text-stone-900">{shownTag}</span>
                    {selected?.name && <span className="text-stone-500"> · {selected.name}</span>}
                    {!selected && pendingValue && <span className="text-amber-700"> · new</span>}</>
                : "Not known"}
            </span>
            <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
          </Button>
        </PopoverTrigger>
        <PopoverContent className="w-80 p-0" align="start">
          <Command filter={(v, s) => (v.toLowerCase().includes(s.trim().toLowerCase()) ? 1 : 0)}>
            <CommandInput placeholder="Search tag, name or group…" />
            <CommandList className="max-h-72">
              <CommandEmpty>No {role === "mother" ? "female" : "male"} found.</CommandEmpty>
              <CommandGroup>
                <CommandItem value="not known unknown none" onSelect={() => pick(null)}>
                  <Check className={cn("mr-2 h-4 w-4", value == null && !pendingValue ? "opacity-100" : "opacity-0")} />Not known
                </CommandItem>
              </CommandGroup>
              {pendingList.length > 0 && (
                <CommandGroup heading="Being tagged now">
                  {pendingList.map(({ p, why }) => (
                    <CommandItem key={`new-${p.tag}`} value={`${p.tag} new being tagged now`} disabled={!!why}
                      onSelect={() => pick(null, p.tag)} className="items-start">
                      <Check className={cn("mr-2 mt-0.5 h-4 w-4 shrink-0", pendingValue?.toLowerCase() === p.tag.toLowerCase() ? "opacity-100" : "opacity-0")} />
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-2">
                          <span className="font-medium">{p.tag}</span>
                          <span className="ml-auto shrink-0 rounded-full bg-amber-100 px-1.5 py-0.5 text-[10px] font-medium text-amber-800">In this list</span>
                        </div>
                        <div className="text-xs text-stone-500">{p.sex === "Unknown" ? "Sex not known" : p.sex}{p.birthDate ? ` · born ${p.birthDate}` : ""}</div>
                        {why && <div className="text-xs text-rose-600">{why}</div>}
                      </div>
                    </CommandItem>
                  ))}
                </CommandGroup>
              )}
              {grouped.map((list, i) => list.length > 0 && (
                <CommandGroup key={i} heading={HEADINGS[i]}>
                  {list.map(({ a, why }) => (
                    <CommandItem key={a.animalId} value={`${a.tagNumber} ${a.name ?? ""} ${a.groupName} #${a.animalId}`}
                      disabled={!!why} onSelect={() => pick(a.animalId)} className="items-start">
                      <Check className={cn("mr-2 mt-0.5 h-4 w-4 shrink-0", value === a.animalId ? "opacity-100" : "opacity-0")} />
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-2">
                          <span className="font-medium">{a.tagNumber}</span>
                          {a.name && <span className="truncate text-stone-500">{a.name}</span>}
                          <span className={cn("ml-auto shrink-0 rounded-full px-1.5 py-0.5 text-[10px] font-medium", STATUS_TONE[a.status])}>{STATUS_LABEL[a.status] ?? a.status}</span>
                        </div>
                        <div className="text-xs text-stone-500">
                          {a.groupName}{a.ageDays != null ? ` · ${fmtAge(a.ageDays)} old` : ""}{a.sex === "Unknown" ? " · sex not known" : ""}
                        </div>
                        {why && <div className="text-xs text-rose-600">{why} — change a birth date to pick it</div>}
                      </div>
                    </CommandItem>
                  ))}
                </CommandGroup>
              ))}
            </CommandList>
          </Command>
        </PopoverContent>
      </Popover>
      {problem && <p className="text-xs text-rose-600">{shownTag} {problem}.</p>}
    </div>
  )
}
