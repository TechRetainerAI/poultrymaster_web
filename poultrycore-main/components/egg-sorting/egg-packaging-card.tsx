"use client"

// Egg packaging & units (migration 393): Boxes of N crates, the farm's
// preferred way of writing egg quantities, and which field Add Sale puts
// first. Lives on Egg Sorting > Sizes & settings beside Eggs per crate.
//
// A box is a quantity unit: stock stays in individual eggs, and a box is NOT a
// poultry Batch. Saving changes how quantities are entered and shown -- never
// stock, posted sales or stock movements.

import { useEffect, useState } from "react"
import { Loader2, Package } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription,
  AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from "@/components/ui/alert-dialog"
import { useToast } from "@/hooks/use-toast"
import { useAuthStore } from "@/lib/store/auth-store"
import { useEggsPerCrate } from "@/hooks/use-eggs-per-crate"
import { applyEggPackaging } from "@/hooks/use-egg-packaging"
import { getEggPackaging, saveEggPackaging, type EggPackagingSettings } from "@/lib/api/egg-sorting"
import {
  DEFAULT_EGG_PACKAGING, formatEggQuantity, MAX_CRATES_PER_BOX, packagingConfigError,
  type EggDisplay, type SaleEntryUnit,
} from "@/lib/poultry/egg-packaging"

const DISPLAY_TEXT: Record<EggDisplay, string> = {
  BoxesCratesPieces: "Boxes, crates & pieces",
  CratesPieces: "Crates & pieces",
  Pieces: "Total eggs (packaging as a hint)",
}

const SAMPLE = 10675

