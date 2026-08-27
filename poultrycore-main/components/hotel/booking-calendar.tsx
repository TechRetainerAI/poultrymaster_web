"use client"
import { useState, useMemo, useRef, useCallback } from "react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { ChevronLeft, ChevronRight, CalendarDays, GripVertical } from "lucide-react"
import { addDays, startOfDay, eachDayOfInterval, format, differenceInDays, isBefore, isAfter, max, min } from "date-fns"
import type { HotelBooking, HotelRoom } from "@/lib/api/hotel"

const STATUS_COLORS: Record<string, { bg: string; border: string; text: string; dragBg: string }> = {
  Confirmed: { bg: "bg-blue-200", border: "border-blue-400", text: "text-blue-900", dragBg: "bg-blue-300" },
  CheckedIn: { bg: "bg-emerald-200", border: "border-emerald-400", text: "text-emerald-900", dragBg: "bg-emerald-300" },
  CheckedOut: { bg: "bg-slate-200", border: "border-slate-400", text: "text-slate-700", dragBg: "bg-slate-300" },
  Cancelled: { bg: "bg-red-100", border: "border-red-300", text: "text-red-700", dragBg: "bg-red-200" },
  NoShow: { bg: "bg-amber-200", border: "border-amber-400", text: "text-amber-900", dragBg: "bg-amber-300" },
}

interface BookingCalendarProps {
  bookings: HotelBooking[]
  rooms: HotelRoom[]
  onBookingClick?: (booking: HotelBooking) => void
  onBookingMove?: (booking: HotelBooking, newRoomId: number, newCheckIn: string, newCheckOut: string) => void
}

type DragMode = "move" | "resize" | null

