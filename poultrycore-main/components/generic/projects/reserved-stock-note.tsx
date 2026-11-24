"use client"

// Inventory page: how much of a product's stock is reserved for projects. The
// stock itself is unchanged -- reserved goods are still on the shelf.

import { useEffect, useState } from "react"
import { useProjectsEnabled } from "@/hooks/use-generic-projects"
import { getReservedStock } from "@/lib/api/generic-projects"

type Reserved = Awaited<ReturnType<typeof getReservedStock>>
let cached: { at: number; data: Reserved } | null = null

export function useReservedStock() {
  const { enabled } = useProjectsEnabled()
  const [data, setData] = useState<Reserved>(cached?.data ?? [])
  useEffect(() => {
    if (!enabled) return
    if (cached && Date.now() - cached.at < 30_000) { setData(cached.data); return }
    getReservedStock().then((d) => { cached = { at: Date.now(), data: d }; setData(d) }).catch(() => {})
  }, [enabled])
  return data
}

export function ReservedStockNote({ productId, reserved }: { productId: number; reserved: Reserved }) {
  const r = reserved.find((x) => x.productId === productId)
  if (!r || r.reserved <= 0) return null
  return (
    <div className="mt-0.5 text-[11px] text-indigo-700" title={r.projects.map((p) => `${p.label}: ${p.remaining}`).join("\n")}>
      {r.reserved.toLocaleString()} reserved for {r.projects.length === 1 ? r.projects[0].label.split(" — ")[0] : `${r.projects.length} projects`}
    </div>
  )
}