export function EggPackagingCard({ canEdit, onChanged }: { canEdit: boolean; onChanged?: () => void }) {
  const { toast } = useToast()
  const farmId = useAuthStore((s) => s.activeFarmId)
  const eggsPerCrate = useEggsPerCrate()
  const [saved, setSaved] = useState<EggPackagingSettings | null>(null)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [on, setOn] = useState(false)
  const [crates, setCrates] = useState("")
  const [display, setDisplay] = useState<EggDisplay>("CratesPieces")
  const [entry, setEntry] = useState<SaleEntryUnit>("Crates")
  const [busy, setBusy] = useState(false)
  const [confirming, setConfirming] = useState(false)

  const reset = (s: EggPackagingSettings) => {
    setOn(!!s.enableBoxes)
    setCrates(s.storedCratesPerBox != null ? String(s.storedCratesPerBox) : "")
    setDisplay(s.storedDisplay ?? "CratesPieces")
    setEntry(s.storedEntryUnit ?? "Crates")
  }

  useEffect(() => {
    let cancelled = false
    setSaved(null)
    setLoadError(null)
    getEggPackaging()
      .then((s) => { if (!cancelled) { setSaved(s); reset(s) } })
      .catch((e) => { if (!cancelled) setLoadError(e instanceof Error ? e.message : "Could not load egg packaging.") })
    return () => { cancelled = true }
  }, [farmId])

  const cratesN = crates.trim() === "" ? null : Number(crates)
  const error = packagingConfigError({ enableBoxes: on, cratesPerBox: cratesN, display, saleEntryUnit: entry })
  const dirty = !!saved && (
    on !== !!saved.enableBoxes
    || cratesN !== (saved.storedCratesPerBox ?? null)
    || display !== (saved.storedDisplay ?? "CratesPieces")
    || entry !== (saved.storedEntryUnit ?? "Crates"))
  // The conversion itself changes (not just how it is written): say what that means first.
  const conversionChanges = !!saved && (on !== !!saved.enableBoxes || (on && cratesN !== (saved.cratesPerBox ?? null)))
  const preview = {
    ...DEFAULT_EGG_PACKAGING, eggsPerCrate, enableBoxes: on && cratesN != null && cratesN >= 1,
    cratesPerBox: on ? cratesN : null, display,
  }

  const save = async () => {
    setConfirming(false)
    setBusy(true)
    try {
      await saveEggPackaging({ enableBoxes: on, cratesPerBox: cratesN, eggDisplay: display, saleEntryUnit: entry })
      const fresh = await getEggPackaging()
      setSaved(fresh)
      reset(fresh)
      applyEggPackaging(farmId, fresh)
      toast({ title: "Egg packaging saved" })
      onChanged?.()
    } catch (e) {
      toast({ title: "Not saved", description: e instanceof Error ? e.message : "", variant: "destructive" })
    } finally {
      setBusy(false)
    }
  }

  return (
    <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
      <CardContent className="space-y-4 p-4">
        <div className="flex items-start justify-between gap-4">
          <div className="min-w-0">
            <div className="flex items-center gap-2 font-semibold text-slate-900">
              <Package className="h-4 w-4 text-amber-600" /> Egg packaging & units
            </div>
            <p className="text-sm text-slate-600">
              Large farms that sell by the box can enter and see eggs in boxes, crates and pieces. A box is only a
              way of counting: your stock is always kept in individual eggs, and nothing here packs eggs or changes stock.
            </p>
          </div>
          <Switch checked={on} disabled={!canEdit || busy || !saved} aria-label="Enable boxes for this farm"
            onCheckedChange={(v) => {
              setOn(v)
              if (!v) { if (display === "BoxesCratesPieces") setDisplay("CratesPieces"); setEntry("Crates") }
              else if (display === "CratesPieces") setDisplay("BoxesCratesPieces")
            }} />
        </div>

        {loadError && <p className="text-sm text-rose-700">{loadError}</p>}

        <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <div className="grid min-w-0 grid-cols-1 gap-1">
            <Label htmlFor="pk-crates" className="text-xs text-slate-500">Crates per box</Label>
            <Input id="pk-crates" inputMode="numeric" value={crates} placeholder="e.g. 14" disabled={!canEdit || !on}
              onChange={(e) => setCrates(e.target.value.replace(/[^\d]/g, ""))} />
            <p className="text-[11px] text-slate-500">
              {on && cratesN != null && cratesN >= 1 && cratesN <= MAX_CRATES_PER_BOX
                ? `1 box = ${cratesN} crates × ${eggsPerCrate} = ${(cratesN * eggsPerCrate).toLocaleString()} eggs`
                : `Whole number, 1 to ${MAX_CRATES_PER_BOX}. Eggs per box follows your eggs per crate (${eggsPerCrate}).`}
            </p>
          </div>
          <div className="grid min-w-0 grid-cols-1 gap-1">
            <Label className="text-xs text-slate-500">Show egg quantities as</Label>
            <Select value={display} disabled={!canEdit} onValueChange={(v) => setDisplay(v as EggDisplay)}>
              <SelectTrigger className="w-full min-w-0 [&>span]:truncate"><SelectValue /></SelectTrigger>
              <SelectContent>
                {(Object.keys(DISPLAY_TEXT) as EggDisplay[]).map((k) => (
                  <SelectItem key={k} value={k} disabled={k === "BoxesCratesPieces" && !on}>{DISPLAY_TEXT[k]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            <p className="text-[11px] text-slate-500">
              {SAMPLE.toLocaleString()} eggs → <b>{formatEggQuantity(SAMPLE, preview, display)}</b>
            </p>
          </div>
          <div className="grid min-w-0 grid-cols-1 gap-1">
            <Label className="text-xs text-slate-500">Add Sale puts first</Label>
            <Select value={entry} disabled={!canEdit || !on} onValueChange={(v) => setEntry(v as SaleEntryUnit)}>
              <SelectTrigger className="w-full min-w-0"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="Boxes">Boxes</SelectItem>
                <SelectItem value="Crates">Crates</SelectItem>
              </SelectContent>
            </Select>
            <p className="text-[11px] text-slate-500">Only the order of the quantity fields; stock works the same either way.</p>
          </div>
        </div>

        {error && dirty && <p className="text-xs text-rose-700">{error}</p>}

        <div className="flex flex-wrap items-center justify-end gap-2">
          {dirty && (
            <Button size="sm" variant="ghost" disabled={busy} onClick={() => saved && reset(saved)}>Cancel</Button>
          )}
          <Button size="sm" disabled={!canEdit || !dirty || !!error || busy}
            onClick={() => (conversionChanges ? setConfirming(true) : void save())}>
            {busy && <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />} Save
          </Button>
        </div>
      </CardContent>

      <AlertDialog open={confirming} onOpenChange={setConfirming}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{on ? (saved?.enableBoxes ? "Change the box size?" : "Turn on boxes?") : "Turn off boxes?"}</AlertDialogTitle>
            <AlertDialogDescription asChild>
              <div className="space-y-2 text-sm text-slate-600">
                {on && cratesN != null && (
                  <p>From now on, 1 box = <b>{cratesN} crates = {(cratesN * eggsPerCrate).toLocaleString()} eggs</b>.</p>
                )}
                <ul className="list-disc space-y-1 pl-5">
                  <li>Your egg stock does not change. It is kept in individual eggs; only how it is shown changes.</li>
                  <li>Sales already posted keep the box size they were recorded with. Their quantities and amounts do not change.</li>
                  <li>Past stock movements and reports of past transactions are not recalculated.</li>
                  {!on && <li>Your box size is kept, so turning boxes back on later restores it.</li>}
                </ul>
              </div>
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={() => void save()}>Save</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </Card>
  )
}
