"use client"

// The farm's alerts, worded plainly: high deaths, eggs or milk falling,
// missing daily records, stock low or running out, births due, vaccinations
// due, groups under a withdrawal period. Used on the Alerts page and the
// dashboard (limit).

import Link from "next/link"
import { AlertTriangle, Bell, Info } from "lucide-react"
import type { LivestockAlert } from "@/lib/api/livestock"
import { cn } from "@/lib/utils"

const TONE = {
  High: { cls: "border-rose-300 bg-rose-50 text-rose-900", Icon: AlertTriangle },
  Medium: { cls: "border-amber-300 bg-amber-50 text-amber-900", Icon: Bell },
  Info: { cls: "border-stone-200 bg-white text-stone-800", Icon: Info },
} as const

export function AlertsList({ alerts, limit }: { alerts: LivestockAlert[]; limit?: number }) {
  const shown = limit ? alerts.slice(0, limit) : alerts
  return (
    <ul className="space-y-2">
      {shown.map((a, i) => {
        const t = TONE[a.severity]
        return (
          <li key={`${a.kind}-${a.groupId ?? a.itemId ?? ""}-${i}`}>
            <Link href={a.href} className={cn("flex items-start gap-3 rounded-md border px-3 py-2 hover:shadow-sm", t.cls)}>
              <t.Icon className="h-4 w-4 mt-0.5 shrink-0" />
              <span>
                <span className="font-medium">{a.title}</span>
                <span className="block text-sm opacity-80">{a.message}</span>
              </span>
            </Link>
          </li>
        )
      })}
    </ul>
  )
}
