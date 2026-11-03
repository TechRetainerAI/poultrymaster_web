"use client"

import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { useRouter } from "next/navigation"
import { useQuery } from "@tanstack/react-query"
import {
  CalendarDays,
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  Eye,
  ExternalLink,
  Film,
  ListVideo,
  Play,
  PlayCircle,
  RefreshCw,
  Search,
  Youtube,
} from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Progress } from "@/components/ui/progress"
import { Skeleton } from "@/components/ui/skeleton"
import { Switch } from "@/components/ui/switch"
import { YouTubePlayer } from "@/components/videos/youtube-player"
import type { ChannelFeed, ChannelVideo } from "@/lib/help/poultry-videos"

async function loadFeed(): Promise<ChannelFeed | null> {
  const res = await fetch("/api/youtube-videos")
  // 404: no playlist or channel set -- shown as "no videos", not as a fault.
  if (res.status === 404) return null
  if (!res.ok) throw new Error("feed-unavailable")
  return res.json()
}

function uploadedOn(iso: string): string {
  const d = new Date(iso)
  return Number.isNaN(d.getTime()) ? "" : d.toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" })
}

/** "3 days ago", the way YouTube labels a video's age. */
function timeAgo(iso: string): string {
  const then = new Date(iso).getTime()
  if (Number.isNaN(then)) return ""
  const days = Math.floor((Date.now() - then) / 86_400_000)
  if (days < 1) return "Today"
  if (days < 2) return "Yesterday"
  if (days < 7) return `${days} days ago`
  if (days < 30) return `${Math.floor(days / 7)} wk ago`
  if (days < 365) return `${Math.floor(days / 30)} mo ago`
  return `${Math.floor(days / 365)} yr ago`
}

const compact = new Intl.NumberFormat(undefined, { notation: "compact", maximumFractionDigits: 1 })

function viewsLabel(v: ChannelVideo): string {
  return v.views == null ? "" : `${compact.format(v.views)} view${v.views === 1 ? "" : "s"}`
}

/** Videos this browser has played. Per viewer and best effort, so it lives in localStorage. */
const WATCHED_KEY = "poultry-videos-watched"
const AUTOPLAY_KEY = "poultry-videos-autoplay"

function readWatched(): string[] {
  try {
    const raw = JSON.parse(localStorage.getItem(WATCHED_KEY) ?? "[]")
    return Array.isArray(raw) ? raw.filter((x) => typeof x === "string") : []
  } catch {
    return []
  }
}

type Filter = "all" | "unwatched" | "watched"

