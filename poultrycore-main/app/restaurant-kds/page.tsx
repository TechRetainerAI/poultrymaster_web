"use client"

import { useEffect, useState, useRef, useCallback } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Loader2, ChefHat, Clock, Bell, RotateCcw, Check, Volume2, VolumeX, Maximize, Minimize } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import {
  listKdsStations, getKdsQueue, getKdsStats, kdsBumpItem, kdsRecallItem, kdsBumpOrder,
  type KdsStation, type KdsQueueItem, type KdsStats,
} from "@/lib/api/restaurant"

function getTimingColor(minutes: number): string {
  if (minutes < 5) return "border-green-500 bg-green-50"
  if (minutes < 10) return "border-yellow-500 bg-yellow-50"
  if (minutes < 15) return "border-orange-500 bg-orange-50"
  return "border-red-500 bg-red-50 animate-pulse"
}

function formatTime(minutes: number): string {
  if (minutes < 1) return "<1m"
  if (minutes < 60) return `${Math.floor(minutes)}m`
  return `${Math.floor(minutes / 60)}h${Math.floor(minutes % 60)}m`
}

// Group queue items by order
function groupByOrder(items: KdsQueueItem[]): Record<string, KdsQueueItem[]> {
  const groups: Record<string, KdsQueueItem[]> = {}
  for (const item of items) {
    const key = `${item.orderId}-${item.orderNumber}`
    if (!groups[key]) groups[key] = []
    groups[key].push(item)
  }
  return groups
}

