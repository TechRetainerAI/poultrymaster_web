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
import {
  saveEggSize,
  saveEggSortingSettings,
  setEggSizePrice,
  type ClosingPolicy,
  type EggClass,
  type EggSortingSettings,
} from "@/lib/api/egg-sorting"
import { cratesText, fmtCount } from "@/lib/production/egg-sorting"
import { EggSortingAuditList } from "@/components/egg-sorting/egg-sorting-audit-list"

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

export function SizesSettingsPanel({
  settings, classes, canEdit, onChanged,
}: {
  settings: EggSortingSettings | null
  classes: EggClass[]
  canEdit: boolean
  onChanged: () => void
}) {
  const { toast } = useToast()
  const farmId = useAuthStore((s) => s.activeFarmId)
  const [busy, setBusy] = useState<string | null>(null)
  const [names, setNames] = useState<Record<number, string>>({})
  const [prices, setPrices] = useState<Record<number, string>>({})
  const [newName, setNewName] = useState("")
  const [crate, setCrate] = useState("30")
  const [unsortedPrice, setUnsortedPrice] = useState("")
  const [auditKey, setAuditKey] = useState(0)

  const sizes = classes.filter((c) => c.classKind === "Size").sort((a, b) => a.sortOrder - b.sortOrder || a.name.localeCompare(b.name))
  useEffect(() => {
    setNames(Object.fromEntries(sizes.map((s) => [s.eggSizeId as number, s.name])))
    setPrices(Object.fromEntries(sizes.map((s) => [s.eggSizeId as number, priceText(s.pricePerCrate)])))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [classes])
  useEffect(() => {
    setCrate(String(settings?.eggsPerCrate ?? 30))
    setUnsortedPrice(priceText(settings?.unsortedPricePerCrate))
  }, [settings])

  const run = async (key: string, fn: () => Promise<unknown>, ok: string) => {
    setBusy(key)
    try { await fn(); toast({ title: ok }); onChanged(); setAuditKey((k) => k + 1) }
    catch (e) { toast({ title: "Not saved", description: e instanceof Error ? e.message : "", variant: "destructive" }) }
    finally { setBusy(null) }
  }

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

  const settingsDirty = crateValid && unsortedParsed !== "bad"
    && (crateN !== (settings?.eggsPerCrate ?? 30) || unsortedParsed !== (settings?.unsortedPricePerCrate ?? null))

  return (
    <div className="space-y-4">
      <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
        <CardContent className="space-y-4 p-4">
          <div className="flex items-start justify-between gap-4">
            <div className="min-w-0">
              <div className="font-semibold text-slate-900">Egg sorting</div>
              <p className="text-sm text-slate-600">
                Off: production goes into Unsorted / General eggs and you sell those directly — nothing else changes.
                On: you can sort Unsorted eggs into the sizes below and sell each size separately.
              </p>
            </div>
            <Switch checked={on} disabled={!canEdit || busy === "settings"}
              onCheckedChange={(v) => void saveSettings({ enableEggSorting: v }, v ? "Egg sorting turned on" : "Egg sorting turned off")} />
          </div>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
            <div className="grid min-w-0 grid-cols-1 gap-1 sm:col-span-3 sm:max-w-md">
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
              <p className="text-[11px] text-slate-500">
                Used wherever eggs are entered or shown as crates: production, sales, internal use, sorting. Stock is always kept in eggs.
              </p>
              {!crateValid && <p className="text-xs text-rose-700">Between 1 and 100.</p>}
            </div>
            <div className="grid min-w-0 grid-cols-1 gap-1">
              <Label htmlFor="es-uprice" className="text-xs text-slate-500">Unsorted / General price per crate</Label>
              <Input id="es-uprice" inputMode="decimal" value={unsortedPrice} placeholder="Not set" disabled={!canEdit}
                onChange={(e) => setUnsortedPrice(e.target.value)} />
              <p className="text-[11px] text-slate-500">Offered as the price on a sale of unsorted eggs; you can still change it on the sale.</p>
              {unsortedParsed === "bad" && <p className="text-xs text-rose-700">Enter a price of 0 or more.</p>}
            </div>
            <div className="flex items-end">
              <Button size="sm" className="w-full sm:w-auto" disabled={!canEdit || !settingsDirty || busy === "settings"}
                onClick={() => void saveSettings({ eggsPerCrate: crateN, unsortedPricePerCrate: unsortedParsed === "bad" ? null : unsortedParsed }, "Settings saved")}>
                {busy === "settings" && <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />} Save
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>

      <Card className="rounded-xl border border-slate-200 bg-white shadow-sm">
        <CardContent className="p-0">
          <div className="border-b border-slate-100 px-4 py-3">
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
              const priceChanged = p !== "bad" && p !== (s.pricePerCrate ?? null)
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
                  {p === "bad" && <div className="text-[11px] text-rose-700">Price must be 0 or more</div>}
                  {(nameChanged || priceChanged) && (
                    <Button size="sm" variant="outline" className="w-full" disabled={!canEdit || busy === `size:${id}` || !(names[id] ?? "").trim()}
                      onClick={() => void run(`size:${id}`, async () => {
                        if (nameChanged) await saveEggSize({ eggSizeId: id, name: names[id].trim(), sortOrder: s.sortOrder, isActive: s.isActive })
                        if (priceChanged) await setEggSizePrice(id, p as number | null)
                      }, "Size saved")}>
                      Save
                    </Button>
                  )}
                </div>
              )
            })}
          </div>
          <div className="hidden overflow-x-auto sm:block">
            <table className="w-full min-w-[44rem] text-sm">
              <thead className="bg-slate-50 text-left text-xs uppercase tracking-wider text-slate-500">
                <tr>
                  <th className="px-4 py-2 font-medium">Size</th>
                  <th className="px-4 py-2 font-medium">Price per crate</th>
                  <th className="px-4 py-2 text-right font-medium">On hand</th>
                  <th className="px-4 py-2 font-medium">Active</th>
                  <th className="px-4 py-2" />
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {sizes.length === 0 && (
                  <tr><td colSpan={5} className="px-4 py-4 text-slate-500">No sizes yet. Turning sorting on adds the standard list.</td></tr>
                )}
                {sizes.map((s) => {
                  const id = s.eggSizeId as number
                  const nameChanged = (names[id] ?? s.name).trim() !== s.name
                  const p = parsePrice(prices[id] ?? "")
                  const priceChanged = p !== "bad" && p !== (s.pricePerCrate ?? null)
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
                              if (priceChanged) await setEggSizePrice(id, p as number | null)
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
            <div className="flex flex-wrap items-end gap-2 border-t border-slate-100 px-4 py-3">
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

      <EggSortingAuditList key={auditKey} title="Change history" description="Settings, sizes, sortings, sale classes and egg adjustments — who changed what, and when." />
    </div>
  )
}
