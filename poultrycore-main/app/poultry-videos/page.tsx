"use client"

import { useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { useQuery } from "@tanstack/react-query"
import { ExternalLink, PlayCircle, RefreshCw, Search, Youtube } from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Skeleton } from "@/components/ui/skeleton"
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

// /poultry-videos is poultry-only through the company-type guard's "/poultry-"
// prefix, so there is no farm-type redirect here.
export default function PoultryVideosPage() {
  const router = useRouter()
  const [searchQuery, setSearchQuery] = useState("")
  const [playing, setPlaying] = useState<ChannelVideo | null>(null)

  // New videos arrive on their own: the route re-reads the playlist's feed
  // every 30 minutes.
  const { data: feed, isLoading, isError, refetch, isFetching } = useQuery({
    queryKey: ["poultry-videos"],
    queryFn: loadFeed,
    staleTime: 10 * 60 * 1000,
  })
  const videos = feed?.videos ?? []

  const shown = useMemo(() => {
    const words = searchQuery.toLowerCase().split(/\s+/).filter(Boolean)
    return videos.filter((v) => {
      const text = `${v.title} ${v.description}`.toLowerCase()
      return words.every((w) => text.includes(w))
    })
  }, [videos, searchQuery])

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

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="max-w-6xl mx-auto space-y-6">
            {/* Page Header */}
            <div className="text-center space-y-3">
              <div className="w-16 h-16 bg-red-100 rounded-2xl flex items-center justify-center mx-auto">
                <PlayCircle className="w-8 h-8 text-red-600" />
              </div>
              <h1 className="text-3xl font-bold text-slate-900">Videos</h1>
              <p className="text-slate-600 max-w-xl mx-auto">
                Short videos that show how to use the system, step by step. New videos appear here as soon as we post them.
              </p>
              {(feed?.playlistUrl || feed?.channelUrl) && (
                <Button asChild variant="outline" size="sm">
                  <a href={feed.playlistUrl || feed.channelUrl} target="_blank" rel="noopener noreferrer">
                    <Youtube className="w-4 h-4 mr-2 text-red-600" /> {feed.playlistUrl ? "Open on YouTube" : "Visit our channel"}
                  </a>
                </Button>
              )}
            </div>

            {isLoading ? (
              <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                {Array.from({ length: 6 }, (_, i) => (
                  <div key={i} className="rounded-xl border bg-white overflow-hidden">
                    <Skeleton className="aspect-video w-full rounded-none" />
                    <div className="p-4 space-y-2">
                      <Skeleton className="h-4 w-3/4" />
                      <Skeleton className="h-3 w-1/3" />
                    </div>
                  </div>
                ))}
              </div>
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
                <div className="relative max-w-md mx-auto">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
                  <Input
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                    placeholder="Search videos"
                    className="pl-9 bg-white"
                  />
                </div>

                {shown.length === 0 ? (
                  <p className="text-center text-slate-500 py-12">No videos match your search.</p>
                ) : (
                  <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                    {shown.map((v) => (
                      <button
                        key={v.id}
                        type="button"
                        onClick={() => setPlaying(v)}
                        className="group text-left rounded-xl border bg-white overflow-hidden shadow-sm hover:shadow-md transition-shadow focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500"
                      >
                        <div className="relative aspect-video bg-slate-200">
                          {/* eslint-disable-next-line @next/next/no-img-element */}
                          <img
                            src={`https://i.ytimg.com/vi/${v.id}/hqdefault.jpg`}
                            alt=""
                            loading="lazy"
                            className="w-full h-full object-cover"
                          />
                          <div className="absolute inset-0 flex items-center justify-center bg-black/10 group-hover:bg-black/25 transition-colors">
                            <PlayCircle className="w-14 h-14 text-white drop-shadow-lg" />
                          </div>
                        </div>
                        <div className="p-4 space-y-1">
                          <h3 className="font-semibold text-slate-900 leading-snug line-clamp-2">{v.title}</h3>
                          <p className="text-xs text-slate-500">{uploadedOn(v.published)}</p>
                          {v.description && <p className="text-sm text-slate-600 line-clamp-2 pt-1">{v.description}</p>}
                        </div>
                      </button>
                    ))}
                  </div>
                )}
              </>
            )}
          </div>
        </main>
      </div>

      {/* The player loads only once a video is opened, so the page itself
          stays light however many videos there are. YouTube weighs the
          player's size when picking a quality, so it is made 1280px wide
          where the screen allows -- big enough for 720p -- and YouTubePlayer
          asks for 720p as it starts. */}
      <Dialog open={!!playing} onOpenChange={(open) => !open && setPlaying(null)}>
        <DialogContent className="sm:max-w-[min(92vw,1280px,calc(78vh*16/9))] p-0 overflow-hidden gap-0">
          {playing && (
            <>
              <div className="aspect-video bg-black">
                <YouTubePlayer videoId={playing.id} title={playing.title} />
              </div>
              <DialogHeader className="p-4 text-left max-h-60 overflow-y-auto">
                <DialogTitle>{playing.title}</DialogTitle>
                {playing.description && (
                  <DialogDescription className="whitespace-pre-line">{playing.description}</DialogDescription>
                )}
                <a
                  href={`https://www.youtube.com/watch?v=${playing.id}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-1 text-sm text-indigo-600 hover:underline pt-1"
                >
                  Watch on YouTube <ExternalLink className="w-3.5 h-3.5" />
                </a>
              </DialogHeader>
            </>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}