export default function RestaurantKDSPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [loading, setLoading] = useState(true)
  const [stations, setStations] = useState<KdsStation[]>([])
  const [queue, setQueue] = useState<KdsQueueItem[]>([])
  const [stats, setStats] = useState<KdsStats | null>(null)
  const [activeStation, setActiveStation] = useState<number | null>(null)
  const [isExpo, setIsExpo] = useState(false)
  const [soundOn, setSoundOn] = useState(true)
  const [isFullscreen, setIsFullscreen] = useState(false)
  const [prevCount, setPrevCount] = useState(0)

  const refreshRef = useRef<NodeJS.Timeout | null>(null)
  const audioRef = useRef<HTMLAudioElement | null>(null)

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    loadInitial()
  }, [activeFarmType, router])

  async function loadInitial() {
    setLoading(true)
    try {
      const st = await listKdsStations()
      setStations(st.filter(s => s.isActive))
      await refreshQueue()
    } catch (e: any) {
      toast({ title: "Failed to load", description: e?.message, variant: "destructive" })
    } finally { setLoading(false) }
  }

  const refreshQueue = useCallback(async () => {
    try {
      const [q, s] = await Promise.all([
        getKdsQueue(activeStation || undefined, isExpo),
        getKdsStats(),
      ])
      // Play sound for new items
      if (soundOn && q.length > prevCount && prevCount > 0) {
        try { audioRef.current?.play() } catch {}
      }
      setPrevCount(q.length)
      setQueue(q)
      setStats(s)
    } catch {}
  }, [activeStation, isExpo, soundOn, prevCount])

  // Auto-refresh every 5 seconds
  useEffect(() => {
    refreshQueue()
    refreshRef.current = setInterval(refreshQueue, 5000)
    return () => { if (refreshRef.current) clearInterval(refreshRef.current) }
  }, [refreshQueue])

  async function handleBump(orderItemId: number) {
    try {
      const { newStatus } = await kdsBumpItem(orderItemId)
      toast({ title: `Item bumped to ${newStatus}` })
      refreshQueue()
    } catch (e: any) {
      toast({ title: "Bump failed", description: e?.message, variant: "destructive" })
    }
  }

  async function handleRecall(orderItemId: number) {
    try {
      const { newStatus } = await kdsRecallItem(orderItemId)
      toast({ title: `Item recalled to ${newStatus}` })
      refreshQueue()
    } catch (e: any) {
      toast({ title: "Recall failed", description: e?.message, variant: "destructive" })
    }
  }

  async function handleBumpOrder(orderId: number) {
    try {
      await kdsBumpOrder(orderId)
      toast({ title: "Order bumped" })
      refreshQueue()
    } catch (e: any) {
      toast({ title: "Bump failed", description: e?.message, variant: "destructive" })
    }
  }

  function toggleFullscreen() {
    if (!document.fullscreenElement) {
      document.documentElement.requestFullscreen()
      setIsFullscreen(true)
    } else {
      document.exitFullscreen()
      setIsFullscreen(false)
    }
  }

  const orderGroups = groupByOrder(queue)

  if (loading) return (
    <div className="flex h-screen items-center justify-center bg-gray-900"><Loader2 className="h-10 w-10 animate-spin text-white" /></div>
  )

  return (
    <div className="flex flex-col h-screen bg-gray-900 text-white">
      {/* Hidden audio element for new order alert */}
      <audio ref={audioRef} preload="auto">
        <source src="data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEARKwAAIhYAQACABAAZGF0YQAAAAA=" type="audio/wav" />
      </audio>

      {/* Top bar */}
      <div className="flex items-center justify-between px-4 py-2 bg-gray-800 border-b border-gray-700 flex-shrink-0">
        <div className="flex items-center gap-3">
          <ChefHat className="h-6 w-6 text-orange-500" />
          <h1 className="text-lg font-bold">Kitchen Display</h1>
        </div>

        {/* Station tabs */}
        <div className="flex gap-1">
          <Button size="sm" variant={activeStation === null && !isExpo ? "default" : "ghost"}
            className={activeStation === null && !isExpo ? "bg-orange-600" : "text-gray-300"}
            onClick={() => { setActiveStation(null); setIsExpo(false) }}>All</Button>
          {stations.map(s => (
            <Button key={s.kdsStationId} size="sm"
              variant={activeStation === s.kdsStationId ? "default" : "ghost"}
              className={activeStation === s.kdsStationId ? "" : "text-gray-300"}
              style={activeStation === s.kdsStationId ? { backgroundColor: s.displayColor } : {}}
              onClick={() => { setActiveStation(s.kdsStationId); setIsExpo(s.isExpo) }}>
              {s.name}
            </Button>
          ))}
          <Button size="sm" variant={isExpo && activeStation === null ? "default" : "ghost"}
            className={isExpo && activeStation === null ? "bg-purple-600" : "text-gray-300"}
            onClick={() => { setActiveStation(null); setIsExpo(true) }}>Expo</Button>
        </div>

        {/* Stats + controls */}
        <div className="flex items-center gap-3">
          {stats && (
            <div className="flex gap-3 text-xs">
              <span className="text-blue-400">Pending: {stats.pendingCount}</span>
              <span className="text-yellow-400">Preparing: {stats.preparingCount}</span>
              <span className="text-green-400">Ready: {stats.readyCount}</span>
              {stats.avgPrepMinutes != null && <span className="text-gray-400">Avg: {stats.avgPrepMinutes.toFixed(1)}m</span>}
              {stats.longestWaitMinutes != null && stats.longestWaitMinutes > 0 && (
                <span className={stats.longestWaitMinutes > 15 ? "text-red-400 font-bold" : "text-gray-400"}>
                  Max: {formatTime(stats.longestWaitMinutes)}
                </span>
              )}
            </div>
          )}
          <Button variant="ghost" size="icon" className="text-gray-400" onClick={() => setSoundOn(!soundOn)}>
            {soundOn ? <Volume2 className="h-4 w-4" /> : <VolumeX className="h-4 w-4" />}
          </Button>
          <Button variant="ghost" size="icon" className="text-gray-400" onClick={toggleFullscreen}>
            {isFullscreen ? <Minimize className="h-4 w-4" /> : <Maximize className="h-4 w-4" />}
          </Button>
          <Button variant="ghost" size="sm" className="text-gray-400" onClick={() => router.push("/restaurant-pos")}>Exit</Button>
        </div>
      </div>

      {/* Order cards grid */}
      <div className="flex-1 overflow-y-auto p-4">
        {Object.keys(orderGroups).length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full text-gray-500">
            <ChefHat className="h-16 w-16 mb-4" />
            <p className="text-xl">No active orders</p>
            <p className="text-sm mt-1">Waiting for orders...</p>
          </div>
        ) : (
          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-4">
            {Object.entries(orderGroups).map(([key, items]) => {
              const first = items[0]
              const maxElapsed = Math.max(...items.map(i => i.elapsedMinutes))
              const allReady = items.every(i => i.status === "Ready")
              const timingClass = getTimingColor(maxElapsed)

              return (
                <div key={key} className={`border-2 rounded-xl overflow-hidden ${timingClass}`}>
                  {/* Order header */}
                  <div className="flex items-center justify-between px-3 py-2 bg-gray-800/90">
                    <div>
                      <span className="font-bold text-white">{first.orderNumber}</span>
                      <div className="flex gap-1 mt-0.5">
                        <Badge variant="outline" className="text-[10px] h-4 text-gray-300 border-gray-600">{first.orderType}</Badge>
                        {first.tableNumber && <Badge variant="outline" className="text-[10px] h-4 text-gray-300 border-gray-600">T{first.tableNumber}</Badge>}
                      </div>
                    </div>
                    <div className="flex items-center gap-1">
                      <Clock className="h-3 w-3 text-gray-400" />
                      <span className={`text-sm font-mono ${maxElapsed > 15 ? "text-red-400 font-bold" : maxElapsed > 10 ? "text-yellow-400" : "text-green-400"}`}>
                        {formatTime(maxElapsed)}
                      </span>
                    </div>
                  </div>

                  {/* Items */}
                  <div className="divide-y divide-gray-300/30">
                    {items.map(item => (
                      <div key={item.orderItemId} className="px-3 py-2 flex items-start justify-between gap-2">
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-1">
                            <span className="font-bold text-gray-900 text-lg">{item.quantity}x</span>
                            <span className="font-medium text-gray-900 truncate">{item.itemName}</span>
                          </div>
                          {item.modifiers && (
                            <div className="text-xs text-gray-600 mt-0.5">{item.modifiers}</div>
                          )}
                          {item.notes && (
                            <div className="text-xs text-red-700 font-medium mt-0.5">* {item.notes}</div>
                          )}
                          <Badge className={`mt-1 text-[10px] ${
                            item.status === "Pending" ? "bg-blue-500" :
                            item.status === "Preparing" ? "bg-yellow-600" :
                            "bg-green-600"
                          } text-white`}>{item.status}</Badge>
                        </div>
                        <div className="flex flex-col gap-1">
                          <Button size="sm" className="h-7 text-xs bg-green-700 hover:bg-green-800 text-white"
                            onClick={() => handleBump(item.orderItemId)}>
                            <Check className="h-3 w-3 mr-1" /> Bump
                          </Button>
                          {item.status !== "Pending" && (
                            <Button size="sm" variant="ghost" className="h-6 text-[10px] text-gray-600"
                              onClick={() => handleRecall(item.orderItemId)}>
                              <RotateCcw className="h-3 w-3 mr-1" /> Recall
                            </Button>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>

                  {/* Order-level bump (for expo) */}
                  {items.length > 1 && (
                    <div className="px-3 py-2 border-t border-gray-300/30">
                      <Button size="sm" className={`w-full h-8 text-xs ${allReady ? "bg-green-700 hover:bg-green-800" : "bg-gray-700 hover:bg-gray-800"} text-white`}
                        onClick={() => handleBumpOrder(first.orderId)}>
                        <Bell className="h-3 w-3 mr-1" /> {allReady ? "Complete Order" : "Bump All"}
                      </Button>
                    </div>
                  )}
                </div>
              )
            })}
          </div>
        )}
      </div>
    </div>
  )
}
