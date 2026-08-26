"use client"

import { cn } from "@/lib/utils"
import { RoomStatusBadge } from "./room-status-badge"
import type { HotelRoom, HotelRoomStatusType } from "@/lib/api/hotel"

const STATUS_BG: Record<HotelRoomStatusType, string> = {
  Available:   "bg-emerald-50 border-emerald-200 hover:bg-emerald-100",
  Occupied:    "bg-violet-50 border-violet-200 hover:bg-violet-100",
  Maintenance: "bg-amber-50 border-amber-200 hover:bg-amber-100",
  Reserved:    "bg-blue-50 border-blue-200 hover:bg-blue-100",
  Cleaning:    "bg-orange-50 border-orange-200 hover:bg-orange-100",
}

interface RoomGridProps {
  rooms: HotelRoom[]
  onRoomClick?: (room: HotelRoom) => void
}

export function RoomGrid({ rooms, onRoomClick }: RoomGridProps) {
  const floors = Array.from(new Set(rooms.map((r) => r.floorNumber ?? 0))).sort((a, b) => a - b)

  return (
    <div className="space-y-6">
      {floors.map((floor) => {
        const floorRooms = rooms
          .filter((r) => (r.floorNumber ?? 0) === floor)
          .sort((a, b) => a.roomNumber.localeCompare(b.roomNumber, undefined, { numeric: true }))
        const floorName = floorRooms[0]?.floorName ?? `Floor ${floor}`

        return (
          <div key={floor}>
            <h3 className="text-sm font-semibold text-slate-600 mb-2">{floorName}</h3>
            <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 xl:grid-cols-8 gap-3">
              {floorRooms.map((room) => (
                <button
                  key={room.hotelRoomId}
                  type="button"
                  onClick={() => onRoomClick?.(room)}
                  className={cn(
                    "flex flex-col items-center gap-1 rounded-lg border p-3 transition-colors cursor-pointer",
                    STATUS_BG[room.status] ?? "bg-slate-50 border-slate-200"
                  )}
                >
                  <span className="text-lg font-bold text-slate-800">{room.roomNumber}</span>
                  <span className="text-xs text-slate-500">{room.roomTypeName}</span>
                  <RoomStatusBadge status={room.status} className="text-[10px] px-1.5 py-0" />
                </button>
              ))}
            </div>
          </div>
        )
      })}

      {rooms.length === 0 && (
        <div className="text-center py-12 text-slate-400">
          No rooms found. Add rooms in Hotel Setup.
        </div>
      )}
    </div>
  )
}
