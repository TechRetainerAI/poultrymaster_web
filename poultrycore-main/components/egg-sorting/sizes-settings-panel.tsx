"use client"

// Egg sizes and sorting settings (Egg Sorting Workspace). Sizes are per farm
// and can be renamed, priced or switched off, never deleted: stock and sales
// history point at them. Every change here is kept in the audit trail (344).

import { useEffect, useState } from "react"
import { Loader2, Plus } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { useToast } from "@/hooks/use-toast"
import { cn } from "@/lib/utils"
import { applyEggsPerCrate } from "@/hooks/use-eggs-per-crate"
import { useAuthStore } from "@/lib/store/auth-store"
import { useEggPackaging } from "@/hooks/use-egg-packaging"
import { boxSize } from "@/lib/poultry/egg-packaging"
import {
  saveEggSize,
  saveEggSortingSettings,
  setEggClassPrices,
  setEggSizePrice,
  type ClosingPolicy,
  type EggClass,
  type EggSortingSettings,
} from "@/lib/api/egg-sorting"
import { cratesText, fmtCount } from "@/lib/production/egg-sorting"
import { EggSortingAuditList } from "@/components/egg-sorting/egg-sorting-audit-list"
import { EggPackagingCard } from "@/components/egg-sorting/egg-packaging-card"

const POLICY_TEXT: Record<ClosingPolicy, string> = {
  Off: "Say nothing about unsorted eggs",
  Warning: "Warn, but allow closing (recommended — many farms sort the next morning)",
  Blocking: "Block closing until the day's eggs are sorted",
}

const priceText = (n: number | null | undefined) => (n == null ? "" : String(n))
const parsePrice = (t: string): number | null | "bad" => {
  if (t.trim() === "") return null
  const n = Number(t)
  return Number.isFinite(n) && n >= 0 ? Math.round(n * 100) / 100 : "bad"
}

/** A price per egg can need more than two decimals (150 / 30 = 5; 140 / 30 = 4.6667). */
const parsePiecePrice = (t: string): number | null | "bad" => {
  if (t.trim() === "") return null
  const n = Number(t)
  return Number.isFinite(n) && n >= 0 ? Math.round(n * 10000) / 10000 : "bad"
}

type CardProps = {
  canEdit: boolean
  /** Called after any save, so the parent can reload and refresh the change history. */
  onChanged: () => void
}

/** Runs one save with a busy key and a toast; shared by the cards below. */
function useSaveRunner(onChanged: () => void) {
  const { toast } = useToast()
  const [busy, setBusy] = useState<string | null>(null)
  const run = async (key: string, fn: () => Promise<unknown>, ok: string) => {
    setBusy(key)
    try { await fn(); toast({ title: ok }); onChanged() }
    catch (e) { toast({ title: "Not saved", description: e instanceof Error ? e.message : "", variant: "destructive" }) }
    finally { setBusy(null) }
  }
  return { busy, run }
}

// Placeholders: what an empty box / egg price falls back to.
function usePriceFallbacks() {
  const packaging = useEggPackaging()
  const boxesOn = boxSize(packaging) != null
  const derivedBox = (crate: number | null | undefined) =>
    crate != null && boxesOn ? (crate * (packaging.cratesPerBox ?? 0)).toFixed(2) : "Not set"
  const derivedPiece = (crate: number | null | undefined) =>
    crate != null ? (crate / Math.max(1, packaging.eggsPerCrate)).toFixed(4).replace(/0+$/, "").replace(/\.$/, "") : "Not set"
  return { packaging, boxesOn, derivedBox, derivedPiece }
}