export function BookingCalendar({ bookings, rooms, onBookingClick, onBookingMove }: BookingCalendarProps) {
  const [startDate, setStartDate] = useState(() => startOfDay(new Date()))
  const DAYS = 14
  const gridRef = useRef<HTMLDivElement>(null)

  // Drag state
  const [dragBooking, setDragBooking] = useState<HotelBooking | null>(null)
  const [dragMode, setDragMode] = useState<DragMode>(null)
  const [dragStartX, setDragStartX] = useState(0)
  const [dragStartY, setDragStartY] = useState(0)
  const [dragOffsetDays, setDragOffsetDays] = useState(0)
  const [dragTargetRoom, setDragTargetRoom] = useState<number | null>(null)
  const [dragResizeDays, setDragResizeDays] = useState(0)

  const dates = useMemo(() => eachDayOfInterval({ start: startDate, end: addDays(startDate, DAYS - 1) }), [startDate])
  const endDate = addDays(startDate, DAYS)

  // Flat ordered room list for Y-axis drag detection
  const orderedRooms = useMemo(() => {
    const sorted = [...rooms].sort((a, b) => {
      const fa = a.floorName ?? a.floorNumber?.toString() ?? "Z"
      const fb = b.floorName ?? b.floorNumber?.toString() ?? "Z"
      if (fa !== fb) return fa.localeCompare(fb)
      return (a.roomNumber ?? "").localeCompare(b.roomNumber ?? "", undefined, { numeric: true })
    })
    return sorted
  }, [rooms])

  // Group rooms by floor
  const floors = useMemo(() => {
    const map = new Map<string, HotelRoom[]>()
    for (const r of orderedRooms) {
      const floor = r.floorName ?? r.floorNumber?.toString() ?? "Unassigned"
      if (!map.has(floor)) map.set(floor, [])
      map.get(floor)!.push(r)
    }
    return Array.from(map.entries())
  }, [orderedRooms])

  function getBookingsForRoom(roomId: number) {
    return bookings.filter((b) => {
      if (b.hotelRoomId !== roomId) return false
      if (b.status === "Cancelled") return false
      const bStart = startOfDay(new Date(b.checkInDate))
      const bEnd = startOfDay(new Date(b.checkOutDate))
      return isBefore(bStart, endDate) && isAfter(bEnd, startDate)
    })
  }

  function getBarStyle(booking: HotelBooking, offsetDays = 0, resizeDays = 0, targetRoom?: number | null) {
    let bStart = startOfDay(new Date(booking.checkInDate))
    let bEnd = startOfDay(new Date(booking.checkOutDate))

    // Apply drag offsets
    if (offsetDays !== 0) { bStart = addDays(bStart, offsetDays); bEnd = addDays(bEnd, offsetDays) }
    if (resizeDays !== 0) { bEnd = addDays(bEnd, resizeDays) }

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

  // Convert pixel offset to day offset
  const pixelsToDays = useCallback((px: number): number => {
    if (!gridRef.current) return 0
    const gridWidth = gridRef.current.getBoundingClientRect().width - 112 // subtract room label width
    const dayWidth = gridWidth / DAYS
    return Math.round(px / dayWidth)
  }, [DAYS])

  // Find which room row the cursor is over
  const findRoomAtY = useCallback((clientY: number): number | null => {
    if (!gridRef.current) return null
    const rows = gridRef.current.querySelectorAll("[data-room-id]")
    for (const row of rows) {
      const rect = row.getBoundingClientRect()
      if (clientY >= rect.top && clientY <= rect.bottom) {
        return Number(row.getAttribute("data-room-id"))
      }
    }
    return null
  }, [])

  // Drag handlers
  function handleDragStart(e: React.MouseEvent, booking: HotelBooking, mode: DragMode) {
    if (booking.status === "CheckedOut" || booking.status === "Cancelled") return
    e.preventDefault()
    e.stopPropagation()
    setDragBooking(booking)
    setDragMode(mode)
    setDragStartX(e.clientX)
    setDragStartY(e.clientY)
    setDragOffsetDays(0)
    setDragResizeDays(0)
    setDragTargetRoom(booking.hotelRoomId ?? null)

    const handleMouseMove = (ev: MouseEvent) => {
      const dx = ev.clientX - e.clientX
      const daysDelta = pixelsToDays(dx)

      if (mode === "move") {
        setDragOffsetDays(daysDelta)
        const roomId = findRoomAtY(ev.clientY)
        if (roomId) setDragTargetRoom(roomId)
      } else if (mode === "resize") {
        setDragResizeDays(Math.max(-differenceInDays(startOfDay(new Date(booking.checkOutDate)), startOfDay(new Date(booking.checkInDate))) + 1, daysDelta))
      }
    }

    const handleMouseUp = (ev: MouseEvent) => {
      document.removeEventListener("mousemove", handleMouseMove)
      document.removeEventListener("mouseup", handleMouseUp)
      document.body.style.cursor = ""
      document.body.style.userSelect = ""

      const dx = ev.clientX - e.clientX
      const finalDays = pixelsToDays(dx)
      const finalRoom = mode === "move" ? findRoomAtY(ev.clientY) : null

      if (mode === "move" && (finalDays !== 0 || (finalRoom && finalRoom !== booking.hotelRoomId))) {
        const newCheckIn = addDays(startOfDay(new Date(booking.checkInDate)), finalDays)
        const newCheckOut = addDays(startOfDay(new Date(booking.checkOutDate)), finalDays)
        const targetRoomId = finalRoom ?? booking.hotelRoomId ?? 0
        onBookingMove?.(booking, targetRoomId, format(newCheckIn, "yyyy-MM-dd"), format(newCheckOut, "yyyy-MM-dd"))
      } else if (mode === "resize" && finalDays !== 0) {
        const newCheckOut = addDays(startOfDay(new Date(booking.checkOutDate)), Math.max(-differenceInDays(startOfDay(new Date(booking.checkOutDate)), startOfDay(new Date(booking.checkInDate))) + 1, finalDays))
        onBookingMove?.(booking, booking.hotelRoomId ?? 0, booking.checkInDate.slice(0, 10), format(newCheckOut, "yyyy-MM-dd"))
      }

      setDragBooking(null)
      setDragMode(null)
      setDragOffsetDays(0)
      setDragResizeDays(0)
      setDragTargetRoom(null)
    }

    document.body.style.cursor = mode === "resize" ? "ew-resize" : "grabbing"
    document.body.style.userSelect = "none"
    document.addEventListener("mousemove", handleMouseMove)
    document.addEventListener("mouseup", handleMouseUp)
  }

  const today = startOfDay(new Date())
  const isDraggable = (b: HotelBooking) => b.status === "Confirmed" || b.status === "CheckedIn"

  return (
    <div className="space-y-3">
      {/* Navigation */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Button variant="outline" size="sm" onClick={() => setStartDate(addDays(startDate, -DAYS))}><ChevronLeft className="h-4 w-4" /></Button>
          <Button variant="outline" size="sm" onClick={() => setStartDate(startOfDay(new Date()))}>Today</Button>
          <Button variant="outline" size="sm" onClick={() => setStartDate(addDays(startDate, DAYS))}><ChevronRight className="h-4 w-4" /></Button>
          <span className="text-sm font-medium text-slate-700 ml-2">{format(startDate, "MMM d")} — {format(addDays(startDate, DAYS - 1), "MMM d, yyyy")}</span>
        </div>
        <div className="flex items-center gap-3 text-xs">
          {Object.entries(STATUS_COLORS).filter(([k]) => k !== "Cancelled").map(([status, colors]) => (
            <div key={status} className="flex items-center gap-1">
              <div className={`w-3 h-3 rounded ${colors.bg} ${colors.border} border`} />
              <span className="text-slate-600">{status}</span>
            </div>
          ))}
          <div className="flex items-center gap-1 ml-2 text-violet-600">
            <GripVertical className="h-3 w-3" />
            <span>Drag to move/resize</span>
          </div>
        </div>
      </div>

      {/* Calendar Grid */}
      <div className="border rounded-lg overflow-hidden bg-white select-none" ref={gridRef}>
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
                <div key={d.toISOString()} className={`flex-1 p-1 text-center border-r last:border-r-0 ${isToday ? "bg-violet-100" : isWeekend ? "bg-slate-100" : ""}`}>
                  <div className={`text-[10px] uppercase ${isToday ? "text-violet-700 font-bold" : "text-slate-400"}`}>{format(d, "EEE")}</div>
                  <div className={`text-xs font-semibold ${isToday ? "text-violet-700" : "text-slate-600"}`}>{format(d, "d")}</div>
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
              <div className="flex border-b bg-slate-50/50">
                <div className="w-28 min-w-28 p-1.5 border-r"><Badge variant="outline" className="text-[10px] bg-violet-50 text-violet-700">{floorName}</Badge></div>
                <div className="flex-1" />
              </div>

              {floorRooms.map((room) => {
                const roomBookings = getBookingsForRoom(room.hotelRoomId)
                const isDropTarget = dragBooking && dragMode === "move" && dragTargetRoom === room.hotelRoomId && dragTargetRoom !== dragBooking.hotelRoomId
                return (
                  <div key={room.hotelRoomId} data-room-id={room.hotelRoomId} className={`flex border-b last:border-b-0 group ${isDropTarget ? "bg-violet-50" : "hover:bg-slate-50/50"}`}>
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
                          return <div key={d.toISOString()} className={`flex-1 border-r last:border-r-0 ${isToday ? "bg-violet-50/50" : isWeekend ? "bg-slate-50/50" : ""}`} />
                        })}
                      </div>

                      {/* Booking Bars */}
                      {roomBookings.map((b) => {
                        const isDragging = dragBooking?.hotelBookingId === b.hotelBookingId
                        const isBeingMoved = isDragging && dragMode === "move" && dragTargetRoom !== room.hotelRoomId
                        // If this booking is being dragged to a different room, hide it here
                        if (isBeingMoved) {
                          const style = getBarStyle(b)
                          if (!style) return null
                          return (
                            <div key={b.hotelBookingId} className="absolute top-1 bottom-1 rounded-md border border-dashed border-slate-300 bg-slate-100/50 z-10" style={{ left: style.left, width: style.width }} />
                          )
                        }

                        const offsetDays = isDragging && dragMode === "move" ? dragOffsetDays : 0
                        const resizeDays = isDragging && dragMode === "resize" ? dragResizeDays : 0
                        const style = getBarStyle(b, offsetDays, resizeDays)
                        if (!style) return null
                        const colors = STATUS_COLORS[b.status] ?? STATUS_COLORS.Confirmed
                        const guestName = `${b.guestFirstName ?? ""} ${b.guestLastName ?? ""}`.trim()
                        const canDrag = isDraggable(b)

                        return (
                          <div
                            key={b.hotelBookingId}
                            className={`absolute top-1 bottom-1 rounded-md ${isDragging ? colors.dragBg : colors.bg} ${colors.border} border ${canDrag ? "cursor-grab active:cursor-grabbing" : "cursor-pointer"} hover:brightness-95 transition-colors flex items-center overflow-hidden z-10 ${isDragging ? "shadow-lg ring-2 ring-violet-400 z-20 opacity-90" : ""}`}
                            style={{ left: style.left, width: style.width }}
                            title={`${guestName} | ${b.bookingRef} | ${b.checkInDate?.slice(0, 10)} → ${b.checkOutDate?.slice(0, 10)}${canDrag ? "\nDrag to move | Drag right edge to resize" : ""}`}
                            onMouseDown={canDrag ? (e) => handleDragStart(e, b, "move") : undefined}
                            onClick={(e) => { if (!dragBooking) { e.stopPropagation(); onBookingClick?.(b) } }}
                          >
                            <span className={`text-[11px] font-medium truncate px-1.5 flex-1 ${colors.text}`}>
                              {guestName || b.bookingRef}
                            </span>
                            {/* Resize handle */}
                            {canDrag && (
                              <div
                                className="w-2 h-full cursor-ew-resize flex items-center justify-center shrink-0 hover:bg-black/10 rounded-r"
                                onMouseDown={(e) => { e.stopPropagation(); handleDragStart(e, b, "resize") }}
                              >
                                <div className="w-0.5 h-3 bg-current opacity-30 rounded" />
                              </div>
                            )}
                          </div>
                        )
                      })}

                      {/* Ghost bar for booking being dragged TO this room */}
                      {dragBooking && dragMode === "move" && dragTargetRoom === room.hotelRoomId && dragTargetRoom !== dragBooking.hotelRoomId && (() => {
                        const style = getBarStyle(dragBooking, dragOffsetDays)
                        if (!style) return null
                        const colors = STATUS_COLORS[dragBooking.status] ?? STATUS_COLORS.Confirmed
                        const guestName = `${dragBooking.guestFirstName ?? ""} ${dragBooking.guestLastName ?? ""}`.trim()
                        return (
                          <div
                            className={`absolute top-1 bottom-1 rounded-md ${colors.dragBg} ${colors.border} border-2 border-dashed shadow-lg z-20 flex items-center px-1.5 overflow-hidden opacity-80`}
                            style={{ left: style.left, width: style.width }}
                          >
                            <span className={`text-[11px] font-medium truncate ${colors.text}`}>{guestName || dragBooking.bookingRef}</span>
                          </div>
                        )
                      })()}
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
        &middot; Drag Confirmed/CheckedIn bookings to move or resize
      </div>
    </div>
  )
}
