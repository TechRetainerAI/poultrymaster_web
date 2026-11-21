"use client"

// Setup > Animals kept. Ticking a species switches on its pages and lets pens,
// batches and groups of it be recorded. A species with active groups cannot be
// unticked (the database refuses; the message says why).

import { useEffect, useMemo, useState } from "react"
import { Check, Egg, Milk, Baby } from "lucide-react"
import { Button } from "@/components/ui/button"
import { useToast } from "@/hooks/use-toast"
import { setSpeciesKept, type LivestockSpecies, type SpeciesCategory } from "@/lib/api/livestock"
import { useLivestockSpecies } from "@/hooks/use-livestock-species"
import { AMBER_BUTTON, LoadError, Loading } from "./livestock-page"
import { cn } from "@/lib/utils"

const CATEGORY_LABEL: Record<SpeciesCategory, string> = {
  Bird: "Birds",
  SmallMammal: "Small animals",
  Ruminant: "Goats & sheep",
  Large: "Pigs & cattle",
}

export function SpeciesKept() {
  const { all, isLoading, error, refresh, loaded } = useLivestockSpecies()
  const { toast } = useToast()
  const [picked, setPicked] = useState<Set<string>>(new Set())
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    if (loaded) setPicked(new Set(all.filter((s) => s.enabled).map((s) => s.speciesCode)))
  }, [loaded, all])

  const byCategory = useMemo(() => {
    const m = new Map<SpeciesCategory, LivestockSpecies[]>()
    for (const s of all) m.set(s.category, [...(m.get(s.category) ?? []), s])
    return [...m.entries()]
  }, [all])

  const dirty = loaded && (all.some((s) => s.enabled !== picked.has(s.speciesCode)))

  const toggle = (code: string) =>
    setPicked((p) => {
      const n = new Set(p)
      if (n.has(code)) n.delete(code)
      else n.add(code)
      return n
    })

  const save = async () => {
    setSaving(true)
    try {
      await setSpeciesKept([...picked])
      await refresh()
      toast({ title: "Saved", description: "The animals your farm keeps are updated." })
    } catch (e: any) {
      toast({ title: "Not saved", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  if (isLoading) return <Loading />
  if (error) return <LoadError message={error.message} onRetry={refresh} />

  return (
    <div className="space-y-5">
      <p className="text-sm text-stone-600">
        Tick every kind of animal your farm keeps. Pages for eggs, milk and births appear only when you keep an animal
        that needs them.
      </p>
      {byCategory.map(([cat, list]) => (
        <div key={cat}>
          <h3 className="text-xs font-semibold uppercase tracking-wide text-amber-800 mb-2">{CATEGORY_LABEL[cat]}</h3>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
            {list.map((s) => {
              const on = picked.has(s.speciesCode)
              return (
                <button
                  key={s.speciesCode}
                  type="button"
                  onClick={() => toggle(s.speciesCode)}
                  aria-pressed={on}
                  className={cn(
                    "text-left rounded-lg border-2 p-3 transition",
                    on ? "border-amber-600 bg-amber-50" : "border-stone-200 bg-white hover:border-stone-300",
                  )}
                >
                  <div className="flex items-center justify-between gap-2">
                    <span className="font-medium text-stone-900">{s.name}</span>
                    <span className={cn("h-5 w-5 rounded border flex items-center justify-center",
                      on ? "bg-amber-600 border-amber-600 text-white" : "border-stone-300")}>
                      {on && <Check className="h-3.5 w-3.5" />}
                    </span>
                  </div>
                  <div className="mt-1 flex flex-wrap gap-x-3 gap-y-1 text-xs text-stone-500">
                    <span>Kept in a {s.penTerm.toLowerCase()} · {s.groupTerm.toLowerCase()}</span>
                    {s.producesEggs && <span className="inline-flex items-center gap-1"><Egg className="h-3 w-3" />Eggs</span>}
                    {s.producesMilk && <span className="inline-flex items-center gap-1"><Milk className="h-3 w-3" />Milk</span>}
                    {s.breedsOnFarm && <span className="inline-flex items-center gap-1"><Baby className="h-3 w-3" />{s.birthTerm}</span>}
                  </div>
                  {s.enabled && s.head > 0 && (
                    <div className="mt-1 text-xs text-amber-800">{s.head.toLocaleString()} on the farm now</div>
                  )}
                </button>
              )
            })}
          </div>
        </div>
      ))}
      <div className="flex justify-end">
        <Button className={AMBER_BUTTON} disabled={!dirty || saving || picked.size === 0} onClick={save}>
          {saving ? "Saving…" : "Save"}
        </Button>
      </div>
    </div>
  )
}