/** Egg sorting on/off, the Daily Closing rule, eggs per crate and the Unsorted prices. */
export function EggSortingSettingsCard({
  settings, classes, canEdit, onChanged, compact = false,
}: CardProps & { settings: EggSortingSettings | null; classes: EggClass[]; compact?: boolean }) {
  const farmId = useAuthStore((s) => s.activeFarmId)
  const { busy, run } = useSaveRunner(onChanged)
  const { packaging, boxesOn, derivedBox, derivedPiece } = usePriceFallbacks()
  const unsortedClass = classes.find((c) => c.classKind === "Unsorted")
  const [crate, setCrate] = useState("30")
  const [unsortedPrice, setUnsortedPrice] = useState("")
  // 394: box and egg prices for Unsorted, shown when the farm has Boxes on.
  const [unsortedBox, setUnsortedBox] = useState("")
  const [unsortedPiece, setUnsortedPiece] = useState("")

  useEffect(() => {
    setUnsortedBox(priceText(unsortedClass?.pricePerBox))
    setUnsortedPiece(priceText(unsortedClass?.pricePerPiece))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [classes])
  useEffect(() => {
    setCrate(String(settings?.eggsPerCrate ?? 30))
    setUnsortedPrice(priceText(settings?.unsortedPricePerCrate))
  }, [settings])

  const on = settings?.enableEggSorting ?? false
  const policy = (settings?.closingPolicy ?? "Warning") as ClosingPolicy
  const crateN = Number(crate)
  const crateValid = Number.isInteger(crateN) && crateN >= 1 && crateN <= 100
  const unsortedParsed = parsePrice(unsortedPrice)

  const saveSettings = (over: Partial<{ enableEggSorting: boolean; closingPolicy: ClosingPolicy; eggsPerCrate: number; unsortedPricePerCrate: number | null }>, ok: string) =>
    run("settings", async () => {
      const next = {
        enableEggSorting: on,
        closingPolicy: policy,
        eggsPerCrate: settings?.eggsPerCrate ?? 30,
        unsortedPricePerCrate: settings?.unsortedPricePerCrate ?? null,
        ...over,
      }
      await saveEggSortingSettings(next)
      applyEggsPerCrate(farmId, next.eggsPerCrate)
    }, ok)

  const unsortedBoxParsed = parsePrice(unsortedBox)
  const unsortedPieceParsed = parsePiecePrice(unsortedPiece)
  const unsortedPackagingDirty = boxesOn && !!unsortedClass && unsortedBoxParsed !== "bad" && unsortedPieceParsed !== "bad"
    && (unsortedBoxParsed !== (unsortedClass.pricePerBox ?? null) || unsortedPieceParsed !== (unsortedClass.pricePerPiece ?? null))
  const settingsDirty = crateValid && unsortedParsed !== "bad" && unsortedBoxParsed !== "bad" && unsortedPieceParsed !== "bad"
    && (crateN !== (settings?.eggsPerCrate ?? 30) || unsortedParsed !== (settings?.unsortedPricePerCrate ?? null) || unsortedPackagingDirty)

  return (
    <Card className={compact ? "gap-0 rounded-none border-0 bg-transparent py-0 shadow-none" : "rounded-xl border border-slate-200 bg-white shadow-sm"}>
      <CardContent className={compact ? "space-y-3 p-0" : "space-y-4 p-4"}>
        <div className={cn("flex justify-between gap-4", compact ? "items-center rounded-lg bg-slate-50 px-3 py-2" : "items-start")}>
          <div className="min-w-0">
            {compact ? (
              <p className="text-sm text-slate-700">
                {on ? "On: sort Unsorted eggs into sizes and sell each size." : "Off: production goes into Unsorted / General eggs."}
              </p>
            ) : (<>
            <div className="font-semibold text-slate-900">Egg sorting</div>
            <p className="text-sm text-slate-600">
              Off: production goes into Unsorted / General eggs and you sell those directly — nothing else changes.
              On: you can sort Unsorted eggs into your egg sizes and sell each size separately.
            </p>
            </>)}
          </div>
          <Switch checked={on} disabled={!canEdit || busy === "settings"}
            onCheckedChange={(v) => void saveSettings({ enableEggSorting: v }, v ? "Egg sorting turned on" : "Egg sorting turned off")} />
        </div>
        <div className={cn("grid grid-cols-1 gap-3", compact ? "sm:grid-cols-2" : "sm:grid-cols-3")}>
          <div className={cn("grid min-w-0 grid-cols-1 gap-1", compact ? "sm:col-span-2" : "sm:col-span-3 sm:max-w-md")}>
            <Label className="text-xs text-slate-500">Daily Closing, when the day&apos;s eggs are not all sorted</Label>
            <Select value={policy} disabled={!canEdit || !on || busy === "settings"}
              onValueChange={(v) => void saveSettings({ closingPolicy: v as ClosingPolicy }, "Daily Closing rule saved")}>
              {/* The chosen rule is a long sentence: cut it with "…" rather
                  than let it widen the card past a phone screen. */}
              <SelectTrigger className="w-full min-w-0 [&>span]:truncate"><SelectValue /></SelectTrigger>
              <SelectContent className="max-w-[calc(100vw-2rem)]">
                {(Object.keys(POLICY_TEXT) as ClosingPolicy[]).map((k) => (
                  <SelectItem key={k} value={k} className="whitespace-normal">{k} — {POLICY_TEXT[k]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="grid min-w-0 grid-cols-1 gap-1">
            <Label htmlFor="es-crate" className="text-xs text-slate-500">Eggs per crate</Label>
            <Input id="es-crate" inputMode="numeric" value={crate} disabled={!canEdit}
              onChange={(e) => setCrate(e.target.value.replace(/[^\d]/g, ""))} />
            {!compact && <p className="text-[11px] text-slate-500">
              Used wherever eggs are entered or shown as crates: production, sales, internal use, sorting. Stock is always kept in eggs.
            </p>}
            {!crateValid && <p className="text-xs text-rose-700">Between 1 and 100.</p>}
          </div>
          <div className="grid min-w-0 grid-cols-1 gap-1">
            <Label htmlFor="es-uprice" className="text-xs text-slate-500">Unsorted / General price per crate</Label>
            <Input id="es-uprice" inputMode="decimal" value={unsortedPrice} placeholder="Not set" disabled={!canEdit}
              onChange={(e) => setUnsortedPrice(e.target.value)} />
            {!compact && <p className="text-[11px] text-slate-500">Offered as the price on a sale of unsorted eggs; you can still change it on the sale.</p>}
            {unsortedParsed === "bad" && <p className="text-xs text-rose-700">Enter a price of 0 or more.</p>}
          </div>
          {boxesOn && (
            <div className="grid min-w-0 grid-cols-2 gap-2">
              <div className="grid min-w-0 grid-cols-1 gap-1">
                <Label htmlFor="es-ubox" className="text-xs text-slate-500">Unsorted price per box</Label>
                <Input id="es-ubox" inputMode="decimal" value={unsortedBox} disabled={!canEdit}
                  placeholder={derivedBox(unsortedParsed === "bad" ? null : unsortedParsed)}
                  onChange={(e) => setUnsortedBox(e.target.value)} />
              </div>
              <div className="grid min-w-0 grid-cols-1 gap-1">
                <Label htmlFor="es-upiece" className="text-xs text-slate-500">Unsorted price per egg</Label>
                <Input id="es-upiece" inputMode="decimal" value={unsortedPiece} disabled={!canEdit}
                  placeholder={derivedPiece(unsortedParsed === "bad" ? null : unsortedParsed)}
                  onChange={(e) => setUnsortedPiece(e.target.value)} />
              </div>
              <p className="col-span-2 text-[11px] text-slate-500">Empty = the crate price × {packaging.cratesPerBox} per box, and the crate price shared over {packaging.eggsPerCrate} eggs.</p>
              {(unsortedBoxParsed === "bad" || unsortedPieceParsed === "bad") && <p className="col-span-2 text-xs text-rose-700">Enter a price of 0 or more.</p>}
            </div>
          )}
          <div className={cn("flex items-end", compact && "justify-end sm:col-span-2")}>
            <Button size="sm" className="w-full sm:w-auto" disabled={!canEdit || !settingsDirty || busy === "settings"}
              onClick={() => void run("settings", async () => {
                const next = {
                  enableEggSorting: on, closingPolicy: policy, eggsPerCrate: crateN,
                  unsortedPricePerCrate: unsortedParsed === "bad" ? null : unsortedParsed,
                }
                await saveEggSortingSettings(next)
                applyEggsPerCrate(farmId, next.eggsPerCrate)
                // 394: Unsorted box / egg prices, with its crate price.
                if (unsortedPackagingDirty && unsortedClass) {
                  await setEggClassPrices(unsortedClass.poultryProductId, {
                    pricePerCrate: next.unsortedPricePerCrate,
                    pricePerBox: unsortedBoxParsed as number | null,
                    pricePerPiece: unsortedPieceParsed as number | null,
                  })
                }
              }, "Settings saved")}>
              {busy === "settings" && <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />} Save
            </Button>
          </div>
        </div>
      </CardContent>
    </Card>
  )
}

/** The farm's egg sizes: rename, price, switch off, add. Never deleted. */
export function EggSizesCard({ classes, canEdit, onChanged, compact = false }: CardProps & { classes: EggClass[]; compact?: boolean }) {
  const { busy, run } = useSaveRunner(onChanged)
  const { boxesOn, derivedBox, derivedPiece } = usePriceFallbacks()
  const [names, setNames] = useState<Record<number, string>>({})
  const [prices, setPrices] = useState<Record<number, string>>({})
  // 394: box and egg prices per size, shown when the farm has Boxes on.
  const [boxPrices, setBoxPrices] = useState<Record<number, string>>({})
  const [piecePrices, setPiecePrices] = useState<Record<number, string>>({})
  const [newName, setNewName] = useState("")

  const sizes = classes.filter((c) => c.classKind === "Size").sort((a, b) => a.sortOrder - b.sortOrder || a.name.localeCompare(b.name))
  useEffect(() => {
    setNames(Object.fromEntries(sizes.map((s) => [s.eggSizeId as number, s.name])))
    setPrices(Object.fromEntries(sizes.map((s) => [s.eggSizeId as number, priceText(s.pricePerCrate)])))
    setBoxPrices(Object.fromEntries(sizes.map((s) => [s.eggSizeId as number, priceText(s.pricePerBox)])))
    setPiecePrices(Object.fromEntries(sizes.map((s) => [s.eggSizeId as number, priceText(s.pricePerPiece)])))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [classes])

  /** A size's crate / box / egg prices: one call when any changed (394), else the 344 crate-price call. */
  const savePrices = async (s: EggClass, crate: number | null, box: number | null, piece: number | null) => {
    if (boxesOn) await setEggClassPrices(s.poultryProductId, { pricePerCrate: crate, pricePerBox: box, pricePerPiece: piece })
    else await setEggSizePrice(s.eggSizeId as number, crate)
  }

  return (
    <Card className={compact ? "gap-0 rounded-none border-0 bg-transparent py-0 shadow-none" : "rounded-xl border border-slate-200 bg-white shadow-sm"}>
      <CardContent className="p-0">
        <div className={cn("border-b border-slate-100 px-4 py-3", compact && "hidden")}>
          <div className="font-semibold text-slate-900">Egg sizes</div>
          <p className="text-sm text-slate-600">
            Each size is its own stock line with its own selling price. Rename, price or switch a size off; sizes are never
            deleted because stock and sales history refer to them.
          </p>
        </div>
        {/* Phone: one card per size instead of a five-column table. */}
        <div className="divide-y divide-slate-100 sm:hidden">
          {sizes.length === 0 && <p className="px-4 py-4 text-sm text-slate-500">No sizes yet. Turning sorting on adds the standard list.</p>}
          {sizes.map((s) => {
            const id = s.eggSizeId as number
            const nameChanged = (names[id] ?? s.name).trim() !== s.name
            const p = parsePrice(prices[id] ?? "")
            const bp = parsePrice(boxPrices[id] ?? "")
            const pp = parsePiecePrice(piecePrices[id] ?? "")
            const priceChanged = p !== "bad" && bp !== "bad" && pp !== "bad"
              && (p !== (s.pricePerCrate ?? null) || (boxesOn && (bp !== (s.pricePerBox ?? null) || pp !== (s.pricePerPiece ?? null))))
            return (
              <div key={id} className={cn("space-y-2 px-4 py-3", !s.isActive && "bg-slate-50 text-slate-500")}>
                <div className="flex items-center justify-between gap-3">
                  <span className="text-xs tabular-nums text-slate-500">
                    On hand <b className="text-slate-800">{fmtCount(s.onHand)}</b> ({cratesText(s.onHand)})
                  </span>
                  <label className="flex items-center gap-2 text-xs text-slate-600">
                    Active
                    <Switch checked={s.isActive} disabled={!canEdit || busy === `size:${id}`}
                      onCheckedChange={(v) => void run(`size:${id}`, () => saveEggSize({ eggSizeId: id, name: s.name, sortOrder: s.sortOrder, isActive: v }),
                        v ? `${s.name} switched on` : `${s.name} switched off`)} />
                  </label>
                </div>
                <div className="grid grid-cols-[1fr_7rem] gap-2">
                  <div className="space-y-1">
                    <Label className="text-[11px] text-slate-500">Size</Label>
                    <Input className="h-9" value={names[id] ?? s.name} disabled={!canEdit}
                      onChange={(e) => setNames((x) => ({ ...x, [id]: e.target.value }))} />
                  </div>
                  <div className="space-y-1">
                    <Label className="text-[11px] text-slate-500">Price / crate</Label>
                    <Input className="h-9" inputMode="decimal" placeholder="Not set" value={prices[id] ?? ""} disabled={!canEdit}
                      onChange={(e) => setPrices((x) => ({ ...x, [id]: e.target.value }))} />
                  </div>
                </div>
                {boxesOn && (
                  <div className="grid grid-cols-2 gap-2">
                    <div className="space-y-1">
                      <Label className="text-[11px] text-slate-500">Price / box</Label>
                      <Input className="h-9" inputMode="decimal" placeholder={derivedBox(p === "bad" ? null : p)} value={boxPrices[id] ?? ""} disabled={!canEdit}
                        onChange={(e) => setBoxPrices((x) => ({ ...x, [id]: e.target.value }))} />
                    </div>
                    <div className="space-y-1">
                      <Label className="text-[11px] text-slate-500">Price / egg</Label>
                      <Input className="h-9" inputMode="decimal" placeholder={derivedPiece(p === "bad" ? null : p)} value={piecePrices[id] ?? ""} disabled={!canEdit}
                        onChange={(e) => setPiecePrices((x) => ({ ...x, [id]: e.target.value }))} />
                    </div>
                  </div>
                )}
                {(p === "bad" || bp === "bad" || pp === "bad") && <div className="text-[11px] text-rose-700">Price must be 0 or more</div>}
                {(nameChanged || priceChanged) && (
                  <Button size="sm" variant="outline" className="w-full" disabled={!canEdit || busy === `size:${id}` || !(names[id] ?? "").trim()}
                    onClick={() => void run(`size:${id}`, async () => {
                      if (nameChanged) await saveEggSize({ eggSizeId: id, name: names[id].trim(), sortOrder: s.sortOrder, isActive: s.isActive })
                      if (priceChanged) await savePrices(s, p as number | null, bp as number | null, pp as number | null)
                    }, "Size saved")}>
                    Save
                  </Button>
                )}
              </div>
            )
          })}
        </div>
        <div className={cn("hidden overflow-x-auto sm:block", compact && "rounded-lg border border-slate-100")}>
          <table className={cn("w-full text-sm",
            compact ? cn("[&_td]:px-2 [&_td]:py-1.5 [&_th]:px-2", boxesOn && "min-w-[40rem]") : boxesOn ? "min-w-[58rem]" : "min-w-[44rem]")}>
            <thead className="bg-slate-50 text-left text-xs uppercase tracking-wider text-slate-500">
              <tr>
                <th className="px-4 py-2 font-medium">Size</th>
                <th className="px-4 py-2 font-medium">Price per crate</th>
                {boxesOn && <th className="px-4 py-2 font-medium">Price per box</th>}
                {boxesOn && <th className="px-4 py-2 font-medium">Price per egg</th>}
                <th className="px-4 py-2 text-right font-medium">On hand</th>
                <th className="px-4 py-2 font-medium">Active</th>
                <th className="px-4 py-2" />
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {sizes.length === 0 && (
                <tr><td colSpan={boxesOn ? 7 : 5} className="px-4 py-4 text-slate-500">No sizes yet. Turning sorting on adds the standard list.</td></tr>
              )}
              {sizes.map((s) => {
                const id = s.eggSizeId as number
                const nameChanged = (names[id] ?? s.name).trim() !== s.name
                const p = parsePrice(prices[id] ?? "")
                const bp = parsePrice(boxPrices[id] ?? "")
                const pp = parsePiecePrice(piecePrices[id] ?? "")
                const priceChanged = p !== "bad" && bp !== "bad" && pp !== "bad"
                  && (p !== (s.pricePerCrate ?? null) || (boxesOn && (bp !== (s.pricePerBox ?? null) || pp !== (s.pricePerPiece ?? null))))
                return (
                  <tr key={id} className={s.isActive ? "" : "bg-slate-50 text-slate-500"}>
                    <td className="px-4 py-2">
                      <Input className="h-8 max-w-xs" value={names[id] ?? s.name} disabled={!canEdit}
                        onChange={(e) => setNames((x) => ({ ...x, [id]: e.target.value }))} />
                    </td>
                    <td className="px-4 py-2">
                      <Input className="h-8 w-28" inputMode="decimal" placeholder="Not set" value={prices[id] ?? ""} disabled={!canEdit}
                        onChange={(e) => setPrices((x) => ({ ...x, [id]: e.target.value }))} />
                      {p === "bad" && <div className="text-[11px] text-rose-700">0 or more</div>}
                    </td>
                    {boxesOn && (
                      <td className="px-4 py-2">
                        <Input className="h-8 w-28" inputMode="decimal" placeholder={derivedBox(p === "bad" ? null : p)} value={boxPrices[id] ?? ""} disabled={!canEdit}
                          onChange={(e) => setBoxPrices((x) => ({ ...x, [id]: e.target.value }))} />
                        {bp === "bad" && <div className="text-[11px] text-rose-700">0 or more</div>}
                      </td>
                    )}
                    {boxesOn && (
                      <td className="px-4 py-2">
                        <Input className="h-8 w-24" inputMode="decimal" placeholder={derivedPiece(p === "bad" ? null : p)} value={piecePrices[id] ?? ""} disabled={!canEdit}
                          onChange={(e) => setPiecePrices((x) => ({ ...x, [id]: e.target.value }))} />
                        {pp === "bad" && <div className="text-[11px] text-rose-700">0 or more</div>}
                      </td>
                    )}
                    <td className="px-4 py-2 text-right tabular-nums">
                      {fmtCount(s.onHand)} <span className="text-xs text-slate-500">({cratesText(s.onHand)})</span>
                    </td>
                    <td className="px-4 py-2">
                      <Switch checked={s.isActive} disabled={!canEdit || busy === `size:${id}`}
                        onCheckedChange={(v) => void run(`size:${id}`, () => saveEggSize({ eggSizeId: id, name: s.name, sortOrder: s.sortOrder, isActive: v }),
                          v ? `${s.name} switched on` : `${s.name} switched off`)} />
                    </td>
                    <td className="whitespace-nowrap px-4 py-2 text-right">
                      {(nameChanged || priceChanged) && (
                        <Button size="sm" variant="outline" disabled={!canEdit || busy === `size:${id}` || !(names[id] ?? "").trim()}
                          onClick={() => void run(`size:${id}`, async () => {
                            if (nameChanged) await saveEggSize({ eggSizeId: id, name: names[id].trim(), sortOrder: s.sortOrder, isActive: s.isActive })
                            if (priceChanged) await savePrices(s, p as number | null, bp as number | null, pp as number | null)
                          }, "Size saved")}>
                          Save
                        </Button>
                      )}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
        {canEdit && (
          <div className={cn("flex flex-wrap items-end gap-2", compact ? "pt-3" : "border-t border-slate-100 px-4 py-3")}>
            <div className="min-w-0 flex-1 space-y-1 sm:flex-none">
              <Label htmlFor="es-newsize" className="text-xs text-slate-500">New size</Label>
              <Input id="es-newsize" className="h-9 w-full sm:w-56" value={newName} placeholder="e.g. Peewee" onChange={(e) => setNewName(e.target.value)} />
            </div>
            <Button size="sm" disabled={!newName.trim() || busy === "new"}
              onClick={() => void run("new", async () => { await saveEggSize({ eggSizeId: null, name: newName.trim(), sortOrder: null, isActive: true }); setNewName("") }, "Size added")}>
              {busy === "new" ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin" /> : <Plus className="mr-1.5 h-4 w-4" />} Add size
            </Button>
          </div>
        )}
      </CardContent>
    </Card>
  )
}

/** All the egg sorting settings plus the change history (the workspace's "Sizes & settings" tab). */
export function SizesSettingsPanel({
  settings, classes, canEdit, onChanged,
}: CardProps & { settings: EggSortingSettings | null; classes: EggClass[] }) {
  const [auditKey, setAuditKey] = useState(0)
  const changed = () => { onChanged(); setAuditKey((k) => k + 1) }
  return (
    <div className="space-y-4">
      <EggSortingSettingsCard settings={settings} classes={classes} canEdit={canEdit} onChanged={changed} />
      <EggSizesCard classes={classes} canEdit={canEdit} onChanged={changed} />
      {/* Packaging sits last, right above the history (2026-11-03). */}
      <EggPackagingCard canEdit={canEdit} onChanged={() => setAuditKey((k) => k + 1)} />
      <EggSortingAuditList key={auditKey} title="Change history" description="Settings, sizes, sortings, sale classes and egg adjustments — who changed what, and when." />
    </div>
  )
}
