"use client"
import { useState, useMemo } from "react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { ChevronLeft, ChevronRight, CalendarDays } from "lucide-react"
import { addDays, startOfDay, eachDayOfInterval, format, differenceInDays, isBefore, isAfter, max, min } from "date-fns"
import type { HotelBooking, HotelRoom } from "@/lib/api/hotel"

const STATUS_COLORS: Record<string, { bg: string; border: string; text: string }> = {
  Confirmed: { bg: "bg-blue-200", border: "border-blue-400", text: "text-blue-900" },
  CheckedIn: { bg: "bg-emerald-200", border: "border-emerald-400", text: "text-emerald-900" },
  CheckedOut: { bg: "bg-slate-200", border: "border-slate-400", text: "text-slate-700" },
  Cancelled: { bg: "bg-red-100", border: "border-red-300", text: "text-red-700" },
  NoShow: { bg: "bg-amber-200", border: "border-amber-400", text: "text-amber-900" },
}

interface BookingCalendarProps {
  bookings: HotelBooking[]
  rooms: HotelRoom[]
  onBookingClick?: (booking: HotelBooking) => void
}

export function BookingCalendar({ bookings, rooms, onBookingClick }: BookingCalendarProps) {
  const [startDate, setStartDate] = useState(() => startOfDay(new Date()))
  const DAYS = 14

  const dates = useMemo(() => eachDayOfInterval({ start: startDate, end: addDays(startDate, DAYS - 1) }), [startDate])
  const endDate = addDays(startDate, DAYS)

  // Group rooms by floor
  const floors = useMemo(() => {
    const map = new Map<string, HotelRoom[]>()
    const sorted = [...rooms].sort((a, b) => (a.roomNumber ?? "").localeCompare(b.roomNumber ?? "", undefined, { numeric: true }))
    for (const r of sorted) {
      const floor = r.floorName ?? r.floorNumber?.toString() ?? "Unassigned"
      if (!map.has(floor)) map.set(floor, [])
      map.get(floor)!.push(r)
    }
    return Array.from(map.entries())
  }, [rooms])

  // Find bookings overlapping the visible window for each room
  function getBookingsForRoom(roomId: number) {
    return bookings.filter((b) => {
      if (b.hotelRoomId !== roomId) return false
      if (b.status === "Cancelled") return false
      const bStart = startOfDay(new Date(b.checkInDate))
      const bEnd = startOfDay(new Date(b.checkOutDate))
      return isBefore(bStart, endDate) && isAfter(bEnd, startDate)
    })
  }

  function getBarStyle(booking: HotelBooking) {
    const bStart = startOfDay(new Date(booking.checkInDate))
    const bEnd = startOfDay(new Date(booking.checkOutDate))
    const visStart = max([bStart, startDate])
    const visEnd = min([bEnd, endDate])
    const left = differenceInDays(visStart, startDate)
    const width = differenceInDays(visEnd, visStart)
    if (width <= 0) return null
    return {
      left: `${(left / DAYS) * 100}%`,
      width: `${(width / DAYS) * 100}%`,
    }
  }

  const today = startOfDay(new Date())

  return (
    <div className="space-y-3">
      {/* Navigation */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Button variant="outline" size="sm" onClick={() => setStartDate(addDays(startDate, -DAYS))}>
            <ChevronLeft className="h-4 w-4" />
          </Button>
          <Button variant="outline" size="sm" onClick={() => setStartDate(startOfDay(new Date()))}>
            Today
          </Button>
          <Button variant="outline" size="sm" onClick={() => setStartDate(addDays(startDate, DAYS))}>
            <ChevronRight className="h-4 w-4" />
          </Button>
          <span className="text-sm font-medium text-slate-700 ml-2">
            {format(startDate, "MMM d")} — {format(addDays(startDate, DAYS - 1), "MMM d, yyyy")}
          </span>
        </div>
        <div className="flex items-center gap-3 text-xs">
          {Object.entries(STATUS_COLORS).filter(([k]) => k !== "Cancelled").map(([status, colors]) => (
            <div key={status} className="flex items-center gap-1">
              <div className={`w-3 h-3 rounded ${colors.bg} ${colors.border} border`} />
              <span className="text-slate-600">{status}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Calendar Grid */}
      <div className="border rounded-lg overflow-hidden bg-white">
        {/* Date Headers */}
        <div className="flex border-b bg-slate-50">
          <div className="w-28 min-w-28 p-2 text-xs font-semibold text-slate-500 border-r flex items-center gap-1">
            <CalendarDays className="h-3 w-3" /> Room
          </div>
          <div className="flex-1 flex">
            {dates.map((d) => {
              const isToday = d.getTime() === today.getTime()
              const isWeekend = d.getDay() === 0 || d.getDay() === 6
              return (
                <div
                  key={d.toISOString()}
                  className={`flex-1 p-1 text-center border-r last:border-r-0 ${isToday ? "bg-violet-100" : isWeekend ? "bg-slate-100" : ""}`}
                >
                  <div className={`text-[10px] uppercase ${isToday ? "text-violet-700 font-bold" : "text-slate-400"}`}>
                    {format(d, "EEE")}
                  </div>
                  <div className={`text-xs font-semibold ${isToday ? "text-violet-700" : "text-slate-600"}`}>
                    {format(d, "d")}
                  </div>
                </div>
              )
            })}
          </div>
        </div>

        {/* Room Rows */}
        {floors.length === 0 ? (
          <div className="p-8 text-center text-slate-400">No rooms configured. Add rooms in Hotel Setup first.</div>
        ) : (
          floors.map(([floorName, floorRooms]) => (
            <div key={floorName}>
              {/* Floor Header */}
              <div className="flex border-b bg-slate-50/50">
                <div className="w-28 min-w-28 p-1.5 border-r">
                  <Badge variant="outline" className="text-[10px] bg-violet-50 text-violet-700">{floorName}</Badge>
                </div>
                <div className="flex-1" />
              </div>

              {/* Room Rows for this Floor */}
              {floorRooms.map((room) => {
                const roomBookings = getBookingsForRoom(room.hotelRoomId)
                return (
                  <div key={room.hotelRoomId} className="flex border-b last:border-b-0 hover:bg-slate-50/50 group">
                    <div className="w-28 min-w-28 p-2 border-r flex items-center gap-1.5">
                      <span className="text-sm font-semibold text-slate-700">{room.roomNumber}</span>
                      <span className="text-[10px] text-slate-400 truncate">{room.roomTypeName}</span>
                    </div>
                    <div className="flex-1 relative" style={{ minHeight: "36px" }}>
                      {/* Day grid lines */}
                      <div className="absolute inset-0 flex pointer-events-none">
                        {dates.map((d) => {
                          const isToday = d.getTime() === today.getTime()
                          const isWeekend = d.getDay() === 0 || d.getDay() === 6
                          return (
                            <div
                              key={d.toISOString()}
                              className={`flex-1 border-r last:border-r-0 ${isToday ? "bg-violet-50/50" : isWeekend ? "bg-slate-50/50" : ""}`}
                            />
                          )
                        })}
                      </div>

                      {/* Booking Bars */}
                      {roomBookings.map((b) => {
                        const style = getBarStyle(b)
                        if (!style) return null
                        const colors = STATUS_COLORS[b.status] ?? STATUS_COLORS.Confirmed
                        const guestName = `${b.guestFirstName ?? ""} ${b.guestLastName ?? ""}`.trim()
                        return (
                          <div
                            key={b.hotelBookingId}
                            className={`absolute top-1 bottom-1 rounded-md ${colors.bg} ${colors.border} border cursor-pointer hover:brightness-95 transition-all flex items-center px-1.5 overflow-hidden z-10`}
                            style={{ left: style.left, width: style.width }}
                            title={`${guestName} | ${b.bookingRef} | ${b.checkInDate?.slice(0, 10)} → ${b.checkOutDate?.slice(0, 10)}`}
                            onClick={() => onBookingClick?.(b)}
                          >
                            <span className={`text-[11px] font-medium truncate ${colors.text}`}>
                              {guestName || b.bookingRef}
                            </span>
                          </div>
                        )
                      })}
                    </div>
                  </div>
                )
              })}
            </div>
          ))
        )}
      </div>

      {/* Summary */}
      <div className="text-xs text-slate-400 text-right">
        {rooms.length} rooms &middot; {bookings.filter((b) => b.status !== "Cancelled").length} active bookings
      </div>
    </div>
  )
}