// /poultry-videos is poultry-only through the company-type guard's "/poultry-"
// prefix, so there is no farm-type redirect here.
export default function PoultryVideosPage() {
  const router = useRouter()
  const [searchQuery, setSearchQuery] = useState("")
  const [filter, setFilter] = useState<Filter>("all")
  const [currentId, setCurrentId] = useState<string | null>(null)
  // The player loads only once someone presses play, so opening the page
  // does not start a video with sound.
  const [started, setStarted] = useState(false)
  const [autoplayNext, setAutoplayNext] = useState(true)
  const [watched, setWatched] = useState<string[]>([])
  const [showMore, setShowMore] = useState(false)
  const playerRef = useRef<HTMLDivElement>(null)

  // New videos arrive on their own: the route re-reads the playlist's feed
  // every 30 minutes.
  const { data: feed, isLoading, isError, refetch, isFetching } = useQuery({
    queryKey: ["poultry-videos"],
    queryFn: loadFeed,
    staleTime: 10 * 60 * 1000,
  })
  const videos = useMemo(() => feed?.videos ?? [], [feed])

  useEffect(() => {
    setWatched(readWatched())
    try {
      if (localStorage.getItem(AUTOPLAY_KEY) === "off") setAutoplayNext(false)
    } catch {
      // Defaults stand.
    }
  }, [])

  // Pick the video named in ?v= (a shared link), else the newest one.
  useEffect(() => {
    if (videos.length === 0 || currentId) return
    const asked = new URLSearchParams(window.location.search).get("v")
    const found = asked && videos.some((v) => v.id === asked)
    setCurrentId(found ? asked : videos[0].id)
  }, [videos, currentId])

  const current = videos.find((v) => v.id === currentId) ?? null
  const currentIndex = current ? videos.indexOf(current) : -1
  const watchedSet = useMemo(() => new Set(watched), [watched])

  const markWatched = useCallback((id: string) => {
    setWatched((prev) => {
      if (prev.includes(id)) return prev
      const next = [...prev, id]
      try {
        localStorage.setItem(WATCHED_KEY, JSON.stringify(next))
      } catch {
        // Not remembered this time; nothing else depends on it.
      }
      return next
    })
  }, [])

  const play = useCallback(
    (id: string) => {
      setCurrentId(id)
      setStarted(true)
      setShowMore(false)
      markWatched(id)
      const url = new URL(window.location.href)
      url.searchParams.set("v", id)
      window.history.replaceState(null, "", url)
      // On a phone the playlist sits under the player, so bring it back into view.
      const top = playerRef.current?.getBoundingClientRect().top ?? 0
      if (top < 0 || top > window.innerHeight / 2) playerRef.current?.scrollIntoView({ behavior: "smooth", block: "start" })
    },
    [markWatched],
  )

  const handleEnded = useCallback(() => {
    if (!autoplayNext) return
    const next = videos[currentIndex + 1]
    if (next) play(next.id)
  }, [autoplayNext, videos, currentIndex, play])

  const toggleAutoplay = (on: boolean) => {
    setAutoplayNext(on)
    try {
      localStorage.setItem(AUTOPLAY_KEY, on ? "on" : "off")
    } catch {
      // Applies to this visit only.
    }
  }

  const shown = useMemo(() => {
    const words = searchQuery.toLowerCase().split(/\s+/).filter(Boolean)
    return videos.filter((v) => {
      if (filter === "watched" && !watchedSet.has(v.id)) return false
      if (filter === "unwatched" && watchedSet.has(v.id)) return false
      const text = `${v.title} ${v.description}`.toLowerCase()
      return words.every((w) => text.includes(w))
    })
  }, [videos, searchQuery, filter, watchedSet])

  const stats = useMemo(() => {
    const watchedCount = videos.filter((v) => watchedSet.has(v.id)).length
    const hasViews = videos.some((v) => v.views != null)
    const totalViews = videos.reduce((sum, v) => sum + (v.views ?? 0), 0)
    const monthAgo = Date.now() - 30 * 86_400_000
    const recent = videos.filter((v) => new Date(v.published).getTime() >= monthAgo).length
    return { watchedCount, hasViews, totalViews, recent, newest: videos[0] }
  }, [videos, watchedSet])

  const handleLogout = () => {
    localStorage.removeItem("auth_token")
    localStorage.removeItem("refresh_token")
    localStorage.removeItem("username")
    localStorage.removeItem("userId")
    localStorage.removeItem("farmId")
    localStorage.removeItem("farmName")
    localStorage.removeItem("isStaff")
    localStorage.removeItem("isSubscriber")
    router.push("/login")
  }

  const prev = currentIndex > 0 ? videos[currentIndex - 1] : null
  const next = currentIndex >= 0 ? videos[currentIndex + 1] ?? null : null
  const watchedPct = videos.length ? Math.round((stats.watchedCount / videos.length) * 100) : 0

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="max-w-[1600px] mx-auto space-y-6">
            {/* Page Header */}
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
              <div className="flex items-center gap-3">
                <div className="w-11 h-11 bg-red-100 rounded-xl flex items-center justify-center shrink-0">
                  <PlayCircle className="w-6 h-6 text-red-600" />
                </div>
                <div>
                  <h1 className="text-2xl font-bold text-slate-900">Videos</h1>
                  <p className="text-sm text-slate-600">Step-by-step guide videos to help you get the most out of the system.</p>
                </div>
              </div>
              {(feed?.playlistUrl || feed?.channelUrl) && (
                <Button asChild variant="outline" size="sm" className="self-start sm:self-auto">
                  <a href={feed.playlistUrl || feed.channelUrl} target="_blank" rel="noopener noreferrer">
                    <Youtube className="w-4 h-4 mr-2 text-red-600" /> {feed.playlistUrl ? "Open on YouTube" : "Visit our channel"}
                  </a>
                </Button>
              )}
            </div>

            {isLoading ? (
              <>
                <div className="grid gap-4 grid-cols-2 lg:grid-cols-4">
                  {Array.from({ length: 4 }, (_, i) => (
                    <Skeleton key={i} className="h-24 rounded-xl" />
                  ))}
                </div>
                <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_400px]">
                  <Skeleton className="aspect-video w-full rounded-xl" />
                  <div className="space-y-3">
                    {Array.from({ length: 5 }, (_, i) => (
                      <div key={i} className="flex gap-3">
                        <Skeleton className="w-40 aspect-video rounded-lg shrink-0" />
                        <div className="flex-1 space-y-2 py-1">
                          <Skeleton className="h-4 w-full" />
                          <Skeleton className="h-3 w-1/2" />
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              </>
            ) : isError ? (
              <Card>
                <CardContent className="py-16 text-center space-y-3">
                  <p className="font-medium text-slate-700">The videos could not be loaded</p>
                  <p className="text-sm text-slate-500">Check your internet connection and try again.</p>
                  <Button variant="outline" size="sm" onClick={() => refetch()} disabled={isFetching}>
                    <RefreshCw className={`w-4 h-4 mr-2 ${isFetching ? "animate-spin" : ""}`} /> Try again
                  </Button>
                </CardContent>
              </Card>
            ) : videos.length === 0 ? (
              <Card>
                <CardContent className="py-16 text-center space-y-2">
                  <PlayCircle className="w-10 h-10 text-slate-300 mx-auto" />
                  <p className="font-medium text-slate-700">No videos yet</p>
                  <p className="text-sm text-slate-500">New videos will show here as soon as we post them.</p>
                </CardContent>
              </Card>
            ) : (
              <>
                {/* Dashboard */}
                <div className="grid gap-4 grid-cols-2 lg:grid-cols-4">
                  <StatCard icon={Film} tone="bg-red-50 text-red-600" label="Videos" value={String(videos.length)} sub="In the playlist" />
                  <Card className="py-0">
                    <CardContent className="p-4 space-y-2">
                      <div className="flex items-center justify-between">
                        <p className="text-sm text-slate-500">Watched</p>
                        <div className="w-8 h-8 rounded-lg bg-emerald-50 text-emerald-600 flex items-center justify-center">
                          <CheckCircle2 className="w-4 h-4" />
                        </div>
                      </div>
                      <p className="text-2xl font-bold text-slate-900">
                        {stats.watchedCount} <span className="text-base font-normal text-slate-500">of {videos.length}</span>
                      </p>
                      <Progress value={watchedPct} className="h-1.5" />
                    </CardContent>
                  </Card>
                  <StatCard
                    icon={Eye}
                    tone="bg-blue-50 text-blue-600"
                    label="Total views"
                    value={stats.hasViews ? compact.format(stats.totalViews) : "—"}
                    sub="Across all videos"
                  />
                  <StatCard
                    icon={CalendarDays}
                    tone="bg-amber-50 text-amber-600"
                    label="Latest video"
                    value={stats.newest ? timeAgo(stats.newest.published) : "—"}
                    sub={`${stats.recent} new in the last 30 days`}
                  />
                </div>

                {/* Watch area: player on the left, playlist on the right */}
                <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_380px] xl:grid-cols-[minmax(0,1fr)_420px] items-start">
                  <div className="space-y-4 min-w-0 scroll-mt-20" ref={playerRef}>
                    <div className="aspect-video bg-black rounded-xl overflow-hidden shadow-sm">
                      {current && started ? (
                        <YouTubePlayer key={current.id} videoId={current.id} title={current.title} onEnded={handleEnded} />
                      ) : current ? (
                        <button
                          type="button"
                          onClick={() => play(current.id)}
                          className="group relative w-full h-full focus:outline-none focus-visible:ring-4 focus-visible:ring-red-500"
                          aria-label={`Play ${current.title}`}
                        >
                          {/* eslint-disable-next-line @next/next/no-img-element */}
                          <img
                            src={`https://i.ytimg.com/vi/${current.id}/hqdefault.jpg`}
                            alt=""
                            className="w-full h-full object-cover opacity-90"
                          />
                          <span className="absolute inset-0 flex items-center justify-center bg-black/20 group-hover:bg-black/30 transition-colors">
                            <span className="w-20 h-14 rounded-2xl bg-red-600 group-hover:bg-red-700 flex items-center justify-center shadow-lg transition-colors">
                              <Play className="w-8 h-8 text-white fill-white" />
                            </span>
                          </span>
                        </button>
                      ) : null}
                    </div>

                    {current && (
                      <>
                        <div className="flex flex-col sm:flex-row sm:items-start justify-between gap-3">
                          <div className="min-w-0">
                            <h2 className="text-xl font-semibold text-slate-900 leading-snug">{current.title}</h2>
                            <p className="text-sm text-slate-500 mt-1">
                              {[viewsLabel(current), uploadedOn(current.published)].filter(Boolean).join(" · ")}
                            </p>
                          </div>
                          <div className="flex items-center gap-2 shrink-0">
                            <Button variant="outline" size="sm" className="rounded-full" disabled={!prev} onClick={() => prev && play(prev.id)}>
                              <ChevronLeft className="w-4 h-4 mr-1" /> Previous
                            </Button>
                            <Button variant="outline" size="sm" className="rounded-full" disabled={!next} onClick={() => next && play(next.id)}>
                              Next <ChevronRight className="w-4 h-4 ml-1" />
                            </Button>
                            <Button asChild variant="outline" size="sm" className="rounded-full">
                              <a href={`https://www.youtube.com/watch?v=${current.id}`} target="_blank" rel="noopener noreferrer">
                                <ExternalLink className="w-4 h-4 sm:mr-1" />
                                <span className="hidden sm:inline">YouTube</span>
                              </a>
                            </Button>
                          </div>
                        </div>

                        {current.description && (
                          <div className="rounded-xl bg-slate-100 p-4 text-sm text-slate-700">
                            <p className={`whitespace-pre-line ${showMore ? "" : "line-clamp-3"}`}>{current.description}</p>
                            {current.description.length > 200 || current.description.split("\n").length > 3 ? (
                              <button
                                type="button"
                                onClick={() => setShowMore((s) => !s)}
                                className="mt-2 font-semibold text-slate-900 hover:underline"
                              >
                                {showMore ? "Show less" : "...more"}
                              </button>
                            ) : null}
                          </div>
                        )}
                      </>
                    )}
                  </div>

                  {/* Playlist */}
                  <Card className="py-0 gap-0 overflow-hidden lg:sticky lg:top-4">
                    <div className="p-4 border-b space-y-3">
                      <div className="flex items-center justify-between gap-2">
                        <div className="min-w-0">
                          <p className="font-semibold text-slate-900 flex items-center gap-2">
                            <ListVideo className="w-4 h-4 text-red-600" /> Playlist
                          </p>
                          <p className="text-xs text-slate-500">
                            {currentIndex >= 0 ? `${currentIndex + 1} / ${videos.length}` : `${videos.length} videos`}
                          </p>
                        </div>
                        <label className="flex items-center gap-2 text-xs text-slate-600 cursor-pointer">
                          Autoplay
                          <Switch checked={autoplayNext} onCheckedChange={toggleAutoplay} aria-label="Play the next video automatically" />
                        </label>
                      </div>
                      <div className="relative">
                        <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
                        <Input
                          value={searchQuery}
                          onChange={(e) => setSearchQuery(e.target.value)}
                          placeholder="Search videos"
                          className="pl-9 bg-white"
                        />
                      </div>
                      <div className="flex gap-2">
                        {(
                          [
                            ["all", "All"],
                            ["unwatched", "Not watched"],
                            ["watched", "Watched"],
                          ] as const
                        ).map(([key, label]) => (
                          <button
                            key={key}
                            type="button"
                            onClick={() => setFilter(key)}
                            className={`px-3 py-1 rounded-lg text-sm font-medium transition-colors ${
                              filter === key ? "bg-slate-900 text-white" : "bg-slate-100 text-slate-700 hover:bg-slate-200"
                            }`}
                          >
                            {label}
                          </button>
                        ))}
                      </div>
                    </div>

                    <div className="max-h-[70vh] lg:max-h-[calc(100vh-14rem)] overflow-y-auto p-2">
                      {shown.length === 0 ? (
                        <p className="text-center text-sm text-slate-500 py-10">No videos match.</p>
                      ) : (
                        shown.map((v) => {
                          const isCurrent = v.id === currentId
                          const seen = watchedSet.has(v.id)
                          return (
                            <button
                              key={v.id}
                              type="button"
                              onClick={() => play(v.id)}
                              aria-current={isCurrent ? "true" : undefined}
                              className={`group w-full flex gap-3 p-2 rounded-lg text-left transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-red-500 ${
                                isCurrent ? "bg-red-50" : "hover:bg-slate-100"
                              }`}
                            >
                              <div className="relative w-40 shrink-0 aspect-video rounded-lg overflow-hidden bg-slate-200">
                                {/* eslint-disable-next-line @next/next/no-img-element */}
                                <img
                                  src={`https://i.ytimg.com/vi/${v.id}/mqdefault.jpg`}
                                  alt=""
                                  loading="lazy"
                                  className="w-full h-full object-cover"
                                />
                                {isCurrent ? (
                                  <span className="absolute inset-0 bg-black/50 flex items-center justify-center text-[11px] font-semibold text-white uppercase tracking-wide">
                                    {started ? "Now playing" : "Up next"}
                                  </span>
                                ) : (
                                  <span className="absolute inset-0 flex items-center justify-center opacity-0 group-hover:opacity-100 bg-black/25 transition-opacity">
                                    <Play className="w-7 h-7 text-white fill-white drop-shadow" />
                                  </span>
                                )}
                                {seen && !isCurrent && (
                                  <span className="absolute bottom-1 right-1 rounded bg-black/75 px-1.5 py-0.5 text-[10px] font-medium text-white flex items-center gap-1">
                                    <CheckCircle2 className="w-3 h-3" /> Watched
                                  </span>
                                )}
                              </div>
                              <div className="min-w-0 py-0.5">
                                <p className={`text-sm font-semibold leading-snug line-clamp-2 ${isCurrent ? "text-red-700" : "text-slate-900"}`}>
                                  {v.title}
                                </p>
                                <p className="text-xs text-slate-500 mt-1">
                                  {[viewsLabel(v), timeAgo(v.published)].filter(Boolean).join(" · ")}
                                </p>
                              </div>
                            </button>
                          )
                        })
                      )}
                    </div>
                  </Card>
                </div>
              </>
            )}
          </div>
        </main>
      </div>
    </div>
  )
}

function StatCard({
  icon: Icon,
  tone,
  label,
  value,
  sub,
}: {
  icon: typeof Film
  tone: string
  label: string
  value: string
  sub: string
}) {
  return (
    <Card className="py-0">
      <CardContent className="p-4 space-y-1">
        <div className="flex items-center justify-between">
          <p className="text-sm text-slate-500">{label}</p>
          <div className={`w-8 h-8 rounded-lg flex items-center justify-center ${tone}`}>
            <Icon className="w-4 h-4" />
          </div>
        </div>
        <p className="text-2xl font-bold text-slate-900">{value}</p>
        <p className="text-xs text-slate-500">{sub}</p>
      </CardContent>
    </Card>
  )
}
