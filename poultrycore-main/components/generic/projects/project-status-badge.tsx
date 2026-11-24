"use client"

import { Badge } from "@/components/ui/badge"
import { cn } from "@/lib/utils"
import { statusLabel } from "@/lib/api/generic-projects"

export const STATUS_TONE: Record<string, string> = {
  Draft: "bg-slate-100 text-slate-700",
  Planned: "bg-sky-100 text-sky-800",
  Active: "bg-emerald-100 text-emerald-800",
  OnHold: "bg-amber-100 text-amber-800",
  Completed: "bg-indigo-100 text-indigo-800",
  Cancelled: "bg-rose-100 text-rose-700",
  Archived: "bg-slate-200 text-slate-600",
}

export function ProjectStatusBadge({ status, className }: { status?: string | null; className?: string }) {
  if (!status) return null
  return <Badge variant="secondary" className={cn(STATUS_TONE[status], className)}>{statusLabel(status)}</Badge>
}
