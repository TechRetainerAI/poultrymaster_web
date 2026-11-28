"use client"

import { Badge } from "@/components/ui/badge"
import type { MedicineClass } from "@/lib/api/generic-pharmacy"
import { MEDICINE_CLASSES, expiryState } from "@/lib/generic/pharmacy"

export function ClassBadge({ cls }: { cls?: MedicineClass | null }) {
  const c = cls ?? "C"
  const tone = c === "A" ? "bg-rose-100 text-rose-700" : c === "B" ? "bg-amber-100 text-amber-800" : "bg-emerald-100 text-emerald-700"
  const short = MEDICINE_CLASSES.find((x) => x.value === c)?.short
  return <Badge className={`${tone} whitespace-nowrap`}>Class {c} · {short}</Badge>
}

export function ExpiryBadge({ date, days }: { date?: string | null; days: number }) {
  const s = expiryState(date, days)
  if (s === "none") return <span className="text-slate-400">—</span>
  const d = String(date).slice(0, 10)
  if (s === "expired") return <Badge className="bg-rose-100 text-rose-700 whitespace-nowrap">Expired {d}</Badge>
  if (s === "soon") return <Badge className="bg-amber-100 text-amber-800 whitespace-nowrap">{d}</Badge>
  return <span className="text-slate-700 whitespace-nowrap">{d}</span>
}
