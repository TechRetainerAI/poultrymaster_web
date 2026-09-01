"use client"

import { Badge } from "@/components/ui/badge"
import { cn } from "@/lib/utils"
import type { HotelRoomStatusType } from "@/lib/api/hotel"

const STATUS_STYLES: Record<HotelRoomStatusType, string> = {
  Available:   "bg-emerald-100 text-emerald-700 border-emerald-200",
  Occupied:    "bg-violet-100 text-violet-700 border-violet-200",
  Maintenance: "bg-amber-100 text-amber-700 border-amber-200",
  Reserved:    "bg-blue-100 text-blue-700 border-blue-200",
  Cleaning:    "bg-orange-100 text-orange-700 border-orange-200",
}

export function RoomStatusBadge({ status, className }: { status: HotelRoomStatusType; className?: string }) {
  return (
    <Badge variant="outline" className={cn(STATUS_STYLES[status] ?? "bg-slate-100 text-slate-700", className)}>
      {status}
    </Badge>
  )
}
