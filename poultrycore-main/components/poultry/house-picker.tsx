"use client"

// House dropdown for the Add / Edit Flock dialogs. Each option shows the
// location, capacity, birds already in it and the room left, so the farm can
// see which house is free before choosing.
//
// "Occupied" uses the same rule as the dialogs' capacity check: the birds of
// the house's ACTIVE flocks (flock.quantity), leaving out the flock being
// edited. Showing anything else would let the picker say "free" and the save
// then refuse it.

import { useMemo } from "react"
import { Home, MapPin } from "lucide-react"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { cn } from "@/lib/utils"
import type { House } from "@/lib/api/house"

interface FlockLike { flockId: number; houseId?: number | null; active?: boolean; quantity?: number | null }

export interface HouseOccupancy {
  capacity: number          // 0 = no capacity recorded
  occupied: number
  free: number | null       // null when capacity is unknown
  flockCount: number
  state: "empty" | "free" | "full" | "unknown"
}

export function houseOccupancy(house: House, flocks: FlockLike[], excludeFlockId?: number | null): HouseOccupancy {
  const mine = flocks.filter((f) => f.houseId === house.houseId && f.active && f.flockId !== excludeFlockId)
  const occupied = mine.reduce((s, f) => s + (Number(f.quantity) || 0), 0)
  const capacity = Number(house.capacity) || 0
  const free = capacity > 0 ? Math.max(0, capacity - occupied) : null
  const state = capacity <= 0 ? (occupied === 0 ? "empty" : "unknown")
    : free === 0 ? "full"
    : occupied === 0 ? "empty"
    : "free"
  return { capacity, occupied, free, flockCount: mine.length, state }
}

const houseName = (h: House) => (h as any).houseName || h.name || `House ${h.houseId}`

const STATE_BADGE: Record<HouseOccupancy["state"], [string, string]> = {
  empty: ["Empty", "bg-emerald-50 text-emerald-700 border-emerald-200"],
  free: ["Has space", "bg-sky-50 text-sky-700 border-sky-200"],
  full: ["Full", "bg-red-50 text-red-700 border-red-200"],
  unknown: ["In use", "bg-slate-50 text-slate-600 border-slate-200"],
}

const NONE = "none"

function Badge({ state }: { state: HouseOccupancy["state"] }) {
  const [text, cls] = STATE_BADGE[state]
  return <span className={cn("shrink-0 rounded-full border px-1.5 py-px text-[10px] font-medium leading-4", cls)}>{text}</span>
}

function capacityText(o: HouseOccupancy) {
  if (o.capacity <= 0) return o.occupied > 0 ? `${o.occupied.toLocaleString()} birds · no capacity set` : "No capacity set"
  return `${o.occupied.toLocaleString()} / ${o.capacity.toLocaleString()} birds`
}

/** A house dropdown whose options show location, capacity, birds in it and room left. */
export function HousePicker({ houses, flocks, value, onChange, birds, excludeFlockId, disabled }: {
  houses: House[]
  flocks: FlockLike[]
  value: number | null | undefined
  onChange: (houseId: number | null) => void
  /** Birds this flock will put in the house, to warn when they will not fit. */
  birds?: number
  excludeFlockId?: number | null
  disabled?: boolean
}) {
  const rows = useMemo(
    () => houses.map((h) => ({ h, o: houseOccupancy(h, flocks, excludeFlockId) })),
    [houses, flocks, excludeFlockId],
  )
  const selected = value ? rows.find((r) => r.h.houseId === value) ?? null : null
  const need = Math.max(0, Number(birds) || 0)
  const overBy = selected && selected.o.free != null && need > selected.o.free ? need - selected.o.free : 0

  return (
    <div className="space-y-1.5">
      <Select value={value ? String(value) : NONE} onValueChange={(v) => onChange(v === NONE ? null : Number(v))} disabled={disabled}>
        <SelectTrigger className="h-10 w-full bg-white">
          <SelectValue>
            {selected ? (
              <span className="flex min-w-0 items-center gap-2">
                <Home className="h-4 w-4 text-slate-400" />
                <span className="truncate font-medium text-slate-900">{houseName(selected.h)}</span>
                {selected.h.location?.trim() && <span className="hidden truncate text-slate-500 sm:inline">· {selected.h.location}</span>}
                <Badge state={selected.o.state} />
                {selected.o.free != null && (
                  <span className={cn("ml-auto text-xs font-semibold tabular-nums", overBy > 0 ? "text-red-600" : "text-emerald-700")}>
                    {selected.o.free.toLocaleString()} free
                  </span>
                )}
              </span>
            ) : (
              <span className="flex items-center gap-2 text-slate-500"><Home className="h-4 w-4 text-slate-400" />No house</span>
            )}
          </SelectValue>
        </SelectTrigger>
        <SelectContent className="max-h-80">
          <SelectItem value={NONE}>
            <span className="text-slate-600">No house — assign one later</span>
          </SelectItem>
          {rows.map(({ h, o }) => {
            const wontFit = o.free != null && need > o.free
            return (
              <SelectItem key={h.houseId} value={String(h.houseId)} className="py-2">
                <span className="flex w-full min-w-[18rem] flex-col gap-0.5">
                  <span className="flex items-center gap-2">
                    <span className="font-medium text-slate-900">{houseName(h)}</span>
                    <Badge state={o.state} />
                  </span>
                  <span className="flex items-center gap-1.5 text-xs text-slate-500">
                    <MapPin className="h-3 w-3" />
                    <span>{h.location?.trim() || "No location"}</span>
                    <span className="text-slate-300">·</span>
                    <span className="tabular-nums">{capacityText(o)}</span>
                    {o.free != null && (
                      <>
                        <span className="text-slate-300">·</span>
                        <span className={cn("font-semibold tabular-nums", o.state === "full" || wontFit ? "text-red-600" : "text-emerald-700")}>
                          {o.free.toLocaleString()} free
                        </span>
                      </>
                    )}
                  </span>
                </span>
              </SelectItem>
            )
          })}
        </SelectContent>
      </Select>

      {selected && (
        <p className="text-xs text-slate-500">
          {selected.h.location?.trim() ? `${selected.h.location} · ` : ""}{capacityText(selected.o)}
          {selected.o.flockCount > 0 ? ` in ${selected.o.flockCount} active flock${selected.o.flockCount === 1 ? "" : "s"}` : ""}
          {selected.o.free != null ? ` · ${selected.o.free.toLocaleString()} free` : ""}
        </p>
      )}
      {houses.length === 0 && <p className="text-xs text-slate-500">No houses set up yet. Add them under Farm Setup → Houses.</p>}
      {overBy > 0 && selected && (
        <p className="text-xs text-red-600">
          Not enough room: {houseName(selected.h)} has space for {(selected.o.free ?? 0).toLocaleString()} more birds; this flock needs {need.toLocaleString()}.
        </p>
      )}
    </div>
  )
}
